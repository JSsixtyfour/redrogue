"""Source contracts for the 1C stage-event recovery changes (2026-09-22).

Three behaviours landed together because the user's reasoning ties them: the
stolen mon goes to the BOX when the party is full, a hand-over that finds no
room anywhere stays retryable, and the villain STAYS ON THE MAP so the retry
is reachable.

Each of those is a structural property that a runtime audit is slow to cover
and easy to regress silently, so they are asserted against the source here.
The byte-level behaviour is in audit_cave_stage_recovery.py, including its
--full-party mode.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]

STAGE_EVENTS = REPO_ROOT / "custom_functions" / "stage_events.asm"
RAM_CONSTANTS = REPO_ROOT / "constants" / "ram_constants.asm"
TRAINERS = REPO_ROOT / "home" / "trainers.asm"
STAGE_TEXT = REPO_ROOT / "text" / "StageEvents.asm"

# (script, the beat-flag pair it sets on recovery, its after-battle handler)
STAGE_SCRIPTS = (
    ("scripts/ProceduralCave1.asm", "EVENT_BEAT_STAGE_EVENT_NPC", "PCStageEventAfterText"),
    ("scripts/ProceduralForest.asm", "EVENT_BEAT_STAGE_EVENT_NPC", "PFStageEventAfterText"),
    ("scripts/ProceduralFacility.asm", "EVENT_BEAT_FACILITY_STAGE_NPC", "PFacStageEventAfterText"),
    ("scripts/ProceduralCemetery1.asm", "EVENT_BEAT_FACILITY_STAGE_NPC", "PCStageEventAfterText"),
)

# Each map's recover-line handler, which must be a thin farcall stub. The four
# private dispatchers, tables and text_far wrappers these replaced were ~60
# bytes each of pure duplication in bank 17.
RECOVER_STUBS = (
    ("scripts/ProceduralCave1.asm", "PCStageEventRecoverText:"),
    ("scripts/ProceduralForest.asm", "PFStageEventRecoverText:"),
    ("scripts/ProceduralFacility.asm", "PFacStageEventRecoverText:"),
    ("scripts/ProceduralCemetery1.asm", "PCemStageEventRecoverText::"),
)


def read(rel):
    return (REPO_ROOT / rel).read_text()


def const(name, text=None):
    text = RAM_CONSTANTS.read_text() if text is None else text
    m = re.search(r"^DEF %s\s+EQU\s+(\d+)" % name, text, re.M)
    if m is None:
        raise AssertionError("no DEF %s in ram_constants.asm" % name)
    return int(m.group(1))


def code_only(text):
    """Strip comments and blank lines.

    These files are heavily commented and the comments name the very labels
    and constants the assertions look for - "took the .noRoom exit", "byte 3
    is a stale MON_BOX_LEVEL" - so a raw substring search matches prose and
    an ordering assertion compares a comment against code. Strip first.
    """
    out = []
    for line in text.splitlines():
        line = re.sub(r";.*$", "", line).rstrip()
        if line:
            out.append(line)
    return "\n".join(out)


def routine(source, label, *, end=None, code=True):
    """The body of `label` up to the next top-level label (or `end`)."""
    start = source.index(label)
    rest = source[start + len(label):]
    if end is not None:
        rest = rest[:rest.index(end)]
    else:
        m = re.search(r"\n(?=[A-Za-z_][A-Za-z0-9_]*::?\s*$)", rest, re.M)
        rest = rest[:m.start()] if m else rest
    return code_only(rest) if code else rest


GIVEBACK_END = "\nStageEventStolenMonToBox:"


class GiveBackOutcomeContractTest(unittest.TestCase):
    def test_result_codes_are_dense_and_counted(self) -> None:
        """The count constant is what every table's length assert keys off."""
        values = {name: const("STAGE_GIVEBACK_" + name)
                  for name in ("NOTHING", "MON", "ITEM", "NO_ROOM", "TO_BOX")}
        self.assertEqual(sorted(values.values()), list(range(5)))
        self.assertEqual(const("NUM_STAGE_GIVEBACK_RESULTS"), 5)

    def test_owed_is_a_fourth_phase_and_fits_the_field(self) -> None:
        """Phase is two bits; OWED has to be the spare value, not a new byte."""
        mask = re.search(r"^DEF STAGE_EVENT_PHASE_MASK\s+EQU\s+%([01]+)",
                         RAM_CONSTANTS.read_text(), re.M)
        self.assertIsNotNone(mask)
        width = mask.group(1).count("1")
        self.assertEqual(width, 2)
        self.assertEqual(const("STAGE_EVENT_PHASE_OWED"), 3)
        self.assertLess(const("STAGE_EVENT_PHASE_OWED"), 1 << width)

    def test_phase_is_advanced_per_outcome_not_up_front(self) -> None:
        """The bug 1C fixes: SETTLED used to be set before the outcome was known.

        A full party then took the failure exit with the event already closed
        and the record about to be wiped, so the mon was simply destroyed.
        """
        body = routine(STAGE_EVENTS.read_text(), "StageEventGiveBack::",
                       end=GIVEBACK_END)
        settle = body.index("STAGE_EVENT_PHASE_SETTLED")
        for branch in (".giveItem", ".giveMon"):
            self.assertLess(body.index(branch), settle,
                            "%s must be decided before SETTLED is written" % branch)
        # Exactly one writer of each phase, so there is no second path that
        # could disagree with the outcome.
        self.assertEqual(body.count("STAGE_EVENT_PHASE_SETTLED"), 1)
        self.assertEqual(body.count("STAGE_EVENT_PHASE_OWED"), 1)
        owed = body.index("STAGE_EVENT_PHASE_OWED")
        self.assertLess(body.index(".noRoom"), owed)

    def test_no_room_keeps_the_record(self) -> None:
        """The retry has nothing to give back if the record is cleared."""
        body = routine(STAGE_EVENTS.read_text(), "StageEventGiveBack::",
                       end=GIVEBACK_END)
        # From the .noRoom LABEL (not the `jr` that targets it) to the next one.
        tail = body[body.index("\n.noRoom\n") + 1:]
        tail = tail[:tail.index("\n.giveMon\n")]
        self.assertNotIn("StageEventClearStolenRecord", tail)
        self.assertIn("STAGE_GIVEBACK_NO_ROOM", tail)

    def test_full_party_routes_to_the_box_before_failing(self) -> None:
        body = routine(STAGE_EVENTS.read_text(), "StageEventGiveBack::",
                       end=GIVEBACK_END)
        give_mon = body[body.index(".giveMon"):]
        self.assertIn("cp PARTY_LENGTH", give_mon)
        self.assertIn("jr nc, .giveMonToBox", give_mon)
        self.assertIn("call StageEventStolenMonToBox", give_mon)
        self.assertIn("jr nc, .noRoom", give_mon)
        self.assertIn("STAGE_GIVEBACK_TO_BOX", give_mon)


class StolenMonToBoxContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.body = routine(STAGE_EVENTS.read_text(), "StageEventStolenMonToBox:")

    def test_appends_rather_than_rebuilding_from_the_enemy_mon(self) -> None:
        """SendNewMonToBox would overwrite the OT and pop the nickname prompt."""
        self.assertNotIn("SendNewMonToBox", self.body)
        self.assertIn("cp MONS_PER_BOX", self.body)
        self.assertIn("ld [wBoxCount], a", self.body)
        for dest in ("wBoxSpecies", "wBoxMons", "wBoxMonNicks", "wBoxMonOT"):
            self.assertIn(dest, self.body)
        for src in ("sStolenBoxMon", "sStolenNickname", "sStolenOTName"):
            self.assertIn(src, self.body)

    def test_reselects_the_records_sram_bank(self) -> None:
        """sStolenRecord is in bank 1; every other stage-event field is bank 0."""
        self.assertIn("ld a, BANK(sStolenRecord)", self.body)
        self.assertIn("ld [rRAMB], a", self.body)
        self.assertLess(self.body.index("ld [rRAMB], a"),
                        self.body.index("ld a, [sStolenBoxMon]"))

    def test_box_level_is_recomputed_not_copied(self) -> None:
        """Byte 3 of the record is a stale party-struct BoxLevel."""
        self.assertIn("CalcLevelFromExperience", self.body)
        self.assertIn("ld a, BOX_DATA", self.body)
        self.assertIn("MON_BOX_LEVEL", self.body)
        self.assertLess(self.body.index("CalcLevelFromExperience"),
                        self.body.index("MON_BOX_LEVEL"))

    def test_box_full_is_the_only_failure_and_writes_nothing(self) -> None:
        head = self.body[:self.body.index(".haveRoom")]
        self.assertIn("cp MONS_PER_BOX", head)
        self.assertNotIn("ld [wBoxCount], a", head)
        self.assertEqual(self.body.count("scf"), 1)


