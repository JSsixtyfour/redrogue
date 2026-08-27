; creates a set of moves that may be used and returns its address in hl
; unused slots are filled with 0, all used slots may be chosen with equal probability
AIEnemyTrainerChooseMoves:
; PERF (2026-08-27): run the whole decision in CGB double speed, then drop back
; to single before returning. Measured at 480,086 cycles / ~6.8 frames / ~114ms
; at T3 even after the _Divide optimisation (AI_PERF_INVESTIGATION.md), which is
; a visible hitch before every enemy move.
;
; Battle deliberately runs at SINGLE speed - init_battle_variables.asm does
; `predef SingleCPUSpeed ; battle transitions have known double-speed visual
; faults` - so this is a NARROW, self-restoring exception, not a change to that
; policy. It is safe precisely because the hazard is TRANSITIONS (rendering),
; and move selection renders nothing: it is pure computation between frames.
; Exact precedent: engine/battle/experience.asm wraps the EXP calculation the
; same way inside the same single-speed battle ("shaves off about 1 second").
;
; SetCPUSpeed honours the player's 60 FPS option (wOptions2 BIT_60_FPS) rather
; than forcing double, so with the option off BOTH calls are no-ops and no
; `stop` is executed. predef preserves bc/de/hl (GetPredefPointer saves them,
; GetPredefRegisters restores them), so the `hl` this routine returns survives
; the exit call - which is why the paired call sits AFTER each `ld hl`.
	predef SetCPUSpeed

; Phase 2b: snapshot last turn's move/power for the anti-spam and
; repeated-move-fatigue heuristics. MUST run before the scoring layers, whose
; ReadMove calls overwrite the wEnemyMove* block this reads from. See
; AITrackLastMove in ai_predicates.asm for why this needs no core.asm hook.
	call AITrackLastMove
	ld a, AI_SCORE_BASE ; Phase 2b: was a hardcoded $a; the baseline is now a
	                    ; constant so widening it is a single edit
	ld hl, wBuffer ; init temporary move selection array. Only the moves with the lowest numbers are chosen in the end
	ld [hli], a   ; move 1
	ld [hli], a   ; move 2
	ld [hli], a   ; move 3
	ld [hl], a    ; move 4
	ld a, [wEnemyDisabledMove] ; forbid disabled move (if any)
	swap a
	and $f
	jr z, .noMoveDisabled
	ld hl, wBuffer
	dec a
	ld c, a
	ld b, $0
	add hl, bc    ; advance pointer to forbidden move
	ld [hl], $50  ; forbid (highly discourage) disabled move
.noMoveDisabled
; AI Overhaul Phase 1: which scoring layers run is now driven by the
; battle-count-derived SKILL TIER, not by the trainer class. AIGetLayerWord
; returns the tier's 16-bit layer bitmask; layers execute in bit order.
; It returns in de because Bankswitch destroys a and bc but preserves de/hl.
	farcall AIGetLayerWord ; de = layer bitmask for this battle's tier
.beforeLayers ; harness hook point only (tools/pyboy_smoke): the last instant
              ; before any scoring layer runs, so a test scenario can prime
              ; WRAM (e.g. HP, to hit an exact predicate band deterministically)
              ; and have every layer - including AI_REDUNDANT - see it, not
              ; just layers that happen to run later in the bit order. Must
              ; stay a distinct address from .nextLayer (needs a real
              ; instruction between them): hook_ai_scores() already hooks
              ; .nextLayer, and PyBoy allows only one hook per address.
	ld b, 0                ; b = layer index
.nextLayer
	ld a, b
	cp NUM_AI_LAYERS
	jr nc, .layersDone     ; stop before the flag bits: they are data, not routines
	srl d
	rr e                   ; carry = "is layer b enabled"
	jr nc, .skipLayer
	push de
	push bc
	ld hl, AIScoringPointers
	ld c, b
	ld b, 0
	add hl, bc
	add hl, bc             ; two bytes per pointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, .layerReturn
	push de
	jp hl                  ; execute the layer
.layerReturn
	pop bc
	pop de
.skipLayer
	inc b
	jr .nextLayer
