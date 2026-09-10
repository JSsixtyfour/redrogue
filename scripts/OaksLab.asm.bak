;INCLUDE "engine/pokemon/rarity.asm"
;INCLUDE "engine/rogue_pointers.asm"
;INCLUDE "engine/pokemon/random_pokemon_selection.asm"

; Dual-purpose room: OaksLab is still the vanilla starter-choice location
; (the .notBridge path below is the untouched starter/rival cutscene state
; machine) AND a bridge gift room (Oak, OaksLabOakGiftList) when entered from
; a lobby door. The whole bridge branch is gated on wWarpedFromWhichMap ==
; INDIGO_PLATEAU_LOBBY so the real Pallet-Town intro is completely unaffected.
OaksLab_Script:
   ld a, [wWarpedFromWhichMap]
   cp INDIGO_PLATEAU_LOBBY
   jr nz, .notBridge
; --- bridge context ---
   CheckEvent EVENT_ENTER_ROOM
   jr nz, .bridgeReady
   SetEvent EVENT_ENTER_ROOM
   farcall rogue_gift_randomized_batch
   ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
   ResetEvent EVENT_BRIDGE_INTRO
.bridgeReady
   ; hide the intro-only rival + 3 starter balls (they don't belong in a
   ; bridge visit and would crowd sprite VRAM); Oak shows by default.
   ld a, TOGGLE_OAKS_LAB_RIVAL
   ld [wToggleableObjectIndex], a
   predef HideObject
   ;ld a, TOGGLE_ROGUE_STARTER_POKEBALL_1
   ;ld [wToggleableObjectIndex], a
   ;predef HideObject
   ;ld a, TOGGLE_ROGUE_STARTER_POKEBALL_2
   ;ld [wToggleableObjectIndex], a
   ;predef HideObject
   ;ld a, TOGGLE_ROGUE_STARTER_POKEBALL_3
   ;ld [wToggleableObjectIndex], a
   ;predef HideObject
   farcall PatchBridgeExitAll   ; reroute EVERY exit onward (incl. the north REWARD_ROOM exit)
   jp EnableAutoTextBoxDrawing

.notBridge
; --- vanilla starter/rival intro (unchanged) ---
   CheckEvent EVENT_ESTABLISHED_STARTER
   jr nz, .default

   farcall rogue_pokemon_randomized_batch
   SetEvent EVENT_ESTABLISHED_STARTER

   jp .end

   .default
   CheckEvent EVENT_GOT_STARTER
   jr z, .end

   ld hl, OaksLab_ScriptPointers
   ld a, [wOaksLabCurScript]
   call CallFunctionInTable
   ; Keep the south/north coord-lock monitor running after a starter is chosen
   ; too -- WARP_NO_RETURN silently blocks the actual warp, but without this
   ; call here the "no turning back" text stopped firing once EVENT_GOT_STARTER
   ; was set, since this branch used to jump straight past it. The monitor's
   ; own hSimulatedJoypadStatesIndex guard makes it a no-op during any of the
   ; rival/battle cutscene's own scripted walks.
   call OaksLabPlayerDontGoAwayScript
   jp EnableAutoTextBoxDrawing

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
	dw_const OaksLabOakText,                      TEXT_OAKSLAB_OAK
	dw_const OaksLabGirlText,                     TEXT_OAKSLAB_GIRL
	dw_const OaksLabScientistText,                TEXT_OAKSLAB_SCIENTIST_1
	dw_const OaksLabScientistText,                TEXT_OAKSLAB_SCIENTIST_2 ; 8th object_event (matches NUM_OBJECT_EVENTS)
    dw_const OaksLabOakDontGoAwayYetText,         TEXT_OAKSLAB_OAK_DONT_GO_AWAY_YET
	dw_const OaksLabRivalIllTakeThisOneText,      TEXT_OAKSLAB_RIVAL_ILL_TAKE_THIS_ONE
	dw_const OaksLabRivalReceivedMonText,         TEXT_OAKSLAB_RIVAL_RECEIVED_MON
	dw_const OaksLabRivalIllTakeYouOnText,        TEXT_OAKSLAB_RIVAL_ILL_TAKE_YOU_ON
	dw_const OaksLabRivalSmellYouLaterText,       TEXT_OAKSLAB_RIVAL_SMELL_YOU_LATER
	dw_const OaksLab_Gift_Text, TEXT_OAKSLAB_GIFT_1
	EXPORT TEXT_OAKSLAB_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu
	dw_const OaksLabOakSelectMonText, TEXT_OAKSLAB_OAK_SELECT_MON


