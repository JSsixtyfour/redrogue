"""Back-to-back gyms (player feedback #2, Phase 4, 2026-10-10).

The badge that brings the count to PAIR_BADGES_A or _B skips the next round's
route: gym A's exits lead to the Reward Room (the route's reward and its
ROUTE_BATTLES credit), then the lobby's single door to the gym the player was
offered and did not take. "A pair is waiting" is derived, not stored: a pair
badge count with BIT_ROGUE_GYM_NEXT clear.
"""
import unittest

from source_constants import parse_map_constants, parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MAPS = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
ROUNDS = parse_rgbds_constants(REPO_ROOT / "constants" / "round_constants.asm")
LATCHED = 1 << RAM["BIT_GYM_CHOICE_LATCHED"]
REVEALED = 1 << RAM["BIT_GYM_CHOICE_REVEALED"]
SHIFT = RAM["GYM_CHOICE_DOOR2_SHIFT"]
PAIR_A, PAIR_B = ROUNDS["PAIR_BADGES_A"], ROUNDS["PAIR_BADGES_B"]
ROUTE_BATTLES, ROUND_BATTLES = ROUNDS["ROUTE_BATTLES"], ROUNDS["ROUND_BATTLES"]
LOBBY, REWARD_ROOM = MAPS["INDIGO_PLATEAU_LOBBY"], MAPS["REWARD_ROOM"]
# constants/toggle_constants.asm: TOGGLE_ROGUE_REWARD_POKEBALL_1..3
REWARD_BALL_TOGGLES = (0x0B, 0x0C, 0x0D)
STAGE_ITEM_TOGGLE = 0x0E  # TOGGLE_STAGE_RANDOM_ITEM: the Reward Room's object 4
EVENT_STEP_FORWARD = 297


def badges(n: int, skip: int = -1) -> int:
    """The lowest n badge slots, never `skip`."""
    mask, slot = 0, 0
    while bin(mask).count("1") < n:
        if slot != skip:
            mask |= 1 << slot
        slot += 1
    return mask


class PairBadgeTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.harness.boot_to_lobby(battle_count=15)

    def fake_gym_warps(self) -> None:
        """A gym's exit table: two warps to the lobby, one elsewhere."""
        h = self.harness
        entries = [13, 4, 0, LOBBY, 13, 5, 0, LOBBY, 0, 4, 2, MAPS["ROUTE_1"]]
        for i, b in enumerate(entries):
            h.write8("wWarpEntries", b, offset=i)
        h.write8("wNumberOfWarps", 3)

    def exit_maps(self) -> list[int]:
        return [entry[3] for entry in self.harness.warp_entries()]

    def award(self, won_slot: int, choice: int, earned: int) -> None:
        h = self.harness
        h.write8("wObtainedBadges", earned)
        h.write8("wGymChoice", choice)
        h.write8("wRogueCurGymBadgeMask", 1 << won_slot)
        self.fake_gym_warps()
        h.park_before_hijack()
        h.call_routine("RogueAwardCurrentGymBadge")
        self.assertEqual(h.read8("wObtainedBadges"), earned | 1 << won_slot)

    def test_winning_door_1s_gym_keeps_door_2s_hidden_unless_revealed(self) -> None:
        h = self.harness
        for reveal in (0, REVEALED):
            with self.subTest(revealed=bool(reveal)):
                earned = badges(PAIR_A - 1, skip=2)    # slots 0-1: neither door's gym
                self.award(2, LATCHED | reveal | 5 << SHIFT | 2, earned)
                self.assertEqual(h.read8("wGymChoice"), LATCHED | reveal | 5 << SHIFT | 5)
                self.assertEqual(self.exit_maps(), [REWARD_ROOM, REWARD_ROOM, MAPS["ROUTE_1"]])

    def test_winning_door_2s_gym_keeps_door_1s_revealed(self) -> None:
        h = self.harness
        earned = badges(PAIR_B - 1, skip=6)    # slots 0-4: neither door's gym
        self.award(6, LATCHED | 6 << SHIFT | 7, earned)
        self.assertEqual(h.read8("wGymChoice"), LATCHED | REVEALED | 7 << SHIFT | 7)
        self.assertEqual(self.exit_maps(), [REWARD_ROOM, REWARD_ROOM, MAPS["ROUTE_1"]])

    def test_any_other_badge_clears_the_choice_and_keeps_the_exits(self) -> None:
        h = self.harness
        for count in range(1, 8):
            if count in (PAIR_A, PAIR_B):
                continue
            with self.subTest(badges_after=count):
                earned = badges(count - 1, skip=7)
                self.award(7, LATCHED | 7 << SHIFT, earned)  # door 2's gym won
                self.assertEqual(h.read8("wGymChoice"), 0)
                self.assertEqual(self.exit_maps(), [LOBBY, LOBBY, MAPS["ROUTE_1"]])

    def test_a_reload_of_gym_a_still_exits_to_the_reward_room(self) -> None:
        """Continue (or any reload) rebuilds the gym's warps from its map data."""
        h = self.harness
        h.write8("hCurMap", MAPS["PEWTER_GYM"])
        cases = (
            (badges(PAIR_A), False, True),       # waiting for the Reward Room
            (badges(PAIR_B), False, True),
            (badges(PAIR_A), True, False),       # Reward Room done: gym B next
            (badges(PAIR_A - 1), False, False),  # not a pair count
            (badges(PAIR_A + 1), False, False),
        )
        for earned, gym_next, patched in cases:
            with self.subTest(badges=bin(earned).count("1"), gym_next=gym_next):
                h.write8("wObtainedBadges", earned)
                flags = h.read8("wRogueFlagsBitfield") & ~1
                h.write8("wRogueFlagsBitfield", flags | int(gym_next))
                self.fake_gym_warps()
                h.park_before_hijack()
                h.call_routine("RoguePairMapLoad")
                want = REWARD_ROOM if patched else LOBBY
                self.assertEqual(self.exit_maps(), [want, want, MAPS["ROUTE_1"]])
        h.write8("hCurMap", LOBBY)

    def test_the_mid_run_reward_room_rewards_like_a_stage(self) -> None:
        """Run start: a flat level. Mid-run: the stage path, the gym tier of the
        round the credited count is in."""
        h = self.harness

        def level(cur_map: int, earned: int, count: int) -> int:
            h.write8("hCurMap", cur_map)
            h.write8("wObtainedBadges", earned)
            h.write8("wBattleCount", count)
            h.park_before_hijack()
            h.call_routine("GetRewardMonLevel")
            return h.read8("wCurEnemyLevel")

        count = PAIR_A * ROUND_BATTLES + 1 + ROUTE_BATTLES
        start = parse_rgbds_constants(REPO_ROOT / "constants" / "balance_constants.asm", ROUNDS)["STARTER_LEVEL"]
        self.assertEqual(level(REWARD_ROOM, 0, 1), start)
        mid = level(REWARD_ROOM, badges(PAIR_A), count)
        self.assertEqual(mid, level(MAPS["ROUTE_1"], badges(PAIR_A), count))
        self.assertGreater(mid, start)
        h.write8("hCurMap", LOBBY)

    def test_the_pair_lobby_offers_one_door_and_no_gift(self) -> None:
        """After the Reward Room: gym-next, the kept gym behind a single door, and
        the bridge never takes the pair's lobby even with no gift given yet."""
        h = self.harness
        h.write8("wObtainedBadges", badges(PAIR_A, skip=5))
        h.write8("wGymChoice", LATCHED | 5 << SHIFT | 5)
        h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") | 1)
        h.write8("wBridgeState", h.read8("wBridgeState") & 0x3F)  # no gift given
        h.park_before_hijack()
        h.call_routine("SelectAndPatchLobbyExit", limit=60000)
        self.assertEqual(h.read8("wGymChoice"), LATCHED | 5 << SHIFT | 5)
        door1, door2 = h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")
        self.assertEqual(door1, door2, "a second door")
        self.assertEqual(door1, h.read8("wRogueMap"), "a gift room took the pair's lobby")
        self.assertIn(door1, {v for k, v in MAPS.items() if k.endswith("_GYM")})


