; ---- Bridge PC ----------------------------------------------------------
; Defined in data/events/hidden_events.asm under
;   hidden_events_for FLORAS_GROTTO
;   hidden_event X, Y, OpenBridgeBillsPC, SPRITE_FACING_UP
; X,Y = the step the player faces (they stand at X,Y+1). Block (bx,by) of
; maps/FlorasGrotto.blk (GYM tileset)
; covers steps x = 2bx..2bx+1, y = 2by..2by+1. Rules: "BRIDGE ROOM PCs" there.
; PC block $65 drawn at block (0,0) -> hotspots (0,1),(1,1).
; -------------------------------------------------------------------------
; Flora's Grotto (map id formerly CERULEAN_TRADE_HOUSE). Flora is the bridge
; gift giver (FloraGiftList in bridge_gift_menu.asm); the vanilla trader is gone.
FlorasGrotto_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	jp EnableAutoTextBoxDrawing

FlorasGrotto_TextPointers:
	def_text_pointers
	dw_const FlorasGrottoFloraText,  TEXT_FLORASGROTTO_FLORA
	dw_const FlorasGrotto_Gift_Text, TEXT_FLORASGROTTO_GIFT_1
	EXPORT TEXT_FLORASGROTTO_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

FlorasGrottoFloraText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .IntroText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_FLORASGROTTO_GIFT_1
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
	text_far _FlorasGrottoFloraText
	text_end

.AlreadyGotText:
	text_far _FlorasGrottoFloraAlreadyGotText
	text_end

FlorasGrotto_Gift_Text:
	script_bridge_gift
