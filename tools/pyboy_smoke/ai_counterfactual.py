"""Counterfactual replay harness for the trainer AI (AI_T4_REGRET_PLAN Phase A, 2026-11-17).

Pass 1 plays one FIGHT 2 battle and saves a state at every enemy decision the plan names:
  turn      the turn plan, saved at MainInBattleLoop.battleMenu before the enemy commits;
  send_out  a faint replacement ranked live by AISelectSendOut.
Pass 2 replays each decision once per (alternative, seed k) to the end of the battle and scores
the outcome V = player party HP fraction lost - enemy party HP fraction lost (higher is better
for the AI). Regret is measured with a selection-bias guard: the best alternative is picked on
seeds 1..K/2 and the regret (best - chosen) is measured only on seeds K/2+1..K.

How an alternative is applied (verified against source 2026-11-17, see the plan's A2 list):
the state is saved at the battle menu, and the override is written by a one-shot hook AT the
decision itself, where the RNG is also reseeded from SHA-256(decision id, k):
  - turn, move slot s: at AICommitEnemyTurn entry, with the plan marked planned and move-chosen
    (bits 5 and 7), write wEnemySelectedMove / wEnemyMoveListIndex (ChooseEnemyMove sets both;
    PP is charged from the index, core.asm:5765) and clear plan bit 6 and bits 0-2;
  - turn, switch to reserve r (T2+): same hook, set plan bit 6 and bits 0-2 = r + 1
    (TrainerAI -> AITrySmartSwitch -> AISwitchIfEnoughMons plays back bit 6);
  - send_out, reserve r: at AISelectSendOut.commit (a = the slot), the n-th faint replacement
    after the saved state, set A = r;
  - as_chosen: no write, still reseeded at the same point.
Everything before the decision replays identically from the state (same inputs, same frames),
so only what follows it varies with k. With the ORIGINAL RNG (no reseed), the as-chosen branch
reproduces the base battle exactly: test_ai_counterfactual checks that.

Run from WSL (autoplay/replay runs need approval per run, AI_T4_REGRET_PLAN rules):
  python3 tools/pyboy_smoke/ai_counterfactual.py --seed 17 --tier 3 --k 8 --jobs 6
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import statistics
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict, dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fight2_driver import Fight2Driver  # noqa: E402
from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_rgbds_constants  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PARTYMON_STRUCT_LENGTH = 44
MON_HP, MON_MAXHP = 0x01, 0x22
PLAN_MOVE_CHOSEN, PLAN_SWITCH, PLAN_PLANNED, PLAN_ARMED = 7, 6, 5, 4
PLAN_SLOT_MASK = 0b111
PP_MASK = 0x3F
MAX_STEPS = 5000
# Cumulative per base battle and per branch, across every menu return (2026-11-21 AI review):
# each driver.play(MAX_STEPS) ends at the next battle menu and play() loops, so a battle that
# never ends (seen: Haze probe round 3, one branch at 23 h and 5 GB) never returned. The values
# are the ones ai_haze_probe4.py ran 38,272 branches under (3 capped). A capped battle has no
# outcome: its branch is invalid, so run() keeps it out of the regret table.
MAX_TURNS = 200
MAX_FRAMES = 500_000
LOOKAHEAD = "lookahead_1"
HEAL_EFFECTS = ("HEAL_EFFECT",)
SETUP_EFFECTS = (
    *(f"{stat}_UP{n}_EFFECT" for stat in ("ATTACK", "DEFENSE", "SPEED", "SPECIAL", "ACCURACY", "EVASION")
      for n in (1, 2)),
    "FOCUS_ENERGY_EFFECT", "LIGHT_SCREEN_EFFECT", "REFLECT_EFFECT", "SUBSTITUTE_EFFECT",
)


# --------------------------------------------------------------------------- pure helpers

def seed_bytes(decision_id: str, k: int) -> bytes:
    """12 bytes for the CMWC state: hRandomAdd, hRandomSub, wRandomTable[10]."""
    return hashlib.sha256(f"{decision_id}:{k}".encode()).digest()[:12]


def split_regret(values: dict[str, list[float]], chosen: str) -> dict[str, object]:
    """Selection-bias-guarded regret. values: {alternative: [V for seed 0..K-1]}, same seeds
    for every alternative (common random numbers). The best alternative is chosen by mean V on
    the first half of the seeds; regret is the paired per-seed difference best - chosen on the
    second half, with its standard error and a normal 95% interval."""
    k = len(values[chosen])
    if any(len(v) != k for v in values.values()):
        raise ValueError("every alternative needs the same seeds")
    if k < 2:
        raise ValueError("need at least 2 seeds")
    half = k // 2
    best = max(sorted(values), key=lambda alt: (statistics.fmean(values[alt][:half]), alt == chosen))
    diffs = [values[best][i] - values[chosen][i] for i in range(half, k)]
    mean = statistics.fmean(diffs)
    se = statistics.stdev(diffs) / math.sqrt(len(diffs)) if len(diffs) > 1 else 0.0
    return {"best": best, "regret": mean, "se": se,
            "ci95": [mean - 1.96 * se, mean + 1.96 * se], "held_out": len(diffs)}


def summarize(records: list[dict[str, object]]) -> list[dict[str, object]]:
    """Per (chosen kind -> best kind): count, mean regret, its 95% CI across decisions, and the
    share of all regret."""
    groups: dict[tuple[str, str], list[float]] = {}
    for record in records:
        key = (record["chosen_kind"], record["best_kind"])
        groups.setdefault(key, []).append(float(record["regret"]))
    total = sum(sum(v) for v in groups.values()) or 1.0
    rows = []
    for (chosen_kind, best_kind), regrets in sorted(groups.items(), key=lambda kv: -sum(kv[1])):
        mean = statistics.fmean(regrets)
        se = statistics.stdev(regrets) / math.sqrt(len(regrets)) if len(regrets) > 1 else 0.0
        rows.append({"chosen_kind": chosen_kind, "best_kind": best_kind, "count": len(regrets),
                     "mean_regret": mean, "ci95": [mean - 1.96 * se, mean + 1.96 * se],
                     "share": sum(regrets) / total})
    return rows


def parse_moves(root: Path) -> dict[int, tuple[str, int]]:
    """{move id: (effect name, power)} from data/moves/moves.asm; row order is the id order."""
    moves: dict[int, tuple[str, int]] = {}
    move_id = 0
    for raw in (root / "data/moves/moves.asm").read_text(encoding="utf-8").splitlines():
        line = raw.split(";", 1)[0].strip()
        if not line.startswith("move "):
            continue
        move_id += 1
        fields = [f.strip() for f in line[len("move "):].split(",")]
        moves[move_id] = (fields[1], int(fields[2]))
    return moves


def move_kind(moves: dict[int, tuple[str, int]], move_id: int) -> str:
    effect, power = moves.get(move_id, ("", 0))
    if effect in HEAL_EFFECTS:
        return "heal"
    if power > 0:
        return "attack"
    if effect in SETUP_EFFECTS:
        return "setup"
    return "status"


# --------------------------------------------------------------------------- data

@dataclass
class Decision:
    index: int
    kind: str                 # "turn" | "send_out"
    state_index: int          # which saved state it replays from
    occurrence: int           # n-th matching hook after that state (1-based)
    turn: int
    chosen: str               # alternative name: "move:s", "switch:r", "send:r"
    alternatives: list[str]
    alt_kinds: dict[str, str]
    player_living: int
    enemy_living: int
    player_hp: list[int] = field(default_factory=list)   # [hp, max]
    enemy_hp: list[int] = field(default_factory=list)
    # Player-side host state at the save, so a replay chooses exactly as pass 1 did: whether
    # the move menu had already opened (then the lookahead is skipped there) and the move
    # override in force (a skipped turn still uses the previous turn's lookahead choice).
    menu_open: bool = False
    move_override: int | None = None


# --------------------------------------------------------------------------- emulator side

class Replayer:
    """One harness + driver with the decision and outcome hooks registered once; per-branch
    behaviour comes from mutable fields (`self.branch`)."""

    def __init__(self, seed: int, tier: int, policy: str, root: Path = ROOT, look_seeds: int = 2):
        import run_ai_benchmark as rab

        # lookahead_1 (A4): best_power's menu path, but each turn's move is chosen by trying
        # every legal move for one turn over look_seeds seeds and keeping the one that leaves
        # the AI worst off. It sees the enemy's planned move, so it is an upper-bound
        # adversary, never a model of a human.
        self.lookahead_seeds = look_seeds if policy == LOOKAHEAD else 0
        driver_policy = "best_power" if policy == LOOKAHEAD else policy
        self.in_trial = False
        self._trial_menu = False
        self._menu_flag = False
        self._move_menus = 0
        self._menu_mark = 0
        self.look_turns = 0
        self.look_skipped = 0
        self.root = root
        self.moves = parse_moves(root)
        battle = parse_rgbds_constants(root / "constants/battle_constants.asm")
        self.locked1 = sum(1 << battle[n] for n in (
            "STORING_ENERGY", "THRASHING_ABOUT", "CHARGING_UP", "USING_TRAPPING_MOVE", "INVULNERABLE"))
        self.locked2 = sum(1 << battle[n] for n in ("NEEDS_TO_RECHARGE", "USING_RAGE"))
        self.h = h = RedRogueHarness(root, root / "tools/pyboy_smoke/artifacts")
        self.driver = Fight2Driver(h, tier=tier, player_policy=driver_policy,
                                   move_powers=rab.parse_move_powers(root / "data/moves/moves.asm"))
        h.register_hook("MoveSelectionMenu", lambda _c: self._count_move_menu())
        self.seed, self.tier, self.policy = seed, tier, policy
        self.max_turns, self.max_frames = MAX_TURNS, MAX_FRAMES
        self.budget: dict[str, object] = {}
        self.outcome: dict[str, float] | None = None
        self.branch: dict[str, object] | None = None
        self.recorder = None  # pass-1 callbacks
        h.register_hook("TrainerBattleVictory", lambda _c: self._end(player_won=True))
        h.register_hook("HandlePlayerBlackOut", lambda _c: self._end(player_won=False))
        h.register_hook("AICommitEnemyTurn", lambda _c: self._on_commit())
        h.register_hook("AISelectSendOut.scoredLead", lambda _c: self._on_scored_lead())
        h.register_hook("AISelectSendOut.commit", lambda _c: self._on_send_commit())
        h.register_hook("MainInBattleLoop.battleMenu", lambda _c: self._on_battle_menu())
        h.register_hook("SwitchEnemyMon", lambda _c: self._on_enemy_switch())

    def close(self):
        self.h.close()

    # ---- reads
    def word(self, label: str, offset: int = 0) -> int:
        return self.h.read8(label, offset) << 8 | self.h.read8(label, offset + 1)

    def party(self, side: str) -> list[tuple[int, int]]:
        """[(hp, max)] per party slot, the active mon's HP read live."""
        h = self.h
        if side == "player":
            base, count = h.address("wPartyMons"), h.read8("wPartyCount")
            active, live = h.read8("wPlayerMonNumber"), self.word("wBattleMonHP")
        else:
            base, count = h.address("wEnemyMon1"), h.read8("wEnemyPartyCount")
            active, live = h.read8("wEnemyMonPartyPos"), self.word("wEnemyMonHP")
        mem = h.pyboy.memory
        out = []
        for i in range(min(6, count)):
            mon = base + i * PARTYMON_STRUCT_LENGTH
            hp = mem[mon + MON_HP] << 8 | mem[mon + MON_HP + 1]
            if i == active:
                hp = live
            out.append((hp, mem[mon + MON_MAXHP] << 8 | mem[mon + MON_MAXHP + 1]))
        return out

    @staticmethod
    def lost(party: list[tuple[int, int]]) -> float:
        total = sum(m for _, m in party)
        return 1.0 - sum(h for h, _ in party) / total if total else 0.0

    def _end(self, player_won: bool) -> None:
        if self.outcome is not None:
            return
        player = 1.0 if not player_won else self.lost(self.party("player"))
        enemy = 1.0 if player_won else self.lost(self.party("enemy"))
        self.outcome = {"player_lost": player, "enemy_lost": enemy, "V": player - enemy,
                        "ai_won": not player_won}

    def reseed(self, decision_id: str, k: int) -> None:
        b = seed_bytes(decision_id, k)
        self.h.write8("hRandomAdd", b[0])
        self.h.write8("hRandomSub", b[1])
        for i in range(10):
            self.h.write8("wRandomTable", b[2 + i], offset=i)

    # ---- decision hooks
    def _count_move_menu(self):
        self._move_menus += 1

    def _on_battle_menu(self):
        if self.in_trial:
            self._trial_menu = True   # a lookahead trial reached the next turn
            return
        self._menu_flag = True
        self._menu_mark = self._move_menus
        if self.recorder:
            self.recorder.battle_menu()

    # ---- A4 lookahead player
    def _host_snapshot(self) -> dict:
        d = self.driver
        return {"v": d.victories["count"], "f": d.defeats["count"], "turns": len(d.turns),
                "pin": d.party_inputs["count"], "pmodes": len(d.party_modes),
                "handled": d._handled, "mode_index": d._mode_index,
                "vol": dict(d.voluntary), "memo": dict(d.switch_memo), "mm": self._move_menus}

    def _host_restore(self, s: dict) -> None:
        d = self.driver
        d.victories["count"], d.defeats["count"] = s["v"], s["f"]
        del d.turns[s["turns"]:]
        d.party_inputs["count"] = s["pin"]
        del d.party_modes[s["pmodes"]:]
        d._handled, d._mode_index = s["handled"], s["mode_index"]
        d.voluntary.clear()
        d.voluntary.update(s["vol"])
        d.switch_memo.update(s["memo"])
        self._move_menus = s["mm"]

    def _board_key(self) -> str:
        """Emulator-side identity of the board, so the same state always draws the same trial
        seeds (pass 1 and every as-chosen replay pick the same player move)."""
        h = self.h
        data = bytes(h.read_bytes("wBattleMon", 0x20)) + bytes(h.read_bytes("wEnemyMon", 0x20))
        data += bytes([h.read8("hRandomAdd"), h.read8("hRandomSub")])
        data += bytes(h.read_bytes("wRandomTable", 10)) + bytes([h.read8("wAITurnPlan")])
        return hashlib.sha256(data).hexdigest()[:16]

    def lookahead(self) -> None:
        """Choose this turn's player move by one-turn trials (A4). Call at a battle-menu stop,
        before the move menu has opened."""
        import benchmark_policies as bp

        self._menu_flag = False
        d, h = self.driver, self.h
        if not self.lookahead_seeds:
            return
        if self._move_menus != self._menu_mark:   # the move menu already took the policy's slot
            self.look_skipped += 1
            return
        slots = bp.legal_slots(bp.read_state(h).player)
        self.look_turns += 1
        if len(slots) < 2:
            d.move_override = slots[0]
            return
        buf = io.BytesIO()
        h.save_state(buf)
        raw = buf.getvalue()
        key = self._board_key()
        host = self._host_snapshot()
        saved = (self.branch, self.recorder, self.outcome)
        self.branch = self.recorder = None
        self.in_trial = True
        means = {}
        try:
            for slot in slots:
                values = []
                for j in range(self.lookahead_seeds):
                    h.load_state(io.BytesIO(raw))
                    self._host_restore(host)
                    self.outcome, self._trial_menu = None, False
                    d.move_override = slot
                    self.reseed(f"look:{key}", j)
                    d.play(600, stop=lambda: self._trial_menu)
                    if self.outcome is not None:
                        values.append(self.outcome["V"])
                    else:
                        values.append(self.lost(self.party("player")) - self.lost(self.party("enemy")))
                means[slot] = statistics.fmean(values)
        finally:
            h.load_state(io.BytesIO(raw))
            self._host_restore(host)
            self.in_trial, self._trial_menu = False, False
            self.branch, self.recorder, self.outcome = saved
        d.move_override = min(slots, key=lambda s: (means[s], s))

    def start_budget(self) -> None:
        """Open the turn/frame budget for one base battle or one branch. play() spends it
        across every call until the next start_budget, so the recorder's re-entries share it."""
        self.budget = {"turn0": len(self.driver.turns), "frames": 0, "limit": None}

    def _over_budget(self, frames_now: int = 0) -> str | None:
        b = self.budget
        if len(self.driver.turns) - b["turn0"] > self.max_turns:
            return "turns"
        if b["frames"] + frames_now > self.max_frames:
            return "frames"
        return None

    def play(self, extra_stop=None) -> str:
        """driver.play, running the lookahead at every battle menu when it is on. Returns
        "stopped" only for extra_stop (the caller handles it, then calls play again), and
        "capped" once the budget start_budget opened is spent (budget["limit"] says which).
        Only frames played here count: a lookahead's trials are rewound, and their turns are
        truncated by _host_restore."""
        if not self.budget:
            self.start_budget()
        while True:
            f0 = self.h.pyboy.frame_count
            result = self.driver.play(
                MAX_STEPS, stop=lambda: (self._menu_flag or bool(extra_stop and extra_stop())
                                         or self._over_budget(self.h.pyboy.frame_count - f0) is not None))
            self.budget["frames"] += self.h.pyboy.frame_count - f0
            limit = self._over_budget()
            if limit is not None and result in ("stopped", "timeout"):
                self.budget["limit"] = limit
                self.outcome = None
                return "capped"
            if result != "stopped":
                return result
            if extra_stop and extra_stop():
                return "stopped"
            self.lookahead()

    def _on_scored_lead(self):
        # A faint replacement: not the opening lead, not an armed (planned) switch, and the
        # active mon is down (an unplanned voluntary switch also arrives here with HP left).
        faint_replacement = (self.h.read8("wEnemyMonPartyPos") != 0xFF
                             and not self.h.read8("wAITurnPlan") >> PLAN_ARMED & 1
                             and self.word("wEnemyMonHP") == 0)
        if not faint_replacement:
            return
        if self.recorder:
            self.recorder.scored_lead()
        b = self.branch
        if b and b["kind"] == "send_out" and not b["applied"]:
            b["seen"] += 1

    def _on_send_commit(self):
        if self.recorder:
            self.recorder.send_commit()
        b = self.branch
        if not b or b["kind"] != "send_out" or b["applied"] or b["seen"] != b["occurrence"]:
            return
        b["applied"] = True
        alt = b["alt"]
        if alt.startswith("send:"):
            self.h.pyboy.register_file.A = int(alt[5:])
        if b["k"] is not None:
            self.reseed(b["decision_id"], b["k"])

    def _on_commit(self):
        if self.recorder:
            self.recorder.commit()
        b = self.branch
        if not b or b["kind"] != "turn" or b["applied"]:
            return
        b["seen"] += 1
        if b["seen"] != b["occurrence"]:
            return
        b["applied"] = True
        h = self.h
        plan = h.read8("wAITurnPlan")
        if not (plan >> PLAN_PLANNED & 1 and plan >> PLAN_MOVE_CHOSEN & 1):
            b["invalid"] = f"plan {plan:#04x} not planned+chosen at commit"
            return
        alt = b["alt"]
        if alt.startswith("move:"):
            slot = int(alt[5:])
            h.write8("wEnemySelectedMove", h.read8("wEnemyMonMoves", offset=slot))
            h.write8("wEnemyMoveListIndex", slot)
            h.write8("wAITurnPlan", plan & ~((1 << PLAN_SWITCH) | PLAN_SLOT_MASK))
        elif alt.startswith("switch:"):
            reserve = int(alt[7:])
            h.write8("wAITurnPlan", (plan & ~PLAN_SLOT_MASK) | (1 << PLAN_SWITCH) | (reserve + 1))
            b["expect_switch"] = True
        if b["k"] is not None:
            self.reseed(b["decision_id"], b["k"])

    def _on_enemy_switch(self):
        b = self.branch
        if b and b.get("expect_switch") and b["applied"]:
            b["switched"] = True

    # ---- state helpers
    def living(self, side: str) -> int:
        return sum(1 for hp, _ in self.party(side) if hp > 0)

    def turn_alternatives(self) -> tuple[list[str], dict[str, str]]:
        h = self.h
        alts, kinds = [], {}
        disabled = h.read8("wEnemyDisabledMoveNumber")
        for slot in range(4):
            move = h.read8("wEnemyMonMoves", offset=slot)
            if not move or not h.read8("wEnemyMonPP", offset=slot) & PP_MASK or move == disabled:
                continue
            alts.append(f"move:{slot}")
            kinds[f"move:{slot}"] = move_kind(self.moves, move)
        tier = h.read8("wAITier") - 1
        locked = (h.read8("wEnemyBattleStatus1") & self.locked1
                  or h.read8("wEnemyBattleStatus2") & self.locked2)
        if tier >= 2 and not locked:
            active = h.read8("wEnemyMonPartyPos")
            for slot, (hp, _) in enumerate(self.party("enemy")):
                if slot != active and hp > 0:
                    alts.append(f"switch:{slot}")
                    kinds[f"switch:{slot}"] = "switch"
        return alts, kinds

    def send_alternatives(self) -> tuple[list[str], dict[str, str]]:
        active = self.h.read8("wEnemyMonPartyPos")
        alts = [f"send:{slot}" for slot, (hp, _) in enumerate(self.party("enemy"))
                if slot != active and hp > 0]
        return alts, {a: "send_out" for a in alts}


