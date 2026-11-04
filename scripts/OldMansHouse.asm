; ---- Bridge PC ----------------------------------------------------------
; Defined in data/events/hidden_events.asm under
;   hidden_events_for OLD_MANS_HOUSE
;   hidden_event X, Y, OpenBridgeBillsPC, SPRITE_FACING_UP
; X,Y = the step the player faces (they stand at X,Y+1). Block (bx,by) of
; maps/OldMansHouse.blk (this room owns it; the chained vanilla houses are unused)
; covers steps x = 2bx..2bx+1, y = 2by..2by+1. Rules: "BRIDGE ROOM PCs" there.
; The bridge PC interaction is at (0,1).
; -------------------------------------------------------------------------
; Old Man's House bridge gift room.
; (OldManGiftList in bridge_gift_menu.asm).
OldMansHouse_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	jp EnableAutoTextBoxDrawing

OldMansHouse_TextPointers:
	def_text_pointers
	dw_const OldMansHouseBaldingGuyText, TEXT_OLDMANSHOUSE_BALDING_GUY
	dw_const OldMansHouse_Gift_Text, TEXT_OLDMANSHOUSE_GIFT_1
	EXPORT TEXT_OLDMANSHOUSE_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

OldMansHouseBaldingGuyText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .IntroText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_OLDMANSHOUSE_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, .AlreadyGotText
	call PrintText
.done
	jp TextScriptEnd

.IntroText:
	text_far _OldMansHouseBaldingGuyText
	text_end

.AlreadyGotText:
	text_far _OldMansHouseBaldingGuyAlreadyGotText
	text_end

OldMansHouse_Gift_Text:
	script_bridge_gift
