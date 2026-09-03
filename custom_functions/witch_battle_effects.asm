; custom_functions/witch_battle_effects.asm
;
; Witch-challenge battle effects that were relocated out of
; engine/battle/core.asm to reclaim space in the "Battle Core" ROM bank
; (bank $0F), which was 100% full (1 free byte) and blocking further battle
; hooks - see KEY_ITEM_EFFECTS_PLAN_PC.md §3i and project_rom0_home_pressure.
;
; HandleRecoilChallenge was the ideal relocation candidate: 127 bytes with
; ZERO same-bank dependencies (its only outbound calls are `predef
; UpdateHPBar2`, which does its own banking, and PrintText, which is HOME),
; and only two call sites, both of which consume nothing but the returned Z
; flag - and Bankswitch preserves flags across a farcall. Net reclaim after
; converting those two `call`s to `farcall`: ~117 bytes.
;
; Its sibling HandleTurnLimitDrain stayed behind in that round, because it
; calls UpdateCurMonHPBar, a non-exported core.asm local. It followed on
; 2026-09-02 when the bank ran short again; rather than export that local, the
; ~14 bytes of it that matter are inlined at the bottom of this file.

; ============================================================
; HandlePostPlayerMoveWitchEffects   (was HandleRecoilChallenge)
;
; farcalled from BOTH full-turn paths in MainInBattleLoop, immediately after
; ExecutePlayerMove. This is the shared seam for every witch challenge whose
; effect is "do something to the player's own mon right after its move
; resolves":
;
;   CHALLENGE_RECOIL_ATTACKS    (12) - wDamage/4 recoil on any damaging move
;   CHALLENGE_SAME_MOVE_PENALTY (14) - maxHP/8 for repeating last turn's move
;   CHALLENGE_RECOIL_PHYSICAL   (16) - wDamage/4 recoil, physical moves only
;   CHALLENGE_RECOIL_SPECIAL    (17) - wDamage/4 recoil, special moves only
;
; Dispatching from here means new challenges of this shape cost ZERO bytes in
; the Battle Core bank: the two call sites stay unchanged farcalls that consume
; only the returned Z flag, and Bankswitch preserves flags.
;
; hWhoseTurn is reliably 0 here - ExecutePlayerMove sets it on entry and nothing
; between there and this hook restores it - which is what makes <USER> the
; correct name in the messages below.
;
; OUTPUT: Z set if the player's mon hit 0 HP; Z clear otherwise (including the
; "no challenge active / nothing happened" paths), matching what both call
; sites already expect so KO Defiance still runs.
; ============================================================
HandlePostPlayerMoveWitchEffects::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .noEffect
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	jr z, .noEffect
	ld a, [wWitchChallenge]
	cp CHALLENGE_SAME_MOVE_PENALTY
	jr z, .sameMovePenalty
	cp CHALLENGE_RECOIL_ATTACKS
	jr z, .recoilAnyMove
	cp CHALLENGE_RECOIL_PHYSICAL
	jr z, .recoilPhysicalOnly
	cp CHALLENGE_RECOIL_SPECIAL
	jr z, .recoilSpecialOnly

.noEffect
	or a               ; ensure Z clear - "nothing happened, mon is alive"
	inc a
	ret

; --- Challenges 16/17: same recoil as 12, gated on the move's damage class.
; Gen 1 has no per-move category: types below SPECIAL ($14) are physical,
; types from SPECIAL up are special. The UNUSED_TYPES gap ($09-$13) never
; appears on a real move, so the single compare is sufficient.
.recoilPhysicalOnly
	ld a, [wPlayerMoveType]
	cp SPECIAL
	jr nc, .noEffect       ; special move under the physical-only challenge
	jr .recoilAnyMove
.recoilSpecialOnly
	ld a, [wPlayerMoveType]
	cp SPECIAL
	jr c, .noEffect        ; physical move under the special-only challenge

; --- Challenge 12 (and the tail of 16/17): wDamage/4, minimum 1.
.recoilAnyMove
	ld a, [wDamage]
	ld b, a
	ld a, [wDamage + 1]
	ld c, a
	or b
	jr z, .noEffect        ; no damage dealt (miss, status move, immunity)
	srl b
	rr c
	srl b
	rr c                   ; bc = wDamage / 4, same as non-Struggle RecoilEffect_
	ld a, b
	or c
	jr nz, .recoilApply
	inc c                  ; minimum 1
.recoilApply
	ld de, RecoilChallengeText
	jr ApplyWitchSelfDamage

