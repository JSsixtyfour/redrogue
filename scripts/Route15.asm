DEF ROUTE15_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_ROUTE_15_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_15_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_15_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_15_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_15_TRAINER_4 % 8))

Route15_Script:

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

    ; wait until the trainer's end-battle text has finished printing
    ; so the auto reward popup doesn't race/overlap with it
    ld a, [wStatusFlags3]
    bit BIT_PRINT_END_BATTLE_TEXT, a
    jr nz, .afterRewardCheck

    ld a, [wEventFlags + (EVENT_BEAT_ROUTE_15_TRAINER_0 / 8)]
    and ROUTE15_ALL_TRAINERS_MASK
    cp ROUTE15_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck

    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_ROUTE15_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay

    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, Route15TrainerHeaders
	ld de, Route15_ScriptPointers
	ld a, [wRoute15CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute15CurScript], a
	ret

	RogueAutoWalkScripts Route15, PAD_LEFT, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_ROUTE_15, TEXT_ROUTE15_NO_TURNING_BACK, SCRIPT_ROUTE15_PLAYER_IS_MOVING, wRoute15CurScript

Route15EntranceCoords:
	dbmapcoord 54, 10
	dbmapcoord 54, 11
	db -1

Route15NoCoords:
	dbmapcoord 53, 10
	dbmapcoord 53, 11
	dbmapcoord 52, 10
	dbmapcoord 52, 11
	db -1

Route15_ScriptPointers:
	def_script_pointers
	dw_const Route15DefaultScript,                  SCRIPT_ROUTE15_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE15_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE15_END_BATTLE
	dw_const Route15PlayerIsMovingScript,           SCRIPT_ROUTE15_PLAYER_IS_MOVING

Route15_TextPointers:
	def_text_pointers
	dw_const Route15JrTrainerF1Text,   TEXT_ROUTE15_JR_TRAINER_F1
	dw_const Route15BirdKeeperText,    TEXT_ROUTE15_BIRD_KEEPER
	dw_const Route15BeautyText,        TEXT_ROUTE15_BEAUTY
	dw_const Route15BikerText,         TEXT_ROUTE15_BIKER
	dw_const Route15JrTrainerF2Text,   TEXT_ROUTE15_JR_TRAINER_F2
	dw_const PickUpItemText,           TEXT_ROUTE15_TM_RAGE
    dw_const RandomPickUpItemText,     TEXT_ROUTE15_RANDOM
    dw_const Route15_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE15_ROGUE_REWARD_POKEBALL_1
    dw_const Route15_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE15_ROGUE_REWARD_POKEBALL_2
    dw_const Route15_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE15_ROGUE_REWARD_POKEBALL_3
    dw_const Route15_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE15_ROGUE_TRADE_NPC
    dw_const Rogue_Route15_Reward_Text, TEXT_ROUTE15_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE15_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route15NoTurningBackText, TEXT_ROUTE15_NO_TURNING_BACK
	dw_const Route15SignText,          TEXT_ROUTE15_SIGN

Route15TrainerHeaders:
	def_trainers 1
Route15TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_15_TRAINER_0, 5, Route15JrTrainerF1BattleText, Route15JrTrainerF1EndBattleText, Route15JrTrainerF1AfterBattleText
Route15TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_15_TRAINER_1, 5, Route15BirdKeeperBattleText, Route15BirdKeeperEndBattleText, Route15BirdKeeperAfterBattleText
Route15TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_15_TRAINER_2, 5, Route15BeautyBattleText, Route15BeautyEndBattleText, Route15BeautyAfterBattleText
Route15TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_15_TRAINER_3, 5, Route15BikerBattleText, Route15BikerEndBattleText, Route15BikerAfterBattleText
Route15TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_15_TRAINER_4, 5, Route15JrTrainerF2BattleText, Route15JrTrainerF2EndBattleText, Route15JrTrainerF2AfterBattleText
	db -1 ; end

Route15JrTrainerF1Text:
	text_asm
	ld hl, Route15TrainerHeader0
	jr Route15TalkToTrainer

Route15BirdKeeperText:
	text_asm
	ld hl, Route15TrainerHeader1
	jr Route15TalkToTrainer

Route15BeautyText:
	text_asm
	ld hl, Route15TrainerHeader2
	jr Route15TalkToTrainer

Route15BikerText:
	text_asm
	ld hl, Route15TrainerHeader3
	jr Route15TalkToTrainer

Route15JrTrainerF2Text:
	text_asm
	ld hl, Route15TrainerHeader4
Route15TalkToTrainer:
	call TalkToTrainer
	jp TextScriptEnd

Route15JrTrainerF1BattleText:
	text_far _Route15JrTrainerF1BattleText
	text_end

Route15JrTrainerF1EndBattleText:
	text_far _Route15JrTrainerF1EndBattleText
	text_end

Route15JrTrainerF1AfterBattleText:
	text_far _Route15JrTrainerF1AfterBattleText
	text_end

Route15BirdKeeperBattleText:
	text_far _Route15CooltrainerM1BattleText
	text_end

Route15BirdKeeperEndBattleText:
	text_far _Route15CooltrainerM1EndBattleText
	text_end

Route15BirdKeeperAfterBattleText:
	text_far _Route15CooltrainerM1AfterBattleText
	text_end

Route15BeautyBattleText:
	text_far _Route15Beauty1BattleText
	text_end

Route15BeautyEndBattleText:
	text_far _Route15Beauty1EndBattleText
	text_end

Route15BeautyAfterBattleText:
	text_far _Route15Beauty1AfterBattleText
	text_end

Route15BikerBattleText:
	text_far _Route15Biker1BattleText
	text_end

Route15BikerEndBattleText:
	text_far _Route15Biker1EndBattleText
	text_end

Route15BikerAfterBattleText:
	text_far _Route15Biker1AfterBattleText
	text_end

Route15JrTrainerF2BattleText:
	text_far _Route15JrTrainerF2BattleText
	text_end

Route15JrTrainerF2EndBattleText:
	text_far _Route15JrTrainerF2EndBattleText
	text_end

Route15JrTrainerF2AfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, Route15GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROUTE15_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route15SignText:
	text_far _Route15SignText
	text_end

Rogue_Route15_Reward_Text:
script_rogue_reward

Route15_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route15_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route15_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route15GreedyText:
	text_far _GreedyText
	text_end

Route15NoTurningBackText:
	text_far _NoTurningBackText
	text_end
