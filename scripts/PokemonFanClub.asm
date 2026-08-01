; Repurposed as a bridge gift room - the Chairman's vanilla bike-voucher story
; is replaced by the standard bridge-gift dispatch (BIKE VOUCHER is now one of
; his possible rolled gifts, FanClubChairmanGiftList in bridge_gift_menu.asm).
PokemonFanClub_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	jp EnableAutoTextBoxDrawing

PokemonFanClub_TextPointers:
	def_text_pointers
	dw_const PokemonFanClubPikachuFanText,   TEXT_POKEMONFANCLUB_PIKACHU_FAN
	dw_const PokemonFanClubSeelFanText,      TEXT_POKEMONFANCLUB_SEEL_FAN
	dw_const PokemonFanClubPikachuText,      TEXT_POKEMONFANCLUB_PIKACHU
	dw_const PokemonFanClubSeelText,         TEXT_POKEMONFANCLUB_SEEL
	dw_const PokemonFanClubChairmanText,     TEXT_POKEMONFANCLUB_CHAIRMAN
	dw_const PokemonFanClubReceptionistText, TEXT_POKEMONFANCLUB_RECEPTIONIST
	dw_const PokemonFanClubSign1Text,        TEXT_POKEMONFANCLUB_SIGN_1
	dw_const PokemonFanClubSign2Text,        TEXT_POKEMONFANCLUB_SIGN_2
	dw_const PokemonFanClub_Gift_Text, TEXT_POKEMONFANCLUB_GIFT_1
	EXPORT TEXT_POKEMONFANCLUB_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

PokemonFanClubPikachuFanText:
	text_asm
	CheckEvent EVENT_PIKACHU_FAN_BOAST
	jr nz, .mineisbetter
	ld hl, .NormalText
	call PrintText
	SetEvent EVENT_SEEL_FAN_BOAST
	jr .done
.mineisbetter
	ld hl, .BetterText
	call PrintText
	ResetEvent EVENT_PIKACHU_FAN_BOAST
.done
	jp TextScriptEnd

.NormalText:
	text_far _PokemonFanClubPikachuFanNormalText
	text_end

.BetterText:
	text_far _PokemonFanClubPikachuFanBetterText
	text_end

PokemonFanClubSeelFanText:
	text_asm
	CheckEvent EVENT_SEEL_FAN_BOAST
	jr nz, .mineisbetter
	ld hl, .NormalText
	call PrintText
	SetEvent EVENT_PIKACHU_FAN_BOAST
	jr .done
.mineisbetter
	ld hl, .BetterText
	call PrintText
	ResetEvent EVENT_SEEL_FAN_BOAST
.done
	jp TextScriptEnd

.NormalText:
	text_far _PokemonFanClubSeelFanNormalText
	text_end

.BetterText:
	text_far _PokemonFanClubSeelFanBetterText
	text_end

PokemonFanClubPikachuText:
	text_asm
	ld hl, .Text
	call PrintText
	ld a, PIKACHU
	call PlayCry
	call WaitForSoundToFinish
	jp TextScriptEnd

.Text
	text_far _PokemonFanClubPikachuText
	text_end

PokemonFanClubSeelText:
	text_asm
	ld hl, .Text
	call PrintText
	ld a, SEEL
	call PlayCry
	call WaitForSoundToFinish
	jp TextScriptEnd

.Text:
	text_far _PokemonFanClubSeelText
	text_end

PokemonFanClubChairmanText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .StoryText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_POKEMONFANCLUB_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, .FinalText
	call PrintText
.done
	jp TextScriptEnd

.StoryText:
	text_far _PokemonFanClubChairmanStoryText
	text_end

.FinalText:
	text_far _PokemonFanClubChairFinalText
	text_end

PokemonFanClub_Gift_Text:
	script_bridge_gift

PokemonFanClubReceptionistText:
	text_far _PokemonFanClubReceptionistText
	text_end

PokemonFanClubSign1Text:
	text_far _PokemonFanClubSign1Text
	text_end

PokemonFanClubSign2Text:
	text_far _PokemonFanClubSign2Text
	text_end
