; uses an item
; UseItem is used with dummy items to perform certain other functions as well
; INPUT:
; [wCurItem] = item ID
; OUTPUT:
; [wActionResultOrTookBattleTurn] = success
; 00: unsuccessful
; 01: successful
; 02: not able to be used right now, no extra menu displayed (only certain items use this)
UseItem::
	rfarjp UseItem_

; checks if an item is a key item
; INPUT:
; [wCurItem] = item ID
; OUTPUT:
; [wIsKeyItem] = result
; 00: item is not key item
; 01: item is key item
IsKeyItem::
	push hl
	push de
	push bc
	rfarcall IsKeyItem_
	pop bc
	pop de
	pop hl
	ret
