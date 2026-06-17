; UNIQUE STAGE: reward is gated by Route24CooltrainerM1Text (the Nugget Bridge NPC),
; which fires after all bridge trainers are beaten — mirrors the vanilla nugget award flow.
; Does NOT use ALL_TRAINERS_MASK in the main loop.
Route24_Script:
    
    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal
    
    SetEvent EVENT_ENTER_ROOM
    ld hl, wRogueFlagsBitfield
    set 0, [hl]                 ; gym is next after this route
    
    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh
    
    .normal
	call EnableAutoTextBoxDrawing
	ld hl, Route24TrainerHeaders
	ld de, Route24_ScriptPointers
	ld a, [wRoute24CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute24CurScript], a
	ret

Route24SetDefaultScript:
	xor a ; SCRIPT_ROUTE24_DEFAULT
	ldh [hJoyIgnore], a
	ld [wRoute24CurScript], a
	ld [wCurMapScript], a
	ret

	RogueAutoWalkScripts Route24, PAD_UP, Route24NuggetScript, EVENT_AUTOWALKED_INTO_ROUTE_24, TEXT_ROUTE24_NO_TURNING_BACK, SCRIPT_ROUTE24_PLAYER_IS_MOVING, wRoute24CurScript

Route24EntranceCoords:
	dbmapcoord 31, 10
	dbmapcoord 31, 11
	db -1

Route24NoCoords:
	dbmapcoord 30, 10
	dbmapcoord 30, 11
	dbmapcoord 29, 10
	dbmapcoord 29, 11
	db -1

Route24_ScriptPointers:
	def_script_pointers
	dw_const Route24DefaultScript,                  SCRIPT_ROUTE24_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE24_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE24_END_BATTLE
	dw_const Route24AfterRocketBattleScript,        SCRIPT_ROUTE24_AFTER_ROCKET_BATTLE
	dw_const Route24PlayerMovingScript,             SCRIPT_ROUTE24_PLAYER_MOVING
	dw_const Route24PlayerIsMovingScript,           SCRIPT_ROUTE24_PLAYER_IS_MOVING

Route24NuggetScript:
	CheckEvent EVENT_GOT_NUGGET
	jp nz, CheckFightingMapTrainers
	ld hl, .PlayerCoordsArray
	call ArePlayerCoordsInArray
	jp nc, CheckFightingMapTrainers
	xor a
	ldh [hJoyHeld], a
	ld a, TEXT_ROUTE24_COOLTRAINER_M1
	ldh [hTextID], a
	call DisplayTextID
	CheckAndResetEvent EVENT_NUGGET_REWARD_AVAILABLE
	ret z
	ld a, PAD_DOWN
	ld [wSimulatedJoypadStatesEnd], a
	ld a, $1
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
	ld a, SCRIPT_ROUTE24_PLAYER_MOVING
	ld [wRoute24CurScript], a
	ld [wCurMapScript], a
	ret

.PlayerCoordsArray:
	dbmapcoord 10, $C
	db -1 ; end

Route24PlayerMovingScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	ld a, SCRIPT_ROUTE24_DEFAULT
	ld [wRoute24CurScript], a
	ld [wCurMapScript], a
	ret

Route24AfterRocketBattleScript:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, Route24SetDefaultScript
	call UpdateSprites
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	SetEvent EVENT_BEAT_ROUTE24_ROCKET
	ld a, TEXT_ROUTE24_COOLTRAINER_M1
	ldh [hTextID], a
	call DisplayTextID
	xor a
	ldh [hJoyIgnore], a
	ld a, SCRIPT_ROUTE24_DEFAULT
	ld [wRoute24CurScript], a
	ld [wCurMapScript], a
	ret

Route24_TextPointers:
	def_text_pointers
	dw_const Route24CooltrainerM1Text, TEXT_ROUTE24_COOLTRAINER_M1
	dw_const Route24CooltrainerM2Text, TEXT_ROUTE24_COOLTRAINER_M2
	dw_const Route24CooltrainerM3Text, TEXT_ROUTE24_COOLTRAINER_M3
	dw_const Route24CooltrainerF1Text, TEXT_ROUTE24_COOLTRAINER_F1
	dw_const Route24Youngster1Text,    TEXT_ROUTE24_YOUNGSTER1
	dw_const Route24CooltrainerF2Text, TEXT_ROUTE24_COOLTRAINER_F2
	dw_const Route24Youngster2Text,    TEXT_ROUTE24_YOUNGSTER2
	dw_const PickUpItemText,           TEXT_ROUTE24_TM_THUNDER_WAVE
    dw_const RandomPickUpItemText,     TEXT_ROUTE24_RANDOM
    dw_const Route24_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE24_ROGUE_REWARD_POKEBALL_1
    dw_const Route24_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE24_ROGUE_REWARD_POKEBALL_2
    dw_const Route24_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE24_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_Route24_Reward_Text, TEXT_ROUTE24_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE24_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route24NoTurningBackText, TEXT_ROUTE24_NO_TURNING_BACK