class SurvivingNpcContractTest(unittest.TestCase):
    def test_home_delegates_the_carve_out(self) -> None:
        """Per-map SLOT lists do not belong in the tightest bank in the ROM."""
        body = routine(TRAINERS.read_text(), "EndTrainerBattle::",
                       end="EndTrainerBattleWhiteout::")
        self.assertIn("farcall StageEventKeepSpriteOnDefeat", body)
        self.assertIn("jr c, .skipRemoveSprite", body)
        for gone in ("cp PROCEDURAL_CAVE_1", "cp PROCEDURAL_FOREST",
                     "cp PROCEDURAL_FACILITY", "cp POKEMON_TOWER_7F"):
            self.assertNotIn(gone, body)

    def test_exempt_table_covers_every_stage_npc_pair(self) -> None:
        source = STAGE_EVENTS.read_text()
        table = routine(source, "StageEventKeepSpriteTable:")
        rows = {}
        for line in table.splitlines():
            m = re.match(r"\s*db (PROCEDURAL_\w+),\s*(\d+),\s*(\d+),\s*(\d+)", line)
            if m:
                rows[m.group(1)] = tuple(int(g) for g in m.groups()[1:])
        self.assertEqual(rows["PROCEDURAL_CAVE_1"], (1, 6, 7))
        self.assertEqual(rows["PROCEDURAL_FOREST"], (1, 6, 7))
        self.assertEqual(rows["PROCEDURAL_FACILITY"], (1, 10, 11))
        for n in range(1, 5):
            self.assertEqual(rows["PROCEDURAL_CEMETERY_%d" % n], (0, 2, 3))
        self.assertIn("db -1", table)

    def test_facility_fake_balls_are_still_hidden_on_defeat(self) -> None:
        """Slots 6-9 are OW_POKEMON objects that are CONSUMED when beaten.

        A blanket per-map exemption would leave them standing and re-fightable,
        which is the regression the 2026-09-17 narrowing fixed.
        """
        table = routine(STAGE_EVENTS.read_text(), "StageEventKeepSpriteTable:")
        m = re.search(r"db PROCEDURAL_FACILITY,\s*(\d+),\s*(\d+),\s*(\d+)", table)
        self.assertIsNotNone(m)
        exempt = {int(g) for g in m.groups()}
        self.assertTrue(exempt.isdisjoint({6, 7, 8, 9}))

    def test_tower_7f_is_exempt_for_every_slot(self) -> None:
        body = routine(STAGE_EVENTS.read_text(), "StageEventKeepSpriteOnDefeat::",
                       end="DEF STAGE_EVENT_KEEP_SLOTS")
        self.assertIn("cp POKEMON_TOWER_7F", body)
        self.assertLess(body.index("cp POKEMON_TOWER_7F"),
                        body.index("StageEventKeepSpriteTable"))

    def test_recovery_blocks_no_longer_hide_the_pair(self) -> None:
        for rel, event, _ in STAGE_SCRIPTS:
            with self.subTest(rel):
                source = read(rel)
                block = source[source.index("farcall StageEventGiveBack"):]
                block = block[:block.index("DisableWaitingAfterTextDisplay")]
                self.assertNotIn("predef HideObject", block)
                self.assertNotIn("PCemHideStageEventNpcs", block)

    def test_recovery_flags_the_partner_as_beaten(self) -> None:
        """Beating either half ends the encounter; the survivor must not fight."""
        for rel, event, _ in STAGE_SCRIPTS:
            with self.subTest(rel):
                source = read(rel)
                block = source[source.index("farcall StageEventGiveBack"):]
                block = block[:block.index("DisableWaitingAfterTextDisplay")]
                self.assertIn("SetEvent %s_1" % event, block)
                self.assertIn("SetEvent %s_2" % event, block)

    def test_headers_point_after_battle_at_the_after_handler(self) -> None:
        """Arg 5 used to loop back to the hideout line, unreachable while hidden."""
        for rel, _, handler in STAGE_SCRIPTS:
            with self.subTest(rel):
                for line in read(rel).splitlines():
                    if re.match(r"\s*trainer EVENT_BEAT_\w*STAGE_NPC_[12]|"
                                r"\s*trainer EVENT_BEAT_STAGE_EVENT_NPC_[12]", line):
                        self.assertTrue(line.rstrip().endswith(handler), line)


