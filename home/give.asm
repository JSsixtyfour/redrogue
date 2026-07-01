GiveItem::
; Give player quantity c of item b,
; and copy the item's name to wStringBuffer.
; Return carry on success.
; TMs and HMs are routed to the bitfield instead of the bag.
	ld a, b
	ld [wNamedObjectIndex], a
	ld [wCurItem], a
	push bc
	farcall IsTMHMItem   ; carry set = is a TM or HM
	pop bc
	jr nc, .notTMHM
	farcall AcquireTMHM  ; marks b as owned in sTMBitfield, doesn't touch bag
	jr .getName
.notTMHM
	; Check if it's a key pocket item (LEFTOVERS, PP_TONIC, KO_DEFIANCE, EXP_ALL…)
	push bc
	farcall IsKeyPocketItem  ; carry set = key pocket item, c = bit_index
	pop bc
	jr nc, .notKeyPocketItem
	farcall AcquireKeyPocketItem  ; sets ownership bit, adds to carry slot if room
	jr .getName
.notKeyPocketItem
	ld a, c
	ld [wItemQuantity], a
	ld hl, wNumBagItems
	call AddItemToInventory
	ret nc
.getName
	call GetItemName
	call CopyToStringBuffer
	scf
	ret

GivePokemon::
; Give the player monster b at level c.
	ld a, b
	ld [wCurPartySpecies], a
	ld a, c
	ld [wCurEnemyLevel], a
	xor a ; PLAYER_PARTY_DATA
	ld [wMonDataLocation], a
	farjp _GivePokemon
