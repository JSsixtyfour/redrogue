Route17_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM
    ld hl, wRogueFlagsBitfield
    set 0, [hl]                 ; gym is next after this route

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh

    .normal
	call EnableAutoTextBoxDrawing
	ld hl, Route17TrainerHeaders
	ld de, Route17_ScriptPointers
	ld a, [wRoute17CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute17CurScript], a
	ret

	RogueAutoWalkScripts Route17, PAD_DOWN, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_ROUTE_17, TEXT_ROUTE17_NO_TURNING_BACK, SCRIPT_ROUTE17_PLAYER_IS_MOVING, wRoute17CurScript

Route17EntranceCoords:
	dbmapcoord 5, 1
	dbmapcoord 6, 1
	db -1

Route17NoCoords:
	dbmapcoord 5, 2
	dbmapcoord 6, 2
	dbmapcoord 5, 3
	dbmapcoord 6, 3
	db -1

Route17_ScriptPointers:
	def_script_pointers
	dw_const Route17DefaultScript,                  SCRIPT_ROUTE17_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE17_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE17_END_BATTLE
	dw_const Route17PlayerIsMovingScript,           SCRIPT_ROUTE17_PLAYER_IS_MOVING

Route17_TextPointers:
	def_text_pointers
	dw_const Route17CueBall1Text,              TEXT_ROUTE17_CUE_BALL1
	dw_const Route17CueBall2Text,              TEXT_ROUTE17_CUE_BALL2
	dw_const Route17Biker3Text,              TEXT_ROUTE17_BIKER3
	dw_const Route17Biker4Text,              TEXT_ROUTE17_BIKER4
	dw_const Route17Biker5Text,              TEXT_ROUTE17_BIKER5
    dw_const RandomPickUpItemText,           TEXT_ROUTE17_RANDOM
    dw_const Route17_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE17_ROGUE_REWARD_POKEBALL_1
    dw_const Route17_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE17_ROGUE_REWARD_POKEBALL_2
    dw_const Route17_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE17_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_Route17_Reward_Text,      TEXT_ROUTE17_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE17_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route17NoticeSign1Text,         TEXT_ROUTE17_NOTICE_SIGN1
	dw_const Route17TrainerTips1Text,        TEXT_ROUTE17_TRAINER_TIPS1
	dw_const Route17TrainerTips2Text,        TEXT_ROUTE17_TRAINER_TIPS2
	dw_const Route17SignText,                TEXT_ROUTE17_SIGN
	dw_const Route17NoticeSign2Text,         TEXT_ROUTE17_NOTICE_SIGN2
	dw_const Route17CyclingRoadEndsSignText, TEXT_ROUTE17_CYCLING_ROAD_ENDS_SIGN
	dw_const Route17NoTurningBackText, TEXT_ROUTE17_NO_TURNING_BACK

Route17TrainerHeaders:
	def_trainers 1
Route17TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_17_TRAINER_0, 3, Route17CueBall1BattleText, Route17CueBall1EndBattleText, Route17CueBall1AfterBattleText
Route17TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_17_TRAINER_1, 4, Route17CueBall2BattleText, Route17CueBall2EndBattleText, Route17CueBall2AfterBattleText
Route17TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_17_TRAINER_2, 4, Route17Biker3BattleText, Route17Biker3EndBattleText, Route17Biker3AfterBattleText
Route17TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_17_TRAINER_3, 4, Route17Biker4BattleText, Route17Biker4EndBattleText, Route17Biker4AfterBattleText
Route17TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_17_TRAINER_4, 3, Route17Biker5BattleText, Route17Biker5EndBattleText, Route17Biker5AfterBattleText
	db -1 ; end

Route17CueBall1Text:
	text_asm
	ld hl, Route17TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

Route17CueBall1BattleText:
	text_far _Route17CueBall1BattleText
	text_end

Route17CueBall1EndBattleText:
	text_far _Route17CueBall1EndBattleText
	text_end

Route17CueBall1AfterBattleText:
	text_far _Route17CueBall1AfterBattleText
	text_end

Route17CueBall2Text:
	text_asm
	ld hl, Route17TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

Route17CueBall2BattleText:
	text_far _Route17CueBall2BattleText
	text_end

Route17CueBall2EndBattleText:
	text_far _Route17CueBall2EndBattleText
	text_end

Route17CueBall2AfterBattleText:
	text_far _Route17CueBall2AfterBattleText
	text_end

Route17Biker3Text:
	text_asm
	ld hl, Route17TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

Route17Biker3BattleText:
	text_far _Route17Biker3BattleText
	text_end

Route17Biker3EndBattleText:
	text_far _Route17Biker3EndBattleText
	text_end

Route17Biker3AfterBattleText:
	text_far _Route17Biker3AfterBattleText
	text_end

Route17Biker4Text:
	text_asm
	ld hl, Route17TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

Route17Biker4BattleText:
	text_far _Route17Biker4BattleText
	text_end

Route17Biker4EndBattleText:
	text_far _Route17Biker4EndBattleText
	text_end

Route17Biker4AfterBattleText:
	text_far _Route17Biker4AfterBattleText
	text_end

Route17Biker5Text:
	text_asm
	ld hl, Route17TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

Route17Biker5BattleText:
	text_far _Route17Biker5BattleText
	text_end

Route17Biker5EndBattleText:
	text_far _Route17Biker5EndBattleText
	text_end

Route17Biker5AfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, Route17GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROUTE17_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route17NoticeSign1Text:
	text_far _Route17NoticeSign1Text
	text_end

Route17TrainerTips1Text:
	text_far _Route17TrainerTips1Text
	text_end

Route17TrainerTips2Text:
	text_far _Route17TrainerTips2Text
	text_end

Route17SignText:
	text_far _Route17SignText
	text_end

Route17NoticeSign2Text:
	text_far _Route17NoticeSign2Text
	text_end

Route17CyclingRoadEndsSignText:
	text_far _Route17CyclingRoadEndsSignText
	text_end

Rogue_Route17_Reward_Text:
script_rogue_reward

Route17_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route17_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route17_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route17GreedyText:
	text_far _GreedyText
	text_end

Route17NoTurningBackText:
	text_far _NoTurningBackText
	text_end
