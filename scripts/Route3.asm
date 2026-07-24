DEF ROUTE3_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_ROUTE_3_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_3_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_3_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_3_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_3_TRAINER_4 % 8))

Route3_Script:

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

    ld a, [wEventFlags + (EVENT_BEAT_ROUTE_3_TRAINER_0 / 8)]
    and ROUTE3_ALL_TRAINERS_MASK
    cp ROUTE3_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck

    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_ROUTE3_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay

    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, Route3TrainerHeaders
	ld de, Route3_ScriptPointers
	ld a, [wRoute3CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute3CurScript], a
	ret

	RogueAutoWalkScripts Route3, PAD_RIGHT, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_ROUTE_3, TEXT_ROUTE3_NO_TURNING_BACK, SCRIPT_ROUTE3_PLAYER_IS_MOVING, wRoute3CurScript

Route3EntranceCoords:
	dbmapcoord 0, 9
	dbmapcoord 0, 10
	db -1

Route3NoCoords:
	dbmapcoord 1, 9
	dbmapcoord 1, 10
	dbmapcoord 2, 9
	dbmapcoord 2, 10
	db -1

Route3_ScriptPointers:
	def_script_pointers
	dw_const Route3DefaultScript,                   SCRIPT_ROUTE3_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE3_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE3_END_BATTLE
	dw_const Route3PlayerIsMovingScript,            SCRIPT_ROUTE3_PLAYER_IS_MOVING

Route3_TextPointers:
	def_text_pointers
	dw_const Route3SuperNerdText,    TEXT_ROUTE3_SUPER_NERD
	dw_const Route3BugCatcherText,   TEXT_ROUTE3_BUG_CATCHER
	dw_const Route3LassText,         TEXT_ROUTE3_LASS
	dw_const Route3Youngster1Text,   TEXT_ROUTE3_YOUNGSTER1
	dw_const Route3Youngster2Text,   TEXT_ROUTE3_YOUNGSTER2
	dw_const Route3JrTrainerMText,   TEXT_ROUTE3_JR_TRAINER_M
    dw_const RandomPickUpItemText,    TEXT_ROUTE3_RANDOM
    dw_const Route3_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE3_ROGUE_REWARD_POKEBALL_1
    dw_const Route3_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE3_ROGUE_REWARD_POKEBALL_2
    dw_const Route3_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE3_ROGUE_REWARD_POKEBALL_3
    dw_const Route3_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE3_ROGUE_TRADE_NPC
    dw_const Rogue_Route3_Reward_Text, TEXT_ROUTE3_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE3_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route3SignText,          TEXT_ROUTE3_SIGN
	dw_const Route3NoTurningBackText, TEXT_ROUTE3_NO_TURNING_BACK

Route3TrainerHeaders:
	def_trainers 1
Route3TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_3_TRAINER_0, 2, Route3BugCatcherBattleText, Route3BugCatcherEndBattleText, Route3BugCatcherAfterBattleText
Route3TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_3_TRAINER_1, 2, Route3LassBattleText, Route3LassEndBattleText, Route3LassAfterBattleText
Route3TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_3_TRAINER_2, 2, Route3Youngster1BattleText, Route3Youngster1EndBattleText, Route3Youngster1AfterBattleText
Route3TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_3_TRAINER_3, 1, Route3Youngster2BattleText, Route3Youngster2EndBattleText, Route3Youngster2AfterBattleText
Route3TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_3_TRAINER_4, 4, Route3JrTrainerMBattleText, Route3JrTrainerMEndBattleText, Route3JrTrainerMAfterBattleText
	db -1 ; end

Route3SuperNerdText:
	text_far _Route3Text1
	text_end

Route3BugCatcherText:
	text_asm
	ld hl, Route3TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

Route3BugCatcherBattleText:
	text_far _Route3Youngster1BattleText
	text_end

Route3BugCatcherEndBattleText:
	text_far _Route3Youngster1EndBattleText
	text_end

Route3BugCatcherAfterBattleText:
	text_far _Route3Youngster1AfterBattleText
	text_end

Route3LassText:
	text_asm
	ld hl, Route3TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

Route3LassBattleText:
	text_far _Route3CooltrainerF1BattleText
	text_end

Route3LassEndBattleText:
	text_far _Route3CooltrainerF1EndBattleText
	text_end

Route3LassAfterBattleText:
	text_far _Route3CooltrainerF1AfterBattleText
	text_end

Route3Youngster1Text:
	text_asm
	ld hl, Route3TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

Route3Youngster1BattleText:
	text_far _Route3Youngster2BattleText
	text_end

Route3Youngster1EndBattleText:
	text_far _Route3Youngster2EndBattleText
	text_end

Route3Youngster1AfterBattleText:
	text_far _Route3Youngster2AfterBattleText
	text_end

Route3Youngster2Text:
	text_asm
	ld hl, Route3TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

Route3Youngster2BattleText:
	text_far _Route3Youngster3BattleText
	text_end

Route3Youngster2EndBattleText:
	text_far _Route3Youngster3EndBattleText
	text_end

Route3Youngster2AfterBattleText:
	text_far _Route3Youngster3AfterBattleText
	text_end

Route3JrTrainerMText:
	text_asm
	ld hl, Route3TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

Route3JrTrainerMBattleText:
	text_far _Route3CooltrainerF3BattleText
	text_end

Route3JrTrainerMEndBattleText:
	text_far _Route3Youngster4EndBattleText
	text_end

Route3JrTrainerMAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, Route3GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROUTE3_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route3SignText:
	text_far _Route3SignText
	text_end

Rogue_Route3_Reward_Text:
script_rogue_reward

Route3_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route3_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route3_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route3GreedyText:
	text_far _GreedyText
	text_end

Route3NoTurningBackText:
	text_far _NoTurningBackText
	text_end
