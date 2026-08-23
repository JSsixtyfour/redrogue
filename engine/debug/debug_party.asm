SetDebugNewGameParty: ; unreferenced except in _DEBUG
	ld de, DebugNewGameParty
.loop
	ld a, [de]
	cp -1
	ret z
	ld [wCurPartySpecies], a
	inc de
	ld a, [de]
	ld [wCurEnemyLevel], a
	inc de
	call AddPartyMon
	jr .loop

DebugNewGameParty: ; unreferenced except in _DEBUG
	; Exeggutor is the only debug party member shared with Red, Green, and Japanese Blue.
	; "Tsunekazu Ishihara: Exeggutor is my favorite. That's because I was
	; always using this character while I was debugging the program."
	; From https://web.archive.org/web/20000607152840/http://pocket.ign.com/news/14973.html
	db EXEGGUTOR, 90
IF DEF(_DEBUG)
	db MEW, 5
ELSE
	db MEW, 20
ENDC
	db JOLTEON, 56
	db DUGTRIO, 56
	db ARTICUNO, 57
IF DEF(_DEBUG)
	db PIKACHU, 5
ENDC
	db -1 ; end

PrepareNewGameDebug: ; dummy except in _DEBUG
IF DEF(_DEBUG)
	xor a ; PLAYER_PARTY_DATA
	ld [wMonDataLocation], a

	; Fly anywhere.
	dec a ; $ff (all bits)
	ld [wTownVisitedFlag], a
	ld [wTownVisitedFlag + 1], a

	; Get all badges except Earth Badge.
	ld a, ~(1 << BIT_EARTHBADGE)
	ld [wObtainedBadges], a

	; Own all TMs and HMs in the debug build (InitPlayerData already cleared
	; sTMBitfield, so just fill it here).
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a       ; select bank 1 explicitly; ambient bank is unreliable
	ld hl, sTMBitfield
	ld a, $ff
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	xor a
	ld [rRAMG], a

	ld a, $10             ; skip naming screen (non-zero) but keep player party (low nibble 0)
	ld [wMonDataLocation], a
	call SetDebugNewGameParty
	xor a
	ld [wMonDataLocation], a

	; Skipping the naming screen above means AskName never runs, so every
	; debug party member's nickname slot is left blank instead of defaulting
	; to anything - rendering that blank name later (e.g. in a party menu)
	; reads past the end of an unterminated string. Give them all a generic
	; placeholder name instead.
	ld a, [wPartyCount]
	ld b, a
	ld de, wPartyMonNicks
.debugNameLoop
	push bc              ; preserve loop counter - both `ld bc` below and CopyData
	                     ; clobber b, which otherwise underflows to $ff on the first
	                     ; `dec b` and turns this into a near-infinite loop that
	                     ; marches de through all of WRAM, corrupting the stack and
	                     ; crashing the debug new game
	ld hl, .DebugMonName
	push de
	ld bc, .DebugMonNameEnd - .DebugMonName
	call CopyData       ; copies hl (source) -> de (dest), advancing both - but
	pop de               ; restore de to the start of this slot, then advance it
	ld hl, NAME_LENGTH   ; by the slot's full width, not just the bytes written,
	add hl, de           ; so the next nickname starts at the next slot
	ld d, h
	ld e, l
	pop bc               ; restore loop counter
	dec b
	jr nz, .debugNameLoop
.DebugMonName
	db "TEST@"
.DebugMonNameEnd

	; Exeggutor gets four HM moves.
	ld hl, wPartyMon1Moves
	ld a, FLY
	ld [hli], a
	ld a, CUT
	ld [hli], a
	ld a, SURF
	ld [hli], a
	ld a, STRENGTH
	ld [hl], a
	ld hl, wPartyMon1PP
	ld a, 15
	ld [hli], a
	ld a, 30
	ld [hli], a
	ld a, 15
	ld [hli], a
	ld [hl], a

	; Jolteon gets Thunderbolt.
	ld hl, wPartyMon3Moves + 3
	ld a, THUNDERBOLT
	ld [hl], a
	ld hl, wPartyMon3PP + 3
	ld a, 15
	ld [hl], a

	; Articuno gets Fly.
	ld hl, wPartyMon5Moves
	ld a, FLY
	ld [hl], a
	ld hl, wPartyMon5PP
	ld a, 15
	ld [hl], a

	; Pikachu gets Surf.
	ld hl, wPartyMon6Moves + 2
	ld a, SURF
	ld [hl], a
	ld hl, wPartyMon6PP + 2
	ld a, 15
	ld [hl], a

	; Get some debug items. Use GiveItem (not AddItemToInventory directly)
	; so TMs/HMs are routed to sTMBitfield instead of the regular bag.
	; push/pop de preserves the list pointer — GiveItem clobbers de via
	; CopyToStringBuffer and other internal calls.
	ld de, DebugNewGameItemsList
