SSAnneBow_Script:
	call EnableAutoTextBoxDrawing
	ld hl, SSAnne5TrainerHeaders
	ld de, SSAnneBow_ScriptPointers
	ld a, [wSSAnneBowCurScript]
	call ExecuteCurMapScriptInTable
	ld [wSSAnneBowCurScript], a
	ret

SSAnneBow_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_SSANNEBOW_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_SSANNEBOW_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_SSANNEBOW_END_BATTLE

SSAnneBow_TextPointers:
	def_text_pointers
	dw_const SSAnneBowSailor1TrainerText,      TEXT_SSANNEBOW_SAILOR1_TRAINER
	dw_const SSAnneBowSailor2TrainerText,      TEXT_SSANNEBOW_SAILOR2_TRAINER
	dw_const SSAnneBowSuperNerdTrainerText,    TEXT_SSANNEBOW_SUPER_NERD_TRAINER
	dw_const SSAnneBowCooltrainerMTrainerText, TEXT_SSANNEBOW_COOLTRAINER_M_TRAINER
	dw_const SSAnneBowJrTrainerFText,          TEXT_SSANNEBOW_JR_TRAINER_F
	dw_const SSAnneBowSuperNerdText,           TEXT_SSANNEBOW_SUPER_NERD
	dw_const SSAnneBowSailor1Text,             TEXT_SSANNEBOW_SAILOR1
	dw_const SSAnneBowCooltrainerMText,        TEXT_SSANNEBOW_COOLTRAINER_M

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
	text_far _SSAnneBowSailor3AfterBattleText
	text_end

SSAnneBowSuperNerdText:
	text_far _SSAnneBowSuperNerdText
	text_end

SSAnneBowSailor1Text:
	text_far _SSAnneBowSailor1Text
	text_end

SSAnneBowCooltrainerMText:
	text_far _SSAnneBowCooltrainerMText
	text_end
