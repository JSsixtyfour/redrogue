DEF POKEMON_TOWER_2F_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_4 % 8))

PokemonTower2F_Script:

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
    ld a, [wEventFlags + (EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_0 / 8)]
    and POKEMON_TOWER_2F_ALL_TRAINERS_MASK
    cp POKEMON_TOWER_2F_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_POKEMONTOWER2F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, PokemonTower2FTrainerHeaders
	ld de, PokemonTower2F_ScriptPointers
	ld a, [wPokemonTower2FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wPokemonTower2FCurScript], a
	ret

;PokemonTower2FResetRivalEncounter:
;	xor a ; SCRIPT_POKEMONTOWER2F_DEFAULT
;	ldh [hJoyIgnore], a
;	ld [wPokemonTower2FCurScript], a
;	ld [wCurMapScript], a
;	ret

	RogueAutoWalkScripts PokemonTower2F, PAD_RIGHT, PokemonTower2FNormalScript, EVENT_AUTOWALKED_INTO_POKEMON_TOWER_2F, TEXT_POKEMONTOWER2F_NO_TURNING_BACK, SCRIPT_POKEMONTOWER2F_PLAYER_IS_MOVING, wPokemonTower2FCurScript

PokemonTower2FEntranceCoords:
	dbmapcoord 18, 9
	db -1

PokemonTower2FNoCoords:
	dbmapcoord 19, 9
	dbmapcoord 20, 9
	db -1

PokemonTower2F_ScriptPointers:
	def_script_pointers
	dw_const PokemonTower2FDefaultScript,       SCRIPT_POKEMONTOWER2F_DEFAULT
	;dw_const PokemonTower2FDefeatedRivalScript, SCRIPT_POKEMONTOWER2F_DEFEATED_RIVAL
	;dw_const PokemonTower2FRivalExitsScript,    SCRIPT_POKEMONTOWER2F_RIVAL_EXITS
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_POKEMONTOWER2F_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_POKEMONTOWER2F_END_BATTLE
	dw_const PokemonTower2FPlayerIsMovingScript,    SCRIPT_POKEMONTOWER2F_PLAYER_IS_MOVING

PokemonTower2FNormalScript:
IF DEF(_DEBUG)
	call DebugPressedOrHeldB
	ret nz
ENDC
	call CheckFightingMapTrainers
	ret
	;CheckEvent EVENT_BEAT_POKEMON_TOWER_RIVAL
	;jr nz, .checkTrainers
	;ld hl, PokemonTower2FRivalEncounterEventCoords
	;call ArePlayerCoordsInArray
	;jr nc, .checkTrainers
	;ld a, SFX_STOP_ALL_MUSIC
	;ld [wNewSoundID], a
	;call PlaySound
	;ld c, BANK(Music_MeetRival)
	;ld a, MUSIC_MEET_RIVAL
	;call PlayMusic
	;ResetEvent EVENT_POKEMON_TOWER_RIVAL_ON_LEFT
	;ld a, [wCoordIndex]
	;cp $1
	;ld a, PLAYER_DIR_UP
	;ld b, SPRITE_FACING_DOWN
	;jr nz, .player_below_rival
; the rival is on the left side and the player is on the right side
;	SetEvent EVENT_POKEMON_TOWER_RIVAL_ON_LEFT
;	ld a, PLAYER_DIR_LEFT
;	ld b, SPRITE_FACING_RIGHT
;.player_below_rival
;	ld [wPlayerMovingDirection], a
;	ld a, POKEMONTOWER2F_RIVAL
;	ldh [hSpriteIndex], a
;	ld a, b
;	ldh [hSpriteFacingDirection], a
;	call SetSpriteFacingDirectionAndDelay
;	ld a, TEXT_POKEMONTOWER2F_RIVAL
;	ldh [hTextID], a
;	call DisplayTextID
;	xor a
;	ldh [hJoyHeld], a
;	ldh [hJoyPressed], a
;	ret
;.checkTrainers
;	call CheckFightingMapTrainers
;	ret

