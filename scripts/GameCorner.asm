DEF GAME_CORNER_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_GAME_CORNER_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_GAME_CORNER_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_GAME_CORNER_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_GAME_CORNER_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_GAME_CORNER_TRAINER_4 % 8))

GameCorner_Script:
	; Skip slot machine setup when used as Gambler's Paradise rogue stage
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
    ld a, [wEventFlags + (EVENT_BEAT_GAME_CORNER_TRAINER_0 / 8)]
    and GAME_CORNER_ALL_TRAINERS_MASK
    cp GAME_CORNER_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_GAME_CORNER_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
    call EnableAutoTextBoxDrawing
	ld hl, GameCornerTrainerHeaders
	ld de, GameCorner_ScriptPointers
	ld a, [wGameCornerCurScript]
	call ExecuteCurMapScriptInTable
    ld [wGameCornerCurScript], a
	ret

;GameCornerSelectLuckySlotMachine:
;	ld hl, wCurrentMapScriptFlags
;	bit BIT_CUR_MAP_LOADED_2, [hl]
;	res BIT_CUR_MAP_LOADED_2, [hl]
;	ret z
;	call Random
;	ldh a, [hRandomAdd]
;	cp $7
;	jr nc, .not_max
;	ld a, $8
;.not_max
;	srl a
;	srl a
;	srl a
;	ld [wLuckySlotHiddenEventIndex], a
;	ret
;
;GameCornerSetRocketHideoutDoorTile:
;	ld hl, wCurrentMapScriptFlags
;	bit BIT_CUR_MAP_LOADED_1, [hl]
;	res BIT_CUR_MAP_LOADED_1, [hl]
;	ret z
;	CheckEvent EVENT_FOUND_ROCKET_HIDEOUT
;	ret nz
;	ld a, $2a
;	ld [wNewTileBlockID], a
;	lb bc, 2, 8
;	predef_jump ReplaceTileBlock

GameCornerReenterMapAfterPlayerLoss:
	xor a ; SCRIPT_GAMECORNER_DEFAULT
	ldh [hJoyIgnore], a
	ld [wGameCornerCurScript], a
	ld [wCurMapScript], a
	ret

GameCorner_ScriptPointers:
	def_script_pointers
	dw_const GameCornerDefaultScript,      SCRIPT_GAMECORNER_DEFAULT
	;dw_const GameCornerRocketBattleScript, SCRIPT_GAMECORNER_ROCKET_BATTLE
	;dw_const GameCornerRocketExitScript,   SCRIPT_GAMECORNER_ROCKET_EXIT

GameCornerDefaultScript:
	ret

;GameCornerRocketBattleScript:
;	ldh a, [hIsInBattle]
;	cp $ff
;	jp z, GameCornerReenterMapAfterPlayerLoss
;	ld a, PAD_CTRL_PAD
;	ldh [hJoyIgnore], a
;	ld a, TEXT_GAMECORNER_ROCKET_AFTER_BATTLE
;	ldh [hTextID], a
;	call DisplayTextID
;	ld a, GAMECORNER_ROCKET
;	ldh [hSpriteIndex], a
;	call SetSpriteMovementBytesToFF
;	ld de, GameCornerMovement_Rocket_WalkAroundPlayer
;	ld a, [wYCoord]
;	cp 6
;	jr nz, .not_direct_movement
;	ld de, GameCornerMovement_Rocket_WalkDirect
;	jr .got_rocket_movement
;.not_direct_movement
;	ld a, [wXCoord]
;	cp 8
;	jr nz, .got_rocket_movement
;	ld de, GameCornerMovement_Rocket_WalkDirect
;.got_rocket_movement
;	ld a, GAMECORNER_ROCKET
;	ldh [hSpriteIndex], a
;	call MoveSprite
;	ld a, SCRIPT_GAMECORNER_ROCKET_EXIT
;	ld [wGameCornerCurScript], a
;	ret

