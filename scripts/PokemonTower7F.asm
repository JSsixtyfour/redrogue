DEF POKEMONTOWER_7_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_POKEMONTOWER_7_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_POKEMONTOWER_7_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_POKEMONTOWER_7_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_POKEMONTOWER_7_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_POKEMONTOWER_7_TRAINER_4 % 8))

PokemonTower7F_Script:

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
    ; Wait while a scripted sequence owns input (the beaten rocket's walk to the
    ; stairs masks the D-pad until HideNPCScript clears it). Offering now opened
    ; the reward menu with the D-pad masked: the cursor couldn't move.
    ldh a, [hJoyIgnore]
    and a
    jr nz, .afterRewardCheck
    ld a, [wStatusFlags3]
    bit BIT_PRINT_END_BATTLE_TEXT, a
    jr nz, .afterRewardCheck
    ld a, [wEventFlags + (EVENT_BEAT_POKEMONTOWER_7_TRAINER_0 / 8)]
    and POKEMONTOWER_7_ALL_TRAINERS_MASK
    cp POKEMONTOWER_7_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    call Delay3
    ld a, TEXT_POKEMONTOWER7F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, PokemonTower7TrainerHeaders
	ld de, PokemonTower7F_ScriptPointers
	ld a, [wPokemonTower7FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wPokemonTower7FCurScript], a
	ret

PokemonTower7FSetDefaultScript:
	xor a
	ldh [hJoyIgnore], a
	ld [wPokemonTower7FCurScript], a ; SCRIPT_POKEMONTOWER7F_DEFAULT
	ld [wCurMapScript], a ; SCRIPT_POKEMONTOWER7F_DEFAULT
	ret

	RogueAutoWalkScripts PokemonTower7F, PAD_UP, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_POKEMON_TOWER_7F, TEXT_POKEMONTOWER7F_NO_TURNING_BACK, SCRIPT_POKEMONTOWER7F_PLAYER_IS_MOVING, wPokemonTower7FCurScript

; No forced walk-in on 7F (deliberate). The player lands on warp 1, (9,16), and
; the tile above it is wall, so every way out of the arrival tile crosses row 16:
; any "no turning back" tile there would fire on the first step. (9,16) is a
; WARP_NO_RETURN warp that WarpFound2 already refuses, so nothing is lost. Both
; lists are empty and the default script just runs CheckFightingMapTrainers.
PokemonTower7FEntranceCoords:
	db -1

PokemonTower7FNoCoords:
	db -1

PokemonTower7F_ScriptPointers:
	def_script_pointers
	dw_const PokemonTower7FDefaultScript,           SCRIPT_POKEMONTOWER7F_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_POKEMONTOWER7F_START_BATTLE
	dw_const PokemonTower7FEndBattleScript,         SCRIPT_POKEMONTOWER7F_END_BATTLE
	dw_const PokemonTower7FHideNPCScript,           SCRIPT_POKEMONTOWER7F_HIDE_NPC
	dw_const PokemonTower7FWarpToMrFujiHouseScript, SCRIPT_POKEMONTOWER7F_WARP_TO_MR_FUJI_HOUSE
	dw_const PokemonTower7FPlayerIsMovingScript,    SCRIPT_POKEMONTOWER7F_PLAYER_IS_MOVING

PokemonTower7FEndBattleScript:
	ld hl, wMiscFlags
	res BIT_SEEN_BY_TRAINER, [hl]
	ldh a, [hIsInBattle]
	cp $ff
	jp z, PokemonTower7FSetDefaultScript
	call EndTrainerBattle
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ldh a, [hActiveSpriteIndex]
	ldh [hSpriteIndex], a
	call DisplayTextID
	call PokemonTower7FRocketLeaveMovementScript
	ld a, SCRIPT_POKEMONTOWER7F_HIDE_NPC
	ld [wPokemonTower7FCurScript], a
	ld [wCurMapScript], a
	ret

PokemonTower7FHideNPCScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ld hl, wToggleableObjectList
	ldh a, [hActiveSpriteIndex]
	ld b, a
.toggleableObjectsListLoop
	ld a, [hli]
	cp -1           ; end of list: not toggleable, so leave it (the old unbounded
	jr z, .notToggleable ; search ran off the list and hid a random object)
	cp b            ; search for sprite ID in toggleable objects list
	ld a, [hli]
	jr nz, .toggleableObjectsListLoop
	ld [wToggleableObjectIndex], a   ; remove toggleable object
	predef HideObject