;PokemonTower2FRivalEncounterEventCoords:
;	dbmapcoord 15,  5
;	dbmapcoord 14,  6
;	db $0F ; end? (should be $ff?)
;
;PokemonTower2FDefeatedRivalScript:
;	ldh a, [hIsInBattle]
;	cp $ff
;	jp z, PokemonTower2FResetRivalEncounter
;    xor a
;	ld [wIsTrainerBattle], a
;	ld a, PAD_CTRL_PAD
;	ldh [hJoyIgnore], a
;	SetEvent EVENT_BEAT_POKEMON_TOWER_RIVAL
;	ld a, TEXT_POKEMONTOWER2F_RIVAL
;	ldh [hTextID], a
;	call DisplayTextID
;	ld de, PokemonTower2FRivalDownThenRightMovement
;	CheckEvent EVENT_POKEMON_TOWER_RIVAL_ON_LEFT
;	jr nz, .got_movement
;	ld de, PokemonTower2FRivalRightThenDownMovement
;.got_movement
;	ld a, POKEMONTOWER2F_RIVAL
;	ldh [hSpriteIndex], a
;	call MoveSprite
;	ld a, SFX_STOP_ALL_MUSIC
;	ld [wNewSoundID], a
;	call PlaySound
;	farcall Music_RivalAlternateStart
;	ld a, SCRIPT_POKEMONTOWER2F_RIVAL_EXITS
;	ld [wPokemonTower2FCurScript], a
;	ld [wCurMapScript], a
;	ret
;
;PokemonTower2FRivalRightThenDownMovement:
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db -1 ; end
;
;PokemonTower2FRivalDownThenRightMovement:
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_DOWN
;	db -1 ; end
;
;PokemonTower2FRivalExitsScript:
;	ld a, [wStatusFlags5]
;	bit BIT_SCRIPTED_NPC_MOVEMENT, a
;	ret nz
;	ld a, TOGGLE_POKEMON_TOWER_2F_RIVAL
;	ld [wToggleableObjectIndex], a
;	predef HideObject
;	xor a
;	ldh [hJoyIgnore], a
;	call PlayDefaultMusic
;	ld a, SCRIPT_POKEMONTOWER2F_DEFAULT
;	ld [wPokemonTower2FCurScript], a
;	ld [wCurMapScript], a
;	ret

PokemonTower2F_TextPointers:
	def_text_pointers
	dw_const PokemonTower2FChanneler1Text, TEXT_POKEMONTOWER2F_CHANNELER1
	dw_const PokemonTower2FChanneler2Text, TEXT_POKEMONTOWER2F_CHANNELER2
	dw_const PokemonTower2FChanneler3Text, TEXT_POKEMONTOWER2F_CHANNELER3
	dw_const PokemonTower2FChanneler4Text, TEXT_POKEMONTOWER2F_CHANNELER4
	dw_const PokemonTower2FChanneler5Text, TEXT_POKEMONTOWER2F_CHANNELER5
	dw_const PokemonTower2FChannelerText,  TEXT_POKEMONTOWER2F_CHANNELER
    dw_const RandomPickUpItemText,         TEXT_POKEMONTOWER2F_RANDOM
    dw_const PokemonTower2F_Rogue_Reward_Script_PokeballText_1, TEXT_POKEMONTOWER2F_ROGUE_REWARD_POKEBALL_1
    dw_const PokemonTower2F_Rogue_Reward_Script_PokeballText_2, TEXT_POKEMONTOWER2F_ROGUE_REWARD_POKEBALL_2
    dw_const PokemonTower2F_Rogue_Reward_Script_PokeballText_3, TEXT_POKEMONTOWER2F_ROGUE_REWARD_POKEBALL_3
    dw_const PokemonTower2F_Rogue_Reward_Script_PokeballText_1, TEXT_POKEMONTOWER2F_ROGUE_TRADE_NPC
	;dw_const PokemonTower2FRivalText,      TEXT_POKEMONTOWER2F_RIVAL
    dw_const Rogue_PokemonTower2F_Reward_Text, TEXT_POKEMONTOWER2F_REWARD_VENDOR_1
    EXPORT TEXT_POKEMONTOWER2F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const PokemonTower2FNoTurningBackText, TEXT_POKEMONTOWER2F_NO_TURNING_BACK

PokemonTower2FTrainerHeaders:
	def_trainers 1
PokemonTower2FTrainerHeader0:
	trainer EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_0, 1, PokemonTower2FChanneler1BattleText, PokemonTower2FChanneler1EndBattleText, PokemonTower2FChanneler1AfterBattleText
PokemonTower2FTrainerHeader1:
	trainer EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_1, 1, PokemonTower2FChanneler2BattleText, PokemonTower2FChanneler2EndBattleText, PokemonTower2FChanneler2AfterBattleText
PokemonTower2FTrainerHeader2:
	trainer EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_2, 1, PokemonTower2FChanneler3BattleText, PokemonTower2FChanneler3EndBattleText, PokemonTower2FChanneler3AfterBattleText
PokemonTower2FTrainerHeader3:
	trainer EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_3, 1, PokemonTower2FChanneler4BattleText, PokemonTower2FChanneler4EndBattleText, PokemonTower2FChanneler4AfterBattleText
PokemonTower2FTrainerHeader4:
	trainer EVENT_BEAT_POKEMON_TOWER_2F_TRAINER_4, 1, PokemonTower2FChanneler5BattleText, PokemonTower2FChanneler5EndBattleText, PokemonTower2FChanneler5AfterBattleText
	db -1 ; end

