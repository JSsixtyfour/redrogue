INCLUDE "engine/pokemon/rarity.asm"
INCLUDE "engine/rogue_pointers.asm"
INCLUDE "engine/pokemon/random_pokemon_selection.asm"

OaksLab_Script:  
   CheckEvent EVENT_ESTABLISHED_STARTER
   jr nz, .default
   
   call rogue_pokemon_randomized_batch
   SetEvent EVENT_ESTABLISHED_STARTER
   
   jp .end
   
   .default
   CheckEvent RIVAL_EXIT
   jr nz, .end
   
   ld hl, OaksLab_ScriptPointers
   ld a, [wOaksLabCurScript]
   jp CallFunctionInTable
   
   .end
   call OaksLabPlayerDontGoAwayScript
   jp EnableAutoTextBoxDrawing


OaksLab_ScriptPointers:
	def_script_pointers
	dw_const OaksLabPlayerDontGoAwayScript,          SCRIPT_OAKSLAB_PLAYER_DONT_GO_AWAY_SCRIPT
	dw_const OaksLabPlayerForcedToWalkBackScript,    SCRIPT_OAKSLAB_PLAYER_FORCED_TO_WALK_BACK_SCRIPT
	dw_const OaksLabRivalChoosesStarterScript,       SCRIPT_OAKSLAB_RIVAL_CHOOSES_STARTER
	dw_const OaksLabRivalChallengesPlayerScript,     SCRIPT_OAKSLAB_RIVAL_CHALLENGES_PLAYER
	dw_const OaksLabRivalStartBattleScript,          SCRIPT_OAKSLAB_RIVAL_START_BATTLE
	dw_const OaksLabRivalEndBattleScript,            SCRIPT_OAKSLAB_RIVAL_END_BATTLE
	dw_const OaksLabRivalStartsExitScript,           SCRIPT_OAKSLAB_RIVAL_STARTS_EXIT
	dw_const OaksLabPlayerWatchRivalExitScript,      SCRIPT_OAKSLAB_PLAYER_WATCH_RIVAL_EXIT
	dw_const OaksLabNoopScript,                      SCRIPT_OAKSLAB_NOOP


OaksLab_TextPointers:
	def_text_pointers
	dw_const Rogue_Lab_Script_PokeballText_1, TEXT_ROGUE_STARTER_POKEBALL_1
    dw_const Rogue_Lab_Script_PokeballText_2, TEXT_ROGUE_STARTER_POKEBALL_2
    dw_const Rogue_Lab_Script_PokeballText_3, TEXT_ROGUE_STARTER_POKEBALL_3
    dw_const OaksLabRivalText,                    TEXT_OAKSLAB_RIVAL
    dw_const OaksLabOakDontGoAwayYetText,         TEXT_OAKSLAB_OAK_DONT_GO_AWAY_YET
	dw_const OaksLabRivalIllTakeThisOneText,      TEXT_OAKSLAB_RIVAL_ILL_TAKE_THIS_ONE
	dw_const OaksLabRivalReceivedMonText,         TEXT_OAKSLAB_RIVAL_RECEIVED_MON
	dw_const OaksLabRivalIllTakeYouOnText,        TEXT_OAKSLAB_RIVAL_ILL_TAKE_YOU_ON
	dw_const OaksLabRivalSmellYouLaterText,       TEXT_OAKSLAB_RIVAL_SMELL_YOU_LATER
    

Rogue_Lab_Script_PokeballText_1:
	text_asm
    CheckEvent EVENT_GOT_STARTER
	jr z, .GetMon
	ld hl, GreedyText
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickPokeballText
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem]
	and a
	jr nz, .done

    ld a, [wRoguePokemon1]
	ld b, a
    ld c, 5
	call GivePokemon
	jr nc, .done
    
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
    SetEvent EVENT_GOT_STARTER
    
    ld de, .MiddleBallMovement1
	ld a, [wYCoord]
	cp 4 ; is the player standing below the table?
	jr z, .moveBlue
	ld de, .MiddleBallMovement2
	jr .moveBlue
    
    .moveBlue
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	call MoveSprite
    
	.done
	jp OaksLabRivalChoosesStarterScript
    
    .MiddleBallMovement1
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_UP
	db -1 ; end

    .MiddleBallMovement2
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db -1 ; end
    
Rogue_Lab_Script_PokeballText_2:
	text_asm
    CheckEvent EVENT_GOT_STARTER
	jr z, .GetMon
	ld hl, GreedyText
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon2]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickPokeballText
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem]
	and a
	jr nz, .done

	ld a, [wRoguePokemon1]
	ld b, a
    ld c, 5
	call GivePokemon
	jr nc, .done
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef HideObject
    SetEvent EVENT_GOT_STARTER
    
    ld de, .RightBallMovement1
	ld a, [wYCoord]
	cp 4 ; is the player standing below the table?
	jr z, .moveBlue
	ld de, .RightBallMovement2
	jr .moveBlue
    
    .moveBlue
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	call MoveSprite


	.done
	jp OaksLabRivalChoosesStarterScript
    
    .RightBallMovement1
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_UP
	db -1 ; end

    .RightBallMovement2
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db -1 ; end
    
