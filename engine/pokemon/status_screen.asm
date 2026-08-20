DrawHP:
; Draws the HP bar in the stats screen
	call GetPredefRegisters
	ld a, $1
	jr DrawHP_

DrawHP2:
; Draws the HP bar in the party screen
	call GetPredefRegisters
	ld a, $2

DrawHP_:
	ld [wHPBarType], a
	push hl
	ld a, [wLoadedMonHP]
	ld b, a
	ld a, [wLoadedMonHP + 1]
	ld c, a
	or b
	jr nz, .nonzeroHP
	xor a
	ld c, a
	ld e, a
	ld a, $6
	ld d, a
	jp .drawHPBarAndPrintFraction
.nonzeroHP
	ld a, [wLoadedMonMaxHP]
	ld d, a
	ld a, [wLoadedMonMaxHP + 1]
	ld e, a
	predef HPBarLength
	ld a, $6
	ld d, a
	ld c, a
.drawHPBarAndPrintFraction
	pop hl
	push de
	push hl
	push hl
	call DrawHPBar
	pop hl
	ldh a, [hUILayoutFlags]
	bit BIT_PARTY_MENU_HP_BAR, a
	jr z, .printFractionBelowBar
	ld bc, $9 ; right of bar
	jr .printFraction
.printFractionBelowBar
	ld bc, SCREEN_WIDTH + 1 ; below bar
.printFraction
	add hl, bc
	ld de, wLoadedMonHP
	lb bc, 2, 3
	call PrintNumber
	ld a, '/'
	ld [hli], a
	ld de, wLoadedMonMaxHP
	lb bc, 2, 3
	call PrintNumber
	pop hl
	pop de
	ret

StatusScreen:
	call LoadMonData
	ld a, [wMonDataLocation]
	cp BOX_DATA
	jr c, .DontRecalculate
; mon is in a box or daycare
	ld a, [wLoadedMonBoxLevel]
	ld [wLoadedMonLevel], a
	ld [wCurEnemyLevel], a
	ld hl, wLoadedMonHPExp - 1
	ld de, wLoadedMonStats
	ld b, $1
	; Fusion (Phase 2): a BOXED fusion recalculates here for display (party
	; fusions skip this and show their stored, already-boosted stats). Without
	; this the status screen would show a boxed fusion's un-boosted stats.
	; wLoadedMon is a party_struct, so de = wLoadedMonStats works exactly like a
	; real MON_STATS pointer, and LoadMonData copied the mon's MON_CATCH_RATE
	; (incl. the fusion flag) into it. Display-only - it writes wLoadedMonStats,
	; not the stored box mon.
	push bc
	push hl
	farcall PrepareFusionCalcStats
	pop hl
	pop bc
	call CalcStats
.DontRecalculate
; Shin Red import Phase 8: if this is the active battler being viewed mid-
; battle (not a benched party mon), show its LIVE stage-modified stats instead
; of the unmodified party ones LoadMonData just copied in. wBattleMon's own
; Attack/Defense/Speed/Special fields already ARE the current modified values
; - CalculateModifiedStat (engine/battle/core.asm) writes stage-adjusted
; results there directly, matching vanilla. No interaction with the boxed-mon
; fusion CalcStats block just above: that branch only runs for BOX_DATA/
; DAYCARE_DATA, never PLAYER_PARTY_DATA, so a mon can't be both a live battler
; and reach it at the same time - this is a pure display overwrite, no
; CalcStats call involved.
	ldh a, [hIsInBattle]
	and a
	jr z, .notActiveBattler
	ld a, [wMonDataLocation]
	and a ; PLAYER_PARTY_DATA
	jr nz, .notActiveBattler
	ldh a, [hWhichPokemon]
	ld b, a
	ld a, [wPlayerMonNumber]
	cp b
	jr nz, .notActiveBattler
	ld hl, wBattleMonAttack
	ld de, wLoadedMonAttack
	ld bc, 8 ; 4 words: Attack, Defense, Speed, Special
	call CopyData
