GainExperience:
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z ; return if link battle
    
    ;shinpokered feature having to do with the GBC double speed CPU mode
;Running in double speed CPU mode shaves off about 1 second of computation delay
	predef SetCPUSpeed

; STAT BOOSTER: resolve the pass count once per GainExperience call (not per
; mon - every party mon that gains exp this battle is boosted the same way),
; before wPartyMon1/hWhichPokemon below touch any of the registers this
; needs. power (0-3) maps onto passes (1-4) uniformly: 0 = vanilla single
; pass. See KEY_ITEM_EFFECTS_PLAN_PC.md §3e.
	ld a, STAT_BOOSTER
	ld [wCurItem], a
	farcall GetKeyItemPower        ; a = 0 (not active) or 1-3 (displayed tier)
	inc a
	ld [wStatExpPasses], a

	ld hl, wPartyMon1
	xor a
	ldh [hWhichPokemon], a
.partyMonLoop ; loop over each mon and add gained exp
	inc hl
	ld a, [hli]
	or [hl] ; is mon's HP 0?
	jp z, .nextMon ; if so, go to next mon
	push hl
	ld hl, wPartyGainExpFlags
	ldh a, [hWhichPokemon]
	ld c, a
	ld b, FLAG_TEST
	predef FlagActionPredef
	ld a, c
	and a ; is mon's gain exp flag set?
	pop hl
	jp z, .nextMon ; if mon's gain exp flag not set, go to next mon
	ld de, (MON_HP_EXP + 1) - (MON_HP + 1)
	add hl, de
	ld d, h
	ld e, l                        ; de = this mon's stat-exp block base

; STAT BOOSTER: run the whole 5-stat add loop [wStatExpPasses] times.
; Repeated addition keeps the 16-bit saturation logic below untouched rather
; than inline-scaling the add. Each pass resets hl/de to the same starting
; point (de is restored from the stack, discarding that pass's own advance)
; so passes 2+ add the same base stats again rather than reading garbage
; past the block. b (outer pass counter) is saved/restored around the inner
; loop, which freely clobbers b/c as scratch (enemy base stat / stat index).
; After the last pass, de is recomputed to the fully-advanced position a
; single vanilla pass would have left it at - every caller below (starting
; at .statExpDone) expects that, not the base address.
	ld a, [wStatExpPasses]
	ld b, a
.statExpPassLoop
	push bc
	push de
	ld hl, wEnemyMonBaseStats
	ld c, NUM_STATS
.gainStatExpLoop
	ld a, [hli]
	ld b, a ; enemy mon base stat
	ld a, [de] ; stat exp
	add b ; add enemy mon base state to stat exp
	ld [de], a
	jr nc, .nextBaseStat
; if there was a carry, increment the upper byte
	dec de
	ld a, [de]
	inc a
	jr z, .maxStatExp ; jump if the value overflowed
	ld [de], a
	inc de
	jr .nextBaseStat
.maxStatExp ; if the upper byte also overflowed, then we have hit the max stat exp
	ld a, $ff
	ld [de], a
	inc de
	ld [de], a
.nextBaseStat
	dec c
	jr z, .statExpPassDone
	inc de
	inc de
	jr .gainStatExpLoop
.statExpPassDone
	pop de                          ; discard this pass's advance; de = block base again
	pop bc
	dec b
	jr nz, .statExpPassLoop

; A single vanilla pass advances de by (NUM_STATS - 1) * 2, NOT NUM_STATS * 2:
; the loop exits through `dec c / jr z` BEFORE the trailing `inc de / inc de`,
; so it steps forward 4 times for 5 stats. de must land on MON_DVS - 1, which
; is what the `ld hl, MON_OTID - (MON_DVS - 1) / add hl, de` below assumes.
; Using NUM_STATS * 2 overshot by 2 and pointed hl at MON_EXP instead of
; MON_OTID, which made every mon read as traded (boosted exp) and then shifted
; the level/max-HP writes 2 bytes down the struct.
	ld hl, (NUM_STATS - 1) * 2
	add hl, de
	ld d, h
	ld e, l                         ; de = fully advanced, as a single pass would leave it

.statExpDone
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand + 1], a
	ld a, [wEnemyMonBaseExp]
	ldh [hMultiplicand + 2], a
	ld a, [wEnemyMonLevel]
	ldh [hMultiplier], a
	call Multiply
	ld a, 7
	ldh [hDivisor], a
	ld b, 4
	call Divide
	ld hl, MON_OTID - (MON_DVS - 1)
	add hl, de
	ld b, [hl] ; wPartyMon*OTID
	inc hl
	ld a, [wPlayerID]
	cp b
	jr nz, .tradedMon
	ld b, [hl]
	ld a, [wPlayerID + 1]
	cp b
	ld a, 0
	jr z, .next
