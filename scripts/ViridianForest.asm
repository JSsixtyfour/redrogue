ViridianForest_Script:
	call EnableAutoTextBoxDrawing
	ld hl, ViridianForestTrainerHeaders
	ld de, ViridianForest_ScriptPointers
	ld a, [wViridianForestCurScript]
	call ExecuteCurMapScriptInTable
	ld [wViridianForestCurScript], a
	ret

ViridianForest_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_VIRIDIANFOREST_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_VIRIDIANFOREST_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_VIRIDIANFOREST_END_BATTLE

ViridianForest_TextPointers:
	def_text_pointers
	dw_const ViridianForestYoungster1Text,      TEXT_VIRIDIANFOREST_YOUNGSTER1
	dw_const ViridianForestYoungster2Text,      TEXT_VIRIDIANFOREST_YOUNGSTER2
	dw_const ViridianForestYoungster3Text,      TEXT_VIRIDIANFOREST_YOUNGSTER3
	dw_const ViridianForestYoungster4Text,      TEXT_VIRIDIANFOREST_YOUNGSTER4
    dw_const ViridianForestYoungster5Text,      TEXT_VIRIDIANFOREST_YOUNGSTER5
    dw_const ViridianForestCooltrainer_FText,   TEXT_VIRIDIANFOREST_COOLTRAINER_F
    dw_const PickUpItemText,                    TEXT_VIRIDIANFOREST_ANTIDOTE
	dw_const PickUpItemText,                    TEXT_VIRIDIANFOREST_POTION
	dw_const RandomPickUpItemText,              TEXT_VIRIDIANFOREST_RANDOM
    dw_const Rogue_ViridianForest_Reward_Text, TEXT_VIRIDIANFOREST_REWARD_VENDOR_1
    EXPORT TEXT_VIRIDIANFOREST_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
    ;dw_const Rogue_Reward_Script_PokeballText_1, TEXT_VIRIDIANFOREST_ROGUE_REWARD_POKEBALL_1
    ;dw_const Rogue_Reward_Script_PokeballText_2, TEXT_VIRIDIANFOREST_ROGUE_REWARD_POKEBALL_2
    ;dw_const Rogue_Reward_Script_PokeballText_3, TEXT_VIRIDIANFOREST_ROGUE_REWARD_POKEBALL_3
    ;dw_const Rogue_RewardRoom_Reward_Text,      TEXT_REWARDROOM_REWARD_VENDOR_1
	dw_const ViridianForestTrainerTips1Text,    TEXT_VIRIDIANFOREST_TRAINER_TIPS1
	dw_const ViridianForestUseAntidoteSignText, TEXT_VIRIDIANFOREST_USE_ANTIDOTE_SIGN
	dw_const ViridianForestTrainerTips2Text,    TEXT_VIRIDIANFOREST_TRAINER_TIPS2
	dw_const ViridianForestTrainerTips3Text,    TEXT_VIRIDIANFOREST_TRAINER_TIPS3
	dw_const ViridianForestTrainerTips4Text,    TEXT_VIRIDIANFOREST_TRAINER_TIPS4
	dw_const ViridianForestLeavingSignText,     TEXT_VIRIDIANFOREST_LEAVING_SIGN
    

ViridianForestTrainerHeaders:
	def_trainers 2
ViridianForestTrainerHeader0:
	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0, 4, ViridianForestYoungster2BattleText, ViridianForestYoungster2EndBattleText, ViridianForestYoungster2AfterBattleText
ViridianForestTrainerHeader1:
	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_1, 4, ViridianForestYoungster3BattleText, ViridianForestYoungster3EndBattleText, ViridianForestYoungster3AfterBattleText
ViridianForestTrainerHeader2:
	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_2, 4, ViridianForestYoungster4BattleText, ViridianForestYoungster4EndBattleText, ViridianForestYoungster4AfterBattleText
ViridianForestTrainerHeader3:
	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_3, 4, ViridianForestYoungster5BattleText, ViridianForestYoungster5EndBattleText, ViridianForestYoungster5AfterBattleText
;ViridianForestTrainerHeader4:
;	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_4, 4, ViridianForestCooltrainer_FBattleText, ViridianForestCooltrainer_FEndBattleText, ViridianForestCooltrainer_FAfterBattleText
	db -1 ; end
    


ViridianForestYoungster1Text:
	text_far _ViridianForestYoungster1Text
	text_end

ViridianForestYoungster2Text:
	text_asm
	ld hl, ViridianForestTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

ViridianForestYoungster3Text:
	text_asm
	ld hl, ViridianForestTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

ViridianForestYoungster4Text:
	text_asm
	ld hl, ViridianForestTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd
    
ViridianForestYoungster5Text:
	text_asm
	ld hl, ViridianForestTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

ViridianForestYoungster2BattleText:
	text_far _ViridianForestYoungster2BattleText
	text_end

ViridianForestYoungster2EndBattleText:
	text_far _ViridianForestYoungster2EndBattleText
	text_end

ViridianForestYoungster2AfterBattleText:
	text_far _ViridianForestYoungster2AfterBattleText
	text_end

ViridianForestYoungster3BattleText:
	text_far _ViridianForestYoungster3BattleText
	text_end

