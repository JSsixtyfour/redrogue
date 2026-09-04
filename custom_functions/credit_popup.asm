; custom_functions/credit_popup.asm
;
; Draws a brief "N credits earned, new total M" box if there are unreported
; credits, then zeroes the tally. No separate "popup pending" flag is needed:
; a nonzero wCreditsEarnedThisRun IS the pending condition, since this routine
; is the only thing that ever clears it.
;
; Deliberately does NOT reset run state (slot pulls, KO Defiance charges) -
; that belongs to RogueOnBlackout below. Tying the reset to the popup would
; skip it whenever the player blacks out having earned zero credits, which is
; exactly the bad early run where it matters most.

RogueCreditPopupCheck::
	ld a, [wCreditsEarnedThisRun]
	and a
	ret z

	hlcoord 1, 1
	lb bc, 18, 4
	predef SaveScreenTileAreaToBuffer3
	hlcoord 1, 1
	ld b, 2
	ld c, 16
	call TextBoxBorder
	hlcoord 2, 2
	ld de, .EarnedText
	call PlaceString
	hlcoord 9, 2
	ld de, wCreditsEarnedThisRun
	lb bc, LEFT_ALIGN | 1, 2
	call PrintNumber
	hlcoord 11, 2
	ld de, .CreditsText
	call PlaceString
	hlcoord 2, 3
	ld de, .TotalText
	call PlaceString
	hlcoord 9, 3
	ld de, wPlayerCoins
	ld c, 2 | LEADING_ZEROES | LEFT_ALIGN
	call PrintBCDNumber
	call UpdateSprites
	ld c, 90
	call DelayFrames

	hlcoord 1, 1
	lb bc, 18, 4
	predef LoadScreenTileAreaFromBuffer3

	xor a
	ld [wCreditsEarnedThisRun], a
	ret

.EarnedText:
	db "EARNED @"
.CreditsText:
	db "CREDITS@"
.TotalText:
	db "TOTAL: @"

