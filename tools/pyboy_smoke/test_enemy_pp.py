"""Enemy Pokemon spend PP (engine/battle/enemy_move_pp.asm, decrement_pp.asm):
the enemy's move choice skips moves with no PP and Struggles when none is left,
and DecrementPP takes the enemy's PP from the battle copy and, in a trainer
battle, from its party struct (never while transformed, never for a wild mon)."""
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT
import autoplay

MOVES = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
TRANSFORMED = 1 << parse_rgbds_constants(REPO_ROOT / "constants/battle_constants.asm")["TRANSFORMED"]


class EnemyPPTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        autoplay.boot(self.harness, seed=1)
        h = self.harness
        for label in ("wPlayerBattleStatus1", "wEnemyBattleStatus1"):
            for offset in range(3):
                h.write8(label, 0, offset=offset)
        h.write8("wEnemyDisabledMove", 0)
        h.write8("wLinkState", 0)

    def enemy_moves(self, moves, pp) -> None:
        for i in range(4):
            self.harness.write8("wEnemyMonMoves", moves[i], offset=i)
            self.harness.write8("wEnemyMonPP", pp[i], offset=i)

    def choose(self, battle: int = 1) -> tuple[int, int]:
        self.harness.write8("hIsInBattle", battle)
        self.harness.call_routine("ChooseEnemyMove")
        return self.harness.read8("wEnemySelectedMove"), self.harness.read8("wEnemyMoveListIndex")

    def test_a_move_without_pp_is_never_chosen(self) -> None:
        self.enemy_moves([MOVES["TACKLE"], MOVES["EMBER"], 0, 0], [0, 10, 0, 0])
        for _ in range(12):
            self.assertEqual(self.choose(), (MOVES["EMBER"], 1))

    def test_no_pp_left_means_struggle(self) -> None:
        self.enemy_moves([MOVES["TACKLE"], MOVES["EMBER"], 0, 0], [0, 0, 0, 0])
        self.assertEqual(self.choose()[0], MOVES["STRUGGLE"])

    def test_a_disabled_move_with_pp_does_not_count(self) -> None:
        self.enemy_moves([MOVES["TACKLE"], MOVES["EMBER"], 0, 0], [0, 10, 0, 0])
        self.harness.write8("wEnemyDisabledMove", 0x21)  # slot 2, 1 turn
        self.assertEqual(self.choose()[0], MOVES["STRUGGLE"])

    def test_pp_up_bits_are_not_pp(self) -> None:
        self.enemy_moves([MOVES["TACKLE"], MOVES["EMBER"], 0, 0], [0xC0, 10, 0, 0])
        for _ in range(8):
            self.assertEqual(self.choose()[0], MOVES["EMBER"])

    # ------------------------------------------------------------ DecrementPP

    def decrement(self, *, turn: int, battle: int, slot: int = 2, party_pos: int = 1) -> tuple[int, int]:
        """Spend slot `slot`'s PP for the side whose turn it is; returns the
        (battle copy, party struct) PP afterwards, both starting at 10."""
        h = self.harness
        mon, party, index, selected, number = (
            ("wEnemyMonPP", "wEnemyMon1PP", "wEnemyMoveListIndex", "wEnemySelectedMove", "wEnemyMonPartyPos")
            if turn else
            ("wBattleMonPP", "wPartyMon1PP", "wPlayerMoveListIndex", "wPlayerSelectedMove", "wPlayerMonNumber"))
        stride = h.address("wPartyMon2") - h.address("wPartyMon1")
        h.write8(mon, 10, offset=slot)
        h.write8(party, 10, offset=party_pos * stride + slot)
        h.write8(index, slot)
        h.write8(selected, MOVES["TACKLE"])
        h.write8(number, party_pos)
        h.write8("hWhoseTurn", turn)
        h.write8("hIsInBattle", battle)
        de = h.address(selected)
        h.pyboy.register_file.D, h.pyboy.register_file.E = de >> 8, de & 0xFF
        h.call_routine("DecrementPP")
        return h.read8(mon, offset=slot), h.read8(party, offset=party_pos * stride + slot)

    def test_trainer_enemy_spends_battle_and_party_pp(self) -> None:
        self.assertEqual(self.decrement(turn=1, battle=2), (9, 9))

    def test_wild_enemy_spends_only_its_battle_pp(self) -> None:
        self.assertEqual(self.decrement(turn=1, battle=1), (9, 10))

    def test_transformed_enemy_keeps_its_party_pp(self) -> None:
        self.harness.write8("wEnemyBattleStatus3", TRANSFORMED)
        self.assertEqual(self.decrement(turn=1, battle=2), (9, 10))

    def test_the_players_transform_does_not_stop_the_enemys_party_pp(self) -> None:
        # The pret wiki tutorial read wPlayerBattleStatus3 for both sides here.
        self.harness.write8("wPlayerBattleStatus3", TRANSFORMED)
        self.assertEqual(self.decrement(turn=1, battle=2), (9, 9))

    def test_player_side_is_unchanged(self) -> None:
        self.assertEqual(self.decrement(turn=0, battle=2), (9, 9))
