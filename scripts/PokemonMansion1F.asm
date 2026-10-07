DEF MANSION_1_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_MANSION_1_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_MANSION_1_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_MANSION_1_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_MANSION_1_TRAINER_3 % 8))

PokemonMansion1F_Script:

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
    ld a, [wEventFlags + (EVENT_BEAT_MANSION_1_TRAINER_0 / 8)]
    and MANSION_1_ALL_TRAINERS_MASK
    cp MANSION_1_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    call Delay3
    ld a, TEXT_POKEMONMANSION1F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
	call Mansion1CheckReplaceSwitchDoorBlocks
	call EnableAutoTextBoxDrawing
	ld hl, Mansion1TrainerHeaders
	ld de, PokemonMansion1F_ScriptPointers
	ld a, [wPokemonMansion1FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wPokemonMansion1FCurScript], a
	ret

Mansion1CheckReplaceSwitchDoorBlocks:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_MANSION_SWITCH_ON
	jr nz, .switchTurnedOn
	lb bc, 6, 12
	call Mansion1LoadEmptyFloorTileBlock
	lb bc, 3, 8
	call Mansion1LoadHorizontalGateBlock
	lb bc, 8, 10
	call Mansion1LoadHorizontalGateBlock
	lb bc, 13, 13
	jp Mansion1LoadHorizontalGateBlock
.switchTurnedOn
	lb bc, 6, 12
	call Mansion1LoadHorizontalGateBlock
	lb bc, 3, 8
	call Mansion1LoadEmptyFloorTileBlock
	lb bc, 8, 10
	call Mansion1LoadEmptyFloorTileBlock
	lb bc, 13, 13
	jp Mansion1LoadEmptyFloorTileBlock

Mansion1LoadHorizontalGateBlock:
	ld a, $2d
	ld [wNewTileBlockID], a
	jr Mansion1ReplaceBlock

Mansion1LoadEmptyFloorTileBlock:
	ld a, $e
	ld [wNewTileBlockID], a
Mansion1ReplaceBlock:
	predef ReplaceTileBlock
	ret

Mansion1Script_Switches::
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	ret nz
	xor a
	ldh [hJoyHeld], a
	ld a, TEXT_POKEMONMANSION1F_SWITCH
	ldh [hTextID], a
	jp DisplayTextID

	RogueAutoWalkScripts PokemonMansion1F, PAD_UP, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_POKEMON_MANSION_1F, TEXT_POKEMONMANSION1F_NO_TURNING_BACK, SCRIPT_POKEMONMANSION1F_PLAYER_IS_MOVING, wPokemonMansion1FCurScript

; Entry is the WARP_NO_RETURN row at (4-7,27); push up.
PokemonMansion1FEntranceCoords:
	dbmapcoord 4, 27
	dbmapcoord 5, 27
	dbmapcoord 6, 27
	dbmapcoord 7, 27
	db -1

PokemonMansion1FNoCoords:
	dbmapcoord 4, 26
	dbmapcoord 5, 26
	dbmapcoord 6, 26
	dbmapcoord 7, 26
	dbmapcoord 4, 25
	dbmapcoord 5, 25
	dbmapcoord 6, 25
	dbmapcoord 7, 25
	db -1

PokemonMansion1F_ScriptPointers:
	def_script_pointers
	dw_const PokemonMansion1FDefaultScript,         SCRIPT_POKEMONMANSION1F_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_POKEMONMANSION1F_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_POKEMONMANSION1F_END_BATTLE
	dw_const PokemonMansion1FPlayerIsMovingScript,  SCRIPT_POKEMONMANSION1F_PLAYER_IS_MOVING

PokemonMansion1F_TextPointers:
	def_text_pointers
	dw_const PokemonMansion1FPaddingText,                          TEXT_POKEMONMANSION1F_PADDING
	dw_const PokemonMansion1FScientistText,                        TEXT_POKEMONMANSION1F_SCIENTIST
    dw_const PokemonMansion1FBurglar1Text,                       TEXT_POKEMONMANSION1F_BURGLAR_1
    dw_const PokemonMansion1FBurglar2Text,                       TEXT_POKEMONMANSION1F_BURGLAR_2
    dw_const PokemonMansion1FScientist2Text,                       TEXT_POKEMONMANSION1F_SCIENTIST_2
	dw_const PickUpItemText,                                       TEXT_POKEMONMANSION1F_ESCAPE_ROPE
	dw_const PickUpItemText,                                       TEXT_POKEMONMANSION1F_CARBOS
    dw_const RandomPickUpItemText,                                 TEXT_POKEMONMANSION1F_RANDOM
    dw_const PokemonMansion1F_Rogue_Reward_Script_PokeballText_1,  TEXT_POKEMONMANSION1F_ROGUE_REWARD_POKEBALL_1
    dw_const PokemonMansion1F_Rogue_Reward_Script_PokeballText_2,  TEXT_POKEMONMANSION1F_ROGUE_REWARD_POKEBALL_2
    dw_const PokemonMansion1F_Rogue_Reward_Script_PokeballText_3,  TEXT_POKEMONMANSION1F_ROGUE_REWARD_POKEBALL_3
    dw_const PokemonMansion1F_Rogue_Reward_Script_PokeballText_1,  TEXT_POKEMONMANSION1F_ROGUE_TRADE_NPC
    dw_const Rogue_PokemonMansion1F_Reward_Text,                   TEXT_POKEMONMANSION1F_REWARD_VENDOR_1
    EXPORT TEXT_POKEMONMANSION1F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const PokemonMansion1FSwitchText,                           TEXT_POKEMONMANSION1F_SWITCH
	dw_const PokemonMansion1FNoTurningBackText, TEXT_POKEMONMANSION1F_NO_TURNING_BACK

