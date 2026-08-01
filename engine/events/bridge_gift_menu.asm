; ============================================================================
; Bridge gift menu - data-driven rewrite.
;
; Each gift giver (identified by the map it lives in) owns one variable-length
; list of GiftEntry structs. A giver's list begins with a 1-byte count, then
; that many GiftEntry records:
;
;   GiftEntry (GIFT_ENTRY_SIZE bytes):
;     db  kind        ; GIFT_MON / GIFT_ITEM / GIFT_TEACH_MOVE / GIFT_SPECIAL
;     dw  param       ; species / item / move id (low byte), OR routine addr
;     dw  nameptr     ; short menu name string
;     dw  descptr     ; description text (text_far)
;
; GIFT_SPECIAL points param at an arbitrary routine so a gift can do anything.
; The giver is resolved from hCurMap (BridgeGiverMapTable) - no WRAM giver id.
; wGift1/2/3 hold the entry indices that were rolled for this visit.
; ============================================================================

DEF GIFT_MON        EQU 0
DEF GIFT_ITEM       EQU 1
DEF GIFT_TEACH_MOVE EQU 2
DEF GIFT_SPECIAL    EQU 3

DEF GIFT_ENTRY_SIZE EQU 7

MACRO gift_entry
; \1 = kind, \2 = param (id or routine), \3 = name ptr, \4 = desc ptr
	db \1
	dw \2
	dw \3
	dw \4
ENDM

DEF BRIDGE_MENU_MAX_OFFERED EQU 3

; ---------------------------------------------------------------------------
; Roll up to 3 distinct gift entry indices for the current giver into
; wGift1/wGift2/wGift3. Unused slots (when a giver has fewer than 3 gifts) are
; marked with $ff. Called (farcall) from each bridge room's setup script.
; ---------------------------------------------------------------------------
rogue_gift_randomized_batch::
	call GetGiverCount          ; a = number of gifts this giver has
	ld c, a                     ; c = range (preserved across Rangerandom)
	cp BRIDGE_MENU_MAX_OFFERED
	jr c, .fewerThan3
	call Rangerandom
	ld [wGift1], a
.roll2
	call Rangerandom
	ld d, a
	ld a, [wGift1]
	cp d
	jr z, .roll2
	ld a, d
	ld [wGift2], a
.roll3
	call Rangerandom
	ld d, a
	ld a, [wGift1]
	cp d
	jr z, .roll3
	ld a, [wGift2]
	cp d
	jr z, .roll3
	ld a, d
	ld [wGift3], a
	ret
.fewerThan3
	; c = count (1 or 2): offer them in order, sentinel the rest
	xor a
	ld [wGift1], a
	ld a, c
	cp 2
	jr c, .only1
	ld a, 1
	ld [wGift2], a
	ld a, $ff
	ld [wGift3], a
	ret
.only1
	ld a, $ff
	ld [wGift2], a
	ld [wGift3], a
	ret

; ---------------------------------------------------------------------------
BridgeGiftMenu::
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	ld hl, BridgeGiftText
	call PrintText
; menu settings
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, PAD_A | PAD_B | PAD_UP | PAD_DOWN
	ld [wMenuWatchedKeys], a
	call GetOfferedCount
	ld [wMaxMenuItem], a         ; max index = the NO THANKS slot
	ld a, $04
	ld [wTopMenuItemY], a
	ld a, $01
	ld [wTopMenuItemX], a
	hlcoord 0, 2
	ld b, 8
	ld c, 18
	call TextBoxBorder
	call BridgePlaceGiftNames
	call UpdateSprites
	xor a
	call BridgePrintGiftDesc     ; description for the initially-hovered gift
.menuLoop
	call HandleMenuInput
	bit B_PAD_A, a
	jr nz, .aPressed
	bit B_PAD_B, a
	jr nz, .noChoice
	ldh a, [hCurrentMenuItem]
	call BridgePrintGiftDesc
	jr .menuLoop
.aPressed
	ldh a, [hCurrentMenuItem]
	push af
	call GetOfferedCount
	ld b, a
	pop af                       ; a = selected menu index
	cp b
	jr z, .noChoice              ; NO THANKS
	call BridgeDoGift
	; fall through to clear BIT_NO_TEXT_DELAY before returning
.noChoice
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ret

; ---------------------------------------------------------------------------
; Place the offered gift names (rows 4,6,8,...) then NO THANKS below them.
BridgePlaceGiftNames:
	call GetOfferedCount
	ld b, a                      ; b = offered count
	ld c, 0                      ; c = index
