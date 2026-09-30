"""Estimator-vs-execution differential (AI_BACKLOG L3).

AIEstimateDamage / AIEstimatePlayerDamage claim to report the engine's own
MAXIMUM ordinary (non-crit) roll for one hit. This checks that claim against
real battle turns: each side's move is forced at Execute*Move entry, HP is held
high so nobody faints, and the damage the engine actually dealt (wDamage at
ApplyDamageTo*Pokemon, while the crit flag is live) must sit inside the estimate's roll window:

    fixed-damage moves (Seismic Toss, Dragon Rage, Super Fang): exactly equal
    everything else: est * 217 // 255 <= dealt <= est

Crits are skipped and misses never reach the apply step (the estimator deliberately excludes both). A
multi-hit move's wDamage is its last hit, which is one ordinary hit.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]

FIXED = {"SEISMIC_TOSS", "DRAGON_RAGE", "SUPER_FANG"}
SAMPLES = 3
HELD_HP = 999


class AIDamageDifferentialTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.rom = (ROOT / "pokeblue_debug.gbc").read_bytes()

    def tearDown(self):
        self.h.close()

    def mon(self, name, moves):
        return {"species": self.species[name], "level": 50,
                "moves": [self.moves[m] for m in moves]}

    def word(self, label, value):
        self.h.write8(label, value >> 8)
        self.h.write8(label, value & 255, offset=1)

    def read_word(self, label):
        return int.from_bytes(bytes(self.h.read_bytes(label, 2)), "big")

    def load_move(self, block, name):
        bank, address = self.h.symbols.get("Moves")
        offset = bank * 0x4000 + address - 0x4000 + (self.moves[name] - 1) * 6
        for index, value in enumerate(self.rom[offset:offset + 6]):
            self.h.write8(block, value, offset=index)

    def run_differential(self, side, names, setup=lambda: None):
        h = self.h
        h.inject_fight2_spec([self.mon("GYARADOS", ["SPLASH"])],
                             [self.mon("TAUROS", ["TACKLE"])],
                             trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=2)
        h.boot_fight2(seed=1)
        if side == "enemy":
            block, routine, target_hp = "wEnemyMoveNum", "AIEstimateDamage", "wBattleMonHP"
            selected, entry, apply = ["wEnemySelectedMove"], "ExecuteEnemyMove", "ApplyDamageToPlayerPokemon"
        else:
            block, routine, target_hp = "wPlayerMoveNum", "AIEstimatePlayerDamage", "wEnemyMonHP"
            # FIGHT2 is a test battle: GetCurrentMove reads the test-battle copy.
            selected = ["wPlayerSelectedMove", "wTestBattlePlayerSelectedMove"]
            entry, apply = "ExecutePlayerMove", "ApplyDamageToEnemyPokemon"

        estimates = {}
        for name in names:
            h.park_before_hijack()
            self.word(target_hp, HELD_HP)  # Super Fang halves CURRENT HP
            setup()
            self.load_move(block, name)
            h.call_routine(routine, limit=120)
            estimates[name] = self.read_word("wAIDamageEstimate")

        samples = {name: [] for name in names}
        by_id = {self.moves[name]: name for name in names}
        state = {"turn": 0, "first_hit": False}

        def at_entry():
            name = names[state["turn"] % len(names)]
            state["turn"] += 1
            state["first_hit"] = True
            for label in selected:
                h.write8(label, self.moves[name])
            self.word("wBattleMonHP", HELD_HP)
            self.word("wEnemyMonHP", HELD_HP)
            setup()

        def at_apply():
            # Final damage, with the crit flag still live (its text prints later).
            # First hit only: a multi-hit crit keeps its damage on later hits
            # after the crit text has already cleared the flag.
            name = by_id.get(h.read8(block))
            if name is None or not state["first_hit"]:
                return
            state["first_hit"] = False
            if h.read8("wCriticalHitOrOHKO"):
                return
            samples[name].append(self.read_word("wDamage"))

        h.hook_flag("TrainerAI", action=lambda: h.write8("wAICount", 0))
        entries = h.hook_flag(entry, action=at_entry)
        h.hook_flag(apply, action=at_apply)
        h.hook_flag("DisplayBattleMenu", action=lambda:
                    h.write8("wBattleAndStartSavedMenuItem", 0))
        for _ in range(9000):
            if all(len(v) >= SAMPLES for n, v in samples.items() if estimates[n]):
                break
            h.tap("a", 1)
            h.tick(8)
        print(f"\n{side} entries={entries['count']} estimates={estimates} dealt={samples}")

        for name in names:
            est, dealt = estimates[name], samples[name]
            with self.subTest(side=side, move=name):
                if est == 0:
                    # Immunity: nothing lands, or a zero reaches the apply step.
                    self.assertEqual([v for v in dealt if v], [],
                                     f"{name}: est 0 but dealt {dealt}")
                    continue
                self.assertGreaterEqual(len(dealt), SAMPLES, f"{name}: only {dealt}")
                low = est if name in FIXED else est * 217 // 255
                for value in dealt:
                    self.assertTrue(low <= value <= est,
                                    f"{name}: dealt {value} outside [{low}, {est}]")

    # Tauros (Normal) into Gyarados (Water/Flying): STAB, 4x, 2x, 0.5x, 0x.
    def test_enemy_damaging_moves(self):
        self.run_differential("enemy", ["TACKLE", "THUNDERBOLT", "ROCK_SLIDE", "SURF",
                                        "EARTHQUAKE"])

    def test_enemy_fixed_and_multihit_moves(self):
        self.run_differential("enemy", ["SEISMIC_TOSS", "DRAGON_RAGE", "SUPER_FANG",
                                        "DOUBLE_KICK", "BODY_SLAM"])

    # Gyarados into Tauros: STAB Surf, 2x Double Kick, 0x Lick, neutral others.
    def test_player_damaging_moves(self):
        self.run_differential("player", ["SURF", "DOUBLE_KICK", "LICK", "THUNDERBOLT",
                                         "EARTHQUAKE"])

    def test_player_fixed_and_multihit_moves(self):
        self.run_differential("player", ["SEISMIC_TOSS", "DRAGON_RAGE", "SUPER_FANG",
                                         "BODY_SLAM", "ROCK_SLIDE"])


    # Reflect and Light Screen double the defending stat inside the damage vars.
    def test_enemy_moves_into_player_screens(self):
        battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
        screens = (1 << battle["HAS_REFLECT_UP"]) | (1 << battle["HAS_LIGHT_SCREEN_UP"])

        def raise_screens():
            self.h.write8("wPlayerBattleStatus3",
                          self.h.read8("wPlayerBattleStatus3") | screens)

        self.run_differential("enemy", ["TACKLE", "THUNDERBOLT", "BODY_SLAM"],
                              setup=raise_screens)


if __name__ == "__main__":
    unittest.main()
