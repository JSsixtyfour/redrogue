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
	ResetEvent EVENT_DEFEATED_FIGHTING_DOJO
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
	call FightingDojoInitRewards
	farcall MiniBossApplyStageTrainer
	xor a ; SCRIPT_FIGHTINGDOJO_DEFAULT
	ld [wFightingDojoCurScript], a

.normal
	; Older in-room saves can still carry the previous stage's third offer.
	ld a, [wRoguePokemon3]
	and a
	call nz, FightingDojoInitRewards
	call FightingDojoShowOrHideExitBlock
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
	run_challenge RUN_CH_NO_RANDOM_ITEM
	jr nz, .hide
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .show
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_RANDOM_ITEM
	jr nz, .show
.hide
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
	dw_const FightingDojoDefaultScript,                SCRIPT_FIGHTINGDOJO_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle,    SCRIPT_FIGHTINGDOJO_START_BATTLE
	dw_const EndTrainerBattle,                         SCRIPT_FIGHTINGDOJO_END_BATTLE
	dw_const FightingDojoKarateMasterPostBattleScript, SCRIPT_FIGHTINGDOJO_KARATE_MASTER_POST_BATTLE
	dw FightingDojoCancelLegacyEntryWalk ; script 4 in older saves

FightingDojoShowOrHideExitBlock:
	GymExitBlock EVENT_BEAT_KARATE_MASTER, $24, $74, 2, 0

FightingDojoInitRewards:
	ld hl, wRogueFlagsBitfield
	res BIT_ROGUE_TRADE_ACTIVE, [hl]
	ResetEvent EVENT_GOT_ROGUE_POKEMON
	CheckEvent EVENT_DEFEATED_FIGHTING_DOJO
	jr z, .publish
	SetEvent EVENT_GOT_ROGUE_POKEMON ; preserve a claim from an older save
.publish
	ld e, 0
	call FightingDojoResolveRewardSpecies
	ld [wRoguePokemon1], a
	ld e, 1
	call FightingDojoResolveRewardSpecies
	ld [wRoguePokemon2], a
	xor a
	ld [wRoguePokemon3], a
	ld [wRoguePokemonForm1], a
	ld [wRoguePokemonForm2], a
	farjp RogueRefresh

FightingDojoResolveRewardSpecies:
	farcall KarateDojoRewardSpecies
	farcall BridgeResolveEvolveSpeciesFar
	ld a, e
	ret

FightingDojoDefaultScript:
	CheckEvent EVENT_BEAT_KARATE_MASTER
	ret nz

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

FightingDojoCancelLegacyEntryWalk:
	xor a
	ldh [hSimulatedJoypadStatesIndex], a
	ld [wSimulatedJoypadStatesEnd], a
	ld hl, wStatusFlags5
	res BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	jp FightingDojoResetScripts

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
	call FightingDojoShowOrHideExitBlock.update
	CheckEvent EVENT_GOT_ROGUE_POKEMON
	jp nz, FightingDojoResetScripts
	ld a, TEXT_FIGHTINGDOJO_KARATE_MASTER_REWARD
	ldh [hTextID], a
	call DisplayTextID
	xor a ; SCRIPT_FIGHTINGDOJO_DEFAULT
	ldh [hJoyIgnore], a
	ld [wFightingDojoCurScript], a
	ld [wCurMapScript], a
	ret

; The first entries must be the objects' own texts in slot order, so
; the script-fired ids below sit past wNumSprites (DisplayTextID reroute).
FightingDojo_TextPointers:
	def_text_pointers
	dw_const FightingDojoKarateMasterText,       TEXT_FIGHTINGDOJO_KARATE_MASTER
	dw_const FightingDojoBlackbelt1Text,         TEXT_FIGHTINGDOJO_BLACKBELT1
	dw_const FightingDojoBlackbelt2Text,         TEXT_FIGHTINGDOJO_BLACKBELT2
	dw_const FightingDojoBlackbelt3Text,         TEXT_FIGHTINGDOJO_BLACKBELT3
	dw_const FightingDojoBoulderText,            TEXT_FIGHTINGDOJO_WEST_BOULDER
	dw_const RandomPickUpItemText,               TEXT_FIGHTINGDOJO_RANDOM_ITEM
	dw_const FightingDojoRewardBall1Text,        TEXT_FIGHTINGDOJO_REWARD_BALL_1
	dw_const FightingDojoRewardBall2Text,        TEXT_FIGHTINGDOJO_REWARD_BALL_2
	dw_const FightingDojoBoulderText,            TEXT_FIGHTINGDOJO_EAST_BOULDER
	dw_const FightingDojoKarateMasterRewardText, TEXT_FIGHTINGDOJO_KARATE_MASTER_REWARD

FightingDojoTrainerHeaders:
	def_trainers 2
FightingDojoTrainerHeader0:
	trainer EVENT_BEAT_FIGHTING_DOJO_TRAINER_0, 3, FightingDojoBlackbelt1BattleText, FightingDojoBlackbelt1EndBattleText, FightingDojoBlackbelt1AfterBattleText
FightingDojoTrainerHeader1:
	trainer EVENT_BEAT_FIGHTING_DOJO_TRAINER_1, 3, FightingDojoBlackbelt2BattleText, FightingDojoBlackbelt2EndBattleText, FightingDojoBlackbelt2AfterBattleText
FightingDojoTrainerHeader2:
	trainer EVENT_BEAT_FIGHTING_DOJO_TRAINER_2, 3, FightingDojoBlackbelt3BattleText, FightingDojoBlackbelt3EndBattleText, FightingDojoBlackbelt3AfterBattleText
	db -1 ; end

FightingDojoKarateMasterText:
	text_asm
	push bc
	CheckEvent EVENT_BEAT_KARATE_MASTER
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
	CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr nz, .defeated_dojo
	call FightingDojoOfferReward
.end
	pop bc
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
	push bc
	call FightingDojoOfferReward
	pop bc
	jp TextScriptEnd

FightingDojoOfferReward:
	ld hl, .IWillGiveYouAPokemonText
	call PrintText
	farjp KarateDojoRewardMenu

.IWillGiveYouAPokemonText:
	text_far _FightingDojoKarateMasterIWillGiveYouAPokemonText
	text_end

FightingDojoBoulderText:
	text_far _IgasDojoBoulderText
	text_end

FightingDojoRewardBall1Text:
	text_asm
	push bc
	ld e, 1
	call KarateDojoChooseReward
	pop bc
	jp TextScriptEnd

FightingDojoRewardBall2Text:
	text_asm
	push bc
	ld e, 2
	call KarateDojoChooseReward
	pop bc
	jp TextScriptEnd

; e = offer slot (1-2), from a ball or the Master's menu.
KarateDojoChooseReward::
	ld a, e
	cp 1
	jr nz, .second
	ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
	farjp Rogue_Reward_Script_PokeballText_1.noTrade
.second
	ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
	farjp Rogue_Reward_Script_PokeballText_2

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