; ============================================================
; RogueResetRunState - the single end-of-run wipe.
;
; Called from RogueOnBlackout (below) and, by farcall, from
; HallOfFameResetEventsAndSaveScript (scripts/HallOfFame.asm). Those are the
; only two places a run ends, and this is the only thing that ends one.
;
; Five parts, in order (order matters - later steps re-derive values the
; earlier blanket clears zeroed):
;
; 1. Events - one ResetEventRange over ZONE 1 of constants/event_constants.asm
;    (every stage/gym/Elite 4 trainer bit, auto-walk "no turning back" flags,
;    reward/offer flags, procedural stage flags, EVENT_VICTORY_ROAD_CLEARED).
;    ZONE 0 (ELEMENT PRISM one-time-ever flags) is untouched by design.
;
; 2. wGameProgressFlags - the SAME region init_player_data.asm blanket-clears
;    at true new game (FillMemory over wGameProgressFlags..wGameProgressFlagsEnd).
;    This one FillMemory covers: wVisitedStagesBitfield, wRogueFlagsBitfield
;    (gym-next/final-trainer/trade-active/witch-accepted), wRogueItem*,
;    wBattleCount, wRoutesSinceSpecial, wMiniBossCount, wWildAreaState,
;    wBridgeOfferedLo/State, wWitchChallenge/Prize, wEarnedStatBoosts,
;    wWitchPrizesEarned, wWitchLevelBonus/wPartyLimit/wBattleTurnLimit/
;    wBattleTurnCount (witch challenge params), wRewardClassBonus/
;    wItemClassBonus/wMoneyMultiplier/wPrizeExpBoost (witch prize bonuses),
;    wFusionSecondarySpecies/BaseStats, wCreditsEarnedThisRun,
;    wRogueFlagsBitfield2, and every map's CurScript byte (every map resets to
;    its default entry state) - plus wHealAllItemLevel/wRestorePPItemLevel/
;    wKODefianceUsages/wExpAllLevel/wDiceCharges/wPrismType/wPrismDamageBonus/
;    wPrismRerollsLeft, which step 3 immediately re-derives.
;
; 3. Re-derive the SRAM-tier caches step 2 just zeroed. wKODefianceUsages,
;    wDiceCharges and wExpAllLevel are not run flags - they are cached copies
;    of a persistent SRAM upgrade tier (sKeyItemTiers), refreshed here so the
;    upgrade a player already bought keeps working instead of silently
;    downgrading to tier 0 until their next Credit Exchange visit.
;    ApplyKeyItemTierEffects (engine/events/credit_mart.asm) already existed
;    for exactly this, its own doc comment saying it should run "at the next
;    run boundary" - it just was never wired to one before now. It also
;    farcalls RoguePrismRefreshCache, covering wPrismType/wPrismDamageBonus.
;    wPrismRerollsLeft needs no re-derive - it is set fresh every time it is
;    used (custom_functions/element_prism.asm), scratch not persistent state.
;    Dice charges use a different per-item bit-packing than
;    ApplyKeyItemTierEffects handles, so that logic (unchanged from what used
;    to live in RogueOnBlackout) is inlined below it.
;
; 4. Badges, item pocket counts, TM/HM ownership, money and coins - reset to
;    the exact values a true new game starts with
;    (engine/movie/oak_speech/init_player_data.asm). All outside
;    wGameProgressFlags, so step 2 does not touch them. TM/HM ownership lives
;    in sTMBitfield (SRAM) - wTMPocketBuf is just a scratch UI display list
;    rebuilt from it every time the bag opens (BuildTMPocketList,
;    custom_functions/tm_bag.asm), not real state, so it is ClearTMBitfield
;    (same file) that is called here, same as at true new game.
;
; 5. Party, boxes (WRAM + all 12 SRAM banks), daycare and starter species -
;    also outside wGameProgressFlags. Party/box use the same "count=0,
;    terminator=-1" empty convention the engine already uses everywhere (the
;    old mon bytes are not wiped, just marked empty, exactly like depositing
;    the last Pokemon from a box already does). The other 11 SRAM boxes are
;    wiped by EmptyAllSRAMBoxes (engine/menus/save.asm), the exact routine
;    already used the first time a player opens Bill's PC - reused rather
;    than re-deriving its box-bank checksum math.
;
; NOT touched: Key Items ownership (sKeyItemsBitfield, SRAM) - explicitly
; documented in init_player_data.asm as surviving a run-reset, since it is
; meta-progression, not run state. Also not touched: the Pokedex.
;
; Clearing wPlayerStarter/wRivalStarter alongside the party means Oak's Lab
; starter selection replays after every blackout/champion-clear (matching the
; 2026-09-03 audit that moved EVENT_ESTABLISHED_STARTER/EVENT_GOT_STARTER/
; EVENT_BATTLED_RIVAL_IN_OAKS_LAB to run-scoped for exactly this reason).
; ============================================================
RogueResetRunState::
	; --- 1. events ---
	ResetEventRange RUN_EVENTS_START, RUN_EVENTS_END

	; --- 2. blanket-clear the run-progress region (same range/routine as
	; true new game) ---
	ld hl, wGameProgressFlags
	ld bc, wGameProgressFlagsEnd - wGameProgressFlags
	call FillMemory

	; --- 3. re-derive the SRAM-tier caches step 2 just zeroed ---
	farcall ApplyKeyItemTierEffects
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a       ; select bank 1 explicitly; ambient bank is unreliable
	; Dice charges: DOOR_DICE/MON_DICE/ITEM_DICE each refill to 1+tier,
	; packed 2 bits each into wDiceCharges (bits 0-1/2-3/4-5). Charges store
	; REMAINING, unlike wRogueFlagsBitfield2's slot-pull bits below (those
	; store USED) - a fresh/new-game byte reading 0 correctly means "own no
	; dice yet". Read tiers directly from sKeyItemTiers while SRAM is already
	; enabled, rather than three farcalls to GetKeyItemPower.
	ld a, [sKeyItemTiers + 2]
	and %11000000                 ; DOOR_DICE is key item index 11 -> bits 6-7
	swap a
	srl a
	srl a                         ; a = tier (0-3)
	inc a                         ; a = charges (1-3), into bits 0-1
	ld b, a

	ld a, [sKeyItemTiers + 3]
	ld c, a                       ; keep byte 3 around for ITEM_DICE below
	and %00000011                 ; MON_DICE is key item index 12 -> bits 0-1
	inc a                         ; charges (1-3)
	sla a
	sla a                         ; shift into bits 2-3
	or b
	ld b, a

	ld a, c
	and %00001100                 ; ITEM_DICE is key item index 13 -> bits 2-3
	srl a
	srl a                         ; a = tier (0-3)
	inc a                         ; a = charges (1-3)
	swap a                        ; shift into bits 4-5
	or b
	ld [wDiceCharges], a
	xor a
	ld [rRAMG], a                 ; leave SRAM disabled, never on a farcall boundary

	; --- 4. badges, item pockets, money, coins (matches InitPlayerData) ---
	; wObtainedBadges is flag_array NUM_BADGES (8 badges -> exactly 1 byte);
	; a stray +1 write would corrupt wLetterPrintingDelayFlags right after it.
	xor a
	ld [wObtainedBadges], a
	ld hl, wRecoveryItemCounts
	ld bc, NUM_RECOVERY_ITEMS + NUM_STAT_ITEMS + NUM_VALUABLE_ITEMS
