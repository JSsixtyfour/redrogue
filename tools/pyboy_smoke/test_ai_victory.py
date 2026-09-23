"""Checkpoint 12 runtime contracts for the final AI victory and postgame.

A win in the AI Lair awards the largest credit distribution, shows the
placeholder line, sets EVENT_AI_DEFEATED, resets the run and saves, rolls
credits without another Hall of Fame record, then sets EVENT_POST_GAME, saves
again and reboots. Postgame, the facility maps drop the crisis overrides.
"""

import re
import unittest

from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import parse_map_constants, parse_rgbds_constants


EVENT_CONSTANTS = REPO_ROOT / "constants" / "event_constants.asm"
MAP_CONSTANTS = REPO_ROOT / "constants" / "map_constants.asm"

# scripts/AILair.asm DEFs (not memory symbols).
AILAIR_STATE_AFTER_BATTLE = 0xFE
AILAIR_STATE_DONE = 0xFF

FINALE_MAPS = ("SILPH_CO_B1F", "SILPH_CO_DORM", "CREDIT_EXCHANGE", "SILPH_CO_VR", "PALMS_ROOM")


class _EventHelpers(HarnessTestCase):
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

    def _event_is_set(self, name: str) -> bool:
        h = self.harness
        assert h is not None
        event = self.events[name]
        addr = h.address("wEventFlags") + event // 8
        return bool(h.pyboy.memory[addr] & (1 << (event % 8)))

    def _force_return(self) -> None:
        """Simulate an immediate `ret` from the routine whose entry just hit."""
        h = self.harness
        assert h is not None
        sp = h.pyboy.register_file.SP
        h.pyboy.register_file.SP = (sp + 2) & 0xFFFF
        h.pyboy.register_file.PC = h.pyboy.memory[sp] | (h.pyboy.memory[sp + 1] << 8)


class AILairVictorySequenceTest(_EventHelpers):
    def test_victory_order_events_saves_and_no_hall_of_fame_record(self) -> None:
        h = self.harness
        assert h is not None

        start = h.address("wPartyDataStart")
        for offset in range(404):
            h.pyboy.memory[start + offset] = 0
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", 25)
        h.write8("wPartySpecies", 0xFF, offset=1)
        h.write8("wPartyMon1Species", 25)

        h.write8("wSilphCo1FCurScript", AILAIR_STATE_AFTER_BATTLE)
        h.write8("hIsInBattle", 0)
        h.write8("wIsTrainerBattle", 1)
        h.write8("hCurMap", self.maps["AI_LAIR"])
        self._set_event("EVENT_AI_DEFEATED", False)
        self._set_event("EVENT_POST_GAME", False)
        self._set_event("EVENT_AI_ATTEMPT_SPENT", False)
        flags = h.address("wCurrentMapScriptFlags")
        h.pyboy.memory[flags] &= ~(1 << 1) & 0xFF  # not an arrival
        hof_teams_before = h.read8("wNumHoFTeams")

        order: list[str] = []
        snaps: list[dict[str, int]] = []

        def snapshot(name: str) -> None:
            order.append(name)
            snaps.append(
                {
                    "ai_defeated": int(self._event_is_set("EVENT_AI_DEFEATED")),
                    "post_game": int(self._event_is_set("EVENT_POST_GAME")),
                    "party_count": h.read8("wPartyCount"),
                    "hof_teams": h.read8("wNumHoFTeams"),
                    "trainer_battle": h.read8("wIsTrainerBattle"),
                    "script": h.read8("wSilphCo1FCurScript"),
                }
            )

        # Observed and allowed to run for real.
        observed = ("RogueAwardCredits3", "RogueResetRunState", "SaveGameData")
        # Observed and skipped: text and button waits need input, the credits
        # and DelayFrame halt on a VBlank that never arrives under
        # call_routine, and Init never returns. Init is reached by `jp` from
        # AILair_Script's own frame, so a forced return there returns from
        # AILair_Script itself.
        skipped = ("DisplayTextID", "AIVictoryCredits", "WaitForTextScrollButtonPress", "Init")
        # Not recorded: the 600-frame reboot delay's DelayFrame calls.
        silent = ("DelayFrame",)
        # Must never run on this path.
        forbidden = ("AnimateHallOfFame", "SaveHallOfFameTeams", "FinalTeamArchiveCapture")

        hooks = []

        def register(label: str, callback) -> None:
            bank, addr = h.symbols.get(label)
            h.pyboy.hook_register(bank, addr, callback, None)
            hooks.append((bank, addr))

        for label in observed:
            register(label, lambda _c, label=label: snapshot(label))
        for label in skipped:
            def skip(_c, label=label) -> None:
                snapshot(label)
                self._force_return()
            register(label, skip)
        for label in silent:
            register(label, lambda _c: self._force_return())
        for label in forbidden:
            register(label, lambda _c, label=label: order.append("FORBIDDEN " + label))

        h.park_before_hijack()
        try:
            h.call_routine("AILair_Script", limit=60000)
        finally:
            for bank, addr in hooks:
                h.pyboy.hook_deregister(bank, addr)

        self.assertEqual(
            order,
            [
                "RogueAwardCredits3",
                "DisplayTextID",
                "RogueResetRunState",
                "SaveGameData",
                "AIVictoryCredits",
                "SaveGameData",
                "WaitForTextScrollButtonPress",
                "Init",
            ],
        )
        by = dict(zip(range(len(snaps)), snaps))
        award, _text, reset, save1, credits, save2, _wait, init = (by[i] for i in range(8))

        # The battle bookkeeping is closed before anything else happens.
        self.assertEqual(award["trainer_battle"], 0)
        self.assertEqual(award["script"], AILAIR_STATE_DONE)
        # EVENT_AI_DEFEATED is set before the reset, and the first save
        # already holds the defeat, the reset party and no postgame flag.
        self.assertEqual(reset["ai_defeated"], 1)
        self.assertEqual(save1["ai_defeated"], 1)
        self.assertEqual(save1["post_game"], 0)
        self.assertEqual(save1["party_count"], 0)
        # Credits add no Hall of Fame team.
        self.assertEqual(credits["hof_teams"], hof_teams_before)
        # EVENT_POST_GAME is set after the credits and before the second save.
        self.assertEqual(credits["post_game"], 0)
        self.assertEqual(save2["post_game"], 1)
        self.assertEqual(init["hof_teams"], hof_teams_before)


