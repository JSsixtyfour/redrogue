GetQuantityOfItemInBag:
; In: b = item ID
; Out: b = how many of that item are in the bag (0 if none)
	call GetPredefRegisters
	; Set wCurItem for the ROMX functions that use it
	ld a, b
	ld [wCurItem], a
	; TMs/HMs: owned = qty 1, not owned = 0
	push bc
	farcall IsTMHMItem
	pop bc
	jr nc, .notTMHM
	push bc
	farcall HasTMHM        ; Z = not owned, NZ = owned
	pop bc
	jr z, .zero
	ld b, 1
	ret
.notTMHM
	; Key pocket items: active (in bag) = qty 1
	push bc
	farcall IsKeyPocketItem
	pop bc
	jr nc, .notKeyPocket
	push bc
	farcall IsKeyItemActive    ; Z = not active, NZ = active
	pop bc
	jr z, .zero
	ld b, 1
	ret
.notKeyPocket
	; Recovery/Stat/Valuable: quantity is the count from the count array
	push bc
	farcall GetPocketItemCount ; a = count (0 if not in any count-array pocket)
	ld c, a
	pop bc
	ld a, c
	and a
	jr nz, .gotCount   ; found in a count array
	; Uncategorized: scan legacy wBagItems
.loop
	ld hl, wNumBagItems
	ld hl, wBagItems - 1
.scanLoop
	inc hl
	ld a, [hli]
	cp $ff
	jr z, .zero
	cp b
	jr nz, .scanLoop
	ld a, [hl]
	ld b, a
	ret
.gotCount
	ld b, a
	ret
.zero
	ld b, 0
	ret


; marcelnote - determines the index of an item in the player's bag
GetIndexOfItemInBag:
; In: b = item ID
; Out: b = index of item in bag ($FF if not found)
	call GetPredefRegisters
	ld hl, wBagItems - 1
	ld c, -1
.loop
	inc c
	inc hl
	ld a, [hli]
	cp $ff
	jr z, .notInBag
	cp b
	jr nz, .loop
	ld b, c
	ret
.notInBag
	ld b, $FF
	ret