.clearItemCounts
	ld [hli], a
	dec bc
	ld a, b
	or c
	ld a, 0
	jr nz, .clearItemCounts
	; TM Pack pocket: wTMPocketBuf is just a scratch UI display list rebuilt
	; from sTMBitfield every time the bag opens (BuildTMPocketList), not the
	; real ownership data - clearing it would do nothing. sTMBitfield (SRAM)
	; is the actual TM/HM ownership bitfield; ClearTMBitfield already exists
	; and is used for exactly this at true new game (init_player_data.asm),
	; same bank as this routine so no farcall needed.
	call ClearTMBitfield
	DEF ROGUE_RESET_START_MONEY EQU $3000  ; matches init_player_data.asm's START_MONEY
	ld hl, wPlayerMoney + 1
	ld a, HIGH(ROGUE_RESET_START_MONEY)
	ld [hld], a
	xor a ; LOW(ROGUE_RESET_START_MONEY)
	ld [hli], a
	inc hl
	ld [hl], a
	xor a
	ld hl, wPlayerCoins
	ld [hli], a
	ld [hl], a

	; --- 5. party, boxes, daycare, starters ---
	xor a
	ld [wPartyCount], a
	ld a, -1
	ld [wPartySpecies], a
	xor a
	ld [wBoxCount], a
	ld a, -1
	ld [wBoxSpecies], a
	farcall EmptyAllSRAMBoxes       ; the other 11 SRAM boxes + their checksums
	xor a
	ld [wDayCareInUse], a
	ld [wDayCareInUse2], a
	ld [wPlayerStarter], a
	ld [wRivalStarter], a
	ld [wRivalStarterBallSpriteIndex], a
	ret

; ============================================================
; RogueOnBlackout — farcalled from ResetStatusAndHalveMoneyOnBlackout.
; A blackout ends the run; everything run-scoped is cleared in one place.
; wRogueFlagsBitfield2 (Credit Exchange slot pulls used) is inside
; wGameProgressFlags, so RogueResetRunState's blanket clear already resets it
; - no separate handling needed here any more.
; ============================================================
RogueOnBlackout::
	jp RogueResetRunState
