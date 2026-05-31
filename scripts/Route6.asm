Route6_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh

    .normal
	call EnableAutoTextBoxDrawing
	ld hl, Route6TrainerHeaders
	ld de, Route6_ScriptPointers
	ld a, [wRoute6CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute6CurScript], a
	ret

Route6_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_ROUTE6_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE6_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE6_END_BATTLE

Route6_TextPointers:
	def_text_pointers
	dw_const Route6JrTrainerM1Text,       TEXT_ROUTE6_JR_TRAINER_M1
	dw_const Route6JrTrainerF1Text,       TEXT_ROUTE6_JR_TRAINER_F1
	dw_const Route6BugCatcherText,          TEXT_ROUTE6_BUG_CATCHER
	dw_const Route6JrTrainerM2Text,       TEXT_ROUTE6_JR_TRAINER_M2
	dw_const Route6JrTrainerF2Text,       TEXT_ROUTE6_JR_TRAINER_F2
    dw_const RandomPickUpItemText,          TEXT_ROUTE6_RANDOM
    dw_const Route6_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE6_ROGUE_REWARD_POKEBALL_1
    dw_const Route6_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE6_ROGUE_REWARD_POKEBALL_2
    dw_const Route6_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE6_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_Route6_Reward_Text,      TEXT_ROUTE6_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE6_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route6UndergroundPathSignText, TEXT_ROUTE6_UNDERGROUND_PATH_SIGN

Route6TrainerHeaders:
	def_trainers 1
Route6TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_6_TRAINER_0, 1, Route6JrTrainerM1BattleText, Route6JrTrainerM1EndBattleText, Route6JrTrainerAfterBattleText
Route6TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_6_TRAINER_1, 1, Route6JrTrainerF1BattleText, Route6JrTrainerF1EndBattleText, Route6JrTrainerAfterBattleText
Route6TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_6_TRAINER_2, 1, Route6BugCatcherBattleText, Route6BugCatcherEndBattleText, Route6BugCatcherAfterBattleText
Route6TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_6_TRAINER_3, 1, Route6JrTrainerM2BattleText, Route6JrTrainerM2EndBattleText, Route6JrTrainerM2AfterBattleText
Route6TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_6_TRAINER_4, 1, Route6JrTrainerF2BattleText, Route6JrTrainerF2EndBattleText, Route6JrTrainerF2AfterBattleText
	db -1 ; end

Route6JrTrainerM1Text:
	text_asm
	ld hl, Route6TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

Route6JrTrainerM1BattleText:
	text_far _Route6JrTrainerM1BattleText
	text_end

Route6JrTrainerM1EndBattleText:
	text_far _Route6JrTrainerM1EndBattleText
	text_end

Route6JrTrainerAfterBattleText: ; used by both COOLTRAINER_M1 and COOLTRAINER_F1
	text_far _Route6JrTrainerAfterBattleText
	text_end

Route6JrTrainerF1Text:
	text_asm
	ld hl, Route6TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

Route6JrTrainerF1BattleText:
	text_far _Route6JrTrainerF1BattleText
	text_end

Route6JrTrainerF1EndBattleText:
	text_far _Route6JrTrainerF1EndBattleText
	text_end

Route6BugCatcherText:
	text_asm
	ld hl, Route6TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

Route6BugCatcherBattleText:
	text_far _Route6BugCatcherBattleText
	text_end

Route6BugCatcherEndBattleText:
	text_far _Route6BugCatcherEndBattleText
	text_end

Route6BugCatcherAfterBattleText:
	text_far _Route6BugCatcherAfterBattleText
	text_end

Route6JrTrainerM2Text:
	text_asm
	ld hl, Route6TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

Route6JrTrainerM2BattleText:
	text_far _Route6JrTrainerM2BattleText
	text_end

Route6JrTrainerM2EndBattleText:
	text_far _Route6JrTrainerM2EndBattleText
	text_end

Route6JrTrainerM2AfterBattleText:
	text_far _Route6JrTrainerM2AfterBattleText
	text_end

Route6JrTrainerF2Text:
	text_asm
	ld hl, Route6TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

Route6JrTrainerF2BattleText:
	text_far _Route6JrTrainerF2BattleText
	text_end

Route6JrTrainerF2EndBattleText:
	text_far _Route6JrTrainerF2EndBattleText
	text_end

Route6JrTrainerF2AfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, Route6GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROUTE6_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route6UndergroundPathSignText:
	text_far _Route6UndergroundPathSignText
	text_end

Rogue_Route6_Reward_Text:
script_rogue_reward

Route6_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route6_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route6_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route6GreedyText:
	text_far _GreedyText
	text_end
