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
; Its sibling HandleTurnLimitDrain deliberately stayed in core.asm: it calls
; UpdateCurMonHPBar, a non-exported core.asm local, so moving it would have
; required exporting that and adding a farcall back - more churn for no
; additional need once this one routine covered the shortfall.

; ============================================================
; HandleRecoilChallenge
; Called after ExecutePlayerMove when CHALLENGE_RECOIL_ATTACKS is active.
; Applies wDamage/4 recoil to the player's active mon (same as non-Struggle
; recoil moves). Skips if no damage was dealt (miss, status move, etc.).
; KO Defiance applies normally if recoil drops HP to 0.
; OUTPUT: Z set if mon HP hit 0; Z clear otherwise.
; ============================================================
HandleRecoilChallenge::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .noRecoil
	ld a, [wWitchChallenge]
	cp CHALLENGE_RECOIL_ATTACKS
	jr nz, .noRecoil
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	jr z, .noRecoil
	; Only apply if damage was dealt
	ld a, [wDamage]
	ld b, a
	ld a, [wDamage + 1]
	ld c, a
	ld a, b
	or c
	jr z, .noRecoil
	; Recoil = wDamage / 4 (same as non-Struggle RecoilEffect_)
	srl b
	rr c
	srl b
	rr c
	ld a, b
	or c
	jr nz, .applyRecoil
	inc c              ; minimum 1
.applyRecoil
	; Apply to player's active mon — same pattern as RecoilEffect_
	ld hl, wBattleMonMaxHP
	ld a, [hli]
	ld [wHPBarMaxHP + 1], a
	ld a, [hl]
	ld [wHPBarMaxHP], a
	push bc
	ld bc, wBattleMonHP - wBattleMonMaxHP
	add hl, bc
	pop bc
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
	jr nc, .recoilUpdateBar
	xor a
	ld [hli], a
	ld [hl], a
	ld hl, wHPBarNewHP
	ld [hli], a
	ld [hl], a
.recoilUpdateBar
	hlcoord 10, 9
	ld a, 1
	ld [wHPBarType], a
	predef UpdateHPBar2
	ld hl, RecoilChallengeText
	call PrintText
	; Return Z set if HP = 0
	ld a, [wBattleMonHP]
	ld b, a
	ld a, [wBattleMonHP + 1]
	or b
	ret

.noRecoil
	or a   ; ensure Z clear
	inc a
	ret

RecoilChallengeText:
	text_far _RecoilChallengeText
	text_end
