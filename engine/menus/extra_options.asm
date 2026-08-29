; ============================================================================
; Extra options menu (Shin Red import, Phase 0).
;
; Reached by pressing SELECT on the normal OPTION screen - see the .extraMenu
; hook in DisplayOptionMenu (engine/menus/main_menu.asm). SELECT was previously
; masked off and did nothing there (`and ~PAD_SELECT`), so this claims an input
; that was genuinely free.
;
; AUDIO's state lives in wOptions2, NOT a spare wOptions bit: wOptions has no
; safely usable SPARE bits (SetCursorPositionsFromOptions does `and $3f` then
; IsInArray over TextSpeedOptionData, so a nonzero value in bits 3-5 walks past
; that table's terminator - see wOptions2's comment in ram/wram.asm). INST. TXT
; below is different: it's not a spare bit, it deliberately reuses wOptions'
; EXISTING TEXT_DELAY_MASK bits (see its own comment for why).
;
; STATUS: six rows - AUDIO (Phase 2.11), INST. TXT (Phase 8, text-speed work),
; LEVELS, FOLLOWER, COLORS and 60 FPS. See the ROW_* / NUM_EXTRA_OPTION_ROWS constants
; below, which are the authority; this paragraph has already gone stale once.
; INST. TXT does NOT add a check to PrintLetterDelay (home/print_text.asm)
; - that routine runs once per printed letter, easily hundreds of times a
; screen, and this fork's RNG is cycle-timing-sensitive (see
; project_smoke_suite_catches_rng_drift): even a dead, never-taken branch added
; there measurably shifted the RNG stream and hung a smoke test on an unrelated
; door warp. Instead INST. TXT drives the SAME wOptions low 3 bits the normal
; TEXT SPEED menu already writes (TEXT_DELAY_MASK), setting them to the new
; TEXT_DELAY_INSTANT (0) - PrintLetterDelay's existing `and $f` / `jr nz` zero
; -delay path (already unconditional on every letter) picks this up for free,
; costing nothing new on the hot path. Turning it off restores TEXT_DELAY_FAST.
; This is exactly shinpokered's own approach (its ToggleLaglessText does
; `and %11111001 / xor TEXT_DELAY_FAST` on wOptions).
;
; It only survives because BOTH SetOptionsFromCursorPositions and
; SetCursorPositionsFromOptions carry a matching guard (also ported from
; shinpokered - see their comments in main_menu.asm). Without those, the OPTION
; menu rewrites wOptions from its TEXT SPEED cursor on every loop pass and
; instantly undoes this. Consequence, matching shinpokered: while INST. TXT is
; on, the normal TEXT SPEED row is inert - turn INST. TXT off to use it again.
;
; AUDIO row: LEFT/RIGHT cycles wOptions2 bits 4-5 (SOUND_MASK2, see
; constants/audio_constants.asm) through MONO/EARPHONE1/EARPHONE2/EARPHONE3,
; consumed by Audio1_ApplyMonoStereo (audio/engine_1.asm). LEFT/RIGHT edits
; whichever row the cursor is on; UP/DOWN moves between rows.
;
; ADDING A ROW: this is now generic and no longer the hazard this comment used
; to describe. hCurrentMenuItem holds the row index (0-based), the cursor uses a
; real increment-and-wrap against NUM_EXTRA_OPTION_ROWS, and .drawCursor walks a
; row-to-Y table. Add a ROW_* constant, bump NUM_EXTRA_OPTION_ROWS, add the label
; and value strings, and add a `cp ROW_x / jr z` arm to the LEFT/RIGHT dispatch.
;
; Known quirk, pre-existing and left alone: UP and DOWN both advance the cursor
; forward, because the handler tests PAD_UP | PAD_DOWN together and unconditionally
; increments. On a 5-row menu that makes UP a 4-step detour rather than a step back.
; The caller re-runs DisplayOptionMenu on return, so there is no need to redraw
; the normal option screen from here.
;
; hCurrentMenuItem is reused as transient row-cursor scratch for the lifetime
; of this menu's own loop only: neither JoypadLowSensitivity nor PlaySound (the
; only other calls in that loop) touch it, and nothing here reads it as "the"
; global current menu item.
; ============================================================================

SECTION "Extra Options Menu", ROMX