.loop
	ld a, c
	cp b
	jr z, .noThanks
	ld hl, wGift1
	ld a, c
	add l
	ld l, a
	ld a, [hl]                   ; entry index
	call GetGiftEntry            ; hl -> entry (bc preserved)
	inc hl
	inc hl
	inc hl                       ; -> name ptr field
	ld a, [hli]
	ld h, [hl]
	ld l, a                      ; hl = name string
	ld d, h
	ld e, l                      ; de = name string
	ld a, c
	add a
	add 4                        ; row = 4 + 2*index
	push bc
	push de
	call BridgeCoordRow2         ; hl = coord(2, row)
	pop de
	call PlaceString
	pop bc
	inc c
	jr .loop
.noThanks
	ld a, b
	add a
	add 4                        ; row = 4 + 2*offered
	call BridgeCoordRow2
	ld de, NoThanksText
	call PlaceString
	ret

; in: a = row ; out: hl = coord at column 2, given row (clobbers a, de)
BridgeCoordRow2:
	ld l, a
	ld h, 0
	ld d, h
	ld e, l                      ; de = row
	add hl, hl                   ; *2
	add hl, hl                   ; *4
	add hl, de                   ; *5
	add hl, hl                   ; *10
	add hl, hl                   ; *20 (SCREEN_WIDTH)
	ld de, wTileMap + 2
	add hl, de
	ret

; in: a = menu index ; prints that slot's description (or Empty for NO THANKS)
BridgePrintGiftDesc:
	push af
	call GetOfferedCount
	ld b, a
	pop af
	cp b
	jr z, .empty
	ld hl, wGift1
	add l
	ld l, a
	ld a, [hl]                   ; entry index
	call GetGiftEntry            ; hl -> entry
	ld bc, 5
	add hl, bc                   ; -> desc ptr field
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp PrintText
.empty
	ld hl, Empty
	jp PrintText

; ---------------------------------------------------------------------------
; in: a = selected menu index ; performs the chosen gift.
BridgeDoGift:
	SetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ld hl, wGift1
	add l
	ld l, a
	ld a, [hl]                   ; entry index
	call GetGiftEntry            ; hl -> entry
	ld a, [hli]                  ; kind
	ld e, [hl]
	inc hl
	ld d, [hl]                   ; de = param
	cp GIFT_MON
	jr z, .mon
	cp GIFT_ITEM
	jr z, .item
	cp GIFT_TEACH_MOVE
	jr z, .teach
; GIFT_SPECIAL: de = routine address; call it, then say bye
	ld h, d
	ld l, e
	ld de, .bye
	push de
	jp hl
.mon
	ld a, e
	call BridgeGiveMon
	jr .bye
.item
	ld a, e
	call BridgeGiveItem
	jr .bye
.teach
	ld a, e
	call BridgeTeachMove
.bye
	ld hl, BridgeByeText
	jp PrintText

; ---------------------------------------------------------------------------
; Generic gift helpers.

; in: a = species. Gives it at the current reward level.
BridgeGiveMon:
	push af
	call GetRewardMonLevel
	ld c, a                      ; level
	pop af
	ld b, a                      ; species
	call GivePokemon
	ret

; in: a = item id. Gives one and announces it.
BridgeGiveItem:
	push af
	ld b, a
	ld c, 1
	call GiveItem
	pop af
	ld [wNamedObjectIndex], a   ; GiveItem clobbers it internally; restore for the name
	call ReceivedItem
	ret

; in: a = move id. Player picks a party mon; teaches it the move.
BridgeTeachMove:
	push af                      ; save move id
	call BridgeSelectPartyMon    ; carry = cancelled; hWhichPokemon = slot
	pop bc                       ; b = move id (carry unaffected by pop)
	ret c
	ld a, b
	ld [wMoveNum], a
	ld [wNamedObjectIndex], a
	call GetMoveName
	call CopyToStringBuffer
	ld a, [wLetterPrintingDelayFlags]
	push af
	xor a
	ld [wLetterPrintingDelayFlags], a
	predef LearnMove
	pop af
	ld [wLetterPrintingDelayFlags], a
	ret

; Opens the party menu for a selection. out: carry set = cancelled,
; hWhichPokemon = chosen slot.
BridgeSelectPartyMon:
	call SaveScreenTilesToBuffer2
	xor a
	ld [wListScrollOffset], a
	ld [wPartyMenuTypeOrMessageID], a
	ldh [hUpdateSpritesEnabled], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	ret

; ---------------------------------------------------------------------------
; Giver resolution helpers (giver = current map).

; out: a = giver index (position in BridgeGiverMapTable). Assumes the current
; map is a bridge giver (only reached while inside a giver room).
GetGiverIndex:
	ldh a, [hCurMap]
	ld b, a
	ld hl, BridgeGiverMapTable
	ld c, 0
