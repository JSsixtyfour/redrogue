MrFujisHouse_Script:
    CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
    farcall rogue_gift_randomized_batch   ; giver resolved from current map
    ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
    ResetEvent EVENT_BRIDGE_INTRO
    .afterSetup
	farcall PatchBridgeExit   ; if entered as a bridge, route the exit to the next stage
	; Force Mr. Fuji (the gift NPC) to appear - he is toggled OFF by default
	; (vanilla: only shows after the Pokemon Tower rescue). The other NPCs already
	; use their post-rescue text unconditionally.
	ld a, TOGGLE_MR_FUJIS_HOUSE_MR_FUJI
	ld [wToggleableObjectIndex], a
	predef ShowObject
	call EnableAutoTextBoxDrawing
	ret

MrFujisHouse_TextPointers:
	def_text_pointers
	dw_const MrFujisHouseSuperNerdText,     TEXT_MRFUJISHOUSE_SUPER_NERD
	dw_const MrFujisHouseLittleGirlText,    TEXT_MRFUJISHOUSE_LITTLE_GIRL
	dw_const MrFujisHousePsyduckText,       TEXT_MRFUJISHOUSE_PSYDUCK
	dw_const MrFujisHouseNidorinoText,      TEXT_MRFUJISHOUSE_NIDORINO
	dw_const MrFujisHouseMrFujiText,        TEXT_MRFUJISHOUSE_MR_FUJI
	dw_const MrFujisHouseMrFujiPokedexText, TEXT_MRFUJISHOUSE_POKEDEX
    dw_const MrFujisHouse_Gift_Text, TEXT_MRFUJISHOUSE_GIFT_1
    EXPORT TEXT_MRFUJISHOUSE_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

MrFujisHouseSuperNerdText:
	text_asm
	;CheckEvent EVENT_RESCUED_MR_FUJI
	;jr nz, .rescued_mr_fuji
	;ld hl, .MrFujiIsntHereText
	;call PrintText
	;jr .done
.rescued_mr_fuji
	ld hl, .MrFujiHadBeenPrayingText
	call PrintText
.done
	jp TextScriptEnd

.MrFujiIsntHereText:
	text_far _MrFujisHouseSuperNerdMrFujiIsntHereText
	text_end

.MrFujiHadBeenPrayingText:
	text_far _MrFujisHouseSuperNerdMrFujiHadBeenPrayingText
	text_end

MrFujisHouseLittleGirlText:
	text_asm
	;CheckEvent EVENT_RESCUED_MR_FUJI
	;jr nz, .rescued_mr_fuji
	;ld hl, .ThisIsMrFujisHouseText
	;call PrintText
	;jr .done
.rescued_mr_fuji
	ld hl, .PokemonAreNiceToHugText
	call PrintText
.done
	jp TextScriptEnd

.ThisIsMrFujisHouseText:
	text_far _MrFujisHouseLittleGirlThisIsMrFujisHouseText
	text_end

.PokemonAreNiceToHugText:
	text_far _MrFujisHouseLittleGirlPokemonAreNiceToHugText
	text_end

MrFujisHousePsyduckText:
	text_far _MrFujisHousePsyduckText
	text_asm
	ld a, PSYDUCK
	call PlayCry
	jp TextScriptEnd

MrFujisHouseNidorinoText:
	text_far _MrFujisHouseNidorinoText
	text_asm
	ld a, NIDORINO
	call PlayCry
	jp TextScriptEnd

MrFujisHouseMrFujiText:
	text_asm
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
    CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .IThinkThisMayHelpYourQuestText
	call PrintText
	
    SetEvent EVENT_BRIDGE_INTRO
    .skip_intro
	xor a
    ld a, TEXT_MRFUJISHOUSE_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
    call DisableWaitingAfterTextDisplay
	jr .done
    
	jr nc, .bag_full
	ld hl, .MrFujisHouseMrFujiKind
	call PrintText
	jr .done
.bag_full
	ld hl, .PokeFluteNoRoomText
	call PrintText
	jr .done
.got_item
	ld hl, .HasMyFluteHelpedYouText
	call PrintText
.done
	jp TextScriptEnd

.IThinkThisMayHelpYourQuestText:
	text_far _MrFujisHouseMrFujiIThinkThisMayHelpYourQuestText
	text_end

.ReceivedPokeFluteText:
	text_far _MrFujisHouseMrFujiReceivedPokeFluteText
	sound_get_key_item
	text_far _MrFujisHouseMrFujiPokeFluteExplanationText
	text_end

.PokeFluteNoRoomText:
	text_far _MrFujisHouseMrFujiPokeFluteNoRoomText
	text_end

.HasMyFluteHelpedYouText:
	text_far _MrFujisHouseMrFujiHasMyFluteHelpedYouText
	text_end
    
.MrFujisHouseMrFujiKind
    text_far _MrFujisHouseMrFujiKind
	text_end
    

MrFujisHouseMrFujiPokedexText:
	text_far _MrFujisHouseMrFujiPokedexText
	text_end

MrFujisHouse_Gift_Text:    
    script_bridge_gift