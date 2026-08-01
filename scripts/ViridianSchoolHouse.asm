; Repurposed as a bridge gift room - Cooltrainer F is the gift giver
; (SchoolCooltrainerGiftList in bridge_gift_menu.asm).
ViridianSchoolHouse_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	jp EnableAutoTextBoxDrawing

ViridianSchoolHouse_TextPointers:
	def_text_pointers
	dw_const ViridianSchoolHouseBrunetteGirlText, TEXT_VIRIDIANSCHOOLHOUSE_BRUNETTE_GIRL
	dw_const ViridianSchoolHouseCooltrainerFText, TEXT_VIRIDIANSCHOOLHOUSE_COOLTRAINER_F
	dw_const ViridianSchoolHouse_Gift_Text, TEXT_VIRIDIANSCHOOLHOUSE_GIFT_1
	EXPORT TEXT_VIRIDIANSCHOOLHOUSE_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

ViridianSchoolHouseBrunetteGirlText:
	text_far _ViridianSchoolHouseBrunetteGirlText
	text_end

ViridianSchoolHouseCooltrainerFText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .IntroText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_VIRIDIANSCHOOLHOUSE_GIFT_1
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
	text_far _ViridianSchoolHouseCooltrainerFText
	text_end

.AlreadyGotText:
	text_far _ViridianSchoolHouseCooltrainerFAlreadyGotText
	text_end

ViridianSchoolHouse_Gift_Text:
	script_bridge_gift