.loop
	ld a, [hli]
	cp b
	jr z, .found
	inc c
	jr .loop
.found
	ld a, c
	ret

; out: hl -> the giver's list (count byte first)
GetGiverListBase:
	call GetGiverIndex
	add a                        ; *2 (dw table)
	ld e, a
	ld d, 0
	ld hl, BridgeGiverLists
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; out: a = number of gifts the current giver has
GetGiverCount:
	call GetGiverListBase
	ld a, [hl]
	ret

; out: a = min(BRIDGE_MENU_MAX_OFFERED, giver count)
GetOfferedCount:
	call GetGiverCount
	cp BRIDGE_MENU_MAX_OFFERED
	ret c
	ld a, BRIDGE_MENU_MAX_OFFERED
	ret

; in: a = entry index ; out: hl -> that GiftEntry. Preserves bc (clobbers de).
GetGiftEntry:
	push bc                      ; save caller's bc BEFORE GetGiverListBase clobbers it
	push af
	call GetGiverListBase
	inc hl                       ; skip count byte -> entry 0
	pop af
	ld bc, GIFT_ENTRY_SIZE
	call AddNTimes               ; hl += a * GIFT_ENTRY_SIZE
	pop bc
	ret

; ---------------------------------------------------------------------------
; GIFT_SPECIAL routines (must not print bye - the dispatcher does).

; Mr. Fuji "#MON RESCUE": give the run's rogue pokemon at reward level.
BridgeMrFujiRescue::
	ld a, [wRoguePokemon1]
	jp BridgeGiveMon

; Mr. Fuji "THICK CLUB": CUBONE early, MAROWAK once deep enough into the run.
; Given as a BIT_SPECIAL_FORM mon so the SpecialFormCaps table's DOUBLE_ATK
; (Thick Club emulation) applies (func_special_form.asm).
BridgeMrFujiCubone::
	ld a, [wBattleCount]
	cp 30
	ld a, CUBONE
	jr nc, .give
	ld a, MAROWAK
.give
	call BridgeGiveMon
	jp BridgeApplySpecialFormToNewMon

; Oak's Light-Ball PIKACHU: given as a BIT_SPECIAL_FORM mon (DOUBLE_ATK |
; DOUBLE_SPC | NO_EVOLVE per SpecialFormCaps).
BridgeOakPikachu::
	ld a, PIKACHU
	call BridgeGiveMon
	jp BridgeApplySpecialFormToNewMon

; Captain's always-crit FARFETCH'D (SpecialFormCaps -> ALWAYS_CRIT).
BridgeCaptainFarfetchd::
	ld a, FARFETCHD
	call BridgeGiveMon
	jp BridgeApplySpecialFormToNewMon

; Copycat's SUPER DITTO: a DITTO with perfect DVs, maxed stat exp, and the
; SUPER_TRANSFORM + TRANSFORM move pair. If the party is full the mon is boxed
; as a plain DITTO (the special treatment only applies on the party path).
BridgeCopyCatSuperDitto::
	ld a, DITTO
	call BridgeGiveMon
	ld a, [wAddedToParty]
	and a
	ret z
	call GetLastPartyMonStruct   ; hl = struct base
	; perfect DVs
	push hl
	ld bc, MON_DVS
	add hl, bc
	ld a, $ff
	ld [hli], a
	ld [hl], a
	pop hl
	; max stat exp (MON_HP_EXP..MON_SPC_EXP = 5 words, contiguous)
	push hl
	ld bc, MON_HP_EXP
	add hl, bc
	ld c, 10
	ld a, $ff
.statExpLoop
	ld [hli], a
	dec c
	jr nz, .statExpLoop
	pop hl
	; moves = SUPER_TRANSFORM, TRANSFORM, 0, 0
	push hl
	ld bc, MON_MOVES
	add hl, bc
	ld a, SUPER_TRANSFORM
	ld [hli], a
	ld a, TRANSFORM
	ld [hli], a
	xor a
	ld [hli], a
	ld [hl], a
	pop hl
	; PP for the new moveset (predef LoadMovePPs: hl = moves, de = PP - 1)
	push hl
	ld bc, MON_MOVES
	add hl, bc                   ; hl = moves ptr
	pop de                       ; de = struct base
	push de                      ; keep struct base
	push hl                      ; save moves ptr
	ld h, d
	ld l, e
	ld bc, MON_PP - 1
	add hl, bc
	ld d, h
	ld e, l                      ; de = PP - 1
	pop hl                       ; hl = moves ptr
	predef LoadMovePPs
	pop hl                       ; hl = struct base
	jp BridgeRecalcStats

