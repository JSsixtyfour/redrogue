DEF POWER_PLANT_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_POWER_PLANT_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_POWER_PLANT_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_POWER_PLANT_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_POWER_PLANT_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_POWER_PLANT_TRAINER_4 % 8))

PowerPlant_Script:

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
    ld a, [wEventFlags + (EVENT_BEAT_POWER_PLANT_TRAINER_0 / 8)]
    and POWER_PLANT_ALL_TRAINERS_MASK
    cp POWER_PLANT_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_POWERPLANT_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, PowerPlantTrainerHeaders
	ld de, PowerPlant_ScriptPointers
	ld a, [wPowerPlantCurScript]
	call ExecuteCurMapScriptInTable
	ld [wPowerPlantCurScript], a
	ret

	RogueAutoWalkScripts PowerPlant, PAD_UP, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_POWER_PLANT, TEXT_POWERPLANT_NO_TURNING_BACK, SCRIPT_POWERPLANT_PLAYER_IS_MOVING, wPowerPlantCurScript

PowerPlantEntranceCoords:
	dbmapcoord 35, 4
	dbmapcoord 35, 5
	db -1

PowerPlantNoCoords:
	dbmapcoord 34, 4
	dbmapcoord 34, 5
	dbmapcoord 33, 4
	dbmapcoord 33, 5
	db -1

PowerPlant_ScriptPointers:
	def_script_pointers
	dw_const PowerPlantDefaultScript,               SCRIPT_POWERPLANT_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_POWERPLANT_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_POWERPLANT_END_BATTLE
	dw_const PowerPlantPlayerIsMovingScript,        SCRIPT_POWERPLANT_PLAYER_IS_MOVING

PowerPlant_TextPointers:
	def_text_pointers
	dw_const PowerPlantScientist1Text,  TEXT_POWERPLANT_SCIENTIST1
	dw_const PowerPlantPokemaniac1Text,  TEXT_POWERPLANT_POKEMANIAC1
	dw_const PowerPlantPokemaniac2Text,  TEXT_POWERPLANT_POKEMANIAC2
	dw_const PowerPlantScientist4Text,  TEXT_POWERPLANT_SCIENTIST4
	dw_const PowerPlantCooltrainerMText,  TEXT_POWERPLANT_COOLTRAINER_M
	dw_const PowerPlantVoltorb1Text,    TEXT_POWERPLANT_VOLTORB1
	dw_const PowerPlantVoltorb2Text,    TEXT_POWERPLANT_VOLTORB2
	dw_const PowerPlantVoltorb3Text,    TEXT_POWERPLANT_VOLTORB3
	dw_const PowerPlantVoltorb4Text,    TEXT_POWERPLANT_VOLTORB4
	dw_const PowerPlantZapdosText,      TEXT_POWERPLANT_ZAPDOS
    dw_const RandomPickUpItemText,      TEXT_POWERPLANT_RANDOM
    dw_const PowerPlant_Rogue_Reward_Script_PokeballText_1, TEXT_POWERPLANT_ROGUE_REWARD_POKEBALL_1
    dw_const PowerPlant_Rogue_Reward_Script_PokeballText_2, TEXT_POWERPLANT_ROGUE_REWARD_POKEBALL_2
    dw_const PowerPlant_Rogue_Reward_Script_PokeballText_3, TEXT_POWERPLANT_ROGUE_REWARD_POKEBALL_3
    dw_const PowerPlant_Rogue_Reward_Script_PokeballText_1, TEXT_POWERPLANT_ROGUE_TRADE_NPC
    dw_const Rogue_PowerPlant_Reward_Text, TEXT_POWERPLANT_REWARD_VENDOR_1
    EXPORT TEXT_POWERPLANT_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const PowerPlantNoTurningBackText, TEXT_POWERPLANT_NO_TURNING_BACK

PowerPlantTrainerHeaders:
	def_trainers 1
PowerPlantScientist1Header:
	trainer EVENT_BEAT_POWER_PLANT_TRAINER_0, 3, PowerPlantScientist1BattleText, PowerPlantScientist1EndBattleText, PowerPlantScientist1AfterBattleText
PowerPlantPokemaniac1Header:
	trainer EVENT_BEAT_POWER_PLANT_TRAINER_1, 3, PowerPlantPokemaniac1BattleText, PowerPlantPokemaniac1EndBattleText, PowerPlantPokemaniac1AfterBattleText