.notToggleable
	xor a
	ldh [hJoyIgnore], a
	ldh [hActiveSpriteIndex], a
	ld [wTrainerHeaderFlagBit], a
	ld a, SCRIPT_POKEMONTOWER7F_DEFAULT
	ld [wPokemonTower7FCurScript], a
	ld [wCurMapScript], a
	ret

PokemonTower7FWarpToMrFujiHouseScript:
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, TOGGLE_POKEMON_TOWER_7F_MR_FUJI
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, SPRITE_FACING_UP
	ld [wSpritePlayerStateData1FacingDirection], a
	; Land exactly where the (10,1) tile warp does: INDIGO_PLATEAU_LOBBY warp 1,
	; stored 0-based. wLastMap is left alone, as the indoor tile-warp path in
	; WarpFound2 leaves it (it is already the lobby, from .randomStage); vanilla's
	; LAVENDER_TOWN here would send the lobby's LAST_MAP warps to Lavender.
	ld a, INDIGO_PLATEAU_LOBBY
	ldh [hWarpDestinationMap], a
	xor a
	ld [wDestinationWarpID], a
	ld hl, wStatusFlags3
	set BIT_WARP_FROM_CUR_SCRIPT, [hl]
	ld a, SCRIPT_POKEMONTOWER7F_DEFAULT
	ld [wPokemonTower7FCurScript], a
	ld [wCurMapScript], a
	ret

PokemonTower7FRocketLeaveMovementScript:
; Walk the beaten rocket down to the stairs row. Each rocket has its own
; -1-terminated list keyed on where the PLAYER stands when the battle ends
; (sight engage, or a talk position). The old vanilla table was keyed on the
; vanilla rocket positions, had no rows for rockets 4/5 and no terminator, so
; it matched the wrong rocket or ran into movement data and walked garbage.
; No match now means no walk: HideNPCScript hides the rocket where it stands.
	ldh a, [hActiveSpriteIndex]
	dec a
	cp 5            ; rockets are object slots 1-5
	ret nc
	add a
	ld hl, PokemonTower7FRocketExitTables
	ld d, 0
	ld e, a
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, [wYCoord]
	ld b, a
	ld a, [wXCoord]
	ld c, a
.loop
	ld a, [hli]
	cp -1
	ret z
	cp b
	jr nz, .skipX
	ld a, [hli]
	cp c
	jr nz, .skipPointer
	ld a, [hli]
	ld d, [hl]
	ld e, a
	ldh a, [hActiveSpriteIndex]
	ldh [hSpriteIndex], a
	jp MoveSprite
.skipX
	inc hl
.skipPointer
	inc hl
	inc hl
	jr .loop

PokemonTower7FRocketExitTables:
	dw PokemonTower7FRocket1Exits
	dw PokemonTower7FRocket2Exits
	dw PokemonTower7FRocket3Exits
	dw PokemonTower7FRocket4Exits
	dw PokemonTower7FRocket5Exits

PokemonTower7FRocket1Exits:
	map_coord_movement 10, 12, PokemonTower7FExit1
	map_coord_movement 11, 12, PokemonTower7FExit2
	map_coord_movement 12, 12, PokemonTower7FExit3
	map_coord_movement  9, 11, PokemonTower7FExit4
	db -1 ; end

PokemonTower7FRocket2Exits:
	map_coord_movement 11, 10, PokemonTower7FExit5
	map_coord_movement 12,  9, PokemonTower7FExit5
	map_coord_movement 10, 10, PokemonTower7FExit6
	map_coord_movement  9, 10, PokemonTower7FExit7
	map_coord_movement 12, 11, PokemonTower7FExit8
	db -1 ; end

PokemonTower7FRocket3Exits:
	map_coord_movement 10,  9, PokemonTower7FExit9
	map_coord_movement  9,  8, PokemonTower7FExit9
	map_coord_movement 11,  9, PokemonTower7FExit10
	map_coord_movement 12,  9, PokemonTower7FExit11
	map_coord_movement  9, 10, PokemonTower7FExit12
	db -1 ; end

