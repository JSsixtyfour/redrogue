; custom_functions/item_descriptions.asm
; Item descriptions for the bag's info box and the mart clerk's text box.
; PrintBagInfoText (custom_functions/tm_bag.asm) farcalls PrintItemDescription
; on every cursor move. Section "Item Descriptions", pinned in layout.link.

; Both boxes are 14 tiles wide inside. '#' prints as four tiles (POKé).
DEF ITEM_DESC_WIDTH EQU 14

; Scratch for a TM's move data, the same spot LearndexDrawInfoStrip uses:
; wMoveBuffer is wTextBoxBuffer, whose first 36 bytes hold the mart's saved
; "Take your time." text for PrintBagInfoText's restore path, so stay past them.
DEF ITEM_DESC_SCRATCH EQUS "wMoveBuffer + 80"
	; +0 power, +1 type, +2 accuracy, +3 PP, +4/+5 type name pointer,
	; +6.. type name (8 chars + '@')

; PrintItemDescription
; in:  e = item id
;      d = layout: 0 = the bag's info box (rows 15-16 at column 5, under the
;          pocket label), nonzero = the clerk's text box (rows 14 and 16 at
;          column 1, the vanilla text lines)
; The caller has already blanked both lines. Items without an entry print
; nothing. TMs/HMs print their move's type, PP, power and accuracy.
; Clobbers everything.
PrintItemDescription::
	ld a, d
	and a
	ld bc, SCREEN_WIDTH       ; bag: the second line is the next row
	hlcoord 5, 15
	jr z, .gotLayout
	ld bc, 2 * SCREEN_WIDTH   ; clerk: double spaced
	hlcoord 1, 14
.gotLayout
	push bc                   ; line step
	push hl                   ; line 1
	ld a, e
	cp HM01
	jr nc, .machine
	ld hl, ItemDescriptions
.find
	ld a, [hli]
	cp -1
	jr z, .none
	cp e
	jr z, .found
	call .skipString
	call .skipString
	jr .find

.none
	pop hl
	pop bc
	ret

.skipString
	ld a, [hli]
	cp '@'
	jr nz, .skipString
	ret

.found
	ld d, h
	ld e, l
	pop hl
	pop bc
	push bc
	push hl
	call PlaceString          ; leaves de on line 1's '@'; clobbers bc
	inc de
	pop hl
	pop bc
	add hl, bc
	jp PlaceString

.machine
	; item id -> TM/HM number as TMToMove expects: TMs 1-50, HMs 51-55
	sub TM01
	jr nc, .isTM
	add NUM_TMS + NUM_HMS
.isTM
	inc a
	ld [wTempTMHM], a
	predef TMToMove           ; wTempTMHM = move id
	; Moves (bank $0E) and TypeNames (bank $09) are read through FarCopyData:
	; a plain [hl] here would read this bank. See LearndexDrawInfoStrip.
	ld a, [wTempTMHM]
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld bc, MOVE_POWER
	add hl, bc
	ld de, ITEM_DESC_SCRATCH
	ld bc, MOVE_LENGTH - MOVE_POWER ; power, type, accuracy, PP
	ASSERT MOVE_TYPE == MOVE_POWER + 1 && MOVE_ACC == MOVE_POWER + 2 \
		&& MOVE_PP == MOVE_POWER + 3 && MOVE_LENGTH == MOVE_POWER + 4
	ld a, BANK(Moves)
	call FarCopyData
	ld a, [ITEM_DESC_SCRATCH + 1] ; type
	add a
	ld c, a
	ld b, 0
	ld hl, TypeNames
	add hl, bc
	ld de, ITEM_DESC_SCRATCH + 4
	ld bc, 2
	ld a, BANK(TypeNames)
	call FarCopyData
	ld a, [ITEM_DESC_SCRATCH + 4]
	ld l, a
	ld a, [ITEM_DESC_SCRATCH + 5]
	ld h, a
	ld de, ITEM_DESC_SCRATCH + 6
	ld bc, 9                  ; FIGHTING/ELECTRIC + '@'
	ld a, BANK(TypeNames)
	call FarCopyData

	; line 1: "ELECTRIC  PP15"
	pop hl
	push hl
	ld de, ITEM_DESC_SCRATCH + 6
	call PlaceString
	pop hl
	push hl
	ld bc, ITEM_DESC_WIDTH - 4
	add hl, bc
	ld a, 'P'
	ld [hli], a
	ld [hli], a
	ld de, ITEM_DESC_SCRATCH + 3
	lb bc, 1, 2
	call PrintNumber

	; line 2: "PWR 95 ACC100%"
	pop hl
	pop bc
	add hl, bc
	push hl
	ld a, 'P'
	ld [hli], a
	ld a, 'W'
	ld [hli], a
	ld a, 'R'
	ld [hli], a
	ld a, [ITEM_DESC_SCRATCH]
	cp 2
	jr nc, .power
	; 0 = status move, 1 = set or variable damage (SEISMIC TOSS, PSYWAVE...)
	inc hl
	inc hl
	ld [hl], '-'
	jr .accuracy
.power
	ld de, ITEM_DESC_SCRATCH
	lb bc, 1, 3
	call PrintNumber