; --- Challenge 14: punish using the same move twice in a row.
; Both trackers are recorded UNCONDITIONALLY before the comparison, so the
; streak state is correct on every path out of here. A repeat requires all
; three of: a real move was used, it matches last turn's, and the same party
; slot used it. wPlayerUsedMove is 0 whenever the mon could not act (asleep,
; frozen, fully paralysed), so a lost turn breaks the streak for free; the slot
; check stops a freshly switched-in mon from inheriting the outgoing mon's move.
.sameMovePenalty
	ld a, [wWitchPrevPlayerMove]
	ld d, a                ; d = previous move
	ld a, [wWitchPrevPlayerSlot]
	ld e, a                ; e = previous slot
	ld a, [wPlayerUsedMove]
	ld b, a
	ld [wWitchPrevPlayerMove], a
	ld a, [wPlayerMonNumber]
	ld c, a
	ld [wWitchPrevPlayerSlot], a
	ld a, b
	and a
	jr z, .noEffect        ; could not act this turn
	cp d
	jr nz, .noEffect       ; different move
	ld a, c
	cp e
	jr nz, .noEffect       ; different mon
	; Repeat confirmed: maxHP/8, minimum 1. wBattleMonMaxHP is big-endian.
	ld a, [wBattleMonMaxHP]
	ld b, a
	ld a, [wBattleMonMaxHP + 1]
	ld c, a
	srl b
	rr c
	srl b
	rr c
	srl b
	rr c                   ; bc = maxHP / 8
	ld a, b
	or c
	jr nz, .sameMoveApply
	inc c                  ; minimum 1
.sameMoveApply
	ld de, SameMovePenaltyText
	; fall through

; ------------------------------------------------------------
; ApplyWitchSelfDamage   (local; every challenge above funnels through here)
; Subtracts bc HP from the player's active mon, redraws its HP bar, prints the
; message at de, and returns Z set if the mon hit 0 HP so KO Defiance can run.
; Caller guarantees bc >= 1. The HP write order and the overkill clamp are
; lifted verbatim from the original HandleRecoilChallenge, which took them from
; RecoilEffect_.
; ------------------------------------------------------------
ApplyWitchSelfDamage:
	push de                ; text pointer; PrintText wants it in hl, later
	ld hl, wBattleMonMaxHP
	ld a, [hli]
	ld [wHPBarMaxHP + 1], a
	ld a, [hl]
	ld [wHPBarMaxHP], a
	push bc
	ld bc, wBattleMonHP - wBattleMonMaxHP
	add hl, bc
	pop bc                 ; hl = wBattleMonHP + 1 (the LOW byte)
	ld a, [hl]
	ld [wHPBarOldHP], a
	sub c
	ld [hld], a
	ld [wHPBarNewHP], a
	ld a, [hl]
	ld [wHPBarOldHP + 1], a
	sbc b
	ld [hl], a
	ld [wHPBarNewHP + 1], a
	jr nc, .updateBar
	xor a                  ; underflowed - clamp to 0 rather than wrap
	ld [hli], a
	ld [hl], a
	ld hl, wHPBarNewHP
	ld [hli], a
	ld [hl], a
.updateBar
	hlcoord 10, 9
	ld a, 1
	ld [wHPBarType], a
	predef UpdateHPBar2
	pop de
	ld h, d
	ld l, e
	call PrintText
	; Return Z set if HP = 0
	ld a, [wBattleMonHP]
	ld b, a
	ld a, [wBattleMonHP + 1]
	or b
	ret

RecoilChallengeText:
	text_far _RecoilChallengeText
	text_end

SameMovePenaltyText:
	text_far _SameMovePenaltyText
	text_end

; ============================================================
; HandleTurnLimitDrain
; Called at end of each full battle turn when CHALLENGE_TURN_LIMIT is active.
; Increments wBattleTurnCount. When count >= wBattleTurnLimit, drains
; maxHP/16 (min 1) from the player's active mon. KO Defiance applies normally.
; OUTPUT: Z set if drain fired AND mon HP hit 0; Z clear otherwise.
;
; Relocated out of engine/battle/core.asm 2026-09-02, for the same reason its
; sibling above was moved in 2026-08-07: "Battle Core" (bank $0F) was down to
; 17 free bytes in the debug build and was blocking new witch hooks. This
; file's header note above lists this routine as the one that deliberately
; STAYED, because it calls UpdateCurMonHPBar, a non-exported core.asm local.
; That call is inlined below rather than exporting it, which is what made the
; move possible. Net reclaim after converting its two call sites to farcall:
; ~105 bytes.
; ============================================================
HandleTurnLimitDrain::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jp z, .noEffect
	ld a, [wWitchChallenge]
	cp CHALLENGE_TURN_LIMIT
	jp nz, .noEffect
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	jp z, .noEffect
	; Increment turn count
	ld hl, wBattleTurnCount
	inc [hl]
	ld a, [wBattleTurnLimit]
	ld b, a
	ld a, [wBattleTurnCount]
	cp b
	jp c, .noEffect       ; count < limit: no drain yet
	; Drain: maxHP/16, minimum 1 — same pattern as HandlePoisonBurnLeechSeed
	ld hl, TurnLimitDrainText
	call PrintText
	ld hl, wBattleMonHP
	push hl
	ld bc, wBattleMonMaxHP - wBattleMonHP
	add hl, bc
	ld a, [hli]
	ld [wHPBarMaxHP + 1], a
	ld b, a
	ld a, [hl]
	ld [wHPBarMaxHP], a
	ld c, a
	srl b
	rr c
	srl b
	rr c
	srl c
	srl c                 ; c = maxHP/16
	ld a, c
	and a
	jr nz, .nonZeroDamage
	inc c                 ; minimum 1
