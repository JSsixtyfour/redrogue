"""Audit SpecialTrainerMoves: build each table row's team through the real ReadTrainer many
times and compare the moves just before and just after the table is applied.

  wsl bash .../witch_probe.sh witch_probe_special_moves.py [rolls]
"""
import collections
import json
import random
import re
import sys
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
MON_LENGTH = 44
OPP_ID_OFFSET = int(re.search(r"OPP_ID_OFFSET\s+EQU\s+(\d+)", (ROOT / "constants/trainer_constants.asm").read_text()).group(1))


def names(path, prefix_skip=()):
    table = {}
    for name, value in parse_rgbds_constants(ROOT / path).items():
        if isinstance(value, int) and not name.startswith(("NUM_", "DEF", "const")) and value not in table:
            table[value] = name
    return table


def rows():
    """(class, number, [(slot, move slot, move)]) from the table's source."""
    text = (ROOT / "data/trainers/special_moves.asm").read_text()
    result, current = [], None
    for line in text.splitlines():
        match = re.match(r"\s*db\s+(.*?)\s*(;.*)?$", line)
        if not match:
            continue
        parts = [p.strip() for p in match.group(1).split(",")]
        if len(parts) == 2:
            current = (parts[0], int(parts[1]), [])
            result.append(current)
        elif len(parts) == 3 and current:
            current[2].append((int(parts[0]), int(parts[1]), parts[2]))
    return result


def main() -> None:
    evidence = Path(sys.argv[1]) / "probe_special_moves"
    evidence.mkdir(parents=True, exist_ok=True)
    rolls = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    declared = re.findall(r"^\s*trainer_const\s+(\w+)", (ROOT / "constants/trainer_constants.asm").read_text(), re.M)
    classes = {name: index for index, name in enumerate(declared)}
    moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
    move_name = {v: k for k, v in moves.items() if isinstance(v, int)}
    species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
    species_name = {}
    for key, value in species.items():
        if isinstance(value, int) and value not in species_name:
            species_name[value] = key
    balance = parse_rgbds_constants(ROOT / "constants/balance_constants.asm")
    h = None
    before = {}

    def team():
        count = h.read8("wEnemyPartyCount")
        memory = h.pyboy.memory
        base = h.address("wEnemyMon1")
        moves_base = h.address("wEnemyMon1Moves")
        return count, [(memory[base + i * MON_LENGTH], [memory[moves_base + i * MON_LENGTH + m] for m in range(4)])
                       for i in range(6)]

    def on_table(_context):
        before["team"] = team()

    report = []
    mask = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")["DIFFICULTY_MASK"]
    rng = random.Random(4)
    for class_name, number, writes in rows():
        # A fresh boot per row: the park point drifts over many direct calls.
        if h is not None:
            h.close()
        h = RedRogueHarness(ROOT, evidence)
        h.boot_to_lobby()
        h.park_before_hijack()
        h.register_hook("ReadTrainer.AddAdditionalMoveData", on_table)
        h.write8("wOptions2", h.read8("wOptions2") & ~mask & 0xFF | 3)  # HARD, PrizeBonusPctTable's order
        klass = classes[class_name]
        # A leader's number is (round - 1) * 3 + 1 + variant (InitGymBattle), so numbers 1-3 are
        # round 1, fought at count 8. Tier 9 is the stage event's final round.
        counts = [72] if number == 9 else [8]
        out = {"row": f"{class_name} {number}", "writes": len(writes), "rolls": 0, "fired": 0, "slot_past_team": 0,
               "duplicates": 0, "team_size": collections.Counter(), "first_duplicates": [], "lost": collections.Counter(),
               "got": collections.Counter(), "unchanged_writes": 0, "changed_writes": 0, "errors": 0}
        for battle_count in counts:
            for _ in range(rolls):
                for offset in range(10):
                    h.write8("wRandomTable", rng.randrange(1, 256), offset=offset)
                h.write8("wBattleCount", battle_count)
                h.write8("wTrainerClass", klass)
                h.write8("wCurOpponent", klass + OPP_ID_OFFSET)
                h.write8("wTrainerNo", number)
                before.pop("team", None)
                try:
                    h.park_before_hijack()
                    h.call_routine("ReadTrainer", limit=120000)
                except Exception as error:
                    out["errors"] += 1
                    out["error"] = str(error)[:200]
                    continue
                out["rolls"] += 1
                if "team" not in before:
                    continue
                out["fired"] += 1
                count, was = before["team"]
                _, now = team()
                out["team_size"][count] += 1
                for slot, move_slot, move in writes:
                    i = slot - 1
                    if i >= count:
                        out["slot_past_team"] += 1
                        continue
                    old = was[i][1][move_slot - 1]
                    new = moves[move]
                    if old == new:
                        out["unchanged_writes"] += 1
                    else:
                        out["changed_writes"] += 1
                        out["lost"][move_name.get(old, old)] += 1
                    out["got"][f"{species_name.get(was[i][0], was[i][0])} {move}"] += 1
                for i in range(count):
                    known = [m for m in now[i][1] if m]
                    if len(set(known)) != len(known):
                        out["duplicates"] += 1
                        if len(out["first_duplicates"]) < 4:
                            out["first_duplicates"].append(
                                f"slot {i + 1} {species_name.get(now[i][0], now[i][0])}: "
                                f"{[move_name.get(m, m) for m in was[i][1]]} -> {[move_name.get(m, m) for m in now[i][1]]}")
        for key in ("team_size", "lost", "got"):
            out[key] = dict(out[key].most_common(10 if key != "team_size" else 6))
        report.append(out)
        print(json.dumps(out, default=str), flush=True)
    (evidence / "report.json").write_text(json.dumps(report, indent=1, default=str))
    h.close()


if __name__ == "__main__":
    main()
