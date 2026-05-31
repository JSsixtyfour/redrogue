Route5_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh

    .normal
	call EnableAutoTextBoxDrawing
	ld hl, Route5TrainerHeaders
	ld de, Route5_ScriptPointers
	ld a, [wRoute5CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute5CurScript], a
	ret

Route5_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_ROUTE5_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE5_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE5_END_BATTLE

Route5_TextPointers:
	def_text_pointers
	dw_const Route5Youngster1Text,  TEXT_ROUTE5_YOUNGSTER1
	dw_const Route5Youngster2Text,  TEXT_ROUTE5_YOUNGSTER2
	dw_const Route5Lass1Text,       TEXT_ROUTE5_LASS1
	dw_const Route5Lass2Text,       TEXT_ROUTE5_LASS2
	dw_const Route5JrTrainerFText,  TEXT_ROUTE5_JR_TRAINER_F
    dw_const RandomPickUpItemText, TEXT_ROUTE5_RANDOM
    dw_const Route5_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE5_ROGUE_REWARD_POKEBALL_1
    dw_const Route5_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE5_ROGUE_REWARD_POKEBALL_2
    dw_const Route5_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE5_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_Route5_Reward_Text, TEXT_ROUTE5_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE5_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route5UndergroundPathSignText, TEXT_ROUTE5_UNDERGROUND_PATH_SIGN

Route5TrainerHeaders:
	def_trainers 1
Route5TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_5_TRAINER_0, 1, Route5Youngster1BattleText, Route5Youngster1EndBattleText, Route5Youngster1AfterBattleText
Route5TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_5_TRAINER_1, 1, Route5Youngster2BattleText, Route5Youngster2EndBattleText, Route5Youngster2AfterBattleText
Route5TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_5_TRAINER_2, 1, Route5Lass1BattleText, Route5Lass1EndBattleText, Route5Lass1AfterBattleText
Route5TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_5_TRAINER_3, 1, Route5Lass2BattleText, Route5Lass2EndBattleText, Route5Lass2AfterBattleText
Route5TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_5_TRAINER_4, 1, Route5JrTrainerFBattleText, Route5JrTrainerFEndBattleText, Route5JrTrainerFAfterBattleText
	db -1 ; end

Route5Youngster1Text:
	text_asm
	ld hl, Route5TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

Route5Youngster1BattleText:
	text_far _Route5Youngster1BattleText
	text_end

Route5Youngster1EndBattleText:
	text_far _Route5Youngster1EndBattleText
	text_end

Route5Youngster1AfterBattleText:
	text_far _Route5Youngster1AfterBattleText
	text_end

Route5Youngster2Text:
	text_asm
	ld hl, Route5TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

Route5Youngster2BattleText:
	text_far _Route5Youngster1BattleText
	text_end

Route5Youngster2EndBattleText:
	text_far _Route5Youngster1EndBattleText
	text_end

Route5Youngster2AfterBattleText:
	text_far _Route5Youngster1AfterBattleText
	text_end

Route5Lass1Text:
	text_asm
	ld hl, Route5TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

Route5Lass1BattleText:
	text_far _Route5Youngster1BattleText
	text_end

Route5Lass1EndBattleText:
	text_far _Route5Youngster1EndBattleText
	text_end

Route5Lass1AfterBattleText:
	text_far _Route5Youngster1AfterBattleText
	text_end

Route5Lass2Text:
	text_asm
	ld hl, Route5TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

Route5Lass2BattleText:
	text_far _Route5Youngster1BattleText
	text_end

Route5Lass2EndBattleText:
	text_far _Route5Youngster1EndBattleText
	text_end

Route5Lass2AfterBattleText:
	text_far _Route5Youngster1AfterBattleText
	text_end

Route5JrTrainerFText:
	text_asm
	ld hl, Route5TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

Route5JrTrainerFBattleText:
	text_far _Route5Youngster1BattleText
	text_end

Route5JrTrainerFEndBattleText:
	text_far _Route5Youngster1EndBattleText
	text_end

Route5JrTrainerFAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, Route5GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROUTE5_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route5UndergroundPathSignText:
	text_far _Route5UndergroundPathSignText
	text_end

Rogue_Route5_Reward_Text:
script_rogue_reward

Route5_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route5_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route5_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route5GreedyText:
	text_far _GreedyText
	text_end
