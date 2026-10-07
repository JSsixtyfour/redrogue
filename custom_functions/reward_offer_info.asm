; Reward offer DVs and the INFO screen.
;
; Each of the three reward offers (wRoguePokemon1-3: stage reward balls, the
; reward menu, Oak's Lab starters) owns a fixed DV pair from the first moment
; anything looks at it, so the INFO preview and the mon actually given agree.
;
; Storage is SRAM (sRogueOfferDVs, ram/sram.asm), not saved WRAM: Main Data had
; only a 3-byte pad left. SRAM is battery-backed directly rather than copied in
; on SAVE, so a reset-without-saving reloads the same offers AND the same DVs -
; there is no re-rolling DVs by resetting.
;
; DVs are rolled LAZILY, keyed by species. About ten sites write
; wRoguePokemon1-3 (lobby batch, four procedural generators, bridge gifts,
; trades), so instead of hooking every writer, each slot remembers which species
; its DVs were rolled for (sRogueOfferDVTag). A slot whose species no longer
; matches its tag is a new offer and gets fresh DVs. The one blind spot - the
; same species landing in the same slot on a later offer keeps the old DVs - is
; harmless.

; ============================================================================
; GetRogueOfferDVs
; IN:  e = offer slot, 1-3
; OUT: h = Spd/Spc DV byte (MON_DVS + 1), l = Atk/Def DV byte (MON_DVS + 0).
;      RAW: no DV Booster floor (see GetRogueOfferDVsFloored).
; Clobbers a, bc, de. Leaves SRAM disabled on bank 0 (house convention).
; Farcall-safe: the slot travels in e and the result in hl, the only registers
; Bankswitch passes through (project_farcall_bc_clobber_bug_class).
; ============================================================================
GetRogueOfferDVs::
	ld d, 0
	dec e                     ; de = slot 0-2
	ld hl, wRoguePokemon1
	add hl, de
	ld b, [hl]                ; b = species offered in this slot right now
	call RogueOfferDVsOpen
	ld hl, sRogueOfferDVTag
	add hl, de
	ld a, [hl]
	cp b
	ld hl, sRogueOfferDVs
	add hl, de
	add hl, de                ; hl = this slot's DV pair
	jr z, .read
	; new offer in this slot: retag and roll (Random preserves hl/de/bc and
	; never switches banks, so it is safe with SRAM open)
	push hl
	ld hl, sRogueOfferDVTag
	add hl, de
	ld [hl], b
	pop hl
	call Random
	ld [hli], a
	call Random
	ld [hld], a
.read
	ld a, [hli]               ; byte 0 = Atk/Def
	ld h, [hl]                ; byte 1 = Spd/Spc
	ld l, a
	; fall through

; Always leave SRAM bank 0 selected and SRAM disabled, the ambient state every
; other SRAM user relies on (project_sram_new_field_needs_explicit_clear).
; Preserves hl/de/bc.
RogueOfferDVsClose:
	xor a
	ld [rRAMB], a
	ld [rBMODE], a
	ld [rRAMG], a ; RAMG_SRAM_DISABLE
	ret

RogueOfferDVsOpen:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sRogueOfferDVs)
	ld [rRAMB], a
	ret

; ============================================================================
; GetRogueOfferDVsFloored
; Same contract as GetRogueOfferDVs, but each nibble is raised to the DV
; Booster's floor - i.e. exactly the DVs the player would receive. Used by the
; INFO screen and by the box path (LoadEnemyMonData), which has no floor of
; its own. _AddPartyMon takes the RAW pair instead, because its existing DV
; Booster block floors whatever it rolled.
; Preserves wCurPartySpecies (wCurItem is the same byte, project_wcuritem_species_alias).
; ============================================================================
GetRogueOfferDVsFloored::
	call GetRogueOfferDVs
	push hl
	ld a, [wCurPartySpecies]
	push af
	ld a, DV_BOOSTER
	ld [wCurItem], a
	farcall GetKeyItemPowerInE ; e = 0 (not active) or 1-3 (tier)
	pop af
	ld [wCurPartySpecies], a
	pop hl
	ld a, e
	and a
	ret z
	dec a
	ld c, a
	ld b, 0
	push hl
	ld hl, OfferDVFloorTable
	add hl, bc
	ld e, [hl]                ; e = floor
	pop hl
	ld a, h
	call OfferApplyDVFloor
	ld h, a
	ld a, l
	call OfferApplyDVFloor
	ld l, a
	ret

; Copies of ApplyDVFloor / DVFloorTable (engine/pokemon/add_mon.asm, bank 3).
; Those take their input in a, which cannot cross a farcall, so this bank keeps
; its own. KEEP THE TABLE IN SYNC with DVFloorTable.
; IN: a = two packed DV nibbles, e = floor. OUT: a. Clobbers d.
OfferApplyDVFloor:
	push af
	and $0f
	cp e
	jr nc, .lowOk
	ld a, e
