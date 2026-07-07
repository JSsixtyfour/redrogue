DEF ROUTE12_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_ROUTE_12_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_12_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_12_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_12_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_ROUTE_12_TRAINER_4 % 8))

Route12_Script:

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

    ld a, [wEventFlags + (EVENT_BEAT_ROUTE_12_TRAINER_0 / 8)]
    and ROUTE12_ALL_TRAINERS_MASK
    cp ROUTE12_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck

    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_ROUTE12_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay

    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, Route12TrainerHeaders
	ld de, Route12_ScriptPointers
	ld a, [wRoute12CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute12CurScript], a
	ret

Route12ResetScripts:
	xor a
	ldh [hJoyIgnore], a
	ld [wRoute12CurScript], a
	ld [wCurMapScript], a
	ret

	RogueAutoWalkScripts Route12, PAD_RIGHT, Route12SnorlaxScript, EVENT_AUTOWALKED_INTO_ROUTE_12, TEXT_ROUTE12_NO_TURNING_BACK, SCRIPT_ROUTE12_PLAYER_IS_MOVING, wRoute12CurScript

Route12EntranceCoords:
	dbmapcoord 4, 62
	db -1

Route12NoCoords:
	dbmapcoord 4, 61
	dbmapcoord 4, 60
	db -1

Route12_ScriptPointers:
	def_script_pointers
	dw_const Route12DefaultScript,                  SCRIPT_ROUTE12_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE12_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE12_END_BATTLE
	dw_const Route12SnorlaxPostBattleScript,        SCRIPT_ROUTE12_SNORLAX_POST_BATTLE
	dw_const Route12PlayerIsMovingScript,           SCRIPT_ROUTE12_PLAYER_IS_MOVING

Route12SnorlaxScript:
;	CheckEventHL EVENT_BEAT_ROUTE12_SNORLAX
;	jp nz, CheckFightingMapTrainers
;	CheckEventReuseHL EVENT_FIGHT_ROUTE12_SNORLAX
;	ResetEventReuseHL EVENT_FIGHT_ROUTE12_SNORLAX
;	jp z, CheckFightingMapTrainers
;	ld a, TEXT_ROUTE12_SNORLAX_WOKE_UP
;	ldh [hTextID], a
;	call DisplayTextID
;	ld a, SNORLAX
;	ld [wCurOpponent], a
;	ld a, 30
;	ld [wCurEnemyLevel], a
;    xor a
;	ld [wIsTrainerBattle], a
;	ld a, TOGGLE_ROUTE_12_SNORLAX
;	ld [wToggleableObjectIndex], a
;	predef HideObject
;	ld a, SCRIPT_ROUTE12_SNORLAX_POST_BATTLE
;	ld [wRoute12CurScript], a
;	ld [wCurMapScript], a
	ret
;
Route12SnorlaxPostBattleScript:
;	ldh a, [hIsInBattle]
;	cp $ff
;	jp z, Route12ResetScripts
;	call UpdateSprites
;	ld a, [wBattleResult]
;	cp $2
;	jr z, .caught_snorlax
;	ld a, TEXT_ROUTE12_SNORLAX_CALMED_DOWN
;	ldh [hTextID], a
;	call DisplayTextID
;.caught_snorlax
;	SetEvent EVENT_BEAT_ROUTE12_SNORLAX
;	call Delay3
;	ld a, SCRIPT_ROUTE12_DEFAULT
;	ld [wRoute12CurScript], a
;	ld [wCurMapScript], a
	ret

