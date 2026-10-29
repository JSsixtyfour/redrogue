PlayDefaultMusic::
	call WaitForSoundToFinish
	xor a
	ld c, a
	ld d, a
	ld [wLastMusicSoundID], a
	jr PlayDefaultMusicCommon

PlayDefaultMusicFadeOutCurrent::
; Fade out the current music and then play the default music.
	ld c, 10
	ld d, 0
	ld a, [wStatusFlags4]
	bit BIT_BATTLE_OVER_OR_BLACKOUT, a
	jr z, PlayDefaultMusicCommon
	xor a
	ld [wLastMusicSoundID], a
	ld c, 8
	ld d, c

PlayDefaultMusicCommon::
	ld a, [wWalkBikeSurfState]
	and a
	jr z, .walking
	cp $2
	jr z, .surfing
	ld a, MUSIC_BIKE_RIDING
	jr .next

.surfing
	ld a, MUSIC_SURFING

.next
	ld b, a
;	ld a, d
;	and a ; should current music be faded out first?
;	ld a, 0 ; BANK(Music_BikeRiding)
;	jr nz, .next2

; Only change the audio ROM bank if the current music isn't going to be faded
; out before the default music begins.
;	ld [wAudioROMBank], a

;.next2
; [wAudioSavedROMBank] will be copied to [wAudioROMBank] after fading out the
; current music (if the current music is faded out).
;	ld [wAudioSavedROMBank], a
	jr .next3

.walking
	ld a, [wMapMusicSoundID]
	ld b, a
;	call CompareMapMusicBankWithCurrentBank
;	jr c, .next4

.next3
	ld a, [wLastMusicSoundID]
	cp b ; is the default music already playing?
	ret z ; if so, do nothing

.next4
	ld a, c
	ld [wMusicFade], a
	ld a, b
	ld [wLastMusicSoundID], a
	ld [wMusicFadeID], a

; if no fade, play immediately
	ld a, [wMusicFade]
	and a
	jr nz, .next5
	ld a, b
	call PlayMusic
.next5

	ret

;UpdateMusic6Times::
;CompareMapMusicBankWithCurrentBank:
;	ret

; plays music or SFX specified by a. If value is $ff, music is stopped
PlaySound::
; If an SFX was flagged as playing under zero-delay text (home/print_text.asm
; PrintLetterDelay), let it finish before starting a new sound instead of cutting
; it off before the player ever saw its letter. Kept from the pre-Crystal engine.
	push af
	ldh a, [hSFXPlayingDuringText]
	bit 2, a
	res 2, a
	ldh [hSFXPlayingDuringText], a
	call nz, WaitForSoundToFinish
	pop af
	push de
	cp $ff
	jr nz, .notff
	xor a
	call PlayMusic
	pop de
	ret
.notff
	ld e, a
	xor a
	ld d, a
	call PlaySFX
	pop de
	ret

;InitSound::
;	push hl
;	push de
;	push bc
;	push af
;
;	ldh a, [hLoadedROMBank]
;	push af
;	ld a, BANK(_InitSound)
;	ldh [hLoadedROMBank], a
;	ld [rROMB], a
;
;	call _InitSound
;
;	pop af
;	ldh [hLoadedROMBank], a
;	ld [rROMB], a
;
;	pop af
;	pop bc
;	pop de
;	pop hl
;	ret

UpdateSound::
;	push hl
;	push de
;	push bc
;	push af

	ldh a, [hLoadedROMBank]
	push af
	ld a, BANK(_UpdateSound)
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	call _UpdateSound

	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a

;	pop af
;	pop bc
;	pop de
;	pop hl
	ret

_LoadMusicByte::
; [wCurMusicByte] = [a:de]
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	ld a, [de]
	ld [wCurMusicByte], a
	ld a, BANK(LoadMusicByte)

	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ret

PlayMusic::
	ld e, a
	xor a
	ld d, a
; Play music de.

	push hl
	push de
	push bc
	push af

	ldh a, [hLoadedROMBank]
	push af
	ld a, BANK(_PlayMusic) ; aka BANK(_InitSound)
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	ld a, e
	and a
	jr z, .nomusic

	call _PlayMusic
	jr .end

.nomusic
	call _InitSound

.end
	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	pop af
	pop bc
	pop de
	pop hl
	ret