; Mr. Fuji's GENE SPLICING: max out a chosen party mon's DVs, then recalc.
BridgeMrFujiGeneSplice::
	call BridgeSelectPartyMon
	ret c
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes               ; hl = selected struct base
	push hl
	ld bc, MON_DVS
	add hl, bc
	ld a, $ff
	ld [hli], a
	ld [hl], a
	pop hl
	jp BridgeRecalcStats

; Bill's DUPLICATE TRICK: pick a party mon, give an exact clone through the
; normal GivePokemon flow. Party-full clones fall back to a fresh same-species
; mon in the box (an exact copy needs the party struct, which the box lacks).
BridgeBillDuplicate::
	call BridgeSelectPartyMon
	ret c
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes               ; hl = source struct base
	ld a, [hl]
	ld b, a                      ; b = species
	push hl                      ; save source base across GivePokemon
	ld de, MON_LEVEL
	add hl, de
	ld a, [hl]
	ld c, a                      ; c = level
	call GivePokemon             ; fresh mon (party or box) + standard messaging
	pop hl                       ; hl = source base (party structs don't move)
	ld a, [wAddedToParty]
	and a
	ret z                        ; boxed -> fresh same-species mon, no exact clone
	push hl                      ; source base
	call GetLastPartyMonStruct   ; hl = dest (new last slot)
	pop de                       ; de = source base
	; CopyData copies [hl] -> [de]; we need source -> dest, so swap hl<->de.
	ld a, h
	ld h, d
	ld d, a
	ld a, l
	ld l, e
	ld e, a                      ; hl = source, de = dest
	ld bc, PARTYMON_STRUCT_LENGTH
	call CopyData
	ret

; Bill's MAD SCIENCE: fuse two party mons (func_fusion.asm handles the whole
; selection UI, guards, and messaging).
BridgeBillFusion::
	farcall CreateFusion
	ret

; Captain's WATER type variant: adds WATER as a chosen party mon's secondary
; type (blue palette, water STAB/defense). Fossil's is the ROCK equivalent.
BridgeCaptainWaterVariant::
	ld e, WATER
	jr BridgeApplyTypeVariantGift

BridgeFossilRockVariant::
	ld e, ROCK
	; fall through

; in: e = target type. Player picks a party mon; if it doesn't already have
; that type (type1 or type2), applies the type variant (flag + MON_TYPE2).
; Rejects with a message if it already has the type; silent on cancel.
BridgeApplyTypeVariantGift:
	ld a, e
	push af                       ; save target type across the menu
	call BridgeSelectPartyMon     ; carry = cancel, hWhichPokemon = slot
	pop bc                        ; b = target type (pop preserves carry)
	ret c
	ldh a, [hWhichPokemon]
	push bc                       ; save target type across AddNTimes
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes                ; hl = struct base
	pop bc                        ; b = target type
	push hl
	push bc
	ld de, MON_TYPE1
	add hl, de
	ld a, [hli]                   ; type1
	cp b
	jr z, .already
	ld a, [hl]                    ; type2 (MON_TYPE2 follows MON_TYPE1)
	cp b
	jr z, .already
	pop bc                        ; b = target type
	pop hl                        ; hl = struct base
	ld d, h
	ld e, l                       ; de = struct base
	ld a, b                       ; a = target type
	farcall ApplyTypeVariant
	ret
.already
	pop bc
	pop hl
	ld hl, BridgeTypeVariantFailText
	jp PrintText

; ---------------------------------------------------------------------------
; Shared special-gift helpers.

; If the most-recently-given mon landed in the party, flag it as a special
; form (its per-species caps come from SpecialFormCaps, func_special_form.asm).
BridgeApplySpecialFormToNewMon:
	ld a, [wAddedToParty]
	and a
	ret z
	call GetLastPartyMonStruct
	ld d, h
	ld e, l
	farcall ApplySpecialForm
	ret

; out: hl = struct base of the last (most-recently-added) party mon.
GetLastPartyMonStruct:
	ld a, [wPartyCount]
	dec a
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	jp AddNTimes

