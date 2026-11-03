; Softboiled is the sole party field move. Keep its renderer and handler
; together outside the nearly-full bank1 and Battle Engine 1 sections.
SECTION "Softboiled Field Menu", ROMX, BANK[$26]

DisplaySoftboiledMonMenu::
	xor a
	ld hl, wFieldMoves
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a ; wNumFieldMoves
	ld [hl], 12 ; wFieldMovesLeftmostXCoord
	ldh a, [hWhichPokemon]
	ld hl, wPartyMon1Moves
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld b, NUM_MOVES
.scanMoves
	ld a, [hli]
	cp SOFTBOILED
	jr z, .softboiled
	dec b
	jr nz, .scanMoves

	hlcoord 11, 11
	lb bc, 5, 7
	call TextBoxBorder
	call UpdateSprites
	ld a, 12
	ldh [hFieldMoveMonMenuTopMenuItemX], a
	hlcoord 13, 12
	ld de, PokemonMenuEntries
	jp PlaceString

.softboiled
	ld a, 9 ; original Softboiled field-move index
	ld [wFieldMoves], a
	ld a, 1
	ld [wNumFieldMoves], a
	ld a, 8
	ld [wFieldMovesLeftmostXCoord], a
	ldh [hFieldMoveMonMenuTopMenuItemX], a
	hlcoord 7, 8
	lb bc, 8, 11
	call TextBoxBorder
	call UpdateSprites
	hlcoord 9, 10
	ld de, .softboiledEntry
	call PlaceString
	hlcoord 9, 12
	ld de, PokemonMenuEntries
	jp PlaceString
.softboiledEntry
	db "SOFTBOILED@"

PokemonMenuEntries:
	db   "STATS"
	next "SWITCH"
	next "CANCEL@"

; Original party-menu Softboiled lifecycle: require strictly more than
; one fifth of the donor's max HP, then use the existing pseudo-Potion path.
UseSoftboiledFieldMove::
	ld hl, wPartyMon1MaxHP
	ldh a, [hWhichPokemon]
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld a, [hli]
	ldh [hDividend], a
	ld a, [hl]
	ldh [hDividend + 1], a
	ld a, 5
	ldh [hDivisor], a
	ld b, 2
	call Divide
	ld bc, MON_HP - MON_MAXHP
	add hl, bc
	ld a, [hld]
	ld b, a
	ldh a, [hQuotient + 3]
	sub b
	ld b, [hl]
	ldh a, [hQuotient + 2]
	sbc b
	jr nc, .notHealthyEnough
	ld a, [wPartyAndBillsPCSavedMenuItem]
	push af
	ld a, POTION
	ld [wCurItem], a
	ld [wPseudoItemID], a
	call UseItem
	xor a
	ld [wPseudoItemID], a
	pop af
	ld [wPartyAndBillsPCSavedMenuItem], a
	ret
.notHealthyEnough
	ld hl, .notHealthyEnoughText
	jp PrintText
.notHealthyEnoughText
	text_far _NotHealthyEnoughText
	text_end
