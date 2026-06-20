UndergroundPathRoute5_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection

    .normal
	ld a, ROUTE_5
	ld [wLastMap], a
	call EnableAutoTextBoxDrawing
	ld hl, UndergroundPathRoute5TrainerHeaders
	ld de, UndergroundPathRoute5_ScriptPointers
	ld a, [wUndergroundPathRoute5CurScript]
	call ExecuteCurMapScriptInTable
	ld [wUndergroundPathRoute5CurScript], a
	ret

UndergroundPathRoute5_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_UNDERGROUNDPATHROUTE5_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_UNDERGROUNDPATHROUTE5_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_UNDERGROUNDPATHROUTE5_END_BATTLE

UndergroundPathEntranceRoute5_TextScriptEndingText:
	text_end

UndergroundPathRoute5_TextPointers:
	def_text_pointers
	dw_const UndergroundPathRoute5CooltrainerMText, TEXT_UNDERGROUNDPATHROUTE5_COOLTRAINER_M
	dw_const UndergroundPathRoute5JugglerText,      TEXT_UNDERGROUNDPATHROUTE5_JUGGLER
	dw_const UndergroundPathRoute5CueBallText,      TEXT_UNDERGROUNDPATHROUTE5_CUE_BALL
	dw_const UndergroundPathRoute5BikerText,        TEXT_UNDERGROUNDPATHROUTE5_BIKER
	dw_const UndergroundPathRoute5SuperNerdText,    TEXT_UNDERGROUNDPATHROUTE5_SUPER_NERD
	dw_const UndergroundPathRoute5LittleGirlText, TEXT_UNDERGROUNDPATHROUTE5_LITTLE_GIRL
    dw_const RandomPickUpItemText,                TEXT_UNDERGROUNDPATHROUTE5_RANDOM
    dw_const UndergroundPathRoute5_Rogue_Reward_Script_PokeballText_1, TEXT_UNDERGROUNDPATHROUTE5_ROGUE_REWARD_POKEBALL_1
    dw_const UndergroundPathRoute5_Rogue_Reward_Script_PokeballText_2, TEXT_UNDERGROUNDPATHROUTE5_ROGUE_REWARD_POKEBALL_2
    dw_const UndergroundPathRoute5_Rogue_Reward_Script_PokeballText_3, TEXT_UNDERGROUNDPATHROUTE5_ROGUE_REWARD_POKEBALL_3
    dw_const UndergroundPathRoute5_Rogue_Reward_Script_PokeballText_1, TEXT_UNDERGROUNDPATHROUTE5_ROGUE_TRADE_NPC
    dw_const Rogue_UndergroundPathRoute5_Reward_Text, TEXT_UNDERGROUNDPATHROUTE5_REWARD_VENDOR_1
    EXPORT TEXT_UNDERGROUNDPATHROUTE5_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm

UndergroundPathRoute5TrainerHeaders:
	def_trainers 1
UndergroundPathRoute5TrainerHeader0:
	trainer EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_0, 1, UndergroundPathRoute5CooltrainerMBattleText, UndergroundPathRoute5CooltrainerMEndBattleText, UndergroundPathRoute5CooltrainerMAfterBattleText
UndergroundPathRoute5TrainerHeader1:
	trainer EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_1, 1, UndergroundPathRoute5JugglerBattleText, UndergroundPathRoute5JugglerEndBattleText, UndergroundPathRoute5JugglerAfterBattleText
UndergroundPathRoute5TrainerHeader2:
	trainer EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_2, 1, UndergroundPathRoute5CueBallBattleText, UndergroundPathRoute5CueBallEndBattleText, UndergroundPathRoute5CueBallAfterBattleText
UndergroundPathRoute5TrainerHeader3:
	trainer EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_3, 1, UndergroundPathRoute5BikerBattleText, UndergroundPathRoute5BikerEndBattleText, UndergroundPathRoute5BikerAfterBattleText
UndergroundPathRoute5TrainerHeader4:
	trainer EVENT_BEAT_UNDERGROUND_PATH_ROUTE5_TRAINER_4, 1, UndergroundPathRoute5SuperNerdBattleText, UndergroundPathRoute5SuperNerdEndBattleText, UndergroundPathRoute5SuperNerdAfterBattleText
	db -1 ; end

UndergroundPathRoute5CooltrainerMText:
	text_asm
	ld hl, UndergroundPathRoute5TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

UndergroundPathRoute5CooltrainerMBattleText:
	text_far _UndergroundPathRoute5SuperNerd1BattleText
	text_end

UndergroundPathRoute5CooltrainerMEndBattleText:
	text_far _UndergroundPathRoute5SuperNerd1EndBattleText
	text_end

UndergroundPathRoute5CooltrainerMAfterBattleText:
	text_far _UndergroundPathRoute5SuperNerd1AfterBattleText
	text_end

UndergroundPathRoute5JugglerText:
	text_asm
	ld hl, UndergroundPathRoute5TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

UndergroundPathRoute5JugglerBattleText:
	text_far _UndergroundPathRoute5SuperNerd1BattleText
	text_end

UndergroundPathRoute5JugglerEndBattleText:
	text_far _UndergroundPathRoute5SuperNerd1EndBattleText
	text_end

UndergroundPathRoute5JugglerAfterBattleText:
	text_far _UndergroundPathRoute5SuperNerd1AfterBattleText
	text_end

UndergroundPathRoute5CueBallText:
	text_asm
	ld hl, UndergroundPathRoute5TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

UndergroundPathRoute5CueBallBattleText:
	text_far _UndergroundPathRoute5SuperNerd1BattleText
	text_end

UndergroundPathRoute5CueBallEndBattleText:
	text_far _UndergroundPathRoute5SuperNerd1EndBattleText
	text_end

UndergroundPathRoute5CueBallAfterBattleText:
	text_far _UndergroundPathRoute5SuperNerd1AfterBattleText
	text_end

UndergroundPathRoute5BikerText:
	text_asm
	ld hl, UndergroundPathRoute5TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

UndergroundPathRoute5BikerBattleText:
	text_far _UndergroundPathRoute5SuperNerd1BattleText
	text_end

UndergroundPathRoute5BikerEndBattleText:
	text_far _UndergroundPathRoute5SuperNerd1EndBattleText
	text_end

UndergroundPathRoute5BikerAfterBattleText:
	text_far _UndergroundPathRoute5SuperNerd1AfterBattleText
	text_end

UndergroundPathRoute5SuperNerdText:
	text_asm
	ld hl, UndergroundPathRoute5TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

UndergroundPathRoute5SuperNerdBattleText:
	text_far _UndergroundPathRoute5SuperNerd1BattleText
	text_end

UndergroundPathRoute5SuperNerdEndBattleText:
	text_far _UndergroundPathRoute5SuperNerd1EndBattleText
	text_end

UndergroundPathRoute5SuperNerdAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, UndergroundPathRoute5GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_UNDERGROUNDPATHROUTE5_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

UndergroundPathRoute5LittleGirlText:
	text_asm
	ld a, TRADE_FOR_SPOT
	ld [wWhichTrade], a
	predef DoInGameTradeDialogue
	ld hl, UndergroundPathEntranceRoute5_TextScriptEndingText
	ret

Rogue_UndergroundPathRoute5_Reward_Text:
script_rogue_reward

UndergroundPathRoute5_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

UndergroundPathRoute5_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

UndergroundPathRoute5_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

UndergroundPathRoute5GreedyText:
	text_far _GreedyText
	text_end
