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
BridgeMrFujiCubone::
	ld a, [wBattleCount]
	cp 30
	ld a, CUBONE
	jr nc, .give
	ld a, MAROWAK
.give
	jp BridgeGiveMon

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
	gift_entry GIFT_MON,        DITTO,          CopyCatGift1_Text, CopyCatGift1_Desc
	gift_entry GIFT_ITEM,       TM_MIMIC,       CopyCatGift2_Text, CopyCatGift2_Desc
	gift_entry GIFT_ITEM,       TM_PSYCHIC_M,   CopyCatGift3_Text, CopyCatGift3_Desc
	gift_entry GIFT_TEACH_MOVE, MIRROR_MOVE,    CopyCatGift4_Text, CopyCatGift4_Desc
	gift_entry GIFT_TEACH_MOVE, TRANSFORM,      CopyCatGift5_Text, CopyCatGift5_Desc
	gift_entry GIFT_ITEM,       NUGGET,         CopyCatGift6_Text, CopyCatGift6_Desc
	gift_entry GIFT_ITEM,       TM_SUBSTITUTE,  CopyCatGift7_Text, CopyCatGift7_Desc

BillGiftList:
	db 7
	gift_entry GIFT_MON,  DITTO,       BillGift1_Text, BillGift1_Desc
	gift_entry GIFT_MON,  EEVEE,       BillGift2_Text, BillGift2_Desc
	gift_entry GIFT_MON,  JOLTEON,     BillGift3_Text, BillGift3_Desc
	gift_entry GIFT_MON,  FLAREON,     BillGift4_Text, BillGift4_Desc
	gift_entry GIFT_MON,  VAPOREON,    BillGift5_Text, BillGift5_Desc
	gift_entry GIFT_ITEM, NUGGET,         BillGift6_Text, BillGift6_Desc
	gift_entry GIFT_ITEM, TM_THUNDERBOLT, BillGift7_Text, BillGift7_Desc

MrFujiGiftList:
	db 7
	gift_entry GIFT_ITEM,       POKE_FLUTE,         MrFujiGift1_Text, MrFujiGift1_Desc
	gift_entry GIFT_SPECIAL,    BridgeMrFujiRescue, MrFujiGift2_Text, MrFujiGift2_Desc
	gift_entry GIFT_SPECIAL,    BridgeMrFujiCubone, MrFujiGift3_Text, MrFujiGift3_Desc
	gift_entry GIFT_MON,        FLAREON,            MrFujiGift4_Text, MrFujiGift4_Desc
	gift_entry GIFT_TEACH_MOVE, NIGHT_SHADE,        MrFujiGift5_Text, MrFujiGift5_Desc
	gift_entry GIFT_TEACH_MOVE, CONFUSE_RAY,        MrFujiGift6_Text, MrFujiGift6_Desc
	gift_entry GIFT_TEACH_MOVE, LICK,               MrFujiGift7_Text, MrFujiGift7_Desc

CaptainGiftList:
	db 3
	gift_entry GIFT_ITEM, HM_CUT,    CaptainGift1_Text, CaptainGift1_Desc
	gift_entry GIFT_MON,  TENTACOOL, CaptainGift2_Text, CaptainGift2_Desc
	gift_entry GIFT_MON,  KRABBY,    CaptainGift3_Text, CaptainGift3_Desc

FossilScientistGiftList:
	db 3
	gift_entry GIFT_MON,  OMANYTE,   FossilGift1_Text, FossilGift1_Desc
	gift_entry GIFT_MON,  KABUTO,    FossilGift2_Text, FossilGift2_Desc
	gift_entry GIFT_ITEM, FIRE_STONE, FossilGift3_Text, FossilGift3_Desc

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

; Gift 1 (PIKACHU) is a plain mon gift for now; Phase B4 upgrades it to a
; GIFT_SPECIAL routine that also applies the Light-Ball special form.
OaksLabOakGiftList:
	db 3
	gift_entry GIFT_MON,  PIKACHU,    OaksLabGift1_Text, OaksLabGift1_Desc
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
CaptainGift3_Text: db "KRABBY@"

FossilGift1_Text: db "OMANYTE@"
FossilGift2_Text: db "KABUTO@"
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