;GameCornerMovement_Rocket_WalkAroundPlayer:
;	db NPC_MOVEMENT_DOWN
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_UP
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db -1 ; end
;
;GameCornerMovement_Rocket_WalkDirect:
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db NPC_MOVEMENT_RIGHT
;	db -1 ; end
;
;GameCornerRocketExitScript:
;	ld a, [wStatusFlags5]
;	bit BIT_SCRIPTED_NPC_MOVEMENT, a
;	ret nz
;	xor a
;	ldh [hJoyIgnore], a
;	ld a, TOGGLE_GAME_CORNER_ROCKET
;	ld [wToggleableObjectIndex], a
;	predef HideObject
;	ld hl, wCurrentMapScriptFlags
;	set BIT_CUR_MAP_LOADED_1, [hl]
;	set BIT_CUR_MAP_LOADED_2, [hl]
;	ld a, SCRIPT_GAMECORNER_DEFAULT
;	ld [wGameCornerCurScript], a
;	ret

GameCorner_TextPointers:
	def_text_pointers
	dw_const GameCornerBeauty1Text,           TEXT_GAMECORNER_BEAUTY1
	dw_const GameCornerClerk1Text,            TEXT_GAMECORNER_CLERK1
	dw_const GameCornerMiddleAgedMan1Text,    TEXT_GAMECORNER_MIDDLE_AGED_MAN1
	dw_const GameCornerBeauty2Text,           TEXT_GAMECORNER_BEAUTY2
	dw_const GameCornerFishingGuruText,       TEXT_GAMECORNER_FISHING_GURU
	dw_const RandomPickUpItemText,            TEXT_GAMECORNER_RANDOM
	dw_const GameCornerMiddleAgedWomanText,   TEXT_GAMECORNER_MIDDLE_AGED_WOMAN
	dw_const GameCornerGymGuideText,          TEXT_GAMECORNER_GYM_GUIDE
	dw_const GameCornerGamblerText,           TEXT_GAMECORNER_GAMBLER
	dw_const GameCornerClerk2Text,            TEXT_GAMECORNER_CLERK2
	dw_const GameCornerGentlemanText,         TEXT_GAMECORNER_GENTLEMAN
	dw_const GameCornerGentlemanText,            TEXT_GAMECORNER_ROCKET
	dw_const GameCornerPosterText,            TEXT_GAMECORNER_POSTER
	dw_const GameCornerRocketAfterBattleText, TEXT_GAMECORNER_ROCKET_AFTER_BATTLE
    dw_const Rogue_GameCorner_Reward_Text, TEXT_GAME_CORNER_REWARD_VENDOR_1
    EXPORT TEXT_GAME_CORNER_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm

GameCornerBeauty1Text:
	text_far _GameCornerBeauty1Text
	text_end

GameCornerClerk1Text:
	text_asm
	farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon
   
    ld hl, GameCornerGreedyText
	call PrintText
	jr .done
    
    .GetMon
    xor a
    ld a, TEXT_GAME_CORNER_REWARD_VENDOR_1
	ldh [hTextID], a
	call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd
    
GameCornerGreedyText:
	text_far _GreedyText
	text_end
;.normalClerk
;	; Show player's coins
;	call GameCornerDrawCoinBox
;	ld hl, .DoYouNeedSomeGameCoins
;	call PrintText
;	call YesNoChoice
;	ldh a, [hCurrentMenuItem]
;	and a
;	jr nz, .declined
;	; Can only get more coins if you
;	; - have the Coin Case
;	ld b, COIN_CASE
;	call IsItemInBag
;	jr z, .no_coin_case
;	; - have room in the Coin Case for at least 9 coins
;	call Has9990Coins
;	jr nc, .coin_case_full
;	; - have at least 1000 yen
;	xor a
;	ldh [hMoney], a
;	ldh [hMoney + 2], a
;	ld a, $10
;	ldh [hMoney + 1], a
;	call HasEnoughMoney
;	jr nc, .buy_coins
;	ld hl, .CantAffordTheCoins
;	jr .print_ret
;.buy_coins
;	; Spend 1000 yen
;	xor a
;	ldh [hMoney], a
;	ldh [hMoney + 2], a
;	ld a, $10
;	ldh [hMoney + 1], a
;	ld hl, hMoney + 2
;	ld de, wPlayerMoney + 2
;	ld c, $3
;	predef SubBCDPredef
;	; Receive 50 coins
;	xor a
;	ldh [hUnusedCoinsByte], a
;	ldh [hCoins], a
;	ld a, $50
;	ldh [hCoins + 1], a
;	ld de, wPlayerCoins + 1
;	ld hl, hCoins + 1
;	ld c, $2
;	predef AddBCDPredef
;	; Update display
;	call GameCornerDrawCoinBox
;	ld hl, .ThanksHereAre50Coins
;	jr .print_ret
;.declined
;	ld hl, .PleaseComePlaySometime
;	jr .print_ret
;.coin_case_full
;	ld hl, .CoinCaseIsFull
;	jr .print_ret
;.no_coin_case
;	ld hl, .DontHaveCoinCase
;.print_ret
;	call PrintText
;	jp TextScriptEnd