class Recorder:
    """Pass 1: hook-side bookkeeping only; states are saved from the driver loop."""

    def __init__(self, rp: Replayer):
        self.rp = rp
        self.pending_turn: dict | None = None
        self.commits = 0
        self.turn_index = 0
        self.seen_turn_menus: set[int] = set()
        self.state_index = -1
        self.scored_since_state = 0
        self.pending_send: dict | None = None
        self.decisions: list[Decision] = []
        self.state_meta = {"menu_open": False, "move_override": None}

    def battle_menu(self):
        rp, h = self.rp, self.rp.h
        turn = len(rp.driver.turns)
        if turn in self.seen_turn_menus:   # a cancelled move menu re-enters here
            return
        self.seen_turn_menus.add(turn)
        plan = h.read8("wAITurnPlan")
        if not plan >> PLAN_MOVE_CHOSEN & 1:   # locked: nothing to vary
            self.pending_turn = {"skip": True, "turn": turn, "commits": self.commits}
            return
        alts, kinds = rp.turn_alternatives()
        chosen = (f"switch:{(plan & PLAN_SLOT_MASK) - 1}" if plan >> PLAN_SWITCH & 1
                  else f"move:{h.read8('wEnemyMoveListIndex')}")
        if chosen not in alts:
            alts.append(chosen)
            kinds[chosen] = kinds.get(chosen, "switch" if chosen.startswith("switch") else
                                      move_kind(rp.moves, h.read8("wEnemySelectedMove")))
        self.pending_turn = {"turn": turn, "commits": self.commits, "alts": alts, "kinds": kinds,
                             "chosen": chosen}

    def commit(self):
        self.commits += 1

    def scored_lead(self):
        rp = self.rp
        self.scored_since_state += 1
        alts, kinds = rp.send_alternatives()
        self.pending_send = {"occurrence": self.scored_since_state, "alts": alts, "kinds": kinds,
                             "turn": len(rp.driver.turns)}

    def send_commit(self):
        p = self.pending_send
        if p is None or self.state_index < 0:
            return
        self.pending_send = None
        chosen = f"send:{self.rp.h.pyboy.register_file.A}"
        if len(p["alts"]) < 2:
            return
        self.decisions.append(self._decision("send_out", self.state_index, p["occurrence"], p["turn"],
                                             chosen, p["alts"], p["kinds"]))

    def _decision(self, kind, state_index, occurrence, turn, chosen, alts, kinds) -> Decision:
        rp = self.rp
        player, enemy = rp.party("player"), rp.party("enemy")
        return Decision(index=len(self.decisions), kind=kind, state_index=state_index,
                        occurrence=occurrence, turn=turn, chosen=chosen, alternatives=alts,
                        alt_kinds=kinds, player_living=sum(1 for h, _ in player if h),
                        enemy_living=sum(1 for h, _ in enemy if h),
                        player_hp=[sum(h for h, _ in player), sum(m for _, m in player)],
                        enemy_hp=[sum(h for h, _ in enemy), sum(m for _, m in enemy)],
                        **self.state_meta)


