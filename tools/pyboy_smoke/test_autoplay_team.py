"""The stronger player's team judgment (autoplay_team.py): planted reward
offers and a real giver's gift list are read and ranked on merit."""
import autoplay
from source_constants import parse_map_constants, parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

SPECIES = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")


class AutoplayTeamTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        autoplay.boot(self.harness, seed=1)
        self.agent = autoplay.AutoplayAgent(self.harness, seed=1, player="strong")
        self.judge = self.agent.judge

    def offer(self, *names: str) -> None:
        for i, name in enumerate(names):
            self.harness.write8("wRoguePokemon1", SPECIES[name], offset=i)
            self.harness.write8("wRoguePokemonForm1", 0, offset=i)

    def test_the_strongest_reward_is_taken(self) -> None:
        self.offer("CATERPIE", "DRAGONITE", "PIDGEY")
        self.harness.write8("wRogueFlagsBitfield", self.harness.read8("wRogueFlagsBitfield") & ~0x04)
        self.assertEqual(self.judge.reward_choice(), 1)

    def test_a_losing_trade_is_not_taken(self) -> None:
        self.offer("RATTATA", "CATERPIE", "WEEDLE")  # the trade slot is the best of three weak offers
        self.harness.write8("wRogueFlagsBitfield", self.harness.read8("wRogueFlagsBitfield") | 0x04)
        self.harness.write8("wroguenpctradegive", SPECIES["MEWTWO"])
        self.assertNotEqual(self.judge.reward_choice(), 0)

    def test_gifts_are_read_from_the_givers_list(self) -> None:
        maps = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
        self.harness.write8("hCurMap", maps["BILLS_HOUSE"])
        for i, index in enumerate((1, 2, 0)):  # EEVEE, JOLTEON, the fusion special
            self.harness.write8("wGift1", index, offset=i)
        entries = self.judge.gift_entries()
        self.assertEqual([kind for kind, _ in entries], ["MON", "MON", "SPECIAL"])
        self.assertEqual(entries[1][1] & 0xFF, SPECIES["JOLTEON"])
        self.assertEqual(self.judge.gift_choice(), 1)  # Jolteon over Eevee and the special