DEF ROW_AUDIO EQU 0
DEF ROW_INSTANT_TEXT EQU 1
DEF ROW_LEVELS EQU 2
DEF ROW_FOLLOWER EQU 3
DEF ROW_ENHANCED_COLORS EQU 4
DEF ROW_60_FPS EQU 5
DEF NUM_EXTRA_OPTION_ROWS EQU 6

DisplayExtraOptionMenu::
; The caller clears the screen on both sides of this call and fully redraws the
; OPTION screen afterwards, so there is nothing to save or restore here.
; Deliberately NOT SaveScreenTilesToBuffer2/LoadScreenTilesFromBuffer2: buffer2
; is shared scratch (pc.asm, players_pc.asm, oaks_pc.asm and the start-menu path
; all use it), and borrowing it here restored a stale screen, leaving the start
; menu visibly bleeding through the OPTION screen until the menu was fully
; exited.
	call ClearScreen
	call Delay3
	hlcoord 0, 0
	ld b, 2
	ld c, 18
	call TextBoxBorder
	hlcoord 0, 4
	ld b, 12
	ld c, 18
	call TextBoxBorder
	hlcoord 1, 2
	ld de, ExtraOptionsTitleText
	call PlaceString
	hlcoord 1, 5
	ld de, ExtraOptionsAudioLabelText
	call PlaceString
	call .drawAudioValue
	hlcoord 1, 7
	ld de, ExtraOptionsInstantTextLabelText
	call PlaceString
	call .drawInstantTextValue
	hlcoord 1, 9
	ld de, ExtraOptionsLevelsLabelText
	call PlaceString
	call .drawLevelsValue
	hlcoord 1, 11
	ld de, ExtraOptionsFollowerLabelText
	call PlaceString
	call .drawFollowerValue
	hlcoord 1, 13
	ld de, ExtraOptionsColorsLabelText
	call PlaceString
	call .drawColorsValue
	hlcoord 1, 15
	ld de, ExtraOptions60FPSLabelText
	call PlaceString
	call .draw60FPSValue
	hlcoord 2, 16
	ld de, ExtraOptionsCancelText
	call PlaceString
	xor a ; ROW_AUDIO
	ldh [hCurrentMenuItem], a
	call .drawCursor
	ld a, $01
	ldh [hAutoBGTransferEnabled], a
	call Delay3
.loop
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	ld b, a
	and PAD_A | PAD_B | PAD_START | PAD_SELECT
	jp nz, .exit
	ld a, b
	and PAD_UP | PAD_DOWN
	jr z, .checkLeftRight
	ld a, SFX_PRESS_AB
	call PlaySound
	ldh a, [hCurrentMenuItem]
	inc a
	cp NUM_EXTRA_OPTION_ROWS
	jr c, .rowCursorDone
	xor a
.rowCursorDone
	ldh [hCurrentMenuItem], a
	call .drawCursor
	jr .loop
.checkLeftRight
	ld a, b
	and PAD_LEFT | PAD_RIGHT
	jr z, .loop
	ld b, a
	ld a, SFX_PRESS_AB
	call PlaySound
	ldh a, [hCurrentMenuItem]
	cp ROW_60_FPS
	jr z, .toggle60FPS
	cp ROW_ENHANCED_COLORS
	jr z, .toggleEnhancedColors
	cp ROW_LEVELS
	jp z, .cycleLevels
	cp ROW_FOLLOWER
	jr z, .toggleFollower
	cp ROW_INSTANT_TEXT
	jr z, .toggleInstantText
.cycleAudio
	ld a, [wOptions2]
	ld d, a
	and SOUND_MASK2
	swap a ; bits 4-5 (SOUND_MASK2) -> bits 0-1
	bit B_PAD_RIGHT, b
	jr nz, .cycleRight
	dec a
	and $3
	jr .cycleDone
.cycleRight
	inc a
	and $3
.cycleDone
	swap a ; bits 0-1 -> bits 4-5
	ld e, a
	ld a, d
	and ~SOUND_MASK2 & $ff
	or e
	ld [wOptions2], a
	call .drawAudioValue
	jr .loop
