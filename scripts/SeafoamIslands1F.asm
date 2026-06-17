DEF SEAFOAM_ISLANDS_1F_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_4 % 8))

SeafoamIslands1F_Script:

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
    ld a, [wEventFlags + (EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_0 / 8)]
    and SEAFOAM_ISLANDS_1F_ALL_TRAINERS_MASK
    cp SEAFOAM_ISLANDS_1F_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_SEAFOAMISLANDS1F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, SeafoamIslands1FTrainerHeaders
	ld de, SeafoamIslands1F_ScriptPointers
	ld a, [wSeafoamIslands1FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wSeafoamIslands1FCurScript], a
	ret

	RogueAutoWalkScripts SeafoamIslands1F, PAD_UP, SeafoamIslands1FNormalScript, EVENT_AUTOWALKED_INTO_SEAFOAM_ISLANDS_1F, TEXT_SEAFOAMISLANDS1F_NO_TURNING_BACK, SCRIPT_SEAFOAMISLANDS1F_PLAYER_IS_MOVING, wSeafoamIslands1FCurScript

SeafoamIslands1FEntranceCoords:
	dbmapcoord 17, 4
	dbmapcoord 17, 5
	db -1

SeafoamIslands1FNoCoords:
	dbmapcoord 16, 4
	dbmapcoord 16, 5
	dbmapcoord 15, 4
	dbmapcoord 15, 5
	db -1

SeafoamIslands1F_ScriptPointers:
	def_script_pointers
	dw_const SeafoamIslands1FDefaultScript,         SCRIPT_SEAFOAMISLANDS1F_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_SEAFOAMISLANDS1F_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_SEAFOAMISLANDS1F_END_BATTLE
	dw_const SeafoamIslands1FPlayerIsMovingScript,  SCRIPT_SEAFOAMISLANDS1F_PLAYER_IS_MOVING

SeafoamIslands1FNormalScript:
	call CheckFightingMapTrainers
	ld a, SEAFOAM_ISLANDS_B1F
	ld [wDungeonWarpDestinationMap], a
	ld hl, Seafoam1HolesCoords
	jp IsPlayerOnDungeonWarp

Seafoam1HolesCoords:
	dbmapcoord 17,  6
	dbmapcoord 24,  6
	db -1 ; end

SeafoamIslands1F_TextPointers:
	def_text_pointers
	dw_const SeafoamIslands1FSwimmerText,      TEXT_SEAFOAMISLANDS1F_SWIMMER
	dw_const SeafoamIslands1FCueBallText,      TEXT_SEAFOAMISLANDS1F_CUE_BALL
	dw_const SeafoamIslands1FCooltrainerFText, TEXT_SEAFOAMISLANDS1F_COOLTRAINER_F
	dw_const SeafoamIslands1FHikerText,        TEXT_SEAFOAMISLANDS1F_HIKER
	dw_const SeafoamIslands1FPokemaniacText,   TEXT_SEAFOAMISLANDS1F_POKEMANIAC
	dw_const BoulderText,                  TEXT_SEAFOAMISLANDS1F_BOULDER1
	dw_const BoulderText,                  TEXT_SEAFOAMISLANDS1F_BOULDER2
    dw_const RandomPickUpItemText,         TEXT_SEAFOAMISLANDS1F_RANDOM
    dw_const SeafoamIslands1F_Rogue_Reward_Script_PokeballText_1, TEXT_SEAFOAMISLANDS1F_ROGUE_REWARD_POKEBALL_1
    dw_const SeafoamIslands1F_Rogue_Reward_Script_PokeballText_2, TEXT_SEAFOAMISLANDS1F_ROGUE_REWARD_POKEBALL_2
    dw_const SeafoamIslands1F_Rogue_Reward_Script_PokeballText_3, TEXT_SEAFOAMISLANDS1F_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_SeafoamIslands1F_Reward_Text, TEXT_SEAFOAMISLANDS1F_REWARD_VENDOR_1
    EXPORT TEXT_SEAFOAMISLANDS1F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const SeafoamIslands1FNoTurningBackText, TEXT_SEAFOAMISLANDS1F_NO_TURNING_BACK

SeafoamIslands1FTrainerHeaders:
	def_trainers 1
