"""Why does a direct ReadTrainer for LT_SURGE number 1 not return? Roll until a call fails,
then report where the CPU is and what the stack holds.

  wsl bash .../witch_probe.sh witch_probe_surge.py [number]
"""
import json
import random
import re
import sys
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
OPP_ID_OFFSET = int(re.search(r"OPP_ID_OFFSET\s+EQU\s+(\d+)", (ROOT / "constants/trainer_constants.asm").read_text()).group(1))


def main() -> None:
    evidence = Path(sys.argv[1]) / "probe_surge"
    evidence.mkdir(parents=True, exist_ok=True)
    number = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    declared = re.findall(r"^\s*trainer_const\s+(\w+)", (ROOT / "constants/trainer_constants.asm").read_text(), re.M)
    klass = declared.index("LT_SURGE")
    mask = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")["DIFFICULTY_MASK"]
    h = RedRogueHarness(ROOT, evidence)
    h.boot_to_lobby()
    # Optional: let the game go idle first, so no main-thread job is under the hijack.
    settle = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    counts = h.hook_flag("DexCountCollection")
    h.tick(settle)
    idle = h.hook_flag("JoypadOverworld")
    h.tick(30)
    print(json.dumps({"settled_frames": settle, "frame": h.pyboy.frame_count, "dex_counts_so_far": counts["count"],
                      "overworld_polls_in_30_frames": idle["count"]}), flush=True)
    h.write8("wOptions2", h.read8("wOptions2") & ~mask & 0xFF | 3)
    # The audit's stream: seed 4, past Brock's and Misty's 60 rolls of 10 draws each.
    rng = random.Random(4)
    for _ in range(1200):
        rng.randrange(1, 256)
    done = 0
    crash = {}

    def on_crash(_context) -> None:
        if crash:
            return
        registers = h.pyboy.register_file
        memory = h.pyboy.memory
        sp = registers.SP
        words = [memory[sp + i * 2] | memory[sp + i * 2 + 1] << 8 for i in range(16)]
        crash.update({"frame": h.pyboy.frame_count, "pc": f"{registers.PC:04x}", "sp": f"{sp:04x}", "a": registers.A,
                      "bc": f"{registers.B:02x}{registers.C:02x}", "de": f"{registers.D:02x}{registers.E:02x}",
                      "hl": f"{registers.HL:04x}", "bank_frame": h.pyboy.frame_count, "cur_opponent": h.read8("wCurOpponent"), "map": h.read8("hCurMap"),
                      "in_battle": h.read8("hIsInBattle"), "stack": [f"{w:04x}" for w in words],
                      "rom_bank": memory[h.address("hLoadedROMBank")], "slot": h.read8("wPartyGenSlot"),
                      "source": h.read8("wPartyGenSource"), "species": h.read8("wCurPartySpecies"),
                      "form": h.read8("wSpawnForm"), "level": h.read8("wCurEnemyLevel"),
                      "team": h.read8("wEnemyPartyCount"), "trainer": [h.read8("wTrainerClass"), h.read8("wTrainerNo")]})

    h.register_hook("CrashScreen", on_crash)
    trail = []

    def tracer(label):
        def hook(_context) -> None:
            registers = h.pyboy.register_file
            trail.append(f"{h.pyboy.frame_count} {label} a={registers.A:02x} bc={registers.B:02x}{registers.C:02x} "
                         f"de={registers.D:02x}{registers.E:02x} hl={registers.HL:04x} "
                         f"bank={h.pyboy.memory[h.address('hLoadedROMBank')]:02x} slot={h.read8('wPartyGenSlot')} "
                         f"species={h.read8('wCurPartySpecies')} cur={h.read8('wCurSpecies')} form={h.read8('wSpawnForm')}")
            del trail[:-30]
        return hook

    for label in ("RogueBuildParty", "PartyGenBuildSlot", "PartyGenApplyMoveset", "PartyGenRollMoveset",
                  "PartyGenApplySetMovesetMask", "PartyGenApplyRequireFlags", "PartyGenEnsureAttack", "PartyGenWriteMove",
                  "AddPartyMon", "GetMonHeader", "PublishFormContext", "GetLevelUpMovesFar", "PartyGenCountTMs",
                  "PartyGenPickOne", "ReadTrainer.AddAdditionalMoveData", "ReadTrainer.FinishUp", "GetMoveMaxPPFar",
                  "StageEventInjectStolenMon", "GetKeyItemPowerInE", "ReadTrainer.gotAmuletPct",
                  "ReadTrainer.noAmuletCoin", "ReadTrainer.LastLoop"):
        try:
            h.register_hook(label, tracer(label))
        except Exception as error:
            print(json.dumps({"no_hook": label, "error": str(error)[:80]}), flush=True)
    for roll in range(60):
        for offset in range(10):
            h.write8("wRandomTable", rng.randrange(1, 256), offset=offset)
        h.write8("wBattleCount", 8)
        h.write8("wTrainerClass", klass)
        h.write8("wCurOpponent", klass + OPP_ID_OFFSET)
        h.write8("wTrainerNo", number)
        try:
            h.park_before_hijack()
            h.call_routine("ReadTrainer", limit=120000)
            done += 1
        except Exception as error:
            registers = h.pyboy.register_file
            sp = registers.SP
            memory = h.pyboy.memory
            stack = [memory[sp + i * 2] | memory[sp + i * 2 + 1] << 8 for i in range(12)]
            print(json.dumps({"crash": crash, "rom_3d58": (ROOT / "pokeblue_debug.gbc").read_bytes()[0x3d58:0x3d64].hex(),
                              "near": sorted(line.strip() for line in (ROOT / "pokeblue_debug.sym").read_text(errors="replace").splitlines()
                                             if line.lower().startswith(("00:3d4", "00:3d5", "00:3d6", "00:3d7")))[:14]},
                             default=str), flush=True)
            print("\n".join(trail), flush=True)
            print(json.dumps({"roll": roll, "completed_before": done, "error": str(error)[:300],
                              "pc": f"{registers.PC:04x}", "sp": f"{sp:04x}", "bank": h.pyboy.memory[0xFF00 + 0x70],
                              "stack": [f"{w:04x}" for w in stack], "team": h.read8("wEnemyPartyCount"),
                              "species": [memory[h.address("wEnemyPartySpecies") + i] for i in range(7)]}), flush=True)
            h.close()
            return
    print(json.dumps({"completed": done, "dex_counts": counts["count"]}), flush=True)
    h.close()


if __name__ == "__main__":
    main()
