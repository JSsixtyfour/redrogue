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
; KNOWN HARNESS DISCREPANCY, 2026-08-20 - do NOT delete this clear to make the
; smoke suite green. With this clear present `make smoke` fails 23 assertions
; (stage-door warps appear never to fire under PyBoy), and removing it returns
; 12/12. It was removed once on that basis and that was WRONG: the user then
; verified the real build on an actual emulator - walked through a lobby stage
; door, reached Rocket B1F, fought a trainer, no issues, correct rendering.
; The game is fine; the failure is specific to the PyBoy harness.
;
; Mechanism still UNKNOWN. Ruled out so far: RunPaletteCommand's CGB arm
; (disabling it did not help), rVBK's constant ($FF4F, hardware.inc:588),
; aliasing on wOnCGB (alone at $cf12), a VBlank ISR writing while rVBK=1 (both
; callers have interrupts unable to fire - :43 is inside Init's `di`, :112 runs
; DisableLCD first), and PyBoy's VRAM bank emulation itself (probed directly:
; bank 0 and bank 1 hold separate values as they should). Investigate the
; harness next; fix it there, not by deleting this clear.
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
