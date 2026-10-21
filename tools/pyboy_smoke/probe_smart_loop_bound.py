"""Measure the AILayerSmart loop-bound bug (Codex follow-up finding 1, 2026-10-21).

Probe, not a smoke test (probe_ prefix keeps it out of `make smoke`).

AISmartCrossCutting ends with `ld b, [wEnemyMoveNum]`, so AILayerSmart's
`dec b / ret z` counter is the last move id, not the slot count. A full
four-move set therefore walks on into wEnemyMonDVs/Level/MaxHP until a zero
byte, and Pound (id 1) ends the loop early.

Each board runs AIEnemyTrainerChooseMoves twice from one savestate:
  shipped  the ROM as built
  fixed    a hook at AILayerSmart.nextMove restores B to the true counter,
           which is exactly what saving BC around AISmartCrossCutting does
and compares, at the moment AILayerSmart returns (before any layer that calls
Random, so VBlank timing cannot diverge the two runs yet): the four slot
scores, the SMART iteration count, and every WRAM byte.

Usage: python3 tools/pyboy_smoke/probe_smart_loop_bound.py [--boards N] [--seed S]
"""
from __future__ import annotations

import argparse
import io
import random
from collections import Counter
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
SMART_LAYER = 4
WRAM = range(0xC000, 0xE000)

PAIRS = [  # (player, enemy): varied types, so SMART's handlers see varied boards
    ("SNORLAX", "TAUROS"), ("ALAKAZAM", "GENGAR"), ("GYARADOS", "JOLTEON"),
    ("RHYDON", "STARMIE"), ("MACHAMP", "DRAGONITE"), ("CHANSEY", "VENUSAUR"),
]


