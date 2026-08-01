; Repurposed as a bridge gift room - the Fishing Guru is the gift giver
; (TrashedHouseFishingGuruGiftList in bridge_gift_menu.asm).
CeruleanTrashedHouse_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	call EnableAutoTextBoxDrawing
	ret

CeruleanTrashedHouse_TextPointers:
	def_text_pointers
	dw_const CeruleanTrashedHouseFishingGuruText, TEXT_CERULEANTRASHEDHOUSE_FISHING_GURU
	dw_const CeruleanTrashedHouseGirlText,        TEXT_CERULEANTRASHEDHOUSE_GIRL
	dw_const CeruleanTrashedHouseWallHoleText,    TEXT_CERULEANTRASHEDHOUSE_WALL_HOLE
	dw_const CeruleanTrashedHouse_Gift_Text, TEXT_CERULEANTRASHEDHOUSE_GIFT_1
	EXPORT TEXT_CERULEANTRASHEDHOUSE_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

CeruleanTrashedHouseFishingGuruText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .WhatsLostIsLostText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_CERULEANTRASHEDHOUSE_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, .TheyStoleATMText
	call PrintText
.done
	jp TextScriptEnd

.TheyStoleATMText:
	text_far _CeruleanTrashedHouseFishingGuruTheyStoleATMText
	text_end

.WhatsLostIsLostText:
	text_far _CeruleanTrashedHouseFishingGuruWhatsLostIsLostText
	text_end

CeruleanTrashedHouse_Gift_Text:
	script_bridge_gift

CeruleanTrashedHouseGirlText:
	text_far _CeruleanTrashedHouseGirlText
	text_end

CeruleanTrashedHouseWallHoleText:
	text_far _CeruleanTrashedHouseWallHoleText
	text_end