.tradedMon
	call BoostExp ; traded mon exp boost
	ld a, 1
.next
	ld [wGainBoostedExp], a
	ldh a, [hIsInBattle]
	dec a ; is it a trainer battle?
	call nz, BoostExp ; if so, boost exp
	; PRIZE_EXP_BOOST (d): PERMANENT (2026-09-02) - does NOT gate on
	; BIT_WITCH_ACCEPTED. Once earned, applies to every kill for the rest of
	; the run. Rebalanced from a flat 1.5x pass (BoostExp) to +10%, to match
	; its new permanence.
	ld a, [wWitchPrizesEarned]
	and 1 << (PRIZE_EXP_BOOST - 1)
	call nz, WitchBoostExp10Percent
.noWitchExpBoost
	inc hl
	inc hl
	inc hl
; add the gained exp to the party mon's exp
	ld b, [hl]
	ldh a, [hQuotient + 3]
	ld [wExpAmountGained + 1], a
	add b
	ld [hld], a
	ld b, [hl]
	ldh a, [hQuotient + 2]
	ld [wExpAmountGained], a
	adc b
	ld [hl], a
	jr nc, .noCarry
	dec hl
	inc [hl]
	inc hl
.noCarry
; calculate exp for the mon at max level, and cap the exp at that value
	inc hl
	push hl
	ldh a, [hWhichPokemon]
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl]
	ld [wCurSpecies], a
	call GetMonHeader
	ld d, MAX_LEVEL
	callfar CalcExperience ; get max exp
; compare max exp with current exp
	ldh a, [hExperience]
	ld b, a
	ldh a, [hExperience + 1]
	ld c, a
	ldh a, [hExperience + 2]
	ld d, a
	pop hl
	ld a, [hld]
	sub d
	ld a, [hld]
	sbc c
	ld a, [hl]
	sbc b
	jr c, .next2
; the mon's exp is greater than the max exp, so overwrite it with the max exp
	ld a, b
	ld [hli], a
	ld a, c
	ld [hli], a
	ld a, d
	ld [hld], a
	dec hl
.next2
	; wExpAmountGained aliases wStringBuffer, which move learning overwrites.
	; Keep this recipient's amount on the stack until all its UI is finished.
	ld a, [wExpAmountGained]
	ld b, a
	ld a, [wExpAmountGained + 1]
	ld c, a
	push bc
	push hl
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	;ld hl, GainedText
    ld a, [wBoostExpByExpAll] ; get using ExpAll flag
    and a ; check the flag
    jr nz, .skipExpText ; if there's EXP. all, skip showing any text
    ld hl, GainedText ;there's no EXP. all, load the text to show
	call PrintText
.skipExpText
	xor a ; PLAYER_PARTY_DATA
	ld [wMonDataLocation], a
	callfar AnimateEXPBar ; Shin Red import Phase 9.1
	call LoadMonData
	pop hl
	ld bc, MON_LEVEL - MON_EXP
	add hl, bc
	push hl
	farcall CalcLevelFromExperience
	pop hl
	ld a, [hl] ; current level
	cp d
	jp z, .restoreExpAmount ; if level didn't change, finish this recipient
	push hl
	callfar KeepEXPBarFull ; Shin Red import Phase 9.1; hl is live (party mon level ptr)
	pop hl
	ld a, [wCurEnemyLevel]
	push af
	push hl
	ld a, d
	ld [wCurEnemyLevel], a
	ld [hl], a
	ld bc, MON_SPECIES - MON_LEVEL
	add hl, bc
	ld a, [hl]
	ld [wCurSpecies], a
	ld [wPokedexNum], a
	call GetMonHeader
	ld bc, (MON_MAXHP + 1) - MON_SPECIES
	add hl, bc
	push hl
	ld a, [hld]
	ld c, a
	ld b, [hl]
	push bc ; push max HP (from before levelling up)
	ld d, h
	ld e, l
	ld bc, (MON_HP_EXP - 1) - MON_MAXHP
	add hl, bc
	ld b, $1 ; consider stat exp when calculating stats
	; Fusion (Phase 2, dynamic max-base stats): de = MON_STATS (= MON_MAXHP)
	; here, exactly what PrepareFusionCalcStats expects. It sets the max-base
	; sentinel (and reloads wMonHeader) if this leveling-up mon is the fusion;
	; _CalcStats auto-clears the sentinel afterward. Preserve hl (exp ptr) and
	; bc (stat-exp flag in b) across the farcall.
	push bc
	push hl
	farcall PrepareFusionCalcStats
	pop hl
	pop bc
	call CalcStats
	pop bc ; pop max HP (from before levelling up)
	pop hl
	ld a, [hld]
	sub c
	ld c, a
	ld a, [hl]
	sbc b
	ld b, a ; bc = difference between old max HP and new max HP after levelling
	ld de, (MON_HP + 1) - MON_MAXHP
	add hl, de