;.DoYouNeedSomeGameCoins:
;	text_far _GameCornerClerk1DoYouNeedSomeGameCoinsText
;	text_end
;
;.ThanksHereAre50Coins:
;	text_far _GameCornerClerk1ThanksHereAre50CoinsText
;	text_end
;
;.PleaseComePlaySometime:
;	text_far _GameCornerClerk1PleaseComePlaySometimeText
;	text_end
;
;.CantAffordTheCoins:
;	text_far _GameCornerClerk1CantAffordTheCoinsText
;	text_end
;
;.CoinCaseIsFull:
;	text_far _GameCornerClerk1CoinCaseIsFullText
;	text_end
;
;.DontHaveCoinCase:
;	text_far _GameCornerClerk1DontHaveCoinCaseText
;	text_end

; ============================================================
; Gambler's Paradise trainer scripts (5 trainers, Route1 style)
; ============================================================
GameCornerTrainerHeaders:
GameCornerTrainerHeader0:
	trainer EVENT_BEAT_GAME_CORNER_TRAINER_0, 1, GameCornerGamblerBattleText, GameCornerGamblerEndBattleText, GameCornerGamblerAfterBattleText
GameCornerTrainerHeader1:
	trainer EVENT_BEAT_GAME_CORNER_TRAINER_1, 2, GameCornerGamblerBattleText, GameCornerGamblerEndBattleText, GameCornerGamblerAfterBattleText
GameCornerTrainerHeader2:
	trainer EVENT_BEAT_GAME_CORNER_TRAINER_2, 3, GameCornerGamblerBattleText, GameCornerGamblerEndBattleText, GameCornerGamblerAfterBattleText
GameCornerTrainerHeader3:
	trainer EVENT_BEAT_GAME_CORNER_TRAINER_3, 4, GameCornerGamblerBattleText, GameCornerGamblerEndBattleText, GameCornerGamblerAfterBattleText
GameCornerTrainerHeader4:
	trainer EVENT_BEAT_GAME_CORNER_TRAINER_4, 5, GameCornerGamblerBattleText, GameCornerGamblerEndBattleText, GameCornerGamblerAfterBattleText
	db -1 ; end

GameCornerGamblerBattleText:
	text_far _GameCornerGamblerBattleText
	text_end

GameCornerGamblerEndBattleText:
	text_far _GameCornerGamblerEndBattleText
	text_end

GameCornerGamblerAfterBattleText:
	text_far _GameCornerGamblerAfterBattleText
	text_end

; Text IDs for the 5 trainer NPCs — all call TalkToTrainer with their header
GameCornerGamblerText:           ; Trainer 0 (slot GAMECORNER_BEAUTY1)
	text_asm
	ld hl, GameCornerTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

GameCornerMiddleAgedMan1Text:    ; Trainer 1 (slot GAMECORNER_CLERK1)
	text_asm
	ld hl, GameCornerTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

GameCornerFishingGuruText:       ; Trainer 2 (slot GAMECORNER_MIDDLE_AGED_MAN1)
	text_asm
	ld hl, GameCornerTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

GameCornerBeauty2Text:           ; Trainer 3 (slot GAMECORNER_BEAUTY2)
	text_asm
	ld hl, GameCornerTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

GameCornerGymGuideText:          ; Trainer 4 (slot GAMECORNER_FISHING_GURU)
	text_asm
	ld hl, GameCornerTrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

