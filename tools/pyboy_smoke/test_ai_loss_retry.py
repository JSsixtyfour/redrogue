"""Checkpoint 11 runtime contracts for the AI Lair loss and retry.

See CHECKPOINT_11_SPEC.md. A loss to the AI spends the current attempt
(EVENT_AI_ATTEMPT_SPENT) and blacks out to the Dorm instead of Pallet Town;
while the attempt is spent the VR machine's warp reverts to the normal run
start and Palm's failure line replaces the repeat line; the next Champion
victory, once EVENT_AI_ATTEMPT_SPENT is set and EVENT_AI_DEFEATED is not,
skips the Hall of Fame record/credits, archives the new team, clears the
spent flag, and warps straight to the Lair.
"""

import unittest

from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import parse_map_constants, parse_rgbds_constants


EVENT_CONSTANTS = REPO_ROOT / "constants" / "event_constants.asm"
MAP_CONSTANTS = REPO_ROOT / "constants" / "map_constants.asm"
RAM_CONSTANTS = REPO_ROOT / "constants" / "ram_constants.asm"

# scripts/AILair.asm DEFs. Not memory symbols (no address), so not resolvable
# from the .sym file - same reasoning as SPRITE_RED etc in
# test_ai_lair_presentation.py.
AILAIR_STATE_AFTER_BATTLE = 0xFE
AILAIR_STATE_DONE = 0xFF

# scripts/SilphCoVR.asm DEF. Third warp_event in that map's object file.
SILPHCOVR_MACHINE_WARP_INDEX = 2

PARTY_SIZE = 404
RECORD_SIZE = 406
HEADER_SIZE = 11
ARCHIVE_BANK = 1


class EventLayoutTest(unittest.TestCase):
    def test_event_is_persistent_and_nothing_else_moved(self) -> None:
        events = parse_rgbds_constants(EVENT_CONSTANTS)
        self.assertEqual(events["EVENT_PALMS_ROOM_OPEN"], 33)
        self.assertEqual(events["EVENT_AI_ATTEMPT_SPENT"], 34)
        # 34 -> 36 (2026-09-23): EVENT_PRISM_BUGSY_SHOWN / _WHITNEY_SHOWN were
        # appended AFTER EVENT_AI_ATTEMPT_SPENT, so nothing above moved.
        self.assertEqual(events["EVENT_PRISM_BUGSY_SHOWN"], 35)
        self.assertEqual(events["EVENT_PRISM_WHITNEY_SHOWN"], 36)
        self.assertEqual(events["PERSISTENT_EVENTS_END"], 36)
        self.assertEqual(events["RUN_EVENTS_START"], 40)
        self.assertLess(events["EVENT_AI_ATTEMPT_SPENT"], events["PERSISTENT_EVENTS_END"] + 1)
        self.assertLessEqual(events["PERSISTENT_EVENTS_END"] + 1, events["RUN_EVENTS_START"])


class AILairLossHookTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        self.events = parse_rgbds_constants(EVENT_CONSTANTS)
        self.maps = parse_map_constants(MAP_CONSTANTS)
        self.harness.boot_fight2(seed=1)

    def _set_event(self, name: str, value: bool) -> None:
        h = self.harness
        assert h is not None
        event = self.events[name]
        addr = h.address("wEventFlags") + event // 8
        bit = 1 << (event % 8)
        if value:
            h.pyboy.memory[addr] |= bit
        else:
            h.pyboy.memory[addr] &= ~bit & 0xFF

    def _arrive_after_battle(self, *, lost: bool) -> bool:
        """Run the after-battle state once. Returns whether the victory branch
        was entered. Checkpoint 12's victory branch rolls credits and ends in
        jp Init, so it is cut off at its first instruction by a forced return
        (the same technique as the Delay3 hook below); the full victory
        sequence is covered in test_ai_victory.py."""
        h = self.harness
        assert h is not None
        h.write8("wSilphCo1FCurScript", AILAIR_STATE_AFTER_BATTLE)
        h.write8("hIsInBattle", 0xFF if lost else 0)
        h.write8("wLastBlackoutMap", self.maps["PALLET_TOWN"])
        h.write8("hCurMap", self.maps["AI_LAIR"])
        self._set_event("EVENT_AI_ATTEMPT_SPENT", False)
        flags = h.address("wCurrentMapScriptFlags")
        # BIT_CUR_MAP_LOADED_1 - clear so AILairHandleMapEntry's own early
        # `ret z` is the path taken (it is not an arrival, so nothing else in
        # that routine should fire).
        h.pyboy.memory[flags] &= ~(1 << 1) & 0xFF
        won_bank, won_addr = h.symbols.get("AILair_Script.won")
        entered = []

        def force_return_at_won(_context) -> None:
            # .won is reached by jr inside AILair_Script with nothing pushed,
            # so the stack top is AILair_Script's own return address.
            entered.append(True)
            sp = h.pyboy.register_file.SP
            h.pyboy.register_file.SP = (sp + 2) & 0xFFFF
            h.pyboy.register_file.PC = h.pyboy.memory[sp] | (h.pyboy.memory[sp + 1] << 8)

        h.park_before_hijack()
        h.pyboy.hook_register(won_bank, won_addr, force_return_at_won, None)
        try:
            h.call_routine("AILair_Script")
        finally:
            h.pyboy.hook_deregister(won_bank, won_addr)
        return bool(entered)

    def test_loss_spends_attempt_and_blacks_out_to_dorm(self) -> None:
        h = self.harness
        assert h is not None
        self.assertFalse(self._arrive_after_battle(lost=True))
        self.assertTrue(self._event_is_set("EVENT_AI_ATTEMPT_SPENT"))
        self.assertEqual(h.read8("wLastBlackoutMap"), self.maps["SILPH_CO_DORM"])
        self.assertEqual(h.read8("wSilphCo1FCurScript"), AILAIR_STATE_DONE)

    def test_win_does_not_spend_attempt(self) -> None:
        h = self.harness
        assert h is not None
        self.assertTrue(self._arrive_after_battle(lost=False))
        self.assertFalse(self._event_is_set("EVENT_AI_ATTEMPT_SPENT"))
        self.assertEqual(h.read8("wLastBlackoutMap"), self.maps["PALLET_TOWN"])

    def _event_is_set(self, name: str) -> bool:
        h = self.harness
        assert h is not None
        event = self.events[name]
        addr = h.address("wEventFlags") + event // 8
        return bool(h.pyboy.memory[addr] & (1 << (event % 8)))


class SilphCoVRGateTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        self.events = parse_rgbds_constants(EVENT_CONSTANTS)
        self.maps = parse_map_constants(MAP_CONSTANTS)
        self.harness.boot_fight2(seed=1)

    def _set_event(self, name: str, value: bool) -> None:
        h = self.harness
        assert h is not None
        event = self.events[name]
        addr = h.address("wEventFlags") + event // 8
        bit = 1 << (event % 8)
        if value:
            h.pyboy.memory[addr] |= bit
        else:
            h.pyboy.memory[addr] &= ~bit & 0xFF

    def _capture_one_valid_team(self, species: int) -> None:
        h = self.harness
        assert h is not None
        h.write_sram_bytes(
            "sFinalTeamArchive", [0xFF] * (HEADER_SIZE + 4 * RECORD_SIZE), bank=ARCHIVE_BANK
        )
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveInit")

        start = h.address("wPartyDataStart")
        for offset in range(PARTY_SIZE):
            h.pyboy.memory[start + offset] = 0
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", species)
        h.write8("wPartySpecies", 0xFF, offset=1)
        h.write8("wPartyMon1Species", species)
        h.write8("wPartyMon1HP", 0)
        h.write8("wPartyMon1HP", 1, offset=1)
        h.write8("wPartyMon1MaxHP", 0)
        h.write8("wPartyMon1MaxHP", 50, offset=1)
        h.write8("wPartyMon1Status", 0x40)
        h.write8("wFusionSecondarySpecies", 0)
        h.write8("wFusionSecondaryForm", 0)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)

    def _seed_machine_warp_to_oaks_lab(self) -> None:
        h = self.harness
        assert h is not None
        offset = SILPHCOVR_MACHINE_WARP_INDEX * 4
        h.write8("wWarpEntries", 0, offset=offset + 2)
        h.write8("wWarpEntries", self.maps["OAKS_LAB"], offset=offset + 3)

    def test_spent_attempt_revokes_vr_machine_and_clearing_it_restores_lair(self) -> None:
        h = self.harness
        assert h is not None
        self._capture_one_valid_team(25)
        self._set_event("EVENT_FINAL_BRIEFING_COMPLETE", True)
        self._set_event("EVENT_AI_DEFEATED", False)
        self._set_event("EVENT_AI_ATTEMPT_SPENT", True)
        self._seed_machine_warp_to_oaks_lab()

        h.park_before_hijack()
        h.call_routine("SilphCoVRPatchMachineWarp")

        offset = SILPHCOVR_MACHINE_WARP_INDEX * 4
        self.assertEqual(h.read8("wWarpEntries", offset=offset + 3), self.maps["OAKS_LAB"])

        self._set_event("EVENT_AI_ATTEMPT_SPENT", False)
        h.park_before_hijack()
        h.call_routine("SilphCoVRPatchMachineWarp")

        self.assertEqual(h.read8("wWarpEntries", offset=offset + 2), 0)
        self.assertEqual(h.read8("wWarpEntries", offset=offset + 3), self.maps["AI_LAIR"])


class HallOfFameRetryPredicateTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        self.events = parse_rgbds_constants(EVENT_CONSTANTS)
        self.harness.boot_fight2(seed=1)

    def _set_event(self, name: str, value: bool) -> None:
        h = self.harness
        assert h is not None
        event = self.events[name]
        addr = h.address("wEventFlags") + event // 8
        bit = 1 << (event % 8)
        if value:
            h.pyboy.memory[addr] |= bit
        else:
            h.pyboy.memory[addr] &= ~bit & 0xFF

    def _is_retry(self, *, defeated: bool, spent: bool) -> bool:
        """HallOfFameIsAIRetry returns its result in carry, which call_routine
        cannot surface (it restores every saved register including F on
        return - see AIShouldSwitchTest in test_ai_switching.py for the same
        problem and the same fix). `.no` is a distinct address from the
        `scf` success tail, so hook `.no` and use "did not fire" as the
        carry-set signal instead of reading flags after the call.
        """
        h = self.harness
        assert h is not None
        self._set_event("EVENT_AI_DEFEATED", defeated)
        self._set_event("EVENT_AI_ATTEMPT_SPENT", spent)

        hit_no = {"value": False}

        def on_no(_context) -> None:
            hit_no["value"] = True

        bank, addr = h.symbols.get("HallOfFameIsAIRetry.no")
        h.pyboy.hook_register(bank, addr, on_no, None)
        try:
            h.park_before_hijack()
            h.call_routine("HallOfFameIsAIRetry")
        finally:
            h.pyboy.hook_deregister(bank, addr)
        return not hit_no["value"]

    def test_only_spent_and_not_defeated_is_a_retry(self) -> None:
        self.assertFalse(self._is_retry(defeated=False, spent=False))
        self.assertFalse(self._is_retry(defeated=True, spent=False))
        self.assertFalse(self._is_retry(defeated=True, spent=True))
        self.assertTrue(self._is_retry(defeated=False, spent=True))


class HallOfFameRetryBranchTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        self.events = parse_rgbds_constants(EVENT_CONSTANTS)
        self.maps = parse_map_constants(MAP_CONSTANTS)
        self.ram_constants = parse_rgbds_constants(RAM_CONSTANTS)
        self.harness.boot_fight2(seed=1)

    def _set_event(self, name: str, value: bool) -> None:
        h = self.harness
        assert h is not None
        event = self.events[name]
        addr = h.address("wEventFlags") + event // 8
        bit = 1 << (event % 8)
        if value:
            h.pyboy.memory[addr] |= bit
        else:
            h.pyboy.memory[addr] &= ~bit & 0xFF

    def _event_is_set(self, name: str) -> bool:
        h = self.harness
        assert h is not None
        event = self.events[name]
        addr = h.address("wEventFlags") + event // 8
        return bool(h.pyboy.memory[addr] & (1 << (event % 8)))

    def _party(self, species: int) -> None:
        h = self.harness
        assert h is not None
        start = h.address("wPartyDataStart")
        for offset in range(PARTY_SIZE):
            h.pyboy.memory[start + offset] = 0
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", species)
        h.write8("wPartySpecies", 0xFF, offset=1)
        h.write8("wPartyMon1Species", species)
        h.write8("wPartyMon1HP", 0)
        h.write8("wPartyMon1HP", 1, offset=1)
        h.write8("wPartyMon1MaxHP", 0)
        h.write8("wPartyMon1MaxHP", 50, offset=1)
        h.write8("wPartyMon1Status", 0x40)
        h.write8("wFusionSecondarySpecies", 0)
        h.write8("wFusionSecondaryForm", 0)

    def test_retry_branch_captures_new_team_clears_flag_and_warps_to_lair(self) -> None:
        h = self.harness
        assert h is not None

        # Archive holds team A before the retry.
        h.write_sram_bytes(
            "sFinalTeamArchive", [0xFF] * (HEADER_SIZE + 4 * RECORD_SIZE), bank=ARCHIVE_BANK
        )
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveInit")
        self._party(25)  # team A
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)
        hof_teams_before = h.read8("wNumHoFTeams")

        # Team B is what the player just beat the Champion with.
        self._party(26)
        self._set_event("EVENT_AI_DEFEATED", False)
        self._set_event("EVENT_AI_ATTEMPT_SPENT", True)

        # HallOfFameResetEventsAndSaveScript's very first instructions are
        # `predef SingleCPUSpeed` then `call Delay3`, which halts waiting for
        # a real VBlank interrupt that never arrives under call_routine's
        # parked-with-IME-disabled precondition (see park_before_hijack's
        # docstring, and test_final_team_archive.py's
        # test_animate_hall_of_fame_captures_before_any_other_state_change for
        # the same DelayFrames wall on AnimateHallOfFame). Verified separately
        # that writing to a ROM address does not change what is later read
        # back (PyBoy correctly models ROM as read-only against the mapped
        # MBC), so patching the byte is not an option. Hook Delay3's entry
        # instead and simulate its `ret` by hand: pop the return address off
        # the stack and jump straight to it. This is exactly what
        # AIShouldSwitchTest's hook-based approach in test_ai_switching.py
        # does for the same class of problem, just returning through the
        # call instead of only observing which address fired.
        delay3_bank, delay3_addr = h.symbols.get("Delay3")

        def force_delay3_return(_context) -> None:
            sp = h.pyboy.register_file.SP
            ret_lo = h.pyboy.memory[sp]
            ret_hi = h.pyboy.memory[sp + 1]
            h.pyboy.register_file.SP = (sp + 2) & 0xFFFF
            h.pyboy.register_file.PC = (ret_hi << 8) | ret_lo

        # Snapshot every assertion-relevant byte from INSIDE a hook fired at
        # .warpToAILair's `ret` (its last instruction, after every write in
        # that block has already run), not after call_routine returns.
        #
        # Measured: reading hWarpDestinationMap right after call_routine
        # returned normally gave 230, one less than the 231 (AI_LAIR) the ROM
        # had just written a moment earlier (confirmed separately with a hook
        # placed right after the `ldh` write, inside this same call). The
        # cause is call_routine's own completion mechanics: its
        # Bankswitch.Return hook restores the ORIGINAL interrupted VBlank
        # handler's PC/registers the instant our routine's `ret` reaches it,
        # but wait_until's per-tick granularity lets that resumed real frame
        # keep running for the remainder of the tick before Python regains
        # control - and that unrelated resumed frame evidently reuses
        # hWarpDestinationMap's HRAM address for something else. Capturing at
        # this routine's own final `ret`, before Bankswitch.Return ever runs,
        # reads the value this routine actually produced.
        warp_bank, warp_addr = h.symbols.get(
            "HallOfFameResetEventsAndSaveScript.warpToAILair"
        )
        ret_addr = warp_addr + 18  # the block's final `ret`, measured against its byte trace
        snapshot: dict[str, int] = {}

        def capture_before_return(_context) -> None:
            snapshot["hWarpDestinationMap"] = h.read8("hWarpDestinationMap")
            snapshot["wDestinationWarpID"] = h.read8("wDestinationWarpID")
            snapshot["wStatusFlags3"] = h.read8("wStatusFlags3")
            snapshot["wLastMap"] = h.read8("wLastMap")
            snapshot["wHallOfFameCurScript"] = h.read8("wHallOfFameCurScript")
            snapshot["wPartyCount"] = h.read8("wPartyCount")
            snapshot["wNumHoFTeams"] = h.read8("wNumHoFTeams")
            snapshot["attempt_spent_event"] = int(self._event_is_set("EVENT_AI_ATTEMPT_SPENT"))

        h.pyboy.hook_register(delay3_bank, delay3_addr, force_delay3_return, None)
        h.pyboy.hook_register(warp_bank, ret_addr, capture_before_return, None)
        try:
            h.park_before_hijack()
            h.call_routine("HallOfFameResetEventsAndSaveScript")
        finally:
            h.pyboy.hook_deregister(delay3_bank, delay3_addr)
            h.pyboy.hook_deregister(warp_bank, ret_addr)

        self.assertEqual(snapshot["hWarpDestinationMap"], self.maps["AI_LAIR"])
        self.assertEqual(snapshot["wDestinationWarpID"], 0)
        bit = self.ram_constants["BIT_WARP_FROM_CUR_SCRIPT"]
        self.assertEqual(snapshot["wStatusFlags3"] & (1 << bit), 1 << bit)
        self.assertEqual(snapshot["wLastMap"], self.maps["HALL_OF_FAME"])

        self.assertEqual(snapshot["attempt_spent_event"], 0)
        self.assertEqual(snapshot["wNumHoFTeams"], hof_teams_before)
        self.assertEqual(snapshot["wHallOfFameCurScript"], 0)
        # RogueResetRunState emptied the party (retry restores the archived
        # team on Lair arrival, same as the first attempt).
        self.assertEqual(snapshot["wPartyCount"], 0)

        # The archive's latest record is now team B, not team A.
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveRestoreLatest")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)
        self.assertEqual(h.read8("wPartyMon1Species"), 26)


class HallOfFameSourceContractTest(unittest.TestCase):
    def test_normal_path_still_has_the_record_and_the_reboot(self) -> None:
        source = (REPO_ROOT / "scripts" / "HallOfFame.asm").read_text()
        self.assertIn("predef HallOfFamePC", source)
        self.assertIn("jp Init", source)
