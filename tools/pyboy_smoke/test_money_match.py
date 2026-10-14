"""Money Match (PROCEDURAL_SUBROOMS_PLAN Phase M).

A Gambler found at a wild area's stage-event hideout (STAGE_EVENT_MONEY_MATCH)
offers a bet: win in few turns for double the prize. These tests cover:

Routines, run directly (PC + `jr @` return stub, IE masked):
  - MoneyMatchApplyPayout: 2B at or under the free turns, 1/16 of 2B less per
    extra turn, floor B/8; a normal battle (bit clear) pays B untouched.
  - WitchApplyMoneyEffects: PRIZE_MONEY's +10% applies on top of the scaled pay.
  - BattleTurnCommitted: counts only while active, saturates at 127.
  - RogueBattleRound: the step is MONEY_MATCH_STEP while active, the round is
    the count's own, and carry is still set as every caller always got it.
  - RogueRosterMixId: a Money Match Gambler takes the route grid row, not
    MIX_GAMBLER; a Gambler's Paradise gambler (bit clear) still gets MIX_GAMBLER.

End to end, in a real Facility (Gambler moved beside the entrance):
  - walking up to him in his line of sight does not start a battle;
  - NO leaves him standing and starts nothing; talking again re-offers;
  - YES starts a battle as route step MONEY_MATCH_STEP with the ordinary AI
    (the themed AI never runs), the win pays the scaled prize, he is gone
    afterwards, wBattleCount is unchanged and the state byte is cleared.
"""

from __future__ import annotations

import io
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import (  # noqa: E402
    parse_map_constants,
    parse_rgbds_constants,
    parse_trainer_class_indexes,
    parse_trainer_constants,
)

ARTIFACTS = ROOT / "tools" / "pyboy_smoke" / "artifacts"

ROUNDS = parse_rgbds_constants(ROOT / "constants/round_constants.asm")
RAM = parse_rgbds_constants(ROOT / "constants/ram_constants.asm", ROUNDS)
MIXES = parse_rgbds_constants(ROOT / "data/trainers/party_specs.asm")
CLASSES = parse_trainer_class_indexes(ROOT / "constants/trainer_constants.asm")
OPPONENTS = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

ACTIVE = 1 << RAM["BIT_MONEY_MATCH_ACTIVE"]
STEP = RAM["MONEY_MATCH_STEP"]
FREE_BUFFER = RAM["MONEY_MATCH_FREE_TURN_BUFFER"]
DECAY = RAM["MONEY_MATCH_DECAY_STEPS"]
ROUND_BATTLES = ROUNDS["ROUND_BATTLES"]
FACILITY_NPC_SLOT = 10          # PFacStageNpc1Header's object slot


def bcd(value: int) -> list[int]:
    digits = f"{value:06d}"
    return [int(digits[i:i + 2], 16) for i in range(0, 6, 2)]


def from_bcd(values) -> int:
    return int("".join(f"{v:02x}" for v in values))


def expected_payout(prize: int, party: int, turns: int) -> int:
    extra = max(0, turns - (party + FREE_BUFFER))
    k = max(1, DECAY - extra)
    return min(prize * k, 999999) // 8


class MoneyMatchRoutineTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.boot_to_lobby()

    def tearDown(self) -> None:
        self.h.close()

    def run_routine(self, label: str, frames: int = 10) -> dict[str, int]:
        """Run `label` to its ret; returns the registers it returned with."""
        h = self.h
        regs = h.pyboy.register_file
        memory = h.pyboy.memory
        saved = {n: getattr(regs, n) for n in ("A", "B", "C", "D", "E", "F", "HL", "PC", "SP")}
        saved_bank = h.read8("hLoadedROMBank")
        stub = h.address("wStringBuffer") + 16
        saved_stub = [memory[stub], memory[stub + 1]]
        saved_ie = memory[0xFFFF]
        bank, address = h.symbols.get(label)
        memory[stub], memory[stub + 1] = 0x18, 0xFE  # jr @
        memory[0xFFFF] = 0
        if bank:
            h.write8("hLoadedROMBank", bank)
            memory[0x2000] = bank
        sp = (saved["SP"] - 2) & 0xFFFF
        memory[sp], memory[sp + 1] = stub & 0xFF, stub >> 8
        regs.SP = sp
        regs.PC = address
        try:
            for _ in range(frames):
                h.pyboy.tick()
                if regs.PC == stub:
                    break
            self.assertEqual(regs.PC, stub, f"{label} did not return (PC ${regs.PC:04X})")
            self.assertEqual(regs.SP, (sp + 2) & 0xFFFF, f"{label} unbalanced the stack")
            return {n: getattr(regs, n) for n in ("A", "B", "C", "D", "E", "F")}
        finally:
            memory[0xFFFF] = saved_ie
            memory[stub], memory[stub + 1] = saved_stub
            h.write8("hLoadedROMBank", saved_bank)
            memory[0x2000] = saved_bank
            for name, value in saved.items():
                setattr(regs, name, value)

    def payout(self, prize: int, party: int, state: int) -> int:
        h = self.h
        for i, v in enumerate(bcd(prize)):
            h.write8("wAmountMoneyWon", v, offset=i)
        h.write8("wEnemyPartyCount", party)
        h.write8("wMoneyMatchState", state)
        h.write8("hActiveSpriteIndex", 0)    # no toggle: skip the hide
        self.run_routine("MoneyMatchApplyPayout")
        return from_bcd(h.read_bytes("wAmountMoneyWon", 3))

    def test_payout_curve(self) -> None:
        prize = 1536
        # N = 4 enemy mons: 5 free turns. The plan's own three examples, then
        # the floor's edges and the saturated counter.
        for turns, want in ((0, 2 * prize), (5, 2 * prize), (6, 2 * prize * 15 // 16),
                            (20, prize // 8), (21, prize // 8), (127, prize // 8)):
            with self.subTest(turns=turns):
                self.assertEqual(self.payout(prize, 4, ACTIVE | turns), want)
                self.assertEqual(want, expected_payout(prize, 4, turns))
        # Rounding is one truncation of B*k/8, not (B/8)*k.
        self.assertEqual(self.payout(1001, 1, ACTIVE | 3), 1001 * 15 // 8)

    def test_normal_battle_untouched(self) -> None:
        self.assertEqual(self.payout(1536, 4, 0), 1536)
        self.assertEqual(self.payout(1536, 4, 5), 1536, "turn bits without the active bit")

    def test_prize_money_stacks_on_top(self) -> None:
        h = self.h
        prize_bit = 1 << (RAM["PRIZE_MONEY"] - 1)
        h.write8("wWitchPrizesEarned", prize_bit)
        h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") & ~(1 << RAM["BIT_WITCH_ACCEPTED"]))
        for i, v in enumerate(bcd(1600)):
            h.write8("wAmountMoneyWon", v, offset=i)
        h.write8("wEnemyPartyCount", 3)
        h.write8("wMoneyMatchState", ACTIVE | 2)
        h.write8("hActiveSpriteIndex", 0)
        self.run_routine("WitchApplyMoneyEffects")
        got = from_bcd(h.read_bytes("wAmountMoneyWon", 3))
        scaled = 3200                                   # 2 x 1600, 2 turns of 4 free
        self.assertEqual(got, scaled + scaled // 10,
                         "PRIZE_MONEY did not apply on top of the Money Match pay")

    def test_beaten_gambler_offers_nothing(self) -> None:
        # A beaten Gambler shown again (the cemetery re-shows per floor) must
        # pass straight to TalkToTrainer's after line: no offer box (it would
        # wait for input and never return here) and no state for the next
        # battle to inherit.
        h = self.h
        won = 1 << RAM["BIT_STAGE_EVENT_MONEY_MATCH_WON"]
        settled = RAM["STAGE_EVENT_PHASE_SETTLED"] << RAM["STAGE_EVENT_PHASE_SHIFT"]
        h.write8("wStageEvent", RAM["STAGE_EVENT_MONEY_MATCH"] | settled | won)
        h.write8("wMoneyMatchState", 0)
        regs = self.run_routine("MoneyMatchTalkGate")
        self.assertFalse(regs["F"] & 0x10, "carry set: the map would skip TalkToTrainer")
        self.assertEqual(h.read8("wMoneyMatchState"), 0)

    def test_win_marks_the_event(self) -> None:
        h = self.h
        settled = RAM["STAGE_EVENT_PHASE_SETTLED"] << RAM["STAGE_EVENT_PHASE_SHIFT"]
        h.write8("wStageEvent", RAM["STAGE_EVENT_MONEY_MATCH"] | settled)
        self.payout(1000, 2, ACTIVE)
        self.assertTrue(h.read8("wStageEvent") & 1 << RAM["BIT_STAGE_EVENT_MONEY_MATCH_WON"])
        h.write8("wStageEvent", RAM["STAGE_EVENT_JOY"] | settled)
        self.payout(1000, 2, 0)
        self.assertFalse(h.read8("wStageEvent") & 1 << RAM["BIT_STAGE_EVENT_MONEY_MATCH_WON"],
                         "an ordinary win marked the event")

    def test_turn_counter(self) -> None:
        h = self.h
        for before, after in ((ACTIVE, ACTIVE | 1), (ACTIVE | 126, ACTIVE | 127),
                              (ACTIVE | 127, ACTIVE | 127), (0, 0), (5, 5)):
            with self.subTest(before=before):
                h.write8("wMoneyMatchState", before)
                self.run_routine("BattleTurnCommitted")
                self.assertEqual(h.read8("wMoneyMatchState"), after)

    def test_step_override(self) -> None:
        h = self.h
        for count in (ROUND_BATTLES * 2 + 1, ROUND_BATTLES * 2 + 6, ROUND_BATTLES * 5):
            h.write8("wBattleCount", count)
            h.write8("wMoneyMatchState", 0)
            plain = self.run_routine("RogueBattleRound")
            h.write8("wMoneyMatchState", ACTIVE | 9)
            money = self.run_routine("RogueBattleRound")
            with self.subTest(count=count):
                self.assertEqual(plain["A"], count % ROUND_BATTLES)
                self.assertEqual(money["B"], plain["B"], "the round must stay the count's own")
                self.assertEqual(money["A"], STEP)
                self.assertTrue(money["F"] & 0x10, "carry no longer set on return")

    def test_mix_row(self) -> None:
        h = self.h
        h.write8("wBattleCount", ROUND_BATTLES * 2 + 6)      # a gym-trainer step
        h.write8("wMoneyMatchState", 0)
        h.write8("wTrainerClass", CLASSES["GAMBLER"])
        self.assertEqual(self.run_routine("RogueRosterMixId")["A"], MIXES["MIX_GAMBLER"])
        h.write8("wMoneyMatchState", ACTIVE)
        money = self.run_routine("RogueRosterMixId")["A"]
        h.write8("wTrainerClass", CLASSES["BUG_CATCHER"])
        route = self.run_routine("RogueRosterMixId")["A"]
        self.assertNotEqual(money, MIXES["MIX_GAMBLER"])
        self.assertEqual(money, route, "Money Match row differs from a route trainer's at step 3")
        h.write8("wMoneyMatchState", 0)
        h.write8("wBattleCount", ROUND_BATTLES * 2 + STEP)
        self.assertEqual(self.run_routine("RogueRosterMixId")["A"], route,
                         "the override row is not the real step-3 row")


class MoneyMatchFacilityTest(unittest.TestCase):
    """Real offer, real battle, real payout, on the Facility."""

    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.h = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.h.close()

    def enter_beside_gambler(self) -> None:
        """Facility with the Gambler two tiles above the entrance tile."""
        h = self.h
        facility = self.maps["PROCEDURAL_FACILITY"]
        lobby = self.maps["INDIGO_PLATEAU_LOBBY"]
        h.boot_to_lobby(battle_count=ROUND_BATTLES + 1, encounter_kind=4)
        h.write8("wStageEvent", RAM["STAGE_EVENT_MONEY_MATCH"])
        h.preload_and_enter_wild_area(facility, "facility")
        h.write8("wLastMap", lobby)
        h.tick(60)
        self.assertEqual(h.read8("wStageEvent") & RAM["STAGE_EVENT_TYPE_MASK"],
                         RAM["STAGE_EVENT_MONEY_MATCH"])
        base = h.address("wMapSpriteExtraData") + (FACILITY_NPC_SLOT - 1) * 2
        self.assertEqual(h.pyboy.memory[base], OPPONENTS["GAMBLER"],
                         "stage NPC slot is not a Gambler trainer")
        # Placement re-reads the hideout on every load: move it to the block
        # above the entrance and re-enter through a self-warp (the
        # test_facility_self_warp mechanism).
        h.write_sram_bytes("sStageEventHideoutX", [9], bank=0)
        h.write_sram_bytes("sStageEventHideoutY", [18], bank=0)
        h.write8("wWarpEntries", 0, offset=2)
        h.write8("wWarpEntries", facility, offset=3)
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the entrance", 600)
        start = h.pyboy.frame_count
        h.pyboy.button_press("down")
        try:
            h.wait_until(lambda: h.read8("hCurMap") == facility
                         and h.read8("wWarpedFromWhichMap") == facility
                         and h.pyboy.frame_count - start > 20, "self-warp", 600)
        finally:
            h.pyboy.button_release("down")
        h.tick(180)
        y, x = h.sprite_positions(FACILITY_NPC_SLOT)[FACILITY_NPC_SLOT - 1]
        self.gambler = (x, y)
        self.assertEqual(self.gambler, (18, 36), "Gambler not where the hideout puts him")
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (18, 39))
        # Two steps up, straight down his line of sight: a sight-4 trainer
        # would engage on the first.
        seen_bit = 1 << RAM["BIT_SEEN_BY_TRAINER"]
        for _ in range(2):
            h.move_tile("up")
            h.tick(30)
            self.assertFalse(h.read8("wMiscFlags") & seen_bit, "the Gambler engaged on sight")
            self.assertEqual(h.read8("hIsInBattle"), 0, "the Gambler engaged on sight")
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (18, 37))

    def gambler_hidden(self) -> bool:
        h = self.h
        table = h.read_bytes("wToggleableObjectList", 64)
        for i in range(0, len(table) - 1, 2):
            if table[i] == 0xFF:
                break
            if table[i] == FACILITY_NPC_SLOT:
                index = table[i + 1]
                return bool(h.read8("wToggleableObjectFlags", offset=index // 8) & 1 << index % 8)
        self.fail("stage NPC slot not in wToggleableObjectList")

    def test_decline_then_win(self) -> None:
        h = self.h
        self.enter_beside_gambler()

        # NO: B answers every prompt and picks NO on the YES/NO box.
        for _ in range(16):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("hIsInBattle"), 0, "declining started a battle")
        h.tap("a", frames=8)                 # talk again: the offer is back
        h.tick(30)
        for _ in range(16):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("hIsInBattle"), 0)
        self.assertEqual(h.read8("wMoneyMatchState"), 0)
        self.assertFalse(self.gambler_hidden())

        battle_count = h.read8("wBattleCount")
        money_before = from_bcd(h.read_bytes("wPlayerMoney", 3))
        seen = {"themed": 0, "step": [], "payout": []}

        def ko(_context) -> None:
            h.write8("wEnemyMonHP", 0)
            h.write8("wEnemyMonHP", 0, offset=1)

        def no_exp(_context) -> None:
            # No EXP, so no level-up or move-learn prompt for the B presses to
            # loop on (B answers NO to "delete a move?" and to "abandon?").
            h.write8("wPartyGainExpFlags", 0)

        def step(_context) -> None:
            seen["step"].append(h.pyboy.register_file.A)

        def themed(_context) -> None:
            seen["themed"] += 1

        def payout(_context) -> None:
            seen["payout"].append((from_bcd(h.read_bytes("wAmountMoneyWon", 3)),
                                   h.read8("wEnemyPartyCount"), h.read8("wMoneyMatchState")))

        hooks = (("MainInBattleLoop", ko), ("GainExperience", no_exp),
                 ("GetRandRoster.stepReady", step),
                 ("AIMoveChoiceModification5", themed), ("MoneyMatchApplyPayout", payout))
        for label, callback in hooks:
            h.register_hook(label, callback)
        try:
            h.tap("a", frames=8)
            for _ in range(40):
                if h.read8("hIsInBattle"):
                    break
                h.tap("a", frames=8)
                h.tick(20)
            self.assertTrue(h.read8("hIsInBattle"), "YES did not start the battle")
            for _ in range(200):
                if not h.read8("hIsInBattle") and h.read8("wMoneyMatchState") == 0 and seen["payout"]:
                    break
                h.tap("b", frames=8)
                h.tick(20)
            h.tick(120)
        finally:
            for label, callback in reversed(hooks):
                h.unregister_hook(label, callback)

        if h.read8("hIsInBattle"):
            pc = h.pyboy.register_file.PC
            where = h.symbols.nearest(h.read8("hLoadedROMBank") if pc >= 0x4000 else 0, pc)
            tiles = h.read_bytes("wTileMap", 360)
            self.fail(f"battle never ended at {where}; steps={seen['step']} "
                      f"payout={seen['payout']} enemyHP={h.read_bytes('wEnemyMonHP', 2)} "
                      f"menu={h.read8('hCurrentMenuItem')} tiles12-17={tiles[240:360]}")
        self.assertEqual(seen["step"], [STEP], "party not rolled as the Money Match step")
        self.assertEqual(seen["themed"], 0, "Gambler's Paradise AI ran in a Money Match")
        self.assertEqual(len(seen["payout"]), 1)
        prize, party, state = seen["payout"][0]
        self.assertTrue(state & ACTIVE, "active bit not set going into the payout")
        want = expected_payout(prize, party, state & 0x7F)
        got = from_bcd(h.read_bytes("wPlayerMoney", 3)) - money_before
        self.assertEqual(got, want, f"paid {got}, expected {want} (B={prize}, N={party}, T={state & 0x7F})")
        self.assertEqual(h.read8("wMoneyMatchState"), 0, "state byte leaked past the battle")
        self.assertEqual(h.read8("wBattleCount"), battle_count, "the Money Match advanced the run")
        self.assertTrue(self.gambler_hidden(), "the Gambler is still on the map after losing")
        self.assertTrue(h.read8("wStageEvent") & 1 << RAM["BIT_STAGE_EVENT_MONEY_MATCH_WON"],
                        "the win was not recorded on the stage event")


if __name__ == "__main__":
    unittest.main()