def record_battle(rp: Replayer, prepare=None) -> tuple[list[bytes], list[Decision], dict]:
    """Pass 1. Returns (saved states, decisions, base outcome). prepare(harness), if given,
    runs before boot (e.g. harness.inject_fight2_spec for a fixture board)."""
    rec = Recorder(rp)
    rp.recorder = rec
    rp.outcome = None
    if prepare is not None:
        prepare(rp.h)
    turns_start = len(rp.driver.turns)
    rp.driver.boot(rp.seed)
    rp.start_budget()
    states: list[bytes] = []
    dropped = 0

    def handle(p) -> None:
        nonlocal dropped
        if p.get("skip"):
            return
        if rec.commits != p["commits"]:   # the enemy committed before the loop regained control
            dropped += 1
            return
        buf = io.BytesIO()
        rp.h.save_state(buf)
        states.append(buf.getvalue())
        rec.state_index = len(states) - 1
        rec.scored_since_state = 0
        rec.state_meta = {"menu_open": rp._move_menus != rp._menu_mark,
                          "move_override": rp.driver.move_override}
        if len(p["alts"]) >= 2:
            rec.decisions.append(rec._decision("turn", rec.state_index, 1, p["turn"], p["chosen"],
                                               p["alts"], p["kinds"]))

    while True:
        result = rp.play(extra_stop=lambda: rec.pending_turn is not None)
        if result != "stopped":
            break
        p, rec.pending_turn = rec.pending_turn, None
        handle(p)          # save the state BEFORE the player's choice ...
        rp.lookahead()     # ... then make it (a no-op unless lookahead_1)
    if result == "timeout":
        raise AssertionError("base battle exceeded the step limit")
    rp.recorder = None
    # A capped base battle keeps the decisions saved before the cap (each state is a real
    # position; branches replay from it with their own budget), but has no outcome.
    base = dict(rp.outcome or {}, result=result, dropped_turn_states=dropped,
                turns=len(rp.driver.turns) - turns_start, frame=rp.h.pyboy.frame_count,
                capped=rp.budget["limit"])
    rp.budget = {}
    return states, rec.decisions, base


