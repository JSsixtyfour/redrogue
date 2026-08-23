ReadTrainer:

; don't change any moves in a link battle
	;ld a, [wLinkState]
	;and a
	;ret nz

; set [wEnemyPartyCount] to 0, [wEnemyPartySpecies] to FF
; XXX first is total enemy pokemon?
; XXX second is species of first pokemon?
	ld hl, wEnemyPartyCount
	xor a
	ld [hli], a
	dec a
	ld [hl], a

; get the pointer to trainer data for this class
	ld a, [wTrainerClass] ; get trainer class
	dec a
	add a
	ld hl, TrainerDataPointers
	ld c, a
	ld b, 0
	add hl, bc ; hl points to trainer class
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, [wTrainerNo]
	ld b, a
; At this point b contains the trainer number,
; and hl points to the trainer class.
; Our next task is to iterate through the trainers,
; decrementing b each time, until we get to the right one.
.CheckNextTrainer
	dec b
	jr z, .IterateTrainer
.SkipTrainer
	ld a, [hli]
	and a
	jr nz, .SkipTrainer
	jr .CheckNextTrainer

; if the first byte of trainer data is FF,
; - each pokemon has a specific level
;      (as opposed to the whole team being of the same level)
; - if [wLoneAttackNo] != 0, one pokemon on the team has a special move
; else the first byte is the level of every pokemon on the team
.IterateTrainer
	; Mini-boss classes use their own team format + runtime level scaling
	; (BuildMiniBossTeam, below). hl already points at the selected team's data.
	; Same bank, so a plain call keeps hl valid (unlike the rogue-bank farcalls).
	ld a, [wTrainerClass]
	cp RIVAL_MINIBOSS
	jr z, .miniBoss
	cp GIOVANNI_MINIBOSS
	jr z, .miniBoss
	ld a, [hli]
	cp $FF ; is the trainer special?
	jr z, .SpecialTrainer ; if so, check for special moves
    farcall GetRandRoster
    jp z, .AddAdditionalMoveData
.LoopTrainerData
	ld a, [hli]
	and a ; have we reached the end of the trainer data?
	jp z, .AddAdditionalMoveData
	ld [wCurPartySpecies], a
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
	push hl
	call AddPartyMon
	pop hl
	jr .LoopTrainerData
.SpecialTrainer
; if this code is being run:
; - each pokemon has a specific level
;      (as opposed to the whole team being of the same level)
; - if [wLoneAttackNo] != 0, one pokemon on the team has a special move
	ld a, [hli]
	and a ; have we reached the end of the trainer data?
	jr z, .AddAdditionalMoveData
	ld [wCurEnemyLevel], a
	push hl
	farcall RogueApplyTrainerLevelModifiers
	pop hl
	ld a, [hli]
	ld [wCurPartySpecies], a
	push hl
	farcall PatchRivalStarterSpecies
	pop hl
	ld e, [hl]                ; peek terminator byte (0 => this mon is the team's ace/last)
	push hl
	farcall PatchLegendaryBossSpecies ; Challenge 11: substitute legendary for the ace
	pop hl
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
	push hl
	call AddPartyMon
	farcall ApplyLegendaryBossMoveset ; Challenge 11: themed moveset on the just-added legendary
	pop hl
	jr .SpecialTrainer
.miniBoss
	; Mini-boss classes support BOTH team formats, for flexibility:
	;  - leading $FF -> the vanilla per-mon-level format (fixed levels, like a
	;    gym team). Author an 8-tier x 3-team Giovanni here, identical to his
	;    gym, and it just works - fall through to the normal special path.
	;  - otherwise -> the runtime-level-scaled mini-boss format (BuildMiniBossTeam).
	ld a, [hl]
	cp $FF
	jr nz, .miniBossCustom
	inc hl                 ; consume the $FF marker (matches the normal path)
	jp .SpecialTrainer
.miniBossCustom
	call BuildMiniBossTeam ; hl -> mini-boss team data (same bank; builds the enemy party)
	jp .AddAdditionalMoveData
.AddAdditionalMoveData
; does the trainer have additional move data?
	ld a, [wTrainerClass]
	ld b, a
	ld a, [wTrainerNo]
	ld c, a
	ld hl, SpecialTrainerMoves
.loopAdditionalMoveData
	ld a, [hli]
	cp $ff
	jr z, .FinishUp
	cp b
	jr nz, .loopSkipTrainer
	ld a, [hli]
	cp c
	jr nz, .loopSkipTrainer
	ld d, h
	ld e, l
.writeAdditionalMoveDataLoop
	ld a, [de]
	inc de
	and a
	jp z, .FinishUp
	dec a
	ld hl, wEnemyMon1Moves
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld a, [de]
	inc de
	dec a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [de]
	inc de
	ld [hl], a
	; new: give the substituted move its own max PP
	push de
	push hl
	dec a
	ld hl, Moves + 5      ; +5 = the PP field within a move entry
	ld bc, MOVE_LENGTH
	call AddNTimes        ; hl -> PP byte for this move
	ld a, [hl]
	pop hl                ; hl -> the move byte just written
	ld bc, MON_PP - MON_MOVES
	add hl, bc            ; hl -> matching PP byte in the enemy mon struct
	ld [hl], a
	pop de
	jr .writeAdditionalMoveDataLoop
.loopSkipTrainer
	ld a, [hli]
	and a
	jr nz, .loopSkipTrainer
	jr .loopAdditionalMoveData
.FinishUp
; clear wAmountMoneyWon addresses
	xor a
	ld de, wAmountMoneyWon
	ld [de], a
	inc de
	ld [de], a
	inc de
	ld [de], a
	ld a, [wCurEnemyLevel]
	ld b, a

; AMULET COIN: inflate the BCD-add loop count below by the key item's tier
; percentage. Money is base x level (b iterations of the same BCD add), so
; extra iterations are extra money with no BCD arithmetic of our own - see
; KEY_ITEM_EFFECTS_PLAN_PC.md.
;
; Register care needed here: Multiply's wrapper (home/math.asm) does NOT
; preserve de (only Divide's does), and de is live below as the accumulator
; write cursor .LastLoop's AddBCDPredef uses - so de is pushed across the
; whole block. c is loaded with a redundant copy of the level: Divide needs
; b set to 2 (its byte-count input), and its wrapper preserves bc as a PAIR
; at call time, so b comes back as 2, not the level, without a copy saved
; somewhere else first. farcall also clobbers b, hence the copy is taken
; before it, not after.
	push de
	ld c, b                        ; c = level, safe across the b=2 clobber below
	push bc
	ld a, AMULET_COIN
	ld [wCurItem], a
	farcall GetKeyItemPower        ; a = 0 (not active) or 1-3 (displayed tier)
	pop bc
	and a
	jr z, .noAmuletCoin
	dec a
	ld hl, .AmuletCoinPctTable
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]                     ; a = percent bonus (10/15/20)
	ldh [hMultiplier], a
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand + 1], a
	ld a, b
	ldh [hMultiplicand + 2], a
	call Multiply                  ; level * pct always fits in 16 bits
	                                ; (max 100*20=2000), so hProduct+2/+3 hold it
	ldh a, [hProduct + 2]
	ldh [hDividend], a
	ldh a, [hProduct + 3]
	ldh [hDividend + 1], a
	ld a, 100
	ldh [hDivisor], a
	ld b, 2
	call Divide
	ldh a, [hQuotient + 3]         ; a = extra loop iterations
	add c                          ; c = original level, saved above
	ld b, a                        ; b = level + extra, still fits a byte (max 120)