; Recalculate a party mon's stats in place from its stored DVs + stat exp, then
; refill current HP to the new max. in: hl = struct base.
BridgeRecalcStats:
	push hl
	ld a, [hl]
	ld [wCurSpecies], a
	call GetMonHeader            ; wMonHeader = species base stats
	pop hl
	push hl
	ld bc, MON_LEVEL
	add hl, bc
	ld a, [hl]
	ld [wCurEnemyLevel], a       ; CalcStats reads level from here
	pop hl
	push hl
	ld bc, MON_STATS
	add hl, bc
	ld d, h
	ld e, l                      ; de = MON_STATS (dest)
	pop hl
	push hl
	ld bc, MON_HP_EXP - 1
	add hl, bc                   ; hl = MON_HP_EXP - 1
	ld b, 1                      ; include stat exp
	push bc
	push hl
	farcall PrepareFusionCalcStats  ; de = MON_STATS (preserved)
	pop hl
	pop bc
	call CalcStats
	pop hl                       ; hl = struct base
	; refill current HP = max HP (both stored hi,lo)
	push hl
	ld bc, MON_STATS             ; MON_MAXHP == MON_STATS
	add hl, bc
	ld a, [hli]
	ld b, a
	ld c, [hl]
	pop hl
	ld de, MON_HP
	add hl, de
	ld [hl], b
	inc hl
	ld [hl], c
	ret

; ---------------------------------------------------------------------------
ReceivedItem::
	call GetItemName
	ld hl, ReceivedItemText
	call PrintText
	ret

; ---------------------------------------------------------------------------
; Text.
BridgeGiftText:
	text_far _BridgeGiftText
	text_end

BridgeByeText:
	text_far _BridgeByeText
	text_end

ReceivedItemText:
	text_far _ReceivedItemText
	text_end

BridgeTypeVariantFailText:
	text_far _BridgeTypeVariantFailText
	text_end

Empty:
	text_far _Empty
	text_end

; ---------------------------------------------------------------------------
; Giver dispatch tables. BridgeGiverMapTable and BridgeGiverLists are indexed
; in lockstep - add a map + its list to both when adding a bridge room.
BridgeGiverMapTable:
	db COPYCATS_HOUSE_2F
	db BILLS_HOUSE
	db MR_FUJIS_HOUSE
	db SS_ANNE_CAPTAINS_ROOM
	db CINNABAR_LAB_FOSSIL_ROOM
	db POKEMON_FAN_CLUB
	db WARDENS_HOUSE
	db VIRIDIAN_SCHOOL_HOUSE
	db VIRIDIAN_NICKNAME_HOUSE
	db CERULEAN_TRASHED_HOUSE
	db REDS_HOUSE_1F
	db LAVENDER_CUBONE_HOUSE
	db CERULEAN_TRADE_HOUSE
	db OAKS_LAB

BridgeGiverLists:
	dw CopyCatGiftList
	dw BillGiftList
	dw MrFujiGiftList
	dw CaptainGiftList
	dw FossilScientistGiftList
	dw FanClubChairmanGiftList
	dw WardenGiftList
	dw SchoolCooltrainerGiftList
	dw NicknameBaldingGuyGiftList
	dw TrashedHouseFishingGuruGiftList
	dw RedsHouseMomGiftList
	dw CuboneHouseGirlGiftList
	dw TradeHouseGrannyGiftList
	dw OaksLabOakGiftList

; ---------------------------------------------------------------------------
CopyCatGiftList:
	db 7
	gift_entry GIFT_SPECIAL,    BridgeCopyCatSuperDitto, CopyCatGift1_Text, CopyCatGift1_Desc
	gift_entry GIFT_ITEM,       TM_MIMIC,       CopyCatGift2_Text, CopyCatGift2_Desc
	gift_entry GIFT_ITEM,       TM_PSYCHIC_M,   CopyCatGift3_Text, CopyCatGift3_Desc
	gift_entry GIFT_TEACH_MOVE, MIRROR_MOVE,    CopyCatGift4_Text, CopyCatGift4_Desc
	gift_entry GIFT_TEACH_MOVE, TRANSFORM,      CopyCatGift5_Text, CopyCatGift5_Desc
	gift_entry GIFT_ITEM,       NUGGET,         CopyCatGift6_Text, CopyCatGift6_Desc
	gift_entry GIFT_ITEM,       TM_SUBSTITUTE,  CopyCatGift7_Text, CopyCatGift7_Desc

BillGiftList:
	db 7
	gift_entry GIFT_SPECIAL, BridgeBillFusion,    BillGift1_Text, BillGift1_Desc
	gift_entry GIFT_MON,  EEVEE,       BillGift2_Text, BillGift2_Desc
	gift_entry GIFT_MON,  JOLTEON,     BillGift3_Text, BillGift3_Desc
	gift_entry GIFT_MON,  FLAREON,     BillGift4_Text, BillGift4_Desc
	gift_entry GIFT_MON,  VAPOREON,    BillGift5_Text, BillGift5_Desc
	gift_entry GIFT_SPECIAL, BridgeBillDuplicate, BillGift6_Text, BillGift6_Desc
	gift_entry GIFT_ITEM, TM_THUNDERBOLT, BillGift7_Text, BillGift7_Desc