; add to the current HP the amount of max HP gained when levelling
	ld a, [hl] ; wPartyMon*HP + 1
	add c
	ld [hld], a
	ld a, [hl] ; wPartyMon*HP + 1
	adc b
	ld [hl], a ; wPartyMon*HP
	ld a, [wPlayerMonNumber]
	ld b, a
	ldh a, [hWhichPokemon]
	cp b ; is the current mon in battle?
	jr nz, .printGrewLevelText
; current mon is in battle
	ld de, wBattleMonHP
; copy party mon HP to battle mon HP
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
; copy other stats from party mon to battle mon
	ld bc, MON_LEVEL - (MON_HP + 1)
	add hl, bc
	push hl
	ld de, wBattleMonLevel
	ld bc, 1 + NUM_STATS * 2 ; size of stats
	call CopyData
	pop hl
	ld a, [wPlayerBattleStatus3]
	bit TRANSFORMED, a
	jr nz, .recalcStatChanges
; the mon is not transformed, so update the unmodified stats
	ld de, wPlayerMonUnmodifiedLevel
	ld bc, 1 + NUM_STATS * 2
	call CopyData
.recalcStatChanges
	xor a ; battle mon
	ld [wCalculateWhoseStats], a
	callfar CalculateModifiedStats
	callfar ApplyBurnAndParalysisPenaltiesToPlayer
	callfar ApplyEarnedStatBoosts
	callfar DrawPlayerHUDAndHPBar
	callfar PrintEmptyString
	call SaveScreenTilesToBuffer1
.printGrewLevelText
	ld hl, GrewLevelText
	call PrintText
	xor a ; PLAYER_PARTY_DATA
	ld [wMonDataLocation], a
	callfar AnimateEXPBarAgain ; Shin Red import Phase 9.1
	call LoadMonData
	ld d, LEVEL_UP_STATS_BOX
	callfar PrintStatsBox
	call WaitForTextScrollButtonPress
	call LoadScreenTilesFromBuffer1
	xor a ; PLAYER_PARTY_DATA
	ld [wMonDataLocation], a
	ld a, [wCurSpecies]
	ld [wPokedexNum], a
	predef LearnMoveFromLevelUp
	; Fusion (Phase 5b): after the PRIMARY's level-up moves, also learn the
	; SECONDARY species' moves for this level. Forward-only by design: only what
	; is learnable at the level just reached, no retroactive backfill.
	; This is the REAL battle level-up site (the one in evos_moves.asm is the
	; post-EVOLUTION learn, which a fusion never reaches - Phase 3 blocks
	; fusions from evolving). de = party mon struct base is IsFusionMon's input
	; (de, NOT hl - farcall clobbers hl as its own jump vector).
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	farcall IsFusionMon
	jr z, .notFusionLevelUpMoves
	ld a, [wCurPartySpecies]
	push af                          ; save the primary's species
	ld a, [wFusionSecondarySpecies]
	ld [wPokedexNum], a              ; LearnMoveFromLevelUp reads the species here
	xor a
	ld [wMonDataLocation], a         ; PLAYER_PARTY_DATA
	predef LearnMoveFromLevelUp      ; secondary's moves; its own "already knows
	                                 ; this move?" check dedups for free
	pop af                           ; primary species
	ld [wCurPartySpecies], a
	ld [wPokedexNum], a              ; LearnMoveFromLevelUp leaves BOTH holding
	                                 ; the secondary - restore the primary
.notFusionLevelUpMoves
	ld hl, wCanEvolveFlags
	ldh a, [hWhichPokemon]
	ld c, a
	ld b, FLAG_SET
	predef FlagActionPredef
	pop hl
	pop af
	ld [wCurEnemyLevel], a

.restoreExpAmount
	pop bc
	ld a, b
	ld [wExpAmountGained], a
	ld a, c
	ld [wExpAmountGained + 1], a
; Fainted/ineligible slots jump straight to .nextMon without a saved amount.
.nextMon
	ld a, [wPartyCount]
	ld b, a
	ldh a, [hWhichPokemon]
	inc a
	cp b
	jr z, .done
	ldh [hWhichPokemon], a
	ld bc, PARTYMON_STRUCT_LENGTH
	ld hl, wPartyMon1
	call AddNTimes
	jp .partyMonLoop
.done
    ;all done with the main run, so do some finishing-up

	;shinpokered feature having to do with the GBC double speed CPU mode
	predef SingleCPUSpeed
	; show "Party gained X EXP. Points!" once, now that wExpAmountGained is set
	ld a, [wBoostExpByExpAll]
	and a
	jr z, .skipExpAllText
	ld hl, WithExpAllText
	call PrintText