.nonZeroDamage
	pop hl                ; hl = wBattleMonHP
	inc hl                ; hl = wBattleMonHP low byte
	ld a, [hl]
	ld [wHPBarOldHP], a
	sub c
	ld [hld], a
	ld [wHPBarNewHP], a
	ld a, [hl]
	ld [wHPBarOldHP + 1], a
	sbc b
	ld [hl], a
	ld [wHPBarNewHP + 1], a
	jr nc, .noOverkill
	xor a
	ld [hli], a
	ld [hl], a
	ld [wHPBarNewHP], a
	ld [wHPBarNewHP + 1], a
.noOverkill
; Inlined copy of engine/battle/core.asm's UpdateCurMonHPBar. That routine is a
; core.asm local, so reaching it from this bank would mean exporting it and
; adding a farcall back - more churn than the 14 bytes it costs to inline it.
; The hWhoseTurn branch is kept VERBATIM rather than hardcoding the player bar
; (which is what HandleRecoilChallenge above does), so this relocation changes
; nothing about which bar is drawn. Whether that branch is CORRECT here is a
; separate, pre-existing question: on the player-moves-first path hWhoseTurn is
; still 1 when this runs, so the enemy's bar gets drawn from the player's HP
; values. Deliberately left exactly as it was - not this change's business.
; The original's push bc / pop bc around the predef is dropped: bc held the
; drain amount, which is dead from here on.
	hlcoord 10, 9         ; tile pointer to player HP bar
	ldh a, [hWhoseTurn]
	and a
	ld a, $1
	jr z, .gotHPBarCoords
	hlcoord 2, 2          ; tile pointer to enemy HP bar
	xor a
.gotHPBarCoords
	ld [wHPBarType], a
	predef UpdateHPBar2
; Faint check. The original read `ld a, [wBattleMonHP]` / `or [hl]`, with a
; comment asserting hl was wBattleMonHP + 1 "after UpdateCurMonHPBar". It was
; not: UpdateCurMonHPBar overwrites hl with an hlcoord before its predef and
; never restores it, so that `or` folded in a TILEMAP byte instead of the HP
; low byte. Tile IDs are almost never 0, so the routine almost always returned
; NZ and its callers almost never saw the faint. Read both HP bytes explicitly,
; exactly as HandleRecoilChallenge above already does.
	ld a, [wBattleMonHP]
	ld b, a
	ld a, [wBattleMonHP + 1]
	or b
	ret                   ; Z set if HP = 0

.noEffect
	or a                  ; ensure Z clear (a=0 from cp, but set NZ explicitly)
	inc a                 ; a=1, Z clear
	ret

TurnLimitDrainText:
	text_far _TurnLimitDrainText
	text_end

; ============================================================
; WitchInitTurnLimit
; Called from StartBattle (engine/battle/core.asm). If CHALLENGE_TURN_LIMIT is
; active, resets the per-battle turn counter and computes this battle's limit
; as 6 + round, where round = min(wBattleCount / 10, 8).
;
; Relocated out of core.asm 2026-09-02 for bank $0F pressure. No inputs and no
; outputs, and StartBattle has nothing live in a/bc/hl across this point - it
; reloads hl, bc and d immediately afterwards - so the farcall's clobbers cost
; nothing. The three in-line gates that used to jump to .noTurnLimitInit
; become plain `ret`s here, which is where a few of the reclaimed bytes come
; from.
; ============================================================
WitchInitTurnLimit::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_TURN_LIMIT
	ret nz
	xor a
	ld [wBattleTurnCount], a
	ld a, [wBattleCount]
	ld b, 0
.getRound
	cp 10
	jr c, .gotRound
	sub 10
	inc b
	jr .getRound
.gotRound
	ld a, b
	cp 9
	jr c, .roundOk
	ld a, 8          ; cap round at 8
.roundOk
	add 6            ; limit = 6 + round
	ld [wBattleTurnLimit], a
	ret

