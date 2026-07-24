DEF DIGLETTS_CAVE_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_DIGLETTS_CAVE_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_DIGLETTS_CAVE_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_DIGLETTS_CAVE_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_DIGLETTS_CAVE_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_DIGLETTS_CAVE_TRAINER_4 % 8))

DiglettsCave_Script:

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

    ; Mini-boss framework (see MINIBOSS_FRAMEWORK.md): if this stage was chosen
    ; as the mini-boss door's stage, swap its 5th trainer (slot from
    ; MiniBossStageSlots) in place to the rolled boss + team. No-op otherwise.
    farcall MiniBossApplyStageTrainer

    .normal
    CheckEvent EVENT_ROGUE_POKEMON_OFFERED
    jr nz, .afterRewardCheck
    ld a, [wStatusFlags3]
    bit BIT_PRINT_END_BATTLE_TEXT, a
    jr nz, .afterRewardCheck
    ld a, [wEventFlags + (EVENT_BEAT_DIGLETTS_CAVE_TRAINER_0 / 8)]
    and DIGLETTS_CAVE_ALL_TRAINERS_MASK
    cp DIGLETTS_CAVE_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_DIGLETTSCAVE_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, DiglettsCaveTrainerHeaders
	ld de, DiglettsCave_ScriptPointers
	ld a, [wDiglettsCaveCurScript]
	call ExecuteCurMapScriptInTable
	ld [wDiglettsCaveCurScript], a
	ret

	RogueAutoWalkScripts DiglettsCave, PAD_RIGHT, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_DIGLETTS_CAVE, TEXT_DIGLETTSCAVE_NO_TURNING_BACK, SCRIPT_DIGLETTSCAVE_PLAYER_IS_MOVING, wDiglettsCaveCurScript

DiglettsCaveEntranceCoords:
	dbmapcoord 5, 5
	db -1

DiglettsCaveNoCoords:
	dbmapcoord 5, 4
	dbmapcoord 5, 3
	db -1

DiglettsCave_ScriptPointers:
	def_script_pointers
	dw_const DiglettsCaveDefaultScript,             SCRIPT_DIGLETTSCAVE_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_DIGLETTSCAVE_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_DIGLETTSCAVE_END_BATTLE
	dw_const DiglettsCavePlayerIsMovingScript,      SCRIPT_DIGLETTSCAVE_PLAYER_IS_MOVING

DiglettsCave_TextPointers:
	def_text_pointers
	dw_const DiglettsCaveHikerText,       TEXT_DIGLETTSCAVE_HIKER
	dw_const DiglettsCaveBugCatcherText,  TEXT_DIGLETTSCAVE_BUG_CATCHER
	dw_const DiglettsCaveYoungsterText,   TEXT_DIGLETTSCAVE_YOUNGSTER
	dw_const DiglettsCaveEngineerText,    TEXT_DIGLETTSCAVE_ENGINEER
	dw_const DiglettsCaveCooltrainerFText,TEXT_DIGLETTSCAVE_COOLTRAINER_F
    dw_const RandomPickUpItemText,        TEXT_DIGLETTSCAVE_RANDOM
    dw_const DiglettsCave_Rogue_Reward_Script_PokeballText_1, TEXT_DIGLETTSCAVE_ROGUE_REWARD_POKEBALL_1
    dw_const DiglettsCave_Rogue_Reward_Script_PokeballText_2, TEXT_DIGLETTSCAVE_ROGUE_REWARD_POKEBALL_2
    dw_const DiglettsCave_Rogue_Reward_Script_PokeballText_3, TEXT_DIGLETTSCAVE_ROGUE_REWARD_POKEBALL_3
    dw_const DiglettsCave_Rogue_Reward_Script_PokeballText_1, TEXT_DIGLETTSCAVE_ROGUE_TRADE_NPC
    dw_const Rogue_DiglettsCave_Reward_Text, TEXT_DIGLETTSCAVE_REWARD_VENDOR_1
    EXPORT TEXT_DIGLETTSCAVE_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const DiglettsCaveNoTurningBackText, TEXT_DIGLETTSCAVE_NO_TURNING_BACK

DiglettsCaveTrainerHeaders:
	def_trainers 1
