; Pokedex page 3: what this mon evolves into, and how.
;
; Lives in "Evos Moves" (bank $31) beside EvosMovesPointerTable, the form
; evolution blocks and the real evolution gate, so it walks the mon's OWN list
; (GetEvoListForMon) with plain in-bank reads and asks IsEvolutionTargetAllowed
; about each entry: a target the evolution engine would refuse this run (its
; species group or form locked or toggled off) is not listed. Same pattern as
; MistStoneChooseEvolution.
;
; Callers: ShowPokedexDataInternal (engine/menus/pokedex.asm, bank $10) and
; FormDexShowData (custom_functions/form_dex.asm, bank $27), each a bare farcall
; between drawing page 2 and their final wait. Only owned entries reach page 2,
; so only they reach this page.

DEF DEX_EVO_FIRST_ROW EQU 11 ; page 2's stat rows, under the divider
DEF DEX_EVO_ROWS      EQU 6  ; rows 11-16, three name/method pairs
DEF DEX_EVO_METHOD_OFFSET EQU SCREEN_WIDTH + 1 ; next row, column 2

; ---------------------------------------------------------------------------
; DexShowEvoPage
; IN:  nothing in registers. The page's identity is read the way its two
;      callers set it up: wRewardInfoSlot $80 | id = a Forms-list page
;      (DexFormKeyOf); 1-3 = a reward INFO preview (wRoguePokemon/Form 1-3);
;      0 = an ordinary species page for wCurPartySpecies, base form.
; OUT: page 3 drawn; the caller's own final A/B wait closes the screen.
; Clobbers everything. Preserves wPokedexNum (= wNamedObjectIndex, which
; GetMonName needs), wLoadedMon + MON_CATCH_RATE, wEvoStoneItemID and
; wEvoNewForm: the dex also opens mid-battle from the catch screen.
; ---------------------------------------------------------------------------
DexShowEvoPage::
	call DexEvoWaitForAB
	hlcoord 9, 4
	lb bc, 5, 10
	call ClearScreenArea ; TYPE/ and the types
	call DexEvoClearRows ; the stat bars and the preview's DVs
	ld c, 20
	call DelayFrames     ; page 2's own beat between wipe and redraw
	hlcoord 9, 4
	ld de, DexEvoHeaderText
	call PlaceString

	ld a, [wPokedexNum]
	push af
	ld a, [wLoadedMon + MON_CATCH_RATE]
	push af
	ld a, [wEvoStoneItemID]
	push af
	ld a, [wEvoNewForm]
	push af

	; d = species, e = form
	ld a, [wCurPartySpecies]
	ld d, a
	ld e, 0
	ld a, [wRewardInfoSlot]
	and a
	jr z, .gotMon
	bit 7, a
	jr nz, .formsList
	dec a
	ld c, a
	ld b, 0
	ld hl, wRoguePokemonForm1
	add hl, bc
	ld e, [hl]
	ld hl, wRoguePokemon1
	add hl, bc
	ld d, [hl]
	jr .gotMon
.formsList
	and $7f
	ld e, a
	farcall DexFormKeyOf ; d = species, e = form
.gotMon
	; IsEvoStoneFormAllowed reads the SOURCE form from here: a form carrying
	; its own form forward always passes, as it does when really evolving.
	ld a, e
	rrca
	rrca
	rrca                 ; 0-3 -> bits 5-6 (FORM_SHIFT)
	ld [wLoadedMon + MON_CATCH_RATE], a

	hlcoord 1, DEX_EVO_FIRST_ROW
	push hl              ; [sp] = where the next line goes
	call GetEvoListForMon
.nextEntry
	ld a, [hli]
	and a
	jr z, .done
	ld b, a
	call EvoEntryTakeForm ; b = plain type, wEvoNewForm
	xor a
	ld [wEvoStoneItemID], a
	ld a, b
	cp EVOLVE_ITEM
	jr nz, .levelOrTrade
	ld a, [hli]          ; the stone
	ld [wEvoStoneItemID], a
	ld c, a
	inc hl               ; minimum level, always 1 for a stone
	jr .gotMethod
.levelOrTrade
	ld a, [hli]          ; the level
	ld c, a
.gotMethod
	; b = type, c = level or stone, hl = target species
	push bc
	call IsEvolutionTargetAllowed ; preserves hl
	pop bc
	jr c, .allowed
	inc hl
	jr .nextEntry

.allowed
	ld a, [hli]          ; target species
	pop de               ; de = next line
	push hl              ; the list, past this entry
	push bc              ; the method
	push af              ; the target
	ld a, e
	cp LOW(wTileMap + (DEX_EVO_FIRST_ROW + DEX_EVO_ROWS) * SCREEN_WIDTH + 1)
	jr nz, .room
	ld a, d
	cp HIGH(wTileMap + (DEX_EVO_FIRST_ROW + DEX_EVO_ROWS) * SCREEN_WIDTH + 1)
	jr nz, .room
