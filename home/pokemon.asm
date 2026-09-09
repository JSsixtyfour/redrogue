DrawHPBar::
; Draw an HP bar d tiles long, and fill it to e pixels.
; If c is nonzero, show at least a sliver regardless.
; The right end of the bar changes with [wHPBarType].

	push hl
	push de
	push bc

	; Left
	ld a, $71 ; "HP:"
	ld [hli], a
	ld a, $62
	ld [hli], a

	push hl

	; Middle
	ld a, $63 ; empty
.draw
	ld [hli], a
	dec d
	jr nz, .draw

	; Right
	ld a, [wHPBarType]
	dec a
	ld a, $6d ; status screen and battle
	jr z, .ok
	dec a ; pokemon menu
.ok
	ld [hl], a

	pop hl

	ld a, e
	and a
	jr nz, .fill

	; If c is nonzero, draw a pixel anyway.
	ld a, c
	and a
	jr z, .done
	ld e, 1

.fill
	ld a, e
	sub 8
	jr c, .partial
	ld e, a
	ld a, $6b ; full
	ld [hli], a
	ld a, e
	and a
	jr z, .done
	jr .fill

.partial
	; Fill remaining pixels at the end if necessary.
	ld a, $63 ; empty
	add e
	ld [hl], a
.done
	pop bc
	pop de
	pop hl
	ret


; loads pokemon data from one of multiple sources to wLoadedMon
; loads base stats to wMonHeader
; INPUT:
; [hWhichPokemon] = index of pokemon within party/box
; [wMonDataLocation] = source
; 00: player's party
; 01: enemy's party
; 02: current box
; 03: daycare
; OUTPUT:
; [wCurPartySpecies] = pokemon ID
; wLoadedMon = base address of pokemon data
; wMonHeader = base address of base stats
LoadMonData::
	jpfar LoadMonData_

OverwritewMoves::
; Write c to [wMoves + b]. Unused.
	ld hl, wMoves
	ld e, b
	ld d, 0
	add hl, de
	ld a, c
	ld [hl], a
	ret

LoadFlippedFrontSpriteByMonIndex::
	ld a, 1
	ld [wSpriteFlipped], a

LoadFrontSpriteByMonIndex::
	push hl
	ld a, [wPokedexNum]
	push af
	ld a, [wCurPartySpecies]
	ld [wPokedexNum], a
	predef IndexToPokedex
	ld hl, wPokedexNum
	ld a, [hl]
	pop bc
	ld [hl], b
	and a
	pop hl
	jr z, .invalidDexNumber ; dex #0 invalid
	cp NUM_POKEMON + 1
	jr c, .validDexNumber   ; dex >#151 invalid