;PlayMusic2::
;	ld e, a
;	xor a
;	ld d, a
; Stop playing music, then play music de.
;
;	push hl
;	push de
;	push bc
;	push af
;
;	ldh a, [hLoadedROMBank]
;	push af
;	ld a, BANK(_PlayMusic)
;	ldh [hLoadedROMBank], a
;	ld [rROMB], a
;
;	push de
;	ld de, MUSIC_NONE
;	call _PlayMusic
;	call DelayFrame
;	pop de
;	call _PlayMusic
;
;	pop af
;	ldh [hLoadedROMBank], a
;	ld [rROMB], a
;
;	pop af
;	pop bc
;	pop de
;	pop hl
;	ret

PlayCry::
; Play monster a's cry.
	push bc
	ld bc, 0
	call PlayCryWithOffsets
	pop bc
	ret

PlayCryWithOffsets::
; Play monster a's cry with Red-style pitch/length offsets b/c (Growl's move sound).
; The table lookup and offset math live with the engine (crysaudio/red_rogue_play_cry.asm).
	push hl
	push de
	push bc
	push af

	ld e, a
	ldh a, [hLoadedROMBank]
	push af
	ld a, BANK(_RedRoguePlayCry)
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	ld a, e
	call _RedRoguePlayCry

	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	call WaitForSoundToFinish

	pop af
	pop bc
	pop de
	pop hl
	ret

PlayBattleSound::
	push hl
	push de
	push bc
	push af

	push af
	ld a, c
	ld [wCryPitch], a
	ld a, b
	ld [wCryPitch + 1], a
	ld a, e
	ld [wCryLength], a
	ld a, d
	ld [wCryLength + 1], a
	pop af

	ld e, a
	xor a
	ld d, a

	ldh a, [hLoadedROMBank]
	push af

	ld a, BANK(_PlayBattleSound)
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	ld a, e
	ld [wCurSFX], a
	call _PlayBattleSound

	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	pop af
	pop bc
	pop de
	pop hl
	ret

PlaySFX::
; Play sound effect de.
; Sound effects are ordered by priority (highest to lowest)

	push hl
	push de
	push bc
	push af

	; Is something already playing?
;	call CheckSFX
;	jr nc, .play

	; Does it have priority?
;	ld a, [wCurSFX]
;	cp e
;	jr c, .done

.play
	ldh a, [hLoadedROMBank]
	push af
	ld a, BANK(_PlaySFX)
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	ld a, e
	ld [wCurSFX], a
	call _PlaySFX

	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a

.done
	pop af
	pop bc
	pop de
	pop hl
	ret

PlaySoundWaitForCurrent::
WaitPlaySFX::
	push af
	call WaitForSoundToFinish
	pop af
	jp PlaySound

; Wait for sound to finish playing
WaitForSoundToFinish::
WaitSFX::
	ld a, [wLowHealthAlarm]
	and a
	ret nz
	ld a, [wSFXDontWait]
	and a
	ret nz
	; BATTLE SPEED 4X: in battle, don't hold the game for a cry or hit sound
	; to finish (the next sound may cut its tail). 1X and 2X still wait.
	; Kept from the pre-Crystal WaitForSoundToFinish (home/delay.asm).
	ldh a, [hIsInBattle]
	and a
	jr z, .waitForSfx
	ld a, [wOptions3]
	and BATTLE_SPEED_MASK
	cp BATTLE_SPEED_X4
	ret z
.waitForSfx

; infinite loop until sfx is done playing

	push hl

.wait
	ld hl, wChannel5Flags1
	bit 0, [hl]
	jr nz, .wait
	ld hl, wChannel6Flags1
	bit 0, [hl]
	jr nz, .wait
	ld hl, wChannel7Flags1
	bit 0, [hl]
	jr nz, .wait
	ld hl, wChannel8Flags1
	bit 0, [hl]
	jr nz, .wait

	pop hl
	ret

WaitForSongToFinish::
.loop
	call IsSongPlaying
	jr c, .loop
	ret

IsSongPlaying::
; Return carry if any song channels are active.
	ld a, [wChannel1Flags1]
	bit 0, a
	jr nz, .playing
	ld a, [wChannel2Flags1]
	bit 0, a
	jr nz, .playing
	ld a, [wChannel3Flags1]
	bit 0, a
	jr nz, .playing
	ld a, [wChannel4Flags1]
	bit 0, a
	jr nz, .playing
	and a
	ret
.playing
	scf
	ret