.notActiveBattler
	ld hl, wStatusFlags2
	set BIT_NO_AUDIO_FADE_OUT, [hl]
	ld a, $33
	ldh [rAUDVOL], a ; Reduce the volume
	call GBPalWhiteOutWithDelay3
	call ClearScreen
	call UpdateSprites
	call LoadHpBarAndStatusTilePatterns
	ld de, BattleHudTiles1  ; source
	ld hl, vChars2 tile $6d ; dest
	lb bc, BANK(BattleHudTiles1), 3
	call CopyVideoDataDouble ; ·│ :L and halfarrow line end
	ld de, BattleHudTiles2
	ld hl, vChars2 tile $78
	lb bc, BANK(BattleHudTiles2), 1
	call CopyVideoDataDouble ; │
	ld de, BattleHudTiles3
	ld hl, vChars2 tile $76
	lb bc, BANK(BattleHudTiles3), 2
	call CopyVideoDataDouble ; ─ ┘
	ld de, PTile
	ld hl, vChars2 tile $72
	lb bc, BANK(PTile), 1
	call CopyVideoDataDouble ; bold P (for PP)
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a
	hlcoord 19, 1
	lb bc, 6, 10
	call DrawLineBox ; Draws the box around name, HP and status
	ld de, -6
	add hl, de
	ld [hl], '<DOT>'
	dec hl
	ld [hl], '№'
	hlcoord 19, 9
	lb bc, 8, 6
	call DrawLineBox ; Draws the box around types, ID No. and OT
	hlcoord 10, 9
	ld de, TypesIDNoOTText
	call PlaceString
	hlcoord 11, 3
	predef DrawHP
	ld hl, wStatusScreenHPBarColor
	call GetHealthBarColor
	ld b, SET_PAL_STATUS_SCREEN
	call RunPaletteCommand
	hlcoord 16, 6
	ld de, wLoadedMonStatus
	call PrintStatusCondition
	jr nz, .StatusWritten
	hlcoord 16, 6
	ld de, OKText
	call PlaceString ; "OK"
.StatusWritten
	hlcoord 9, 6
	ld de, StatusText
	call PlaceString ; "STATUS/"
	hlcoord 14, 2
	call PrintLevel
	ld a, [wMonHIndex]
	ld [wPokedexNum], a
	ld [wCurSpecies], a
	predef IndexToPokedex
	hlcoord 3, 7
	ld de, wPokedexNum
	lb bc, LEADING_ZEROES | 1, 3
	call PrintNumber ; Pokémon no.
	hlcoord 11, 10
	predef PrintMonType
	ld hl, NamePointers2
	call .GetStringPointer
	ld d, h
	ld e, l
	hlcoord 9, 1
	call PlaceString ; Pokémon name
	ld hl, OTPointers
	call .GetStringPointer
	ld d, h
	ld e, l
	hlcoord 12, 16
	call PlaceString ; OT
	hlcoord 12, 14
	ld de, wLoadedMonOTID
	lb bc, LEADING_ZEROES | 2, 5
	call PrintNumber ; ID Number
	call .StatsBoxModeFromJoypad ; hold SELECT/START as the screen opens
	ld d, STATUS_SCREEN_STATS_BOX
	call PrintStatsBox
	call Delay3
	call GBPalNormal
	; Fusion (Phase 4a): pre-load the secondary's front sprite into vBackPic
	; BEFORE drawing the primary, so the diagonal overlay after it is instant
	; (no visible "primary first, then secondary" flicker) and wMonHIndex is left
	; on the PRIMARY for StatusScreen2's page-2 name. de = wLoadedMon is
	; IsFusionMon's input (de, NOT hl - farcall clobbers hl as its jump vector).
	ld de, wLoadedMon
	farcall IsFusionMon
	jr z, .notFusionPreload
	farcall PreloadFusionSecondaryPic