Rogue_Lab_Script_PokeballText_3:
	text_asm
    CheckEvent EVENT_GOT_STARTER
	jr z, .GetMon
    
	ld hl, GreedyText
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon3]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickPokeballText
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem]
	and a
	jr nz, .done

	ld a, [wRoguePokemon1]
	ld b, a
    ld c, 5
	call GivePokemon
	jr nc, .done
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef HideObject
    SetEvent EVENT_GOT_STARTER
    
    ld de, .LeftBallMovement1
	ld a, [wXCoord]
	cp 9 ; is the player standing to the right of the table?
	jr nz, .moveBlue
	push hl
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	ld a, SPRITESTATEDATA1_YPIXELS
	ldh [hSpriteDataOffset], a
	call GetPointerWithinSpriteStateData1
	push hl
	ld [hl], $4c ; SPRITESTATEDATA1_YPIXELS
	inc hl
	inc hl
	ld [hl], $0 ; SPRITESTATEDATA1_XPIXELS
	pop hl
	inc h
	ld [hl], 8 ; SPRITESTATEDATA2_MAPY
	inc hl
	ld [hl], 9 ; SPRITESTATEDATA2_MAPX
	ld de, .LeftBallMovement2 ; the rival is not currently onscreen, so account for that
	pop hl
	jr .moveBlue
    
    .moveBlue
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	call MoveSprite
    
    .done
	jp OaksLabRivalChoosesStarterScript
    
    .LeftBallMovement1
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
    .LeftBallMovement2
	db NPC_MOVEMENT_RIGHT
	db -1 ; end
    
OaksLabRivalChoosesStarterScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ld a, PAD_SELECT | PAD_START | PAD_CTRL_PAD
	ld [wJoyIgnore], a
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	ld a, TEXT_OAKSLAB_RIVAL_ILL_TAKE_THIS_ONE
	ldh [hTextID], a
	call DisplayTextID
	ld a, [wRivalStarterBallSpriteIndex]
	cp ROGUE_STARTER_POKEBALL_1
	jr nz, .not_charmander
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_1
	jr .hideBallAndContinue
.not_charmander
	cp ROGUE_STARTER_POKEBALL_2
	jr nz, .not_squirtle
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_2
	jr .hideBallAndContinue
.not_squirtle
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_3
.hideBallAndContinue
	ld [wToggleableObjectIndex], a
	predef HideObject
	call Delay3
	ld a, [wRivalStarterTemp]
	ld [wRivalStarter], a
	ld [wCurPartySpecies], a
	ld [wNamedObjectIndex], a
	call GetMonName
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	ld a, TEXT_OAKSLAB_RIVAL_RECEIVED_MON
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_STARTER
	xor a
	ld [wJoyIgnore], a

OaksLabRivalChallengesPlayerScript:
	ld a, [wYCoord]
	cp 6
	ret nz
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	xor a ; SPRITE_FACING_DOWN
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a
	ld c, BANK(Music_MeetRival)
	ld a, MUSIC_MEET_RIVAL
	call PlayMusic
	ld a, TEXT_OAKSLAB_RIVAL_ILL_TAKE_YOU_ON
	ldh [hTextID], a
	call DisplayTextID
	ld a, $1
	ldh [hNPCPlayerRelativePosPerspective], a
	ld a, $1
	swap a
	ldh [hNPCSpriteOffset], a
	predef CalcPositionOfPlayerRelativeToNPC
	ldh a, [hNPCPlayerYDistance]
	dec a
	ldh [hNPCPlayerYDistance], a
	predef FindPathToPlayer
	ld de, wNPCMovementDirections2
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	call MoveSprite

OaksLabRivalStartBattleScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz

	; define which team rival uses, and fight it
	ld a, OPP_RIVAL1
	ld [wCurOpponent], a
	ld a, [wRivalStarter]
	cp STARTER2
	jr nz, .not_squirtle
	ld a, $1
	jr .done
.not_squirtle
	cp STARTER3
	jr nz, .not_bulbasaur
	ld a, $2
	jr .done
.not_bulbasaur
	ld a, $3
.done
	ld [wTrainerNo], a
	ld a, OAKSLAB_RIVAL
	ld [wSpriteIndex], a
	call GetSpritePosition1
	ld hl, OaksLabRivalIPickedTheWrongPokemonText
	ld de, OaksLabRivalAmIGreatOrWhatText
	call SaveEndBattleTextPointers
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	xor a
	ld [wJoyIgnore], a
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a

OaksLabRivalEndBattleScript:
	ld a, PAD_CTRL_PAD
	ld [wJoyIgnore], a
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a
	call UpdateSprites
	ld a, OAKSLAB_RIVAL
	ld [wSpriteIndex], a
	call SetSpritePosition1
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	xor a ; SPRITE_FACING_DOWN
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	predef HealParty
	SetEvent EVENT_BATTLED_RIVAL_IN_OAKS_LAB

