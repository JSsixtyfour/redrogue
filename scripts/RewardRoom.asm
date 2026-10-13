

RewardRoom_Script:
    CheckEvent EVENT_ENTER_ROOM
    jr nz, .step_forward
    
    rfarcall RentalSettleZoneReturn
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
    farcall RoguePairRewardRoomObjects ; the balls and the route's item ball
    jr .objectsReady
.runStartObjects
    ; Explicitly: stages share these toggles and nothing resets them per run, so
    ; the last run's last stage could leave a ball taken or the trade NPC up.
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
    ld [wToggleableObjectIndex], a
    predef ShowObject
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
    ld [wToggleableObjectIndex], a
    predef ShowObject
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
    ld [wToggleableObjectIndex], a
    predef ShowObject
    ld a, TOGGLE_ROGUE_TRADE_NPC
    ld [wToggleableObjectIndex], a
    predef HideObject
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
    ; Objects 4-5 (the mid-run item ball, the trade NPC). Objects' texts come first, in slot order:
    ; DisplayTextID reroutes any script-fired id <= wNumSprites through a slot.
    dw_const RandomPickUpItemText,                   TEXT_REWARDROOM_RANDOM_ITEM
    dw_const RewardRoomTradeNPCText,                 TEXT_REWARDROOM_TRADE_NPC
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

; The balls are a stage's balls (reward_poke_balls.asm): the offer's form, DVs
; and INFO page, at GetRewardMonLevel's level (STARTER_LEVEL at run start, the
; stage level on a back-to-back pair's mid-run visit).
Rogue_RewardRoom_Script_PokeballText_1:
	text_asm
	ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
	farcall Rogue_Reward_Script_PokeballText_1.noTrade
	jp TextScriptEnd

; The trade NPC: the full ball 1 routine, whose trade path runs while a trade is up.
RewardRoomTradeNPCText:
	text_asm
	ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
	farcall Rogue_Reward_Script_PokeballText_1
	jp TextScriptEnd

Rogue_RewardRoom_Script_PokeballText_2:
	text_asm
	ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
	farcall Rogue_Reward_Script_PokeballText_2
	jp TextScriptEnd

Rogue_RewardRoom_Script_PokeballText_3:
	text_asm
	ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
	farcall Rogue_Reward_Script_PokeballText_3
	jp TextScriptEnd

    Rogue_RewardRoom_Reward_Text:
	script_rogue_reward