.skipExpAllText
	ld hl, wPartyGainExpFlags
	xor a
	ld [hl], a ; clear gain exp flags
	ld a, [wPlayerMonNumber]
	ld c, a
	ld b, FLAG_SET
	push bc
	predef FlagActionPredef ; set the gain exp flag for the mon that is currently out
	ld hl, wPartyFoughtCurrentEnemyFlags
	xor a
	ld [hl], a
	pop bc
	predef_jump FlagActionPredef ; set the fought current enemy flag for the mon that is currently out

; divide enemy base stats, catch rate, and base exp by the number of mons gaining exp
;DivideExpDataByNumMonsGainingExp:
;	ld a, [wPartyGainExpFlags]
;	ld b, a
;	xor a
;	ld c, $8
;	ld d, $0
;.countSetBitsLoop ; loop to count set bits in wPartyGainExpFlags
;	xor a
;	srl b
;	adc d
;	ld d, a
;	dec c
;	jr nz, .countSetBitsLoop
;	cp $2
;	ret c ; return if only one mon is gaining exp
;	ld [wTempByteValue], a ; store number of mons gaining exp
;	ld hl, wEnemyMonBaseStats
;	ld c, wEnemyMonBaseExp + 1 - wEnemyMonBaseStats
;.divideLoop
;	xor a
;	ldh [hDividend], a
;	ld a, [hl]
;	ldh [hDividend + 1], a
;	ld a, [wTempByteValue]
;	ldh [hDivisor], a
;	ld b, $2
;	call Divide ; divide value by number of mons gaining exp
;	ldh a, [hQuotient + 3]
;	ld [hli], a
;	dec c
;	jr nz, .divideLoop
;	ret

; multiplies exp by 1.5
BoostExp:
	ldh a, [hQuotient + 2]
	ld b, a
	ldh a, [hQuotient + 3]
	ld c, a
	srl b
	rr c
	add c
	ldh [hQuotient + 3], a
	ldh a, [hQuotient + 2]
	adc b
	ldh [hQuotient + 2], a
	jr c, .overflow
	ret
.overflow ; saturate at $ffff instead of wrapping
	ld a, $ff
	ldh [hQuotient + 2], a
	ldh [hQuotient + 3], a
	ret

; ============================================================
; WitchBoostExp10Percent
; Witch prize d (PRIZE_EXP_BOOST), rebalanced 2026-09-02 from a flat 1.5x
; (BoostExp) to +10%, to match its new permanence (see the call site below).
;
; Unlike BoostExp's pure shift (value + value/2, a power-of-two divide), 10%
; needs a real divide. hQuotient aliases hDividend (same UNION, ram/hram.asm),
; so the current EXP total is already sitting in the right place to read as
; the dividend - just clear the two high bytes Divide expects for a 4-byte
; dividend and set the divisor.
; This is a PLAIN BINARY divide (home/math.asm's Divide, not the BCD one the
; witch's money prize uses) - EXP math throughout this routine is binary
; (Multiply/Divide, no `daa`), so the divisor is decimal 10, not BCD $10.
; Divide preserves bc/de/hl (home/math.asm), so nothing needs saving here.
; It shares hDividend/hQuotient's UNION with hMultiplicand/hProduct, which is
; safe: nothing downstream of this call reads those before hQuotient+2/+3 is
; consumed at .noWitchExpBoost's tail.
; ============================================================
WitchBoostExp10Percent:
	ldh a, [hQuotient + 2]
	ld d, a
	ldh a, [hQuotient + 3]
	ld e, a                  ; de = current exp total
	xor a
	ldh [hDividend], a
	ldh [hDividend + 1], a   ; Divide's dividend is 4 bytes; clear the high half
	ld a, 10
	ldh [hDivisor], a
	ld b, 4
	call Divide               ; hQuotient = exp / 10
	ldh a, [hQuotient + 3]
	add e
	ldh [hQuotient + 3], a
	ldh a, [hQuotient + 2]
	adc d
	ldh [hQuotient + 2], a
	jr c, .overflow
	ret
.overflow ; saturate at $ffff instead of wrapping, same as BoostExp
	ld a, $ff
	ldh [hQuotient + 2], a
	ldh [hQuotient + 3], a
	ret

GainedText:
	text_far _GainedText
	text_asm
	ld a, [wBoostExpByExpAll]
	ld hl, WithExpAllText
	and a
	ret nz
	ld hl, ExpPointsText
	ld a, [wGainBoostedExp]
	and a
	ret z
	ld hl, BoostedText
	ret

WithExpAllText:
	text_far _WithExpAllText
	text_asm
	ld hl, ExpPointsText
	ret

BoostedText:
	text_far _BoostedText

ExpPointsText:
	text_far _ExpPointsText
	text_end

GrewLevelText:
	text_far _GrewLevelText
	sound_level_up
	text_end
