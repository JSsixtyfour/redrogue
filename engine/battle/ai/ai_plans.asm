; AI strategy plans (AI_OVERHAUL_PLAN.md Phase 5), bank $2C half.
;
; PINNED to bank $2C for the same reasons ai_switching.asm is - see that file's
; header for the full rationale (ROM_BIBLE.md section 5 rule 6: Red, Blue and
; Debug first-fit independently, and a floated section of this size could land
; in a different, tight bank in one variant only). A SEPARATE section from the
; switching engine rather than an extension of it, so either can be relocated
; without dragging the other.
;
; WHY THIS IS NOT IN BANK $0E, unlike every AILayer* routine: plan selection and
; execution happen once per TURN, not once per move, so they are outside the
; dispatcher's same-bank `jp hl` constraint entirely. That matters here more
; than anywhere else in the AI, because bank $0E had 472 bytes free across all
; three ROMs when Phase 5 started and this file alone is several times that.
; engine/battle/ai/ai_plan.asm holds the (small) half that genuinely must be in
; $0E; see its header for the split.
;
; Farcall discipline: across a farcall only de, hl and the flags survive in
; either direction, a is destroyed inbound (Bankswitch's first instruction) and
; a/bc are destroyed outbound. Every predicate reached from here returns its
; answer in CARRY for exactly that reason.

SECTION "Trainer AI Plans", ROMX, BANK[$2C]

; --- Tuning ---------------------------------------------------------------
; Plan-specific numbers live here rather than in constants/ai_constants.asm, so
; adding a plan is one file's edit. Only the invariants every plan must respect
; (AI_PLAN_MAX_MAGNITUDE, AI_PLAN_INCUMBENCY) are shared constants.

; AIFit_Bruiser's constant. Deliberately small: it must lose to any plan that
; has an actual idea, even after that rival plan holds incumbency.
DEF AI_FITNESS_FALLBACK EQU 4

DEF AI_FITNESS_AGILITY_WRAP EQU 40
DEF AI_FITNESS_AGILITY_SLOW EQU 20 ; added when the enemy is currently SLOWER,
                                   ; which is when the speed boost is doing real
                                   ; work rather than being a spare turn

; How many turns the plan will spend trying to win the speed race before it
; gives up and traps anyway. Bounded because "boost until faster" has a real
; non-terminating case: the player may also be boosting, or the enemy may be
; paralysed, in which case Agility never wins and the plan would loop forever.
DEF AI_AGILITY_MAX_ATTEMPTS EQU 2

; --- Plan table -----------------------------------------------------------
; Layout: required class mask, fitness routine, execute routine.
;
; A plan is a CANDIDATE when every class in its required mask appears somewhere
; in the mon's moveset (see AIPlanQualifies). "Somewhere" is deliberately not
; "in one move" - a mon satisfies TRAP | BOOST_SPD with Wrap in one slot and
; Agility in another, which is the point.
;
; The required mask is a coarse filter only. Anything finer - "any ONE of the
; three boost classes", "and the trap is not type-immune" - belongs in the
; fitness routine, which is why the table stays six bytes per entry instead of
; carrying a second any-of mask.

MACRO ai_plan
	dw \1 ; required class mask
	dw \2 ; fitness routine  -> a = 0..255, 0 meaning "never run this"
	dw \3 ; execute routine  -> de = class mask, l = magnitude (0 = nothing)
ENDM

DEF AI_PLAN_ENTRY_SIZE EQU 6

AIPlanTable:
	ai_plan 0, AIFit_Bruiser, AIRun_Bruiser
	ai_plan AICLASS_TRAP | AICLASS_BOOST_SPD, AIFit_AgilityWrap, AIRun_AgilityWrap
	assert (@ - AIPlanTable) / AI_PLAN_ENTRY_SIZE == NUM_AI_PLANS, \
		"AIPlanTable must have exactly NUM_AI_PLANS entries, indexed by plan id - 1"

; ---------------------------------------------------------------------------
; The single entry point bank $0E farcalls into, once per turn.
;
; OUTPUT: de = class mask to encourage, l = magnitude (0 = no directive),
;         h reserved and zero. See ai_plan.asm's header for why the directive
;         is shaped to fit de/hl.
;
; ONE DIRECTIVE, ENCOURAGE ONLY - and that is a design decision, not a register
; shortage. Plans steer by making the move they want cheaper; they never need to
; suppress an alternative, because suppression is what the other layers already
; do and because AI_PLAN_MAX_MAGNITUDE keeps every directive below AI_KILL. That
; combination is what makes "set up" and "take the win in front of you"
; automatically resolve the right way round: a plan cannot out-argue a kill
; AI_DAMAGE has already found, which is rank 1 of the priority cascade.
AIPlanSelectAndExecute::
	call AIPlanSelect ; resolves wAIPlan (and clears wAIPlanStep on a change)

	ld a, [wAIPlan]
	and a
	jr z, .noDirective
	dec a ; plan ids are 1-based; the table is 0-based
	ld hl, AIPlanTable + 4 ; the execute pointer within entry 0
	ld bc, AI_PLAN_ENTRY_SIZE
	call AddNTimes
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp hl ; the execute routine's own ret returns through Bankswitch

.noDirective
	ld hl, 0
	ret

; ---------------------------------------------------------------------------
; Picks the plan for this turn and writes it to wAIPlan, clearing wAIPlanStep
; whenever the plan actually changes.
;
; RE-RUN EVERY TURN, WITH AN INCUMBENCY BONUS - a deliberate deviation from the
; plan document, which specified abort conditions plus an exclusion set of
; already-aborted plans. Re-selecting with hysteresis subsumes that design and
; is strictly cheaper: a plan that has become impossible returns 0 from its own
; fitness routine and loses to the fallback with no bookkeeping, a plan that has
; merely become worse loses only if a rival beats it by more than
; AI_PLAN_INCUMBENCY, and there is no exclusion set to allocate WRAM for or to
; forget to clear. It is the same shape as Phase 4's anti-ping-pong guard: the
; failure mode being defended against is oscillation, and the fix is hysteresis
; rather than memory of what was already tried.
;
; Every register the loop needs is pushed across the fitness call, because a
; fitness routine may clobber anything - several of them farcall into the damage
; simulator, which destroys a and bc on the way back by itself.
AIPlanSelect:
	ld b, 0                ; best fitness seen
	ld c, AI_PLAN_NONE     ; plan it belongs to
	ld d, AI_PLAN_NONE + 1 ; plan id under consideration
	ld hl, AIPlanTable

.nextPlan
	ld a, d
	cp NUM_AI_PLANS + 1
	jr nc, .done

	call AIPlanQualifies ; hl -> this entry's required mask; preserves bc/de/hl
	jr nc, .skipPlan

	push hl
	push de
	push bc
	inc hl
	inc hl ; hl -> fitness pointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	call .callFitness ; a = fitness; may clobber everything else
	pop bc
	pop de
	pop hl ; POP rr never touches a or the flags, so the fitness survives all three

	and a
	jr z, .skipPlan ; 0 means "this plan cannot run right now"

; Incumbency. Applied here rather than inside each fitness routine so that a new
; plan cannot forget it, and saturating rather than wrapping so a high-fitness
; incumbent does not fall to near zero.
	push af
	ld a, [wAIPlan]
	cp d
	jr nz, .notIncumbent
	pop af
	add AI_PLAN_INCUMBENCY
	jr nc, .compare
	ld a, $ff
	jr .compare
.notIncumbent
	pop af

.compare
	cp b
	jr c, .skipPlan ; strictly worse
	jr z, .skipPlan ; a tie keeps the earlier table entry, so table ordering is
	                ; a deliberate tiebreak rather than an accident
	ld b, a
	ld c, d

.skipPlan
	ld a, l
	add AI_PLAN_ENTRY_SIZE
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	inc d
	jr .nextPlan

.done
	ld a, [wAIPlan]
	cp c
	ret z ; unchanged - crucially, wAIPlanStep is left alone, so a multi-turn
	      ; plan keeps its progress
	ld a, c
	ld [wAIPlan], a
	xor a
	ld [wAIPlanStep], a
	ret

.callFitness
	jp hl

; ---------------------------------------------------------------------------
; Carry SET if every class in the 16-bit required mask at [hl] appears somewhere
; in the active mon's moveset.
; INPUT: hl -> a 16-bit little-endian required mask.
; Preserves bc, de and hl. Clobbers af.
AIPlanQualifies:
	push bc
	push de
	push hl
	call AIPlanUnionMask ; de = union of the four per-slot masks; clobbers hl
	pop hl
	ld a, [hli]
	ld b, a
	ld a, [hl]
	ld c, a ; bc = required mask
	dec hl  ; leave hl exactly where the caller left it
	ld a, e
	and b
	cp b
	jr nz, .no
	ld a, d
	and c
	cp c
	jr nz, .no
	pop de
	pop bc
	scf
	ret
.no
	pop de
	pop bc
	and a ; clear carry
	ret

; ---------------------------------------------------------------------------
; OUTPUT: de = the OR of all four per-slot class masks, i.e. everything this
; mon's moveset can do. Recomputed on demand rather than cached, because
; AIClassifyMoveset rewrites the per-slot masks at the top of every turn and a
; cached union would be one more thing that can go stale - see
; project_wram_union_clobbering for why shared scratch with two owners is a bug
; class here rather than a hypothetical.
; Clobbers af, bc, hl.
AIPlanUnionMask::
	ld hl, wBuffer + AI_BUF_PLANCLASS
	ld d, 0
	ld e, 0
	ld b, NUM_MOVES
.next
	ld a, [hli]
	or e
	ld e, a
	ld a, [hli]
	or d
	ld d, a
	dec b
	jr nz, .next
	ret

; ---------------------------------------------------------------------------
; Finds a move belonging to a class.
; INPUT:  de = class mask to search for.
; OUTPUT: carry SET and a = the move id of the first slot carrying any class in
;         the mask; carry clear and a undefined if no slot does.
; Clobbers af, bc, hl.
AIPlanFindClassMove:
	ld hl, wBuffer + AI_BUF_PLANCLASS
	ld b, 0 ; slot index
.next
	ld a, [hli]
	and e
	jr nz, .foundLowByte
	ld a, [hli]
	and d
	jr nz, .found
	inc b
	ld a, b
	cp NUM_MOVES
	jr c, .next
	and a ; clear carry: no slot carries this class
	ret
.foundLowByte
	inc hl ; the high byte was not consumed on this path
.found
	ld hl, wEnemyMonMoves
	ld c, b
	ld b, 0
	add hl, bc
	ld a, [hl]
	scf
	ret

; ---------------------------------------------------------------------------
; Carry SET if a move of the given class exists AND is not type-immune against
; the player's mon.
; INPUT: de = class mask.
; Clobbers af, bc, de, hl, and the wEnemyMove* block.
;
; Uses AIGetTypeEffectiveness - the same single-type check AI_TYPES scores with
; and AIHasSuperEffectiveMove tests with - rather than PreviewTypeMatchup's
; dual-type accumulator, deliberately: a plan must not decide a move is viable
; on a different reading of the board than the layer that will score it. See
; AI_OVERHAUL_PLAN.md follow-up F7 for why $10 rather than 10 is this engine's
; neutral sentinel; zero is zero either way, which is all this asks.
AIPlanClassMoveLands:
	call AIPlanFindClassMove
	ret nc
	ld e, a
	farcall AIReadMoveFromE ; fills wEnemyMoveType, which the next call reads
	farcall AIGetTypeEffectiveness
	ld a, [wTypeEffectiveness]
	and a
	ret z ; immune: carry is already clear
	scf
	ret

; ===========================================================================
; PLAN: Bruiser - the guaranteed fallback
; ===========================================================================
; Required mask 0, so it qualifies for every mon that exists. Its whole job is
; to guarantee AIPlanSelect always lands on a valid plan, which is what lets
; every other plan return a fitness of 0 freely without the selector needing a
; "nothing qualified" branch of its own.

AIFit_Bruiser:
	ld a, AI_FITNESS_FALLBACK
	ret

; NO DIRECTIVE, on purpose. The obvious implementation - nudge AICLASS_DAMAGE -
; would be a blanket bias toward damage over status on every T3 trainer with no
; better plan, which is exactly the mistake the plan document warns about at
; length ("do not let the 0-BP penalty swallow status"): RBY is won by status,
; and AI_DAMAGE already ranks damaging moves against each other on real expected
; damage. "No plan" is a legitimate state and should score like one.
AIRun_Bruiser:
	ld hl, 0
	ret

; ===========================================================================
; PLAN: AgilityWrap - win the speed race, then soft-lock
; ===========================================================================
; The reference plan, written end-to-end as the template every other entry in
; AIPlanTable is meant to be written against.
;
; The line: a partial-trapping move locks the target out of acting entirely, and
; if the trapper is FASTER it re-locks the moment the previous lock expires -
; a soft-lock the target never escapes. Speed is the whole precondition, which
; is why the speed boost comes first and why being slower is what makes the
; boost valuable rather than a wasted turn.

; Fitness. Written cheapest-rejection-first, so the common "this plan cannot
; work" cases cost the least. The class filter has already guaranteed both moves
; exist, so this only has to establish that the plan can still WORK.
AIFit_AgilityWrap:
; ENGINE TRUTH, not strategy: trapping now respects type immunity in this
; codebase (a Wrap on a Ghost fails outright - engine/battle/effects.asm runs
; the immunity check BEFORE set USING_TRAPPING_MOVE). The plan document flags
; this specific fitness routine as one that MUST check it or commit to a move
; that cannot work. Cheap here because the classifier already knows which slot
; holds the trap move.
	ld de, AICLASS_TRAP
	call AIPlanClassMoveLands
	jr nc, .no

; A two-turn setup needs two turns to spend. Below half HP, or with a lethal
; player move on the board, the turn spent boosting is a turn the mon does not
; have - and unlike a status move, a speed boost does nothing to prevent the KO.
	farcall AIEnemyHPBelowHalf
	jr c, .no
	farcall AIPlayerWouldKO
	jr c, .no

	farcall AIEnemyIsFaster
	ld a, AI_FITNESS_AGILITY_WRAP
	ret c ; already outspeeding - still a fine plan, it just skips its first step
	add AI_FITNESS_AGILITY_SLOW ; `ld a, n` sets no flags, so the carry tested
	                            ; above is still the speed answer here
	ret
.no
	xor a
	ret

; Execute. Three states, but only ONE of them is stored: whether the trap is
; currently locked in, and whether the enemy outspeeds the player, are both live
; board state, so reading them is strictly better than tracking them - a mon
; that gets paralysed mid-plan correctly falls back to boosting, with no
; explicit abort condition needed anywhere.
;
; wAIPlanStep counts BOOST ATTEMPTS, not successes, and that is the intent: it
; exists solely to bound the one case that does not terminate on its own. If the
; player is also boosting, or the enemy is paralysed, the speed race is
; unwinnable and "boost until faster" would loop for the rest of the battle.
; After AI_AGILITY_MAX_ATTEMPTS the plan traps anyway and takes the lock it can
; get. Counting attempts rather than successes is what makes the bound hold even
; on turns when AI_DAMAGE overrides the directive to take a kill.
AIRun_AgilityWrap:
	ld a, [wEnemyBattleStatus1]
	bit USING_TRAPPING_MOVE, a
	jr nz, .locked

	farcall AIEnemyIsFaster
	jr c, .trap

	ld a, [wAIPlanStep]
	cp AI_AGILITY_MAX_ATTEMPTS
	jr nc, .trap
	inc a
	ld [wAIPlanStep], a
	ld de, AICLASS_BOOST_SPD
	ld hl, AI_VERY_STRONG
	ret

.trap
	ld de, AICLASS_TRAP
	ld hl, AI_VERY_STRONG
	ret

.locked
; The lock is in. Nothing to steer: the target is not acting, so AI_DAMAGE's
; ranking of the remaining moves is already the right answer, and re-encouraging
; the trap move would fight the engine's own multi-turn lock handling.
	ld hl, 0
	ret

; ===========================================================================
; Effect -> class lookup
; ===========================================================================
; INPUT:  e = a move effect id.
; OUTPUT: de = that effect's static class mask, or 0 if the effect carries no
;         class. Returning in de is mandatory, not stylistic: this is farcalled
;         from AIClassifyMoveset in bank $0E, and de is the only register pair
;         that survives a farcall in both directions.
; Clobbers af, bc, hl.
AIPlanLookupEffect::
	ld a, e
	ld c, a
	ld hl, AIMoveClassTable
	ld de, AI_MOVECLASS_ENTRY_SIZE
	call IsInArray
	jr nc, .none
	inc hl ; step past the effect byte IsInArray matched on
	ld a, [hli]
	ld d, [hl]
	ld e, a
	ret
.none
	ld de, 0
	ret

DEF AI_MOVECLASS_ENTRY_SIZE EQU 3 ; effect id (1) + class mask (2)

; Keyed on the EFFECT byte the engine itself dispatches on, so a class can never
; disagree with what a move actually does - see constants/ai_constants.asm for
; why this replaced the plan document's per-move table.
;
; Absence from this table is meaningful and common: an ordinary attack has no
; special effect, and AIClassifyMoveset gives it AICLASS_DAMAGE from its power
; alone. Only moves whose PURPOSE is something other than "deal damage" need an
; entry here, plus the two fixed-damage families, which deal damage while
; carrying a base power of zero and so would otherwise classify as nothing.
AIMoveClassTable:
	dbw SLEEP_EFFECT,           AICLASS_SLEEP
	dbw PARALYZE_EFFECT,        AICLASS_PARALYZE
	dbw POISON_EFFECT,          AICLASS_POISON
	dbw CONFUSION_EFFECT,       AICLASS_CONFUSE
	dbw TRAPPING_EFFECT,        AICLASS_TRAP
	dbw HEAL_EFFECT,            AICLASS_RECOVERY
	dbw SPEED_UP1_EFFECT,       AICLASS_BOOST_SPD
	dbw SPEED_UP2_EFFECT,       AICLASS_BOOST_SPD
	dbw ATTACK_UP1_EFFECT,      AICLASS_BOOST_ATK
	dbw ATTACK_UP2_EFFECT,      AICLASS_BOOST_ATK
	dbw SPECIAL_UP1_EFFECT,     AICLASS_BOOST_SPC
	dbw SPECIAL_UP2_EFFECT,     AICLASS_BOOST_SPC
	dbw DEFENSE_UP1_EFFECT,     AICLASS_BOOST_DEF
	dbw DEFENSE_UP2_EFFECT,     AICLASS_BOOST_DEF
	dbw LIGHT_SCREEN_EFFECT,    AICLASS_SCREEN
	dbw REFLECT_EFFECT,         AICLASS_SCREEN
	dbw MIST_EFFECT,            AICLASS_SCREEN
	dbw SUBSTITUTE_EFFECT,      AICLASS_SUB
	dbw EXPLODE_EFFECT,         AICLASS_EXPLODE | AICLASS_DAMAGE
	dbw OHKO_EFFECT,            AICLASS_OHKO
	dbw LEECH_SEED_EFFECT,      AICLASS_DRAIN
; Dream Eater and the draining moves deal damage AND recover with it, so they
; carry both classes. Dream Eater is not AICLASS_SLEEP: it does not CAUSE sleep,
; it consumes it, and a sleep plan that steered toward it would be picking the
; move that only works after the plan has already succeeded.
	dbw DRAIN_HP_EFFECT,        AICLASS_DRAIN | AICLASS_DAMAGE
	dbw DREAM_EATER_EFFECT,     AICLASS_DRAIN | AICLASS_DAMAGE
; Fixed damage: Seismic Toss, Night Shade, Sonic Boom, Dragon Rage, Psywave and
; Super Fang all have a base power of zero, so the classifier's power test never
; fires for them. They are unambiguously damaging moves and several are among
; the best ones a low-Attack mon owns (Phase 3 Step 3), so they are named here.
	dbw SPECIAL_DAMAGE_EFFECT,  AICLASS_DAMAGE
	dbw SUPER_FANG_EFFECT,      AICLASS_DAMAGE
	db -1
