; custom_functions/credit_award.asm
;
; Awards credits (wPlayerCoins) for run milestones. Three separate farcall
; entry points, not one parameterized routine: farcall clobbers `a` via
; Bankswitch's first instruction, so a caller cannot pass the amount in `a`.
; Each entry point sets its own amount only after the bankswitch has landed.
;
; The amount rides the stack across the Has9990Coins farcall and the
; AddBCDPredef (both clobber a/bc/hl) rather than living in a WRAM byte -
; WRAM0 has no spare bytes. Note the carry from Has9990Coins must be tested
; BEFORE the matching pop, since `pop af` restores flags and would wipe it.

RogueAwardCredits1::
	ld a, 1
	jr RogueAwardCreditsCommon

RogueAwardCredits2::
	ld a, 2
	jr RogueAwardCreditsCommon

RogueAwardCredits3::
	ld a, 3

RogueAwardCreditsCommon:
	push af                       ; stash the amount across the farcall
	; skip the award entirely if the balance is already near the BCD cap,
	; reusing the same $9990 ceiling check the old coin-gift NPCs used
	; (scripts/GameCorner.asm Has9990Coins) rather than writing new BCD
	; comparison logic
	farcall Has9990Coins
	jr nc, .atCap                 ; carry clear = balance >= 9990, skip
	pop af
	push af                       ; keep a second copy for the run tally
	ld b, a
	xor a
	ldh [hUnusedCoinsByte], a
	ldh [hCoins], a
	ld a, b                       ; amounts are 1-3, so this is already valid BCD
	ldh [hCoins + 1], a
	ld de, wPlayerCoins + 1
	ld hl, hCoins + 1
	ld c, $2
	predef AddBCDPredef

	pop af
	ld hl, wCreditsEarnedThisRun
	add [hl]
	ld [hl], a
	ret

.atCap
	pop af
	ret
