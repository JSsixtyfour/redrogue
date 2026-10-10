"""PARTY_ROSTER.md -> band_pools.asm: the generator, its lint, and its curve block.

No emulator needed. Each lint rule is proven in both directions on a minimal
synthetic doc (fires on the bad doc, silent on the fixed one), so a rule that
always passes or always fails is caught. The committed asm and the committed curve
block are also checked against what the tool generates from the committed doc.
"""
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools"))

import gen_party_roster as gpr  # noqa: E402

NAMES = gpr.Names()
GROUPS = gpr.load_rarity_groups()
EVO_TARGETS = gpr.load_evolution_targets()


def doc(body, section="Gym leaders", prefix="Brock"):
    return "## {}\n\n### {} (TEST)\n\n{}\n".format(section, prefix, body)


def findings(body, **kw):
    chars = gpr.parse_doc(doc(body, **kw), NAMES)
    return gpr.lint(chars, NAMES, GROUPS, EVO_TARGETS)


def messages(body, severity, **kw):
    return [m for sev, m in findings(body, **kw) if sev == severity]


class RosterFilesTest(unittest.TestCase):
    def test_committed_asm_equals_generator_output(self):
        text = gpr.read(gpr.DOC)
        chars = gpr.parse_doc(text, NAMES)
        self.assertEqual(gpr.read(gpr.OUT), gpr.emit_asm(chars),
                         "band_pools.asm is stale: run python3 tools/gen_party_roster.py")

    def test_committed_curve_block_is_current(self):
        text = gpr.read(gpr.DOC)
        self.assertEqual(text, gpr.splice_curve(text, gpr.curve_block(gpr.load_curve())),
                         "PARTY_ROSTER.md curve block is stale: run python3 tools/gen_party_roster.py")

    def test_shipping_doc_has_no_lint_errors(self):
        chars = gpr.parse_doc(gpr.read(gpr.DOC), NAMES)
        errors = [m for sev, m in gpr.lint(chars, NAMES, GROUPS, EVO_TARGETS) if sev == "error"]
        self.assertEqual([], errors)


class KantoAceRuleTest(unittest.TestCase):
    BAD = "**Band 1: rounds 1-2**\n- Aces: Sudowoodo (johto)\n- Fodder: Geodude\n"
    GOOD = "**Band 1: rounds 1-2**\n- Aces: Onix, Sudowoodo (johto)\n- Fodder: Geodude\n"

    def test_fires_without_a_kanto_ace(self):
        errs = messages(self.BAD, "error")
        self.assertEqual(1, len(errs), errs)
        self.assertIn("Brock band 1 Aces", errs[0])

    def test_silent_with_a_kanto_ace(self):
        self.assertEqual([], messages(self.GOOD, "error"))

    def test_johto_gated_leader_is_exempt(self):
        self.assertEqual([], messages(self.BAD, "error", prefix="Falkner"))

    def test_band_without_aces_is_exempt(self):
        self.assertEqual([], messages("**Band 1: rounds 1-2**\n- Fodder: Geodude\n", "error"))

    def test_every_kind_is_checked(self):
        # An empty ace pool falls back to its first entry unfiltered
        # (PartyGenRollFromPool .giveUp), so the rule is not gym-only.
        self.assertEqual(1, len(messages(self.BAD, "error", section="Wild-area trainers",
                                         prefix="JessieJames")))
        self.assertEqual([], messages(self.GOOD, "error", section="Wild-area trainers",
                                      prefix="JessieJames"))


class RunRuleTest(unittest.TestCase):
    def band(self, fodder):
        return "**Band 1: rounds 1-2**\n- Aces: Onix\n- Fodder: {}\n".format(fodder)

    def test_johto_species_needs_a_tag(self):
        self.assertEqual(1, len(messages(self.band("Geodude, Larvitar"), "error")))
        self.assertEqual([], messages(self.band("Geodude, Larvitar (johto)"), "error"))
        self.assertEqual([], messages(self.band("Geodude, Larvitar (warp)"), "error"))

    def test_warp_species_needs_the_warp_tag(self):
        warp = next(sp for sp, g in sorted(GROUPS.items()) if g == "warp" and sp.isalpha())
        name = gpr.species_display(warp)
        self.assertEqual(1, len(messages(self.band("{} (johto)".format(name)), "error")))
        self.assertEqual([], messages(self.band("{} (warp)".format(name)), "error"))

    def test_pinned_form_needs_warp_except_espeon_and_umbreon(self):
        self.assertEqual(1, len(messages(self.band("Hisuian Growlithe"), "error")))
        self.assertEqual(1, len(messages(self.band("Hisuian Growlithe (johto)"), "error")))
        self.assertEqual([], messages(self.band("Hisuian Growlithe (warp)"), "error"))
        self.assertEqual([], messages(self.band("Espeon (johto), Umbreon (johto)"), "error"))
        self.assertEqual(1, len(messages(self.band("Leafeon (johto)"), "error")))


