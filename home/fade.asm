; These routines manage gradual fading
; (e.g., entering a doorway)
; Z = ordinary animation, NZ = Sensitivity. Only a and flags are clobbered.
CheckSensitivity::
	ld a, [wOptions3]
	bit BIT_REDUCED_ANIM, a
	ret

EnableSensitivity::
	ld hl, wOptions3
	set BIT_REDUCED_ANIM, [hl]
	ld hl, wOptions
	set BIT_BATTLE_ANIMATION, [hl]
	ret

; Recovery loads saved WRAM before MainMenu's ordinary options loader.
; Preserve both its carry/NZ result and the choice made before the intro.
SensitivityLossRecoveryBoot::
	ld a, [wOptions3]
	push af
	rfarcall LossRecoveryBoot
	push af
	pop bc
	pop af
	push bc
	and 1 << BIT_REDUCED_ANIM
	call nz, EnableSensitivity
	pop af
	ret

SensitivityBattleTransition::
	call GBFadeOutToBlack
	xor a
	ldh [hAutoBGTransferEnabled], a
	ret

LoadGBPal::
	rfarjp LoadGBPal_

GBFadeInFromBlack::
	rfarjp GBFadeInFromBlack_

GBFadeOutToWhite::
	rfarjp GBFadeOutToWhite_

GBFadeOutToBlack::
	rfarjp GBFadeOutToBlack_

GBFadeInFromWhite::
	rfarjp GBFadeInFromWhite_

FadePal1:: dc 3,3,3,3, 3,3,3,3, 3,3,3,3
FadePal2:: dc 3,3,3,2, 3,3,3,2, 3,3,2,0
FadePal3:: dc 3,3,2,1, 3,2,1,0, 3,2,1,0
FadePal4:: dc 3,2,1,0, 3,1,0,0, 3,2,0,0
;              rBGP     rOBP0    rOBP1
FadePal5:: dc 3,2,1,0, 3,1,0,0, 3,2,0,0
FadePal6:: dc 2,1,0,0, 2,0,0,0, 2,1,0,0
FadePal7:: dc 1,0,0,0, 1,0,0,0, 1,0,0,0
FadePal8:: dc 0,0,0,0, 0,0,0,0, 0,0,0,0
