DEF SS_ANNE_5_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_SS_ANNE_5_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_SS_ANNE_5_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_SS_ANNE_5_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_SS_ANNE_5_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_SS_ANNE_5_TRAINER_4 % 8))

SSAnneBow_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM
    ld hl, wRogueFlagsBitfield
    set 0, [hl]                 ; gym is next after this route

    ResetEvent EVENT_GOT_ROGUE_POKEMON
    ResetEvent EVENT_ROGUE_POKEMON_OFFERED

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh

    .normal
    CheckEvent EVENT_ROGUE_POKEMON_OFFERED
    jr nz, .afterRewardCheck
    ld a, [wStatusFlags3]
    bit BIT_PRINT_END_BATTLE_TEXT, a
    jr nz, .afterRewardCheck
    ld a, [wEventFlags + (EVENT_BEAT_SS_ANNE_5_TRAINER_0 / 8)]
    and SS_ANNE_5_ALL_TRAINERS_MASK
    cp SS_ANNE_5_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_SSANNEBOW_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, SSAnne5TrainerHeaders
	ld de, SSAnneBow_ScriptPointers
	ld a, [wSSAnneBowCurScript]
	call ExecuteCurMapScriptInTable
	ld [wSSAnneBowCurScript], a
	ret

	RogueAutoWalkScripts SSAnneBow, PAD_LEFT, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_SS_ANNE_BOW, TEXT_SSANNEBOW_NO_TURNING_BACK, SCRIPT_SSANNEBOW_PLAYER_IS_MOVING, wSSAnneBowCurScript

SSAnneBowEntranceCoords:
	dbmapcoord 6, 13
	dbmapcoord 7, 13
	db -1

SSAnneBowNoCoords:
	dbmapcoord 6, 12
	dbmapcoord 7, 12
	dbmapcoord 6, 11
	dbmapcoord 7, 11
	db -1

SSAnneBow_ScriptPointers:
	def_script_pointers
	dw_const SSAnneBowDefaultScript,                SCRIPT_SSANNEBOW_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_SSANNEBOW_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_SSANNEBOW_END_BATTLE
	dw_const SSAnneBowPlayerIsMovingScript,         SCRIPT_SSANNEBOW_PLAYER_IS_MOVING

SSAnneBow_TextPointers:
	def_text_pointers
	dw_const SSAnneBowSailor1TrainerText,      TEXT_SSANNEBOW_SAILOR1_TRAINER
	dw_const SSAnneBowSailor2TrainerText,      TEXT_SSANNEBOW_SAILOR2_TRAINER
	dw_const SSAnneBowSuperNerdTrainerText,    TEXT_SSANNEBOW_SUPER_NERD_TRAINER
	dw_const SSAnneBowCooltrainerMTrainerText, TEXT_SSANNEBOW_COOLTRAINER_M_TRAINER
	dw_const SSAnneBowJrTrainerFText,          TEXT_SSANNEBOW_JR_TRAINER_F
	dw_const SSAnneBowSuperNerdText,       TEXT_SSANNEBOW_SUPER_NERD
	dw_const SSAnneBowSailor1Text,         TEXT_SSANNEBOW_SAILOR1
	dw_const SSAnneBowCooltrainerMText,    TEXT_SSANNEBOW_COOLTRAINER_M
    dw_const RandomPickUpItemText,         TEXT_SSANNEBOW_RANDOM
    dw_const SSAnneBow_Rogue_Reward_Script_PokeballText_1, TEXT_SSANNEBOW_ROGUE_REWARD_POKEBALL_1
    dw_const SSAnneBow_Rogue_Reward_Script_PokeballText_2, TEXT_SSANNEBOW_ROGUE_REWARD_POKEBALL_2
    dw_const SSAnneBow_Rogue_Reward_Script_PokeballText_3, TEXT_SSANNEBOW_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_SSAnneBow_Reward_Text,  TEXT_SSANNEBOW_REWARD_VENDOR_1
    EXPORT TEXT_SSANNEBOW_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const SSAnneBowNoTurningBackText, TEXT_SSANNEBOW_NO_TURNING_BACK

SSAnne5TrainerHeaders:
	def_trainers 1
SSAnne5TrainerHeader0:
	trainer EVENT_BEAT_SS_ANNE_5_TRAINER_0, 3, SSAnneBowSailor1TrainerBattleText, SSAnneBowSailor1TrainerEndBattleText, SSAnneBowSailor1TrainerAfterBattleText