PokemonTower7FRocket4Exits:
	map_coord_movement 11,  7, PokemonTower7FExit13
	map_coord_movement 12,  6, PokemonTower7FExit13
	map_coord_movement 12,  8, PokemonTower7FExit14
	db -1 ; end

PokemonTower7FRocket5Exits:
	map_coord_movement 10,  6, PokemonTower7FExit15
	map_coord_movement  9,  5, PokemonTower7FExit15
	map_coord_movement  9,  7, PokemonTower7FExit16
	db -1 ; end

PokemonTower7FExit1: ; U R R D D D D D L L
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit2: ; D D D D L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit3: ; D D D D L L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit4: ; R D D D D L
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit5: ; D D L D D D D L L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit6: ; D D D D D D L L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit7: ; D D D D D D L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit8: ; L D D D D D D L L
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit9: ; D D R D D D D D L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit10: ; D D D D D D D L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit11: ; D D D D D D D L L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit12: ; R D D D D D D D L
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit13: ; D D L D D D D D D D L L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit14: ; L D D D D D D D D D L L
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit15: ; D D R D D D D D D D D L
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7FExit16: ; R D D D D D D D D D D L
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_LEFT
	db -1 ; end

PokemonTower7F_TextPointers:
	def_text_pointers
	dw_const PokemonTower7FRocket1Text,   TEXT_POKEMONTOWER7F_ROCKET1
	dw_const PokemonTower7FRocket2Text,   TEXT_POKEMONTOWER7F_ROCKET2
	dw_const PokemonTower7FRocket3Text,   TEXT_POKEMONTOWER7F_ROCKET3
	dw_const PokemonTower7FRocket4Text, TEXT_POKEMONTOWER7F_ROCKET4
	dw_const PokemonTower7FRocket5Text, TEXT_POKEMONTOWER7F_ROCKET5
	dw_const PokemonTower7FMrFujiText,    TEXT_POKEMONTOWER7F_MR_FUJI
    dw_const RandomPickUpItemText,        TEXT_POKEMONTOWER7F_RANDOM
    dw_const PokemonTower7F_Rogue_Reward_Script_PokeballText_1, TEXT_POKEMONTOWER7F_ROGUE_REWARD_POKEBALL_1
    dw_const PokemonTower7F_Rogue_Reward_Script_PokeballText_2, TEXT_POKEMONTOWER7F_ROGUE_REWARD_POKEBALL_2
    dw_const PokemonTower7F_Rogue_Reward_Script_PokeballText_3, TEXT_POKEMONTOWER7F_ROGUE_REWARD_POKEBALL_3
    dw_const PokemonTower7F_Rogue_Reward_Script_PokeballText_1, TEXT_POKEMONTOWER7F_ROGUE_TRADE_NPC
    dw_const Rogue_PokemonTower7F_Reward_Text, TEXT_POKEMONTOWER7F_REWARD_VENDOR_1
    EXPORT TEXT_POKEMONTOWER7F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const PokemonTower7FNoTurningBackText, TEXT_POKEMONTOWER7F_NO_TURNING_BACK

PokemonTower7TrainerHeaders:
	def_trainers 1
PokemonTower7TrainerHeader0:
	trainer EVENT_BEAT_POKEMONTOWER_7_TRAINER_0, 3, PokemonTower7FRocket1BattleText, PokemonTower7FRocket1EndBattleText, PokemonTower7FRocket1AfterBattleText
PokemonTower7TrainerHeader1:
	trainer EVENT_BEAT_POKEMONTOWER_7_TRAINER_1, 3, PokemonTower7FRocket2BattleText, PokemonTower7FRocket2EndBattleText, PokemonTower7FRocket2AfterBattleText
PokemonTower7TrainerHeader2:
	trainer EVENT_BEAT_POKEMONTOWER_7_TRAINER_2, 3, PokemonTower7FRocket3BattleText, PokemonTower7FRocket3EndBattleText, PokemonTower7FRocket3AfterBattleText
PokemonTower7TrainerHeader3:
	trainer EVENT_BEAT_POKEMONTOWER_7_TRAINER_3, 3, PokemonTower7FRocket4BattleText, PokemonTower7FRocket4EndBattleText, PokemonTower7FRocket4AfterBattleText