MrFujiGiftList:
	db 7
	gift_entry GIFT_ITEM,       POKE_FLUTE,         MrFujiGift1_Text, MrFujiGift1_Desc
	gift_entry GIFT_SPECIAL,    BridgeMrFujiRescue, MrFujiGift2_Text, MrFujiGift2_Desc
	gift_entry GIFT_SPECIAL,    BridgeMrFujiCubone,     MrFujiGift3_Text, MrFujiGift3_Desc
	gift_entry GIFT_SPECIAL,    BridgeMrFujiGeneSplice, MrFujiGift4_Text, MrFujiGift4_Desc
	gift_entry GIFT_TEACH_MOVE, NIGHT_SHADE,        MrFujiGift5_Text, MrFujiGift5_Desc
	gift_entry GIFT_TEACH_MOVE, CONFUSE_RAY,        MrFujiGift6_Text, MrFujiGift6_Desc
	gift_entry GIFT_TEACH_MOVE, LICK,               MrFujiGift7_Text, MrFujiGift7_Desc

CaptainGiftList:
	db 4
	gift_entry GIFT_ITEM,    HM_CUT,    CaptainGift1_Text, CaptainGift1_Desc
	gift_entry GIFT_MON,     TENTACOOL, CaptainGift2_Text, CaptainGift2_Desc
	gift_entry GIFT_SPECIAL, BridgeCaptainWaterVariant, CaptainGift3_Text, CaptainGift3_Desc
	gift_entry GIFT_SPECIAL, BridgeCaptainFarfetchd, CaptainGift4_Text, CaptainGift4_Desc

FossilScientistGiftList:
	db 3
	gift_entry GIFT_MON,     OMANYTE,   FossilGift1_Text, FossilGift1_Desc
	gift_entry GIFT_SPECIAL, BridgeFossilRockVariant, FossilGift2_Text, FossilGift2_Desc
	gift_entry GIFT_ITEM,    FIRE_STONE, FossilGift3_Text, FossilGift3_Desc

FanClubChairmanGiftList:
	db 3
	gift_entry GIFT_ITEM, BIKE_VOUCHER, FanClubGift1_Text, FanClubGift1_Desc
	gift_entry GIFT_MON,  CLEFAIRY,     FanClubGift2_Text, FanClubGift2_Desc
	gift_entry GIFT_ITEM, RARE_CANDY,   FanClubGift3_Text, FanClubGift3_Desc

WardenGiftList:
	db 3
	gift_entry GIFT_ITEM, HM_STRENGTH, WardenGift1_Text, WardenGift1_Desc
	gift_entry GIFT_MON,  KANGASKHAN,  WardenGift2_Text, WardenGift2_Desc
	gift_entry GIFT_ITEM, RARE_CANDY,  WardenGift3_Text, WardenGift3_Desc

SchoolCooltrainerGiftList:
	db 3
	gift_entry GIFT_TEACH_MOVE, DOUBLE_TEAM, SchoolGift1_Text, SchoolGift1_Desc
	gift_entry GIFT_ITEM,       CALCIUM,     SchoolGift2_Text, SchoolGift2_Desc
	gift_entry GIFT_ITEM,       RARE_CANDY,  SchoolGift3_Text, SchoolGift3_Desc

NicknameBaldingGuyGiftList:
	db 3
	gift_entry GIFT_MON,  SPEAROW,    NicknameGift1_Text, NicknameGift1_Desc
	gift_entry GIFT_ITEM, PP_UP,      NicknameGift2_Text, NicknameGift2_Desc
	gift_entry GIFT_ITEM, RARE_CANDY, NicknameGift3_Text, NicknameGift3_Desc

TrashedHouseFishingGuruGiftList:
	db 3
	gift_entry GIFT_ITEM, GOOD_ROD, TrashedGift1_Text, TrashedGift1_Desc
	gift_entry GIFT_MON,  MAGIKARP, TrashedGift2_Text, TrashedGift2_Desc
	gift_entry GIFT_MON,  POLIWAG,  TrashedGift3_Text, TrashedGift3_Desc

RedsHouseMomGiftList:
	db 3
	gift_entry GIFT_ITEM, FULL_RESTORE, MomGift1_Text, MomGift1_Desc
	gift_entry GIFT_MON,  EEVEE,        MomGift2_Text, MomGift2_Desc
	gift_entry GIFT_ITEM, RARE_CANDY,   MomGift3_Text, MomGift3_Desc

CuboneHouseGirlGiftList:
	db 3
	gift_entry GIFT_MON,  CUBONE, CuboneHouseGift1_Text, CuboneHouseGift1_Desc
	gift_entry GIFT_MON,  GASTLY, CuboneHouseGift2_Text, CuboneHouseGift2_Desc
	gift_entry GIFT_ITEM, REVIVE, CuboneHouseGift3_Text, CuboneHouseGift3_Desc