class PostgameFacilityStateTest(_EventHelpers):
    SENTINEL = 0x12

    def _music_after_override(self, map_name: str) -> int:
        h = self.harness
        assert h is not None
        h.write8("hCurMap", self.maps[map_name])
        h.write8("wMapMusicSoundID", self.SENTINEL)
        h.park_before_hijack()
        h.call_routine("OverrideFinaleFacilityMusic")
        return h.read8("wMapMusicSoundID")

    def test_postgame_drops_the_crisis_music_on_every_facility_map(self) -> None:
        self._set_event("EVENT_OAK_CHAMPION_DEFEATED", True)
        self._set_event("EVENT_AI_DEFEATED", False)
        crisis = {name: self._music_after_override(name) for name in FINALE_MAPS}
        self.assertEqual(len(set(crisis.values())), 1)
        self.assertNotEqual(next(iter(crisis.values())), self.SENTINEL)

        self._set_event("EVENT_AI_DEFEATED", True)
        for name in FINALE_MAPS:
            self.assertEqual(self._music_after_override(name), self.SENTINEL, name)

    def _restores_crisis_actors(self) -> bool:
        h = self.harness
        assert h is not None
        bank, addr = h.symbols.get("SilphCoB1FShouldRestoreCrisisActors.no")
        took_no = []
        h.pyboy.hook_register(bank, addr, lambda _c: took_no.append(True), None)
        try:
            h.park_before_hijack()
            h.call_routine("SilphCoB1FShouldRestoreCrisisActors")
        finally:
            h.pyboy.hook_deregister(bank, addr)
        return not took_no

    def test_postgame_b1f_restores_the_ordinary_actors(self) -> None:
        self._set_event("EVENT_OAK_CHAMPION_DEFEATED", True)
        self._set_event("EVENT_FINAL_BRIEFING_COMPLETE", True)
        self._set_event("EVENT_AI_DEFEATED", False)
        self.assertTrue(self._restores_crisis_actors())
        self._set_event("EVENT_AI_DEFEATED", True)
        self.assertFalse(self._restores_crisis_actors())


class VictorySourceContractTest(unittest.TestCase):
    def _routine(self, path: str, label: str) -> str:
        source = (REPO_ROOT / path).read_text()
        match = re.search(rf"^{re.escape(label)}::?\n(.*?)(?=^\S)", source, re.M | re.S)
        self.assertIsNotNone(match, label)
        return match.group(1)

    def test_ai_victory_credits_skip_the_hall_of_fame_record(self) -> None:
        body = self._routine("engine/movie/hall_of_fame.asm", "AIVictoryCredits")
        for forbidden in ("wNumHoFTeams", "SaveHallOfFameTeams", "FinalTeamArchiveCapture", "AnimateHallOfFame"):
            self.assertNotIn(forbidden, body)
        self.assertTrue(body.rstrip().endswith("farjp HallOfFameCredits"))
        credits = (REPO_ROOT / "engine/movie/credits.asm").read_text()
        self.assertRegex(credits, r"HallOfFamePC:\n\tfarcall AnimateHallOfFame\n(?:;.*\n)*HallOfFameCredits::\n")

    def test_vr_palm_uses_his_ordinary_line_postgame(self) -> None:
        body = self._routine("scripts/SilphCoVR.asm", "SilphCoVR_ProfPalmText")
        self.assertRegex(
            body,
            r"ld hl, \.normalText\n\tCheckEvent EVENT_AI_DEFEATED[^\n]*\n\tjr nz, \.print\n\tCheckEvent EVENT_FINAL_BRIEFING_COMPLETE",
        )

    def test_continue_from_the_ai_lair_goes_to_the_dorm(self) -> None:
        source = (REPO_ROOT / "engine/menus/main_menu.asm").read_text()
        redirect = source.index("cp AI_LAIR")
        self.assertLess(redirect, source.index("ld a, [wNumHoFTeams]", redirect - 200))
        self.assertRegex(source, r"cp AI_LAIR\n\tjr nz, \.notAILair\n\tSetEvent EVENT_POST_GAME\n\tjr \.toDorm")
        self.assertRegex(source, r"\.toDorm\n(?:\t;.*\n)*\tld a, SILPH_CO_DORM\n\tld \[wDestinationMap\], a")


if __name__ == "__main__":
    unittest.main()