.invalidDexNumber
	; This is the so-called "Rhydon trap" or "Rhydon glitch"
	; to fail-safe invalid dex numbers
	; (see https://glitchcity.wiki/wiki/Rhydon_trap
	; or https://bulbapedia.bulbagarden.net/wiki/Rhydon_glitch)
	ld a, RHYDON
	ld [wCurPartySpecies], a
	ret
.validDexNumber
	push hl
	ld de, vFrontPic
	call LoadMonFrontSprite
	pop hl
	ldh a, [hLoadedROMBank]
	push af
	ld a, BANK(CopyUncompressedPicToHL)
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	xor a
	ldh [hStartTileID], a
	call CopyUncompressedPicToHL
	xor a
	ld [wSpriteFlipped], a
	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ret


PlayCry::
; Play monster a's cry.
	call GetCryData
	call PlaySound
	jp WaitForSoundToFinish

GetCryData::
; Load cry data for monster a.
	dec a
	ld c, a
	ld b, 0
	ld hl, CryData
	add hl, bc
	add hl, bc
	add hl, bc

	ld a, BANK(CryData)
	call BankswitchHome
	ld a, [hli]
	ld b, a ; cry id
	ld a, [hli]
	ld [wFrequencyModifier], a
	ld a, [hl]
	ld [wTempoModifier], a
	call BankswitchBack

	; Cry headers have 3 channels,
	; and start from index CRY_SFX_START,
	; so add 3 times the cry id.
	ld a, b
	ld c, CRY_SFX_START
	rlca ; * 2
	add b
	add c
	ret

DisplayPartyMenu::
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a
	call GBPalWhiteOutWithDelay3
	call ClearSprites
	call PartyMenuInit
	call DrawPartyMenu
	jp HandlePartyMenuInput

GoBackToPartyMenu::
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a
	call PartyMenuInit
	call RedrawPartyMenu
	jp HandlePartyMenuInput

PartyMenuInit::
	ld a, 1 ; hardcoded bank
	call BankswitchHome
	call LoadHpBarAndStatusTilePatterns
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	xor a ; PLAYER_PARTY_DATA
	ld [wMonDataLocation], a
	ld [wMenuWatchMovingOutOfBounds], a
	ld hl, wTopMenuItemY
	inc a
	ld [hli], a ; top menu item Y
	xor a
	ld [hli], a ; top menu item X
	ld a, [wPartyAndBillsPCSavedMenuItem]
	push af
	ldh [hCurrentMenuItem], a ; current menu item ID
	inc hl ; wTileBehindCursor
	ld a, [wPartyCount]
	and a ; are there more than 0 pokemon in the party?
	jr z, .storeMaxMenuItemID
	dec a
; if party is not empty, the max menu item ID is ([wPartyCount] - 1)
; otherwise, it is 0
.storeMaxMenuItemID
	ld [hli], a ; max menu item ID
	ld a, [wForcePlayerToChooseMon]
	and a
	ld a, PAD_A | PAD_B
	jr z, .next
	xor a
	ld [wForcePlayerToChooseMon], a
	inc a ; a = PAD_A
.next
	ld [hli], a ; menu watched keys
	pop af
	ld [hl], a ; old menu item ID
	ret

HandlePartyMenuInput::
	ld a, 1
	ld [wMenuWrappingEnabled], a
	ld a, $40
	ld [wPartyMenuAnimMonEnabled], a
	call HandleMenuInput_
	call PlaceUnfilledArrowMenuCursor
	ld b, a
	xor a
	ld [wPartyMenuAnimMonEnabled], a
	ldh a, [hCurrentMenuItem]
	ld [wPartyAndBillsPCSavedMenuItem], a
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ld a, [wMenuItemToSwap]
	and a
	jp nz, .swappingPokemon
	pop af
	ldh [hTileAnimations], a
	bit B_PAD_B, b
	jr nz, .noPokemonChosen
	ld a, [wPartyCount]
	and a
	jr z, .noPokemonChosen
	ldh a, [hCurrentMenuItem]
	ldh [hWhichPokemon], a
	ld hl, wPartySpecies
	ld b, 0
	ld c, a
	add hl, bc
	ld a, [hl]
	ld [wCurPartySpecies], a
	ld [wBattleMonSpecies2], a
	call BankswitchBack
	and a
	ret
.noPokemonChosen
	call BankswitchBack
	scf
	ret
.swappingPokemon
	bit B_PAD_B, b
	jr z, .handleSwap ; if not, handle swapping the pokemon
.cancelSwap ; if the B button was pressed
	farcall ErasePartyMenuCursors
	xor a
	ld [wMenuItemToSwap], a
	ld [wPartyMenuTypeOrMessageID], a
	call RedrawPartyMenu
	jr HandlePartyMenuInput
.handleSwap
	ldh a, [hCurrentMenuItem]
	ldh [hWhichPokemon], a
	farcall SwitchPartyMon
	jr HandlePartyMenuInput

DrawPartyMenu::
	ld hl, DrawPartyMenu_
	jr DrawPartyMenuCommon

RedrawPartyMenu::
	ld hl, RedrawPartyMenu_

DrawPartyMenuCommon::
	ld b, BANK(RedrawPartyMenu_)
	jp Bankswitch

; prints a pokemon's status condition
; INPUT:
; de = address of status condition
; hl = destination address
PrintStatusCondition::
	push de
	dec de
	dec de ; de = address of current HP
	ld a, [de]
	ld b, a
	dec de
	ld a, [de]
	or b ; is the pokemon's HP zero?
	pop de
	jr nz, PrintStatusConditionNotFainted
; if the pokemon's HP is 0, print "FNT"
	ld_hli_a_string "FNT"
	and a
	ret

PrintStatusConditionNotFainted::
	homecall_sf PrintStatusAilment
	ret

; function to print pokemon level, leaving off the ":L" if the level is at least 100
; INPUT:
; hl = destination address
; [wLoadedMonLevel] = level
PrintLevel::
	ld a, '<LV>' ; ":L" tile ID
	ld [hli], a
	ld c, 2 ; number of digits
	ld a, [wLoadedMonLevel] ; level
	cp 100
	jr c, PrintLevelCommon
; if level at least 100, write over the ":L" tile
	dec hl
	inc c ; increment number of digits to 3
	jr PrintLevelCommon

; prints the level without leaving off ":L" regardless of level
; INPUT:
; hl = destination address
; [wLoadedMonLevel] = level
PrintLevelFull::
	ld a, '<LV>' ; ":L" tile ID
	ld [hli], a
	ld c, 3 ; number of digits
	ld a, [wLoadedMonLevel] ; level

PrintLevelCommon::
	ld [wTempByteValue], a
	ld de, wTempByteValue
	ld b, LEFT_ALIGN | 1 ; 1 byte
	jp PrintNumber

GetwMoves::
; Unused. Returns the move at index a from wMoves in a
	ld hl, wMoves
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	ret

; ---------------------------------------------------------------------------
; PublishFormContext  (Species Groups Phase 2R)
;
; Publishes a mon's form so that the GetMonHeader call which FOLLOWS applies
; that mon's form rather than the base species' row.
;
; INPUT:  hl = the mon's struct base (party / box / wBattleMon / wEnemyMon)
;         wCurSpecies = that mon's species, already set by the caller
; OUTPUT: wFormContextSpecies / wFormContextForm published
; PRESERVES: hl, bc, de.  CLOBBERS: af only.
;   de is preserved deliberately rather than documented as clobbered. Several
;   call sites hold a live struct pointer and item_effects.asm carries an
;   explicit warning about de as scratch around one; auditing de liveness at
;   every site is exactly how this project's recurring register-contract bugs
;   happen. Two bytes of HOME removes the whole question.
;
; Call this immediately before `call GetMonHeader`, at any site that loads a
; SPECIFIC mon's header without going through LoadMonData_ (which publishes for
; itself). Sites that merely RELOAD the header they already hold do not need it -
; ApplyFormOverride recognises a refresh on its own; see func_forms.asm.
;
; Publishing unconditionally, form 0 included, is the point: ApplyFormOverride
; consumes the context, so a formless mon actively clears whatever the previous
; mon published instead of inheriting it.
;
; Lives in HOME so every bank can plain-call it. 22 bytes here buys 3 bytes per
; call site, which is the right trade with HOME this tight.
PublishFormContext::
	push hl
	push de
	ld de, MON_CATCH_RATE
	add hl, de
	ld a, [hl]
	and FORM_MASK
	rlca                  ; bits 5-6 -> bits 0-1
	rlca
	rlca
	ld [wFormContextForm], a
	ld a, [wCurSpecies]
	ld [wFormContextSpecies], a
	pop de
	pop hl
	ret

