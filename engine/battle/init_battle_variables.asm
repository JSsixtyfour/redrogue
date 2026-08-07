InitBattleVariables:
; ELEMENT PRISM: resolve the two hot-path damage caches once per battle (see
; custom_functions/element_prism.asm). Placed here rather than in core.asm's
; InitBattleCommon because this routine is already callfar'd once per battle
; start from there, and "Battle Core" is the tightest bank in the ROM.
	farcall RoguePrismRefreshCache
; TURN REWIND: mark "no snapshot yet" for this battle (see
; custom_functions/turn_rewind.asm). Here for the same reason as the prism
; refresh above - this routine is already callfar'd once per battle start
; from core.asm's InitBattleCommon, and "Battle Core" is the tightest bank.
	farcall TurnRewindInit
	ldh a, [hTileAnimations]
	ld [wSavedTileAnimations], a
	xor a
    ld [wWasTrainerBattle], a
	ld [wActionResultOrTookBattleTurn], a
	ld [wBattleResult], a
	ld hl, wPartyAndBillsPCSavedMenuItem
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ld [wListScrollOffset], a
	ld [wCriticalHitOrOHKO], a
	ld [wBattleMonSpecies], a
	ld [wPartyGainExpFlags], a
	ld [wPlayerMonNumber], a
	ld [wEscapedFromBattle], a
	ld [wMapPalOffset], a
	ld hl, wPlayerHPBarColor
	ld [hli], a ; wPlayerHPBarColor
	ld [hl], a ; wEnemyHPBarColor
	ld hl, wCanEvolveFlags
	ld b, wMiscBattleDataEnd - wMiscBattleData
.loop
	ld [hli], a
	dec b
	jr nz, .loop
	inc a ; POUND
	ld [wTestBattlePlayerSelectedMove], a
	ldh a, [hCurMap]
	cp SAFARI_ZONE_EAST
	jr c, .notSafariBattle
	cp SAFARI_ZONE_CENTER_REST_HOUSE
	jr nc, .notSafariBattle
	ld a, BATTLE_TYPE_SAFARI
	ld [wBattleType], a
.notSafariBattle
	jpfar PlayBattleMusic
