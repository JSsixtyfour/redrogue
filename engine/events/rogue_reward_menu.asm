DEF ROGUE_REWARD_NUM_SLOTS EQU 3

RogueRewardMenu::
    ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	ld hl, RogueRewardText
	call PrintText
; the following are the menu settings
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, PAD_A | PAD_B | PAD_UP | PAD_DOWN
	ld [wMenuWatchedKeys], a
	ld a, ROGUE_REWARD_NUM_SLOTS
	ld [wMaxMenuItem], a
	ld a, $04
	ld [wTopMenuItemY], a
	ld a, $01
	ld [wTopMenuItemX], a
	hlcoord 0, 2
	ld b, 8
	ld c, 16
	call TextBoxBorder
	call RogueDrawRewardSlots
	call UpdateSprites
	ld hl, RogueRewardTextChoice
	call PrintText
	; if trade is active, show hover box immediately (cursor starts at slot 0)
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	jr z, .menuLoop
	jr .showTradeHover
.menuLoop
	call HandleMenuInput
	bit B_PAD_A, a
	jr nz, .aPressed
	bit B_PAD_B, a
	jr nz, .noChoice
	; cursor moved — update hover box if trade is active
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	jr z, .menuLoop
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .eraseTradeHover
.showTradeHover
    hlcoord 0, 0
	lb bc, 18, 3
	predef SaveScreenTileAreaToBuffer3
	hlcoord 0, 0
	ld b, 1
	ld c, 16
	call TextBoxBorder
	hlcoord 1, 1
	ld de, TradeHoverLabel
	call PlaceString
	ld a, [wroguenpctradegive]
	ld [wNamedObjectIndex], a
	call GetMonName
	hlcoord 7, 1
	ld de, wNameBuffer
	call PlaceString
	jr .menuLoop
.eraseTradeHover
	hlcoord 0, 0
	lb bc, 18, 3
	predef LoadScreenTileAreaFromBuffer3
	jr .menuLoop
.aPressed
	ldh a, [hCurrentMenuItem]
	cp ROGUE_REWARD_NUM_SLOTS
	jr z, .noChoice
	call HandleRewardChoice
.noChoice
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ret

RogueRewardText:
    text_far _RogueRewardText
	text_end

RogueRewardTextChoice:
	text_far _WhichPrizeText
	text_end

; ---------------------------------------------------------------------------
; RogueDrawRewardSlots
; Draws each of wRoguePokemon1..ROGUE_REWARD_NUM_SLOTS's name, then NO THANKS
; beneath them, and the TRADE label over slot 0 if a trade offer is active
; there. One count-driven loop instead of three unrolled copies of the same
; draw, following the same shape BridgeGiftMenu uses for its own gift rows
; (BridgeCoordRow2, same bank, so a plain call reaches it).
; ---------------------------------------------------------------------------
RogueDrawRewardSlots:
	ld c, 0                      ; c = slot index (0-based), also wRoguePokemon offset
.slotLoop
	ld a, c
	add a
	add 4                        ; row = 4 + 2*index
	call BridgeCoordRow2         ; hl = coord(2, row)
	push hl
	ld hl, wRoguePokemon1
	ld d, 0
	ld e, c
	add hl, de
	ld a, [hl]
	ld [wNamedObjectIndex], a
	call GetMonName
	pop hl
	call PlaceString             ; preserves hl
	; slot 0 only: TRADE label if a trade offer occupies it
	ld a, c
	and a
	jr nz, .noTradeLabel
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	jr z, .noTradeLabel
	hlcoord 12, 4
	ld de, TradeSlotLabel
	call PlaceString
.noTradeLabel
	inc c
	ld a, c
	cp ROGUE_REWARD_NUM_SLOTS
	jr c, .slotLoop

	ld a, ROGUE_REWARD_NUM_SLOTS
	add a
	add 4                        ; row = 4 + 2*ROGUE_REWARD_NUM_SLOTS
	call BridgeCoordRow2
	ld de, NoThanksText
	jp PlaceString

HandleRewardChoice:
    ldh a, [hCurrentMenuItem]
    ld b, a
    push bc
	ld d, 0
	ld e, a
	ld hl, wRoguePokemon1
	add hl, de
	ld a, [hl]
	ld [wNamedObjectIndex], a
