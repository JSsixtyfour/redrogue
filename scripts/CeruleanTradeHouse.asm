; Repurposed as a bridge gift room - Granny is the gift giver
; (TradeHouseGrannyGiftList in bridge_gift_menu.asm). The Gambler's in-game
; trade offer is untouched.
CeruleanTradeHouse_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	jp EnableAutoTextBoxDrawing

CeruleanTradeHouse_TextPointers:
	def_text_pointers
	dw_const CeruleanTradeHouseGrannyText,  TEXT_CERULEANTRADEHOUSE_GRANNY
	dw_const CeruleanTradeHouseGamblerText, TEXT_CERULEANTRADEHOUSE_GAMBLER
	dw_const CeruleanTradeHouse_Gift_Text, TEXT_CERULEANTRADEHOUSE_GIFT_1
	EXPORT TEXT_CERULEANTRADEHOUSE_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

CeruleanTradeHouseGrannyText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .IntroText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_CERULEANTRADEHOUSE_GIFT_1
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
	text_far _CeruleanTradeHouseGrannyText
	text_end

.AlreadyGotText:
	text_far _CeruleanTradeHouseGrannyAlreadyGotText
	text_end

CeruleanTradeHouse_Gift_Text:
	script_bridge_gift

CeruleanTradeHouseGamblerText:
	text_asm
	ld a, TRADE_FOR_LOLA
	ld [wWhichTrade], a
	predef DoInGameTradeDialogue
	jp TextScriptEnd
