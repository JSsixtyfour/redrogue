; Repurposed as a bridge gift room - the Warden's vanilla gold-teeth/HM04
; state machine is replaced by the standard bridge-gift dispatch (HM STRENGTH
; is now one of his possible rolled gifts, WardenGiftList in bridge_gift_menu.asm).
WardensHouse_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	jp EnableAutoTextBoxDrawing

WardensHouse_TextPointers:
	def_text_pointers
	dw_const WardensHouseWardenText,  TEXT_WARDENSHOUSE_WARDEN
	dw_const PickUpItemText,          TEXT_WARDENSHOUSE_RARE_CANDY
	dw_const BoulderText,             TEXT_WARDENSHOUSE_BOULDER
	dw_const WardensHouseDisplayText, TEXT_WARDENSHOUSE_DISPLAY_LEFT
	dw_const WardensHouseDisplayText, TEXT_WARDENSHOUSE_DISPLAY_RIGHT
	dw_const WardensHouse_Gift_Text, TEXT_WARDENSHOUSE_GIFT_1
	EXPORT TEXT_WARDENSHOUSE_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

WardensHouseWardenText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .ThanksText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_WARDENSHOUSE_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, .Gibberish1Text
	call PrintText
.done
	jp TextScriptEnd

.Gibberish1Text:
	text_far _WardensHouseWardenGibberish1Text
	text_end

.ThanksText:
	text_far _WardensHouseWardenThanksText
	text_end

WardensHouse_Gift_Text:
	script_bridge_gift

WardensHouseDisplayText:
	text_asm
	ldh a, [hTextID]
	cp TEXT_WARDENSHOUSE_DISPLAY_LEFT
	ld hl, .MerchandiseText
	jr nz, .print_text
	ld hl, .PhotosAndFossilsText
.print_text
	call PrintText
	jp TextScriptEnd

.PhotosAndFossilsText:
	text_far _WardensHouseDisplayPhotosAndFossilsText
	text_end

.MerchandiseText:
	text_far _WardensHouseDisplayMerchandiseText
	text_end