.notFusionPreload
	hlcoord 1, 0
	call LoadFlippedFrontSpriteByMonIndex ; draw Pokémon picture
	; Fusion: overlay the secondary as the lower-right diagonal triangle.
	ld de, wLoadedMon
	farcall IsFusionMon
	jr z, .notFusionOverlay
	farcall OverlayFusionSecondaryPic
.notFusionOverlay
	ld a, [wCurPartySpecies]
	call PlayCry
; Shin Red import Phase 8: View Stat EXP (hold SELECT) / View DVs (hold START).
; The box was already drawn for whatever was held on entry, above. This also
; lets the view be switched without leaving: WaitForTextScrollButtonPress only
; exits on A/B, so SELECT/START can be held right through it, and if one of them
; is still down when it returns, redraw the box and keep waiting instead of
; leaving. Only the box is redrawn - picture, name and HP bar are untouched.
.waitOrPeek
	call WaitForTextScrollButtonPress
	ldh a, [hJoyHeld]
	and PAD_SELECT | PAD_START
	jr z, .done ; plain A/B: leave, as before
	call .StatsBoxModeFromJoypad
	ld d, STATUS_SCREEN_STATS_BOX
	call PrintStatsBox
	jr .waitOrPeek
.done
	pop af
	ldh [hTileAnimations], a
	ret

; Turns the currently held SELECT/START into a PrintStatsBox content mode in e.
; SELECT wins over START if somehow both are down.
.StatsBoxModeFromJoypad
	call Joypad
	ldh a, [hJoyHeld]
	ld e, STATS_BOX_STAT_EXP
	bit B_PAD_SELECT, a
	ret nz
	ld e, STATS_BOX_DVS
	bit B_PAD_START, a
	ret nz
	ld e, STATS_BOX_NORMAL
	ret

.GetStringPointer
	ld a, [wMonDataLocation]
	add a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, [wMonDataLocation]
	cp DAYCARE_DATA
	ret z
    cp DAYCARE_DATA2
	ret z
	ldh a, [hWhichPokemon]
	jp SkipFixedLengthTextEntries

OTPointers:
	dw wPartyMonOT
	dw wEnemyMonOT
	dw wBoxMonOT
	dw wDayCareMonOT
    dw wDayCareMonOT2

NamePointers2:
	dw wPartyMonNicks
	dw wEnemyMonNicks
	dw wBoxMonNicks
	dw wDayCareMonName
    dw wDayCareMonName2

TypesIDNoOTText:
	db   "TYPE1/"
	next "TYPE2/"
	next "<ID>№/"
	next "OT/"
	next "@"

StatusText:
	db "STATUS/@"

OKText:
	db "OK@"

; Draws a line starting from hl high b and wide c
DrawLineBox:
	ld de, SCREEN_WIDTH ; New line
.PrintVerticalLine
	ld [hl], $78 ; │
	add hl, de
	dec b
	jr nz, .PrintVerticalLine
	ld [hl], $77 ; ┘
	dec hl
.PrintHorizLine
	ld [hl], $76 ; ─
	dec hl
	dec c
	jr nz, .PrintHorizLine
	ld [hl], $6f ; ← (halfarrow ending)
	ret

PTile: INCBIN "gfx/font/P.1bpp"

; d = STATUS_SCREEN_STATS_BOX or LEVEL_UP_STATS_BOX (box position/size).
; e = STATS_BOX_* content, ONLY consulted when d == STATUS_SCREEN_STATS_BOX; the
; battle/level-up box always shows the normal stats and never sets it.
PrintStatsBox:
	ld a, d
	ASSERT STATUS_SCREEN_STATS_BOX == 0
	and a
	jr nz, .LevelUpStatsBox ; battle or Rare Candy
	push de ; e is the content mode and TextBoxBorder clobbers de (ld de, SCREEN_WIDTH)
	hlcoord 0, 8
	ld b, 8
	ld c, 8
	call TextBoxBorder ; also blanks the interior, so a previous mode's text is gone
	pop de
	ld a, e
	and a ; STATS_BOX_NORMAL
	jr nz, .AlternateView
	hlcoord 1, 9
	ld bc, SCREEN_WIDTH + 5 ; one row down and 5 columns right
	jr .PrintStats