.layersDone
; The personality layer runs at EVERY tier, outside the bitmask, so that
; class-specific AI (Gambler's Paradise) survives at every skill level rather
; than only appearing once its tier happens to include AI_PLAN.
	call AIRunPersonality
.loopFindMinimumEntries ; all entries will be decremented sequentially until one of them is zero
	ld hl, wBuffer  ; temp move selection array
	ld de, wEnemyMonMoves  ; enemy moves
	ld c, NUM_MOVES
.loopDecrementEntries
	ld a, [de]
	inc de
	and a
	jr z, .loopFindMinimumEntries
	dec [hl]
	jr z, .minimumEntriesFound
	inc hl
	dec c
	jr z, .loopFindMinimumEntries
	jr .loopDecrementEntries
.minimumEntriesFound
	ld a, c
.loopUndoPartialIteration ; undo last (partial) loop iteration
	inc [hl]
	dec hl
	inc a
	cp NUM_MOVES + 1
	jr nz, .loopUndoPartialIteration
	ld hl, wBuffer  ; temp move selection array
	ld de, wEnemyMonMoves  ; enemy moves
	ld c, NUM_MOVES
.filterMinimalEntries ; all minimal entries now have value 1. All other slots will be disabled (move set to 0)
	ld a, [de]
	and a
	jr nz, .moveExisting
	ld [hl], a
.moveExisting
	ld a, [hl]
	dec a
	jr z, .slotWithMinimalValue
	xor a
	ld [hli], a     ; disable move slot
	jr .next
.slotWithMinimalValue
	ld a, [de]
	ld [hli], a     ; enable move slot
.next
	inc de
	dec c
	jr nz, .filterMinimalEntries
	ld hl, wBuffer    ; use created temporary array as move set
	predef SingleCPUSpeed ; restore battle's single speed; preserves hl
	ret
.useOriginalMoveSet
	ld hl, wEnemyMonMoves    ; use original move set
	predef SingleCPUSpeed ; restore battle's single speed; preserves hl
	ret

; Scoring layers, indexed by bit position in the tier's layer word. The order
; here IS the execution order (see constants/ai_constants.asm). Entries marked
; "stub" are placeholders for later phases and currently just return.
AIScoringPointers:
	dw AILayerRedundant            ; bit 0  AI_REDUNDANT - stub until Phase 2a
	dw AIMoveChoiceModification1   ; bit 1  AI_BASIC
	dw AIMoveChoiceModification3   ; bit 2  AI_TYPES
	dw AIMoveChoiceModification2   ; bit 3  AI_SETUP
	dw AILayerSmart                ; bit 4  AI_SMART
	dw AILayerDamage               ; bit 5  AI_DAMAGE
	dw AILayerThreat               ; bit 6  AI_THREAT
	dw AILayerPlan                 ; bit 7  AI_PLAN    - stub until Phase 5
	dw AILayerRisky                ; bit 8  AI_RISKY
	assert (@ - AIScoringPointers) / 2 == NUM_AI_LAYERS, 		"AIScoringPointers must have exactly NUM_AI_LAYERS entries"

; Every scoring layer named in AIScoringPointers above is now real. Each lives
; in its own file, INCLUDEd into this section at the bottom of the file so they
; all land in bank $0E, which the dispatcher's same-bank `jp hl` requires:
;   AILayerRedundant  Phase 2a   engine/battle/ai/ai_redundant.asm
;   AILayerSmart      Phase 2b   engine/battle/ai/ai_smart.asm
;   AILayerDamage     Phase 3    engine/battle/ai/ai_damage.asm
;   AILayerThreat     Phase 3    engine/battle/ai/ai_threat.asm
;   AILayerRisky      Phase 3    engine/battle/ai/ai_risky.asm
;   AILayerPlan       Phase 5    engine/battle/ai/ai_plan.asm
; (AILayerPlan is the one layer split across two banks - the bulk of the plan
; system is in bank $2C, engine/battle/ai/ai_plans.asm. See either file's
; header for why that split is possible and where the boundary falls.)

; Trainer-class personality. Runs at every tier, outside the layer bitmask, so
; that class-specific AI survives at every skill level.
;
; Phase 5 did NOT fold this into the plan system, contrary to what this comment
; used to anticipate. AIRunPersonality runs AFTER the whole layer loop and so
; wins any disagreement with a plan by construction, which makes "the Gambler
; also has a plan" a silent conflict rather than a feature. AILayerPlan instead
; returns immediately for a trainer class with a forced personality: the plan
; document's "trainer-class personality forces a plan and skips selection",
; expressed as a skip rather than as a plan-table entry.
AIRunPersonality:
	ld a, [wTrainerClass]
	cp GAMBLER
	jp z, AIMoveChoiceModification5 ; Gambler's Paradise themed AI
	ret

; discourages moves that cause no damage but only a status ailment if player's mon already has one
AIMoveChoiceModification1:
	ld a, [wBattleMonStatus]
	and a
	ret z ; return if no status ailment on player's mon
	ld hl, wBuffer - 1 ; temp move selection array (-1 byte offset)
	ld de, wEnemyMonMoves ; enemy moves
	ld b, NUM_MOVES + 1
.nextMove
	dec b
	ret z ; processed all 4 moves
	inc hl
	ld a, [de]
	and a
	ret z ; no more moves in move set
	inc de
	call ReadMove
	ld a, [wEnemyMovePower]
	and a
	jr nz, .nextMove
	ld a, [wEnemyMoveEffect]
	push hl
	push de
	push bc
	ld hl, StatusAilmentMoveEffects
	ld de, 1
	call IsInArray
	pop bc
	pop de
	pop hl
	jr nc, .nextMove
	; Phase 2b: was `ld a,[hl] / add $5 / ld[hl],a`. AIDiscourage preserves
	; bc/de/hl (only clobbers a), so this drops straight in - hl still points
	; at this move's score byte from the pop above.
	ld a, AI_HEAVY
	call AIDiscourage
	jr .nextMove

StatusAilmentMoveEffects:
	db EFFECT_01 ; unused sleep effect
	db SLEEP_EFFECT
	db POISON_EFFECT
	db PARALYZE_EFFECT
	db -1 ; end

; slightly encourage moves with specific effects.
; in particular, stat-modifying moves and other move effects
; that fall in-between
AIMoveChoiceModification2:
	; Phase 2b: was `cp $1 / ret nz`, which only fires on the SECOND time this
	; enemy mon acts (wAILayer2Encouragement starts at 0 on send-out - see
	; core.asm:1037/6394 - and is incremented after the move executes, so a
	; check for ==1 matches the second action, never the first). Yume and
	; PureRGB both fix this the same way: fire on turn 1 of the send-out.
	ld a, [wAILayer2Encouragement]
	and a
	ret nz
	ld hl, wBuffer - 1 ; temp move selection array (-1 byte offset)
	ld de, wEnemyMonMoves ; enemy moves
	ld b, NUM_MOVES + 1
.nextMove
	dec b
	ret z ; processed all 4 moves
	inc hl
	ld a, [de]
	and a
	ret z ; no more moves in move set
	inc de
	call ReadMove
	ld a, [wEnemyMoveEffect]
	cp ATTACK_UP1_EFFECT
	jr c, .nextMove
	cp BIDE_EFFECT
	jr c, .preferMove
	cp ATTACK_UP2_EFFECT
	jr c, .nextMove
	cp POISON_EFFECT
	jr c, .preferMove
	jr .nextMove
.preferMove
	; Phase 2b: was `dec [hl]`.
	ld a, AI_STRONG
	call AIEncourage
	jr .nextMove

; encourages moves that are effective against the player's mon (even if non-damaging).
; discourage damaging moves that are ineffective or not very effective against the player's mon,
; unless there's no damaging move that deals at least neutral damage
AIMoveChoiceModification3:
	ld hl, wBuffer - 1 ; temp move selection array (-1 byte offset)
	ld de, wEnemyMonMoves ; enemy moves
	ld b, NUM_MOVES + 1
.nextMove
	dec b
	ret z ; processed all 4 moves
	inc hl
	ld a, [de]
	and a
	ret z ; no more moves in move set
	inc de
	call ReadMove
; Phase 3 Step 3: fixed-damage moves ignore type effectiveness completely in
; this engine - Seismic Toss deals the user's level whatever it hits, and it
; ignores immunity too (AI_OVERHAUL_PLAN.md follow-up F1). Scoring them off the
; type chart is therefore not merely redundant but wrong: it was encouraging
; Seismic Toss as "super effective" against a Normal type, where its damage is
; identical to what it does to anything else. AI_DAMAGE ranks these on their
; real simulated damage instead.
	ld a, [wEnemyMoveEffect]
	cp SPECIAL_DAMAGE_EFFECT
	jr z, .nextMove
	cp SUPER_FANG_EFFECT
	jr z, .nextMove
	push hl
	push bc
	push de
	callfar AIGetTypeEffectiveness
	pop de
	pop bc
	pop hl
	ld a, [wTypeEffectiveness]
	cp $10
	jr z, .nextMove
	jr c, .notEffectiveMove
	; Phase 2b: was `dec [hl]`.
	ld a, AI_NUDGE
	call AIEncourage
	jr .nextMove
.notEffectiveMove ; discourages non-effective moves if better moves are available
	push hl
	push de
	push bc
	ld a, [wEnemyMoveType]
	ld d, a
	ld hl, wEnemyMonMoves  ; enemy moves
	ld b, NUM_MOVES + 1
	ld c, $0
.loopMoves
	dec b
	jr z, .done
	ld a, [hli]
	and a
	jr z, .done
	call ReadMove
	ld a, [wEnemyMoveEffect]
	cp SUPER_FANG_EFFECT
	jr z, .betterMoveFound ; Super Fang is considered to be a better move
	cp SPECIAL_DAMAGE_EFFECT
	jr z, .betterMoveFound ; any special damage moves are considered to be better moves
	cp FLY_EFFECT
	jr z, .betterMoveFound ; Fly is considered to be a better move
	ld a, [wEnemyMoveType]
	cp d
	jr z, .loopMoves
	ld a, [wEnemyMovePower]
	and a
	jr nz, .betterMoveFound ; damaging moves of a different type are considered to be better moves
	jr .loopMoves
.betterMoveFound
	ld c, a
.done
	ld a, c
	pop bc
	pop de
	pop hl
	and a
	jr z, .nextMove
	; Phase 2b: was `inc [hl]`.
	ld a, AI_NUDGE
	call AIDiscourage
	jr .nextMove
AIMoveChoiceModification4:
	ret

; Gambler's Paradise AI (GAMBLER trainer class, via move_choices "1, 5").
; Scores the enemy's moves toward the high-risk gambler fantasy. Lower score =
; more preferred; ties are broken randomly by the caller, so unscored moves
; act as the "pick something random" fallback for free.
;
; The signature play is a one-hit KO (Fissure/Horn Drill/Guillotine), but Gen 1
; auto-misses OHKO moves when the user is slower - so this AI only reaches for
; the OHKO when it can actually connect (fast enough, target not immune, target
; not higher level), and otherwise sets up the speed check first (Agility, or a
; paralysis move to quarter the target's speed) before firing next turn. Trap
; moves, sleep, speed-drops and Metronome fill in as secondary gambles.
;
; Shared conditions are precomputed once into c as bit flags:
;   bit 0 = enemy is fast enough for an OHKO to connect (speed >= player)
;   bit 1 = enemy level >= player level (design gate on the OHKO)
;   bit 2 = player has no status (room to inflict paralysis/sleep)
;   bit 3 = enemy's moveset contains an OHKO move (worth setting up for)
AIMoveChoiceModification5:
	ld c, 0
	; bit 0: enemy speed >= player speed (2-byte big-endian: +0 hi, +1 lo)
	ld a, [wEnemyMonSpeed]
	ld b, a
	ld a, [wBattleMonSpeed]
	cp b
	jr z, .speedHiEqual
	jr c, .enemyFastEnough    ; player_hi < enemy_hi
	jr .speedChecked          ; player_hi > enemy_hi
.speedHiEqual
	ld a, [wEnemyMonSpeed + 1]
	ld b, a
	ld a, [wBattleMonSpeed + 1]
	cp b
	jr c, .enemyFastEnough    ; player_lo < enemy_lo
	jr nz, .speedChecked      ; player_lo > enemy_lo
.enemyFastEnough              ; equal speed also counts as "fast enough"
	set 0, c
.speedChecked
	; bit 1: enemy level >= player level
	ld a, [wBattleMonLevel]
	ld b, a
	ld a, [wEnemyMonLevel]
	cp b
	jr c, .levelChecked
	set 1, c
.levelChecked
	; bit 2: player has no status
	ld a, [wBattleMonStatus]
	and a
	jr nz, .statusChecked
	set 2, c
.statusChecked
	; bit 3: enemy knows an OHKO move
	ld hl, wEnemyMonMoves
	ld b, NUM_MOVES
.ohkoScan
	ld a, [hl]
	and a
	jr z, .flagsReady         ; empty slot: no more moves
	call ReadMove             ; preserves hl/de/bc
	ld a, [wEnemyMoveEffect]
	cp OHKO_EFFECT
	jr z, .setOhkoFlag
	inc hl
	dec b
	jr nz, .ohkoScan
	jr .flagsReady
.setOhkoFlag
	set 3, c
.flagsReady
	ld hl, wBuffer - 1        ; score array (-1 offset, matches other mods)
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.nextMove
	dec b
	ret z
	inc hl
	ld a, [de]
	and a
	ret z                     ; no more moves
	inc de
	call ReadMove
	ld a, [wEnemyMoveEffect]
	cp OHKO_EFFECT
	jp z, .ohko
	cp TRAPPING_EFFECT
	jp z, .trap
	cp SLEEP_EFFECT
	jp z, .sleep
	cp SPEED_UP2_EFFECT
	jp z, .agility
	cp PARALYZE_EFFECT
	jp z, .paralyze
	cp PARALYZE_SIDE_EFFECT1
	jp z, .paralyze
	cp PARALYZE_SIDE_EFFECT2
	jp z, .paralyze
	cp SPEED_DOWN1_EFFECT
	jp z, .speedDown
	cp SPEED_DOWN_SIDE_EFFECT
	jp z, .speedDown
	cp METRONOME_EFFECT
	jp z, .metronome
	jp .nextMove              ; neutral
.ohko
	bit 0, c                  ; fast enough?
	jr z, .ohkoAvoid
	bit 1, c                  ; level ok?
	jr z, .ohkoAvoid
	push hl                   ; not type-immune?
	push bc
	push de
	callfar AIGetTypeEffectiveness
	pop de
	pop bc
	pop hl
	ld a, [wTypeEffectiveness]
	and a
	jr z, .ohkoAvoid
	ld a, [hl]                ; viable OHKO - strongly prefer
	sub 6
	ld [hl], a
	jp .nextMove
.ohkoAvoid                    ; would auto-miss or is gated off - avoid
	ld a, [hl]
	add 5
	ld [hl], a
	jp .nextMove
.trap
	ld a, [hl]
	sub 4
	ld [hl], a
	jp .nextMove
.sleep
	bit 2, c                  ; only if player has no status
	jp z, .nextMove
	ld a, [hl]
	sub 3
	ld [hl], a
	jp .nextMove
.agility
	bit 0, c                  ; already fast enough?
	jr nz, .agilityIdle
	bit 3, c                  ; holding an OHKO to set up?
	jr z, .agilityIdle
	ld a, [hl]                ; slower + has OHKO - set up the speed flip
	sub 5
	ld [hl], a
	jp .nextMove
.agilityIdle                  ; otherwise a wasted turn
	ld a, [hl]
	add 2
	ld [hl], a
	jp .nextMove
.paralyze
	bit 0, c                  ; already fast enough - no setup needed
	jp nz, .nextMove
	bit 3, c                  ; no OHKO to set up
	jp z, .nextMove
	bit 2, c                  ; player already statused
	jp z, .nextMove
	ld a, [hl]                ; slower + has OHKO + statusable - quarter their speed
	sub 5
	ld [hl], a
	jp .nextMove
.speedDown
	bit 0, c
	jp nz, .nextMove
	bit 3, c
	jp z, .nextMove
	ld a, [hl]                ; slower + has OHKO - drop their speed instead
	sub 3
	ld [hl], a
	jp .nextMove
.metronome
	ld a, [hl]
	sub 2
	ld [hl], a
	jp .nextMove

ReadMove:
	push hl
	push de
	push bc
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld de, wEnemyMoveNum
	call CopyData
	pop bc
	pop de
	pop hl
	ret

; data/trainers/move_choices.asm is SUPERSEDED by the per-tier layer words in
; engine/battle/ai/ai_core.asm (AITierLayers). It is no longer assembled - the
; table it defined is unreferenced, and dropping it reclaims its bytes in this
; nearly-full bank. The file is kept on disk because Phase 5 may reuse its
; class-by-class breakdown when authoring trainer personalities.

INCLUDE "data/trainers/pic_pointers_money.asm"

INCLUDE "data/trainers/names.asm"

INCLUDE "engine/battle/misc.asm"

INCLUDE "engine/battle/read_trainer_party.asm"

INCLUDE "data/trainers/special_moves.asm"

INCLUDE "data/trainers/parties.asm"

TrainerAI:
	and a
	ldh a, [hIsInBattle]
	dec a
	ret z ; if not a trainer, we're done here
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z ; if in a link battle, we're done as well
; AI Overhaul Phase 6: T2+ trainers only consider items when their active
; mon is the ace (Gen 2's rule - no other living party member). T0/T1 fall
; straight through to .dispatch, unchanged from vanilla item AI. The farcall
; to AIGetTier runs UNCONDITIONALLY (even for T0/T1) purely to resolve and
; cache wAITier - AIIncreaseStat (below) reads it back for its own gate
; without a second farcall. Resolving it has no observable effect on its
; own, so T0/T1 stay byte-identical.
	farcall AIGetTier ; resolve wAITier - its `a` return cannot survive the trip
	ld a, [wAITier]
	and a
	jr z, .dispatch ; unresolved: behave exactly as before
	dec a ; a = resolved tier (0-3)
	cp AI_TIER_SKILLED
	jr c, .dispatch ; T0/T1: vanilla, no ace restriction
	farcall AIActiveMonIsAce ; bank $2C - loops the enemy party
	jr nc, .noItem ; not the ace: no item this turn
.dispatch
	ld a, [wTrainerClass] ; what trainer class is this?
	dec a
	ld c, a
	ld b, 0
	ld hl, TrainerAIPointers
	add hl, bc
	add hl, bc
	add hl, bc
	ld a, [wAICount]
	and a
	ret z ; if no AI uses left, we're done here
	inc hl
	inc a
	jr nz, .getpointer
	dec hl
	ld a, [hli]
	ld [wAICount], a
.getpointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	call Random
	jp hl
.noItem
	and a ; carry clear: no item used, TrainerAI's caller falls through to a
	      ; normal move-based turn
	ret

INCLUDE "data/trainers/ai_pointers.asm"

INCLUDE "engine/battle/ai/ai_accessors.asm"

INCLUDE "engine/battle/ai/ai_score_helpers.asm"

INCLUDE "engine/battle/ai/ai_predicates.asm"

INCLUDE "engine/battle/ai/ai_redundant.asm"

INCLUDE "engine/battle/ai/ai_smart.asm"

INCLUDE "engine/battle/ai/ai_damage.asm"

INCLUDE "engine/battle/ai/ai_threat.asm"

INCLUDE "engine/battle/ai/ai_risky.asm"

INCLUDE "engine/battle/ai/ai_plan.asm"

JugglerAI:
	cp 25 percent + 1
	ret nc
	jp AISwitchIfEnoughMons

BlackbeltAI:
	cp 13 percent - 1
	ret nc
	jp AIUseXAttack

GiovanniAI:
	cp 25 percent + 1
	ret nc
	jp AIUseGuardSpec

CooltrainerMAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXAttack

CooltrainerFAI:
	; AI Overhaul Phase 6: fixed - the intended 25% gate was dead code (the
	; `ret nc` right after the roll was commented out), so Cooltrainer F's
	; Hyper Potion and switch-consideration checks ran on EVERY call
	; regardless of the roll. This is a real balance change: Cooltrainer F is
	; now noticeably less item-happy than she has been up to this point.
	cp 25 percent + 1
	ret nc
	ld a, 10
	call AICheckIfHPBelowFraction
	jp c, AIUseHyperPotion
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AISwitchIfEnoughMons

BrockAI:
; if his active monster has a status condition, use a full heal
	ld a, [wEnemyMonStatus]
	and a
	ret z
	jp AIUseFullHeal

MistyAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXDefend

LtSurgeAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXSpeed

ErikaAI:
	cp 50 percent + 1
	ret nc
	ld a, 10
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseSuperPotion

KogaAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXAttack

BlaineAI:
	cp 25 percent + 1
	ret nc
	; was missing the HP-fraction check every other potion-using AI here has
	; (Erika/Sabrina/Lance/CooltrainerF) - used Super Potion on every 25%
	; roll regardless of HP, even near-full
	ld a, 10
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseSuperPotion

SabrinaAI:
	cp 25 percent + 1
	ret nc
	ld a, 10
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseHyperPotion

Rival2AI:
	cp 13 percent - 1
	ret nc
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUsePotion

Rival3AI:
	cp 13 percent - 1
	ret nc
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseFullRestore

LoreleiAI:
	cp 50 percent + 1
	ret nc
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseSuperPotion

BrunoAI:
	cp 25 percent + 1
	ret nc
	jp AIUseXDefend

AgathaAI:
	cp 8 percent
	jp c, AISwitchIfEnoughMons
	cp 50 percent + 1
	ret nc
	ld a, 4
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseSuperPotion

LanceAI:
	cp 50 percent + 1
	ret nc
	ld a, 5
	call AICheckIfHPBelowFraction
	ret nc
	jp AIUseHyperPotion

GenericAI:
	and a ; clear carry
	ret

; end of individual trainer AI routines

DecrementAICount:
	ld hl, wAICount
	dec [hl]
	scf
	ret

AIPlayRestoringSFX:
	ld a, SFX_HEAL_AILMENT
	jp PlaySoundWaitForCurrent

AIUseFullRestore:
	call AIPlayRestoringSFX
	call AICureStatus
	ld a, FULL_RESTORE
	ld [wAIItem], a
	ld de, wHPBarOldHP
	ld hl, wEnemyMonHP + 1
	ld a, [hld]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
	inc de
	ld hl, wEnemyMonMaxHP + 1
	ld a, [hld]
	ld [de], a
	inc de
	ld [wHPBarMaxHP], a
	ld [wEnemyMonHP + 1], a
	ld a, [hl]
	ld [de], a
	ld [wHPBarMaxHP+1], a
	ld [wEnemyMonHP], a
	jr AIPrintItemUseAndUpdateHPBar

AIUsePotion:
; enemy trainer heals his monster with a potion
	call AIPlayRestoringSFX
	ld a, POTION
	ld b, 20
	jr AIRecoverHP

AIUseSuperPotion:
; enemy trainer heals his monster with a super potion
	call AIPlayRestoringSFX
	ld a, SUPER_POTION
	ld b, 50
	jr AIRecoverHP

AIUseHyperPotion:
; enemy trainer heals his monster with a hyper potion
	call AIPlayRestoringSFX
	ld a, HYPER_POTION
	ld b, 200
	; fallthrough

AIRecoverHP:
; heal b HP and print "trainer used $(a) on pokemon!"
	ld [wAIItem], a
	ld hl, wEnemyMonHP + 1
	ld a, [hl]
	ld [wHPBarOldHP], a
	add b
	ld [hld], a
	ld [wHPBarNewHP], a
	ld a, [hl]
	ld [wHPBarOldHP+1], a
	ld [wHPBarNewHP+1], a
	jr nc, .next
	inc a
	ld [hl], a
	ld [wHPBarNewHP+1], a
.next
	inc hl
	ld a, [hld]
	ld b, a
	ld de, wEnemyMonMaxHP + 1
	ld a, [de]
	dec de
	ld [wHPBarMaxHP], a
	sub b
	ld a, [hli]
	ld b, a
	ld a, [de]
	ld [wHPBarMaxHP+1], a
	sbc b
	jr nc, AIPrintItemUseAndUpdateHPBar
	inc de
	ld a, [de]
	dec de
	ld [hld], a
	ld [wHPBarNewHP], a
	ld a, [de]
	ld [hl], a
	ld [wHPBarNewHP+1], a
	; fallthrough

AIPrintItemUseAndUpdateHPBar:
	call AIPrintItemUse_
	hlcoord 2, 2
	xor a
	ld [wHPBarType], a
	predef UpdateHPBar2
	jp DecrementAICount

AISwitchIfEnoughMons:
; enemy trainer switches if there are 2 or more unfainted mons in party
	ld a, [wEnemyPartyCount]
	ld c, a
	ld hl, wEnemyMon1HP

	ld d, 0 ; keep count of unfainted monsters

	; count how many monsters haven't fainted yet
.loop
	ld a, [hli]
	ld b, a
	ld a, [hld]
	or b
	jr z, .Fainted ; has monster fainted?
	inc d
.Fainted
	push bc
	ld bc, PARTYMON_STRUCT_LENGTH
	add hl, bc
	pop bc
	dec c
	jr nz, .loop

	ld a, d ; how many available monsters are there?
	cp 2    ; don't bother if only 1
	jr c, .noSwitch
; AI Overhaul Phase 4: having a spare mon is now only the PRECONDITION, not the
; decision. The three callers (JugglerAI / BlackbeltAI / AgathaAI) still make
; their own class-specific random roll before reaching here, so hooking the
; decision at this single point upgrades all of them without touching any of
; them. AIShouldSwitch returns carry SET for "switch" and deliberately returns
; carry SET at T0/T1 too, so the low tiers keep exactly today's behaviour.
	farcall AIShouldSwitch
	jp c, SwitchEnemyMon
.noSwitch
	and a
	ret

SwitchEnemyMon:

	; Shin Red import Phase 4 (4.14): if the player is mid-trapping-move (Wrap
	; etc.) when the AI switches out, end it here and mark the player as having
	; already used their turn this round. Without this, wPlayerNumAttacksLeft
	; stays nonzero against a mon that is no longer the trapping target, so the
	; PP-decrement bookkeeping in MoveHitTest/CheckNumAttacksLeft can underflow.
	ld a, [wPlayerBattleStatus1]
	bit USING_TRAPPING_MOVE, a
	jr z, .prepareWithdraw
	ld hl, wPlayerBattleStatus1
	res USING_TRAPPING_MOVE, [hl]
	xor a
	ld [wPlayerNumAttacksLeft], a
	ld a, $ff
	ld [wPlayerSelectedMove], a
.prepareWithdraw

; prepare to withdraw the active monster: copy HP, party pos, and status to roster

	ld a, [wEnemyMonPartyPos]
	ld hl, wEnemyMon1HP
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	ld hl, wEnemyMonHP
	ld bc, MON_STATUS + 1 - MON_HP ; also copies party pos in-between HP and status
	call CopyData

	ld hl, AIBattleWithdrawText
	call PrintText

	; This wFirstMonsNotOutYet variable is abused to prevent the player from
	; switching in a new mon in response to this switch.
	ld a, 1
	ld [wFirstMonsNotOutYet], a
	callfar EnemySendOut
	xor a
	ld [wFirstMonsNotOutYet], a

	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	scf
	ret

AIBattleWithdrawText:
	text_far _AIBattleWithdrawText
	text_end

AIUseFullHeal:
	call AIPlayRestoringSFX
	call AICureStatus
	ld a, FULL_HEAL
	jp AIPrintItemUse

AICureStatus:
; cures the status of enemy's active pokemon
	ld a, [wEnemyMonPartyPos]
	ld hl, wEnemyMon1Status
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	; Shin Red import Phase 5: undo the burn/paralysis stat penalty before
	; wEnemyMonStatus is cleared below, mirroring the item_effects.asm fixes.
	; bc (just consumed by AddNTimes) is dead here.
	push hl
	farcall UndoBurnParStatsForEnemy
	pop hl
	xor a
	ld [hl], a ; clear status in enemy team roster
	ld [wEnemyMonStatus], a ; clear status of active enemy
	ld hl, wEnemyBattleStatus3
	res BADLY_POISONED, [hl]
	ret

AIUseXAccuracy: ; unreferenced
	call AIPlayRestoringSFX
	ld hl, wEnemyBattleStatus2
	set USING_X_ACCURACY, [hl]
	ld a, X_ACCURACY
	jp AIPrintItemUse

AIUseGuardSpec:
	call AIPlayRestoringSFX
	ld hl, wEnemyBattleStatus2
	set PROTECTED_BY_MIST, [hl]
	ld a, GUARD_SPEC
	jp AIPrintItemUse

AIUseDireHit: ; unreferenced
	call AIPlayRestoringSFX
	ld hl, wEnemyBattleStatus2
	set GETTING_PUMPED, [hl]
	ld a, DIRE_HIT
	jp AIPrintItemUse

AICheckIfHPBelowFraction:
; return carry if enemy trainer's current HP is below 1 / a of the maximum
	ldh [hDivisor], a
	ld hl, wEnemyMonMaxHP
	ld a, [hli]
	ldh [hDividend], a
	ld a, [hl]
	ldh [hDividend + 1], a
	ld b, 2
	call Divide
	ldh a, [hQuotient + 3]
	ld c, a
	ldh a, [hQuotient + 2]
	ld b, a
	ld hl, wEnemyMonHP + 1
	ld a, [hld]
	ld e, a
	ld a, [hl]
	ld d, a
	ld a, d
	sub b
	ret nz
	ld a, e
	sub c
	ret

AIUseXAttack:
	ld b, ATTACK_UP1_EFFECT
	ld a, X_ATTACK
	jr AIIncreaseStat

AIUseXDefend:
	ld b, DEFENSE_UP1_EFFECT
	ld a, X_DEFEND
	jr AIIncreaseStat

AIUseXSpeed:
	ld b, SPEED_UP1_EFFECT
	ld a, X_SPEED
	jr AIIncreaseStat

AIUseXSpecial:
	ld b, SPECIAL_UP1_EFFECT
	ld a, X_SPECIAL
	; fallthrough

AIIncreaseStat:
; AI Overhaul Phase 6, two additions layered onto the vanilla body below:
;
; 1. IDEMPOTENCE (every tier - a bugfix, not a strategic upgrade): don't
;    waste the item-use message and wAICount on a stat already at the Gen 1
;    cap ($D/13). StatModifierUpEffect (effects.asm) already refuses the
;    boost at cap and prints "Nothing happened", but only AFTER
;    AIPrintItemUse_ has announced the item and DecrementAICount has spent a
;    use - this check runs first and skips both. b (the +1 effect id -
;    ATTACK_UP1_EFFECT etc, the only kind the four X-items ever pass) maps
;    directly onto wEnemyMonStatMods' byte order (Attack/Defense/Speed/
;    Special), the same mapping StatModifierUpEffect itself uses.
;
; 2. KO-SIMULATOR GATE (T2+ only, via wAITier - already resolved by
;    TrainerAI's own farcall to AIGetTier before dispatch, so no second
;    farcall here): don't set up a stat when the player can KO this turn
;    anyway. AIPlayerWouldKO (ai_threat.asm, same bank $0E, plain call) is
;    exactly the Phase 3 predicate for this. T0/T1 skip straight to the
;    vanilla body once the idempotence check passes.
;
; Layered ON TOP of each class handler's own flat percentage roll rather
; than replacing it: touching six independently hand-tuned handlers
; (BlackbeltAI/CooltrainerMAI/KogaAI/BrunoAI/MistyAI/LtSurgeAI), several with
; their own documented history, is a materially larger and riskier change
; than one shared gate both paths funnel through, for the same practical
; effect - a losing T2+ trainer stops wasting a turn setting up when it is
; about to be OHKO'd anyway.
	push af ; item id, needed at .proceed
	push bc ; effect id (b) + scratch (c), needed throughout
	ld a, b
	sub ATTACK_UP1_EFFECT
	ld c, a
	ld b, 0
	ld hl, wEnemyMonStatMods
	add hl, bc
	ld a, [hl]
	cp $d
	jr z, .maxedOut ; af and bc both still pushed here
	pop bc
	ld a, [wAITier]
	and a
	jr z, .proceed ; unresolved: behave as before
	dec a
	cp AI_TIER_SKILLED
	jr c, .proceed ; T0/T1: vanilla, no KO check
	push bc
	call AIPlayerWouldKO
	pop bc
	jr c, .wouldDie ; af still pushed here, bc already popped
.proceed
	pop af
	ld [wAIItem], a
	push bc
	call AIPrintItemUse_
	pop bc
	ld hl, wEnemyMoveEffect
	ld a, [hld]
	push af
	ld a, [hl]
	push af
	push hl
	ld a, XSTATITEM_DUPLICATE_ANIM
	ld [hli], a
	ld [hl], b
	callfar StatModifierUpEffect
	pop hl
	pop af
	ld [hli], a
	pop af
	ld [hl], a
	jp DecrementAICount
.maxedOut
	pop bc
.wouldDie
	pop af
	and a ; carry clear: no item used
	ret

AIPrintItemUse:
	ld [wAIItem], a
	call AIPrintItemUse_
	jp DecrementAICount

AIPrintItemUse_:
; print "x used [wAIItem] on z!"
	ld a, [wAIItem]
	ld [wNamedObjectIndex], a
	call GetItemName
	ld hl, AIBattleUseItemText
	jp PrintText

AIBattleUseItemText:
	text_far _AIBattleUseItemText
	text_end
