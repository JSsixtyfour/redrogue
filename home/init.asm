SoftReset::
	call StopAllSounds
	call GBPalWhiteOut
	ld c, 32
	call DelayFrames
	; Carry the CGB flag through Init's WRAM0 wipe in E, exactly as _Start does.
	; Must be the last thing before the fallthrough: the calls above clobber de.
	ld a, [wOnCGB]
	ld e, a
	; fallthrough

Init::
;  Program init.
	di

	xor a
	ldh [rIF], a
	ldh [rIE], a
	ldh [rSCX], a
	ldh [rSCY], a
	ldh [rSB], a
	ldh [rSC], a
	ldh [rWX], a
	ldh [rWY], a
	ldh [rTMA], a
	ldh [rTAC], a
	ldh [rBGP], a
	ldh [rOBP0], a
	ldh [rOBP1], a

	ld a, LCDC_ON
	ldh [rLCDC], a
	call DisableLCD

	ld sp, wStack

	ld hl, STARTOF(WRAM0)
	ld bc, SIZEOF(WRAM0)
.loop
	ld [hl], 0
	inc hl
	dec bc
	ld a, b
	or c
	jr nz, .loop

	; Restore the CGB flag the wipe just destroyed, from E (see _Start).
	; MUST be before ClearVram, which reads wOnCGB to decide whether to also
	; clear VRAM bank 1's attribute map.
	ld a, e
	ld [wOnCGB], a

	call ClearVram

	ld hl, STARTOF(HRAM)
	ld bc, SIZEOF(HRAM)
	call FillMemory

	call ClearSprites

	ld a, BANK(WriteDMACodeToHRAM)
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	call WriteDMACodeToHRAM

	xor a
	ldh [hTileAnimations], a
	ldh [rSTAT], a
	ldh [hSCX], a
	ldh [hSCY], a
	ldh [rIF], a
	ld a, IE_VBLANK | IE_TIMER | IE_SERIAL
	ldh [rIE], a

	ld a, 144 ; move the window off-screen
	ldh [hWY], a
	ldh [rWY], a
	ld a, 7
	ldh [rWX], a

	ld a, CONNECTION_NOT_ESTABLISHED
	ldh [hSerialConnectionStatus], a

	ld h, HIGH(vBGMap0)
	call ClearBgMap
	ld h, HIGH(vBGMap1)
	call ClearBgMap

	ld a, LCDC_DEFAULT
	ldh [rLCDC], a
	ld a, 16
	ldh [hSoftReset], a
	call StopAllSounds

	ei

	predef LoadSGB

	ld a, BANK(SFX_Shooting_Star)
	ld [wAudioROMBank], a
	ld [wAudioSavedROMBank], a
	ld a, HIGH(vBGMap1)
	ldh [hAutoBGTransferDest + 1], a
	xor a
	ldh [hAutoBGTransferDest], a
	dec a
	ldh [hUpdateSpritesEnabled], a

	predef PlayIntro

	call DisableLCD
	call ClearVram
	call GBPalNormal
	call ClearSprites
	ld a, LCDC_DEFAULT
	ldh [rLCDC], a

	jp PrepareTitleScreen

ClearVram::
; Shin Red import Phase 3: on CGB, VRAM bank 1 holds the BG attribute map (one
; byte per tile: palette in bits 0-2, tile bank 3, flips 5-6, priority 7).
; Boot-ROM state there is not something to rely on, and leftover garbage gives
; every tile a random palette and random flips - that was the observed symptom
; of the first GBC build (colours differing on every single boot). Clear it too,
; then put rVBK back on bank 0: every other VRAM writer in the tree assumes
; bank 0 and never touches rVBK.
;
; HISTORY, 2026-08-20 - RESOLVED, recorded so it is not re-litigated. Adding
; this clear made `make smoke` fail 23 assertions (stage-door warps appearing
; never to fire), and it was deleted once on that basis. That was WRONG: the
; real build was fine all along, verified on BGB (lobby door -> Rocket B1F ->
; trainer battle, correct rendering). The clear only shifted init timing, and
; the harness's enter_stage_door1 was walking onto the warp with a hardcoded
; 20-frame press - too short at the new phase, since a warp fires only while the
; direction is still held as the step lands. Measured: 20/24/30-frame presses
; never warped, 40 always did. Fixed in tools/pyboy_smoke/harness.py by making
; door entry retry instead of trusting a fixed press. Nothing was wrong here.
	ld a, [wOnCGB]
	and a
	jr z, .bank0
	ld a, 1
	ldh [rVBK], a
	call .bank0
	xor a
	ldh [rVBK], a
.bank0
	ld hl, STARTOF(VRAM)
	ld bc, SIZEOF(VRAM)
	xor a
	jp FillMemory


StopAllSounds::
	ld a, BANK("Audio Engine 1")
	ld [wAudioROMBank], a
	ld [wAudioSavedROMBank], a
	xor a
	ld [wAudioFadeOutControl], a
	ld [wNewSoundID], a
	ld [wLastMusicSoundID], a
	dec a
	jp PlaySound
