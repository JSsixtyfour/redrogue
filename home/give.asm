GiveItem::
; Give player quantity c of item b, copy item name to wStringBuffer.
; Return carry on success.
; Routing: TM/HM → bitfield  | key pocket item → sKeyItemsBitfield
;          recovery/stat/valuable → count array  | else → legacy wBagItems
	ld a, b
	ld [wNamedObjectIndex], a
	ld [wCurItem], a
	push bc
	farcall IsTMHMItem     ; reads wCurItem (farcall clobbers b)
	pop bc
	jr nc, .notTMHM
	farcall AcquireTMHM
	jr .getName
.notTMHM
	push bc
	farcall IsKeyPocketItem
	pop bc
	jr nc, .notKeyPocketItem
	farcall AcquireKeyPocketItem
	; hSpriteOffset: 0=equipped, $FF=carry full (sent to PC)
	ldh a, [hSpriteOffset]
	and a
	jr z, .getName         ; equipped — normal "got item" message
	jr .sentToPC
.notKeyPocketItem
	ld a, c
	ld [wItemQuantity], a  ; save qty before farcalls clobber c
	; Each GiveXxxItem self-scans its table using wCurItem, returns carry set if matched.
	farcall GiveRecoveryItem
	jr c, .getName
	farcall GiveStatItem
	jr c, .getName
	farcall GiveValuableItem
	jr c, .getName
	; Uncategorized — legacy wBagItems (should be empty in normal play)
	ld hl, wNumBagItems
	call AddItemToInventory
	ret nc
.getName
	call GetItemName
	call CopyToStringBuffer
	scf
	ret
.sentToPC
	; Carry slots were full — item is owned but not equipped (sent to PC storage).
	call GetItemName
	call CopyToStringBuffer
	; The caller (rogue reward menu etc.) will print the name from wStringBuffer.
	; Flag via carry clear so callers can optionally show "sent to PC" message.
	and a    ; carry clear = sent to PC
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
