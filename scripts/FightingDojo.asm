; Karate Master mini-boss stage (MINIBOSS_FRAMEWORK.md). Reached only through a
; lobby door that rolled MINIBOSS_KARATE; never a normal stage.
FightingDojo_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .normal

	SetEvent EVENT_ENTER_ROOM
	ld hl, wRogueFlagsBitfield
	set 0, [hl]                 ; gym is next after this stage

	; Stage events are run-zone bits, so clear this visit's state explicitly
	; (the endless-mode revisit fallback can bring the player back).
	ResetEventRange EVENT_BEAT_KARATE_MASTER, EVENT_BEAT_FIGHTING_DOJO_TRAINER_3
	ResetEvents EVENT_DEFEATED_FIGHTING_DOJO, EVENT_AUTOWALKED_INTO_FIGHTING_DOJO
	SetEvent EVENT_FIGHTING_DOJO_VISITED ; once per run (MiniBossIsMapVisited)

	; Roll which of the three Dojo #MON is NOT offered (0-2), stored in two
	; event bits so NO THANKS and a second talk show the same pair.
	ResetEvents EVENT_DOJO_EXCLUDED_BIT0, EVENT_DOJO_EXCLUDED_BIT1
	ld c, 3
	call Rangerandom
	ld b, a
	bit 0, b
	jr z, .excludedBit1
	SetEvent EVENT_DOJO_EXCLUDED_BIT0
.excludedBit1
	bit 1, b
	jr z, .excludedDone
	SetEvent EVENT_DOJO_EXCLUDED_BIT1
.excludedDone

	farcall Random_Item_Selection
	call FightingDojoShowRandomItem
	farcall RogueRefresh
	farcall MiniBossApplyStageTrainer
	xor a ; SCRIPT_FIGHTINGDOJO_DEFAULT
	ld [wFightingDojoCurScript], a

.normal
	call EnableAutoTextBoxDrawing
	ld hl, FightingDojoTrainerHeaders
	ld de, FightingDojo_ScriptPointers
	ld a, [wFightingDojoCurScript]
	call ExecuteCurMapScriptInTable
	ld [wFightingDojoCurScript], a
	ret

; RogueRefresh only toggles the global stage item, so the Dojo mirrors its
; witch "no random item" check for its own ball.
FightingDojoShowRandomItem:
	ld a, TOGGLE_FIGHTING_DOJO_RANDOM_ITEM
	ld [wToggleableObjectIndex], a
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .show
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_RANDOM_ITEM
	jr nz, .show
	predef_jump HideObject
.show
	predef_jump ShowObject

FightingDojoResetScripts:
	xor a ; SCRIPT_FIGHTINGDOJO_DEFAULT
	ldh [hJoyIgnore], a
	ld [wFightingDojoCurScript], a
	ld [wCurMapScript], a
	ret

FightingDojo_ScriptPointers:
	def_script_pointers
	dw_const FightingDojoGateScript,                   SCRIPT_FIGHTINGDOJO_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle,    SCRIPT_FIGHTINGDOJO_START_BATTLE
	dw_const EndTrainerBattle,                         SCRIPT_FIGHTINGDOJO_END_BATTLE
	dw_const FightingDojoKarateMasterPostBattleScript, SCRIPT_FIGHTINGDOJO_KARATE_MASTER_POST_BATTLE
	dw_const FightingDojoPlayerIsMovingScript,         SCRIPT_FIGHTINGDOJO_PLAYER_IS_MOVING