Rogue_Lab_Script_PokeballText_1:
	text_asm
	push bc
	CheckEvent EVENT_GOT_STARTER
	jr z, .GetMon
	ld hl, GreedyText
	call PrintText
	jr .end_text

.GetMon
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld a, [wRoguePokemon1]
	call OaksLabShowStarterDex
	ld hl, PickPokeballText
	call PrintText
	ld a, $1
	ldh [hNoWaitAfterText], a
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .end_text

	ld a, [wRoguePokemon1]
	ld b, a
	ld c, 5
	call GivePokemon
	jr nc, .pickRival
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
.pickRival
	SetEvent EVENT_GOT_STARTER
	ld e, 1 ; player took starter slot 1
	call OaksLabRivalPicksAndWalks
.end_text
	pop bc
	jp TextScriptEnd

Rogue_Lab_Script_PokeballText_2:
	text_asm
	push bc
	CheckEvent EVENT_GOT_STARTER
	jr z, .GetMon
	ld hl, GreedyText
	call PrintText
	jr .end_text

.GetMon
	ld a, [wRoguePokemon2]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld a, [wRoguePokemon2]
	call OaksLabShowStarterDex
	ld hl, PickPokeballText
	call PrintText
	ld a, $1
	ldh [hNoWaitAfterText], a
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .end_text

	ld a, [wRoguePokemon2]
	ld b, a
	ld c, 5
	call GivePokemon
	jr nc, .pickRival
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef HideObject
.pickRival
	SetEvent EVENT_GOT_STARTER
	ld e, 2 ; player took starter slot 2
	call OaksLabRivalPicksAndWalks
.end_text
	pop bc
	jp TextScriptEnd

Rogue_Lab_Script_PokeballText_3:
	text_asm
	push bc
	CheckEvent EVENT_GOT_STARTER
	jr z, .GetMon
	ld hl, GreedyText
	call PrintText
	jr .end_text

.GetMon
	ld a, [wRoguePokemon3]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld a, [wRoguePokemon3]
	call OaksLabShowStarterDex
	ld hl, PickPokeballText
	call PrintText
	ld a, $1
	ldh [hNoWaitAfterText], a
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .end_text

	ld a, [wRoguePokemon3]
	ld b, a
	ld c, 5
	call GivePokemon
	jr nc, .pickRival
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef HideObject
.pickRival
	SetEvent EVENT_GOT_STARTER
	ld e, 3 ; player took starter slot 3
	call OaksLabRivalPicksAndWalks
.end_text
	pop bc
	jp TextScriptEnd