; ============================================================
; WitchApplyMoneyEffects
; Called from TrainerBattleVictory (engine/battle/core.asm) just before the
; "money for winning" text. The "no money" challenge zeroes the win before it
; is shown or added.
;
; PRIZE_MONEY is PERMANENT (2026-09-02): unlike the challenge, it does NOT
; gate on BIT_WITCH_ACCEPTED - once earned it applies to every win for the
; rest of the run, whether or not a challenge is currently active. Also
; rebalanced from a flat 2x (AddBCDPredef with source == dest) to +10%, to
; match its new permanence.
;
; Relocated out of core.asm 2026-09-02 for bank $0F pressure. Nothing is live
; in a/bc/hl at the call site (c died with the DelayFrames above it, and hl is
; reloaded with MoneyForWinningText immediately after), so the farcall's
; clobbers are free.
; ============================================================
WitchApplyMoneyEffects::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .checkMoneyPrize
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_MONEY
	jr nz, .checkMoneyPrize
	xor a
	ld hl, wAmountMoneyWon
	ld [hli], a
	ld [hli], a
	ld [hl], a
.checkMoneyPrize
	ld a, [wWitchPrizesEarned]
	and 1 << (PRIZE_MONEY - 1)
	ret z
	; wAmountMoneyWon += wAmountMoneyWon / 10. DivideBCD only ever divides
	; hMoney (engine/math/bcd.asm), so copy the 3-byte BCD value in first.
	ld a, [wAmountMoneyWon]
	ldh [hMoney], a
	ld a, [wAmountMoneyWon + 1]
	ldh [hMoney + 1], a
	ld a, [wAmountMoneyWon + 2]
	ldh [hMoney + 2], a
	xor a
	ldh [hDivideBCDDivisor], a
	ldh [hDivideBCDDivisor + 1], a
	ld a, $10             ; BCD ten - NOT decimal 16
	ldh [hDivideBCDDivisor + 2], a
	predef DivideBCDPredef3
	ld de, wAmountMoneyWon + 2
	ld hl, hDivideBCDQuotient + 2
	ld c, $3
	predef AddBCDPredef ; wAmountMoneyWon += wAmountMoneyWon / 10
	ret

; ============================================================
; RogueWitchBlockHealing
; CHALLENGE_NO_HEALING: refuses medicine items (potions, revives, status
; healers - anything that dispatches through ItemUseMedicine) OUTSIDE battle
; only. In-battle items, healing moves, and the lobby nurse are deliberately
; untouched - this challenge targets overworld self-sufficiency, not healing
; itself.
; OUTPUT: carry set = refuse this item use; carry clear = allow it.
; CLOBBERS: a
; ============================================================
RogueWitchBlockHealing::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .allow
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_HEALING
	jr nz, .allow
	ldh a, [hIsInBattle]
	and a
	jr nz, .allow          ; in battle - allowed
	scf
	ret
.allow
	and a                  ; clear carry
	ret

; ============================================================
; RogueWitchDiscountBuyPrice
; Witch prize j (PRIZE_CHEAP_ITEMS): 10% off at the money marts. Called from
; engine/events/pokemart.asm's buy path right after DisplayChooseQuantityMenu,
; which by then has left the final computed total in hMoney - so this scales
; the SAME total the quoted price, the affordability check, and the payment
; all read next, and it composes multiplicatively on top of whatever produced
; that total.
; PERMANENT (earned once, applies for the rest of the run) - tests
; wWitchPrizesEarned directly, not wWitchPrize/BIT_WITCH_ACCEPTED.
; Scope: gated on the prize, not the shop, so it applies at any money mart
; open while the prize is owned - in practice the two lobby clerks. The
; Credit Exchange (own currency/cost logic) and the dorm vendor are untouched.
; CLOBBERS: a, bc, de, hl
; ============================================================
RogueWitchDiscountBuyPrice::
	ld a, [wWitchPrizesEarned + 1]  ; prize 10 is bit 1 of the HIGH byte
	and 1 << (PRIZE_CHEAP_ITEMS - 9)
	ret z
	; hMoney / 10 -> hDivideBCDQuotient (DivideBCD divides hMoney by the
	; divisor and aliases the quotient over hDivideBCDDivisor - see
	; engine/math/bcd.asm). This is BCD math (unlike the plain-binary EXP
	; divide above), so the divisor is BCD ten: $10, not decimal 10/$0A.
	xor a
	ldh [hDivideBCDDivisor], a
	ldh [hDivideBCDDivisor + 1], a
	ld a, $10               ; BCD ten - NOT decimal 16
	ldh [hDivideBCDDivisor + 2], a
	predef DivideBCDPredef3
	; hMoney -= hMoney / 10
	ld de, hMoney + 2
	ld hl, hDivideBCDQuotient + 2
	ld c, 3
	predef SubBCDPredef
	ret
