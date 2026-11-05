"""Replay one matrix case and report the machine at its first anomaly: registers, the stack by name,
the screen, the party and battle state. Keeps watching SP until the crash.

  wsl bash .../witch_probe.sh witch_probe_first_anomaly.py <evidence> <rom> <case> <branch>
"""
import json
import os
import sys
from pathlib import Path

import autoplay_checks
import witch_autoplay as wa


def main() -> None:
    evidence, rom, case, branch = sys.argv[2:6]
    original = autoplay_checks.GameChecks.anomaly
    seen = {"count": 0}

    def anomaly(self, check, detail, **extra):
        original(self, check, detail, **extra)
        seen["count"] += 1
        if seen["count"] > 1:
            return
        h = self.h
        registers = h.pyboy.register_file
        sp = registers.SP
        words = [self._where(self._word(sp + 2 * i)) for i in range(40)]
        count = h.read8("wPartyCount")
        print(json.dumps({
            "check": check, "detail": detail, "frame": h.pyboy.frame_count, "pc": self._where(registers.PC),
            "sp": f"${sp:04X}", "lowest_sp": f"${self.lowest_sp:04X}", "stack_top": f"${self.stack_top:04X}",
            "bank": h.read8("hLoadedROMBank"), "in_battle": h.read8("hIsInBattle"),
            "screen": wa.screen_rows(h), "stack": words,
            "party": [count] + [h.read8("wPartySpecies", offset=i) for i in range(count)],
            "status": [h.read8("wPartyMon1Status", offset=i * 44) for i in range(count)],
            "battle_status": h.read8("wBattleMonStatus"), "moves": list(h.read_bytes("wBattleMonMoves", 4)),
            "species": h.read8("wBattleMonSpecies"), "whose": h.read8("hWhoseTurn"),
            "cur_opponent": h.read8("wCurOpponent"), "class": h.read8("wTrainerClass"), "no": h.read8("wTrainerNo"),
            "text": h.read8("hTextID"), "selected": h.read8("wPlayerSelectedMove"),
            "enemy_selected": h.read8("wEnemySelectedMove"), "list_index": h.read8("wPlayerMoveListIndex"),
            "name_index": h.read8("wNameListIndex"), "num_moves_minus_one": h.read8("wNumMovesMinusOne"),
            "disabled": h.read8("wPlayerDisabledMove"), "pp": list(h.read_bytes("wBattleMonPP", 4)),
            "menu_item": h.read8("hCurrentMenuItem"), "status1": h.read8("wPlayerBattleStatus1"),
            "status2": h.read8("wPlayerBattleStatus2"), "status3": h.read8("wPlayerBattleStatus3"),
            "enemy_status1": h.read8("wEnemyBattleStatus1"), "enemy_moves": list(h.read_bytes("wEnemyMonMoves", 4)),
            "enemy_species": h.read8("wEnemyMonSpecies"), "player_num": h.read8("wPlayerMonNumber"),
            "interventions_tail": None}, default=str), flush=True)
        h.write_failure_artifacts("first_anomaly")
        os.kill(os.getppid(), 9)
        os._exit(0)

    autoplay_checks.GameChecks.anomaly = anomaly
    sys.exit(wa.main(["run", "--evidence", evidence, "--rom", rom, "--case", case, "--branch", branch, "--jobs", "1", "--timeout", "600"]))


if __name__ == "__main__":
    main()