def play_branch(rp: Replayer, state: bytes, decision: Decision, alt: str, k: int | None,
                decision_id: str) -> dict[str, object]:
    rp.h.load_state(io.BytesIO(state))
    rp.driver.resync()
    rp.outcome = None
    rp.start_budget()
    rp.branch = {"kind": decision.kind, "alt": alt, "k": k, "decision_id": decision_id,
                 "occurrence": decision.occurrence, "seen": 0, "applied": False}
    turns_start = len(rp.driver.turns)
    # Every state was saved at a battle-menu stop, before the player chose: choose now, the
    # same way pass 1 did (the trial seeds come from the board, so the choice repeats).
    rp._menu_flag = False
    rp.driver.move_override = decision.move_override
    if not decision.menu_open:
        rp._menu_mark = rp._move_menus
        rp.lookahead()
    result = rp.play()
    b, rp.branch = rp.branch, None
    capped, rp.budget = rp.budget["limit"], {}
    out = dict(rp.outcome or {}, result=result, applied=b["applied"],
               turns_after=len(rp.driver.turns) - turns_start, frame=rp.h.pyboy.frame_count,
               capped=capped)
    if "invalid" in b:
        out["invalid"] = b["invalid"]
    if capped:   # no outcome: keep it out of every comparison
        out["invalid"] = f"capped at the {capped} limit"
    if b.get("expect_switch") and not b.get("switched"):
        out["invalid"] = "planned switch did not happen"
    if not b["applied"]:
        out["invalid"] = "decision point not reached"
    return out


