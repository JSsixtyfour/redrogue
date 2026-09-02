; Trainer AI core: skill-tier resolution, the per-tier layer table, the
; behaviour-flag query, the saturating score helpers, and the player-state
; accessor seam. See AI_OVERHAUL_PLAN.md.
;
; Lives in its own floating section rather than in "Battle Engine 7" (bank $0E,
; ~243 bytes free) or "Battle Core" (bank $0F, ~50 bytes free). Four banks are
; completely empty, so this has room to grow through the later phases.
;
; CALLING CONVENTION ACROSS THE BANK BOUNDARY:
; Bankswitch (home/bankswitch.asm) clobbers a and bc on the way back out, and
; leaves de and hl as the callee left them. So every routine here that has to
; return something to a caller in another bank returns it in de or hl, never in
; a or bc. Getting this wrong fails silently.

SECTION "Trainer AI Core", ROMX

; Base skill tier by Rogue round. round = wBattleCount / 10.
; These tables ARE the difficulty ladder - retuning the ramp means editing the
; numbers below and nothing else.
; One row per LEVELS difficulty setting (wOptions2 bits 0-2), one byte per
; round. ROW ORDER FOLLOWS THE CONSTANT VALUES, not difficulty order: the enum
; in constants/ram_constants.asm is NORMAL=0, EASY=1, VERY_EASY=2, HARD=3,
; VERY_HARD=4, because NORMAL must stay 0 for InitOptions' `xor a`. Reordering
; these rows to read "easiest first" would silently mis-index.
;
; User's design, 2026-09-01: difficulty changes WHERE the ladder starts and
; where it stops, not merely how fast it climbs.
;   VERY EASY  half T0, half T1
;   EASY       thirds of T0 / T1 / T2
;   NORMAL     unchanged from the original ladder
;   HARD       thirds of T1 / T2 / T3
;   VERY HARD  half T2, half T3
; Verified monotone: read down any round column and the tier never decreases as
; difficulty rises.
;
; Consequence worth knowing before retuning: VERY EASY never reaches T2 and
; EASY never reaches T3, so neither ever meets the plan system, the switching
; engine or threat awareness. That is what "stop" means here, not an oversight.
AITierByRound:
;	round: 0  1  2  3  4  5  6  7  8
	db 0, 0, 1, 1, 2, 2, 2, 3, 3 ; DIFFICULTY_NORMAL
	db 0, 0, 0, 1, 1, 1, 2, 2, 2 ; DIFFICULTY_EASY
	db 0, 0, 0, 0, 0, 1, 1, 1, 1 ; DIFFICULTY_VERY_EASY
	db 1, 1, 1, 2, 2, 2, 3, 3, 3 ; DIFFICULTY_HARD
	db 2, 2, 2, 2, 2, 3, 3, 3, 3 ; DIFFICULTY_VERY_HARD
	assert @ - AITierByRound == (AI_MAX_ROUND + 1) * NUM_AI_DIFFICULTY_ROWS, \
		"AITierByRound must have one row per difficulty and one entry per round"

; Highest tier each difficulty may reach, applied AFTER the boss bumps. Without
; this a gym leader's +1 would walk VERY EASY into T2 and EASY into T3, undoing
; the "stop" the rows above exist to express. It also subsumes the AI_MAX_TIER
; clamp, since no entry exceeds it.
;
; TUNING KNOB: raise a row here if bosses should stay a real spike even on the
; easy settings. One byte per difficulty.
AITierCeiling:
	db AI_TIER_EXPERT    ; DIFFICULTY_NORMAL
	db AI_TIER_SKILLED   ; DIFFICULTY_EASY
	db AI_TIER_COMPETENT ; DIFFICULTY_VERY_EASY
	db AI_TIER_EXPERT    ; DIFFICULTY_HARD
	db AI_TIER_EXPERT    ; DIFFICULTY_VERY_HARD
	assert @ - AITierCeiling == NUM_AI_DIFFICULTY_ROWS, \
		"AITierCeiling must have one entry per difficulty"

; Which layers and flags each tier runs. One 16-bit word per tier; adding a
; layer to a tier is a one-word edit. Layers execute in bit order.
;
; NOTE ON PHASE 1: AI_REDUNDANT, AI_SMART, AI_DAMAGE, AI_THREAT, AI_PLAN and
; AI_RISKY are stubs until their phases land, so today T0 has no active
; scoring at all. That is intentional and temporary - AI_REDUNDANT (Phase 2a)
; is what gives T0 its "does not do useless things" floor. Vanilla already
; shipped classes with no AI layers (YOUNGSTER, CUE_BALL), so this is not a new
; category of behaviour.
;
; PHASE 7 (2026-08-26): AI_OMNISCIENT is now CLEARED on T0/T1. Those tiers
; reason about the player's MOVESET only from what AITrackSeenPlayerMove has
; actually recorded this battle (ai_fairplay.asm) - see AIGetPlayerMoveN in
; ai_accessors.asm, the one routine this flip changes. Type/status/HP/stat
; stages stay live at every tier (the user's 2026-08-25 decision: a human
; opponent can see all of those on screen too). T2/T3 keep the bit set and
; stay fully omniscient, including about the moveset, forever.
AITierLayers:
	dw AI_REDUNDANT                                                        ; T0 Novice
	dw AI_REDUNDANT | AI_BASIC | AI_TYPES | AI_SETUP                       ; T1 Competent
	dw AI_REDUNDANT | AI_BASIC | AI_TYPES | AI_SETUP | AI_SMART \
	   | AI_DAMAGE | AI_OMNISCIENT                                         ; T2 Skilled
	dw AI_REDUNDANT | AI_BASIC | AI_TYPES | AI_SETUP | AI_SMART \
	   | AI_DAMAGE | AI_THREAT | AI_PLAN | AI_RISKY | AI_OMNISCIENT        ; T3 Expert
	assert (@ - AITierLayers) / 2 == NUM_AI_TIERS, \
		"AITierLayers must have one word per tier"