SSAnne5TrainerHeader1:
	trainer EVENT_BEAT_SS_ANNE_5_TRAINER_1, 3, SSAnneBowSailor2TrainerBattleText, SSAnneBowSailor2TrainerEndBattleText, SSAnneBowSailor2TrainerAfterBattleText
SSAnne5TrainerHeader2:
	trainer EVENT_BEAT_SS_ANNE_5_TRAINER_2, 1, SSAnneBowSuperNerdTrainerBattleText, SSAnneBowSuperNerdTrainerEndBattleText, SSAnneBowSuperNerdTrainerAfterBattleText
SSAnne5TrainerHeader3:
	trainer EVENT_BEAT_SS_ANNE_5_TRAINER_3, 1, SSAnneBowCooltrainerMTrainerBattleText, SSAnneBowCooltrainerMTrainerEndBattleText, SSAnneBowCooltrainerMTrainerAfterBattleText
SSAnne5TrainerHeader4:
	trainer EVENT_BEAT_SS_ANNE_5_TRAINER_4, 1, SSAnneBowJrTrainerFBattleText, SSAnneBowJrTrainerFEndBattleText, SSAnneBowJrTrainerFAfterBattleText
	db -1 ; end

SSAnneBowSailor1TrainerText:
	text_asm
	ld hl, SSAnne5TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

SSAnneBowSailor1TrainerBattleText:
	text_far _SSAnneBowSailor2BattleText
	text_end

SSAnneBowSailor1TrainerEndBattleText:
	text_far _SSAnneBowSailor2EndBattleText
	text_end

SSAnneBowSailor1TrainerAfterBattleText:
	text_far _SSAnneBowSailor2AfterBattleText
	text_end

SSAnneBowSailor2TrainerText:
	text_asm
	ld hl, SSAnne5TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

SSAnneBowSailor2TrainerBattleText:
	text_far _SSAnneBowSailor3BattleText
	text_end

SSAnneBowSailor2TrainerEndBattleText:
	text_far _SSAnneBowSailor3EndBattleText
	text_end

SSAnneBowSailor2TrainerAfterBattleText:
	text_far _SSAnneBowSailor3AfterBattleText
	text_end

SSAnneBowSuperNerdTrainerText:
	text_asm
	ld hl, SSAnne5TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

SSAnneBowSuperNerdTrainerBattleText:
	text_far _SSAnneBowSailor2BattleText
	text_end

SSAnneBowSuperNerdTrainerEndBattleText:
	text_far _SSAnneBowSailor2EndBattleText
	text_end

SSAnneBowSuperNerdTrainerAfterBattleText:
	text_far _SSAnneBowSailor2AfterBattleText
	text_end

SSAnneBowCooltrainerMTrainerText:
	text_asm
	ld hl, SSAnne5TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

SSAnneBowCooltrainerMTrainerBattleText:
	text_far _SSAnneBowSailor2BattleText
	text_end

SSAnneBowCooltrainerMTrainerEndBattleText:
	text_far _SSAnneBowSailor2EndBattleText
	text_end

SSAnneBowCooltrainerMTrainerAfterBattleText:
	text_far _SSAnneBowSailor2AfterBattleText
	text_end

SSAnneBowJrTrainerFText:
	text_asm
	ld hl, SSAnne5TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

SSAnneBowJrTrainerFBattleText:
	text_far _SSAnneBowSailor3BattleText
	text_end

SSAnneBowJrTrainerFEndBattleText:
	text_far _SSAnneBowSailor3EndBattleText
	text_end

SSAnneBowJrTrainerFAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, SSAnneBowGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_SSANNEBOW_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

SSAnneBowSuperNerdText:
	text_far _SSAnneBowSuperNerdText
	text_end

SSAnneBowSailor1Text:
	text_far _SSAnneBowSailor1Text
	text_end

SSAnneBowCooltrainerMText:
	text_far _SSAnneBowCooltrainerMText
	text_end

Rogue_SSAnneBow_Reward_Text:
script_rogue_reward

SSAnneBow_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

SSAnneBow_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

SSAnneBow_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

SSAnneBowNoTurningBackText:
	text_far _NoTurningBackText
	text_end

SSAnneBowGreedyText:
	text_far _GreedyText
	text_end