PowerPlantPokemaniac2Header:
	trainer EVENT_BEAT_POWER_PLANT_TRAINER_2, 3, PowerPlantPokemaniac2BattleText, PowerPlantPokemaniac2EndBattleText, PowerPlantPokemaniac2AfterBattleText
PowerPlantScientist4Header:
	trainer EVENT_BEAT_POWER_PLANT_TRAINER_3, 3, PowerPlantScientist4BattleText, PowerPlantScientist4EndBattleText, PowerPlantScientist4AfterBattleText
PowerPlantCooltrainerMHeader:
	trainer EVENT_BEAT_POWER_PLANT_TRAINER_4, 3, PowerPlantCooltrainerMBattleText, PowerPlantCooltrainerMEndBattleText, PowerPlantCooltrainerMAfterBattleText
	db -1 ; end

PowerPlantInitBattleScript:
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wPowerPlantCurScript], a
	jp TextScriptEnd

PowerPlantVoltorb1Text:
	text_far _PowerPlantVoltorbBattleText
	text_end

PowerPlantVoltorb2Text:
	text_far _PowerPlantVoltorbBattleText
	text_end

PowerPlantVoltorb3Text:
	text_far _PowerPlantVoltorbBattleText
	text_end

PowerPlantVoltorb4Text:
	text_far _PowerPlantVoltorbBattleText
	text_end

PowerPlantZapdosText:
	text_far _PowerPlantZapdosBattleText
	text_end

PowerPlantScientist1Text:
	text_asm
	ld hl, PowerPlantScientist1Header
	call TalkToTrainer
	jp TextScriptEnd

PowerPlantPokemaniac1Text:
	text_asm
	ld hl, PowerPlantPokemaniac1Header
	call TalkToTrainer
	jp TextScriptEnd

PowerPlantPokemaniac2Text:
	text_asm
	ld hl, PowerPlantPokemaniac2Header
	call TalkToTrainer
	jp TextScriptEnd

PowerPlantScientist4Text:
	text_asm
	ld hl, PowerPlantScientist4Header
	call TalkToTrainer
	jp TextScriptEnd

PowerPlantCooltrainerMText:
	text_asm
	ld hl, PowerPlantCooltrainerMHeader
	call TalkToTrainer
	jp TextScriptEnd

PowerPlantVoltorbBattleText:
	text_far _PowerPlantVoltorbBattleText
	text_end

PowerPlantZapdosBattleText:
	text_far _PowerPlantZapdosBattleText
	text_asm
	ld a, ZAPDOS
	call PlayCry
	call WaitForSoundToFinish
	jp TextScriptEnd

PowerPlantScientist1BattleText:
	text_far _PowerPlantScientist1BattleText
	text_end

PowerPlantScientist1EndBattleText:
	text_far _PowerPlantScientist1EndBattleText
	text_end

PowerPlantScientist1AfterBattleText:
	text_far _PowerPlantScientist1AfterBattleText
	text_end

PowerPlantPokemaniac1BattleText:
	text_far _PowerPlantScientist1BattleText
	text_end

PowerPlantPokemaniac1EndBattleText:
	text_far _PowerPlantScientist1EndBattleText
	text_end

PowerPlantPokemaniac1AfterBattleText:
	text_far _PowerPlantScientist1AfterBattleText
	text_end

PowerPlantPokemaniac2BattleText:
	text_far _PowerPlantScientist1BattleText
	text_end

PowerPlantPokemaniac2EndBattleText:
	text_far _PowerPlantScientist1EndBattleText
	text_end

PowerPlantPokemaniac2AfterBattleText:
	text_far _PowerPlantScientist1AfterBattleText
	text_end

PowerPlantScientist4BattleText:
	text_far _PowerPlantScientist1BattleText
	text_end

PowerPlantScientist4EndBattleText:
	text_far _PowerPlantScientist1EndBattleText
	text_end

PowerPlantScientist4AfterBattleText:
	text_far _PowerPlantScientist1AfterBattleText
	text_end

PowerPlantCooltrainerMBattleText:
	text_far _PowerPlantScientist1BattleText
	text_end

PowerPlantCooltrainerMEndBattleText:
	text_far _PowerPlantScientist1EndBattleText
	text_end

PowerPlantCooltrainerMAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, PowerPlantGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_POWERPLANT_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Rogue_PowerPlant_Reward_Text:
script_rogue_reward

PowerPlant_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

PowerPlant_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

PowerPlant_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

PowerPlantNoTurningBackText:
	text_far _NoTurningBackText
	text_end

PowerPlantGreedyText:
	text_far _GreedyText
	text_end