; Resolve this battle's skill tier and cache it.
; OUTPUT: a = tier (0..AI_MAX_TIER). Also stores tier+1 in wAITier.
; Safe to call at any point in a battle: it depends only on state that is
; already settled by the time the AI first runs.
AIResolveTier::
; A debug override wins outright, so the harness can pin a tier by writing one
; byte. Stored as tier+1 so that 0 means "no override".
	ld a, [wAIDebugTierOverride]
	and a
	jr z, .noOverride
	dec a
	cp AI_MAX_TIER + 1
	jr c, .store
	ld a, AI_MAX_TIER
	jr .store
.noOverride
; round = min(wBattleCount / 10, AI_MAX_ROUND), by repeated subtraction.
	ld a, [wBattleCount]
	ld b, 0
.divideByTen
	cp 10
	jr c, .gotRound
	sub 10
	inc b
	jr .divideByTen
.gotRound
	ld a, b
	cp AI_MAX_ROUND + 1
	jr c, .roundInRange
	ld a, AI_MAX_ROUND
.roundInRange
	ld d, 0
	ld e, a
	ld hl, AITierByRound
	add hl, de ; hl = NORMAL's row, offset by the round

; Advance to this playthrough's difficulty row. c keeps the difficulty index
; alive for the ceiling lookup after the boss bumps; the bumps below touch only
; a and b, so it survives them.
	ld a, [wOptions2]
	and DIFFICULTY_MASK
	cp NUM_AI_DIFFICULTY_ROWS
	jr c, .difficultyInRange
	xor a ; a value outside the enum can only come from a corrupt option byte;
	      ; fall back to NORMAL rather than indexing off the end of the table
.difficultyInRange
	ld c, a
	ld de, AI_MAX_ROUND + 1
.rowLoop
	and a
	jr z, .gotRow
	add hl, de
	dec a
	jr .rowLoop
.gotRow
	ld b, [hl] ; b = base tier for this round at this difficulty

; Boss bumps. Each is worth one tier, and the clamp below catches the overlap.
; The Elite Four and Champion deliberately need no test here: they only occur
; at wBattleCount 86+, which is round 8, which is already AI_MAX_TIER.
	ld a, [wGymLeaderNo]
	and a
	jr z, .notGymLeader
	inc b
.notGymLeader
	ld a, [wTrainerClass]
	cp RIVAL_MINIBOSS
	jr z, .miniBoss
	cp GIOVANNI_MINIBOSS
	jr nz, .notMiniBoss
.miniBoss
	inc b
.notMiniBoss
; Final trainer of a tier already gets a level and class bonus; give it a skill
; bump too. This is a tuning knob - drop these five lines to disable it.
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_FINAL_TRAINER, a
	jr z, .notFinalTrainer
	inc b
.notFinalTrainer
; Clamp to this difficulty's ceiling. Deliberately AFTER the bumps - see
; AITierCeiling. No separate AI_MAX_TIER clamp is needed: no ceiling entry
; exceeds it.
	ld hl, AITierCeiling
	ld d, 0
	ld e, c
	add hl, de
	ld a, [hl]
	cp b
	jr c, .store ; ceiling < computed tier: keep the ceiling
	ld a, b
.store
	push af
	inc a
	ld [wAITier], a ; cached as tier+1; 0 means unresolved
	pop af
	ret

; Get this battle's skill tier, resolving it on first use.
; OUTPUT: a = tier (0..AI_MAX_TIER).
; Lazy rather than resolved during battle init on purpose: wMiscBattleData is
; bulk-zeroed partway through InitBattleVariables, so anything written there
; earlier would be wiped. Zero-means-unresolved makes that a feature.
AIGetTier::
	ld a, [wAITier]
	and a
	jp z, AIResolveTier
	dec a
	ret

; Get the layer/flag word for this battle's tier.
; OUTPUT: de = the 16-bit layer word.
; Returns in de because a and bc do not survive Bankswitch - see the header.
AIGetLayerWord::
	call AIGetTier
	add a ; two bytes per entry
	ld hl, AITierLayers
	ld d, 0
	ld e, a
	add hl, de
	ld a, [hli]
	ld d, [hl]
	ld e, a
	ret

; Test a behaviour flag (AI_OMNISCIENT and friends) for this battle's tier.
; INPUT:  de = flag mask to test
; OUTPUT: z clear if any tested bit is set, z set if none are.
AIHasFlag::
	push de
	call AIGetLayerWord
	ld a, d
	ld h, a
	ld a, e
	ld l, a
	pop de
	ld a, h
	and d
	jr nz, .set
	ld a, l
	and e
.set
	ret

; --- Player-state accessor seam: MOVED (Phase 3 Step 2) --------------------
; AIGetTargetType1 / AIGetTargetType2 / AIGetTargetStatus / AIGetPlayerMoveN now
; live in engine/battle/ai/ai_accessors.asm, INCLUDEd into bank $0E beside the
; scoring layers. They had to move: they are called from the per-move scoring
; loop with plain same-bank calls, and AIGetPlayerMoveN's argument arrives in
; `a`, which cannot survive a farcall. Leaving them here produced a real
; cross-bank `call` bug - see that file's header for the full account.
;
; Phase 7 (2026-08-26) edited only AIGetPlayerMoveN of those four, to change
; the information model - see that file's header for the full account.