.pageFull ; test_dex_evo_page reads the full page here
	call DexEvoWaitForAB ; a full page: show the rest on a fresh one
	call DexEvoClearRows
	ld de, wTileMap + DEX_EVO_FIRST_ROW * SCREEN_WIDTH + 1
.room
	pop af
	push de              ; the line
	; Name the target as the form this entry makes: FORM entries through
	; wEvoNewForm, Eevee's stones through EvoStoneForms (Leaf Stone -> LEAFEON,
	; not FLAREON). The context is consumed by one lookup, so it is set per line.
	ld d, a
	ld c, a
	call GetEvolvedForm  ; a = form; de preserved
	ld [wFormContextForm], a
	ld a, d
	ld [wFormContextSpecies], a
	ld [wNamedObjectIndex], a
	call GetMonName      ; de = the name; hl preserved
	pop hl
	call PlaceString
	ld a, ':'
	ld [bc], a           ; PlaceString returns the next tile in bc
	pop bc               ; the method
	push hl
	ld de, DEX_EVO_METHOD_OFFSET
	add hl, de
	call DexEvoPrintMethod
	pop hl
	ld de, 2 * SCREEN_WIDTH
	add hl, de
	ld d, h
	ld e, l
	pop hl               ; the list
	push de              ; the next line
	jr .nextEntry

.done
	pop hl
	ld a, l
	cp LOW(wTileMap + DEX_EVO_FIRST_ROW * SCREEN_WIDTH + 1)
	jr nz, .listed
	ld a, h
	cp HIGH(wTileMap + DEX_EVO_FIRST_ROW * SCREEN_WIDTH + 1)
	jr nz, .listed
	; Nothing printed. The cursor only returns to the first row after a full
	; page when a line is about to go there, so this means no entry at all.
	ld de, DexEvoNoneText
	call PlaceString
.listed
	xor a
	ld [wFormContextSpecies], a
	pop af
	ld [wEvoNewForm], a
	pop af
	ld [wEvoStoneItemID], a
	pop af
	ld [wLoadedMon + MON_CATCH_RATE], a
	pop af
	ld [wPokedexNum], a
.restored ; test_dex_evo_page checks the saved state here
	ret

; The page-turn wait, as ShowPokedexDataInternal's .waitForButtonPress2.
DexEvoWaitForAB:
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	and PAD_A | PAD_B
	jr z, DexEvoWaitForAB
	ld a, SFX_PRESS_AB
	jp PlaySound

; Rows 10-16 inside the frame, under the divider.
DexEvoClearRows:
	hlcoord 1, 10
	lb bc, 7, 18
	jp ClearScreenArea

; IN: b = EVOLVE_LEVEL / _ITEM / _TRADE, c = level or stone, hl = tile.
; Method on its own line: "LV 36", "LV42/TR" (a level-up at 42 or any real
; trade), or the item name.
DexEvoPrintMethod:
	ld a, b
	cp EVOLVE_ITEM
	jr z, .stone
	ld [hl], 'L'
	inc hl
	ld [hl], 'V'
	inc hl
	cp EVOLVE_TRADE
	jr z, .noGap
	inc hl
.noGap
	push af
	ld a, c
	call DexEvoPrintDecimal
	pop af
	cp EVOLVE_TRADE
	ret nz
	ld de, DexEvoTradeText
	jp PlaceString
.stone
	ld a, c
	ld [wNamedObjectIndex], a
	call GetItemName
	jp PlaceString

; a = 0-255 at hl, no leading zeros; hl moves past it. Clobbers af, bc, de.
DexEvoPrintDecimal:
	ld e, 0              ; nonzero once a digit is printed
	ld c, 100
	call .digit
	ld c, 10
	call .digit
	add '0'
	ld [hli], a
	ret
.digit
	ld d, '0' - 1
.subtract
	inc d
	sub c
	jr nc, .subtract
	add c
	ld b, a              ; remainder
	ld a, d
	cp '0'
	jr nz, .put
	ld a, e
	and a
	jr z, .skip          ; a leading zero
	ld a, d
.put
	ld [hli], a
	ld e, 1
.skip
	ld a, b
	ret

DexEvoHeaderText:
	db "EVOLUTION@"
DexEvoNoneText:
	db "NO EVOLUTION@"
DexEvoTradeText:
	db "/TR@"
ASSERT BANK(DexShowEvoPage) == BANK(EvosMovesPointerTable), \
       "DexShowEvoPage walks the evolution lists with plain in-bank reads"