PokemonTower2FChanneler1Text:
	text_asm
	ld hl, PokemonTower2FTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower2FChanneler2Text:
	text_asm
	ld hl, PokemonTower2FTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower2FChanneler3Text:
	text_asm
	ld hl, PokemonTower2FTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower2FChanneler4Text:
	text_asm
	ld hl, PokemonTower2FTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower2FChanneler5Text:
	text_asm
	ld hl, PokemonTower2FTrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower2FChanneler1BattleText:
	text_far _PokemonTower2FChanneler1BattleText
	text_end

PokemonTower2FChanneler1EndBattleText:
	text_far _PokemonTower2FChanneler1EndBattleText
	text_end

PokemonTower2FChanneler1AfterBattleText:
	text_far _PokemonTower2FChanneler1AfterBattleText
	text_end

PokemonTower2FChanneler2BattleText:
	text_far _PokemonTower2FChanneler1BattleText
	text_end

PokemonTower2FChanneler2EndBattleText:
	text_far _PokemonTower2FChanneler1EndBattleText
	text_end

PokemonTower2FChanneler2AfterBattleText:
	text_far _PokemonTower2FChanneler1AfterBattleText
	text_end

PokemonTower2FChanneler3BattleText:
	text_far _PokemonTower2FChanneler1BattleText
	text_end

PokemonTower2FChanneler3EndBattleText:
	text_far _PokemonTower2FChanneler1EndBattleText
	text_end

PokemonTower2FChanneler3AfterBattleText:
	text_far _PokemonTower2FChanneler1AfterBattleText
	text_end

PokemonTower2FChanneler4BattleText:
	text_far _PokemonTower2FChanneler1BattleText
	text_end

PokemonTower2FChanneler4EndBattleText:
	text_far _PokemonTower2FChanneler1EndBattleText
	text_end

PokemonTower2FChanneler4AfterBattleText:
	text_far _PokemonTower2FChanneler1AfterBattleText
	text_end

PokemonTower2FChanneler5BattleText:
	text_far _PokemonTower2FChanneler1BattleText
	text_end

PokemonTower2FChanneler5EndBattleText:
	text_far _PokemonTower2FChanneler1EndBattleText
	text_end

PokemonTower2FChanneler5AfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, PokemonTower2FGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_POKEMONTOWER2F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

;PokemonTower2FRivalText:
;	text_asm
;	CheckEvent EVENT_BEAT_POKEMON_TOWER_RIVAL
;	jr z, .do_battle
;	ld hl, .HowsYourDexText
;	call PrintText
;	jr .text_script_end
;.do_battle
;	ld hl, .WhatBringsYouHereText
;	call PrintText
;	ld hl, wStatusFlags3
;	set BIT_TALKED_TO_TRAINER, [hl]
;	set BIT_PRINT_END_BATTLE_TEXT, [hl]
;	ld hl, .DefeatedText
;	ld de, .VictoryText
;	call SaveEndBattleTextPointers
;	ld a, OPP_RIVAL2
;	ld [wCurOpponent], a
;
;	; select which team to use during the encounter
;	ld a, [wRivalStarter]
;	ld b, a
;	ld a, [wRoguePokemon2]
;	cp b
;	jr nz, .NotSlot2
;	ld a, $4
;	jr .done
;.NotSlot2
;	ld a, [wRoguePokemon3]
;	cp b
;	jr nz, .Slot1
;	ld a, $5
;	jr .done
;.Slot1
;	ld a, $6
;.done
;	ld [wTrainerNo], a
;
;    ld a, 1
;	ld [wIsTrainerBattle], a
;	ld a, SCRIPT_POKEMONTOWER2F_DEFEATED_RIVAL
;	ld [wPokemonTower2FCurScript], a
;	ld [wCurMapScript], a
;.text_script_end
;	jp TextScriptEnd
;
;.WhatBringsYouHereText:
;	text_far _PokemonTower2FRivalWhatBringsYouHereText
;	text_end
;
;.DefeatedText:
;	text_far _PokemonTower2FRivalDefeatedText
;	text_end
;
;.VictoryText:
;	text_far _PokemonTower2FRivalVictoryText
;	text_end
;
;.HowsYourDexText:
;	text_far _PokemonTower2FRivalHowsYourDexText
;	text_end

PokemonTower2FChannelerText:
	text_far _PokemonTower2FChannelerText
	text_end

Rogue_PokemonTower2F_Reward_Text:
script_rogue_reward

PokemonTower2F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

PokemonTower2F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

PokemonTower2F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

PokemonTower2FNoTurningBackText:
	text_far _NoTurningBackText
	text_end

PokemonTower2FGreedyText:
	text_far _GreedyText
	text_end
