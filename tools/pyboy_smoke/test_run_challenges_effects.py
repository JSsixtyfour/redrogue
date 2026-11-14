"""Run challenge effects with NO witch accepted: each run bit alone must be enough.

Where a witch twin exists the effect code is shared (the run bit sits beside the
witch test), so these pin the new run-only sites and the run/witch stacking.
Runs inside isolated_routine_calls, which restores the machine on exit.
"""
from routine_session import isolated_routine_calls
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
ROUND_BATTLES = parse_rgbds_constants(REPO_ROOT / "constants" / "round_constants.asm")["ROUND_BATTLES"]


def bcd_bytes(value: int) -> list[int]:
    digits = f"{value:06d}"
    return [int(digits[2 * i:2 * i + 2], 16) for i in range(3)]


def bcd_value(data: list[int]) -> int:
    return int("".join(f"{b:02x}" for b in data))


class RunChallengeEffectsTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        h = self.harness
        h.boot_to_lobby()
        self.session = isolated_routine_calls(h)
        self.session.__enter__()
        flags = h.read8("wRogueFlagsBitfield")
        h.write8("wRogueFlagsBitfield", flags & ~(1 << RAM["BIT_WITCH_ACCEPTED"]))
        self.choose()

    def tearDown(self) -> None:
        try:
            self.session.__exit__(None, None, None)
        finally:
            super().tearDown()

    def choose(self, *ids: int) -> None:
        mask = sum(1 << i for i in ids)
        self.harness.write8("wRunChallenges", mask & 0xFF)
        self.harness.write8("wRunChallenges", mask >> 8, offset=1)

    def test_less_money_takes_a_quarter_of_the_payout(self) -> None:
        h = self.harness
        for total in (0, 4, 7, 100, 1000, 2503, 99999):
            for on in (False, True):
                with self.subTest(total=total, on=on):
                    self.choose(*([RAM["RUN_CH_LESS_MONEY"]] if on else []))
                    h.write8("wMoneyMatchState", 0)
                    for i, b in enumerate(bcd_bytes(total)):
                        h.write8("wAmountMoneyWon", b, offset=i)
                    h.call_routine("WitchApplyMoneyEffects", limit=200000)
                    got = bcd_value(h.read_bytes("wAmountMoneyWon", 3))
                    self.assertEqual(got, total - total // 4 if on else total)

    def test_pricier_items_add_a_quarter_before_the_discount(self) -> None:
        h = self.harness
        discount = 1 << (RAM["PRIZE_CHEAP_ITEMS"] - 9)
        for earned in (False, True):
            h.write8("wWitchPrizesEarned", discount if earned else 0, offset=1)
            for on in (False, True):
                for total in (0, 3, 10, 250, 1500, 99999):
                    with self.subTest(earned=earned, on=on, total=total):
                        self.choose(*([RAM["RUN_CH_PRICIER_ITEMS"]] if on else []))
                        for i, b in enumerate(bcd_bytes(total)):
                            h.write8("hMoney", b, offset=i)
                        h.call_routine("RogueWitchDiscountBuyPrice")
                        want = total + total // 4 if on else total
                        if earned:
                            want -= want // 10
                        self.assertEqual(bcd_value(h.read_bytes("hMoney", 3)), want)

    def test_turn_limit_counts_down_from_six_plus_round_beside_a_witch_party_limit(self) -> None:
        h = self.harness
        h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") | (1 << RAM["BIT_WITCH_ACCEPTED"]))
        h.write8("wWitchChallenge", RAM["CHALLENGE_PARTY_LIMIT"])
        h.write8("wPartyLimit", 4)                    # the UNION a witch turn limit would overwrite
        self.choose(RAM["RUN_CH_TURN_LIMIT"])
        for rnd in (0, 1, 5, 8):
            with self.subTest(round=rnd):
                h.write8("wBattleCount", rnd * ROUND_BATTLES + 3)
                h.call_routine("WitchInitTurnLimit")
                self.assertEqual(h.read8("wRunTurnsLeft"), 6 + rnd)
                self.assertEqual(h.read8("wPartyLimit"), 4, "the witch's party limit was clobbered")
        # The countdown: every turn with turns left only decrements (no drain, no text).
        for left in (2, 1):
            h.write8("wLinkState", 0)
            h.write8("wRunTurnsLeft", left + 1)
            h.call_routine("HandleTurnLimitDrain", limit=200000)
            self.assertEqual(h.read8("wRunTurnsLeft"), left)
            self.assertEqual(h.read8("wPartyLimit"), 4)

    def test_full_parties_never_shrink_a_team(self) -> None:
        h = self.harness
        sizes = {False: set(), True: set()}
        h.write8("wMoneyMatchState", 0)
        for on in (False, True):
            self.choose(*([RAM["RUN_CH_FULL_PARTIES"]] if on else []))
            for seed in range(40):
                h.write8("wBattleCount", ROUND_BATTLES + 1)           # a normal route trainer
                h.write8("wEndlessDepth", 0)
                h.call_routine("RogueBattleRound")
                h.call_routine("GetRandRoster", limit=200000)
                sizes[on].add(h.read8("wEnemyPartyCount"))
                h.pyboy.memory[0xFF04] = seed & 0xFF                  # DIV: perturb the RNG a little
        self.assertGreater(len(sizes[False]), 1, "no shrink seen without the challenge; the test is vacuous")
        self.assertEqual(len(sizes[True]), 1, f"sizes with FULL PARTIES: {sorted(sizes[True])}")
        self.assertEqual(sizes[True], {max(sizes[False])})