.LevelUpStatsBox
	hlcoord 9, 2
	ld b, 8
	ld c, 9
	call TextBoxBorder
	hlcoord 11, 3
	ld bc, SCREEN_WIDTH + 4 ; one row down and 4 columns right
.PrintStats
	push bc
	push hl
	ld de, .StatsText
	call PlaceString
	pop hl
	pop bc
	add hl, bc
	ld de, wLoadedMonAttack
	lb bc, 2, 3
	call .PrintStat
	ld de, wLoadedMonDefense
	call .PrintStat
	ld de, wLoadedMonSpeed
	call .PrintStat
	ld de, wLoadedMonSpecial
	jp PrintNumber

; Stat exp needs a 5-digit field, which does not fit to the right of
; ATTACK/DEFENSE/SPEED/SPECIAL inside this 8-wide box, so both alternate views
; relabel with 3-letter names and start their numbers further left.
.AlternateView
	push de
	hlcoord 1, 9
	ld de, .ShortStatsText
	call PlaceString
	pop de
	ld a, e
	dec a ; STATS_BOX_STAT_EXP?
	jr nz, .PrintDVs
; Shows what the stat exp is WORTH, not the raw 0-65535 counter, which is an
; opaque number to read on a status screen. _CalcStat adds ceil(sqrt(stat exp))
; / 4 to (Base + DV) * 2 before the level multiply, so at level 100 the value
; printed here is very nearly the literal number of stat points training has
; bought - and it has a legible ceiling of +63 rather than 65535.
; The four Exp fields are contiguous (see MON_*_EXP in
; constants/pokemon_data_constants.asm), so .StatExpBonus walks de forward
; through them and only the first needs loading. HP's stat exp is skipped here
; exactly as it was before - this box has no HP row.
	hlcoord 1, 9
	ld bc, SCREEN_WIDTH + 3 ; "NN/63" from column 4 ends on the last interior column
	add hl, bc
	ld de, wLoadedMonAttackExp
	call .StatExpBonus
	call .PrintStatExpBonus
	call .StatExpBonus
	call .PrintStatExpBonus
	call .StatExpBonus
	call .PrintStatExpBonus
	call .StatExpBonus
	jp .PrintStatExpBonus

; INPUT:  de = a 2-byte big-endian stat exp field, hl = the screen cursor
; OUTPUT: a = the stat bonus that stat exp is worth (0-63), de advanced past
;         the field, hl untouched
; CLOBBERS: b
; Mirrors _CalcStat's ceil(sqrt(stat exp)) / 4, including its 255 clamp, but
; computes the root by subtracting successive odd numbers (n^2 = 1+3+..+(2n-1))
; instead of calling Multiply. That keeps it off HRAM entirely, which matters on
; this screen: staging a value in HRAM for PrintNumber does not work here, see
; the .PrintDV comment below.
.StatExpBonus:
	push hl ; screen cursor - the root is computed in hl
	ld a, [de]
	ld h, a
	inc de
	ld a, [de]
	ld l, a
	inc de ; hl = stat exp, de = past the field
	push de
	ld b, 0 ; b = the root so far
	ld de, 1 ; de = the next odd number to subtract, i.e. 2b + 1
.sqrtLoop
	ld a, h
	or l
	jr z, .sqrtDone ; landed exactly on a perfect square
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a
	inc b
	jr c, .sqrtDone ; went past 0, so b is already the ceiling
	ld a, b
	cp $ff
	jr z, .sqrtDone ; the same clamp _CalcStat's own loop applies
	inc de
	inc de
	jr .sqrtLoop
.sqrtDone
	pop de
	pop hl
	ld a, b
	srl a
	srl a ; / 4, matching _CalcStat
	ret