class AfterBattleTextContractTest(unittest.TestCase):
    def test_map_stubs_delegate_to_the_shared_body(self) -> None:
        """Bank 17 has tens of bytes free; four copies of this do not fit."""
        for rel, _, handler in STAGE_SCRIPTS:
            if handler == "PCStageEventAfterText" and "Cemetery" in rel:
                continue  # the Cemetery borrows the Cave's, by design
            with self.subTest(rel):
                body = routine(read(rel), handler + "::" if "Cave" in rel else handler + ":")
                self.assertIn("farcall StageEventPrintAfterLine", body)
                self.assertIn("jp TextScriptEnd", body)

    def test_shared_body_retries_only_from_owed(self) -> None:
        body = routine(STAGE_EVENTS.read_text(), "StageEventPrintAfterLine::",
                       end="\nStageEventPrintRecoverLine::")
        self.assertIn("cp STAGE_EVENT_PHASE_OWED << STAGE_EVENT_PHASE_SHIFT", body)
        self.assertIn("jr nz, .idle", body)
        self.assertIn("call StageEventGiveBack", body)
        # The retry prints its outcome through the same shared line printer the
        # automatic recovery uses, so the two can never word it differently.
        self.assertIn("jp StageEventPrintRecoverLine", body)

    def test_every_type_and_result_has_a_row(self) -> None:
        source = STAGE_EVENTS.read_text()
        after = routine(source, "StageEventAfterTexts:", end="StageEventRecoverTexts:")
        recover = routine(source, "StageEventRecoverTexts:",
                          end="StageEventAfterJessieJames:")
        self.assertEqual(after.count("\tdw "), const("NUM_STAGE_EVENT_TYPES"))
        self.assertEqual(recover.count("\tdw "), const("NUM_STAGE_GIVEBACK_RESULTS"))
        self.assertIn("ASSERT NUM_STAGE_EVENT_TYPES == 5", after)
        self.assertIn("ASSERT NUM_STAGE_GIVEBACK_RESULTS == 5", recover)

    def test_map_recover_handlers_are_thin_stubs(self) -> None:
        """One dispatcher and one set of strings, not four of each."""
        for rel, label in RECOVER_STUBS:
            with self.subTest(rel):
                source = read(rel)
                stub = routine(source, label)
                self.assertIn("farcall StageEventPrintRecoverLine", stub)
                self.assertIn("jp TextScriptEnd", stub)
                # The private table and wrappers must be gone, or a stale copy
                # can drift away from the shared strings.
                self.assertNotIn("StageEventRecoverTexts", source.replace(
                    "StageEventPrintRecoverLine", ""))
                self.assertNotIn("StageRecoverToBox", source)