; The door is both the arrival and the exit. Its header warps are
; WARP_NO_RETURN, so until the master falls the entrance auto-walk and the
; "no turning back" lock apply; after that the door is pointed at the lobby
; (rewritten every tick, so a header reload can't undo it).
FightingDojoGateScript:
	CheckEvent EVENT_BEAT_KARATE_MASTER
	jp z, FightingDojoDefaultScript
	ld a, INDIGO_PLATEAU_LOBBY
	ld [wWarpEntries + 3], a    ; warp 0 destination map
	ld [wWarpEntries + 7], a    ; warp 1 destination map
	jp CheckFightingMapTrainers

	RogueAutoWalkScripts FightingDojo, PAD_UP, FightingDojoMasterApproachScript, EVENT_AUTOWALKED_INTO_FIGHTING_DOJO, TEXT_FIGHTINGDOJO_NO_TURNING_BACK, SCRIPT_FIGHTINGDOJO_PLAYER_IS_MOVING, wFightingDojoCurScript

FightingDojoEntranceCoords:
	dbmapcoord 4, 11
	dbmapcoord 5, 11
	db -1

FightingDojoNoCoords:
	db -1

; Vanilla: stepping beside the master at (4, 3) makes him turn and talk.
FightingDojoMasterApproachScript:
	call CheckFightingMapTrainers
	ld a, [wTrainerHeaderFlagBit]
	and a
	ret nz
	xor a
	ldh [hJoyHeld], a
	ld [wSavedCoordIndex], a
	ld a, [wYCoord]
	cp 3
	ret nz
	ld a, [wXCoord]
	cp 4
	ret nz
	ld a, 1
	ld [wSavedCoordIndex], a
	ld a, PLAYER_DIR_RIGHT
	ld [wPlayerMovingDirection], a
	ld a, FIGHTINGDOJO_KARATE_MASTER
	ldh [hSpriteIndex], a
	ld a, SPRITE_FACING_LEFT
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	ld a, TEXT_FIGHTINGDOJO_KARATE_MASTER
	ldh [hTextID], a
	call DisplayTextID
	ret

FightingDojoKarateMasterPostBattleScript:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, FightingDojoResetScripts
	ld a, [wSavedCoordIndex]
	and a ; nz if the player was at (4, 3), left of the Karate Master
	jr z, .already_facing
	ld a, PLAYER_DIR_RIGHT
	ld [wPlayerMovingDirection], a
	ld a, FIGHTINGDOJO_KARATE_MASTER
	ldh [hSpriteIndex], a
	ld a, SPRITE_FACING_LEFT
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
.already_facing
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	SetEventRange EVENT_BEAT_KARATE_MASTER, EVENT_BEAT_FIGHTING_DOJO_TRAINER_3
	ld a, TEXT_FIGHTINGDOJO_KARATE_MASTER_REWARD
	ldh [hTextID], a
	call DisplayTextID
	xor a ; SCRIPT_FIGHTINGDOJO_DEFAULT
	ldh [hJoyIgnore], a
	ld [wFightingDojoCurScript], a
	ld [wCurMapScript], a
	ret

; The first entries must be the objects' own texts in slot order (1-6), so
; the script-fired ids below sit past wNumSprites (DisplayTextID reroute).
FightingDojo_TextPointers:
	def_text_pointers
	dw_const FightingDojoKarateMasterText,       TEXT_FIGHTINGDOJO_KARATE_MASTER
	dw_const FightingDojoBlackbelt1Text,         TEXT_FIGHTINGDOJO_BLACKBELT1
	dw_const FightingDojoBlackbelt2Text,         TEXT_FIGHTINGDOJO_BLACKBELT2
	dw_const FightingDojoBlackbelt3Text,         TEXT_FIGHTINGDOJO_BLACKBELT3
	dw_const FightingDojoBlackbelt4Text,         TEXT_FIGHTINGDOJO_BLACKBELT4
	dw_const RandomPickUpItemText,               TEXT_FIGHTINGDOJO_RANDOM_ITEM
	dw_const FightingDojoKarateMasterRewardText, TEXT_FIGHTINGDOJO_KARATE_MASTER_REWARD
	dw_const FightingDojoNoTurningBackText,      TEXT_FIGHTINGDOJO_NO_TURNING_BACK

FightingDojoTrainerHeaders:
	def_trainers 2
FightingDojoTrainerHeader0:
	trainer EVENT_BEAT_FIGHTING_DOJO_TRAINER_0, 4, FightingDojoBlackbelt1BattleText, FightingDojoBlackbelt1EndBattleText, FightingDojoBlackbelt1AfterBattleText
FightingDojoTrainerHeader1:
	trainer EVENT_BEAT_FIGHTING_DOJO_TRAINER_1, 4, FightingDojoBlackbelt2BattleText, FightingDojoBlackbelt2EndBattleText, FightingDojoBlackbelt2AfterBattleText
FightingDojoTrainerHeader2:
	trainer EVENT_BEAT_FIGHTING_DOJO_TRAINER_2, 3, FightingDojoBlackbelt3BattleText, FightingDojoBlackbelt3EndBattleText, FightingDojoBlackbelt3AfterBattleText
FightingDojoTrainerHeader3:
	trainer EVENT_BEAT_FIGHTING_DOJO_TRAINER_3, 3, FightingDojoBlackbelt4BattleText, FightingDojoBlackbelt4EndBattleText, FightingDojoBlackbelt4AfterBattleText
	db -1 ; end

FightingDojoKarateMasterText:
	text_asm
	CheckEvent EVENT_DEFEATED_FIGHTING_DOJO
	jr nz, .defeated_dojo
	CheckEventReuseA EVENT_BEAT_KARATE_MASTER
	jr nz, .defeated_master
	ld hl, .Text
	call PrintText
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, .DefeatedText
	ld de, .DefeatedText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	call EngageMapTrainer
	call InitBattleEnemyParameters
	ld a, SCRIPT_FIGHTINGDOJO_KARATE_MASTER_POST_BATTLE
	ld [wFightingDojoCurScript], a
	ld [wCurMapScript], a
	jr .end
.defeated_dojo
	ld hl, .StayAndTrainWithUsText
	call PrintText
	jr .end
.defeated_master
	; chose NO THANKS earlier: the same pair is offered again
	call FightingDojoOfferReward
.end
	jp TextScriptEnd

.Text:
	text_far _FightingDojoKarateMasterText
	text_end

.DefeatedText:
	text_far _FightingDojoKarateMasterDefeatedText
	text_end

.StayAndTrainWithUsText:
	text_far _FightingDojoKarateMasterStayAndTrainWithUsText
	text_end

FightingDojoKarateMasterRewardText:
	text_asm
	call FightingDojoOfferReward
	jp TextScriptEnd

; The Dojo's own reward menu (custom_functions/karate_dojo.asm). It is NOT the
; bridge gift system and touches none of its state.
FightingDojoOfferReward:
	ld hl, .IWillGiveYouAPokemonText
	call PrintText
	farcall KarateDojoRewardMenu ; carry = a #MON was given
	ret nc
	SetEvent EVENT_DEFEATED_FIGHTING_DOJO
	ret

.IWillGiveYouAPokemonText:
	text_far _FightingDojoKarateMasterIWillGiveYouAPokemonText
	text_end

FightingDojoNoTurningBackText:
	text_far _NoTurningBackText
	text_end

FightingDojoBlackbelt1Text:
	text_asm
	ld hl, FightingDojoTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

FightingDojoBlackbelt1BattleText:
	text_far _FightingDojoBlackbelt1BattleText
	text_end

FightingDojoBlackbelt1EndBattleText:
	text_far _FightingDojoBlackbelt1EndBattleText
	text_end

FightingDojoBlackbelt1AfterBattleText:
	text_far _FightingDojoBlackbelt1AfterBattleText
	text_end

FightingDojoBlackbelt2Text:
	text_asm
	ld hl, FightingDojoTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

FightingDojoBlackbelt2BattleText:
	text_far _FightingDojoBlackbelt2BattleText
	text_end

FightingDojoBlackbelt2EndBattleText:
	text_far _FightingDojoBlackbelt2EndBattleText
	text_end

FightingDojoBlackbelt2AfterBattleText:
	text_far _FightingDojoBlackbelt2AfterBattleText
	text_end

FightingDojoBlackbelt3Text:
	text_asm
	ld hl, FightingDojoTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

FightingDojoBlackbelt3BattleText:
	text_far _FightingDojoBlackbelt3BattleText
	text_end

FightingDojoBlackbelt3EndBattleText:
	text_far _FightingDojoBlackbelt3EndBattleText
	text_end

FightingDojoBlackbelt3AfterBattleText:
	text_far _FightingDojoBlackbelt3AfterBattleText
	text_end

FightingDojoBlackbelt4Text:
	text_asm
	ld hl, FightingDojoTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

FightingDojoBlackbelt4BattleText:
	text_far _FightingDojoBlackbelt4BattleText
	text_end

FightingDojoBlackbelt4EndBattleText:
	text_far _FightingDojoBlackbelt4EndBattleText
	text_end

FightingDojoBlackbelt4AfterBattleText:
	text_far _FightingDojoBlackbelt4AfterBattleText
	text_end