.lowOk
	ld d, a
	pop af
	swap a
	and $0f
	cp e
	jr nc, .highOk
	ld a, e
.highOk
	swap a
	or d
	ret

OfferDVFloorTable:
	db 6, 10, 13

; ============================================================================
; RogueOfferDVsClear - new game. SRAM powers up $FF, and stale tags from an old
; run could otherwise match a new offer. A zero tag matches no real offer.
; Preserves nothing.
; ============================================================================
RogueOfferDVsClear::
	call RogueOfferDVsOpen
	ld hl, sRogueOfferDVs
	ld bc, sRogueOfferDVsEnd - sRogueOfferDVs
	xor a
	call FillMemory
	jr RogueOfferDVsClose

; ============================================================================
; YesNoInfoChoice - YES / NO / INFO in a box above the message box, the three-
; option sibling of YesNoChoice (home/yes_no.asm), which can't take a third
; option (DisplayTwoOptionMenu hard-codes wMaxMenuItem = 1 and a 5x6 save).
; OUT: hCurrentMenuItem 0 = YES, 1 = NO (also B), 2 = INFO. Screen restored.
; Callers must test for INFO BEFORE the usual `and a / jr nz` NO test.
; ============================================================================
YesNoInfoChoice::
	call SaveScreenTilesToBuffer1
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	ldh a, [hUILayoutFlags]
	res BIT_DOUBLE_SPACED_MENU, a ; inverted name: CLEAR = 2-row cursor stride
	ldh [hUILayoutFlags], a
	hlcoord 13, 5
	lb bc, 5, 5
	call TextBoxBorder
	call UpdateSprites
	hlcoord 15, 6
	ld de, YesNoInfoText
	call PlaceString
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	xor a
	ldh [hCurrentMenuItem], a
	ld [wMenuWatchMovingOutOfBounds], a
	ld hl, wTopMenuItemY
	ld a, 6
	ld [hli], a ; wTopMenuItemY
	ld a, 14
	ld [hli], a ; wTopMenuItemX
	inc hl      ; wTileBehindCursor
	ld a, 2
	ld [hli], a ; wMaxMenuItem
	ld a, PAD_A | PAD_B
	ld [hli], a ; wMenuWatchedKeys
	xor a
	ld [hl], a  ; wLastMenuItem
	call HandleMenuInput
	bit B_PAD_B, a
	jr z, .chosen
	ld a, 1 ; B = NO
	ldh [hCurrentMenuItem], a
.chosen
	ld c, 15
	call DelayFrames
	jp LoadScreenTilesFromBuffer1

YesNoInfoText:
	db   "YES"
	next "NO"
	next "INFO@"

; ============================================================================
; RewardOfferChoice - the whole YES / NO / INFO step for offer slot e (1-3),
; so each call site costs only `ld e, N / farcall / jr z` (Oak's Lab's bank
; $07 has single-digit bytes free).
; OUT: z  = INFO was picked and shown; the map was reloaded, so the caller
;           re-names the offer, reprints its prompt and calls this again.
;      nz = answered; hCurrentMenuItem 0 = YES, 1 = NO.
; Flags survive the farcall return. Clobbers everything but d (the reward
; balls keep their toggle index there, though they also push it).
; ============================================================================
RewardOfferChoice::
	push de
	call YesNoInfoChoice
	pop de
	ldh a, [hCurrentMenuItem]
	cp 2
	ret nz
	push de
	call ShowRewardOfferInfo
	pop de
	xor a ; z: ask again
	ret

; ============================================================================
; ShowRewardOfferInfo - the INFO screen: the full Pokedex page for offer slot
; e (1-3), in the offer's form, with page 2 and its DVs. Generalizes the old
; OaksLabShowStarterDex. The species is marked OWNED for the duration (so the
; full entry renders) and un-marked afterwards only if it wasn't owned before.
; Farcall-safe (slot in e). Clobbers everything; the map is reloaded, so the
; caller reprints its prompt.
; ============================================================================
ShowRewardOfferInfo::
	ld a, e
	ld [wRewardInfoSlot], a
	ld b, FLAG_TEST
	call RewardInfoDexOwnedFlag ; c != 0 if already owned
	ld a, c
	push af
	ld b, FLAG_SET
	call RewardInfoDexOwnedFlag
	call RewardInfoSpecies
	ld [wPokedexNum], a ; ShowPokedexData reads the species from here
	ld [wCurPartySpecies], a
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	predef ShowPokedexData
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	call ReloadMapData
	ld c, 10
	call DelayFrames
	pop af
	and a
	jr nz, .wasOwned
	ld b, FLAG_RESET
	call RewardInfoDexOwnedFlag