; copies the base stat data of a pokemon to wMonHeader
; INPUT:
; [wCurSpecies] = pokemon ID
GetMonHeader::
	ldh a, [hLoadedROMBank]
	push af
	ld a, BANK(BaseStats)
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	push bc
	push de
	push hl
	ld a, [wPokedexNum]
	push af
	ld a, [wCurSpecies]
	ld [wPokedexNum], a
	; All three pseudo-mons (FOSSIL_KABUTOPS, FOSSIL_AERODACTYL, MON_GHOST) were
	; retired 2026-09-03 and their index slots reclaimed as real species, so the
	; `.specialID` branch that used to sit here is gone with them. Phase 2R's
	; regional-form override reintroduces the same idea - patch wMonHeader after
	; the base-stat copy with an overriding sprite pointer, dimension and typing -
	; but keyed on the form bits in MON_CATCH_RATE rather than on a species id.
	;
	; Mew's `cp MEW / jr z, .mew` special case is GONE (Species Groups Phase 2).
	; Vanilla kept Mew's 28-byte row outside BaseStats, in bank $01 next to its
	; pics, which left a HOLE at dex 151 in a table indexed flatly as
	; (dex - 1) * BASE_DATA_SIZE. That was invisible while Mew was the LAST dex
	; number, but it silently shifted every species added after it by one row -
	; dex 152 read dex 153's stats, and the final species read off the end of the
	; table entirely. Mew now sits in BaseStats at its own dex position, so the
	; table is dense from 1 to NUM_POKEMON and this lookup needs no exceptions.
	; See the alignment asserts in data/pokemon/base_stats.asm.
	predef IndexToPokedex
	ld a, [wPokedexNum]
	dec a
	ld bc, BASE_DATA_SIZE
	ld hl, BaseStats
	call AddNTimes
	ld de, wMonHeader
	ld bc, BASE_DATA_SIZE
	call CopyData
	; Species Groups Phase 2R: if a form context is pending for this species,
	; overwrite the row just copied with that form's own 28-byte row. Costs
	; three bytes of ROM0 (HOME has ~113 free); the table walk and the copy all
	; live in bank $30. Returns with wMonHForm = the form applied, or 0.
	;
	; Placed AFTER the base copy and BEFORE the wMonHIndex write on purpose: the
	; form row overwrites byte 0 (BASE_DEX_NO) along with everything else, and
	; the write below then puts the species index back where the rest of the
	; engine expects it, exactly as it does for an ordinary species.
	;
	; Clobbering af/bc/de/hl here is safe - all three pairs were pushed at entry
	; and `a` is reloaded on the very next line.
	ASSERT BANK(ApplyFormOverride) == BANK(BaseStats), \
	       "Species Forms must be pinned to BANK(BaseStats) - see layout.link"
	call ApplyFormOverride
	ld a, [wCurSpecies]
	ld [wMonHIndex], a
	pop af
	ld [wPokedexNum], a
	pop hl
	pop de
	pop bc
	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ret

; copy party pokemon's name to wNameBuffer
GetPartyMonName2::
	ldh a, [hWhichPokemon] ; index within party
	ld hl, wPartyMonNicks

; this is called more often
GetPartyMonName::
	push hl
	push bc
	call SkipFixedLengthTextEntries ; add NAME_LENGTH to hl, a times
	ld de, wNameBuffer
	push de
	ld bc, NAME_LENGTH
	call CopyData
	pop de
	pop bc
	pop hl
	ret