; Show the full Pokedex page for an arbitrary (randomized) starter when the
; player examines its ball, generalizing vanilla StarterDex. IN: a = internal
; species id. We temporarily set that species' OWNED bit (by its dex number, via
; IndexToPokedex) so ShowPokedexData renders the complete entry, then clear it
; again since the player hasn't actually caught it. The species is kept on the
; stack across ShowPokedexData/ReloadMapData (which clobber registers + WRAM).
OaksLabShowStarterDex:
	push af
	ld [wPokedexNum], a
	predef IndexToPokedex          ; wPokedexNum = dex # for this species
	ld a, [wPokedexNum]
	dec a
	ld c, a
	ld b, FLAG_SET
	ld hl, wPokedexOwned
	predef FlagActionPredef         ; temporarily owned -> full entry renders
	pop af
	push af
	ld [wPokedexNum], a             ; ShowPokedexData reads the species from here
	ld [wCurPartySpecies], a
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	predef ShowPokedexData
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	call ReloadMapData
	ld c, 10
	call DelayFrames
	pop af
	ld [wPokedexNum], a
	predef IndexToPokedex          ; wPokedexNum = dex # again
	ld a, [wPokedexNum]
	dec a
	ld c, a
	ld b, FLAG_RESET
	ld hl, wPokedexOwned
	predef FlagActionPredef         ; clear it (player hasn't caught it yet)
	ret

; --- Rival starter pick + walk (Red Rogue) ---
; Called from each pokeball handler with e = the slot the player took (1..3).
; RivalPickStarter (in random_pokemon_selection.asm) chooses Blue's starter among
; the two remaining slots by rarity, then type advantage over the player's
; starter, then random; it sets wRivalStarter + wRivalStarterBallSpriteIndex.
; We then fall through to walk Blue to that ball.
OaksLabRivalPicksAndWalks:
	farcall RivalPickStarter
	; fall through

; Walk Blue to his chosen ball. wRivalStarterBallSpriteIndex = ROGUE_STARTER_POKEBALL_1/2/3
; (1/2/3) = left(x=6)/middle(x=7)/right(x=8). Blue starts at (4,3). The "1" tables route
; via row 5 (used when the player stands on row 4 and would block row 4); the
; "2" tables route via row 4. Middle/Right tables match vanilla; Left adds a
; row-5 variant and keeps the vanilla far-right (xCoord==9) reposition case.
MoveRivalToChosenBall:
	ld a, [wRivalStarterBallSpriteIndex]
	cp ROGUE_STARTER_POKEBALL_1 ; 1 = left
	jr z, .leftBall
	cp ROGUE_STARTER_POKEBALL_2 ; 2 = middle
	jr z, .middleBall
; else ROGUE_STARTER_POKEBALL_3 = right ball
	ld a, [wYCoord]
	cp 4 ; player standing directly below the table?
	ld de, RivalRightBallMovement1
	jr z, .move
	ld de, RivalRightBallMovement2
	jr .move
.middleBall
	ld a, [wYCoord]
	cp 4
	ld de, RivalMiddleBallMovement1
	jr z, .move
	ld de, RivalMiddleBallMovement2
	jr .move
.leftBall
	;ld a, [wXCoord]
	;cp 9 ; player to the right of the table (rival offscreen)?
	;jr z, .leftBallReposition
	;ld a, [wYCoord]
	;cp 4
	;ld de, RivalLeftBallMovement1
	;jr z, .move
	ld de, RivalLeftBallMovement2
	jr .move
.leftBallReposition
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
	ld de, RivalLeftBallReposition
.move
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	call MoveSprite
	; MoveSprite masks every button with hJoyIgnore = $ff. Keep Blue's movement
	; protected, but allow A/B to dismiss the outer text wait. This matters when
	; GivePokemon sent a full-party starter to the box: hNoWaitAfterText made its
	; nested PrintText return, leaving the box message for the outer wait below.
	ld a, PAD_SELECT | PAD_START | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	; advance the state machine so OaksLabRivalChoosesStarterScript runs once
	; Blue finishes walking: it hides his ball and gives him his starter.
	ld a, SCRIPT_OAKSLAB_RIVAL_CHOOSES_STARTER
	ld [wOaksLabCurScript], a
	ret

;RivalLeftBallMovement1:
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_UP
;	db -1 ; end
RivalLeftBallMovement2:
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db -1 ; end
RivalLeftBallReposition:
	db NPC_MOVEMENT_RIGHT
	db -1 ; end
RivalMiddleBallMovement1:
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_UP
	db -1 ; end
RivalMiddleBallMovement2:
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db -1 ; end
RivalRightBallMovement1:
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_UP
	db -1 ; end
RivalRightBallMovement2:
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db -1 ; end
    
OaksLabRivalChoosesStarterScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ld a, PAD_SELECT | PAD_START | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
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
	ld a, [wRivalStarter]     ; set by RivalPickStarter (stable WRAM, no temp)
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
	ldh [hJoyIgnore], a
    ld a, SCRIPT_OAKSLAB_RIVAL_CHALLENGES_PLAYER
	ld [wOaksLabCurScript], a
	ret

OaksLabRivalChallengesPlayerScript:
	ld a, [wYCoord]
	cp 2
	ret nz
	ld a, [wXCoord]
	cp 4
	jr z, .gated
	cp 5
	ret nz
.gated
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
	; Walk Blue from his ball spot (row 4, x=6/7/8 by wRivalStarterBallSpriteIndex)
	; to the exit tile the player is not standing on: player at x=4 -> Blue to
	; (5,2); player at x=5 -> Blue to (4,2). Path: left along row 4, then up 2.
	ld a, [wRivalStarterBallSpriteIndex]
	cp ROGUE_STARTER_POKEBALL_1 ; 1 = left ball (x=6)
	jr z, .leftBall
	cp ROGUE_STARTER_POKEBALL_2 ; 2 = middle ball (x=7)
	jr z, .middleBall
; else ROGUE_STARTER_POKEBALL_3 = right ball (x=8)
	ld a, [wXCoord]
	cp 4
	ld de, RivalChallengeRight_ToCol5
	jr z, .move
	ld de, RivalChallengeRight_ToCol4
	jr .move
.middleBall
	ld a, [wXCoord]
	cp 4
	ld de, RivalChallengeMid_ToCol5
	jr z, .move
	ld de, RivalChallengeMid_ToCol4
	jr .move
.leftBall
	ld a, [wXCoord]
	cp 4
	ld de, RivalChallengeLeft_ToCol5
	jr z, .move
	ld de, RivalChallengeLeft_ToCol4
.move
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	call MoveSprite
	; NOTE: MoveSprite is async; Blue faces the player once his walk finishes,
	; handled at the top of OaksLabRivalStartBattleScript (below).
    ld a, SCRIPT_OAKSLAB_RIVAL_START_BATTLE
	ld [wOaksLabCurScript], a
	ret

; Precomputed Blue walk tables for OaksLabRivalChallengesPlayerScript.
; left ball (x=6)
RivalChallengeLeft_ToCol5:  db NPC_MOVEMENT_LEFT, NPC_MOVEMENT_UP, NPC_MOVEMENT_UP, -1                     ; player at 4 -> Blue to (5,2)
RivalChallengeLeft_ToCol4:  db NPC_MOVEMENT_LEFT, NPC_MOVEMENT_LEFT, NPC_MOVEMENT_UP, NPC_MOVEMENT_UP, -1   ; player at 5 -> Blue to (4,2)
; middle ball (x=7)
RivalChallengeMid_ToCol5:   db NPC_MOVEMENT_LEFT, NPC_MOVEMENT_LEFT, NPC_MOVEMENT_UP, NPC_MOVEMENT_UP, -1
RivalChallengeMid_ToCol4:   db NPC_MOVEMENT_LEFT, NPC_MOVEMENT_LEFT, NPC_MOVEMENT_LEFT, NPC_MOVEMENT_UP, NPC_MOVEMENT_UP, -1
; right ball (x=8)
RivalChallengeRight_ToCol5: db NPC_MOVEMENT_LEFT, NPC_MOVEMENT_LEFT, NPC_MOVEMENT_LEFT, NPC_MOVEMENT_UP, NPC_MOVEMENT_UP, -1
RivalChallengeRight_ToCol4: db NPC_MOVEMENT_LEFT, NPC_MOVEMENT_LEFT, NPC_MOVEMENT_LEFT, NPC_MOVEMENT_LEFT, NPC_MOVEMENT_UP, NPC_MOVEMENT_UP, -1

OaksLabRivalStartBattleScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz

	; walk is finished: face Blue toward the player (player at x=4 is on his
	; left -> face left; player at x=5 is on his right -> face right).
	ld a, [wXCoord]
	cp 4
	ld a, SPRITE_FACING_LEFT
	jr z, .faceSet
	ld a, SPRITE_FACING_RIGHT
.faceSet
	ld b, a
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	ld a, b
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay

	; define which team rival uses, and fight it
	ld a, 1
	ld [wIsTrainerBattle], a
    ld a, OPP_RIVAL1
	ld [wCurOpponent], a
	ld a, [wRivalStarter]
	ld b, a
	ld a, [wRoguePokemon2]
	cp b
	jr nz, .not_slot2
	ld a, $1
	jr .done
.not_slot2
	ld a, [wRoguePokemon3]
	cp b
	jr nz, .not_slot3
	ld a, $2
	jr .done
.not_slot3
	ld a, $3
.done
	ld [wTrainerNo], a
	ld a, OAKSLAB_RIVAL
	ldh [hActiveSpriteIndex], a
	call GetSpritePosition1
	ld hl, OaksLabRivalIPickedTheWrongPokemonText
	ld de, OaksLabRivalAmIGreatOrWhatText
	call SaveEndBattleTextPointers
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	xor a
	ldh [hJoyIgnore], a
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a
    ld a, SCRIPT_OAKSLAB_RIVAL_END_BATTLE
	ld [wOaksLabCurScript], a
	ret

OaksLabRivalEndBattleScript:
    xor a
	ld [wIsTrainerBattle], a
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a
	call UpdateSprites
	ld a, OAKSLAB_RIVAL
	ldh [hActiveSpriteIndex], a
	call SetSpritePosition1
	ld a, OAKSLAB_RIVAL
	ldh [hSpriteIndex], a
	xor a ; SPRITE_FACING_DOWN
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	predef HealParty
	SetEvent EVENT_BATTLED_RIVAL_IN_OAKS_LAB
    ld a, SCRIPT_OAKSLAB_RIVAL_STARTS_EXIT
	ld [wOaksLabCurScript], a
	ret

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
    ld a, SCRIPT_OAKSLAB_PLAYER_WATCH_RIVAL_EXIT
	ld [wOaksLabCurScript], a
	ret

; Blue leaves the way he came, walking south down his column to the doorway.
; He battles at the north exit tiles (4,2)/(5,2), so this is a straight run
; down row 2 -> row 11; his column (4 or 5) stays clear of Oak and the lab NPCs.
.RivalExitMovement
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db NPC_MOVEMENT_DOWN
	db -1 ; end

OaksLabPlayerWatchRivalExitScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	jr z, .rivalGone
	; still walking: the player turns south to watch Blue head for the door
	xor a ; SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ret
.rivalGone
	ld a, TOGGLE_OAKS_LAB_RIVAL
	ld [wToggleableObjectIndex], a
	predef HideObject
	xor a
	ldh [hJoyIgnore], a
	call PlayDefaultMusic ; reset to map music
	ld a, SCRIPT_OAKSLAB_NOOP
	ld [wOaksLabCurScript], a
	ret
    
; South-exit one-way lock (route-style, mirrors Route1DefaultScript's
; ArePlayerCoordsInArray / StartSimulatingJoypadStates block-back pattern).
; Called every frame from OaksLab_Script's default path once the starter/rival
; intro state machine isn't actively driving wOaksLabCurScript, so the
; non-match path must stay a cheap ArePlayerCoordsInArray + ret.
; OaksLabNoReturnCoords covers both south doorway tiles (the warp_events at
; (4,11)/(5,11) in data/maps/objects/OaksLab.asm, now WARP_NO_RETURN) and the
; row directly inside them (4,10)/(5,10), so the player is turned back before
; ever reaching the warp tile itself (matches how Route1NoCoords blocks one
; row before its actual warp row).
OaksLabEntranceCoords: ; south doorway arrival tiles -> auto-walk the player in
	dbmapcoord 4, 11
	dbmapcoord 5, 11
	db -1

OaksLabSouthBlockCoords: ; the row just inside the doorway -> "Don't go away yet!"
	dbmapcoord 4, 10
	dbmapcoord 5, 10
	db -1

OaksLabNorthBlockCoords: ; north-exit approach -> blocked until a starter is chosen
	dbmapcoord 4, 1
	dbmapcoord 5, 1
	db -1

; Runs every frame from OaksLab_Script's pre-starter (.end) path. Three jobs,
; each self-gated on the simulated-joypad index so a walk/block fires exactly
; once per approach (the old code lumped the doorway + inner row into ONE array
; and only stepped once, so it fired on entry and fired twice):
;   - south doorway   -> auto-walk the player up into the lab
;   - one row inside  -> Oak "Don't go away yet!" + shove back up
;   - north exit      -> only while the player has NO POKEMON, Oak tells them to
;                        choose one + shove back down
OaksLabPlayerDontGoAwayScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	; North exit: only block while the player still has no POKEMON.
	ld a, [wPartyCount]
	and a
	jr nz, .checkSouth
	ld hl, OaksLabNorthBlockCoords
	call ArePlayerCoordsInArray
	jr c, .needMon
.checkSouth
	ld hl, OaksLabSouthBlockCoords
	call ArePlayerCoordsInArray
	jr c, .dontLeave
	; Doorway: walk the player forward (up) into the lab.
	ld hl, OaksLabEntranceCoords
	call ArePlayerCoordsInArray
	ret nc
	xor a
	ldh [hJoyPressed], a
	ldh [hJoyHeld], a
	ld hl, wSimulatedJoypadStatesEnd
	ld a, PAD_UP
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ld a, $3 ; three steps up
	ldh [hSimulatedJoypadStatesIndex], a
	jp StartSimulatingJoypadStates
.needMon
	ld a, TEXT_OAKSLAB_OAK_SELECT_MON
	ld c, PAD_DOWN
	jr .blockAndPush
.dontLeave
	ld a, TEXT_OAKSLAB_OAK_DONT_GO_AWAY_YET
	ld c, PAD_UP
.blockAndPush
	; a = text id to show, c = one-step push direction
	ldh [hTextID], a
	push bc
	xor a
	ldh [hJoyPressed], a
	ldh [hJoyHeld], a
	ld [wSimulatedJoypadStatesEnd], a
	call DisplayTextID
	pop bc
	ld a, c
	ld [wSimulatedJoypadStatesEnd], a
	ld a, $1
	ldh [hSimulatedJoypadStatesIndex], a
	jp StartSimulatingJoypadStates
    
OaksLabPlayerForcedToWalkBackScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3

	ld a, SCRIPT_OAKSLAB_PLAYER_DONT_GO_AWAY_SCRIPT
	ld [wOaksLabCurScript], a
	ret

OaksLabOakDontGoAwayYetText:
	text_far _OaksLabOakDontGoAwayYetText
	text_end

OaksLabOakSelectMonText:
	text_far _OaksLabOakSelectMonText
	text_end

OaksLabGirlText:
	text_far _OaksLabGirlText
	text_end

OaksLabScientistText:
	text_far _OaksLabScientistText
	text_end
    
OaksLabNoopScript:
	ret
    
OaksLabRivalText:
	text_asm
	; Once Blue has received his own starter (state has advanced past picking
	; it), talking to him shows a different line than the pre-pick "impatient"
	; nudge.
	ld a, [wOaksLabCurScript]
	cp SCRIPT_OAKSLAB_RIVAL_CHALLENGES_PLAYER
	jr nc, .ThanksText
	ld hl, .ImpatientText
	call PrintText
	jp TextScriptEnd

.ThanksText:
	ld hl, .ThanksTextFar
	call PrintText
	jp TextScriptEnd

.ImpatientText:
	text_far _OaksLabRivalImpatientText
	text_end

.ThanksTextFar:
	text_far _OaksLabRivalThanksText
	text_end

; Oak's own gift dispatch. In a bridge visit he hands out a gift; during
; normal play (Oak is now present in the lab for the starter sequence and
; afterward) he just prints placeholder flavor text.
OaksLabOakText:
	text_asm
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	jr z, .bridge
	; starter-selection context: nudge the player before they choose a starter,
	; wish them luck once they have one.
	CheckEvent EVENT_GOT_STARTER
	jr nz, .chosen
	ld hl, OaksLabOakChooseMonText
	call PrintText
	jp TextScriptEnd
.chosen
	ld hl, OaksLabOakGoodLuckText
	call PrintText
	jp TextScriptEnd
.bridge
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .IntroText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_OAKSLAB_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, .AlreadyGotText
	call PrintText
.done
	jp TextScriptEnd

.IntroText:
	text_far _OaksLabOakGiftIntroText
	text_end

.AlreadyGotText:
	text_far _OaksLabOakAlreadyGotText
	text_end

.NormalText:
	text_far _OaksLabOakNormalText
	text_end

OaksLabOakChooseMonText:
	text_far _OaksLabOakChooseMonText
	text_end

OaksLabOakGoodLuckText:
	text_far _OaksLabOakGoodLuckText
	text_end

OaksLab_Gift_Text:
	script_bridge_gift

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
    
PickPokeballText:
	text_far _PickPokeBallText
	text_end
    
GreedyText:
	text_far _GreedyText
	text_end
