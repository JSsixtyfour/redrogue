

RewardRoom_Script:
    CheckEvent EVENT_ENTER_ROOM
    jr nz, .step_forward
    
    SetEvent EVENT_ENTER_ROOM
    ; Mid-run (a badge won) this is a back-to-back pair's stand-in for the skipped
    ; route, between gym A and the lobby (RoguePairRewardRoomEntry, gym_statues.asm).
    ld a, [wObtainedBadges]
    and a
    jr z, .runStart
    farcall RoguePairRewardRoomEntry
    jr .exitsReady
.runStart
    ; Pick the next random stage and patch exit warps before the player can walk out.
    ; Uses SelectAndPatchRewardRoomExit (no BIT_WARP_FROM_CUR_SCRIPT).
    farcall SelectAndPatchRewardRoomExit
.exitsReady
    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    ld a, [wObtainedBadges]
    and a
    jr z, .runStartObjects
    farcall RoguePairRewardRoomObjects ; the route's item ball, not the flat-level balls
    jr .objectsReady
.runStartObjects
    ld a, TOGGLE_STAGE_RANDOM_ITEM
    ld [wToggleableObjectIndex], a
    predef HideObject
.objectsReady
    
    call EnableAutoTextBoxDrawing
	call Delay3
	ld hl, wSimulatedJoypadStatesEnd
	ld de, PlayerEntryMovementRLE
	call DecodeRLEList
	dec a
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
    
    .step_forward
    CheckEvent EVENT_STEP_FORWARD
    jr nz, .default
    ld a, [wYCoord]
	cp 6 ; has player stepped forward
    jr nz, .default
    
    call Delay3
    xor a
    ld a, LOW(TEXT_REWARDROOM_REWARD_VENDOR_1)
	ldh [hTextID], a
	call DisplayTextID
    SetEvent EVENT_STEP_FORWARD

    .default
	jp EnableAutoTextBoxDrawing

RewardRoom_TextPointers:
	def_text_pointers
	;dw_const Route2SignText,             TEXT_ROUTE2_OPTION_1
    ;dw_const Route2SignText,             TEXT_ROUTE2_OPTION_2
    dw_const Rogue_RewardRoom_Script_PokeballText_1, TEXT_ROGUE_REWARD_POKEBALL_1
    dw_const Rogue_RewardRoom_Script_PokeballText_2, TEXT_ROGUE_REWARD_POKEBALL_2
    dw_const Rogue_RewardRoom_Script_PokeballText_3, TEXT_ROGUE_REWARD_POKEBALL_3
    ; Object 4 (the mid-run item ball). Objects' texts come first, in slot order:
    ; DisplayTextID reroutes any script-fired id <= wNumSprites through a slot.
    dw_const RandomPickUpItemText,                   TEXT_REWARDROOM_RANDOM_ITEM
	dw_const RewardRoomDoor1SignText,    TEXT_REWARDROOM_DOOR1_SIGN
	dw_const RewardRoomDoor2SignText,    TEXT_REWARDROOM_DOOR2_SIGN
    dw_const Rogue_RewardRoom_Reward_Text, TEXT_REWARDROOM_REWARD_VENDOR_1
    EXPORT TEXT_REWARDROOM_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm

RewardRoomDoor1SignText:
	text_asm
	ld hl, RewardRoomLobbySignText
	ld a, [wObtainedBadges]
	and a
	jr nz, .print           ; mid-run: both doors lead back to the lobby
	ld a, [wRogueDoor1]
	ld hl, .itemPtrs
	ld d, 0
	ld e, a
	add hl, de
	add hl, de          ; hl += 2 * class (each entry is a dw)
	ld a, [hli]
	ld h, [hl]
	ld l, a
.print
	call PrintText
	jp TextScriptEnd
.itemPtrs
	dw .healingText
	dw .statText
	dw .tmText
	dw .moneyText
.healingText
	text "DOOR 1:"
	line "HEALING ITEMS@"
	text_end
.statText
	text "DOOR 1:"
	line "STAT BOOSTS@"
	text_end
.tmText
	text "DOOR 1:"
	line "TM ITEMS@"
	text_end
.moneyText
	text "DOOR 1:"
	line "MONEY@"
	text_end

RewardRoomDoor2SignText:
	text_asm
	ld hl, RewardRoomLobbySignText
	ld a, [wObtainedBadges]
	and a
	jr nz, .print           ; mid-run: both doors lead back to the lobby
	ld a, [wRogueDoor2]
	ld hl, .itemPtrs
	ld d, 0
	ld e, a
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
.print
	call PrintText
	jp TextScriptEnd
.itemPtrs
	dw .healingText
	dw .statText
	dw .tmText
	dw .moneyText
.healingText
	text "DOOR 2:"
	line "HEALING ITEMS@"
	text_end
.statText
	text "DOOR 2:"
	line "STAT BOOSTS@"
	text_end
.tmText
	text "DOOR 2:"
	line "TM ITEMS@"
	text_end
.moneyText
	text "DOOR 2:"
	line "MONEY@"
	text_end
	
RewardRoomLobbySignText:
	text "TO THE LOBBY@"
	text_end

PlayerEntryMovementRLE:
	db PAD_UP, 1
	db -1 ; end

Rogue_RewardRoom_Script_PokeballText_1:
	text_asm
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .done

    ld a, [wRoguePokemon1]
	ld b, a
    ld c, STARTER_LEVEL
	call GivePokemon
	jr nc, .done
    
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	jp TextScriptEnd
    
Rogue_RewardRoom_Script_PokeballText_2:
	text_asm
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon2]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .done

    ld a, [wRoguePokemon2]
	ld b, a
    ld c, STARTER_LEVEL
	call GivePokemon
	jr nc, .done
    
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	jp TextScriptEnd

Rogue_RewardRoom_Script_PokeballText_3:
	text_asm
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon3]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .done

    ld a, [wRoguePokemon3]
	ld b, a
    ld c, STARTER_LEVEL
	call GivePokemon
	jr nc, .done
    
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	jp TextScriptEnd
    
    PickRewardPokeballText:
	text_far _PickPokeBallText
	text_end
    
    GreedyText_Reward:
	text_far _GreedyText
	text_end
    
    Rogue_RewardRoom_Reward_Text:
	script_rogue_reward