GameCornerMiddleAgedWomanText:
	text_far _GameCornerMiddleAgedWomanText
	text_end

GameCornerClerk2Text:
	text_asm
	ld hl, .WantSomeCoinsText
	call PrintText
	jp TextScriptEnd

.WantSomeCoinsText:
	text_far _GameCornerClerk2WantSomeCoinsText
	text_end

GameCornerGentlemanText:
	text_asm
	ld hl, .ThrowingMeOffText
	call PrintText
	jp TextScriptEnd

.ThrowingMeOffText:
	text_far _GameCornerGentlemanThrowingMeOffText
	text_end

;GameCornerRocketText:
;	text_asm
;	ld hl, .ImGuardingThisPosterText
;	call PrintText
;	ld hl, wStatusFlags3
;	set BIT_TALKED_TO_TRAINER, [hl]
;	set BIT_PRINT_END_BATTLE_TEXT, [hl]
;	ld hl, .BattleEndText
;	ld de, .BattleEndText
;	call SaveEndBattleTextPointers
;	ldh a, [hSpriteIndex]
;	ldh [hActiveSpriteIndex], a
;	call EngageMapTrainer
;	call InitBattleEnemyParameters
;	xor a
;	ldh [hJoyHeld], a
;	ldh [hJoyPressed], a
;	ldh [hJoyReleased], a
;	ld a, SCRIPT_GAMECORNER_ROCKET_BATTLE
;	ld [wGameCornerCurScript], a
;	jp TextScriptEnd
;
;.ImGuardingThisPosterText:
;	text_far _GameCornerRocketImGuardingThisPosterText
;	text_end
;
;.BattleEndText:
;	text_far _GameCornerRocketBattleEndText
;	text_end
;
GameCornerRocketAfterBattleText:
	text_far _GameCornerRocketAfterBattleText
	text_end

GameCornerPosterText:
	text_asm
	ld a, $1
	ldh [hNoWaitAfterText], a
	ld hl, .SwitchBehindPosterText
	call PrintText
	call WaitForSoundToFinish
	ld a, SFX_GO_INSIDE
	call PlaySound
	call WaitForSoundToFinish
	SetEvent EVENT_FOUND_ROCKET_HIDEOUT
	ld a, $43
	ld [wNewTileBlockID], a
	lb bc, 2, 8
	predef ReplaceTileBlock
	jp TextScriptEnd

.SwitchBehindPosterText:
	text_far _GameCornerPosterSwitchBehindPosterText
	text_asm
	ld a, SFX_SWITCH
	call PlaySound
	call WaitForSoundToFinish
	jp TextScriptEnd

GameCornerOopsForgotCoinCaseText:
	text_far _GameCornerOopsForgotCoinCaseText
	text_end

GameCornerDrawCoinBox:
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	hlcoord 11, 0
	ld b, 5
	ld c, 7
	call TextBoxBorder
	call UpdateSprites
	hlcoord 12, 1
	ld b, 4
	ld c, 7
	call ClearScreenArea
	hlcoord 12, 2
	ld de, GameCornerMoneyText
	call PlaceString
	hlcoord 12, 3
	ld de, GameCornerBlankText1
	call PlaceString
	hlcoord 12, 3
	ld de, wPlayerMoney
	ld c, 3 | MONEY_SIGN | LEADING_ZEROES
	call PrintBCDNumber
	hlcoord 12, 4
	ld de, GameCornerCreditText
	call PlaceString
	hlcoord 12, 5
	ld de, GameCornerBlankText2
	call PlaceString
	hlcoord 15, 5
	ld de, wPlayerCoins
	ld c, 2 | LEADING_ZEROES
	call PrintBCDNumber
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ret

GameCornerMoneyText:
	db "MONEY@"

GameCornerCreditText:
	db "CREDIT@"

GameCornerBlankText1:
	db "       @"

GameCornerBlankText2:
	db "       @"

Rogue_GameCorner_Reward_Text:
	script_rogue_reward

Has9990Coins::
	ld a, $99
	ldh [hCoins], a
	ld a, $90
	ldh [hCoins + 1], a
	jp HasEnoughCoins