TradeHouseGrannyGiftList:
	db 3
	gift_entry GIFT_ITEM, NUGGET,     TradeHouseGift1_Text, TradeHouseGift1_Desc
	gift_entry GIFT_MON,  CLEFAIRY,   TradeHouseGift2_Text, TradeHouseGift2_Desc
	gift_entry GIFT_ITEM, MOON_STONE, TradeHouseGift3_Text, TradeHouseGift3_Desc

; Gift 1 is the Light-Ball PIKACHU special form (BridgeOakPikachu).
OaksLabOakGiftList:
	db 3
	gift_entry GIFT_SPECIAL, BridgeOakPikachu, OaksLabGift1_Text, OaksLabGift1_Desc
	gift_entry GIFT_ITEM, PROTEIN,    OaksLabGift2_Text, OaksLabGift2_Desc
	gift_entry GIFT_ITEM, RARE_CANDY, OaksLabGift3_Text, OaksLabGift3_Desc

; ---------------------------------------------------------------------------
; Menu name strings.
CopyCatGift1_Text: db "SUPER DITTO@"
CopyCatGift2_Text: db "MIMIC TM@"
CopyCatGift3_Text: db "PSYCHIC TM@"
CopyCatGift4_Text: db "MIRROR MOVE TUTOR@"
CopyCatGift5_Text: db "TRANSFORM TUTOR@"
CopyCatGift6_Text: db "NUGGET@"
CopyCatGift7_Text: db "SUBSTITUTE TM@"

BillGift1_Text: db "MAD SCIENCE@"
BillGift2_Text: db "EEVEE@"
BillGift3_Text: db "JOLTEON@"
BillGift4_Text: db "FLAREON@"
BillGift5_Text: db "VAPOREON@"
BillGift6_Text: db "DUPLICATE TRICK@"
BillGift7_Text: db "THUNDERBOLT TM@"

MrFujiGift1_Text: db "POKé FLUTE@"
MrFujiGift2_Text: db "#MON RESCUE@"
MrFujiGift3_Text: db "THICK CLUB@"
MrFujiGift4_Text: db "GENE SPLICING@"
MrFujiGift5_Text: db "NIGHTSHADE TUTOR@"
MrFujiGift6_Text: db "CONFUSE RAY TUTOR@"
MrFujiGift7_Text: db "LICK TUTOR@"

CaptainGift1_Text: db "HM CUT@"
CaptainGift2_Text: db "TENTACOOL@"
CaptainGift3_Text: db "SEA BLESSING@"
CaptainGift4_Text: db "LUCKY DUCK@"

FossilGift1_Text: db "OMANYTE@"
FossilGift2_Text: db "FOSSIL COAT@"
FossilGift3_Text: db "FIRE STONE@"

FanClubGift1_Text: db "BIKE VOUCHER@"
FanClubGift2_Text: db "CLEFAIRY@"
FanClubGift3_Text: db "RARE CANDY@"

WardenGift1_Text: db "HM STRENGTH@"
WardenGift2_Text: db "KANGASKHAN@"
WardenGift3_Text: db "RARE CANDY@"

SchoolGift1_Text: db "DOUBLE TEAM TUTOR@"
SchoolGift2_Text: db "CALCIUM@"
SchoolGift3_Text: db "RARE CANDY@"

NicknameGift1_Text: db "SPEAROW@"
NicknameGift2_Text: db "PP UP@"
NicknameGift3_Text: db "RARE CANDY@"

TrashedGift1_Text: db "GOOD ROD@"
TrashedGift2_Text: db "MAGIKARP@"
TrashedGift3_Text: db "POLIWAG@"

MomGift1_Text: db "FULL RESTORE@"
MomGift2_Text: db "EEVEE@"
MomGift3_Text: db "RARE CANDY@"

CuboneHouseGift1_Text: db "CUBONE@"
CuboneHouseGift2_Text: db "GASTLY@"
CuboneHouseGift3_Text: db "REVIVE@"

TradeHouseGift1_Text: db "NUGGET@"
TradeHouseGift2_Text: db "CLEFAIRY@"
TradeHouseGift3_Text: db "MOON STONE@"

OaksLabGift1_Text: db "PIKACHU@"
OaksLabGift2_Text: db "PROTEIN@"
OaksLabGift3_Text: db "RARE CANDY@"

; ---------------------------------------------------------------------------
; Descriptions.
CopyCatGift1_Desc:
	text_far _CopyCatGift1Desc
	text_end