.wasOwned
	xor a
	ld [wRewardInfoSlot], a
	ret

; OUT: a = species in offer slot [wRewardInfoSlot]. Clobbers de, hl.
RewardInfoSpecies:
	ld a, [wRewardInfoSlot]
	dec a
	ld e, a
	ld d, 0
	ld hl, wRoguePokemon1
	add hl, de
	ld a, [hl]
	ret

; IN: b = FLAG_TEST / FLAG_SET / FLAG_RESET on the offer species' OWNED bit.
; OUT: c = FLAG_TEST result. Clobbers everything.
RewardInfoDexOwnedFlag:
	push bc
	call RewardInfoSpecies
	ld [wPokedexNum], a
	predef IndexToPokedex
	pop bc
	ld a, [wPokedexNum]
	dec a
	ld c, a
	ld hl, wPokedexOwned
	predef_jump FlagActionPredef

; ============================================================================
; Preview hooks called from ShowPokedexDataInternal (engine/menus/pokedex.asm).
; Each is a no-op unless wRewardInfoSlot is set, so the real Pokedex, the
; catch screen and every other ShowPokedexData caller are unchanged.
; ============================================================================

; Before GetMonName and again before GetMonHeader: publish the offer's form so
; the name, sprite, types and base-stat bars are the form's. A context is
; consumed by each header load (ApplyFormOverride's contract), hence twice;
; PrintMonType's later reload keeps it through the refresh path.
; Clobbers af, bc, hl.
RewardInfoPublishForm::
	ld a, [wRewardInfoSlot]
	and a
	ret z
	dec a
	ld c, a
	ld b, 0
	ld hl, wRoguePokemonForm1
	add hl, bc
	ld a, [hl]
	ld [wFormContextForm], a
	ld hl, wRoguePokemon1
	add hl, bc
	ld a, [hl]
	ld [wFormContextSpecies], a
	ret

; Replaces the page-2 gate. OUT: nz = show page 2 (base stats). Always during
; a preview (Oak's Lab starters come before the Pokedex); otherwise only once
; the player has the Pokedex, as before. Flags survive Bankswitch's return.
RewardInfoWantsPageTwo::
	ld a, [wRewardInfoSlot]
	and a
	ret nz
	CheckEvent EVENT_GOT_POKEDEX
	ret

; After PrintBaseStats: swap the long stat labels for short ones and print the
; offer's DVs (DV Booster floor applied, i.e. exactly what taking it gives) in
; the gap: label at col 2, DV at cols 7-8, bars untouched from col 10.
PrintRewardOfferDVs::
	ld a, [wRewardInfoSlot]
	and a
	ret z
	ld e, a
	call GetRogueOfferDVsFloored ; h = Spd/Spc, l = Atk/Def
	push hl
	hlcoord 1, 11
	lb bc, NUM_STATS, 8
	call ClearScreenArea
	ldh a, [hUILayoutFlags]
	push af
	set BIT_SINGLE_SPACED_LINES, a
	ldh [hUILayoutFlags], a
	hlcoord 2, 11
	ld de, RewardInfoStatLabels
	call PlaceString
	pop af
	ldh [hUILayoutFlags], a
	pop de ; d = Spd/Spc, e = Atk/Def
	; HP DV: the low bit of each of Atk, Def, Spd, Spc, in that order
	ld b, 0
	ld a, e
	swap a
	rrca
	rl b
	ld a, e
	rrca
	rl b
	ld a, d
	swap a
	rrca
	rl b
	ld a, d
	rrca
	rl b
	ld a, b
	hlcoord 7, 11
	call RewardInfoPrintDV
	ld a, e
	swap a
	call RewardInfoPrintDV ; Atk
	ld a, e
	call RewardInfoPrintDV ; Def
	ld a, d
	swap a
	call RewardInfoPrintDV ; Spd
	ld a, d
	; fall through        ; Spc

; Two-digit DV (low nibble of a) at hl, then hl moves down one row. Writes
; tiles directly, like StatusViewPrintDV (PrintNumber/HRAM alias trap).
; Preserves de.
RewardInfoPrintDV:
	and $f
	ld b, ' '
	cp 10
	jr c, .ones
	sub 10
	ld b, '1'
.ones
	add '0'
	ld [hl], b
	inc hl
	ld [hl], a
	ld bc, SCREEN_WIDTH - 1
	add hl, bc
	ret

RewardInfoStatLabels:
	db   "HP"
	next "ATK"
	next "DEF"
	next "SPD"
	next "SPC@"
