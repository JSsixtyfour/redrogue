"""Endless mode checkpoint G: levels past 100 (ENDLESS_MODE_CHECKPOINT_G.md).

The player stops at MAX_LEVEL (235), enemies at ENEMY_MAX_LEVEL (255), and the
wild-area boss at the player's cap. Every test drives the real routine at a
level the original game never reached, where an 8-bit level computation used to
wrap: the crit's level doubling (>= 128), Psywave's 1.5 x level (a hang at
171-172), curated movesets (none matched above 110), the boss's OW_POKEMON
level byte (>= 128 fought at level - 128), Pay Day (>= 128) and obedience.

Every ROM test boots the lobby and runs inside isolated_routine_calls, which
restores the whole machine on exit. Registers b/c/d/e/hl that a routine reads
are set in a hook on its entry: call_routine's bank trampoline owns b and hl.
"""
import unittest

from routine_session import isolated_routine_calls
from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_move_tutor_prices import return_from_call
from test_smoke import HarnessTestCase, REPO_ROOT

CONST = REPO_ROOT / "constants"
BATTLE = parse_rgbds_constants(CONST / "battle_constants.asm")
MAX_LEVEL = BATTLE["MAX_LEVEL"]
ENEMY_MAX_LEVEL = BATTLE["ENEMY_MAX_LEVEL"]
MOVES = parse_rgbds_constants(CONST / "move_constants.asm")
SPECIES = parse_rgbds_constants(CONST / "pokemon_constants.asm")
SPAN = 72
ROUND_BATTLES = 8