.toggleInstantText
; binary option: LEFT and RIGHT both flip it, matching the AUDIO row's use of
; the same two buttons for its own cycle. "On" IS wOptions' low 3 bits reading
; TEXT_DELAY_INSTANT (0) - no separate flag to keep in sync.
	ld a, [wOptions]
	and TEXT_DELAY_MASK
	jr z, .turnOff ; was already instant -> turn off, default to FAST
; currently FAST/MEDIUM/SLOW -> turn on: clear the low 3 bits to
; TEXT_DELAY_INSTANT (0)
	ld a, [wOptions]
	and ~TEXT_DELAY_MASK & $ff
	ld [wOptions], a
	jr .drawInstantText
.turnOff
	ld a, [wOptions]
	and ~TEXT_DELAY_MASK & $ff
	or TEXT_DELAY_FAST
	ld [wOptions], a
.drawInstantText
	call .drawInstantTextValue
	jp .loop
.toggleEnhancedColors
	ld hl, wOptions2
	ld a, 1 << BIT_ENHANCED_COLORS
	xor [hl]
	ld [hl], a
	call .drawColorsValue
	jp .loop
.toggleFollower
	ld hl, wOptions2
	ld a, 1 << BIT_FOLLOWER_DISABLED
	xor [hl]
	ld [hl], a
	call .drawFollowerValue
	jp .loop
.toggle60FPS
	ld hl, wOptions2
	ld a, 1 << BIT_60_FPS
	xor [hl]
	ld [hl], a
	predef SetCPUSpeed
	call .draw60FPSValue
	jp .loop
.exit
	ld a, SFX_PRESS_AB
	call PlaySound
	ret

; Places '▷' at the currently selected row's column 0 and blanks the other
; rows. Redraws every row rather than tracking the previous position.
.drawCursor
	ld hl, .rowYTable
	ld c, 0
	ld b, NUM_EXTRA_OPTION_ROWS
.drawCursorLoop
	ld a, [hli]
	push hl
	push bc
	hlcoord 0, 0
	ld bc, SCREEN_WIDTH
	call AddNTimes
	pop bc
	ldh a, [hCurrentMenuItem]
	cp c
	ld a, ' '
	jr nz, .drawCursorChar
	ld a, '▷'
.drawCursorChar
	ld [hl], a
	pop hl
	inc c
	dec b
	jr nz, .drawCursorLoop
	ret

.rowYTable
	db 5 ; ROW_AUDIO
	db 7 ; ROW_INSTANT_TEXT
	db 9 ; ROW_LEVELS
	db 11 ; ROW_FOLLOWER
	db 13 ; ROW_ENHANCED_COLORS
	db 15 ; ROW_60_FPS

; Cycle the stored difficulty through the display order, preserving the other
; bits in wOptions2.
.cycleLevels
	ld a, [wOptions2]
	ld d, a
	and DIFFICULTY_MASK
	ld e, a
	ld hl, .levelsDisplayOrder
	xor a
	ld c, a
.findLevelsPosition
	ld a, [hli]
	cp e
	jr z, .foundLevelsPosition
	inc c
	jr .findLevelsPosition
.foundLevelsPosition
	bit B_PAD_RIGHT, b
	jr nz, .stepLevelsRight
	ld a, c
	and a
	jr z, .wrapLevelsLeft
	dec c
	jr .levelsPositionReady
.wrapLevelsLeft
	ld c, NUM_LEVELS_SETTINGS - 1
	jr .levelsPositionReady
.stepLevelsRight
	inc c
	ld a, c
	cp NUM_LEVELS_SETTINGS
	jr c, .levelsPositionReady
	xor a
	ld c, a
.levelsPositionReady
	ld a, d
	and ~DIFFICULTY_MASK & $ff
	ld b, a
	ld hl, .levelsDisplayOrder
	ld a, c
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	or b
	ld [wOptions2], a
	call .drawLevelsValue
	jp .loop

.levelsDisplayOrder
	db DIFFICULTY_VERY_EASY
	db DIFFICULTY_EASY
	db DIFFICULTY_NORMAL
	db DIFFICULTY_HARD
	db DIFFICULTY_VERY_HARD
DEF NUM_LEVELS_SETTINGS EQU 5

