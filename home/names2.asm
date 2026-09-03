NamePointers::
; entries correspond to *_NAME constants
	dw MonsterNames
	dw MoveNames
	dw UnusedBadgeNames
	dw ItemNames
	dw wPartyMonOT ; player's OT names list
	dw wEnemyMonOT ; enemy's OT names list
	dw TrainerNames

GetName::
; arguments:
; [wNameListIndex] = which name
; [wNameListType] = which list
; [wPredefBank] = bank of list
;
; returns pointer to name in de
	ld a, [wNameListIndex]
	ld [wNamedObjectIndex], a

	; TM/HM names are not stored in ItemNames, so an ITEM index at or above HM01
	; has to be resolved by GetMachineName instead.
	;
	; Vanilla ran this test HERE, before dispatching on wNameListType, and its
	; own comment flagged it as a bug: it hijacked EVERY list, so any Pokemon,
	; move or trainer index >= $C4 came back as "TM07". Three ASSERTs existed
	; solely to keep those lists below the threshold, and the Pokemon one capped
	; NUM_POKEMON_INDEXES at 195 - a hard wall for the species expansion.
	;
	; Gating on ITEM_NAME fixes the bug at its root and frees species indexes to
	; run to $FE. The move and trainer asserts are dropped with it; both counts
	; are nowhere near $C4, and they are no longer load-bearing now that only the
	; item list consults HM01. Tail-call semantics are unchanged - GetMachineName
	; still returns straight to GetName's caller.
	ld a, [wNameListType]
	cp ITEM_NAME
	jr nz, .notMachineName
	ld a, [wNameListIndex]
	cp HM01
	jp nc, GetMachineName
.notMachineName

	ldh a, [hLoadedROMBank]
	push af
	push hl
	push bc
	push de
	ld a, [wNameListType]
	dec a
	jr nz, .otherEntries
	; 1 = MONSTER_NAME
	call GetMonName
	ld hl, NAME_LENGTH
	add hl, de
	ld e, l
	ld d, h
	jr .gotPtr
.otherEntries
	; 2-7 = other names
	ld a, [wPredefBank]
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ld a, [wNameListType]
	dec a
	add a
	ld d, 0
	ld e, a
	jr nc, .skip
	inc d
.skip
	ld hl, NamePointers
	add hl, de
	ld a, [hli]
	ldh [hSwapTemp + 1], a
	ld a, [hl]
	ldh [hSwapTemp], a
	ldh a, [hSwapTemp]
	ld h, a
	ldh a, [hSwapTemp + 1]
	ld l, a
	ld a, [wNameListIndex]
	ld b, a ; wanted entry
	ld c, 0 ; entry counter
.nextName
	ld d, h
	ld e, l
.nextChar
	ld a, [hli]
	cp '@'
	jr nz, .nextChar
	inc c
	ld a, b
	cp c
	jr nz, .nextName
	ld h, d
	ld l, e
	ld de, wNameBuffer
	ld bc, NAME_BUFFER_LENGTH
	call CopyData
.gotPtr
	pop de
	pop bc
	pop hl
	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ret