; a = a stat bonus (0-63). Writes "NN/63" across 5 tiles at hl, then steps hl
; down two rows exactly like .PrintStat, preserving de. Spelling out the "/63"
; denominator is the whole point of this view: on its own a bare "40" is just
; another opaque number, but against its own ceiling it reads as a progress
; figure. The five tiles are exactly the width freed by dropping the old raw
; 5-digit stat exp counter.
; Hand-written for the same reason as .PrintDV below: PrintNumber reads its
; operand from memory and zeroes hPastLeadingZeros on the way in.
.PrintStatExpBonus:
	push de
	push hl
	ld b, '0'
.bonusTensLoop
	cp 10
	jr c, .bonusGotTens
	sub 10
	inc b
	jr .bonusTensLoop
.bonusGotTens
	ld c, a
	ld a, b
	cp '0'
	jr nz, .bonusWriteTens
	ld a, ' ' ; blank a leading zero rather than printing "05/63"
.bonusWriteTens
	ld [hli], a
	ld a, c
	add '0'
	ld [hli], a
	ld a, '/'
	ld [hli], a
	ld a, '6'
	ld [hli], a
	ld a, '3'
	ld [hl], a
	pop hl
	ld de, SCREEN_WIDTH * 2
	add hl, de
	pop de
	ret

; DVs are packed nibbles at wLoadedMonDVs, the same layout _CalcStat unpacks in
; calc_stats.asm: byte 0 = Atk<<4|Def, byte 1 = Spd<<4|Spc.
.PrintDVs
	hlcoord 1, 9
	ld bc, SCREEN_WIDTH + 6 ; 2 digits from column 7 end on the last interior column
	add hl, bc
	ld a, [wLoadedMonDVs]
	swap a
	call .PrintDV
	ld a, [wLoadedMonDVs]
	call .PrintDV
	ld a, [wLoadedMonDVs + 1]
	swap a
	call .PrintDV
	ld a, [wLoadedMonDVs + 1]
	; fallthrough

; a = a DV in its low nibble (0-15). Writes it right-aligned across 2 tiles at
; hl, then steps hl down two rows exactly like .PrintStat.
; Deliberately NOT routed through PrintNumber: that takes its operand from
; memory, and its first act is to zero hPastLeadingZeros - which is the SAME
; HRAM byte as hSwapTemp ($ff95), so staging a nibble there for it silently
; prints 0 every time.
.PrintDV:
	and $f
	push hl
	ld b, ' '
	cp 10
	jr c, .dvNoTensDigit
	sub 10
	ld b, '1'
.dvNoTensDigit
	add '0'
	ld c, a
	ld a, b
	ld [hli], a
	ld [hl], c
	pop hl
	ld de, SCREEN_WIDTH * 2
	add hl, de
	ret

.PrintStat:
	push hl
	call PrintNumber
	pop hl
	ld de, SCREEN_WIDTH * 2
	add hl, de
	ret

.StatsText:
	db   "ATTACK"
	next "DEFENSE"
	next "SPEED"
	next "SPECIAL@"

.ShortStatsText:
	db   "ATK"
	next "DEF"
	next "SPD"
	next "SPC@"

StatusScreen2:
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a
	ldh [hAutoBGTransferEnabled], a
	ld bc, NUM_MOVES + 1
	ld hl, wMoves
	call FillMemory
	ld hl, wLoadedMonMoves
	ld de, wMoves
	ld bc, NUM_MOVES
	call CopyData
	callfar FormatMovesString
	hlcoord 9, 2
	lb bc, 5, 10
	call ClearScreenArea ; Clear under name
	hlcoord 19, 3
	ld [hl], $78
	hlcoord 0, 8
	ld b, 8
	ld c, 18
	call TextBoxBorder ; Draw move container
	hlcoord 2, 9
	ld de, wMovesString
	call PlaceString ; Print moves
	ld a, [wNumMovesMinusOne]
	inc a
	ld c, a ; number of known moves
	ld a, NUM_MOVES
	sub c
	ld b, a ; number of blank moves
	hlcoord 11, 10
	ld de, SCREEN_WIDTH * 2
	ld a, '<BOLD_P>'
	call StatusScreen_PrintPP ; Print "PP"
	ld a, b
	and a
	jr z, .InitPP
	ld c, a
	ld a, '-'
	call StatusScreen_PrintPP ; Fill the rest with --