DiglettsCaveTrainerHeader0:
	trainer EVENT_BEAT_DIGLETTS_CAVE_TRAINER_0, 1, DiglettsCaveHikerBattleText, DiglettsCaveHikerEndBattleText, DiglettsCaveHikerAfterBattleText
DiglettsCaveTrainerHeader1:
	trainer EVENT_BEAT_DIGLETTS_CAVE_TRAINER_1, 1, DiglettsCaveBugCatcherBattleText, DiglettsCaveBugCatcherEndBattleText, DiglettsCaveBugCatcherAfterBattleText
DiglettsCaveTrainerHeader2:
	trainer EVENT_BEAT_DIGLETTS_CAVE_TRAINER_2, 1, DiglettsCaveYoungsterBattleText, DiglettsCaveYoungsterEndBattleText, DiglettsCaveYoungsterAfterBattleText
DiglettsCaveTrainerHeader3:
	trainer EVENT_BEAT_DIGLETTS_CAVE_TRAINER_3, 1, DiglettsCaveEngineerBattleText, DiglettsCaveEngineerEndBattleText, DiglettsCaveEngineerAfterBattleText
DiglettsCaveTrainerHeader4:
	trainer EVENT_BEAT_DIGLETTS_CAVE_TRAINER_4, 1, DiglettsCaveCooltrainerFBattleText, DiglettsCaveCooltrainerFEndBattleText, DiglettsCaveCooltrainerFAfterBattleText
	db -1 ; end

DiglettsCaveHikerText:
	text_asm
	ld hl, DiglettsCaveTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

DiglettsCaveHikerBattleText:
	text_far _DiglettsCaveBugCatcher1BattleText
	text_end

DiglettsCaveHikerEndBattleText:
	text_far _DiglettsCaveBugCatcher1EndBattleText
	text_end

DiglettsCaveHikerAfterBattleText:
	text_far _DiglettsCaveBugCatcher1AfterBattleText
	text_end

DiglettsCaveBugCatcherText:
	text_asm
	ld hl, DiglettsCaveTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

DiglettsCaveBugCatcherBattleText:
	text_far _DiglettsCaveBugCatcher1BattleText
	text_end

DiglettsCaveBugCatcherEndBattleText:
	text_far _DiglettsCaveBugCatcher1EndBattleText
	text_end

DiglettsCaveBugCatcherAfterBattleText:
	text_far _DiglettsCaveBugCatcher1AfterBattleText
	text_end

DiglettsCaveYoungsterText:
	text_asm
	ld hl, DiglettsCaveTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

DiglettsCaveYoungsterBattleText:
	text_far _DiglettsCaveBugCatcher1BattleText
	text_end

DiglettsCaveYoungsterEndBattleText:
	text_far _DiglettsCaveBugCatcher1EndBattleText
	text_end

DiglettsCaveYoungsterAfterBattleText:
	text_far _DiglettsCaveBugCatcher1AfterBattleText
	text_end

DiglettsCaveEngineerText:
	text_asm
	ld hl, DiglettsCaveTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

DiglettsCaveEngineerBattleText:
	text_far _DiglettsCaveBugCatcher1BattleText
	text_end

DiglettsCaveEngineerEndBattleText:
	text_far _DiglettsCaveBugCatcher1EndBattleText
	text_end

DiglettsCaveEngineerAfterBattleText:
	text_far _DiglettsCaveBugCatcher1AfterBattleText
	text_end

DiglettsCaveCooltrainerFText:
	text_asm
	ld hl, DiglettsCaveTrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

DiglettsCaveCooltrainerFBattleText:
	text_far _DiglettsCaveBugCatcher1BattleText
	text_end

DiglettsCaveCooltrainerFEndBattleText:
	text_far _DiglettsCaveBugCatcher1EndBattleText
	text_end

DiglettsCaveCooltrainerFAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, DiglettsCaveGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_DIGLETTSCAVE_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Rogue_DiglettsCave_Reward_Text:
script_rogue_reward

DiglettsCave_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

DiglettsCave_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

DiglettsCave_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

DiglettsCaveNoTurningBackText:
	text_far _NoTurningBackText
	text_end

DiglettsCaveGreedyText:
	text_far _GreedyText
	text_end