Route12_TextPointers:
	def_text_pointers
	dw_const Route12SnorlaxText,           TEXT_ROUTE12_SNORLAX
	dw_const Route12Fisher1Text,           TEXT_ROUTE12_FISHER1
	dw_const Route12Fisher2Text,           TEXT_ROUTE12_FISHER2
	dw_const Route12RockerText,            TEXT_ROUTE12_ROCKER
	dw_const Route12JrTrainerMText,        TEXT_ROUTE12_JR_TRAINER_M
	dw_const Route12CooltrainerFText,      TEXT_ROUTE12_COOLTRAINER_F
	dw_const PickUpItemText,               TEXT_ROUTE12_TM_PAY_DAY
	dw_const PickUpItemText,               TEXT_ROUTE12_IRON
    dw_const RandomPickUpItemText,         TEXT_ROUTE12_RANDOM
    dw_const Route12_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE12_ROGUE_REWARD_POKEBALL_1
    dw_const Route12_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE12_ROGUE_REWARD_POKEBALL_2
    dw_const Route12_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE12_ROGUE_REWARD_POKEBALL_3
    dw_const Route12_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE12_ROGUE_TRADE_NPC
    dw_const Rogue_Route12_Reward_Text,    TEXT_ROUTE12_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE12_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route12SignText,              TEXT_ROUTE12_SIGN
	dw_const Route12SportFishingSignText,  TEXT_ROUTE12_SPORT_FISHING_SIGN
	dw_const Route12SnorlaxWokeUpText,     TEXT_ROUTE12_SNORLAX_WOKE_UP
	dw_const Route12SnorlaxCalmedDownText, TEXT_ROUTE12_SNORLAX_CALMED_DOWN
	dw_const Route12NoTurningBackText,     TEXT_ROUTE12_NO_TURNING_BACK

Route12TrainerHeaders:
	def_trainers 1
Route12TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_12_TRAINER_0, 4, Route12Fisher1BattleText, Route12Fisher1EndBattleText, Route12Fisher1AfterBattleText
Route12TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_12_TRAINER_1, 4, Route12Fisher2BattleText, Route12Fisher2EndBattleText, Route12Fisher2AfterBattleText
Route12TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_12_TRAINER_2, 4, Route12RockerBattleText, Route12RockerEndBattleText, Route12RockerAfterBattleText
Route12TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_12_TRAINER_3, 4, Route12JrTrainerMBattleText, Route12JrTrainerMEndBattleText, Route12JrTrainerMAfterBattleText
Route12TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_12_TRAINER_4, 4, Route12CooltrainerFBattleText, Route12CooltrainerFEndBattleText, Route12CooltrainerFAfterBattleText
	db -1 ; end

Route12SnorlaxText:
	text_far _Route12SnorlaxText
	text_end

Route12SnorlaxWokeUpText:
	text_far _Route12SnorlaxWokeUpText
	text_end

Route12SnorlaxCalmedDownText:
	text_far _Route12SnorlaxCalmedDownText
	text_end

Route12Fisher1Text:
	text_asm
	ld hl, Route12TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

Route12Fisher1BattleText:
	text_far _Route12Fisher1BattleText
	text_end

Route12Fisher1EndBattleText:
	text_far _Route12Fisher1EndBattleText
	text_end

Route12Fisher1AfterBattleText:
	text_far _Route12Fisher1AfterBattleText
	text_end

Route12Fisher2Text:
	text_asm
	ld hl, Route12TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

Route12Fisher2BattleText:
	text_far _Route12Fisher2BattleText
	text_end

Route12Fisher2EndBattleText:
	text_far _Route12Fisher2EndBattleText
	text_end

Route12Fisher2AfterBattleText:
	text_far _Route12Fisher2AfterBattleText
	text_end

Route12RockerText:
	text_asm
	ld hl, Route12TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

Route12RockerBattleText:
	text_far _Route12SuperNerdBattleText
	text_end

Route12RockerEndBattleText:
	text_far _Route12SuperNerdEndBattleText
	text_end

Route12RockerAfterBattleText:
	text_far _Route12SuperNerdAfterBattleText
	text_end

Route12JrTrainerMText:
	text_asm
	ld hl, Route12TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

Route12JrTrainerMBattleText:
	text_far _Route12CooltrainerMBattleText
	text_end

Route12JrTrainerMEndBattleText:
	text_far _Route12CooltrainerMEndBattleText
	text_end

Route12JrTrainerMAfterBattleText:
	text_far _Route12CooltrainerMAfterBattleText
	text_end

Route12CooltrainerFText:
	text_asm
	ld hl, Route12TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

Route12CooltrainerFBattleText:
	text_far _Route12Fisher3BattleText
	text_end

Route12CooltrainerFEndBattleText:
	text_far _Route12Fisher3EndBattleText
	text_end

Route12CooltrainerFAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, Route12GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROUTE12_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route12SignText:
	text_far _Route12SignText
	text_end

Route12SportFishingSignText:
	text_far _Route12SportFishingSignText
	text_end

Rogue_Route12_Reward_Text:
script_rogue_reward

Route12_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route12_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route12_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route12NoTurningBackText:
	text_far _NoTurningBackText
	text_end

Route12GreedyText:
	text_far _GreedyText
	text_end