.InitPP
	ld hl, wLoadedMonMoves
	decoord 14, 10
	ld b, 0
.PrintPP
	ld a, [hli]
	and a
	jr z, .PPDone
	push bc
	push hl
	push de
	ld hl, hCurrentMenuItem
	ld a, [hl]
	push af
	ld a, b
	ld [hl], a
	push hl
	callfar GetMaxPP
	pop hl
	pop af
	ld [hl], a
	pop de
	pop hl
	push hl
	ld bc, MON_PP - MON_MOVES - 1
	add hl, bc
	ld a, [hl]
	and PP_MASK
	ld [wStatusScreenCurrentPP], a
	ld h, d
	ld l, e
	push hl
	ld de, wStatusScreenCurrentPP
	lb bc, 1, 2
	call PrintNumber
	ld a, '/'
	ld [hli], a
	ld de, wMaxPP
	lb bc, 1, 2
	call PrintNumber
	pop hl
	ld de, SCREEN_WIDTH * 2
	add hl, de
	ld d, h
	ld e, l
	pop hl
	pop bc
	inc b
	ld a, b
	cp NUM_MOVES
	jr nz, .PrintPP
.PPDone
	hlcoord 9, 3
	ld de, StatusScreenExpText
	call PlaceString
	ld a, [wLoadedMonLevel]
	push af
	cp MAX_LEVEL
	jr z, .Level100
	inc a
	ld [wLoadedMonLevel], a ; Increase temporarily if not 100
.Level100
	hlcoord 14, 6
	ld [hl], '<to>'
	inc hl
	inc hl
	call PrintLevel
	pop af
	ld [wLoadedMonLevel], a
	ld de, wLoadedMonExp
	hlcoord 12, 4
	lb bc, 3, 7
	call PrintNumber ; exp
	call CalcExpToLevelUp
	ld de, wLoadedMonExp
	hlcoord 7, 6
	lb bc, 3, 7
	call PrintNumber ; exp needed to level up

	; unneeded, this clears the diacritic characters in JPN versions
	hlcoord 9, 0
	call StatusScreen_ClearName

	hlcoord 9, 1
	call StatusScreen_ClearName
	ld a, [wMonHIndex]
	ld [wNamedObjectIndex], a
	call GetMonName
	hlcoord 9, 1
	call PlaceString
	ld a, $1
	ldh [hAutoBGTransferEnabled], a
	call Delay3
	call WaitForTextScrollButtonPress
	pop af
	ldh [hTileAnimations], a
	ld hl, wStatusFlags2
	res BIT_NO_AUDIO_FADE_OUT, [hl]
	ld a, $77
	ldh [rAUDVOL], a
	call GBPalWhiteOut
	jp ClearScreen

CalcExpToLevelUp:
	ld a, [wLoadedMonLevel]
	cp MAX_LEVEL
	jr z, .atMaxLevel
	inc a
	ld d, a
	callfar CalcExperience
	ld hl, wLoadedMonExp + 2
	ldh a, [hExperience + 2]
	sub [hl]
	ld [hld], a
	ldh a, [hExperience + 1]
	sbc [hl]
	ld [hld], a
	ldh a, [hExperience]
	sbc [hl]
	ld [hld], a
	ret
.atMaxLevel
	ld hl, wLoadedMonExp
	xor a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ret

StatusScreenExpText:
	db   "EXP POINTS"
	next "LEVEL UP@"

StatusScreen_ClearName:
	ld bc, NAME_LENGTH - 1
	ld a, ' '
	jp FillMemory

StatusScreen_PrintPP:
; print PP or -- c times, going down two rows each time
	ld [hli], a
	ld [hld], a
	add hl, de
	dec c
	jr nz, StatusScreen_PrintPP
	ret
