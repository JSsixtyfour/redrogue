"""Audit: the good NPCs (Joy, Jenny) are FOUND, not met.

The user's design, restated 2026-09-17 after the first play session: "these are
two separate encounters ... only one should appear at a time ... they should
not initially confront the player when the player spawns. They should just
exist in their spots as something the player can find without any prior
warning."

Phase 7f got the first half right - a good NPC never runs the villains'
vanish-and-hide sequence - and the second half wrong in two ways that this
script now pins down:

  1. BOTH of them appeared at once. STAGE_EVENT_BOTH_GOOD (type 6) put Joy and
     Jenny on the map together. STAGE_EVENT_MAX_ROLLABLE is 5 as of
     2026-09-17, so type 6 is unreachable; its rows stay in all seven parallel
     tables on purpose.
  2. They AMBUSHED the player. The type gate sat below the DisplayTextID, so a
     good NPC delivered the villain's arrival box the instant the map faded in
     and then stood at the entrance for the rest of the visit. The gate moved
     above the theft, and their placement routine learned to take the hideout
     branch regardless of phase.

So the contract measured here is:

  A. rolling never yields type 6
  B. on entry, with NO input at all, a good NPC's phase is already SETTLED -
     no greeting was shown and none is waiting to be dismissed
  C. on entry, both NPC slots are at the HIDEOUT, not at the entrance
  D. they still never move afterwards, and never enter HIDING
  E. StageEventRoundTier's ladder still gives 2/2/3/3/4/4/5/5/6 across rounds

B and C are differential: the same checks run for a VILLAIN, which must still
arrive at the entrance with its greeting up. Without that control, a build
where the stage event never armed at all would pass B and C trivially - which
is exactly the failure mode `project_fixture_hides_missing_production_code`
records.

Usage:
    python3 tools/pyboy_smoke/audit_stage_event_good_npc.py
"""

from __future__ import annotations

import random
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants, parse_trainer_class_indexes  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
SRAM_BANK = 0
SPRITE_SLOTS = 7
NPC1, NPC2 = 5, 6          # 0-based indexes of object slots 6 and 7
ENTRANCE_BLOCK = (9, 19)   # the cave's pinned entrance


def stage_event_constants() -> dict:
    text = (REPO_ROOT / "constants" / "ram_constants.asm").read_text()
    out = {}
    for name, value in re.findall(r"^DEF (STAGE_EVENT_\w+)\s+EQU\s+(\S+)", text, re.M):
        value = value.strip()
        if value.startswith("$"):
            out[name] = int(value[1:], 16)
        elif value.startswith("%"):
            out[name] = int(value[1:], 2)
        elif value.isdigit():
            out[name] = int(value)
        elif value in out:
            out[name] = out[value]
    return out