.getMonName
	call GetMonName
    ; trade offer always occupies slot 1 (index 0); BIT_ROGUE_TRADE_ACTIVE gates it
    ldh a, [hCurrentMenuItem]
    and a
    jr nz, .givePrize
    ld a, [wRogueFlagsBitfield]
    bit BIT_ROGUE_TRADE_ACTIVE, a
    jr z, .givePrize
    ; trade slot selected — run full in-game trade dialogue with animation
    pop bc                          ; balance push bc from top of HandleRewardChoice
    ld hl, wStatusFlags5
    res BIT_NO_TEXT_DELAY, [hl]     ; restore normal text speed for animation
    ld a, TRADE_FOR_RANDOM
    ld [wWhichTrade], a
    ldh a, [hTileAnimations]
    push af
    xor a
    ldh [hTileAnimations], a
    predef RogueDoInGameTradeDialogue
    pop af
    ldh [hTileAnimations], a
    ; TRADE_FOR_RANDOM flag is set by InGameTrade_DoTrade on success
    ld c, TRADE_FOR_RANDOM
    ld b, FLAG_TEST
    ld hl, wCompletedInGameTradeFlags
    predef FlagActionPredef
    ld a, c
    and a
    ret z                           ; declined or wrong mon selected
    SetEvent EVENT_GOT_ROGUE_POKEMON
    ret                             ; trade NPC stays visible, unlike the pokeballs
.givePrize
	ld hl, SoYouWantRewardText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem] ; yes/no answer (Y=0, N=1)
	and a
    pop bc
	jp nz, .printOhFineThen
.giveMon
    ; Challenge 7 (PARTY_LIMIT): limit = min(2 + wBattleCount/10, 5).
    ; Increases by 1 each round (every 10 battles), starting at 2. Cap 5.
    ld a, [wRogueFlagsBitfield]
    bit BIT_WITCH_ACCEPTED, a
    jr z, .noPartyLimit
    ld a, [wWitchChallenge]
    cp CHALLENGE_PARTY_LIMIT
    jr nz, .noPartyLimit
    ld a, [wBattleCount]
    ld c, 0
.limitDivLoop
    cp 10
    jr c, .limitDivDone
    sub 10
    inc c
    jr .limitDivLoop
.limitDivDone
    ld a, c
    add 2               ; limit = 2 + rounds_completed
    cp 6
    jr c, .limitCapped
    ld a, 5
.limitCapped
    ld c, a             ; c = party limit
    ld a, [wPartyCount]
    cp c
    jr c, .noPartyLimit ; wPartyCount < limit: allow
    ld hl, WitchPartyLimitText
    call PrintText
    ret
.noPartyLimit
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
    add a, b
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, [wNamedObjectIndex]
	ld [wCurPartySpecies], a
	push af
	call GetRewardMonLevel
	ld c, a
	pop af
	ld b, a
	call GivePokemon
    SetEvent EVENT_GOT_ROGUE_POKEMON

; If either the party or box was full, wait after displaying message.
	push af
	ld a, [wAddedToParty]
	and a
	call z, WaitForTextScrollButtonPress
	pop af

; If the mon couldn't be given to the player (because both the party and box
; were full), return without subtracting coins.
	ret nc
	; _GivePokemon's add-to-party success path sets hNoWaitAfterText=1 for its
	; own purposes and never clears it - without this, Goodluck below would
	; flash by without waiting for a button press.
	xor a
	ldh [hNoWaitAfterText], a
	ld hl, Goodluck
	jp PrintText
.printOhFineThen
	ld hl, OhFineThenRewardText
	jp PrintText

WitchPartyLimitText:
	text_far _WitchPartyLimitText
	text_end

SoYouWantRewardText:
	text_far _SoYouWantPrizeText
	text_end

TradeSlotLabel:
	db "TRADE@"

TradeHoverLabel:
	db "GIVE:@"

OhFineThenRewardText:
	text_far _OhFineThenText
	;text_waitbutton
	text_end

Goodluck:
	text_far _Goodluck
	;text_waitbutton
	text_end

NoThanksText:
	db "NO THANKS@"

GetRewardMonLevel::
	; Reward Room and Oak's Lab (starter selection) always use a flat level 5
	; regardless of progress. Everywhere else, the level is tailored to
	; whichever tier is relevant (1 higher than the highest standard,
	; non-final-bonus trainer level in that tier), read directly from
	; trainer_difficulty_settings/_gym so it can never drift out of sync with
	; the actual trainer data.
	;
	; Two different callers, two different tiers:
	; - A stage's own reward pokeballs are rolled at stage entry, while still
	;   on a route - the gym of the SAME round is always what's coming up
	;   next, so this case always uses the gym tier, no remainder check.
	; - The salesman/trader (lobby only) needs to know which door is
	;   literally next, which does depend on wBattleCount's position within
	;   the round (remainder 0-4 = route next, 5-9 = gym next).
	ldh a, [hCurMap]
	cp REWARD_ROOM
	jr z, .flatFive
	cp OAKS_LAB
	jr z, .flatFive
	cp INDIGO_PLATEAU_LOBBY
	jr z, .lobbyCaller

	ld a, [wBattleCount]
	cp 90
	jr c, .noClampRoundStage
	ld a, 89