Route24TrainerHeaders:
	def_trainers 1
Route24TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_24_TRAINER_0, 4, Route24CooltrainerM3BattleText, Route24CooltrainerM3EndBattleText, Route24CooltrainerM3AfterBattleText
Route24TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_24_TRAINER_1, 1, Route24CooltrainerF1BattleText, Route24CooltrainerF1EndBattleText, Route24CooltrainerF1AfterBattleText
Route24TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_24_TRAINER_2, 1, Route24Youngster1BattleText, Route24Youngster1EndBattleText, Route24Youngster1AfterBattleText
Route24TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_24_TRAINER_3, 1, Route24CooltrainerF2BattleText, Route24CooltrainerF2EndBattleText, Route24CooltrainerF2AfterBattleText
Route24TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_24_TRAINER_4, 1, Route24Youngster2BattleText, Route24Youngster2EndBattleText, Route24Youngster2AfterBattleText
	db -1 ; end

Route24CooltrainerM1Text:
    text_asm
    SetEvent EVENT_GOT_NUGGET
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon
   
    ld hl, .YouCouldBecomeATopLeaderText
	call PrintText
	jr .done
    
    .GetMon
    ld hl, .YouBeatOurContestText
	call PrintText
    xor a
    ld a, TEXT_ROUTE24_REWARD_VENDOR_1
	ldh [hTextID], a
	call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

.YouBeatOurContestText:
	text_far _Route24CooltrainerM1YouBeatOurContestText
	text_end

.ReceivedNuggetText:
	text_far _Route24CooltrainerM1ReceivedNuggetText
	sound_get_item_1
	text_promptbutton
	text_end

.NoRoomText:
	text_far _Route24CooltrainerM1NoRoomText
	text_end

.JoinTeamRocketText:
	text_far _Route24CooltrainerM1JoinTeamRocketText
	text_end

.DefeatedText:
	text_far _Route24CooltrainerM1DefeatedText
	text_end

.YouCouldBecomeATopLeaderText:
	text_far _Route24CooltrainerM1YouCouldBecomeATopLeaderText
	text_end

Route24CooltrainerM2Text:
	text_far _Route24CooltrainerM1YouCouldBecomeATopLeaderText
	text_end

Route24CooltrainerM3Text:
	text_asm
	ld hl, Route24TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

Route24CooltrainerF1Text:
	text_asm
	ld hl, Route24TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

Route24Youngster1Text:
	text_asm
	ld hl, Route24TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

Route24CooltrainerF2Text:
	text_asm
	ld hl, Route24TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

Route24Youngster2Text:
	text_asm
	ld hl, Route24TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

Route24CooltrainerM2BattleText:
	text_far _Route24CooltrainerM2BattleText
	text_end

Route24CooltrainerM2EndBattleText:
	text_far _Route24CooltrainerM2EndBattleText
	text_end

Route24CooltrainerM2AfterBattleText:
	text_far _Route24CooltrainerM2AfterBattleText
	text_end

Route24CooltrainerM3BattleText:
	text_far _Route24CooltrainerM3BattleText
	text_end

Route24CooltrainerM3EndBattleText:
	text_far _Route24CooltrainerM3EndBattleText
	text_end

Route24CooltrainerM3AfterBattleText:
	text_far _Route24CooltrainerM3AfterBattleText
	text_end

Route24CooltrainerF1BattleText:
	text_far _Route24CooltrainerF1BattleText
	text_end

Route24CooltrainerF1EndBattleText:
	text_far _Route24CooltrainerF1EndBattleText
	text_end

Route24CooltrainerF1AfterBattleText:
	text_far _Route24CooltrainerF1AfterBattleText
	text_end

Route24Youngster1BattleText:
	text_far _Route24Youngster1BattleText
	text_end

Route24Youngster1EndBattleText:
	text_far _Route24Youngster1EndBattleText
	text_end

Route24Youngster1AfterBattleText:
	text_far _Route24Youngster1AfterBattleText
	text_end

Route24CooltrainerF2BattleText:
	text_far _Route24CooltrainerF2BattleText
	text_end

Route24CooltrainerF2EndBattleText:
	text_far _Route24CooltrainerF2EndBattleText
	text_end

Route24CooltrainerF2AfterBattleText:
	text_far _Route24CooltrainerF2AfterBattleText
	text_end

Route24Youngster2BattleText:
	text_far _Route24Youngster2BattleText
	text_end

Route24Youngster2EndBattleText:
	text_far _Route24Youngster2EndBattleText
	text_end

Route24Youngster2AfterBattleText:
	text_far _Route24Youngster2AfterBattleText
	text_end

Rogue_Route24_Reward_Text:
script_rogue_reward

Route24_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route24_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route24_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd


Route24NoTurningBackText:
	text_far _NoTurningBackText
	text_end

Route24GreedyText:
	text_far _GreedyText
	text_end