def run_arrival(event_type: int, label: str, good: bool, const: dict,
                failures: list) -> None:
    phase_mask = const["STAGE_EVENT_PHASE_MASK"]
    phase_shift = const["STAGE_EVENT_PHASE_SHIFT"]
    hiding = const["STAGE_EVENT_PHASE_HIDING"]
    settled = const["STAGE_EVENT_PHASE_SETTLED"]
    waiting = const["STAGE_EVENT_PHASE_WAITING"]
    map_id = parse_map_constants(
        REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", event_type)
        h.preload_and_enter_wild_area(map_id, "Procedural Cave")

        player = (h.read8("wXCoord"), h.read8("wYCoord"))
        before = [tuple(p) for p in h.sprite_positions(SPRITE_SLOTS)]
        npc1_before = (before[NPC1][1], before[NPC1][0])   # (x, y) in steps
        npc2_before = (before[NPC2][1], before[NPC2][0])
        entry_phase = (h.read8("wStageEvent") & phase_mask) >> phase_shift
        hx = h.read_sram_bytes("sStageEventHideoutX", 1, bank=SRAM_BANK)[0]
        hy = h.read_sram_bytes("sStageEventHideoutY", 1, bank=SRAM_BANK)[0]

        at_entrance = (npc1_before[0] // 2, npc1_before[1] // 2) == ENTRANCE_BLOCK
        at_hideout = (npc1_before[0] // 2, npc1_before[1] // 2) == (hx, hy)

        print("%-10s type %d: player=%s npc1=%s npc2=%s hideout=(%d,%d) "
              "entry phase=%d %s"
              % (label, event_type, player, npc1_before, npc2_before, hx, hy,
                 entry_phase,
                 "AT-HIDEOUT" if at_hideout else
                 ("AT-ENTRANCE" if at_entrance else "elsewhere")))

        if good:
            # B: no greeting was shown and none is pending.
            if entry_phase != settled:
                failures.append(
                    "%s: phase is %d on arrival with no input, expected SETTLED "
                    "(%d). A good NPC's type gate must run BEFORE the "
                    "DisplayTextID, so no greeting is ever displayed."
                    % (label, entry_phase, settled))
            # C: at the hideout from the first frame.
            if not at_hideout:
                failures.append(
                    "%s: slot 6 is at step %s = block %s on arrival, but the "
                    "hideout is block (%d,%d). They must be placed there from "
                    "the first frame - nothing repositions them later, because "
                    "the vanish is exactly what they skip."
                    % (label, npc1_before,
                       (npc1_before[0] // 2, npc1_before[1] // 2), hx, hy))
            if at_entrance:
                failures.append(
                    "%s: slot 6 is standing on the entrance block - this is the "
                    "reported ambush" % label)
        else:
            # The control. A villain must still do the old thing.
            if entry_phase != waiting:
                failures.append(
                    "%s (CONTROL): phase is %d on arrival, expected WAITING "
                    "(%d) - the villain's greeting should be up. If this fails "
                    "the good-NPC checks above prove nothing, because the event "
                    "is not arming at all."
                    % (label, entry_phase, waiting))
            if not at_entrance:
                failures.append(
                    "%s (CONTROL): slot 6 is at block %s, not the entrance %s - "
                    "villains must still arrive in front of the player"
                    % (label, (npc1_before[0] // 2, npc1_before[1] // 2),
                       ENTRANCE_BLOCK))

        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)

        after_phase = (h.read8("wStageEvent") & phase_mask) >> phase_shift
        after = [tuple(p) for p in h.sprite_positions(SPRITE_SLOTS)]
        npc1_after = (after[NPC1][1], after[NPC1][0])

        if good:
            # D
            if after_phase != settled:
                failures.append("%s: phase is %d after input, expected SETTLED "
                                "(%d)" % (label, after_phase, settled))
            if after_phase == hiding:
                failures.append("%s: phase is HIDING - the villain vanish ran "
                                "for a good NPC" % label)
            if npc1_after != npc1_before:
                failures.append("%s: slot 6 moved from %s to %s - a good NPC "
                                "must stay put" % (label, npc1_before, npc1_after))
        else:
            if after_phase != hiding:
                failures.append(
                    "%s (CONTROL): phase is %d after the greeting, expected "
                    "HIDING (%d) - the vanish did not run"
                    % (label, after_phase, hiding))
    finally:
        try:
            h.close()
        except Exception:
            pass


def run_roll_distribution(const: dict, failures: list) -> None:
    """A: StageEventRoll must never produce a type above MAX_ROLLABLE.

    Phrased as "above MAX_ROLLABLE" rather than "equal to STAGE_EVENT_BOTH_GOOD"
    because that constant no longer exists - it is commented out in
    ram_constants.asm now that the pair cannot roll - and reading it by name
    crashed this audit with a KeyError. The general form is also strictly
    stronger: it catches a seventh type added later just as well.
    """
    max_rollable = const["STAGE_EVENT_MAX_ROLLABLE"]
    type_mask = const["STAGE_EVENT_TYPE_MASK"]

    seen = {}
    # call_routine corrupts the machine after roughly ten invocations per boot,
    # so this is spread over fresh boots rather than looped on one.
    #
    # EVERY BOOT MUST BE RESEEDED. Without this the boots are identical, replay
    # the same nine rolls, and the sample is 9 wide while the total reads 36 -
    # which would drop the confidence that type 6 is gone from ~99.9% to ~81%
    # while looking stronger on the page. Measured: unseeded gave exactly
    # {1: 20, 3: 8, 5: 8}, i.e. 5+2+2 repeated four times.
    for boot in range(4):
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby()
            rng = random.Random(boot)
            base = h.address("wRandomTable")
            for offset in range(10):
                h.pyboy.memory[base + offset] = rng.randrange(1, 256)
            for i in range(9):
                h.write8("wStageEvent", 0)
                h.call_routine("StageEventRoll", limit=4000)
                t = h.read8("wStageEvent") & type_mask
                seen[t] = seen.get(t, 0) + 1
        finally:
            try:
                h.close()
            except Exception:
                pass

    total = sum(seen.values())
    print("roll distribution over %d rolls: %s"
          % (total, {k: seen[k] for k in sorted(seen)}))
    over = sorted(t for t in seen if t > max_rollable)
    if over:
        failures.append(
            "StageEventRoll produced type(s) %s, above STAGE_EVENT_MAX_ROLLABLE "
            "(%d), %d times in %d rolls. Type 6 was Joy and Jenny together; they "
            "are separate encounters and only one may appear per wild area."
            % (over, max_rollable, sum(seen[t] for t in over), total))
    # The same sample has to show the roll IS live, or "never 6" is vacuous.
    if len([k for k in seen if k]) < 3:
        failures.append(
            "only %d distinct armed types in %d rolls - the roll looks dead, so "
            "'never type 6' proves nothing" % (len([k for k in seen if k]), total))


def run_round_tier(failures: list) -> None:
    classes = parse_trainer_class_indexes(REPO_ROOT / "constants" / "trainer_constants.asm")
    expected_n = {1: 2, 2: 2, 3: 3, 4: 3, 5: 4, 6: 4, 7: 5, 8: 5, 9: 6}
    battle_counts = {1: 0, 2: 15, 3: 25, 4: 35, 5: 45, 6: 55, 7: 65, 8: 75, 9: 85}

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_fight2(seed=1)
        for round_n, bc in battle_counts.items():
            h.write8("wBattleCount", bc)
            h.write8("wTrainerClass", classes["NURSE_JOY"])
            # Drive RogueBuildParty directly against the round-derived wTrainerNo,
            # mirroring what StageEventRoundTier would compute for this wBattleCount.
            h.write8("wTrainerNo", round_n)
            h.call_routine("ReadTrainer", limit=600)
            n = h.read8("wEnemyPartyCount")
            print("round %d (wBattleCount=%d): wEnemyPartyCount=%d (want %d)"
                  % (round_n, bc, n, expected_n[round_n]))
            if n != expected_n[round_n]:
                failures.append("round %d: party count %d, expected %d"
                                % (round_n, n, expected_n[round_n]))
    finally:
        try:
            h.close()
        except Exception:
            pass


def main() -> int:
    const = stage_event_constants()
    failures: list = []

    run_roll_distribution(const, failures)
    run_arrival(const["STAGE_EVENT_JESSIE_JAMES"], "villain", False, const, failures)
    run_arrival(const["STAGE_EVENT_JOY"], "joy", True, const, failures)
    run_arrival(const["STAGE_EVENT_JENNY"], "jenny", True, const, failures)
    run_round_tier(failures)

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: good NPCs wait at the hideout with no greeting, villains still "
          "arrive and vanish, type 6 never rolls, and teams scale with the round")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