class Probe:
    def __init__(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.fix = False
        self.visits = 0
        self.cross_calls = 0
        self.result: dict | None = None
        h = self.h
        h.register_hook("AILayerSmart", self._smart_entry)
        h.register_hook("AILayerSmart.nextMove", self._next_move)
        h.register_hook("AISmartCrossCutting", self._cross)
        h.register_hook("AIEnemyTrainerChooseMoves.layerReturn", self._layer_return)

    # hooks ---------------------------------------------------------------
    def _smart_entry(self, _ctx) -> None:
        self.visits = 0
        self.cross_calls = 0
        self.smart_start = self.h.cycle_count()

    def _next_move(self, _ctx) -> None:
        self.visits += 1
        if self.fix:
            self.h.pyboy.register_file.B = (6 - self.visits) & 0xFF

    def _cross(self, _ctx) -> None:
        self.cross_calls += 1

    def _layer_return(self, _ctx) -> None:
        sp = self.h.pyboy.register_file.SP
        if self.h.pyboy.memory[(sp + 1) & 0xFFFF] != SMART_LAYER or self.result is not None:
            return
        self.result = {
            "scores": self.h.read_bytes("wBuffer", 4),
            "slots": self.cross_calls,
            "wram": bytes(self.h.pyboy.memory[a] for a in WRAM),
            "sp": sp,
            "cycles": self.h.cycle_count() - self.smart_start,
        }

    # board ---------------------------------------------------------------
    def boot(self, player: str, enemy: str) -> bytes:
        h = self.h
        mv = self.moves
        h.inject_fight2_spec(
            [{"species": self.species[player], "level": 50, "moves": [mv["TACKLE"], mv["THUNDERBOLT"]]}],
            [{"species": self.species[enemy], "level": 50,
              "moves": [mv["TACKLE"], mv["GROWL"], mv["BITE"], mv["SURF"]]}],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        h.boot_fight2(seed=1)
        h.reveal_player_moves(0, [0, 1], clear=True)
        h.park_before_hijack()
        state = io.BytesIO()
        h.save_state(state)
        return state.getvalue()

    def run(self, state: bytes, moves: list[int], dvs: tuple[int, int], fix: bool) -> dict:
        h = self.h
        h.load_state(io.BytesIO(state))
        for slot, move in enumerate(moves):
            h.write8("wEnemyMonMoves", move, offset=slot)
            h.write8("wEnemyMonPP", 10, offset=slot)
        h.write8("wEnemyMonDVs", dvs[0])
        h.write8("wEnemyMonDVs", dvs[1], offset=1)
        self.fix = fix
        self.result = None
        h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
        assert self.result is not None, "AILayerSmart never returned (tier lacks SMART?)"
        # Final scores after every layer, personality and the reliable-KO pass.
        self.result["final"] = h.read_bytes("wBuffer", 4)
        return self.result


def label_for(h: RedRogueHarness, address: int) -> str:
    return h.symbols.nearest(0, address) or f"${address:04x}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--boards", type=int, default=40, help="boards per species pair")
    parser.add_argument("--seed", type=int, default=20261021)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    moves_table = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
    struggle = moves_table["STRUGGLE"]
    pound = moves_table["POUND"]
    pool = [m for m in range(1, struggle)]

    totals = Counter()
    slot_hist = Counter()
    score_diffs: list[str] = []
    choice_diffs: list[str] = []
    wram_diff_labels = Counter()
    for player, enemy in PAIRS:
        probe = Probe()  # boot_fight2 is one boot per harness
        h = probe.h
        try:
            state = probe.boot(player, enemy)
            for board in range(args.boards):
                moves = rng.sample(pool, 4)
                if board % 5 == 0:  # force Pound into slots 0-2 on a fifth of boards
                    moves[rng.randrange(3)] = pound
                    if moves.count(pound) > 1:
                        continue
                dvs = (rng.randrange(256), rng.randrange(256))
                shipped = probe.run(state, moves, dvs, fix=False)
                fixed = probe.run(state, moves, dvs, fix=True)
                again = probe.run(state, moves, dvs, fix=False)
                totals["boards"] += 1
                if again["final"] != shipped["final"]:
                    totals["final_noise"] += 1  # shipped vs shipped: RNG/timing noise
                best = lambda s: {i for i, v in enumerate(s) if moves[i] and v == min(s)}
                if best(shipped["final"]) != best(fixed["final"]):
                    totals["choice_changed"] += 1
                    choice_diffs.append(
                        f"{enemy} moves={moves} slots={shipped['slots']} "
                        f"final shipped={shipped['final']} fixed={fixed['final']}")
                elif shipped["final"] != fixed["final"]:
                    totals["final_scores_changed"] += 1
                slot_hist[shipped["slots"]] += 1
                if fixed["slots"] != 4:
                    totals["fixed_not_4"] += 1
                if shipped["slots"] > 4:
                    totals["overrun"] += 1
                    totals["overrun_cycles_shipped"] += shipped["cycles"]
                    totals["overrun_cycles_fixed"] += fixed["cycles"]
                if shipped["slots"] < 4:
                    totals["truncated"] += 1
                if shipped["scores"] != fixed["scores"]:
                    totals["score_changed"] += 1
                    score_diffs.append(
                        f"{enemy} moves={moves} dvs={dvs} slots={shipped['slots']} "
                        f"shipped={shipped['scores']} fixed={fixed['scores']}")
                # WRAM: ignore dead stack below SP (stale frames from deeper calls)
                stack_floor = min(shipped["sp"], fixed["sp"]) - 0x100
                diffs = [WRAM.start + i for i, (a, b) in enumerate(zip(shipped["wram"], fixed["wram"]))
                         if a != b and not stack_floor <= WRAM.start + i < shipped["sp"]]
                if diffs:
                    totals["wram_changed"] += 1
                    for address in sorted({label_for(h, a) for a in diffs}):
                        wram_diff_labels[address] += 1
        finally:
            h.close()

    print(f"boards={totals['boards']}")
    print(f"shipped SMART slots visited: {dict(sorted(slot_hist.items()))}")
    print(f"overrun (>4 slots)={totals['overrun']} truncated (<4)={totals['truncated']} "
          f"fixed-run not exactly 4={totals['fixed_not_4']}")
    if totals["overrun"]:
        print(f"AILayerSmart cycles on overrun boards, mean: shipped="
              f"{totals['overrun_cycles_shipped'] // totals['overrun']} "
              f"fixed={totals['overrun_cycles_fixed'] // totals['overrun']}")
    print(f"SMART scores differ shipped vs fixed: {totals['score_changed']}")
    for line in score_diffs[:25]:
        print("  " + line)
    print(f"final decision: best-slot set changed={totals['choice_changed']} "
          f"scores-only changed={totals['final_scores_changed']} "
          f"shipped-vs-shipped noise={totals['final_noise']}")
    for line in choice_diffs[:25]:
        print("  " + line)
    print(f"boards with any other WRAM difference: {totals['wram_changed']}")
    for label, count in wram_diff_labels.most_common(40):
        print(f"  {count:4d}  {label}")


if __name__ == "__main__":
    main()
