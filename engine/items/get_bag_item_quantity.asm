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
; Count comes back in e: a holds the caller's bank after a farcall. This used to
; read a into c and then `pop bc` over it, so every Recovery/Stat/Valuable item
; reported the caller's c as its quantity (fixed 2026-09-24).
	push bc
	push de
	farcall GetPocketItemCountInE ; e = count (0 if not in any count-array pocket)
	ld a, e
	pop de
	pop bc
	; 0 also covers every item in no pocket: those are never stored (GiveItem).
	ld b, a
	ret
.zero
	ld b, 0
	ret