def damage(level: int, crit: bool, power: int, attack: int, defense: int) -> int:
    """CalculateDamage from an empty wDamage: the level doubled for a crit, then
    (2L/5 + 2) * power * attack / defense / 50, capped at 997, plus 2."""
    level *= 2 if crit else 1
    q = ((2 * level // 5 + 2) * power * attack // defense) // 50
    return min(q, 997) + 2


class EndlessLevelsTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.harness.boot_to_lobby()
        self.session = isolated_routine_calls(self.harness)
        self.session.__enter__()

    def tearDown(self) -> None:
        try:
            self.session.__exit__(None, None, None)
        finally:
            self.harness.close()

    def read16(self, label: str) -> int:
        return self.harness.read8(label) << 8 | self.harness.read8(label, offset=1)

    def entry(self, label: str, **registers):
        """Set registers on the callee's own entry, then call it."""
        h = self.harness

        def at_entry(*_args) -> None:
            for name, value in registers.items():
                setattr(h.pyboy.register_file, name, value)

        h.register_hook(label, at_entry)
        try:
            h.call_routine(label)
        finally:
            h.unregister_hook(label, at_entry)

    # -- B1: critical hits ---------------------------------------------

    def test_crit_doubles_the_level_in_16_bits(self) -> None:
        h = self.harness
        h.write8("hWhoseTurn", 0)
        h.write8("wPlayerMoveEffect", 0)
        power, attack, defense = 80, 150, 100
        for level in (50, 100, 127, 128, 150, 200, 255):
            for crit in (False, True):
                h.write8("wCriticalHitOrOHKO", int(crit))
                h.write8("wDamage", 0)
                h.write8("wDamage", 0, offset=1)
                self.entry("CalculateDamage", B=attack, C=defense, D=power, E=level)
                self.assertEqual(self.read16("wDamage"), damage(level, crit, power, attack, defense),
                                 (level, crit))

    def test_a_high_level_crit_always_beats_a_normal_hit(self) -> None:
        h = self.harness
        h.write8("hWhoseTurn", 0)
        h.write8("wPlayerMoveEffect", 0)
        for level in (130, 180, 255):
            got = []
            for crit in (0, 1):
                h.write8("wCriticalHitOrOHKO", crit)
                h.write8("wDamage", 0)
                h.write8("wDamage", 0, offset=1)
                self.entry("CalculateDamage", B=100, C=100, D=60, E=level)
                got.append(self.read16("wDamage"))
            self.assertGreater(got[1], got[0], f"level {level}: crit {got[1]} vs {got[0]}")

    # -- B2: Psywave ---------------------------------------------------

    def psywave(self, level: int, *, enemy: bool) -> int:
        """One Psywave through the real special-damage dispatch; the hook on the
        damage application returns before any HP or screen work."""
        h = self.harness
        if enemy:
            h.write8("wEnemyMonLevel", level)
            h.write8("wEnemyMoveNum", MOVES["PSYWAVE"])
            start, apply = "ApplyAttackToPlayerPokemon.specialDamage", "ApplyDamageToPlayerPokemon"
        else:
            h.write8("wBattleMonLevel", level)
            h.write8("wPlayerMoveNum", MOVES["PSYWAVE"])
            start, apply = "ApplyAttackToEnemyPokemon.specialDamage", "ApplyDamageToEnemyPokemon"
        h.write8("wDamage", 0xEE)
        h.write8("wDamage", 0xEE, offset=1)
        seen = {}

        def at_apply(*_args) -> None:
            seen["damage"] = self.read16("wDamage")
            return_from_call(h)

        h.register_hook(apply, at_apply)
        try:
            h.call_routine(start, limit=20000)       # the old roll never returned at 171-172
        finally:
            h.unregister_hook(apply, at_apply)
        self.assertIn("damage", seen, f"Psywave at {level} never applied damage")
        return seen["damage"]

    def test_psywave_terminates_and_stays_in_range_at_every_level(self) -> None:
        for enemy in (False, True):
            for level in (100, 170, 171, 172, 200, 255):
                cap = level + level // 2
                for _ in range(4):
                    dmg = self.psywave(level, enemy=enemy)
                    self.assertGreaterEqual(dmg, 1, (enemy, level))
                    self.assertLessEqual(dmg, cap, (enemy, level))

    # -- B3: curated movesets above 110 ----------------------------------

    def test_curated_sets_still_match_above_110(self) -> None:
        h = self.harness
        classes = parse_trainer_class_indexes(CONST / "trainer_constants.asm")
        h.write8("wEndlessDepth", 4)
        h.write8("wBattleCount", 1)                 # global round 37: a leader well past 110
        counts = {"entered": 0, "failed": 0}

        def entered(*_args) -> None:
            counts["entered"] += 1

        def failed(*_args) -> None:
            counts["failed"] += 1

        h.register_hook("PartyGenApplySetMovesetMask.recordPasses", entered)
        h.register_hook("PartyGenApplySetMovesetMask.recordFail", failed)
        try:
            h.write8("wTrainerClass", classes["BROCK"])
            h.write8("wTrainerNo", 22)
            h.call_routine("ReadTrainer", limit=4000)
        finally:
            h.unregister_hook("PartyGenApplySetMovesetMask.recordPasses", entered)
            h.unregister_hook("PartyGenApplySetMovesetMask.recordFail", failed)
        count = h.read8("wEnemyPartyCount")
        levels = [h.read8("wEnemyMon1Level", offset=i * (h.address("wEnemyMon2") - h.address("wEnemyMon1")))
                  for i in range(count)]
        self.assertGreater(min(levels), 110, levels)
        self.assertGreater(counts["entered"] - counts["failed"], 0,
                           f"no curated set matched a level-{max(levels)} leader team")

    # -- the wild-area boss ----------------------------------------------

    def boss_level(self, depth: int, count: int) -> int:
        h = self.harness
        h.write8("wEndlessDepth", depth)
        h.write8("wBattleCount", count)
        h.call_routine("PCGetBossLevel")
        return h.read8("wCurEnemyLevel")

    def test_boss_level_stops_at_the_player_cap(self) -> None:
        # HARD (0%): the boss's funnel level saturates past 235, so the cap is
        # what stops it. NORMAL's -10% leaves it at 230, under the cap.
        self.harness.set_difficulty("HARD")
        self.assertEqual(self.boss_level(255, 76), MAX_LEVEL)
        self.assertLessEqual(self.boss_level(0, 70), 100, "the original circuit is unchanged")

    def engage(self, species: int, stored: int) -> int:
        """EngageMapTrainer for sprite 1 holding (species, stored level byte)."""
        h = self.harness
        h.write8("wMapSpriteExtraData", species)
        h.write8("wMapSpriteExtraData", stored, offset=1)
        h.write8("hActiveSpriteIndex", 1)
        h.call_routine("EngageMapTrainer")
        return h.read8("wEngagedTrainerSet")

    def test_boss_above_127_engages_at_its_real_level(self) -> None:
        h = self.harness
        boss = SPECIES["ONIX"]
        for depth, count in ((3, 40), (6, 1), (255, 76)):
            level = self.boss_level(depth, count)
            self.assertGreater(level, 127, (depth, count))
            h.write8("wRoguePokemon1", boss)
            h.write8("wRoguePokemonForm1", 0)
            got = self.engage(boss, (level & 0x7F) | 0x80)
            self.assertEqual(got, level, f"boss at {level} engaged as {got}")
            # Not the staged boss's species: the map byte is all there is.
            self.assertEqual(self.engage(SPECIES["MEWTWO"], (level & 0x7F) | 0x80), level & 0x7F)
            # The boss's species but another level: its own byte is kept.
            other = (level + 5) & 0x7F
            self.assertEqual(self.engage(boss, other | 0x80), other)

    # -- the player's side -------------------------------------------------

    def test_pay_day_carries_past_level_127(self) -> None:
        h = self.harness

        def skip_text(*_args) -> None:
            return_from_call(h)

        h.register_hook("PrintText", skip_text)
        try:
            for level, want in ((100, [0, 0x02, 0x00]), (200, [0, 0x04, 0x00]), (MAX_LEVEL, [0, 0x04, 0x70])):
                h.write8("hWhoseTurn", 0)
                h.write8("wBattleMonLevel", level)
                h.call_routine("PayDayEffect_")
                self.assertEqual(h.read_bytes("wPayDayMoney", 3), want, level)
        finally:
            h.unregister_hook("PrintText", skip_text)

    def test_traded_mons_up_to_the_cap_obey(self) -> None:
        h = self.harness
        h.write8("wPlayerMonNumber", 0)
        h.write8("wPartyMon1OTID", h.read8("wPlayerID") ^ 0xFF)   # a traded mon
        for level in (101, 200, MAX_LEVEL):
            h.write8("wBattleMonLevel", level)
            h.call_routine("CheckForDisobedience")
            self.assertFalse(h.last_call_registers["F"] & 0x80, f"level {level} disobeyed")


if __name__ == "__main__":
    unittest.main()