# --------------------------------------------------------------------------- fan-out

_WORKER: Replayer | None = None


RUN_OPTIONS = {"look_seeds": 2, "kinds": None}


def _init_worker(seed, tier, policy, look_seeds):
    global _WORKER
    _WORKER = Replayer(seed, tier, policy, look_seeds=look_seeds)


def _work(task):
    state, decision_dict, alt, k, decision_id = task
    return (decision_dict["index"], alt, k,
            play_branch(_WORKER, state, Decision(**decision_dict), alt, k, decision_id))


def run(seed: int, tier: int, policy: str, k: int, jobs: int, out: Path, limit: int | None) -> dict:
    t0 = time.perf_counter()
    look_seeds, kinds = RUN_OPTIONS["look_seeds"], RUN_OPTIONS["kinds"]
    rp = Replayer(seed, tier, policy, look_seeds=look_seeds)
    try:
        states, decisions, base = record_battle(rp)
        base.update(look_turns=rp.look_turns, look_skipped=rp.look_skipped)
    finally:
        rp.close()
    if kinds:
        decisions = [d for d in decisions if d.kind in kinds]
    if limit is not None:
        decisions = decisions[:limit]
    tasks = []
    for d in decisions:
        decision_id = f"{seed}:{tier}:{policy}:{d.index}"
        for alt in d.alternatives:
            for kk in range(k):
                tasks.append((states[d.state_index], asdict(d), alt, kk, decision_id))
    results: dict[int, dict[str, dict[int, dict]]] = {}
    with ProcessPoolExecutor(max_workers=jobs, initializer=_init_worker,
                             initargs=(seed, tier, policy, look_seeds)) as pool:
        for index, alt, kk, res in pool.map(_work, tasks, chunksize=4):
            results.setdefault(index, {}).setdefault(alt, {})[kk] = res
    records = []
    with out.open("w", encoding="utf-8") as f:
        for d in decisions:
            branch = results.get(d.index, {})
            invalid = {alt: r.get("invalid") for alt, rs in branch.items() for r in rs.values()
                       if r.get("invalid")}
            valid = {alt: [rs[kk]["V"] for kk in range(k)] for alt, rs in branch.items()
                     if alt not in invalid and all("V" in rs[kk] for kk in range(k))}
            record = {**asdict(d), "seed": seed, "tier": tier, "policy": policy, "k": k,
                      "V": valid, "invalid": invalid}
            if d.chosen in valid and len(valid) >= 2:
                stats = split_regret(valid, d.chosen)
                record.update(stats, chosen_kind=d.alt_kinds.get(d.chosen, "?"),
                              best_kind=d.alt_kinds.get(stats["best"], "?"))
            f.write(json.dumps(record) + "\n")
            records.append(record)
    scored = [r for r in records if "regret" in r]
    capped = {limit: sum(1 for alts in results.values() for rs in alts.values()
                         for r in rs.values() if r.get("capped") == limit)
              for limit in ("turns", "frames")}
    summary = {"seed": seed, "tier": tier, "policy": policy, "k": k, "base": base,
               "decisions": len(decisions), "scored": len(scored), "branches": len(tasks),
               "capped_branches": capped,
               "seconds": round(time.perf_counter() - t0, 1), "table": summarize(scored)}
    out.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def parse_seeds(text: str) -> list[int]:
    """"17", "17,18", or "100:130" (half-open, like range). Expanded FIGHT 2 seeds are 100+;
    1-99 is the in-ROM prompt's range (see run_ai_benchmark.fixture_seeds)."""
    seeds: list[int] = []
    for part in text.split(","):
        if ":" in part:
            lo, hi = part.split(":")
            seeds.extend(range(int(lo), int(hi)))
        else:
            seeds.append(int(part))
    return seeds


