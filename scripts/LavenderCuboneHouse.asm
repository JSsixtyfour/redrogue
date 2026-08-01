; Repurposed as a bridge gift room - the Brunette Girl is the gift giver
; (CuboneHouseGirlGiftList in bridge_gift_menu.asm).
LavenderCuboneHouse_Script:
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

LavenderCuboneHouse_TextPointers:
	def_text_pointers
	dw_const LavenderCuboneHouseCuboneText,       TEXT_LAVENDERCUBONEHOUSE_CUBONE
	dw_const LavenderCuboneHouseBrunetteGirlText, TEXT_LAVENDERCUBONEHOUSE_BRUNETTE_GIRL
	dw_const LavenderCuboneHouse_Gift_Text, TEXT_LAVENDERCUBONEHOUSE_GIFT_1
	EXPORT TEXT_LAVENDERCUBONEHOUSE_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

LavenderCuboneHouseCuboneText:
	text_far _LavenderCuboneHouseCuboneText
	text_asm
	ld a, CUBONE
	call PlayCry
	jp TextScriptEnd

LavenderCuboneHouseBrunetteGirlText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .TheGhostIsGoneText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_LAVENDERCUBONEHOUSE_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, .PoorCubonesMotherText
	call PrintText
.done
	jp TextScriptEnd

.PoorCubonesMotherText:
	text_far _LavenderCuboneHouseBrunetteGirlPoorCubonesMotherText
	text_end

.TheGhostIsGoneText:
	text_far _LavenderCuboneHouseBrunetteGirlGhostIsGoneText
	text_end

LavenderCuboneHouse_Gift_Text:
	script_bridge_gift
