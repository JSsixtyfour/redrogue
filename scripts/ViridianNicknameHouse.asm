; Repurposed as a bridge gift room - Balding Guy is the gift giver
; (NicknameBaldingGuyGiftList in bridge_gift_menu.asm).
ViridianNicknameHouse_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	jp EnableAutoTextBoxDrawing

ViridianNicknameHouse_TextPointers:
	def_text_pointers
	dw_const ViridianNicknameHouseBaldingGuyText, TEXT_VIRIDIANNICKNAMEHOUSE_BALDING_GUY
	dw_const ViridianNicknameHouseLittleGirlText, TEXT_VIRIDIANNICKNAMEHOUSE_LITTLE_GIRL
	dw_const ViridianNicknameHouseSpearowText,    TEXT_VIRIDIANNICKNAMEHOUSE_SPEAROW
	dw_const ViridianNicknameHouseSpearySignText, TEXT_VIRIDIANNICKNAMEHOUSE_SPEARY_SIGN
	dw_const ViridianNicknameHouse_Gift_Text, TEXT_VIRIDIANNICKNAMEHOUSE_GIFT_1
	EXPORT TEXT_VIRIDIANNICKNAMEHOUSE_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

ViridianNicknameHouseBaldingGuyText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .IntroText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_VIRIDIANNICKNAMEHOUSE_GIFT_1
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
	text_far _ViridianNicknameHouseBaldingGuyText
	text_end

.AlreadyGotText:
	text_far _ViridianNicknameHouseBaldingGuyAlreadyGotText
	text_end

ViridianNicknameHouse_Gift_Text:
	script_bridge_gift

ViridianNicknameHouseLittleGirlText:
	text_far _ViridianNicknameHouseLittleGirlText
	text_end

ViridianNicknameHouseSpearowText:
	text_asm
	ld hl, .Text
	call PrintText
	ld a, SPEAROW
	call PlayCry
	call WaitForSoundToFinish
	jp TextScriptEnd

.Text:
	text_far _ViridianNicknameHouseSpearowText
	text_end

ViridianNicknameHouseSpearySignText:
	text_far _ViridianNicknameHouseSpearySignText
	text_end