ViridianForestYoungster3EndBattleText:
	text_far _ViridianForestYoungster3EndBattleText
	text_end

ViridianForestYoungster3AfterBattleText:
	text_far _ViridianForestYoungster3AfterBattleText
	text_end

ViridianForestYoungster4BattleText:
	text_far _ViridianForestYoungster4BattleText
	text_end

ViridianForestYoungster4EndBattleText:
	text_far _ViridianForestYoungster4EndBattleText
	text_end

ViridianForestYoungster4AfterBattleText:
	text_far _ViridianForestYoungster4AfterBattleText
	text_end

ViridianForestYoungster5BattleText:
	text_far _ViridianForestYoungster4BattleText
	text_end

ViridianForestYoungster5EndBattleText:
	text_far _ViridianForestYoungster4EndBattleText
	text_end

ViridianForestYoungster5AfterBattleText:
	text_far _ViridianForestYoungster4AfterBattleText
	text_end
    
ViridianForestYoungster6Text:
	text_far _ViridianForestYoungster5Text
	text_end

ViridianForestTrainerTips1Text:
	text_far _ViridianForestTrainerTips1Text
	text_end

ViridianForestUseAntidoteSignText:
	text_far _ViridianForestUseAntidoteSignText
	text_end

ViridianForestTrainerTips2Text:
	text_far _ViridianForestTrainerTips2Text
	text_end

ViridianForestTrainerTips3Text:
	text_far _ViridianForestTrainerTips3Text
	text_end

ViridianForestTrainerTips4Text:
	text_far _ViridianForestTrainerTips4Text
	text_end

ViridianForestLeavingSignText:
	text_far _ViridianForestLeavingSignText
	text_end



    ;SetEvent EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_4
    ;ld a, TEXT_REWARDROOM_REWARD_VENDOR_1
	;ldh [hTextID], a
	;call DisplayTextID
	;script_rogue_reward
    ;ret
;	text_asm
;	CheckEvent EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_4
;	jr z, .beforeBeat
;	CheckEventReuseA EVENT_GOT_ROGUE_POKEMON
;	jr nz, .afterBeat
;	call z, GiveRewardViridian
;	call DisableWaitingAfterTextDisplay
;	jr .done
;.afterBeat
;	ld hl, .post_reward
;	call PrintText
;	jr .done
;.beforeBeat
;	ld hl, .PreBattleText
;	call PrintText
;	ld hl, wStatusFlags3
;	set BIT_TALKED_TO_TRAINER, [hl]
;	set BIT_PRINT_END_BATTLE_TEXT, [hl]
;	;ld hl, CeruleanGymMistyReceivedCascadeBadgeText
;	;ld de, CeruleanGymMistyReceivedCascadeBadgeText
;	;call SaveEndBattleTextPointers
;	ldh a, [hSpriteIndex]
;	ld [wSpriteIndex], a
;	call EngageMapTrainer
;	call InitBattleEnemyParameters
;	;ld a, $2
;	;ld [wGymLeaderNo], a
;	;xor a
;	;ldh [hJoyHeld], a
;	;ld a, SCRIPT_CERULEANGYM_MISTY_POST_BATTLE
;	;ld [wCeruleanGymCurScript], a
;.done
;	jp TextScriptEnd
;
;.PreBattleText:
;	text_far _ViridianForestYoungster2BattleText
;	text_end
;
;.post_reward:
;	text_far _ViridianForestYoungster4EndBattleText
;	text_end

;CeruleanGymMistyReceivedTM11Text:
;	text_far _CeruleanGymMistyReceivedTM11Text
;	sound_get_item_1
;	text_end

;CeruleanGymMistyTM11NoRoomText:
;	text_far _CeruleanGymMistyTM11NoRoomText
;	text_end

;CeruleanGymMistyReceivedCascadeBadgeText:
;	text_far _CeruleanGymMistyReceivedCascadeBadgeText
;	sound_get_key_item ; actually plays the second channel of SFX_BALL_POOF due to the wrong music bank being loaded
;	text_promptbutton
;	text_end

;CeruleanGymMistyPostBattleScript:
;	ld a, [wIsInBattle]
;	cp $ff
;	jp z, CeruleanGymResetScripts
;	ld a, PAD_CTRL_PAD
;	ld [wJoyIgnore], a
;
;GiveRewardViridian:
;	SetEvent EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_4
;	script_rogue_reward
	;SetEvent EVENT_GOT_TM11
	;jr .gymVictory
;.BagFull
;	ld a, TEXT_CERULEANGYM_MISTY_TM11_NO_ROOM
;	ldh [hTextID], a
;	call DisplayTextID
;.gymVictory
;	ld hl, wObtainedBadges
;	set BIT_CASCADEBADGE, [hl]
;	ld hl, wBeatGymFlags
;	set BIT_CASCADEBADGE, [hl]

	; deactivate gym trainers


ViridianForestCooltrainer_FText:
    text_asm
	farcall Delay3
    xor a
    ld a, TEXT_VIRIDIANFOREST_REWARD_VENDOR_1
	ldh [hTextID], a
	call DisplayTextID
    jp TextScriptEnd

Rogue_ViridianForest_Reward_Text:
script_rogue_reward