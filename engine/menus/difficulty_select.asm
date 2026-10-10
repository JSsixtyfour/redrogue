; Difficulty-select screen, reached by farcall from OakSpeech in place of
; ChoosePlayerCharacter, which it chains into once a tier is chosen.
;
; Entry state is the same as ChoosePlayerCharacter's (screen cleared and faded
; out to white, hAutoBGTransferEnabled on, MUSIC_ROUTES2 playing), and it fades
; out and clears again before handing over, so character select sees exactly the
; state it always did. Entering through this one label keeps OakSpeech's bank1
; footprint unchanged (same-size farcall).
;
; The tier lives only in wOptions2 & DIFFICULTY_MASK, the same bits the OPTION
; menu's DIFFICULTY row edits, and every LEFT/RIGHT writes it straight back
; (there is no cancel, so committing on A would be identical). That also means
; no scratch RAM: the display index is re-derived from wOptions2 on demand.
; PrepareOakSpeech keeps wOptions2 across the new-game wipe, so a tier picked on
; the title-screen OPTION menu shows here as the starting position.

; ---------------------------------------------------------------------------
; Tier descriptions: 2 lines of at most 18 characters each, split by <NEXT>.
; Numbers from balance_constants.asm (DIFF_LEVEL_PCT_* / DIFF_PRIZE_BONUS_PCT_*),
; 2026-10-09. HARD is the balance baseline.
; ---------------------------------------------------------------------------
DifficultySelectDescriptions:
	dw .veryEasy, .easy, .normal, .hard, .veryHard
.veryEasy: db "Foes 30% lower.<NEXT>Simple AI, most ¥.@"
.easy:     db "Foes 20% lower.<NEXT>More prize money.@"
.normal:   db "Foes 10% lower.<NEXT>A bit more money.@"
.hard:     db "The intended run:<NEXT>full-level foes.@"
.veryHard: db "Foes 10% higher.<NEXT>Smarter AI early.@"

; Display order, easiest to hardest -> stored DIFFICULTY_* value. Same values as
; OptDifficultyOrder in options_menu.asm (a different bank, so duplicated).
DifficultySelectOrder:
	db DIFFICULTY_VERY_EASY
	db DIFFICULTY_EASY
	db DIFFICULTY_NORMAL
	db DIFFICULTY_HARD
	db DIFFICULTY_VERY_HARD
DEF DIFFSEL_NUM_TIERS EQU 5
DEF DIFFSEL_NORMAL_INDEX EQU 2
	ASSERT DIFFSEL_NUM_TIERS == NUM_AI_DIFFICULTY_ROWS

; 10 characters each (field = columns 5-14), padded so a redraw fully
; overwrites the previous name. The field, its arrows (columns 3 and 16) and the
; title are centred on the screen's true centre, 9.5, so the even-length names
; sit exactly in the middle; the 9-character ones can only be half a tile off.
DifficultySelectNames:
	dw .veryEasy, .easy, .normal, .hard, .veryHard
.veryEasy: db "VERY EASY @"
.easy:     db "   EASY   @"
.normal:   db "  NORMAL  @"
.hard:     db "   HARD   @"
.veryHard: db "VERY HARD @"

; The track's five stops sit at columns 1, 5, 9, 13 and 17. A tile-aligned
; marker can't land on 9.5, so the NORMAL stop is half a tile left of centre.
DEF DIFFSEL_TRACK_X EQU 1
DEF DIFFSEL_STOP_SPACING EQU 4

ChooseDifficultyThenCharacter::
	call DifficultySelect
	call GBFadeOutToWhite
	call ClearScreen
	farjp ChoosePlayerCharacter