Mansion1TrainerHeaders:
	def_trainers 2
Mansion1TrainerHeader0:
	trainer EVENT_BEAT_MANSION_1_TRAINER_0, 3, PokemonMansion1FScientistBattleText, PokemonMansion1FScientistEndBattleText, PokemonMansion1FScientistAfterBattleText
Mansion1TrainerHeader1:
	trainer EVENT_BEAT_MANSION_1_TRAINER_1, 2, PokemonMansion1FBurglar1BattleText, PokemonMansion1FBurglar1EndBattleText, PokemonMansion1FBurglar1AfterBattleText
Mansion1TrainerHeader2:
	trainer EVENT_BEAT_MANSION_1_TRAINER_2, 2, PokemonMansion1FBurglar2BattleText, PokemonMansion1FBurglar2EndBattleText, PokemonMansion1FBurglar2AfterBattleText
Mansion1TrainerHeader3:
	trainer EVENT_BEAT_MANSION_1_TRAINER_3, 2, PokemonMansion1FScientist2BattleText, PokemonMansion1FScientist2EndBattleText, PokemonMansion1FScientist2AfterBattleText
	db -1 ; end

; Slot 1's padding object: never drawn or reachable, so it says nothing.
PokemonMansion1FPaddingText:
	text_end

PokemonMansion1FScientistText:
	text_asm
	ld hl, Mansion1TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

PokemonMansion1FBurglar1Text:
	text_asm
	ld hl, Mansion1TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

PokemonMansion1FBurglar2Text:
	text_asm
	ld hl, Mansion1TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

PokemonMansion1FScientist2Text:
	text_asm
	ld hl, Mansion1TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

PokemonMansion1FScientistBattleText:
	text_far _PokemonMansion1FScientistBattleText
	text_end

PokemonMansion1FScientistEndBattleText:
	text_far _PokemonMansion1FScientistEndBattleText
	text_end

PokemonMansion1FScientistAfterBattleText:
	text_far _PokemonMansion1FScientistAfterBattleText
	text_end

PokemonMansion1FBurglar1BattleText:
	text_far _PokemonMansion1FBurglar1BattleText
	text_end

PokemonMansion1FBurglar1EndBattleText:
	text_far _PokemonMansion1FBurglar1EndBattleText
	text_end

PokemonMansion1FBurglar1AfterBattleText:
	text_far _PokemonMansion1FBurglar1AfterBattleText
	text_end

PokemonMansion1FBurglar2BattleText:
	text_far _PokemonMansion1FBurglar2BattleText
	text_end

PokemonMansion1FBurglar2EndBattleText:
	text_far _PokemonMansion1FBurglar2EndBattleText
	text_end

PokemonMansion1FBurglar2AfterBattleText:
	text_far _PokemonMansion1FBurglar2AfterBattleText
	text_end

PokemonMansion1FScientist2BattleText:
	text_far _PokemonMansion1FScientist2BattleText
	text_end

PokemonMansion1FScientist2EndBattleText:
	text_far _PokemonMansion1FScientist2EndBattleText
	text_end

PokemonMansion1FScientist2AfterBattleText:
	; Reward menu only once all four are beaten; otherwise (and after the
	; reward is claimed) the boss's own line, or the mini-boss's. See
	; custom_functions/rogue_boss_after_battle.asm.
	text_asm
	ld a, [wEventFlags + (EVENT_BEAT_MANSION_1_TRAINER_0 / 8)]
	and MANSION_1_ALL_TRAINERS_MASK
	sub MANSION_1_ALL_TRAINERS_MASK
	ld e, a                       ; e = 0 iff all four beaten
	farcall RogueBossAfterBattle  ; d = 0 normal / 1 reward / 2 already printed
	dec d
	jr z, .reward
	dec d
	jr z, .done
	ld hl, PokemonMansion1FBossAfterText
	call PrintText
	jr .done
.reward
	ld a, TEXT_POKEMONMANSION1F_REWARD_VENDOR_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.done
	jp TextScriptEnd

PokemonMansion1FSwitchText:
	text_asm
	ld hl, .Text
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .not_pressed
	ld a, $1
	ldh [hNoWaitAfterText], a
	ld hl, wCurrentMapScriptFlags
	set BIT_CUR_MAP_LOADED_1, [hl]
	ld hl, .PressedText
	call PrintText
	ld a, SFX_GO_INSIDE
	call PlaySound
	CheckAndSetEvent EVENT_MANSION_SWITCH_ON
	jr z, .done
	ResetEventReuseHL EVENT_MANSION_SWITCH_ON
	jr .done
.not_pressed
	ld hl, .NotPressedText
	call PrintText
.done
	jp TextScriptEnd

.Text:
	text_far _PokemonMansion1FSwitchText
	text_end

.PressedText:
	text_far _PokemonMansion1FSwitchPressedText
	text_end

.NotPressedText:
	text_far _PokemonMansion1FSwitchNotPressedText
	text_end

Rogue_PokemonMansion1F_Reward_Text:
script_rogue_reward

PokemonMansion1F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

PokemonMansion1F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

PokemonMansion1F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

PokemonMansion1FNoTurningBackText:
	text_far _NoTurningBackText
	text_end

PokemonMansion1FBossAfterText:
	text_far _PokemonMansion1FScientist2AfterBattleText
	text_end