.noClampRoundStage
	ld b, 0                 ; b = round index (0-8)
.getRoundIndexStage
	cp 10
	jr c, .gotTable
	sub 10
	inc b
	jr .getRoundIndexStage

.lobbyCaller
	ld a, [wBattleCount]
	cp 90
	jr c, .noClampRound
	ld a, 89                ; clamp to round 9's settings, same as GetRandRoster
.noClampRound
	ld b, 0                 ; b = round index (0-8)
.getRoundIndex
	cp 10
	jr c, .gotRoundIndex
	sub 10
	inc b
	jr .getRoundIndex
.gotRoundIndex
	; a = remainder within the round (0-9): 0-4 means a gym was just cleared
	; (or no battles yet) and a route is next; 5-9 means a route was just
	; cleared and the gym is next.
	cp 5
	jr nc, .gotTable
	ld hl, trainer_difficulty_settings
	jr .pickedTable
.gotTable
	ld hl, trainer_difficulty_settings_gym
.pickedTable
	ld a, b                 ; each settings block is 11 bytes
	ld d, a
	add a, a                ; *2
	add a, a                ; *4
	add a, a                ; *8
	add a, d                ; *9
	add a, d                ; *10
	add a, d                ; *11
	ld c, a
	ld b, 0
	add hl, bc               ; hl -> this round's 11-byte block (still bank 07 address)
	ld de, wRewardLevelDataBuffer ; trainer_difficulty_settings/_gym live in bank 07,
	ld a, BANK(trainer_difficulty_settings) ; this function doesn't - read across
	ld bc, 2                ; banks instead of a plain (same-bank-only) [hl] read
	call FarCopyData
	ld a, [wRewardLevelDataBuffer]   ; byte 0: level range
	ld b, a
	ld a, [wRewardLevelDataBuffer + 1] ; byte 1: minimum level
	add b                    ; minimum + range = (max standard level) + 1
	cp 51
	jr c, .levelOk
	ld a, 50
.levelOk
	ld [wCurEnemyLevel], a
	ret
.flatFive
	ld a, 5
	ld [wCurEnemyLevel], a
	ret

RogueRefresh::
	farcall MarkCurrentStageVisited  ; record this stage as visited for no-duplicate selection
	; witch's "no reward pokemon" challenge: hide all 3 pokeballs and the
	; trade NPC instead of the usual show/hide-by-trade-flag logic below
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .normalPokeballLogic
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_REWARD_POKEMON
	jr nz, .normalPokeballLogic
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_TRADE_NPC
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef HideObject
	jr .randomItemCheck
.normalPokeballLogic
	; show/hide pokeball 1 and trade NPC based on trade active flag
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	jr nz, .tradeActive
	; no trade: show pokeball 1, hide trade NPC
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_ROGUE_TRADE_NPC
	ld [wToggleableObjectIndex], a
	predef HideObject
	jr .showRest
.tradeActive
	; trade: hide pokeball 1, show trade NPC
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_TRADE_NPC
	ld [wToggleableObjectIndex], a
	predef ShowObject
.showRest
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef ShowObject
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef ShowObject
.randomItemCheck
	; witch's "no random item" challenge: hide the random item instead of
	; the usual unconditional show
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .showRandomItem
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_RANDOM_ITEM
	jr nz, .showRandomItem
	ld a, TOGGLE_STAGE_RANDOM_ITEM
	ld [wToggleableObjectIndex], a
	predef HideObject
	ret
.showRandomItem
    ld a, TOGGLE_STAGE_RANDOM_ITEM
	ld [wToggleableObjectIndex], a
	predef ShowObject
	; Challenge 9 (ALL_POISONED): poison every party member at stage entry.
	; Fainted mons are included visually but PSN does no additional battle damage to them.
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_ALL_POISONED
	ret nz
	ld a, [wPartyCount]
	and a
	ret z
	ld b, a          ; b = party count
	ld hl, wPartyMon1Status
	ld de, PARTYMON_STRUCT_LENGTH
.poisonLoop
	set PSN, [hl]            ; set PSN bit on status byte (PSN = bit 3 = $08)
	add hl, de               ; advance to next mon's status byte
	dec b
	jr nz, .poisonLoop