class WarningRulesTest(unittest.TestCase):
    def test_fodder_base_form(self):
        self.assertEqual(1, len(messages("**Band 1: rounds 1-2**\n- Aces: Onix\n- Fodder: Golem\n",
                                         "warning")))
        self.assertEqual([], messages("**Band 1: rounds 1-2**\n- Aces: Onix\n- Fodder: Geodude\n",
                                      "warning"))

    def test_weak_ace(self):
        weak = "**Band 2: rounds 3-4**\n- Aces: Kadabra\n- Fodder: Geodude\n"
        strong = "**Band 2: rounds 3-4**\n- Aces: Alakazam, Rhydon\n- Fodder: Geodude\n"
        self.assertTrue(any("Kadabra" in m for m in messages(weak, "warning")))
        self.assertFalse(any("weak" in m for m in messages(strong, "warning")))
        # Band 1 has no floor.
        self.assertFalse(any("weak" in m for m in messages(
            "**Band 1: rounds 1-2**\n- Aces: Kadabra\n- Fodder: Geodude\n", "warning")))

    def test_duplicate_within_list(self):
        twice = "**Band 1: rounds 1-2**\n- Aces: Onix\n- Fodder: Geodude, Geodude\n"
        thrice = "**Band 1: rounds 1-2**\n- Aces: Onix\n- Fodder: Geodude, Geodude, Geodude\n"
        self.assertEqual([], messages(twice, "warning"))
        self.assertTrue(any("listed 3 times" in m for m in messages(thrice, "warning")))

    def test_form_bst_comes_from_the_form_file(self):
        # data/pokemon/forms/agolem.asm: 80/120/130/45/65
        self.assertEqual(440, gpr.base_stat_total("GOLEM", 1))
        self.assertEqual(420, gpr.base_stat_total("GOLEM", None))


class CurveBlockTest(unittest.TestCase):
    # Hand-computed: round 1 has 2 mons, base 9, step 2 -> ace 11; round 2 has 2 mons,
    # base 15, step 3 -> ace 18. Round 7 has 5 mons, base 43, step 2 -> ace 51; round 8
    # has 6 mons, base 47, step 2 -> ace 57.
    ROUNDS = {1: (2, 9, 2), 2: (2, 15, 3), 3: (3, 19, 3), 4: (3, 27, 2),
              5: (4, 31, 2), 6: (4, 38, 2), 7: (5, 43, 2), 8: (6, 47, 2)}

    def test_block_numbers(self):
        rows = gpr.curve_block(self.ROUNDS).splitlines()
        self.assertIn("| 1 | 1-2 | 2-2 | 9-15 | 11-18 |", rows)
        self.assertIn("| 4 | 7-8 | 5-6 | 43-47 | 51-57 |", rows)

    # The live curve (Curve G, 2026-10-10). ROUNDS above is Curve F, kept as a
    # fixed fixture for the formatting tests.
    CURRENT = {1: (2, 11, 2), 2: (2, 17, 3), 3: (3, 21, 3), 4: (3, 26, 2),
               5: (4, 31, 2), 6: (4, 38, 2), 7: (5, 40, 2), 8: (6, 45, 2)}

    def test_block_tracks_the_constants(self):
        loaded = gpr.load_curve()
        for r, (mons, base, step) in self.CURRENT.items():
            self.assertEqual((mons, base, step), loaded[r],
                             "GYM_R{} changed: update this test and rerun the tool".format(r))

    def test_expression_is_a_loud_error(self):
        text = "\n".join("DEF GYM_R{}_{} EQU {}".format(r, k, "1 + 2" if (r, k) == (3, "BASE") else 4)
                         for r in range(1, 9) for k in ("MONS", "BASE", "STEP"))
        with self.assertRaises(gpr.RosterError):
            gpr.load_curve(text)

    def test_splice_rewrites_only_between_the_markers(self):
        text = "before\n{}\nstale\n{}\nafter\n".format(gpr.CURVE_BEGIN, gpr.CURVE_END)
        out = gpr.splice_curve(text, gpr.curve_block(self.ROUNDS))
        self.assertTrue(out.startswith("before\n"))
        self.assertTrue(out.endswith("\nafter\n"))
        self.assertNotIn("stale", out)

    def test_missing_markers_fail(self):
        with self.assertRaises(gpr.RosterError):
            gpr.splice_curve("no markers here\n", "x")


if __name__ == "__main__":
    unittest.main()
