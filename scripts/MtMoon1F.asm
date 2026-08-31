DEF MT_MOON_1_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_MT_MOON_1_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_MT_MOON_1_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_MT_MOON_1_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_MT_MOON_1_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_MT_MOON_1_TRAINER_4 % 8))

MtMoon1F_Script:

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
    ld a, [wEventFlags + (EVENT_BEAT_MT_MOON_1_TRAINER_0 / 8)]
    and MT_MOON_1_ALL_TRAINERS_MASK
    cp MT_MOON_1_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_MTMOON1F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, MtMoon1TrainerHeaders
	ld de, MtMoon1F_ScriptPointers
	ld a, [wMtMoon1FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wMtMoon1FCurScript], a
	ret

	RogueAutoWalkScripts MtMoon1F, PAD_UP, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_MT_MOON_1F, TEXT_MTMOON1F_NO_TURNING_BACK, SCRIPT_MTMOON1F_PLAYER_IS_MOVING, wMtMoon1FCurScript

MtMoon1FEntranceCoords:
	dbmapcoord 14, 35
	dbmapcoord 15, 35
	db -1

MtMoon1FNoCoords:
	dbmapcoord 14, 34
	dbmapcoord 15, 34
	dbmapcoord 14, 33
	dbmapcoord 15, 33
	db -1

MtMoon1F_ScriptPointers:
	def_script_pointers
	dw_const MtMoon1FDefaultScript,                 SCRIPT_MTMOON1F_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_MTMOON1F_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_MTMOON1F_END_BATTLE
	dw_const MtMoon1FPlayerIsMovingScript,          SCRIPT_MTMOON1F_PLAYER_IS_MOVING

MtMoon1F_TextPointers:
	def_text_pointers
	dw_const MtMoon1FLassText,       TEXT_MTMOON1F_LASS
	dw_const MtMoon1FBugCatcherText, TEXT_MTMOON1F_BUG_CATCHER
	dw_const MtMoon1FSuperNerdText,  TEXT_MTMOON1F_SUPER_NERD
	dw_const MtMoon1FYoungsterText,  TEXT_MTMOON1F_YOUNGSTER
	dw_const MtMoon1FHikerText,      TEXT_MTMOON1F_HIKER
	dw_const PickUpItemText,         TEXT_MTMOON1F_POTION1
	dw_const PickUpItemText,            TEXT_MTMOON1F_MOON_STONE
	dw_const PickUpItemText,            TEXT_MTMOON1F_RARE_CANDY
	dw_const PickUpItemText,            TEXT_MTMOON1F_POTION2
    dw_const RandomPickUpItemText,      TEXT_MTMOON1F_RANDOM
    dw_const MtMoon1F_Rogue_Reward_Script_PokeballText_1, TEXT_MTMOON1F_ROGUE_REWARD_POKEBALL_1
    dw_const MtMoon1F_Rogue_Reward_Script_PokeballText_2, TEXT_MTMOON1F_ROGUE_REWARD_POKEBALL_2
    dw_const MtMoon1F_Rogue_Reward_Script_PokeballText_3, TEXT_MTMOON1F_ROGUE_REWARD_POKEBALL_3
    dw_const MtMoon1F_Rogue_Reward_Script_PokeballText_1, TEXT_MTMOON1F_ROGUE_TRADE_NPC
    dw_const Rogue_MtMoon1F_Reward_Text, TEXT_MTMOON1F_REWARD_VENDOR_1
    EXPORT TEXT_MTMOON1F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const MtMoon1FBewareZubatSign,   TEXT_MTMOON1F_BEWARE_ZUBAT_SIGN
	dw_const MtMoon1FNoTurningBackText, TEXT_MTMOON1F_NO_TURNING_BACK

MtMoon1TrainerHeaders:
	def_trainers 1
MtMoon1TrainerHeader0:
	trainer EVENT_BEAT_MT_MOON_1_TRAINER_0, 2, MtMoon1FLassBattleText, MtMoon1FLassEndBattleText, MtMoon1FLassAfterBattleText
MtMoon1TrainerHeader1:
	trainer EVENT_BEAT_MT_MOON_1_TRAINER_1, 3, MtMoon1FBugCatcherBattleText, MtMoon1FBugCatcherEndBattleText, MtMoon1FBugCatcherAfterBattleText