OaksLabRivalStartsExitScript:
	ld c, 20
	call DelayFrames
	ld a, TEXT_OAKSLAB_RIVAL_SMELL_YOU_LATER
	ldh [hTextID], a
	call DisplayTextID
	farcall Music_RivalAlternateStart
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	ld de, .RivalExitMovement
	call MoveSprite
	ld a, [wXCoord]
	cp 4
	; move left or right depending on where the player is standing
	jr nz, .moveLeft
	ld a, NPC_MOVEMENT_RIGHT
	jr .next
.moveLeft
	ld a, NPC_MOVEMENT_LEFT
.next
	ld [wNPCMovementDirections], a

    jp OaksLabPlayerWatchRivalExitScript
    
.RivalExitMovement
	db NPC_CHANGE_FACING
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db -1 ; end

OaksLabPlayerWatchRivalExitScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	jr nz, .checkRivalPosition
	ld a, TOGGLE_OAKS_LAB_RIVAL
	ld [wToggleableObjectIndex], a
	predef HideObject
	xor a
	ld [wJoyIgnore], a
	call PlayDefaultMusic ; reset to map music
	ret
    
; make the player keep facing the rival as he walks away
.checkRivalPosition
	ld a, [wNPCNumScriptedSteps]
	cp $5
	jr nz, .turnPlayerDown
	ld a, [wXCoord]
	cp 4
	jr nz, .turnPlayerLeft
	ld a, SPRITE_FACING_RIGHT
	ld [wSpritePlayerStateData1FacingDirection], a
	jr .done
.turnPlayerLeft
	ld a, SPRITE_FACING_LEFT
	ld [wSpritePlayerStateData1FacingDirection], a
	jr .done
.turnPlayerDown
	cp $4
	ret nz
	xor a ; ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
.done
	ret
    
OaksLabPlayerDontGoAwayScript:
	ld a, [wYCoord]
	cp $B
	ret nz
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	xor a ; SPRITE_FACING_DOWN
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	call UpdateSprites
	ld a, TEXT_OAKSLAB_OAK_DONT_GO_AWAY_YET
	ldh [hTextID], a
	call DisplayTextID
	ld a, $1
	ld [wSimulatedJoypadStatesIndex], a
	ld a, PAD_UP
	ld [wSimulatedJoypadStatesEnd], a
	call StartSimulatingJoypadStates
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a

	ld a, SCRIPT_OAKSLAB_PLAYER_FORCED_TO_WALK_BACK_SCRIPT
	ld [wOaksLabCurScript], a
	ret
    
OaksLabPlayerForcedToWalkBackScript:
	ld a, [wSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3

	ld a, SCRIPT_OAKSLAB_PLAYER_DONT_GO_AWAY_SCRIPT
	ld [wOaksLabCurScript], a
	ret

OaksLabOakDontGoAwayYetText:
	text_asm
	ld hl, NoTurningBack
	call PrintText
	jp TextScriptEnd
    
OaksLabNoopScript:
	ret
    
OaksLabRivalText:
	text_asm
	ld hl, .GrampsIsntAroundText
	call PrintText
	jr .done

.done
	jp TextScriptEnd
    
    
    .GrampsIsntAroundText:
	text_far _OaksLabRivalGrampsIsntAroundText
	text_end
    
    jp TextScriptEnd

GreedyText:
	text_far _GreedyText
	text_end
    
PickPokeballText:
	text_far _PickPokeBallText
	text_end

NoTurningBack:
	text_asm
	ld hl, .Text
	call PrintText
	jp TextScriptEnd

.Text:
	text_far _NoTurningBack
	text_end
    
OaksLabRivalIPickedTheWrongPokemonText:
	text_far _OaksLabRivalIPickedTheWrongPokemonText
	text_end

OaksLabRivalAmIGreatOrWhatText:
	text_far _OaksLabRivalAmIGreatOrWhatText
	text_end

OaksLabRivalSmellYouLaterText:
	text_asm
	ld hl, .Text
	call PrintText
	jp TextScriptEnd

.Text:
	text_far _OaksLabRivalSmellYouLaterText
	text_end
    
OaksLabRivalIllTakeThisOneText:
	text_asm
	ld hl, .Text
	call PrintText
	jp TextScriptEnd

.Text:
	text_far _OaksLabRivalIllTakeThisOneText
	text_end

OaksLabRivalReceivedMonText:
	text_asm
	ld hl, .Text
	call PrintText
	jp TextScriptEnd

.Text:
	text_far _OaksLabRivalReceivedMonText
	sound_get_key_item
	text_end

OaksLabRivalIllTakeYouOnText:
	text_asm
	ld hl, .Text
	call PrintText
	jp TextScriptEnd

.Text:
	text_far _OaksLabRivalIllTakeYouOnText
	text_end
    