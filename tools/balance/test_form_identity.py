"""Form identities must survive the offline model's source ingestion."""

import random
import unittest
from collections import Counter
from unittest.mock import patch

import parse


class FormIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.game = parse.load_all()

    def test_scream_tail_retains_its_identity_and_empty_evolution_list(self):
        import model

        key = parse.species_key("JIGGLYPUFF", 1)
        sp = self.game.species[key]
        self.assertEqual((sp.base_species, sp.form, sp.base_exp), ("JIGGLYPUFF", 1, 76))
        self.assertEqual(sp.evos, [])
        cfg = model.Config(groups=("KANTO", "JOHTO", "WARP"))
        for level in (1, 35, 50, 100):
            self.assertEqual(model.evolve_by_level(self.game, cfg, key, level, random.Random(0)), key)
        self.assertIn(key, [pick for tier in self.game.rarity["WARP"] for pick in tier.base])

    def test_regional_branches_have_exact_target_forms(self):
        species = self.game.species
        self.assertIn((parse.EVOLVE_ITEM, 1, "MAROWAK#1"), species["CUBONE"].evos)
        self.assertIn((parse.EVOLVE_ITEM, 1, "RAICHU#1"), species["PIKACHU"].evos)
        self.assertIn((parse.EVOLVE_LEVEL, 28, "PERSIAN#2"), species["MEOWTH#2"].evos)
        self.assertIn((parse.EVOLVE_LEVEL, 37, "SLOWBRO#1"), species["SLOWPOKE#1"].evos)
        self.assertIn((parse.EVOLVE_ITEM, 1, "SLOWKING#1"), species["SLOWPOKE#1"].evos)

    def test_base_species_remain_separate(self):
        species = self.game.species
        self.assertEqual(parse.species_key("JIGGLYPUFF"), "JIGGLYPUFF")
        self.assertEqual(species["JIGGLYPUFF"].form, 0)
        self.assertIn((parse.EVOLVE_ITEM, 1, "WIGGLYTUFF"), species["JIGGLYPUFF"].evos)
        self.assertEqual(species["JIGGLYPUFF#1"].internal_id, species["JIGGLYPUFF"].internal_id)
        self.assertEqual(species["MEOWTH#2"].form_group, "WARP")
        self.assertEqual(species["JOLTEON#2"].form_group, "JOHTO")

    def test_pool_rows_preserve_explicit_forms(self):
        all_picks = [pick for runs in self.game.pools.values() for picks in runs.values() for pick in picks]
        for key in ("GROWLITHE#1", "MEOWTH#2", "DIGLETT#2", "TAUROS#3", "MAGNETON#1"):
            self.assertIn(key, all_picks)
        self.assertEqual(parse._entry_identity(["NINETALES", "POOL_FORM_BASE"]), "NINETALES")
        self.assertEqual(parse._entry_identity(["GOLEM", "POOL_FORM_KEEP | (1)"]), "GOLEM#1")

    def test_form_record_stats_are_read_independently(self):
        # Perturb a form source row: sharing its base ID must not reuse base stats.
        read = parse._lines
        def changed(rel):
            lines = read(rel)
            if rel == "data/pokemon/forms/gslowking.asm":
                lines = [line.replace("db 164 ; base exp", "db 237 ; base exp") for line in lines]
            return lines
        with patch.object(parse, "_lines", side_effect=changed):
            species = parse.load_species()
        self.assertEqual(species["SLOWKING#1"].base_exp, 237)
        self.assertEqual(species["SLOWKING"].base_exp, 164)
        self.assertTrue(all(sp.base_species and sp.display_name for sp in self.game.species.values()))
        for sp in self.game.species.values():
            for _, _, target in sp.evos:
                self.assertIn(target, self.game.species)

    def test_generated_eevee_uses_only_unlocked_exact_branches(self):
        import model

        cfg = model.Config(groups=("KANTO", "JOHTO", "WARP"))
        self.assertEqual(len(self.game.eevee_branches), 8)
        outcomes = {model.evolve_by_level(self.game, cfg, "EEVEE", 35, random.Random(seed))
                    for seed in range(200)}
        self.assertEqual(outcomes, {"FLAREON", "JOLTEON", "VAPOREON", "FLAREON#1",
                                    "JOLTEON#1", "JOLTEON#2", "VAPOREON#1", "VAPOREON#2"})
        rng = random.Random(20261018)
        counts = Counter(model.evolve_by_level(self.game, cfg, "EEVEE", 35, rng)
                         for _ in range(6000))
        # Deterministic broad bounds reject preferential branch weights.
        self.assertTrue(all(650 <= count <= 850 for count in counts.values()), counts)
        cfg.groups = ("KANTO",)
        self.assertEqual({model.evolve_by_level(self.game, cfg, "EEVEE", 35, random.Random(seed))
                          for seed in range(100)}, {"FLAREON", "JOLTEON", "VAPOREON"})

    def test_native_classification_uses_only_base_rows(self):
        self.assertEqual(parse.classify(self.game.rarity, "JIGGLYPUFF#1"),
                         parse.classify(self.game.rarity, "JIGGLYPUFF"))
        form_only = {group: [parse.Tier([], []) for _ in range(5)] for group in parse.GROUPS}
        form_only["WARP"][0] = parse.Tier(["JIGGLYPUFF#1"], ["JIGGLYPUFF#1"])
        self.assertIsNone(parse.classify(form_only, "JIGGLYPUFF"))

    def test_form_carry_and_base_branch_unlock_gates_differ(self):
        import model

        cfg = model.Config(groups=("KANTO",))
        # An existing regional mon carries its authored target form even with
        # Warp off, while the Johto base-species gate still excludes Slowking.
        self.assertEqual({model.evolve_by_level(self.game, cfg, "SLOWPOKE#1", 50, random.Random(seed))
                          for seed in range(30)}, {"SLOWBRO#1"})
        self.assertEqual({model.evolve_by_level(self.game, cfg, "CUBONE", 50, random.Random(seed))
                          for seed in range(30)}, {"MAROWAK"})
        cfg.groups = ("KANTO", "JOHTO", "WARP")
        self.assertEqual({model.evolve_by_level(self.game, cfg, "CUBONE", 50, random.Random(seed))
                          for seed in range(30)}, {"MAROWAK", "MAROWAK#1"})


if __name__ == "__main__":
    unittest.main()