.items_loop
	ld a, [de]
	cp -1
	jr z, .items_end
	ld b, a
	inc de
	ld a, [de]
	ld c, a
	inc de
	push de
	call GiveItem
	pop de
	jr .items_loop
.items_end

	; Give debug key pocket items via GiveItem (same de-preservation needed).
	ld de, DebugKeyItemsList
.keyItemsLoop
	ld a, [de]
	cp -1
	jr z, .keyItemsEnd
	ld b, a
	inc de
	ld a, [de]
	ld c, a
	inc de
	push de
	call GiveItem
	pop de
	jr .keyItemsLoop
.keyItemsEnd

	; Complete the Pokédex.
	ld hl, wPokedexOwned
	call DebugSetPokedexEntries
	ld hl, wPokedexSeen
	call DebugSetPokedexEntries
	SetEvent EVENT_GOT_POKEDEX

	; Rival chose Squirtle,
	; Player chose Charmander.
	ld hl, wRivalStarter
	ASSERT wRivalStarter + 2 == wPlayerStarter
	ld a, STARTER2
	ld [hli], a
	inc hl
	ld a, STARTER1
	ld [hl], a

	; Own every SilphCoDorm room piece. Deliberately NOT gated on
	; BIT_DEBUG2_MODE: the dorm isn't reachable from the Debug 2 spawn, so
	; granting only there is useless. Every debug new game gets them.
	farcall RoomGrantAllPieces

	; Split Debug 1's sandbox state from Debug 2's rogue-run setup.
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr nz, .debug2

	; Debug 1 is the general sandbox. Start in the dorm with the intro tour
	; complete so its connected facilities are immediately available.
	SetEvent EVENT_INTRO_TOUR_COMPLETE
	ret

	; --- Debug 2 extras (gated on BIT_DEBUG2_MODE) ---
.debug2
	; Prompt for a starting battle count (mart-style counter, 1-99, min 1).
	; The debug speech was skipped, so ensure font/text-box tiles are loaded
	; before drawing the quantity box.
	call LoadFontTilePatterns
	call LoadTextBoxTilePatterns
	xor a
	ld [wListMenuID], a        ; NOLISTMENU - plain quantity box, not the priced variant
	ld a, 99
	ld [wMaxItemQuantity], a
	call DisplayChooseQuantityMenu
	ld a, [wItemQuantity]      ; 1-99
	ld [wBattleCount], a

	; This helper is kept in the floating debug bank because bank 1 is full.
	farcall Debug2ChooseAITier

	; Apply the Porygon rival starter, half-max money, and the battle-count-
	; derived round state (badge count + gym/route flag), then the two forced-
	; door prompts (door 1, door 2). This lives in the rogue bank to keep
	; bank1 within its size limit; it only touches WRAM, so farcall is safe.
	farcall Debug2ApplyRoundState
	ret

DebugSetPokedexEntries:
	ld b, wPokedexOwnedEnd - wPokedexOwned - 1
	ld a, %11111111
.loop
	ld [hli], a
	dec b
	jr nz, .loop
	ld [hl], %01111111
	ret

DebugNewGameItemsList: ; marcelnote - moved some to key items pocket
	;db BICYCLE, 1
	;db MASTER_BALL, 99
	db RARE_CANDY, 99
	db FULL_RESTORE, 99
	db FULL_HEAL, 99
	;db ESCAPE_ROPE, 99
	;db MAX_ELIXIR, 99 ; marcelnote - added
;	db TOWN_MAP, 1
;	db SECRET_KEY, 1
;	db CARD_KEY, 1
;	db S_S_TICKET, 1
;	db LIFT_KEY, 1
	;db TM_TELEPORT, 1
	db TM_DIG, 1
	db TM_SOFTBOILED, 1
	db -1 ; end

DebugKeyItemsList:    ; marcelnote - new for Key Items pocket
	db BICYCLE, 1
	db TOWN_MAP, 1
	;db POKE_BEEPER, 1 ; marcelnote - added
	db OLD_ROD, 1
	;db ITEMFINDER, 1
	;db POKE_FLUTE, 1
	;db SECRET_KEY, 1
	;db CARD_KEY, 1
	;db S_S_TICKET, 1
	;db LIFT_KEY, 1
	;db SILPH_SCOPE, 1 ; marcelnote - added
	;db CITRUS_PASS, 1 ; marcelnote - added
	;db COIN_CASE, 1 ; marcelnote - added
;	db SURFBOARD, 1 ; marcelnote - added
	;db HM_CUT, 1 ; marcelnote - added
	;db HM_FLY, 1 ; marcelnote - added
	;db HM_SURF, 1 ; marcelnote - added
	;db HM_STRENGTH, 1 ; marcelnote - added
	;db HM_FLASH, 1 ; marcelnote - added
	db -1 ; end

DebugUnusedList: ; unreferenced
	db -1 ; end
ELSE
	ret
ENDC
