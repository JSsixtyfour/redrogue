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
; This table IS the difficulty ladder - retuning the ramp means editing these
; nine numbers and nothing else.
AITierByRound:
	db AI_TIER_NOVICE    ; round 0
	db AI_TIER_NOVICE    ; round 1
	db AI_TIER_COMPETENT ; round 2
	db AI_TIER_COMPETENT ; round 3
	db AI_TIER_SKILLED   ; round 4
	db AI_TIER_SKILLED   ; round 5
	db AI_TIER_SKILLED   ; round 6
	db AI_TIER_EXPERT    ; round 7
	db AI_TIER_EXPERT    ; round 8
	assert @ - AITierByRound == AI_MAX_ROUND + 1, \
		"AITierByRound must have one entry per round 0..AI_MAX_ROUND"

; Which layers and flags each tier runs. One 16-bit word per tier; adding a
; layer to a tier is a one-word edit. Layers execute in bit order.
;
; NOTE ON PHASE 1: AI_REDUNDANT, AI_SMART, AI_DAMAGE, AI_THREAT, AI_PLAN and
; AI_RISKY are stubs until their phases land, so today T0 has no active
; scoring at all. That is intentional and temporary - AI_REDUNDANT (Phase 2a)
; is what gives T0 its "does not do useless things" floor. Vanilla already
; shipped classes with no AI layers (YOUNGSTER, CUE_BALL), so this is not a new
; category of behaviour.
AITierLayers:
	dw AI_REDUNDANT | AI_OMNISCIENT                                        ; T0 Novice
	dw AI_REDUNDANT | AI_BASIC | AI_TYPES | AI_SETUP | AI_OMNISCIENT       ; T1 Competent
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
	ld hl, AITierByRound
	ld d, 0
	ld e, a
	add hl, de
	ld b, [hl] ; b = base tier for this round

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
	ld a, b
	cp AI_MAX_TIER + 1
	jr c, .store
	ld a, AI_MAX_TIER
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
; Phase 7 still edits only those four routines to change the information model;
; only their address changed, not their contract.
