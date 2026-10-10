"""The gym-next lobby's gym choice (player feedback #1, Phase 3, 2026-10-09).

A gym-next lobby offers two unbeaten gyms, latched in wGymChoice: door 1 is
revealed, door 2 hidden until the Psychic is paid; with one unbeaten gym left
the single door is hidden. The badge awarded follows the gym actually entered.
"""
import unittest

from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

MAPS = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
CLASSES = parse_trainer_class_indexes(REPO_ROOT / "constants" / "trainer_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
LATCHED = 1 << RAM["BIT_GYM_CHOICE_LATCHED"]
REVEALED = 1 << RAM["BIT_GYM_CHOICE_REVEALED"]
SHIFT = RAM["GYM_CHOICE_DOOR2_SHIFT"]

# Vanilla Kanto order, the unrolled-lineup fallback (GymMapByBadge).
KANTO_GYMS = ["PEWTER_GYM", "CERULEAN_GYM", "VERMILION_GYM", "CELADON_GYM",
              "FUCHSIA_GYM", "SAFFRON_GYM", "CINNABAR_GYM", "VIRIDIAN_GYM"]
OPEN_DOOR_BLOCK, WALL_BLOCK = 0x08, 0x0C


def decode(raw: list[int]) -> str:
    out = []
    for b in raw:
        if b == 0x50:
            break
        if 0x80 <= b <= 0x99:
            out.append(chr(ord("A") + b - 0x80))
        else:
            out.append({0x7F: " ", 0xE6: "?", 0xF3: "/", 0xE8: "."}.get(b, f"<{b:02x}>"))
    return "".join(out)


class GymChoiceLobbyTest(HarnessTestCase):
    def door2_block(self) -> int:
        h = self.harness
        stride = h.read8("wCurMapWidth") + 6
        return h.read8("wOverworldMap", 3 * stride + 3 + 5)

    def slot_map(self, slot: int) -> int:
        """_PickNextGym's mapping: the lineup leader's gym, or the Kanto default."""
        h = self.harness
        leader = h.read8("wRunGymLineup", slot)
        if not leader:
            return MAPS[KANTO_GYMS[slot]]
        gym_by_leader = {CLASSES[n]: MAPS[g] for n, g in (
            ("BROCK", "PEWTER_GYM"), ("MISTY", "CERULEAN_GYM"), ("LT_SURGE", "VERMILION_GYM"),
            ("ERIKA", "CELADON_GYM"), ("KOGA", "FUCHSIA_GYM"), ("JANINE", "FUCHSIA_GYM"),
            ("SABRINA", "SAFFRON_GYM"), ("BLAINE", "CINNABAR_GYM"), ("GIOVANNI", "VIRIDIAN_GYM"),
            ("FALKNER", "VIOLET_GYM"), ("BUGSY", "AZALEA_GYM"), ("WHITNEY", "GOLDENROD_GYM"),
            ("MORTY", "ECRUTEAK_GYM"), ("CHUCK", "CIANWOOD_GYM"), ("JASMINE", "OLIVINE_GYM"),
            ("PRYCE", "MAHOGANY_GYM"), ("CLAIR", "BLACKTHORN_GYM"))}
        return gym_by_leader[leader]

    def test_a_gym_cycle_offers_two_unbeaten_gyms(self) -> None:
        h = self.harness
        h.boot_to_lobby(battle_count=15)
        choice = h.read8("wGymChoice")
        self.assertTrue(choice & LATCHED, f"nothing latched: {choice:#04x}")
        self.assertFalse(choice & REVEALED)
        door1_slot, door2_slot = choice & 7, (choice >> SHIFT) & 7
        self.assertNotEqual(door1_slot, door2_slot)
        badges = h.read8("wObtainedBadges")
        self.assertFalse(badges & (1 << door1_slot) or badges & (1 << door2_slot), "a beaten gym was offered")
        self.assertEqual(h.read8("wLobbyDoor1StageMap"), self.slot_map(door1_slot))
        self.assertEqual(h.read8("wLobbyDoor2StageMap"), self.slot_map(door2_slot))
        self.assertEqual(self.door2_block(), OPEN_DOOR_BLOCK, "door 2 is walled off")
        h.wait_until(lambda: h.read8("wNumSigns") == 2, "both door signs live", 300)

    def test_the_choice_survives_a_lobby_reroll(self) -> None:
        """Re-entering (or a save) keeps the same two gyms until a badge is won."""
        h = self.harness
        h.boot_to_lobby(battle_count=15)
        before = (h.read8("wGymChoice"), h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap"))
        h.park_before_hijack()
        h.call_routine("SelectAndPatchLobbyExit", limit=60000)
        after = (h.read8("wGymChoice"), h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap"))
        self.assertEqual(before, after)

    def test_one_gym_left_is_a_single_hidden_door(self) -> None:
        h = self.harness
        h.boot_to_lobby(battle_count=15)
        h.write8("wObtainedBadges", 0xFF & ~(1 << 2))      # only slot 2 left
        h.write8("wGymChoice", 0)
        # Both gifts already given, so the bridge cannot take this visit's doors.
        h.write8("wBridgeState", (h.read8("wBridgeState") & 0x3F) | (2 << 6))
        h.park_before_hijack()
        h.call_routine("SelectAndPatchLobbyExit", limit=60000)
        choice = h.read8("wGymChoice")
        self.assertEqual((choice & 7, (choice >> SHIFT) & 7), (2, 2))
        self.assertEqual(h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap"))
        h.park_before_hijack()
        h.call_routine("Lobby_UpdateExitDoor")
        self.assertEqual(self.door2_block(), WALL_BLOCK)

    def sign(self, door: int) -> tuple[str, str]:
        """Run LobbyBuildGymSign directly (jr-@ return stub, IE masked) and read
        both lines the moment it returns. In the game the sign prints them at
        once; through call_routine the lobby keeps running frames afterwards and
        something there rewrites wNameBuffer (a species name, seen 2026-10-09)."""
        h = self.harness
        regs, mem = h.pyboy.register_file, h.pyboy.memory
        saved = {n: getattr(regs, n) for n in ("A", "B", "C", "D", "E", "F", "HL", "PC", "SP")}
        saved_bank, saved_ie = h.read8("hLoadedROMBank"), mem[0xFFFF]
        stub = h.address("wStringBuffer") + 18      # past both sign lines' longest use (17 + '@')
        keep = [mem[stub], mem[stub + 1]]
        bank, address = h.symbols.get("LobbyBuildGymSign")
        mem[stub], mem[stub + 1] = 0x18, 0xFE           # jr @
        mem[0xFFFF] = 0
        h.write8("hLoadedROMBank", bank)
        mem[0x2000] = bank
        sp = (saved["SP"] - 2) & 0xFFFF
        mem[sp], mem[sp + 1] = stub & 0xFF, stub >> 8
        regs.SP, regs.PC, regs.E = sp, address, door
        try:
            for _ in range(10):
                h.pyboy.tick()
                if regs.PC == stub:
                    break
            self.assertEqual(regs.PC, stub, "LobbyBuildGymSign did not return")
            lines = decode(h.read_bytes("wNameBuffer", 20)), decode(h.read_bytes("wStringBuffer", 18))
        finally:
            mem[0xFFFF] = saved_ie
            mem[stub], mem[stub + 1] = keep
            h.write8("hLoadedROMBank", saved_bank)
            mem[0x2000] = saved_bank
            for n, v in saved.items():
                setattr(regs, n, v)
        return lines

    def test_signs_name_the_revealed_door_and_hide_the_other(self) -> None:
        h = self.harness
        h.boot_to_lobby(battle_count=15)
        for slot in range(8):
            h.write8("wRunGymLineup", 0, offset=slot)
        h.write8("wObtainedBadges", 0)
        h.write8("wGymChoice", LATCHED | (5 << SHIFT) | 0)   # Pewter / Saffron
        self.assertEqual(self.sign(1), ("PEWTER GYM", "BROCK/ROCK"))
        self.assertEqual(self.sign(2), ("??? GYM", "???/???"))
        h.write8("wGymChoice", LATCHED | REVEALED | (5 << SHIFT) | 0)
        self.assertEqual(self.sign(2), ("SAFFRON GYM", "SABRINA/PSYCHIC"))

    def test_the_longest_sign_fits(self) -> None:
        """Two 18-column lines: Blackthorn and Lt. Surge are the longest."""
        h = self.harness
        h.boot_to_lobby(battle_count=15)
        h.write8("wObtainedBadges", 0)
        h.write8("wRunGymLineup", CLASSES["CLAIR"], offset=0)
        h.write8("wRunGymLineup", CLASSES["LT_SURGE"], offset=1)
        h.write8("wGymChoice", LATCHED | REVEALED | (1 << SHIFT) | 0)
        self.assertEqual(self.sign(1), ("BLACKTHORN GYM", "CLAIR/DRAGON"))
        line1, line2 = self.sign(2)
        self.assertEqual((line1, line2), ("VERMILION GYM", "LT.SURGE/ELECTRIC"))
        self.assertLessEqual(max(len(line1), len(line2)), 18)

    def test_the_badge_follows_the_gym_entered(self) -> None:
        """Entering door 2's gym points wRogueCurGymBadgeMask at door 2's slot."""
        h = self.harness
        h.boot_to_lobby(battle_count=15)
        for slot in range(8):
            h.write8("wRunGymLineup", 0, offset=slot)
        h.write8("wGymChoice", LATCHED | (6 << SHIFT) | 3)   # Celadon / Cinnabar
        h.write8("wRogueCurGymBadgeMask", 1 << 3)
        h.write8("hCurMap", MAPS["CINNABAR_GYM"])
        h.park_before_hijack()
        h.call_routine("RogueGymChoiceMapLoad")
        self.assertEqual(h.read8("wRogueCurGymBadgeMask"), 1 << 6)
        h.write8("hCurMap", MAPS["CELADON_GYM"])
        h.park_before_hijack()
        h.call_routine("RogueGymChoiceMapLoad")
        self.assertEqual(h.read8("wRogueCurGymBadgeMask"), 1 << 3)
        h.write8("hCurMap", MAPS["ROUTE_3"])                 # anything else: unchanged
        h.park_before_hijack()
        h.call_routine("RogueGymChoiceMapLoad")
        self.assertEqual(h.read8("wRogueCurGymBadgeMask"), 1 << 3)
        h.write8("hCurMap", MAPS["INDIGO_PLATEAU_LOBBY"])


class BridgeReturnsToLobbyTest(HarnessTestCase):
    def test_a_gift_room_exits_back_to_the_lobby(self) -> None:
        """Bridge rooms used to route straight on to the queued gym; with two gym
        doors the choice is made in the lobby, so the gift room leads back there."""
        h = self.harness
        h.boot_to_lobby(encounter_kind=2)              # Debug 2: a bridge visit
        room = h.read8("wLobbyDoor1StageMap")
        gym = h.read8("wRogueMap")
        h.move_tile("up")
        for _ in range(6):
            if h.read8("hCurMap") == room:
                break
            h.pyboy.button_press("down")
            h.tick(40)
            h.pyboy.button_release("down")
            h.tick(6)
        self.assertEqual(h.read8("hCurMap"), room, "did not enter the gift room")
        h.tick(60)
        dests = [entry[3] for entry in h.warp_entries()]
        self.assertIn(MAPS["INDIGO_PLATEAU_LOBBY"], dests, f"exits: {dests}")
        self.assertNotIn(gym, dests, "an exit still leads straight to the gym")

if __name__ == "__main__":
    unittest.main(verbosity=2)