class BoxTransferReusesTheCapturePathTest(unittest.TestCase):
    """The give-back's box case is the capture path's event, so it says and
    does the same things: ItemUseBall's transfer wording, its EVENT_MET_BILL
    split, and its box-full follow-up."""

    def setUp(self) -> None:
        self.body = routine(STAGE_EVENTS.read_text(), "StageEventPrintRecoverLine::",
                            end="StageEventAfterTexts:")

    def test_box_result_is_intercepted_before_the_table(self) -> None:
        self.assertIn("cp STAGE_GIVEBACK_TO_BOX", self.body)
        self.assertLess(self.body.index("cp STAGE_GIVEBACK_TO_BOX"),
                        self.body.index("ld hl, StageEventRecoverTexts"))

    def test_bill_split_matches_the_capture_path(self) -> None:
        to_box = self.body[self.body.index("\n.toBox\n"):]
        self.assertIn("CheckEvent EVENT_MET_BILL", to_box)
        self.assertIn("StageEventRecoverToBoxBill", to_box)
        self.assertIn("StageEventRecoverToBoxPC", to_box)
        # hl is loaded BEFORE the test, which is only legal because this
        # tree's CheckEvent clobbers `a` alone. Guard that premise.
        macro = (REPO_ROOT / "macros" / "scripts" / "events.asm").read_text()
        check = macro[macro.index("MACRO CheckEvent"):]
        check = check[:check.index("ENDM")]
        self.assertNotIn("ld hl", check)

    def test_box_full_reminder_is_reused_not_reinvented(self) -> None:
        """The capture path prints it; a give-back into slot 20 must too."""
        self.assertIn("farcall BridgeMaybePrintBoxFullReminder", self.body)
        to_box = self.body[self.body.index("\n.toBox\n"):]
        self.assertIn("farcall BridgeMaybePrintBoxFullReminder", to_box)
        # Gated on the RESULT. The helper's own guard only asks whether the box
        # is full, so an item handed back into an already-full box would
        # otherwise announce a transfer that never happened.
        self.assertNotIn("BridgeMaybePrintBoxFullReminder",
                         self.body[:self.body.index("\n.toBox\n")])

    def test_transfer_line_names_the_right_mon(self) -> None:
        """The capture path reads wBoxMonNicks because it FRONT-inserts.

        The give-back appends at wBoxCount, so box slot 0 is somebody else.
        """
        source = STAGE_TEXT.read_text()
        for name in ("_StageEventRecoverToBoxBillText", "_StageEventRecoverToBoxPCText"):
            with self.subTest(name):
                body = routine(source, name + "::", code=False)
                body = body[:body.index("prompt")]
                self.assertIn("text_ram wNameBuffer", body)
                self.assertNotIn("wBoxMonNicks", body)

    def test_transfer_line_waits_so_the_reminder_cannot_erase_it(self) -> None:
        """PrintText redraws the box, so a second line with no wait wipes it."""
        source = STAGE_TEXT.read_text()
        for name in ("_StageEventRecoverToBoxBillText", "_StageEventRecoverToBoxPCText"):
            with self.subTest(name):
                body = routine(source, name + "::", code=False)
                head = body[:body.index("prompt")]
                self.assertNotIn("@", head)  # '@' before a prompt orphans it

    def test_new_strings_fit_the_box(self) -> None:
        source = STAGE_TEXT.read_text()
        names = ["_StageEventAfter%sText" % n for n in
                 ("JessieJames", "Psychic", "Burglar", "Joy", "Jenny")]
        names += ["_StageEventRecoverToBoxBillText",
                  "_StageEventRecoverToBoxPCText",
                  "_StageEventRecoverNoRoomText"]
        for name in names:
            with self.subTest(name):
                self.assertIn(name + "::", source)
                body = routine(source, name + "::", code=False)
                stop = min(i for i in (body.find("text_end"), body.find("prompt"))
                           if i != -1)
                body = body[:stop]
                for literal in re.findall(r'\b(?:text|line|cont|para) "([^"]*)"', body):
                    # "#" expands to POKeMON; count it as 7 columns, not 1.
                    width = len(literal) + literal.count("#") * 6
                    # A leading text_ram is a nickname of up to 10 columns.
                    self.assertLessEqual(width, 18, literal)


if __name__ == "__main__":
    unittest.main()