DifficultySelect:
	hlcoord 5, 1
	ld de, DifficultySelectTitleText
	call PlaceString
	hlcoord 3, 3
	ld [hl], '◀'
	hlcoord 16, 3
	ld [hl], '▶'
	hlcoord DIFFSEL_TRACK_X, 6
	ld de, DifficultySelectTrackText
	call PlaceString
	hlcoord 1, 7
	ld de, DifficultySelectEndsText
	call PlaceString
	hlcoord 1, 9
	ld de, DifficultySelectNoteText
	call PlaceString
	call DiffSelDrawTier
	call GBFadeInFromWhite
	ld hl, ChooseDifficultyText
	call PrintText
	call DiffSelDrawDescription
.inputLoop
	call DelayFrame
	call JoypadLowSensitivity
	ldh a, [hJoy5] ; newly pressed
	ld b, a
	and PAD_A | PAD_LEFT | PAD_RIGHT
	jr z, .inputLoop
	bit B_PAD_A, b
	jr nz, .chosen
	push bc
	call DiffSelGetIndex
	pop bc
	bit B_PAD_LEFT, b
	jr nz, .easier
; harder, stopping at the hard end of the slider (no wrap)
	cp DIFFSEL_NUM_TIERS - 1
	jr nc, .inputLoop
	inc a
	jr .move
.easier
	and a
	jr z, .inputLoop
	dec a
.move
	call DiffSelSetIndex
	ld a, SFX_TINK
	call PlaySound
	call DiffSelDrawTier
	call DiffSelDrawDescription
	jr .inputLoop

.chosen
	ld a, SFX_PRESS_AB
	jp PlaySound

; a = display index (0 = VERY EASY) of the tier in wOptions2. A value no row
; lists falls back to NORMAL, as the OPTION menu and AIResolveTier both do.
DiffSelGetIndex:
	ld a, [wOptions2]
	and DIFFICULTY_MASK
	ld b, a
	ld hl, DifficultySelectOrder
	ld c, 0
.loop
	ld a, [hli]
	cp b
	jr z, .found
	inc c
	ld a, c
	cp DIFFSEL_NUM_TIERS
	jr c, .loop
	ld c, DIFFSEL_NORMAL_INDEX
.found
	ld a, c
	ret

; Writes display index a back into wOptions2's difficulty bits.
DiffSelSetIndex:
	ld c, a
	ld b, 0
	ld hl, DifficultySelectOrder
	add hl, bc
	ld b, [hl]
	ld a, [wOptions2]
	and ~DIFFICULTY_MASK
	or b
	ld [wOptions2], a
	ret

; hl = entry [index] of the dw table at hl.
DiffSelPointerAtIndex:
	push hl
	call DiffSelGetIndex
	pop hl
	add a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; Name on row 3 and the marker above the track on row 5.
DiffSelDrawTier:
	ld hl, DifficultySelectNames
	call DiffSelPointerAtIndex
	ld d, h
	ld e, l
	hlcoord 5, 3
	call PlaceString
	hlcoord 0, 5
	lb bc, 1, SCREEN_WIDTH
	call ClearScreenArea
	call DiffSelGetIndex
	add a
	add a ; * DIFFSEL_STOP_SPACING
	ASSERT DIFFSEL_STOP_SPACING == 4
	add DIFFSEL_TRACK_X
	ld c, a
	ld b, 0
	hlcoord 0, 5
	add hl, bc
	ld [hl], '▼'
	ret

; Overwrite the interior of the text box PrintText left on screen, leaving its
; border intact (rows 13-16 all cleared so the prompt's second line can't
; survive; see ChoosePlayerCharacter.drawName).
DiffSelDrawDescription:
	hlcoord 1, 13
	lb bc, 4, 18
	call ClearScreenArea
	ld hl, DifficultySelectDescriptions
	call DiffSelPointerAtIndex
	ld d, h
	ld e, l
	hlcoord 1, 14
	jp PlaceString

DifficultySelectTitleText: db "DIFFICULTY@"
DifficultySelectTrackText: db "·───·───·───·───·@"
DifficultySelectEndsText:  db "V.EASY     V.HARD@"
DifficultySelectNoteText:
	db   "Can be changed at"
	next "any time in OPTION.@" ; columns 1-19

ChooseDifficultyText:
	text_far _ChooseDifficultyText
	text_end