SeafoamIslands1FTrainerHeader0:
	trainer EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_0, 1, SeafoamIslands1FSwimmerBattleText, SeafoamIslands1FSwimmerEndBattleText, SeafoamIslands1FSwimmerAfterBattleText
SeafoamIslands1FTrainerHeader1:
	trainer EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_1, 1, SeafoamIslands1FCueBallBattleText, SeafoamIslands1FCueBallEndBattleText, SeafoamIslands1FCueBallAfterBattleText
SeafoamIslands1FTrainerHeader2:
	trainer EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_2, 1, SeafoamIslands1FCooltrainerFBattleText, SeafoamIslands1FCooltrainerFEndBattleText, SeafoamIslands1FCooltrainerFAfterBattleText
SeafoamIslands1FTrainerHeader3:
	trainer EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_3, 1, SeafoamIslands1FHikerBattleText, SeafoamIslands1FHikerEndBattleText, SeafoamIslands1FHikerAfterBattleText
SeafoamIslands1FTrainerHeader4:
	trainer EVENT_BEAT_SEAFOAM_ISLANDS_1F_TRAINER_4, 1, SeafoamIslands1FPokemaniacBattleText, SeafoamIslands1FPokemaniacEndBattleText, SeafoamIslands1FPokemaniacAfterBattleText
	db -1 ; end

SeafoamIslands1FSwimmerText:
	text_asm
	ld hl, SeafoamIslands1FTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

SeafoamIslands1FSwimmerBattleText:
	text_far _SeafoamIslands1FSwimmer1BattleText
	text_end

SeafoamIslands1FSwimmerEndBattleText:
	text_far _SeafoamIslands1FSwimmer1EndBattleText
	text_end

SeafoamIslands1FSwimmerAfterBattleText:
	text_far _SeafoamIslands1FSwimmer1AfterBattleText
	text_end

SeafoamIslands1FCueBallText:
	text_asm
	ld hl, SeafoamIslands1FTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

SeafoamIslands1FCueBallBattleText:
	text_far _SeafoamIslands1FSwimmer1BattleText
	text_end

SeafoamIslands1FCueBallEndBattleText:
	text_far _SeafoamIslands1FSwimmer1EndBattleText
	text_end

SeafoamIslands1FCueBallAfterBattleText:
	text_far _SeafoamIslands1FSwimmer1AfterBattleText
	text_end

SeafoamIslands1FCooltrainerFText:
	text_asm
	ld hl, SeafoamIslands1FTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

SeafoamIslands1FCooltrainerFBattleText:
	text_far _SeafoamIslands1FSwimmer1BattleText
	text_end

SeafoamIslands1FCooltrainerFEndBattleText:
	text_far _SeafoamIslands1FSwimmer1EndBattleText
	text_end

SeafoamIslands1FCooltrainerFAfterBattleText:
	text_far _SeafoamIslands1FSwimmer1AfterBattleText
	text_end

SeafoamIslands1FHikerText:
	text_asm
	ld hl, SeafoamIslands1FTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

SeafoamIslands1FHikerBattleText:
	text_far _SeafoamIslands1FSwimmer1BattleText
	text_end

SeafoamIslands1FHikerEndBattleText:
	text_far _SeafoamIslands1FSwimmer1EndBattleText
	text_end

SeafoamIslands1FHikerAfterBattleText:
	text_far _SeafoamIslands1FSwimmer1AfterBattleText
	text_end

SeafoamIslands1FPokemaniacText:
	text_asm
	ld hl, SeafoamIslands1FTrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

SeafoamIslands1FPokemaniacBattleText:
	text_far _SeafoamIslands1FSwimmer1BattleText
	text_end

SeafoamIslands1FPokemaniacEndBattleText:
	text_far _SeafoamIslands1FSwimmer1EndBattleText
	text_end

SeafoamIslands1FPokemaniacAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, SeafoamIslands1FGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_SEAFOAMISLANDS1F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Rogue_SeafoamIslands1F_Reward_Text:
script_rogue_reward

SeafoamIslands1F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

SeafoamIslands1F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

SeafoamIslands1F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

SeafoamIslands1FNoTurningBackText:
	text_far _NoTurningBackText
	text_end

SeafoamIslands1FGreedyText:
	text_far _GreedyText
	text_end
