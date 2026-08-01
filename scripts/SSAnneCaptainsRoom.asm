; Repurposed as a bridge gift room - the vanilla back-rub minigame + HM01 grant
; is replaced by the standard bridge-gift dispatch (HM CUT is now one of the
; Captain's possible rolled gifts, CaptainGiftList in bridge_gift_menu.asm).
SSAnneCaptainsRoom_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	jp EnableAutoTextBoxDrawing

SSAnneCaptainsRoom_TextPointers:
	def_text_pointers
	dw_const SSAnneCaptainsRoomCaptainText,     TEXT_SSANNECAPTAINSROOM_CAPTAIN
	dw_const SSAnneCaptainsRoomTrashText,       TEXT_SSANNECAPTAINSROOM_TRASH
	dw_const SSAnneCaptainsRoomSeasickBookText, TEXT_SSANNECAPTAINSROOM_SEASICK_BOOK
	dw_const SSAnneCaptainsRoom_Gift_Text, TEXT_SSANNECAPTAINSROOM_GIFT_1
	EXPORT TEXT_SSANNECAPTAINSROOM_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

SSAnneCaptainsRoomCaptainText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, SSAnneCaptainsRoomCaptainIFeelMuchBetterText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_SSANNECAPTAINSROOM_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, SSAnneCaptainsRoomCaptainNotSickAnymoreText
	call PrintText
.done
	jp TextScriptEnd

SSAnneCaptainsRoomCaptainIFeelMuchBetterText:
	text_far _SSAnneCaptainsRoomCaptainIFeelMuchBetterText
	text_end

SSAnneCaptainsRoomCaptainNotSickAnymoreText:
	text_far _SSAnneCaptainsRoomCaptainNotSickAnymoreText
	text_end

SSAnneCaptainsRoom_Gift_Text:
	script_bridge_gift

SSAnneCaptainsRoomTrashText:
	text_far _SSAnneCaptainsRoomTrashText
	text_end

SSAnneCaptainsRoomSeasickBookText:
	text_far _SSAnneCaptainsRoomSeasickBookText
	text_end