CopyCatGift2_Desc:
	text_far _CopyCatGift2Desc
	text_end
CopyCatGift3_Desc:
	text_far _CopyCatGift3Desc
	text_end
CopyCatGift4_Desc:
	text_far _CopyCatGift4Desc
	text_end
CopyCatGift5_Desc:
	text_far _CopyCatGift5Desc
	text_end
CopyCatGift6_Desc:
	text_far _CopyCatGift6Desc
	text_end
CopyCatGift7_Desc:
	text_far _CopyCatGift7Desc
	text_end

BillGift1_Desc:
	text_far _BillGift1Desc
	text_end
BillGift2_Desc:
	text_far _BillGift2Desc
	text_end
BillGift3_Desc:
	text_far _BillGift3Desc
	text_end
BillGift4_Desc:
	text_far _BillGift4Desc
	text_end
BillGift5_Desc:
	text_far _BillGift5Desc
	text_end
BillGift6_Desc:
	text_far _BillGift6Desc
	text_end
BillGift7_Desc:
	text_far _BillGift7Desc
	text_end

MrFujiGift1_Desc:
	text_far _MrFujiGift1Desc
	text_end
MrFujiGift2_Desc:
	text_far _MrFujiGift2Desc
	text_end
MrFujiGift3_Desc:
	text_far _MrFujiGift3Desc
	text_end
MrFujiGift4_Desc:
	text_far _MrFujiGift4Desc
	text_end
MrFujiGift5_Desc:
	text_far _MrFujiGift5Desc
	text_end
MrFujiGift6_Desc:
	text_far _MrFujiGift6Desc
	text_end
MrFujiGift7_Desc:
	text_far _MrFujiGift7Desc
	text_end

CaptainGift1_Desc:
	text_far _CaptainGift1Desc
	text_end
CaptainGift2_Desc:
	text_far _CaptainGift2Desc
	text_end
CaptainGift3_Desc:
	text_far _CaptainGift3Desc
	text_end
CaptainGift4_Desc:
	text_far _CaptainGift4Desc
	text_end

FossilGift1_Desc:
	text_far _FossilGift1Desc
	text_end
FossilGift2_Desc:
	text_far _FossilGift2Desc
	text_end
FossilGift3_Desc:
	text_far _FossilGift3Desc
	text_end

FanClubGift1_Desc:
	text_far _FanClubGift1Desc
	text_end
FanClubGift2_Desc:
	text_far _FanClubGift2Desc
	text_end
FanClubGift3_Desc:
	text_far _FanClubGift3Desc
	text_end

WardenGift1_Desc:
	text_far _WardenGift1Desc
	text_end
WardenGift2_Desc:
	text_far _WardenGift2Desc
	text_end
WardenGift3_Desc:
	text_far _WardenGift3Desc
	text_end

SchoolGift1_Desc:
	text_far _SchoolGift1Desc
	text_end
SchoolGift2_Desc:
	text_far _SchoolGift2Desc
	text_end
SchoolGift3_Desc:
	text_far _SchoolGift3Desc
	text_end

NicknameGift1_Desc:
	text_far _NicknameGift1Desc
	text_end
NicknameGift2_Desc:
	text_far _NicknameGift2Desc
	text_end
NicknameGift3_Desc:
	text_far _NicknameGift3Desc
	text_end

TrashedGift1_Desc:
	text_far _TrashedGift1Desc
	text_end
TrashedGift2_Desc:
	text_far _TrashedGift2Desc
	text_end
TrashedGift3_Desc:
	text_far _TrashedGift3Desc
	text_end

MomGift1_Desc:
	text_far _MomGift1Desc
	text_end
MomGift2_Desc:
	text_far _MomGift2Desc
	text_end
MomGift3_Desc:
	text_far _MomGift3Desc
	text_end

CuboneHouseGift1_Desc:
	text_far _CuboneHouseGift1Desc
	text_end
CuboneHouseGift2_Desc:
	text_far _CuboneHouseGift2Desc
	text_end
CuboneHouseGift3_Desc:
	text_far _CuboneHouseGift3Desc
	text_end

TradeHouseGift1_Desc:
	text_far _TradeHouseGift1Desc
	text_end
TradeHouseGift2_Desc:
	text_far _TradeHouseGift2Desc
	text_end
TradeHouseGift3_Desc:
	text_far _TradeHouseGift3Desc
	text_end

OaksLabGift1_Desc:
	text_far _OaksLabGift1Desc
	text_end
OaksLabGift2_Desc:
	text_far _OaksLabGift2Desc
	text_end
OaksLabGift3_Desc:
	text_far _OaksLabGift3Desc
	text_end
