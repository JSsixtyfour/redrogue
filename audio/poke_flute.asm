; Plays the key-item / badge fanfare while the BATTLE audio bank (AUDIO_2) is
; loaded. SFX_GET_KEY_ITEM has no AUDIO_2 entry, and sound IDs are bank-relative,
; so playing it here lands on whatever occupies that offset in bank 8 - the
; "wrong music bank is loaded" the gym scripts' old comments describe.
;
; Instead: start SFX_CAUGHT_MON (which DOES exist in this bank, so the channels
; get allocated correctly), then immediately repoint those channels at
; SFX_UnusedFanfare, an otherwise-unreferenced 3-channel fanfare already sitting
; in bank 8. Ported from shinpokered's Music_GetKeyItemInBattle; its data is
; byte-identical to that fork's SFX_08_unused2, and audio/sfx/unused_fanfare.asm's
; own header records it as SFX_KEY_ITEM in pokegold/pokecrystal - so this is the
; intended fanfare, not a stand-in.
;
; Deliberately does NOT touch wAudioROMBank: victory music from this same bank is
; still playing, and repointing the bank mid-playback would make the engine read
; the live music channels' command bytes out of the wrong bank.
Music_GetKeyItemInBattle::
	ld a, SFX_CAUGHT_MON
	call PlaySoundWaitForCurrent
	ld hl, wChannelCommandPointers + CHAN5 * 2
	ld de, SFX_UnusedFanfare_Ch5
	call Audio2_OverwriteChannelPointer
	ld de, SFX_UnusedFanfare_Ch6
	call Audio2_OverwriteChannelPointer
	ld de, SFX_UnusedFanfare_Ch7
	call Audio2_OverwriteChannelPointer
; Wait for the fanfare here rather than in HOME's TextCommand_SOUND: ROM0 has
; only tens of bytes free, and spinning here is free (VBlank still drives the
; audio engine). CHAN7 is the fanfare's last channel, so it clears last.
.waitFanfare
	ld a, [wChannelSoundIDs + CHAN7]
	and a
	jr nz, .waitFanfare
	ret

Music_PokeFluteInBattle::
	; begin playing the "caught mon" sound effect
	ld a, SFX_CAUGHT_MON
	call PlaySoundWaitForCurrent
	; then immediately overwrite the channel pointers
	ld hl, wChannelCommandPointers + CHAN5 * 2
	ld de, SFX_Pokeflute_Ch5
	call Audio2_OverwriteChannelPointer
	ld de, SFX_Pokeflute_Ch6
	call Audio2_OverwriteChannelPointer
	ld de, SFX_Pokeflute_Ch7

Audio2_OverwriteChannelPointer:
	ld a, e
	ld [hli], a
	ld a, d
	ld [hli], a
	ret