class DoorDiceGymChoiceTest(HarnessTestCase):
    """Door Dice on a gym-next lobby forgets a reveal and rolls new gyms, but never
    adds a door: a single-door lobby (a pair's, or the last gym) stays single."""

    def roll(self, choice: int, earned: int, gym_next: bool = True) -> int:
        h = self.harness
        h.write8("wObtainedBadges", earned)
        h.write8("wGymChoice", choice)
        flags = h.read8("wRogueFlagsBitfield") & ~1
        h.write8("wRogueFlagsBitfield", flags | int(gym_next))
        h.write8("wDiceCharges", (h.read8("wDiceCharges") & ~3) | 3)
        h.write8("wBridgeState", (h.read8("wBridgeState") & 0x3F) | (2 << 6))  # no gift this visit
        h.park_before_hijack()
        h.call_routine("RogueItemUseDoorDice", limit=200000)
        return h.read8("wGymChoice")

    def setUp(self) -> None:
        super().setUp()
        h = self.harness
        h.boot_to_lobby(battle_count=15)

        def skip_text(_):  # the "rerolled" box would wait for a button
            r = h.pyboy.register_file
            r.PC = h.pyboy.memory[r.SP] | h.pyboy.memory[r.SP + 1] << 8
            r.SP += 2

        h.register_hook("PrintText", skip_text)

    def test_a_single_door_stays_single_and_hidden(self) -> None:
        h = self.harness
        earned = badges(PAIR_A, skip=5)
        seen = set()
        for _ in range(6):
            choice = self.roll(LATCHED | REVEALED | 5 << SHIFT | 5, earned)
            door1, door2 = choice & 7, (choice >> SHIFT) & 7
            self.assertEqual(door1, door2, f"a second door: {choice:#04x}")
            self.assertTrue(choice & LATCHED)
            self.assertFalse(choice & REVEALED, "the reveal survived the reroll")
            self.assertFalse(earned & 1 << door1, "a beaten gym")
            self.assertEqual(h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap"))
            seen.add(door1)
        self.assertGreater(len(seen), 1, "the reroll never moved the gym")

    def test_two_doors_stay_two(self) -> None:
        choice = self.roll(LATCHED | REVEALED | 5 << SHIFT | 4, badges(2, skip=4))
        self.assertTrue(choice & LATCHED)
        self.assertFalse(choice & REVEALED)
        self.assertNotEqual(choice & 7, (choice >> SHIFT) & 7)

    def test_a_route_visit_latches_nothing(self) -> None:
        self.assertEqual(self.roll(0, badges(2), gym_next=False), 0)


class PairRewardRoomTest(HarnessTestCase):
    def test_the_reward_room_stands_in_for_the_skipped_route(self) -> None:
        h = self.harness
        h.boot_to_lobby(battle_count=15)
        count = PAIR_A * ROUND_BATTLES + 1                 # just after gym A's leader
        h.write8("wObtainedBadges", badges(PAIR_A, skip=5))
        h.write8("wGymChoice", LATCHED | 5 << SHIFT | 5)
        h.write8("wBattleCount", count)
        h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") & ~1)
        item_flags = h.read8("wToggleableObjectFlags", STAGE_ITEM_TOGGLE // 8)  # as if picked up
        h.write8("wToggleableObjectFlags", item_flags | 1 << STAGE_ITEM_TOGGLE % 8, offset=STAGE_ITEM_TOGGLE // 8)
        for toggle in REWARD_BALL_TOGGLES:                  # as if shown by the last route
            byte = h.read8("wToggleableObjectFlags", toggle // 8)
            h.write8("wToggleableObjectFlags", byte & ~(1 << toggle % 8), offset=toggle // 8)
        # Door 1's warp stands in for gym A's patched exit: a direct warp to the
        # Reward Room's first warp (the lobby patched it to a concrete map on entry).
        warps = h.warp_entries()
        door1 = [i for i, e in enumerate(warps) if e[:2] == [11, 7]]
        self.assertTrue(door1, warps)
        for i in door1:
            h.write8("wWarpEntries", 0, offset=4 * i + 2)
            h.write8("wWarpEntries", REWARD_ROOM, offset=4 * i + 3)
        menu = h.hook_flag("RogueRewardMenu")
        h.move_tile("up")
        for _ in range(6):
            if h.read8("hCurMap") == REWARD_ROOM:
                break
            h.pyboy.button_press("down")
            h.tick(40)
            h.pyboy.button_release("down")
            h.tick(6)
        self.assertEqual(h.read8("hCurMap"), REWARD_ROOM, "did not enter the Reward Room")
        h.tick(30)
        self.assertEqual(h.read8("wBattleCount"), count + ROUTE_BATTLES, "route credit")
        self.assertTrue(h.read8("wRogueFlagsBitfield") & 1, "gym-next not set")
        self.assertEqual(h.read8("wLobbyDoor1StageMap"), LOBBY)
        self.assertEqual(h.read8("wLobbyDoor2StageMap"), LOBBY)
        self.assertEqual(h.read8("wGymChoice"), LATCHED | 5 << SHIFT | 5, "the kept gym")
        for toggle in REWARD_BALL_TOGGLES:
            self.assertTrue(h.read8("wToggleableObjectFlags", toggle // 8) & 1 << toggle % 8,
                            f"reward ball toggle {toggle:#04x} still shown")
        self.assertFalse(h.read8("wToggleableObjectFlags", STAGE_ITEM_TOGGLE // 8) & 1 << STAGE_ITEM_TOGGLE % 8,
                         "the skipped route's item ball is not shown")
        self.assertEqual(h.read8("wNumSprites"), 4)
        # The vendor's menu is the reward: it opens once the entry walk ends
        # (EVENT_STEP_FORWARD, re-armed on entry, is set when it closes).
        self.assertFalse(h.read8("wEventFlags", EVENT_STEP_FORWARD // 8) & 1 << EVENT_STEP_FORWARD % 8)
        h.wait_until(lambda: menu["count"], "the reward vendor's menu", 600)
        exits = [e for e in h.warp_entries() if e[3] == 0xFE]  # ROGUE_MAP: via wLobbyDoorNStageMap
        self.assertEqual(len(exits), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
