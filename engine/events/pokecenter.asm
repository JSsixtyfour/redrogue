DisplayPokemonCenterDialogue_::
	call SaveScreenTilesToBuffer1 ; save screen
	ld hl, wStatusFlags4
	bit BIT_USED_POKECENTER, [hl]
	set BIT_UNKNOWN_4_1, [hl]
	set BIT_USED_POKECENTER, [hl]
	jr nz, .repeatHealText
	ld hl, PokemonCenterFirstHealText
	call PrintText
	jr .heal
.repeatHealText
	ld hl, PokemonCenterRepeatHealText
	call PrintText
.heal
	call SetLastBlackoutMap
	call LoadScreenTilesFromBuffer1 ; restore screen
	ld hl, NeedYourPokemonText
	call PrintText
	ld a, $28
	ld [wSprite01StateData1ImageIndex], a ; make the nurse turn to face the machine
	call Delay3
	predef HealParty
	farcall AnimateHealingMachine ; do the healing machine animation
	xor a
	ld [wAudioFadeOutControl], a
	ld a, [wAudioSavedROMBank]
	ld [wAudioROMBank], a
	ld a, [wMapMusicSoundID]
	ld [wLastMusicSoundID], a
	ld [wNewSoundID], a
	call PlaySound
	ld a, $24
	ld [wSprite01StateData1ImageIndex], a ; make the nurse bow
	ld c, a
	call DelayFrames
	ld hl, PokemonCenterFarewellText
	call PrintText
	jp UpdateSprites

PokemonCenterFirstHealText:
	text_far _PokemonCenterFirstHealText
	text_end

PokemonCenterRepeatHealText:
	text_far _PokemonCenterRepeatHealText
	text_end

NeedYourPokemonText:
	text_far _NeedYourPokemonText
	text_end

PokemonCenterFarewellText:
	text_far _PokemonCenterFarewellText
	text_end
