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
	ld a, d
	and a ; should current music be faded out first?
	ld a, BANK(Music_BikeRiding)
	jr nz, .next2

; Only change the audio ROM bank if the current music isn't going to be faded
; out before the default music begins.
	ld [wAudioROMBank], a

.next2
; [wAudioSavedROMBank] will be copied to [wAudioROMBank] after fading out the
; current music (if the current music is faded out).
	ld [wAudioSavedROMBank], a
	jr .next3

.walking
	ld a, [wMapMusicSoundID]
	ld b, a
	call CompareMapMusicBankWithCurrentBank
	jr c, .next4

.next3
	ld a, [wLastMusicSoundID]
	cp b ; is the default music already playing?
	ret z ; if so, do nothing

.next4
	ld a, c
	ld [wAudioFadeOutControl], a
	ld a, b
	ld [wLastMusicSoundID], a
	ld [wNewSoundID], a
	jp PlaySound

UpdateMusic6Times::
; This is called when entering a map, before fading out the current music and
; playing the default music (i.e. the map's music or biking/surfing music).
; There is a single music engine now (AUDIO_1); the old per-bank dispatch
; (which bank is [wAudioROMBank] pointing at?) is gone. Audio1_UpdateMusic
; reads note data out of whichever bank actually holds it via GetNextMusicByte
; below, which bank-switches per byte.
	ld c, 6
.loop
	push bc ; Bankswitch (inside farcall) clobbers bc, so the loop counter must survive it
	farcall Audio1_UpdateMusic
	pop bc
	dec c
	jr nz, .loop
	ret

CompareMapMusicBankWithCurrentBank::
; Compares the map music's audio ROM bank with the current audio ROM bank
; and updates the audio ROM bank variables.
; Returns whether the banks are different in carry.
	ld a, [wMapMusicROMBank]
	ld e, a
	ld a, [wAudioROMBank]
	cp e
	jr nz, .differentBanks
	ld [wAudioSavedROMBank], a
	and a
	ret
.differentBanks
	ld a, c ; this is a fade-out counter value and it's always non-zero
	and a
	ld a, e
	jr nz, .next
; If the fade-counter is non-zero, we don't change the audio ROM bank because
; it's needed to keep playing the music as it fades out. The FadeOutAudio
; routine will take care of copying [wAudioSavedROMBank] to [wAudioROMBank]
; when the music has faded out.
	ld [wAudioROMBank], a
.next
	ld [wAudioSavedROMBank], a
	scf
	ret

PlayMusic::
	ld b, a
	ld [wNewSoundID], a
	xor a
	ld [wAudioFadeOutControl], a
	ld a, c
	ld [wAudioROMBank], a
	ld [wAudioSavedROMBank], a
	ld a, b

; plays music specified by a. If value is $ff, music is stopped
PlaySound::
; If a channel 4/5/6 SFX was flagged as playing under zero-delay text
; (home/print_text.asm PrintLetterDelay), let it finish before starting a new
; sound instead of cutting it off before the player ever saw its letter.
	push af
	ldh a, [hSFXPlayingDuringText]
	bit 2, a
	res 2, a
	ldh [hSFXPlayingDuringText], a
	call nz, WaitForSoundToFinish
	pop af
	push hl
	push de
	push bc
	ld b, a
	ld a, [wNewSoundID]
	and a
	jr z, .next
	xor a
	ld [wChannelSoundIDs + CHAN5], a
	ld [wChannelSoundIDs + CHAN6], a
	ld [wChannelSoundIDs + CHAN7], a
	ld [wChannelSoundIDs + CHAN8], a
.next
	ld a, [wAudioFadeOutControl]
	and a ; has a fade-out length been specified?
	jr z, .noFadeOut
	ld a, [wNewSoundID]
	and a ; is the new sound ID 0?
	jr z, .done ; if so, do nothing
	xor a
	ld [wNewSoundID], a
	ld a, [wLastMusicSoundID]
	cp $ff ; has the music been stopped?
	jr nz, .fadeOut ; if not, fade out the current music
; If it has been stopped, start playing the new music immediately.
	xor a
	ld [wAudioFadeOutControl], a
.noFadeOut
	xor a
	ld [wNewSoundID], a
; The 4-way bank dispatch (which of Audio1/2/3/4_PlaySound to call, based on
; [wAudioROMBank]) moved into DetermineAudioFunction below, since it's now
; needed in two places (here, and Audio1_note's drum_note / the
; unknownmusic0xef command inside engine_1.asm's note-command interpreter -
; both need to play an SFX in whichever bank is currently active).
	call DetermineAudioFunction
	jr .done

.fadeOut
	ld a, b
	ld [wLastMusicSoundID], a
	ld a, [wAudioFadeOutControl]
	ld [wAudioFadeOutCounterReloadValue], a
	ld [wAudioFadeOutCounter], a
	ld a, b
	ld [wAudioFadeOutControl], a

.done
	pop bc
	pop de
	pop hl
	ret

GetNextMusicByte::
; Reads the next music command byte for the currently-active bank
; ([wAudioROMBank]), then restores the caller's bank. Mandatory in HOME (not
; ROMX): it bank-switches to wAudioROMBank and keeps running, so the code
; itself must stay mapped through the switch - this is the documented
; HOME->ROMX bank-switch landmine (see WRAM_BIBLE.md and
; project_bank_switch_from_romx). Called by Audio1_GetNextMusicByte, once per
; command byte, from the single copy of the note-command interpreter in
; engine_1.asm (AUDIO_1) - this is how that one copy reads note data that
; physically lives in AUDIO_2/3/4.
	ldh a, [hLoadedROMBank]
	push af
	ld a, [wAudioROMBank]
	call SetCurBank
	ld d, $0
	ld a, c
	add a
	ld e, a
	ld hl, wChannelCommandPointers
	add hl, de
	ld a, [hli]
	ld e, a
	ld a, [hld]
	ld d, a
	ld a, [de]
	inc de
	ld [hl], e
	inc hl
	ld [hl], d
	ld e, a
	pop af
	call SetCurBank
	ld a, e
	ret

DetermineAudioFunction::
; Bank-switches to [wAudioROMBank] and calls that bank's PlaySound (b holds
; the sound ID), then restores the caller's bank. Mandatory in HOME for the
; same bank-switch-and-keep-running reason as GetNextMusicByte above; it also
; centralizes the 4-way dispatch that used to be duplicated inline in both
; UpdateMusic6Times and PlaySound.
	ldh a, [hLoadedROMBank]
	push af
	ld a, [wAudioROMBank]
	call SetCurBank
	cp BANK(Audio1_PlaySound)
	jr nz, .checkForAudio2
; audio 1
	ld a, b
	call Audio1_PlaySound
	jr .done

.checkForAudio2
	cp BANK(Audio2_PlaySound)
	jr nz, .checkForAudio3
; audio 2
	ld a, b
	call Audio2_PlaySound
	jr .done

.checkForAudio3
	cp BANK(Audio3_PlaySound)
	jr nz, .audio4
; audio 3
	ld a, b
	call Audio3_PlaySound
	jr .done

.audio4
; invalid banks default to audio 4; vanilla hits this with Missingno, whose
; sprite dimensions overflow into wAudioROMBank (see pokeyellow's
; DetermineAudioFunction, same comment)
	ld a, b
	call Audio4_PlaySound

.done
	pop af
	call SetCurBank
	ret
