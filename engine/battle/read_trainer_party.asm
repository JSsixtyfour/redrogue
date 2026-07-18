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
	ld [wCurEnemyLevel], a
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
	jr nz, .LastLoop ; repeat wCurEnemyLevel times
	ret

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
	; Fill the remaining slots up to THIS ROUND's team size (matches the normal
	; 5th route trainer count), not a fixed count - so the boss scales. No count
	; byte follows MINIBOSS_RANDOM_FILL in the data; the next byte is the 0
	; terminator.
	farcall MiniBossTeamSize   ; a = team size for this round
	ld b, a
.fillLoop
	ld a, [wEnemyPartyCount]
	cp b
	jr nc, .loop               ; already at/over team size -> resume (next byte = terminator)
	push de
	push bc
	farcall MiniBossRollFillMon ; sets wCurPartySpecies (rarer-random) AND wCurEnemyLevel
	call MiniBossAddMon
	pop bc
	pop de
	jr .fillLoop

; Appends the mon in wCurPartySpecies at wCurEnemyLevel to the enemy party.
; No party-full guard here: the .fill loop caps at the round's team size (<= 6)
; and curated/starter counts are bounded by the authored data, so the party
; never exceeds PARTY_LENGTH (same trust model as ReadTrainer's normal loop).
MiniBossAddMon:
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
	jp AddPartyMon