; Prints the current AUDIO mode at a fixed 9-char-wide column so a shorter
; name (MONO) fully overwrites a longer one (EARPHONEn) left behind by the
; previous draw. Column 10, not 8: "INST. TXT" below is 9 characters and ran
; into a value drawn at column 8. The widest value (EARPHONE1) still ends at
; column 18, the last cell inside the border.
.drawAudioValue
	hlcoord 10, 5
	ld a, [wOptions2]
	and SOUND_MASK2
	swap a
	ld e, a
	ld d, 0
	push hl
	ld hl, .valueTextTable
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	pop hl
	call PlaceString
	ret

.valueTextTable
	dw ExtraOptionsAudioMonoText
	dw ExtraOptionsAudioEarphone1Text
	dw ExtraOptionsAudioEarphone2Text
	dw ExtraOptionsAudioEarphone3Text

; Prints the current LEVELS value at the same fixed column as the other values.
.drawLevelsValue
	hlcoord 10, 9
	ld a, [wOptions2]
	and DIFFICULTY_MASK
	ld e, a
	ld d, 0
	push hl
	ld hl, .levelsValueTextTable
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	pop hl
	call PlaceString
	ret

.levelsValueTextTable
	dw ExtraOptionsLevelsNormalText
	dw ExtraOptionsLevelsEasyText
	dw ExtraOptionsLevelsVeryEasyText
	dw ExtraOptionsLevelsHardText
	dw ExtraOptionsLevelsVeryHardText

; Prints ON/OFF at the same fixed column as .drawAudioValue. "On" is wOptions'
; low 3 bits reading TEXT_DELAY_INSTANT (0).
.drawInstantTextValue
	hlcoord 10, 7
	ld de, ExtraOptionsInstantTextOnText
	ld a, [wOptions]
	and TEXT_DELAY_MASK
	jr z, .placeInstantTextValue
	ld de, ExtraOptionsInstantTextOffText
.placeInstantTextValue
	jp PlaceString

.drawColorsValue
	hlcoord 10, 13
	ld de, ExtraOptionsOnText
	ld a, [wOptions2]
	bit BIT_ENHANCED_COLORS, a
	jr nz, .placeBinaryValue
	ld de, ExtraOptionsOffText
	jr .placeBinaryValue

.drawFollowerValue
	hlcoord 10, 11
	ld de, ExtraOptionsOnText
	ld a, [wOptions2]
	bit BIT_FOLLOWER_DISABLED, a
	jr z, .placeBinaryValue
	ld de, ExtraOptionsOffText
	jr .placeBinaryValue

.draw60FPSValue
	hlcoord 10, 15
	ld de, ExtraOptionsOnText
	ld a, [wOptions2]
	bit BIT_60_FPS, a
	jr nz, .placeBinaryValue
	ld de, ExtraOptionsOffText
.placeBinaryValue
	jp PlaceString

ExtraOptionsTitleText:
	db "EXTRA OPTIONS@"

ExtraOptionsAudioLabelText:
	db "AUDIO@"

ExtraOptionsAudioMonoText:
	db "MONO     @"

ExtraOptionsAudioEarphone1Text:
	db "EARPHONE1@"

ExtraOptionsAudioEarphone2Text:
	db "EARPHONE2@"

ExtraOptionsAudioEarphone3Text:
	db "EARPHONE3@"

ExtraOptionsLevelsLabelText:
	db "LEVELS@"

ExtraOptionsLevelsVeryEasyText:
	db "VERY EASY@"
ExtraOptionsLevelsEasyText:
	db "EASY     @"
ExtraOptionsLevelsNormalText:
	db "NORMAL   @"
ExtraOptionsLevelsHardText:
	db "HARD     @"
ExtraOptionsLevelsVeryHardText:
	db "VERY HARD@"

ExtraOptionsInstantTextLabelText:
; 7 characters, so it stops clear of the value column at 10. "INST. TXT" was 9
; and butted straight up against it with no gap.
	db "INSTANT@"

ExtraOptionsInstantTextOnText:
	db "ON       @"

ExtraOptionsInstantTextOffText:
	db "OFF      @"

ExtraOptionsColorsLabelText:
	db "COLORS@"

ExtraOptionsFollowerLabelText:
	db "FOLLOWER@"

ExtraOptions60FPSLabelText:
	db "60 FPS@"

ExtraOptionsOnText:
	db "ON       @"

ExtraOptionsOffText:
	db "OFF      @"

ExtraOptionsCancelText:
	db "CANCEL@"