.accuracy
	; 0-255 -> percent, LearndexDrawInfoStrip's formula: (acc * 100 + 255) / 256
	ld a, [ITEM_DESC_SCRATCH + 2]
	ld c, a
	ld b, 0
	ld hl, 255
	ld a, 100
	call AddNTimes
	ld a, h
	ld [ITEM_DESC_SCRATCH + 2], a
	pop hl
	push hl
	ld bc, 7
	add hl, bc
	ld a, 'A'
	ld [hli], a
	ld a, 'C'
	ld [hli], a
	ld [hli], a
	ld de, ITEM_DESC_SCRATCH + 2
	lb bc, 1, 3
	call PrintNumber
	pop hl
	ld bc, ITEM_DESC_WIDTH - 1
	add hl, bc
	ld [hl], '%'
	ret

; item_desc ITEM, "line 1", "line 2" - each line at most ITEM_DESC_WIDTH
; tiles, counting '#' as the four it prints (so "#MON" is 7). Order does not matter; an item
; listed twice shows its first entry.
MACRO item_desc
	ASSERT CHARLEN(STRRPL(\2, "#", "POKé")) <= ITEM_DESC_WIDTH, \
		"item_desc \1: line 1 wider than 14 tiles: \2"
	ASSERT CHARLEN(STRRPL(\3, "#", "POKé")) <= ITEM_DESC_WIDTH, \
		"item_desc \1: line 2 wider than 14 tiles: \3"
	ASSERT (\1) != 0 && (\1) < HM01, "item_desc \1: not a describable item"
	db \1
	db \2, "@", \3, "@"
ENDM

INCLUDE "data/items/descriptions.asm"

; e = highlighted item ($ff = CANCEL). Called only in active credit lists.
; The preview is refreshed before input and after scrolling. Clear CANCEL too,
; so a previous item's benefit cannot linger under the cancel row.
PrintCreditUpgradeInfo::
	push de
	hlcoord 1, 14
	lb bc, 3, 18
	call ClearScreenArea
	pop de
	ld a, e
	cp $ff
	ret z
	ld [wCurItem], a
	ld a, [wWhichPrizeWindow]
	and a
	jr nz, .upgrade
	ld d, 1
	jp PrintItemDescription
.upgrade
	farcall GetKeyItemTierInE
	ld a, e
	cp MAX_KEY_ITEM_TIER
	ret nc
	push af
	ld a, [wCurItem]
	ld hl, CreditUpgradeInfoTable
.find
	cp [hl]
	jr z, .found
	ld bc, 73 ; item id + two tiers, each two 18-byte terminated lines
	add hl, bc
	jr .find
.found
	inc hl
	pop af
	and a
	jr z, .tierReady
	ld bc, 36
	add hl, bc
.tierReady
	push hl
	ld d, h
	ld e, l
	hlcoord 1, 14
	call PlaceString
	pop hl
	ld bc, 18
	add hl, bc
	ld d, h
	ld e, l
	hlcoord 1, 16
	jp PlaceString

CreditUpgradeInfoTable:
	db LEFTOVERS
	db "T2 HP 1/16▶1/12  @"
	db "After each battle@"
	db "T3 HP 1/12▶1/8   @"
	db "After each battle@"
	db PP_TONIC
	db "T2 PP 1/16▶1/14  @"
	db "After each battle@"
	db "T3 PP 1/14▶1/12  @"
	db "After each battle@"
	db KO_DEFIANCE
	db "T2 Saves 1▶2     @"
	db "Per run          @"
	db "T3 Saves 2▶3     @"
	db "Per run          @"
	db SHINY_CHARM
	db "T2 1/128▶1/64    @"
	db "Shiny odds       @"
	db "T3 1/64▶1/32     @"
	db "Shiny odds       @"
	db AMULET_COIN
	db "T2 +10%▶+15%     @"
	db "Prize money      @"
	db "T3 +15%▶+20%     @"
	db "Prize money      @"
	db TURN_REWIND
	db "T2 Rewinds 2▶3   @"
	db "Per run          @"
	db "T3 Rewinds 3▶4   @"
	db "Per run          @"
	db RARE_SCOPE
	db "T2 +31▶+63 /256  @"
	db "Wild rarity roll @"
	db "T3 +63▶+95 /256  @"
	db "Wild rarity roll @"
	db RARE_LENS
	db "T2 +12▶+25 /256  @"
	db "Item rarity roll @"
	db "T3 +25▶+38 /256  @"
	db "Item rarity roll @"
	db DV_BOOSTER
	db "T2 Min. DV 6▶10  @"
	db "New party members@"
	db "T3 Min. DV 10▶13 @"
	db "New party members@"
	db STAT_BOOSTER
	db "T2 Stat EXP 2x▶3x@"
	db "From battles     @"
	db "T3 Stat EXP 3x▶4x@"
	db "From battles     @"
	db DOOR_DICE
	db "T2 Rerolls 1▶2   @"
	db "Per run          @"
	db "T3 Rerolls 2▶3   @"
	db "Per run          @"
	db MON_DICE
	db "T2 Rerolls 1▶2   @"
	db "Per run          @"
	db "T3 Rerolls 2▶3   @"
	db "Per run          @"
	db ITEM_DICE
	db "T2 Rerolls 1▶2   @"
	db "Per run          @"
	db "T3 Rerolls 2▶3   @"
	db "Per run          @"
	db ELEMENT_PRISM
	db "T2 +10%▶+15%     @"
	db "Typed move damage@"
	db "T3 +15%▶+20%     @"
	db "Typed move damage@"
