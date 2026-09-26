; ---- Bridge PC ----------------------------------------------------------
; Defined in data/events/hidden_events.asm under
;   hidden_events_for CINNABAR_LAB_FOSSIL_ROOM
;   hidden_event X, Y, OpenBridgeBillsPC, SPRITE_FACING_UP
; X,Y = the step the player faces (they stand at X,Y+1). Block (bx,by) of
; maps/CinnabarLabFossilRoom.blk
; covers steps x = 2bx..2bx+1, y = 2by..2by+1. Rules: "BRIDGE ROOM PCs" there.
; Uses its vanilla PCs at (0,4),(2,4) (OpenPokemonCenterPC).
; -------------------------------------------------------------------------
; Repurposed as a bridge gift room - Scientist 1's vanilla fossil-revival
; state machine is replaced by the standard bridge-gift dispatch
; (FossilScientistGiftList in bridge_gift_menu.asm). Scientist 2's in-game
; trade is untouched.
CinnabarLabFossilRoom_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	jp EnableAutoTextBoxDrawing

CinnabarLabFossilRoom_TextPointers:
	def_text_pointers
	dw_const CinnabarLabFossilRoomScientist1Text, TEXT_CINNABARLABFOSSILROOM_SCIENTIST1
	dw_const CinnabarLabFossilRoomScientist2Text, TEXT_CINNABARLABFOSSILROOM_SCIENTIST2
	dw_const CinnabarLabFossilRoom_Gift_Text, TEXT_CINNABARLABFOSSILROOM_GIFT_1
	EXPORT TEXT_CINNABARLABFOSSILROOM_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

CinnabarLabFossilRoomScientist1Text:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .Text
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_CINNABARLABFOSSILROOM_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, .ComeAgainText
	call PrintText
.done
	jp TextScriptEnd

.Text:
	text_far _CinnabarLabFossilRoomScientist1Text
	text_end

.ComeAgainText:
	text_far _CinnabarLabFossilRoomScientist1ComeAgainText
	text_end

CinnabarLabFossilRoom_Gift_Text:
	script_bridge_gift

CinnabarLabFossilRoomScientist2Text:
	text_far _CinnabarLabFossilRoomScientist2Text
	text_end
