; ---- Bridge PC ----------------------------------------------------------
; Defined in data/events/hidden_events.asm under
;   hidden_events_for IGAS_DOJO
;   hidden_event X, Y, OpenBridgeBillsPC, SPRITE_FACING_UP
; X,Y = the step the player faces (they stand at X,Y+1). Block (bx,by) of
; maps/IgasDojo.blk (DOJO tileset)
; covers steps x = 2bx..2bx+1, y = 2by..2by+1. Rules: "BRIDGE ROOM PCs" there.
; PC block $65 drawn at block (0,0) -> hotspots (0,1),(1,1).
; -------------------------------------------------------------------------
; Iga's Dojo (map id formerly LAVENDER_CUBONE_HOUSE). Iga is the bridge gift
; giver (IgaGiftList in bridge_gift_menu.asm).
IgasDojo_Script:
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

IgasDojo_TextPointers:
	def_text_pointers
	dw_const IgasDojoNidorinoText,       TEXT_IGASDOJO_NIDORINO
	dw_const IgasDojoIgaText, TEXT_IGASDOJO_IGA
    dw_const IgasDojoBoulderText,       TEXT_IGASDOJO_BOULDER
	dw_const IgasDojo_Gift_Text, TEXT_IGASDOJO_GIFT_1
	EXPORT TEXT_IGASDOJO_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

IgasDojoNidorinoText:
	text_far _IgasDojoNidorinoText
	text_asm
	ld a, NIDORINO
	call PlayCry
	jp TextScriptEnd

IgasDojoIgaText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .IntroText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_IGASDOJO_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, .AlreadyGotText
	call PrintText
.done
	jp TextScriptEnd

.AlreadyGotText:
	text_far _IgasDojoIgaAlreadyGotText
	text_end

.IntroText:
	text_far _IgasDojoIgaIntroText
	text_end

IgasDojo_Gift_Text:
	script_bridge_gift

IgasDojoBoulderText:
	text_far _IgasDojoBoulderText
	text_end