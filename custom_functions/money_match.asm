; custom_functions/money_match.asm
;
; Money Match (PROCEDURAL_SUBROOMS_PLAN.md Phase M, 2026-10-13). A Gambler in
; the forest rest house (Phase 4) offers a bet: beat him in few turns and he
; pays double the prize, less for every turn past the free ones. He is a plain
; object; his text_asm starts the battle after a YES (MoneyMatchHouseTalk). He
; stays after a win and says MoneyMatchAfterText for the rest of that forest.
;
; Battle side, all keyed on wMoneyMatchState (BIT_MONEY_MATCH_ACTIVE):
;   - BattleTurnCommitted (bridge_effects.asm) counts the player's turns.
;   - GetRandRoster / RogueBattleRound fight him as route step MONEY_MATCH_STEP
;     of the current round, and the five Gambler's Paradise class checks
;     (pool, no-dupes skip, MIX_GAMBLER, the themed AI and the plan skip) treat
;     him as an ordinary trainer.
;   - MoneyMatchApplyPayout below, from WitchApplyMoneyEffects.
;   - EndOfBattle zeroes the byte, so it cannot reach the next battle.
; The win does not advance wBattleCount: the house is on TrainerBattleVictory's
; procedural-map list.
;
; Opens its own section, pinned to $3A in layout.link; farcall-only, and its
; text is read in-bank by PrintText while this bank is mapped.

SECTION "Money Match", ROMX

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
; Clobbers a/bc/de/hl.
MoneyMatchApplyPayout::
	ld a, [wMoneyMatchState]
	bit BIT_MONEY_MATCH_ACTIVE, a
	ret z
	bit BIT_MONEY_MATCH_NO_PAYOUT, a
	jr nz, .noBet                   ; a subroom resident: no bet
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
	ret

; A subroom resident's no-bet fight, won. The PokeManiac's prize is one of his
; Pokemon, picked here while his party is intact: once the battle ends the map
; is entered again and its wild data, which shares wEnemyMon1's bytes (the
; union in ram/wram.asm), is reloaded. The pick is copied to wEnemyMon6's slot,
; which nothing writes before his prize text runs (FacManiacPrize).
.noBet
	ld a, [wTrainerClass]
	cp POKEMANIAC
	ret nz
	ld a, [wEnemyPartyCount]
	ld c, a
	call Rangerandom
	cp PARTY_LENGTH - 1
	ret z                           ; already in the last slot
	ld hl, wEnemyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld de, wEnemyMon6
	jp CopyData

; The house gambler's talk, from his text_asm. Already beaten in this forest:
; his after line, no offer. Otherwise the offer and a YES/NO.
; OUTPUT: carry = accepted (wMoneyMatchState armed; the caller starts the
; battle). Clobbers a/bc/de/hl.
MoneyMatchHouseTalk::
	call MoneyMatchHouseWon
	ld hl, MoneyMatchAfterText
	jr nz, .say
	ld hl, MoneyMatchOfferText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, MoneyMatchDeclinedText   ; he stays; talking again repeats the offer
	jr nz, .say
	ld a, 1 << BIT_MONEY_MATCH_ACTIVE ; active, no turns yet
	ld [wMoneyMatchState], a
	; Nothing more to read: close the box as the battle starts. Without this
	; DisplayTextID waits for one more A on the offer (user, BGB 2026-10-14).
	ld a, 1
	ldh [hNoWaitAfterText], a
	scf
	ret
.say
	call PrintText
	and a
	ret

; The house's after-battle script, on a win. Clobbers a/hl.
MoneyMatchHouseRecordWin::
	call MoneyMatchOpenHost
	ld a, [hl]
	or b
	ld [hl], a
	jr MoneyMatchCloseSRAM

; OUTPUT: nz = he was beaten in this stage (each stage's preload clears its
; byte). Clobbers a/b/hl.
MoneyMatchHouseWon:
	call MoneyMatchOpenHost
	ld a, [hl]
	and b
	ld l, a
	call MoneyMatchCloseSRAM
	ld a, l
	and a
	ret

; Opens SRAM bank 0 on the stage's state byte. Out: hl = it, b = his "beaten"
; bit: the forest rest house's sProcForestItemGot, or the cave subroom's
; CAVESUB_STATE (shared with its Super Nerd; FacSuperNerdSettle records it).
MoneyMatchOpenHost:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK(sProcForestItemGot) == 0
	ASSERT BANK(sProcCaveStagingBuffer) == 0
	xor a
	ld [rRAMB], a
	ldh a, [hCurMap]
	cp PROCEDURAL_CAVE_SUBROOM
	jr z, .cave
	cp PROCEDURAL_CAVE_1            ; the resident's fallback
	jr z, .cave
	ld hl, sProcForestItemGot
	ld b, 1 << BIT_PF_MONEY_MATCH_WON
	ret
.cave
	ld hl, CAVESUB_STATE
	ld b, 1 << BIT_CAVESUB_RESIDENT_WON
	ret

MoneyMatchCloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

MoneyMatchOfferText:
	text "Looking for a"
	line "fight?"

	para "The faster you"
	line "beat me the"
	cont "bigger the payday."
	done

MoneyMatchAfterText:
	text "That match was"
	line "worth every penny!"
	done

MoneyMatchDeclinedText:
	text "No guts, no"
	line "glory! I'll be"
	cont "right here."
	done
