; custom_functions/money_match.asm
;
; Money Match (PROCEDURAL_SUBROOMS_PLAN.md Phase M, 2026-10-13). A Gambler found
; at a wild area's stage-event hideout (STAGE_EVENT_MONEY_MATCH) offers a bet:
; beat him in few turns and he pays double the prize, less for every turn past
; the free ones. He never engages on sight (StageEventLimitTrainerSight), only
; after a YES here, and he leaves once beaten.
;
; Battle side, all keyed on wMoneyMatchState (BIT_MONEY_MATCH_ACTIVE):
;   - BattleTurnCommitted (bridge_effects.asm) counts the player's turns.
;   - GetRandRoster / RogueBattleRound fight him as route step MONEY_MATCH_STEP
;     of the current round, and the five Gambler's Paradise class checks
;     (pool, no-dupes skip, MIX_GAMBLER, the themed AI and the plan skip) treat
;     him as an ordinary trainer.
;   - MoneyMatchApplyPayout below, from WitchApplyMoneyEffects.
;   - EndOfBattle zeroes the byte, so it cannot reach the next battle.
; Like every stage-event trainer, the win does not advance wBattleCount
; (TrainerBattleVictory's procedural-map guard).
;
; Opens its own section, pinned to $3A in layout.link; farcall-only, and its
; text is read in-bank by PrintText while this bank is mapped.

SECTION "Money Match", ROMX

; Farcalled first thing by each stage map's slot-1 stage-NPC text_asm, ahead of
; its TalkToTrainer. Any other event type passes straight through.
; OUTPUT: carry set = no battle (the player declined; the text is shown), the
; caller ends the text script. Carry clear = carry on into TalkToTrainer.
; Clobbers a/bc/de/hl; the callers' text scripts end right after, so bc (the
; text cursor) is dead.
MoneyMatchTalkGate::
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	cp STAGE_EVENT_MONEY_MATCH
	jr nz, .battle
	; Already beaten: no offer and, above all, no state. TalkToTrainer sees
	; his beat flag and only says his after line, so a bit set here would
	; ride into the next, unrelated battle. Reachable wherever a beaten
	; Gambler is shown again (the cemetery re-shows per floor entry).
	ld a, [wStageEvent]
	bit BIT_STAGE_EVENT_MONEY_MATCH_WON, a
	jr nz, .battle
	ld hl, MoneyMatchOfferText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .declined
	ld a, 1 << BIT_MONEY_MATCH_ACTIVE ; active, no turns yet
	ld [wMoneyMatchState], a
.battle
	and a
	ret
.declined
	; He stays put: talking to him again repeats the offer.
	ld hl, MoneyMatchDeclinedText
	call PrintText
	scf
	ret

; Called by WitchApplyMoneyEffects at every trainer victory, after the witch
; no-money zeroing and before PRIZE_MONEY / Oak's grant.
;
; B = wAmountMoneyWon as ReadTrainer computed it, T = turns taken, F = enemy
; party size + MONEY_MATCH_FREE_TURN_BUFFER (one KO a turn, plus one spare).
;   extra = max(0, T - F), k = max(1, 16 - extra)
;   payout = 2B x k/16 = B x k / 8
; i.e. 2B with no extra turns, 1/16 of 2B less per extra turn, floor 2B/16.
; Multiplying before dividing keeps the rounding to one truncation. AddBCD
; saturates at 999999, so a prize over 62499 caps rather than wraps.
;
; Also hides him (sets his toggle flag) so he is gone when the overworld
; returns: a WON trainer battle never reaches EndTrainerBattle's own hide.
; Clobbers a/bc/de/hl.
MoneyMatchApplyPayout::
	ld a, [wMoneyMatchState]
	bit BIT_MONEY_MATCH_ACTIVE, a
	ret z
	and MONEY_MATCH_TURNS_MASK
	ld b, a                         ; b = T
	ld a, [wEnemyPartyCount]
	add MONEY_MATCH_FREE_TURN_BUFFER
	ld c, a                         ; c = F
	ld a, b
	sub c                           ; a = T - F
	jr nc, .haveExtra
	xor a
.haveExtra
	ld c, a
	ld a, MONEY_MATCH_DECAY_STEPS
	sub c                           ; a = 16 - extra
	jr c, .floor
	jr nz, .haveK
.floor
	ld a, 1
.haveK
	ld c, a                         ; c = k, 1..16
	xor a
	ldh [hMoney], a
	ldh [hMoney + 1], a
	ldh [hMoney + 2], a
.multiply
	push bc
	ld de, hMoney + 2
	ld hl, wAmountMoneyWon + 2
	ld c, 3
	predef AddBCDPredef             ; hMoney += B
	pop bc
	dec c
	jr nz, .multiply
	; DivideBCD divides hMoney only (engine/math/bcd.asm). Divisor and quotient
	; are the same three HRAM bytes.
	xor a
	ldh [hDivideBCDDivisor], a
	ldh [hDivideBCDDivisor + 1], a
	ld a, 8                         ; BCD 8 is also decimal 8
	ldh [hDivideBCDDivisor + 2], a
	predef DivideBCDPredef3
	ldh a, [hDivideBCDQuotient]
	ld [wAmountMoneyWon], a
	ldh a, [hDivideBCDQuotient + 1]
	ld [wAmountMoneyWon + 1], a
	ldh a, [hDivideBCDQuotient + 2]
	ld [wAmountMoneyWon + 2], a
	ld hl, wStageEvent
	set BIT_STAGE_EVENT_MONEY_MATCH_WON, [hl]

	; Hide him. hActiveSpriteIndex is still his object index from the talk
	; (EndTrainerBattle reads it the same way after the battle). Setting the
	; flag is enough: CheckSpriteAvailability hides a flagged object on the
	; first overworld frame. HideObject itself would also run UpdateSprites,
	; which has no business running mid-battle.
	ld hl, wToggleableObjectList
	ld de, 2
	ldh a, [hActiveSpriteIndex]
	call IsInArray
	ret nc
	inc hl
	ld c, [hl]
	ld hl, wToggleableObjectFlags
	ld b, FLAG_SET
	predef_jump FlagActionPredef

MoneyMatchOfferText:
	text "Hey, high roller!"
	line "Fancy a MONEY"
	cont "MATCH?"

	para "Beat me fast and"
	line "I pay double the"
	cont "prize money."

	para "Every turn you"
	line "dawdle costs you."
	cont "Wanna play?"
	done

MoneyMatchDeclinedText:
	text "No guts, no"
	line "glory! I'll be"
	cont "right here."
	done
