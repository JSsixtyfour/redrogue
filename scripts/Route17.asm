Route17_Script:
	call EnableAutoTextBoxDrawing
	ld hl, Route17TrainerHeaders
	ld de, Route17_ScriptPointers
	ld a, [wRoute17CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute17CurScript], a
	ret

Route17_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_ROUTE17_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE17_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE17_END_BATTLE

Route17_TextPointers:
	def_text_pointers
	dw_const Route17CueBall1Text,            TEXT_ROUTE17_CUE_BALL1
	dw_const Route17CueBall2Text,            TEXT_ROUTE17_CUE_BALL2
	dw_const Route17Biker3Text,              TEXT_ROUTE17_BIKER3
	dw_const Route17Biker4Text,              TEXT_ROUTE17_BIKER4
	dw_const Route17Biker5Text,              TEXT_ROUTE17_BIKER5
	dw_const Route17NoticeSign1Text,         TEXT_ROUTE17_NOTICE_SIGN1
	dw_const Route17TrainerTips1Text,        TEXT_ROUTE17_TRAINER_TIPS1
	dw_const Route17TrainerTips2Text,        TEXT_ROUTE17_TRAINER_TIPS2
	dw_const Route17SignText,                TEXT_ROUTE17_SIGN
	dw_const Route17NoticeSign2Text,         TEXT_ROUTE17_NOTICE_SIGN2
	dw_const Route17CyclingRoadEndsSignText, TEXT_ROUTE17_CYCLING_ROAD_ENDS_SIGN

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
	text_far _Route17Biker5AfterBattleText
	text_end

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