def run_many(seeds: list[int], tier: int, policy: str, k: int, jobs: int, out: Path,
             limit: int | None) -> dict:
    """One run() per seed into <out stem>.seed<N>.jsonl, then everything combined into `out`
    and a summary across all seeds (the gate reads the combined table)."""
    per_seed, records = [], []
    for seed in seeds:
        path = out.with_name(f"{out.stem}.seed{seed}.jsonl")
        s = run(seed, tier, policy, k, jobs, path, limit)
        per_seed.append({key: s[key] for key in ("seed", "base", "decisions", "scored", "branches",
                                                 "capped_branches", "seconds")})
        records.extend(json.loads(line) for line in path.read_text(encoding="utf-8").splitlines())
        print(f"seed {seed}: {s['decisions']} decisions, {s['branches']} branches, {s['seconds']} s",
              flush=True)
    with out.open("w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")
    scored = [r for r in records if "regret" in r]
    summary = {"seeds": seeds, "tier": tier, "policy": policy, "k": k, "decisions": len(records),
               "scored": len(scored), "per_seed": per_seed, "table": summarize(scored)}
    out.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main() -> int:
    global MAX_TURNS, MAX_FRAMES
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seed", type=int, default=17)
    ap.add_argument("--seeds", default=None, help='several fixtures: "100:130" or "17,18"')
    ap.add_argument("--tier", type=int, default=3, choices=(0, 1, 2, 3))
    ap.add_argument("--policy", default="best_power")
    ap.add_argument("--k", type=int, default=8)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--limit", type=int, default=None, help="only the first N decisions per seed")
    ap.add_argument("--out", type=Path, default=ROOT / "tools/pyboy_smoke/artifacts/ai_counterfactual.jsonl")
    ap.add_argument("--look-seeds", type=int, default=2,
                    help=f"--policy {LOOKAHEAD}: trial seeds per player move per turn")
    ap.add_argument("--max-turns", type=int, default=MAX_TURNS,
                    help="turn budget per base battle and per branch (a capped one is dropped)")
    ap.add_argument("--max-frames", type=int, default=MAX_FRAMES,
                    help="frame budget per base battle and per branch")
    ap.add_argument("--kinds", default=None,
                    help='branch only these decision kinds, e.g. "send_out" (pass 1 still records all)')
    args = ap.parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    RUN_OPTIONS["look_seeds"] = args.look_seeds
    MAX_TURNS, MAX_FRAMES = args.max_turns, args.max_frames   # forked workers inherit them
    RUN_OPTIONS["kinds"] = set(args.kinds.split(",")) if args.kinds else None
    if args.seeds:
        summary = run_many(parse_seeds(args.seeds), args.tier, args.policy, args.k, args.jobs,
                           args.out, args.limit)
    else:
        summary = run(args.seed, args.tier, args.policy, args.k, args.jobs, args.out, args.limit)
    print(json.dumps({k: v for k, v in summary.items() if k not in ("table", "per_seed")}, indent=2))
    for row in summary["table"]:
        lo, hi = row["ci95"]
        print(f"{row['chosen_kind']:>9} -> {row['best_kind']:<9} n={row['count']:3}  "
              f"regret {row['mean_regret']:+.4f}  CI [{lo:+.4f}, {hi:+.4f}]  share {row['share']:.0%}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