.noAmuletCoin
	pop de

.LastLoop
; update wAmountMoneyWon addresses (money to win) based on enemy's level
	ld hl, wTrainerBaseMoney + 2
	ld c, 3 ; wAmountMoneyWon is a 3-byte number
	push bc
	predef AddBCDPredef
	pop bc
	inc de
	inc de
    inc de ; increment de one more time to prevent the previous memory address (wEscapedFromBattle) from being affected
	dec b
	jr nz, .LastLoop ; repeat wCurEnemyLevel (+ AMULET COIN bonus) times
	ret

.AmuletCoinPctTable:
	db 10, 15, 20

; ============================================================
; Mini-boss team builder (see MINIBOSS_FRAMEWORK.md)
; Only the team-data walk lives here (same bank as the party data, so hl/de
; reads are plain). The bulky level/fill/table logic lives in the rogue bank
; (func_enc_gen.asm: MiniBossSetLevel / MiniBossRollFillMon) and is reached by
; farcall - those helpers take no pointer input (they read wBattleCount and
; write wCurEnemyLevel/wCurPartySpecies), so they're bank-safe.
;
; INPUT: hl -> the selected team's data (RivalMiniBossData / GiovanniMiniBossData
;        format: a 0-terminated list of species/markers, no leading $FF, no
;        per-mon level bytes). Every mon's level is supplied at runtime from
;        trainer_difficulty_settings_miniboss[round].
; ============================================================
BuildMiniBossTeam::
	ld d, h
	ld e, l                    ; de = team data pointer (survives the farcalls below)
.loop
	ld a, [de]
	inc de
	and a
	ret z                      ; 0 terminator = team complete
	cp MINIBOSS_RANDOM_FILL
	jr z, .fill
	cp RIVAL_STARTER_PLACEHOLDER
	jr z, .starter
	; literal curated "signature" species
	ld [wCurPartySpecies], a
	push de
	farcall MiniBossSetLevel   ; wCurEnemyLevel = this round's level
	call MiniBossAddMon
	pop de
	jr .loop
.starter
	ld [wCurPartySpecies], a    ; a = RIVAL_STARTER_PLACEHOLDER (from .loop above)
	push de
	farcall MiniBossSetLevel
	farcall PatchRivalStarterSpecies ; swap in wRivalStarter, evolved to wCurEnemyLevel
	call MiniBossAddMon
	pop de
	jr .loop
.fill
	ld a, [de]                 ; fill count (>= 1)
	inc de
	ld b, a
.fillLoop
	push de
	push bc
	farcall MiniBossRollFillMon ; sets wCurPartySpecies (rarer-random) AND wCurEnemyLevel
	call MiniBossAddMon
	pop bc
	pop de
	dec b
	jr nz, .fillLoop
	jr .loop

; Appends the mon in wCurPartySpecies at wCurEnemyLevel to the enemy party.
; No party-full guard here: the .fill loop caps at the round's team size (<= 6)
; and curated/starter counts are bounded by the authored data, so the party
; never exceeds PARTY_LENGTH (same trust model as ReadTrainer's normal loop).
MiniBossAddMon:
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
	jp AddPartyMon
