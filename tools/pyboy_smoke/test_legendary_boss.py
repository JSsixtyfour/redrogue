"""Challenge 11 (Legendary Boss): the ace swap inside the party spec builder.

Every gym leader has a party spec, so ReadTrainer builds them through
RogueBuildParty and never reaches the old .SpecialTrainer hook. Measured in BGB
2026-10-13: PatchLegendaryBossSpecies never fired for Sabrina with the challenge
accepted. The swap now lives in PartyGenLegendaryBossAce, which farcalls
RollLegendaryBossAce for the team's last slot.

These drive the real ReadTrainer and read the built party back. Leaders are keyed
on TRAINER CLASS, never wGymLeaderNo: Kanto and Johto share leader numbers 1-8,
so BROCK (shares 1 with FALKNER), JASMINE (6, SABRINA) and CLAIR (8, GIOVANNI)
are the cases a number-keyed table would have swapped by mistake.

Each test boots once and stays under the harness's ~10 ReadTrainer calls per boot
(see the module note in test_party_specs.py).
"""
import re

from source_constants import (
    parse_map_constants, parse_rgbds_constants, parse_trainer_class_indexes)
from test_smoke import HarnessTestCase, REPO_ROOT

# Mirrors LegendaryBossTable in custom_functions/legendary_boss_helpers.asm.
LEGENDARY_POOLS = {
    "ERIKA": ["MEW", "CELEBI"],
    "SABRINA": ["MEWTWO", "MEW", "CELEBI", "LUGIA"],
    "BLAINE": ["MEW", "HO_OH"],
    "GIOVANNI": ["MEWTWO"],
    "FALKNER": ["LUGIA", "HO_OH"],
    "MORTY": ["HO_OH"],
    "PRYCE": ["CELEBI"],
}
NOT_ELIGIBLE = ["BROCK", "JASMINE", "CLAIR"]

# Round 6 A: a gym-5-or-later team, the only place the witch offers the challenge.
TRAINER_NO = 16

def enable_expansions(h):
    groups = parse_rgbds_constants(REPO_ROOT / "constants/rogue_species_groups.asm")
    h.write_sram_bytes("sRogueSpeciesGroupsEnabled",
                       [groups["GROUP_OVERRIDE_TAG"] | sum(1 << groups[n] for n in ("BIT_GROUP_KANTO", "BIT_GROUP_JOHTO", "BIT_GROUP_WARP"))], bank=1)


def curated_sets(species, tiers):
    """{frozenset(moves)} of movesets.asm's rows for `species` whose tier
    expression names any of `tiers`. Level is not filtered: boss and corpus
    ELITE/HARD rows all start at or below a gym 5+ ace's level."""
    text = (REPO_ROOT / "data/trainers/movesets.asm").read_text(encoding="utf-8")
    body = re.search(r"^Moveset_{}::\n(.*?)^(?:Moveset_|SECTION|$)".format(species),
                     text, re.S | re.M).group(1)
    out = set()
    for m in re.finditer(r"db ([A-Z_0-9]+), ([A-Z_0-9]+), ([A-Z_0-9]+), ([A-Z_0-9]+), ([^,]+),",
                         body):
        if any(t in m.group(5) for t in tiers):
            out.add(frozenset(m.group(i) for i in range(1, 5)))
    return out


class LegendaryBossSwapSmokeTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants/pokemon_constants.asm")
        self.classes = parse_trainer_class_indexes(
            REPO_ROOT / "constants/trainer_constants.asm")
        self.ram = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")

    def _set_challenge(self, on):
        h = self.harness
        flags = h.read8("wRogueFlagsBitfield")
        bit = 1 << self.ram["BIT_WITCH_ACCEPTED"]
        h.write8("wRogueFlagsBitfield", (flags | bit) if on else (flags & ~bit & 0xFF))
        h.write8("wWitchChallenge", self.ram["CHALLENGE_LEGENDARY_BOSS"] if on else 0)

    def _build(self, trainer_class):
        h = self.harness
        h.write8("wLegendaryBossSpecies", 0)
        h.write8("wTrainerClass", self.classes[trainer_class])
        h.write8("wTrainerNo", TRAINER_NO)
        h.call_routine("ReadTrainer", limit=4000)
        count = h.read8("wEnemyPartyCount")
        return count, h.read_bytes("wEnemyPartySpecies", count + 1)

    def _assert_ordinary_moves(self, ace, slot, stride):
        """The ordinary slot source survives, and its moves survive for trade."""
        h = self.harness
        self.assertFalse(h.read8("wPartyGenSlotSource", offset=slot) & 0x80)
        got = h.read_bytes("wEnemyMon1Moves", 4, offset=slot * stride)
        self.assertTrue(any(got))
        self.assertEqual(h.read_bytes("wLegendaryBossMoves", 4), got)

    def test_every_eligible_leader_fields_a_legendary_from_its_pool(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.set_difficulty("HARD")  # VERY EASY would skip curated sets by design
        enable_expansions(h)
        self.moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        self._set_challenge(True)
        stride = h.address("wEnemyMon2") - h.address("wEnemyMon1")
        for leader, pool in LEGENDARY_POOLS.items():
            with self.subTest(leader=leader):
                count, party = self._build(leader)
                self.assertGreater(count, 0)
                ace = party[count - 1]
                allowed = {self.species[s] for s in pool}
                self.assertIn(ace, allowed,
                              f"{leader}'s ace is {ace}, expected one of {pool}")
                self.assertEqual(h.read8("wLegendaryBossSpecies"), ace,
                                 "the trade byte must name the fielded ace")
                form = (h.read8("wEnemyMon1CatchRate",
                                offset=(count - 1) * stride) >> 5) & 0b11
                # Armored Mewtwo (form 1) is Giovanni's alone (2026-10-27); every
                # other swapped ace, Sabrina's Mewtwo included, carries no form.
                self.assertEqual(form, 1 if leader == "GIOVANNI" else 0,
                                 "only Giovanni's ace is armored")
                self._assert_ordinary_moves(ace, count - 1, stride)

    def test_no_swap_for_number_twins_or_without_the_challenge(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        legendaries = {self.species[s] for pool in LEGENDARY_POOLS.values() for s in pool}
        self._set_challenge(True)
        for leader in NOT_ELIGIBLE:
            with self.subTest(leader=leader, challenge=True):
                count, party = self._build(leader)
                self.assertNotIn(party[count - 1], legendaries)
                self.assertEqual(h.read8("wLegendaryBossSpecies"), 0)
        self._set_challenge(False)
        for leader in ("SABRINA", "GIOVANNI"):
            with self.subTest(leader=leader, challenge=False):
                count, party = self._build(leader)
                self.assertNotIn(party[count - 1], legendaries)
                self.assertEqual(h.read8("wLegendaryBossSpecies"), 0)

    def test_kanto_only_blaine_never_fields_ho_oh(self):
        h = self.harness
        h.boot_fight2(seed=1)
        h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [1], bank=1)
        self._set_challenge(True)
        for _ in range(6):
            count, party = self._build("BLAINE")
            self.assertEqual(party[count - 1], self.species["MEW"])
        self._build("MORTY")
        self.assertEqual(h.read8("wLegendaryBossSpecies"), 0,
                         "a disabled-only pool cannot produce an ace")


CARRY = 1 << 4


class LegendaryBossGateSmokeTest(HarnessTestCase):
    """Phase 3: the witch's gate and the wrong-door rule.

    GYM LEADERS HAVE NO ORDER. The lobby's two doors are two random unbeaten
    badge slots (wGymChoice) and wRunGymLineup holds each slot's leader CLASS,
    so these write a lineup and a door pair by hand and ask the real routines.
    """

    def setUp(self):
        super().setUp()
        h = self.harness
        h.boot_fight2(seed=1)
        self.classes = parse_trainer_class_indexes(
            REPO_ROOT / "constants/trainer_constants.asm")
        self.ram = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants/pokemon_constants.asm")
        # Slot 0 BROCK (no legendary), slot 1 SABRINA, slot 2 MORTY, the rest
        # leaders without one. Badge slots, not gym numbers.
        lineup = ["BROCK", "SABRINA", "MORTY", "JASMINE", "CLAIR", "MISTY",
                  "LT_SURGE", "KOGA"]
        for i, name in enumerate(lineup):
            h.write8("wRunGymLineup", self.classes[name], offset=i)
        # A leader is a legendary door only while its pool holds a species the
        # player does not own (party or current box), so ownership is an input
        # here: start with no legendary anywhere.
        self._own([self.species["PIDGEY"]])
        enable_expansions(h)

    def _own(self, party, box=()):
        h = self.harness
        for i, sp in enumerate(list(party) + [0xFF]):
            h.write8("wPartySpecies", sp, offset=i)
        h.write8("wBoxCount", len(box))
        for i, sp in enumerate(list(box) + [0xFF]):
            h.write8("wBoxSpecies", sp, offset=i)

    def _doors(self, door1, door2):
        latched = 1 << self.ram["BIT_GYM_CHOICE_LATCHED"]
        self.harness.write8("wGymChoice", latched | door1 | (door2 << 3))

    def _call(self, label):
        self.harness.call_routine(label, limit=4000)
        return self.harness.last_call_registers

    def test_doors_report_which_leader_holds_a_legendary(self):
        for door1, door2, want in ((0, 1, 0b10), (1, 0, 0b01), (0, 3, 0b00),
                                   (1, 2, 0b11), (2, 2, 0b11)):
            with self.subTest(door1=door1, door2=door2):
                self._doors(door1, door2)
                self.assertEqual(self._call("LegendaryBossDoors")["E"], want)
        # Morty fields only Ho-Oh: owning one (here in the box) closes his door.
        self._own([self.species["PIDGEY"]], box=[self.species["HO_OH"]])
        self._doors(1, 2)
        self.assertEqual(self._call("LegendaryBossDoors")["E"], 0b01)
        self.harness.write8("wGymChoice", 0)  # nothing latched: a route visit
        self.assertEqual(self._call("LegendaryBossDoors")["E"], 0)

    def test_offer_needs_four_badges_both_doors_and_a_masterball_mon(self):
        h = self.harness
        mewtwo, pidgey = self.species["MEWTWO"], self.species["PIDGEY"]

        def offerable(badges, door1, door2, party):
            h.write8("wObtainedBadges", badges)
            self._doors(door1, door2)
            for i, sp in enumerate(party + [0xFF]):
                h.write8("wPartySpecies", sp, offset=i)
            return bool(self._call("IsLegendaryBossOfferable")["F"] & CARRY)

        # Badges are lineup slots; door slots must be unbeaten, so leave 0-2 clear.
        self.assertTrue(offerable(0b11110000, 1, 2, [pidgey, mewtwo]))
        self.assertTrue(offerable(0b11111101, 1, 1, [pidgey, mewtwo]), "one gym left")
        self.assertFalse(offerable(0b11110000, 0, 1, [mewtwo]), "only door 2 qualifies")
        self.assertFalse(offerable(0b11110000, 1, 0, [mewtwo]), "only door 1 qualifies")
        self.assertFalse(offerable(0b01110000, 0, 1, [mewtwo]), "3 badges")
        self.assertFalse(offerable(0b11110000, 0, 3, [mewtwo]), "no eligible door")
        self.assertFalse(offerable(0b11110000, 1, 2, [pidgey]), "no masterball mon")
        self.assertFalse(offerable(0xFF, 1, 1, [mewtwo]), "finale")

    def test_disabled_pool_closes_door_and_blocks_offer(self):
        h = self.harness
        h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [1], bank=1)
        self._doors(1, 2)  # Sabrina has Kanto options; Morty has only Ho-Oh.
        self.assertEqual(self._call("LegendaryBossDoors")["E"], 0b01)
        h.write8("wObtainedBadges", 0b11110000)
        self._own([self.species["MEWTWO"]])
        self.assertFalse(self._call("IsLegendaryBossOfferable")["F"] & CARRY)

    def test_wrong_door_breaks_the_bargain_and_right_door_keeps_it(self):
        h = self.harness
        maps = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
        bit = 1 << self.ram["BIT_WITCH_ACCEPTED"]
        for gym, slot, keeps in (("SAFFRON_GYM", 1, True), ("PEWTER_GYM", 0, False)):
            with self.subTest(gym=gym):
                self._doors(0, 1)
                h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") | bit)
                h.write8("wWitchChallenge", self.ram["CHALLENGE_LEGENDARY_BOSS"])
                h.write8("hCurMap", maps[gym])
                self._call("RogueGymChoiceMapLoad")
                self.assertEqual(h.read8("wRogueCurGymBadgeMask"), 1 << slot,
                                 "the badge must still follow the door taken")
                accepted = bool(h.read8("wRogueFlagsBitfield") & bit)
                challenge = h.read8("wWitchChallenge")
                if keeps:
                    self.assertTrue(accepted)
                    self.assertEqual(challenge, self.ram["CHALLENGE_LEGENDARY_BOSS"])
                else:
                    self.assertFalse(accepted, "wrong door must clear the bargain")
                    self.assertEqual(challenge, 0)