MtMoon1TrainerHeader2:
	trainer EVENT_BEAT_MT_MOON_1_TRAINER_2, 3, MtMoon1FSuperNerdBattleText, MtMoon1FSuperNerdEndBattleText, MtMoon1FSuperNerdAfterBattleText
MtMoon1TrainerHeader3:
	trainer EVENT_BEAT_MT_MOON_1_TRAINER_3, 3, MtMoon1FYoungsterBattleText, MtMoon1FYoungsterEndBattleText, MtMoon1FYoungsterAfterBattleText
MtMoon1TrainerHeader4:
	trainer EVENT_BEAT_MT_MOON_1_TRAINER_4, 3, MtMoon1FHikerBattleText, MtMoon1FHikerEndBattleText, MtMoon1FHikerAfterBattleText
	db -1 ; end

MtMoon1FLassText:
	text_asm
	ld hl, MtMoon1TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

MtMoon1FBugCatcherText:
	text_asm
	ld hl, MtMoon1TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

MtMoon1FSuperNerdText:
	text_asm
	ld hl, MtMoon1TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

MtMoon1FYoungsterText:
	text_asm
	ld hl, MtMoon1TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

MtMoon1FHikerText:
	text_asm
	ld hl, MtMoon1TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

MtMoon1FLassBattleText:
	text_far _MtMoon1FCooltrainerF1BattleText
	text_end

MtMoon1FLassEndBattleText:
	text_far _MtMoon1FCooltrainerF1EndBattleText
	text_end

MtMoon1FLassAfterBattleText:
	text_far _MtMoon1FCooltrainerF1AfterBattleText
	text_end

MtMoon1FBugCatcherBattleText:
	text_far _MtMoon1FYoungster2BattleText
	text_end

MtMoon1FBugCatcherEndBattleText:
	text_far _MtMoon1FYoungster2EndBattleText
	text_end

MtMoon1FBugCatcherAfterBattleText:
	text_far _MtMoon1FYoungster2AfterBattleText
	text_end

MtMoon1FSuperNerdBattleText:
	text_far _MtMoon1FSuperNerdBattleText
	text_end

MtMoon1FSuperNerdEndBattleText:
	text_far _MtMoon1FSuperNerdEndBattleText
	text_end

MtMoon1FSuperNerdAfterBattleText:
	text_far _MtMoon1FSuperNerdAfterBattleText
	text_end

MtMoon1FYoungsterBattleText:
	text_far _MtMoon1FYoungster1BattleText
	text_end

MtMoon1FYoungsterEndBattleText:
	text_far _MtMoon1FYoungster1EndBattleText
	text_end

MtMoon1FYoungsterAfterBattleText:
	text_far _MtMoon1FYoungster1AfterBattleText
	text_end

; Conditional trainer text (vanilla Hiker vs Giovanni mini-boss). text_asm
; handler: must not clobber bc (live print cursor), must return hl -> the
; chosen text (see Route1JrTrainerMBattleText for the established pattern).
MtMoon1FHikerBattleText:
	text_asm
	ld a, [wRogueFlagsBitfield]
	bit BIT_MINIBOSS_ACTIVE, a
	ld hl, .Vanilla
	ret z
	ld hl, .GiovanniMiniBoss
	ret
.Vanilla
	text_far _MtMoon1FHikerBattleText
	text_end
.GiovanniMiniBoss
	text_far _GiovanniMiniBossBattleText
	text_end

MtMoon1FHikerEndBattleText:
	text_asm
	ld a, [wRogueFlagsBitfield]
	bit BIT_MINIBOSS_ACTIVE, a
	ld hl, .Vanilla
	ret z
	ld hl, .GiovanniMiniBoss
	ret
.Vanilla
	text_far _MtMoon1FHikerEndBattleText
	text_end
.GiovanniMiniBoss
	text_far _GiovanniMiniBossEndBattleText
	text_end

MtMoon1FHikerAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, MtMoon1FGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_MTMOON1F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

MtMoon1FBewareZubatSign:
	text_far _MtMoon1FBewareZubatSign
	text_end

Rogue_MtMoon1F_Reward_Text:
script_rogue_reward

MtMoon1F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

MtMoon1F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

MtMoon1F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

MtMoon1FNoTurningBackText:
	text_far _NoTurningBackText
	text_end

MtMoon1FGreedyText:
	text_far _GreedyText
	text_end