PokemonTower7TrainerHeader4:
	trainer EVENT_BEAT_POKEMONTOWER_7_TRAINER_4, 3, PokemonTower7FRocket5BattleText, PokemonTower7FRocket5EndBattleText, PokemonTower7FRocket5AfterBattleText
	db -1 ; end

PokemonTower7FRocket1Text:
	text_asm
	ld hl, PokemonTower7TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower7FRocket2Text:
	text_asm
	ld hl, PokemonTower7TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower7FRocket3Text:
	text_asm
	ld hl, PokemonTower7TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower7FRocket4Text:
	text_asm
	ld hl, PokemonTower7TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower7FRocket5Text:
	text_asm
	ld hl, PokemonTower7TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

PokemonTower7FMrFujiText:
	text_asm
	ld hl, .RescueText
	call PrintText
	SetEvent EVENT_RESCUED_MR_FUJI
	SetEvent EVENT_RESCUED_MR_FUJI_2
	ld a, TOGGLE_MR_FUJIS_HOUSE_MR_FUJI
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, SCRIPT_POKEMONTOWER7F_WARP_TO_MR_FUJI_HOUSE
	ld [wPokemonTower7FCurScript], a
	ld [wCurMapScript], a
	jp TextScriptEnd

.RescueText:
	text_far _PokemonTower7FMrFujiRescueText
	text_end

PokemonTower7FRocket1BattleText:
	text_far _PokemonTower7FRocket1BattleText
	text_end

PokemonTower7FRocket1EndBattleText:
	text_far _PokemonTower7FRocket1EndBattleText
	text_end

PokemonTower7FRocket1AfterBattleText:
	text_far _PokemonTower7FRocket1AfterBattleText
	text_end

PokemonTower7FRocket2BattleText:
	text_far _PokemonTower7FRocket2BattleText
	text_end

PokemonTower7FRocket2EndBattleText:
	text_far _PokemonTower7FRocket2EndBattleText
	text_end

PokemonTower7FRocket2AfterBattleText:
	text_far _PokemonTower7FRocket2AfterBattleText
	text_end

PokemonTower7FRocket3BattleText:
	text_far _PokemonTower7FRocket3BattleText
	text_end

PokemonTower7FRocket3EndBattleText:
	text_far _PokemonTower7FRocket3EndBattleText
	text_end

PokemonTower7FRocket3AfterBattleText:
	text_far _PokemonTower7FRocket3AfterBattleText
	text_end

PokemonTower7FRocket4BattleText:
	text_far _PokemonTower7FRocket1BattleText
	text_end

PokemonTower7FRocket4EndBattleText:
	text_far _PokemonTower7FRocket1EndBattleText
	text_end

PokemonTower7FRocket4AfterBattleText:
	text_far _PokemonTower7FRocket1AfterBattleText
	text_end

PokemonTower7FRocket5BattleText:
	text_far _PokemonTower7FRocket2BattleText
	text_end

PokemonTower7FRocket5EndBattleText:
	text_far _PokemonTower7FRocket2EndBattleText
	text_end

PokemonTower7FRocket5AfterBattleText:
	; Reward menu only once all five are beaten; otherwise (and after the
	; reward is claimed) the boss's own line, or the mini-boss's. See
	; custom_functions/rogue_boss_after_battle.asm.
	text_asm
	ld a, [wEventFlags + (EVENT_BEAT_POKEMONTOWER_7_TRAINER_0 / 8)]
	and POKEMONTOWER_7_ALL_TRAINERS_MASK
	sub POKEMONTOWER_7_ALL_TRAINERS_MASK
	ld e, a                       ; e = 0 iff all five beaten
	farcall RogueBossAfterBattle  ; d = 0 normal / 1 reward / 2 already printed
	dec d
	jr z, .reward
	dec d
	jr z, .done
	ld hl, PokemonTower7FBossAfterText
	call PrintText
	jr .done
.reward
	ld a, TEXT_POKEMONTOWER7F_REWARD_VENDOR_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.done
	jp TextScriptEnd

Rogue_PokemonTower7F_Reward_Text:
script_rogue_reward

PokemonTower7F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

PokemonTower7F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

PokemonTower7F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

PokemonTower7FNoTurningBackText:
	text_far _NoTurningBackText
	text_end

PokemonTower7FBossAfterText:
	text_far _PokemonTower7FRocket2AfterBattleText
	text_end