def learnable_moves(species):
    """Level-1 moves (base stats) plus every level-up move: all WriteMonMoves
    can give. Levels are ignored; this asks "learnset or not", not which four."""
    base = (REPO_ROOT / "data/pokemon/base_stats/{}.asm".format(
        species.lower().replace("_", ""))).read_text(encoding="utf-8")
    first = re.search(r"db (\w+), (\w+), (\w+), (\w+) ; level 1 learnset", base)
    evos = (REPO_ROOT / "data/pokemon/evos_moves.asm").read_text(encoding="utf-8")
    label = "".join(p.capitalize() for p in species.split("_")) + "EvosMoves:"
    body = evos[evos.index(label):]
    body = body[body.index("; Learnset"):body.index("db 0", body.index("; Learnset"))]
    return set(first.groups()) | set(re.findall(r"db \d+, (\w+)", body))


class LegendaryBossVeryEasySmokeTest(HarnessTestCase):
    """VERY EASY also keeps the ordinary slot source and preserves its moves."""

    def test_very_easy_boss_uses_ordinary_source(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.set_difficulty("VERY_EASY")
        enable_expansions(h)
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        classes = parse_trainer_class_indexes(REPO_ROOT / "constants/trainer_constants.asm")
        ram = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        h.write8("wRogueFlagsBitfield",
                 h.read8("wRogueFlagsBitfield") | (1 << ram["BIT_WITCH_ACCEPTED"]))
        h.write8("wWitchChallenge", ram["CHALLENGE_LEGENDARY_BOSS"])
        stride = h.address("wEnemyMon2") - h.address("wEnemyMon1")
        # One-species pools, so the ace is known: Giovanni MEWTWO, Morty HO_OH, Pryce CELEBI.
        for leader, legend in (("GIOVANNI", "MEWTWO"), ("MORTY", "HO_OH"),
                               ("PRYCE", "CELEBI")):
            with self.subTest(leader=leader):
                h.write8("wTrainerClass", classes[leader])
                h.write8("wTrainerNo", TRAINER_NO)
                h.call_routine("ReadTrainer", limit=4000)
                count = h.read8("wEnemyPartyCount")
                self.assertEqual(h.read_bytes("wEnemyPartySpecies", count)[-1],
                                 species[legend])
                got = [m for m in h.read_bytes("wEnemyMon1Moves", 4,
                                               offset=(count - 1) * stride) if m]
                self.assertTrue(got, f"{legend} has no moves")
                self.assertFalse(h.read8("wPartyGenSlotSource", offset=count - 1) & 0x80)
                self.assertEqual(h.read_bytes("wLegendaryBossMoves", 4),
                                 h.read_bytes("wEnemyMon1Moves", 4, offset=(count - 1) * stride))


class LegendaryTradeFormSmokeTest(HarnessTestCase):
    """Giovanni's post-battle trade hands over Armored Mewtwo (MEWTWO form 1),
    armor kept; Sabrina's Mewtwo trades plain (user decision 2026-10-27).

    Runs the real per-leader entry and stops it at RogueDoInGameTradeDialogue's
    entry, reading the offer's wroguenpctradeform there: the byte
    InGameTrade_DoTrade turns into the received mon's wSpawnForm."""

    def _offer_form(self, entry):
        h = self.harness
        regs, mem = h.pyboy.register_file, h.pyboy.memory
        ram = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        h.write8("wRogueFlagsBitfield",
                 h.read8("wRogueFlagsBitfield") | (1 << ram["BIT_WITCH_ACCEPTED"]))
        h.write8("wWitchChallenge", ram["CHALLENGE_LEGENDARY_BOSS"])
        h.write8("wLegendaryBossSpecies", species["MEWTWO"])
        for i, sp in enumerate([species["PIDGEY"], species["MEW"], 0xFF]):
            h.write8("wPartySpecies", sp, offset=i)  # MEW: the masterball mon to give
        h.write8("wroguenpctradeform", 0xAA)          # must be overwritten
        seen = []
        hook_bank, hook_addr = h.symbols.get("RogueDoInGameTradeDialogue")
        h.pyboy.hook_register(hook_bank, hook_addr,
                              lambda _ctx: seen.append(h.read8("wroguenpctradeform")), None)
        try:
            # jr @ return stub, IE masked: the offer runs to the dialogue's
            # entry without needing a frame (reference_pyboy_direct_stub_executor).
            stub = h.address("wStringBuffer") + 16
            mem[stub], mem[stub + 1] = 0x18, 0xFE
            mem[0xFFFF] = 0
            bank, addr = h.symbols.get(entry)
            h.write8("hLoadedROMBank", bank)
            mem[0x2000] = bank
            sp = (regs.SP - 2) & 0xFFFF
            mem[sp], mem[sp + 1] = stub & 0xFF, stub >> 8
            regs.SP = sp
            regs.PC = addr
            for _ in range(20):
                h.pyboy.tick()
                if seen:
                    break
        finally:
            h.pyboy.hook_deregister(hook_bank, hook_addr)
        self.assertTrue(seen, f"{entry} never reached the trade dialogue")
        return seen[0]

    def test_giovanni_trades_armored_mewtwo(self):
        self.harness.boot_fight2(seed=1)
        self.assertEqual(self._offer_form("OfferLegendaryTradeGiovanni"), 1)

    def test_sabrina_trades_plain_mewtwo(self):
        self.harness.boot_fight2(seed=1)
        self.assertEqual(self._offer_form("OfferLegendaryTradeSabrina"), 0)


class LegendaryTradeMovesSmokeTest(HarnessTestCase):
    def test_received_moves_and_pp_match_preserved_battle_set(self):
        h = self.harness
        h.boot_fight2(seed=1)
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        script = parse_rgbds_constants(REPO_ROOT / "constants/script_constants.asm")
        chosen = [moves[n] for n in ("SURF", "PSYCHIC_M", "RECOVER", "THUNDER_WAVE")]
        h.write8("wWhichTrade", script["TRADE_FOR_RANDOM"])
        h.write8("wroguenpctradedialogue", script["TRADE_DIALOGSET_LEGENDARY"])
        h.write8("wLegendaryBossSpecies", species["MEW"])
        h.write8("wInGameTradeReceiveMonSpecies", species["MEW"])
        for i, move in enumerate(chosen):
            h.write8("wLegendaryBossMoves", move, offset=i)
        slot = h.read8("wPartyCount") - 1
        offset = slot * (h.address("wPartyMon2") - h.address("wPartyMon1"))
        for i in range(4):
            h.write8("wPartyMon1Moves", moves["TACKLE"], offset=offset + i)
            h.write8("wPartyMon1PP", 0, offset=offset + i)
        h.call_routine("InGameTrade_CopyLegendaryMoves")
        self.assertEqual(h.read_bytes("wPartyMon1Moves", 4, offset=offset), chosen)
        self.assertEqual(h.read_bytes("wPartyMon1PP", 4, offset=offset), [15, 10, 20, 20])
        # A later ordinary random trade must not inherit the challenge set.
        h.write8("wroguenpctradedialogue", 0)
        h.write8("wPartyMon1Moves", moves["TACKLE"], offset=offset)
        h.call_routine("InGameTrade_CopyLegendaryMoves")
        self.assertEqual(h.read8("wPartyMon1Moves", offset=offset), moves["TACKLE"])
