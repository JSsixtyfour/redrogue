_AddPartyMon::
; Adds a new mon to the player's or enemy's party.
; [wMonDataLocation] is used in an unusual way in this function.
; If the lower nybble is 0, the mon is added to the player's party, else the enemy's.
; If the entire value is 0, then the player is allowed to name the mon.
	ld de, wPartyCount
	ld a, [wMonDataLocation]
	and $f
	jr z, .next
	ld de, wEnemyPartyCount
.next
	ld a, [de]
	inc a
	cp PARTY_LENGTH + 1
	ret nc ; return if the party is already full
	ld [de], a
	ld a, [de]
	ldh [hNewPartyLength], a
	add e
	ld e, a
	jr nc, .noCarry
	inc d
.noCarry
	ld a, [wCurPartySpecies]
	ld [de], a ; write species of new mon in party list
	inc de
	ld a, $ff ; terminator
	ld [de], a
	ld hl, wPartyMonOT
	ld a, [wMonDataLocation]
	and $f
	jr z, .next2
	ld hl, wEnemyMonOT
.next2
	ldh a, [hNewPartyLength]
	dec a
	call SkipFixedLengthTextEntries
	ld d, h
	ld e, l
	ld hl, wPlayerName
	ld bc, NAME_LENGTH
	call CopyData
	ld a, [wMonDataLocation]
	and a
	jr nz, .skipNaming
	ld hl, wPartyMonNicks
	ldh a, [hNewPartyLength]
	dec a
	call SkipFixedLengthTextEntries
	ld a, NAME_MON_SCREEN
	ld [wNamingScreenType], a
	predef AskName
.skipNaming
	ld hl, wPartyMons
	ld a, [wMonDataLocation]
	and $f
	jr z, .next3
	ld hl, wEnemyMons
.next3
	ldh a, [hNewPartyLength]
	dec a
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld e, l
	ld d, h
	push hl
	ld a, [wCurPartySpecies]
	ld [wCurSpecies], a
	call GetMonHeader
	ld hl, wMonHeader
	ld a, [hli]
	ld [de], a ; species
	inc de
	pop hl
	push hl
	ld a, [wMonDataLocation]
	and $f
	ld a, ATKDEFDV_TRAINER  ; set enemy trainer mon IVs to fixed average values
	ld b, SPDSPCDV_TRAINER
	jr nz, .next4

; If the mon is being added to the player's party, update the pokedex.
	ld a, [wCurPartySpecies]
	ld [wPokedexNum], a
	push de
	predef IndexToPokedex
	pop de
	ld a, [wPokedexNum]
	dec a
	ld c, a
	ld b, FLAG_TEST
	ld hl, wPokedexOwned
	call FlagAction
	ld a, c ; whether the mon was already flagged as owned
	ld a, [wPokedexNum]
	dec a
	ld c, a
	ld b, FLAG_SET
	push bc
	call FlagAction
	pop bc
	ld hl, wPokedexSeen
	call FlagAction

	pop hl
	push hl

	ldh a, [hIsInBattle]
	and a ; is this a wild mon caught in battle?
	jr nz, .copyEnemyMonData

; Not wild.
	call Random ; generate random IVs
	ld b, a
	call Random

; DV BOOSTER: floor each of the four DV nibbles (Atk/Def packed into this
; second roll's byte, Spd/Spc into the first) at a per-tier minimum, before
; they're written to MON_DVS below. hl/de are live mon-struct pointers used
; further down and must survive the farcall; the two rolls travel the same
; way, stashed in bc (b=first roll, c=second roll) - see
; KEY_ITEM_EFFECTS_PLAN_PC.md §3d for why ATK's nibble is floored too (a
; gender-display landmine, not live in this project today).
	ld c, a                        ; c = second roll (-> MON_DVS byte0: Atk/Def)
	push hl
	push de
	push bc
	ld a, DV_BOOSTER
	ld [wCurItem], a
	farcall GetKeyItemPower        ; a = 0 (not active) or 1-3 (displayed tier)
	pop bc
	pop de
	pop hl
	and a
	jr z, .noDVBoost
	dec a
	push hl
	ld hl, .DVFloorTable
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]                     ; a = floor (6/10/13)
	pop hl
	ld e, a                        ; e = floor value, held here across both calls below
	ld a, b                        ; a = first roll (-> MON_DVS byte1: Spd/Spc)
	call .ApplyDVFloor
	ld b, a
	ld a, c
	call .ApplyDVFloor
	ld c, a
.noDVBoost
	ld a, c                        ; a = (possibly floored) second roll

.next4
	push bc
	ld bc, MON_DVS
	add hl, bc
	pop bc
	ld [hli], a
	ld [hl], b         ; write IVs
	ld bc, (MON_HP_EXP - 1) - (MON_DVS + 1)
	add hl, bc
	ld a, 1
	ld c, a
	xor a
	ld b, a
	call CalcStat      ; calc HP stat (set cur Hp to max HP)
	ldh a, [hMultiplicand+1]
	ld [de], a
	inc de
	ldh a, [hMultiplicand+2]
	ld [de], a
	inc de
	xor a
	ld [de], a         ; box level
	inc de
	ld [de], a         ; status ailments
	inc de
	jr .copyMonTypesAndMoves
.copyEnemyMonData
	ld bc, MON_DVS
	add hl, bc
	ld a, [wEnemyMonDVs] ; copy IVs from cur enemy mon
	ld [hli], a
	ld a, [wEnemyMonDVs + 1]
	ld [hl], a
	ld a, [wEnemyMonHP]    ; copy HP from cur enemy mon
	ld [de], a
	inc de
	ld a, [wEnemyMonHP+1]
	ld [de], a
	inc de
	xor a
	ld [de], a                ; box level
	inc de
	ld a, [wEnemyMonStatus]   ; copy status ailments from cur enemy mon
	ld [de], a
	inc de
.copyMonTypesAndMoves
	ld hl, wMonHTypes
	ld a, [hli]       ; type 1
	ld [de], a
	inc de
	ld a, [hli]       ; type 2
	ld [de], a
	inc de
	ld a, [hli]       ; catch rate (held item in gen 2)
; This byte is otherwise dead once a mon is owned (nothing reads a stored
; mon's own catch rate - only a live enemy's, via wEnemyMonActualCatchRate,
; which is loaded separately in battle core and never touches this copy).
; Bits 0-3 are repurposed as flags: ghost variant (func_ghost_variant.asm),
; fusion (func_fusion.asm), type variant, special form (func_special_form.asm).
; Zero the WHOLE byte (not just the used bits) - species catch rates occupy
; both nibbles (e.g. Bulbasaur=45=$2D has bit0 set; Pikachu=190=$BE has bits
; 4-7 set), so anything less than a full clear risks a species spawning
; pre-flagged by coincidence. This also future-proofs bits 4-7 for the next
; flag added to this byte - see MON_CATCH_RATE_BITFIELD_PC.md.

; SHINY CHARM: roll a shiny flag for this newly created mon (bit 4 of this
; same repurposed byte - see func_shiny.asm). Base rate is 1/256 even with
; no charm owned; owning one only widens the threshold via GetKeyItemPower.
; de is the live struct write cursor used immediately below and must
; survive the farcall - see KEY_ITEM_EFFECTS_PLAN_PC.md §3a.
	push de
	ld a, SHINY_CHARM
	ld [wCurItem], a
	farcall GetKeyItemPower        ; a = 0 (not active) or 1-3 (displayed tier)
	ld hl, .ShinyThresholdTable
	ld e, a
	ld d, 0
	add hl, de
	ld d, [hl]                     ; d = threshold (1/2/4/8); Random preserves de
	call Random                    ; a = fresh roll
	cp d
	pop de                         ; de = struct write cursor, restored
	jr c, .isShiny                 ; carry set = roll < threshold
	xor a
	jr .writeShinyFlag
.isShiny
	ld a, 1 << BIT_SHINY
.writeShinyFlag
	ld [de], a
	ld hl, wMonHMoves
	ld a, [hli]
	inc de
	push de
	ld [de], a
	ld a, [hli]
	inc de
	ld [de], a
	ld a, [hli]
	inc de
	ld [de], a
	ld a, [hli]
	inc de
	ld [de], a
	push de
	dec de
	dec de
	dec de
	xor a
	ld [wLearningMovesFromDayCare], a
	predef WriteMonMoves
	pop de
	ld a, [wPlayerID]  ; set trainer ID to player ID
	inc de
	ld [de], a
	ld a, [wPlayerID + 1]
	inc de
	ld [de], a
	push de
	ld a, [wCurEnemyLevel]
	ld d, a
	callfar CalcExperience
	pop de
	inc de
	ldh a, [hExperience] ; write experience
	ld [de], a
	inc de
	ldh a, [hExperience + 1]
	ld [de], a
	inc de
	ldh a, [hExperience + 2]
	ld [de], a
	xor a
	ld b, NUM_STATS * 2
.writeEVsLoop              ; set all EVs to 0
	inc de
	ld [de], a
	dec b
	jr nz, .writeEVsLoop
	inc de
	inc de
	pop hl
	call AddPartyMon_WriteMovePP
	inc de
	ld a, [wCurEnemyLevel]
	ld [de], a
	inc de
	ldh a, [hIsInBattle]
	dec a
	jr nz, .calcFreshStats
	ld hl, wEnemyMonMaxHP
	ld bc, NUM_STATS * 2
	call CopyData          ; copy stats of cur enemy mon
	pop hl
	jr .done
.calcFreshStats
	pop hl
	ld bc, MON_HP_EXP - 1
	add hl, bc
	ld b, $0
	call CalcStats         ; calculate fresh set of stats
.done
	scf
	ret

.ShinyThresholdTable:
; SHINY CHARM (see KEY_ITEM_EFFECTS_PLAN_PC.md §3a). Index 0 is the base
; rate with no charm owned; GetKeyItemPower's 1-3 (displayed tier) select
; entries 1-3.
	db 1, 2, 4, 8

; ============================================================
; ApplyDVFloor — DV BOOSTER helper (see KEY_ITEM_EFFECTS_PLAN_PC.md §3d).
; INPUT:  a = byte holding two packed 4-bit DVs, e = floor value (0-15)
; OUTPUT: a = same byte with both nibbles raised to at least e
; CLOBBERS: d (b/c/e untouched, so this is safe to call twice in a row with
; the same floor still sitting in e)
; ============================================================
.ApplyDVFloor:
	push af
	and $0f
	cp e
	jr nc, .lowOk
	ld a, e
.lowOk
	ld d, a                        ; d = floored low nibble
	pop af
	swap a
	and $0f
	cp e
	jr nc, .highOk
	ld a, e
.highOk
	swap a
	or d
	ret

.DVFloorTable:
	db 6, 10, 13

LoadMovePPs:
	call GetPredefRegisters
	; fallthrough
AddPartyMon_WriteMovePP:
	ld b, NUM_MOVES
.pploop
	ld a, [hli]     ; read move ID
	and a
	jr z, .empty
	dec a
	push hl
	push de
	push bc
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld de, wMoveData
	ld a, BANK(Moves)
	call FarCopyData
	pop bc
	pop de
	pop hl
	ld a, [wMoveData + MOVE_PP]
.empty
	inc de
	ld [de], a
	dec b
	jr nz, .pploop ; there are still moves to read
	ret

; adds enemy mon [wCurPartySpecies] (at position [hWhichPokemon] in enemy list) to own party
; used in the cable club trade center
_AddEnemyMonToPlayerParty::
	ld hl, wPartyCount
	ld a, [hl]
	cp PARTY_LENGTH
	scf
	ret z            ; party full, return failure
	inc a
	ld [hl], a       ; add 1 to party members
	ld c, a
	ld b, $0
	add hl, bc
	ld a, [wCurPartySpecies]
	ld [hli], a      ; add mon as last list entry
	ld [hl], $ff     ; write new sentinel
	ld hl, wPartyMons
	ld a, [wPartyCount]
	dec a
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld e, l
	ld d, h
	ld hl, wLoadedMon
	call CopyData    ; write new mon's data (from wLoadedMon)
	ld hl, wPartyMonOT
	ld a, [wPartyCount]
	dec a
	call SkipFixedLengthTextEntries
	ld d, h
	ld e, l
	ld hl, wEnemyMonOT
	ldh a, [hWhichPokemon]
	call SkipFixedLengthTextEntries
	ld bc, NAME_LENGTH
	call CopyData    ; write new mon's OT name (from an enemy mon)
	ld hl, wPartyMonNicks
	ld a, [wPartyCount]
	dec a
	call SkipFixedLengthTextEntries
	ld d, h
	ld e, l
	ld hl, wEnemyMonNicks
	ldh a, [hWhichPokemon]
	call SkipFixedLengthTextEntries
	ld bc, NAME_LENGTH
	call CopyData    ; write new mon's nickname (from an enemy mon)
	ld a, [wCurPartySpecies]
	ld [wPokedexNum], a
	predef IndexToPokedex
	ld a, [wPokedexNum]
	dec a
	ld c, a
	ld b, FLAG_SET
	ld hl, wPokedexOwned
	push bc
	call FlagAction ; add to owned pokemon
	pop bc
	ld hl, wPokedexSeen
	call FlagAction ; add to seen pokemon
	and a
	ret                  ; return success

_MoveMon::
	ld a, [wMoveMonType]
	and a   ; BOX_TO_PARTY
	jr z, .checkPartyMonSlots
	cp DAYCARE_TO_PARTY
	jr z, .checkPartyMonSlots
    cp DAYCARE_TO_PARTY2
	jr z, .checkPartyMonSlots
	cp PARTY_TO_DAYCARE
	ld hl, wDayCareMon
	jr z, .findMonDataSrc
    cp PARTY_TO_DAYCARE2
	ld hl, wDayCareMon2
	jr z, .findMonDataSrc
	; else it's PARTY_TO_BOX
	ld hl, wBoxCount
	ld a, [hl]
	cp MONS_PER_BOX
	jr nz, .partyOrBoxNotFull
	jr .boxFull
.checkPartyMonSlots
	ld hl, wPartyCount
	ld a, [hl]
	cp PARTY_LENGTH
	jr nz, .partyOrBoxNotFull
.boxFull
	scf
	ret
.partyOrBoxNotFull
	inc a
	ld [hl], a           ; increment number of mons in party/box
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [wMoveMonType]
	cp DAYCARE_TO_PARTY
	ld a, [wDayCareMon]
	jr z, .copySpecies
    cp DAYCARE_TO_PARTY2
	ld a, [wDayCareMon2]
	jr z, .copySpecies
	ld a, [wCurPartySpecies]
.copySpecies
	ld [hli], a          ; write new mon ID
	ld [hl], $ff         ; write new sentinel
; find mon data dest
	ld a, [wMoveMonType]
	dec a
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	ld a, [wPartyCount]
	jr nz, .addMonOffset
	; if it's PARTY_TO_BOX
	ld hl, wBoxMons
	ld bc, BOXMON_STRUCT_LENGTH
	ld a, [wBoxCount]
.addMonOffset
	dec a
	call AddNTimes
.findMonDataSrc
	push hl
	ld e, l
	ld d, h
	ld a, [wMoveMonType]
	and a
	ld hl, wBoxMons
	ld bc, BOXMON_STRUCT_LENGTH
	jr z, .addMonOffset2
	cp DAYCARE_TO_PARTY
	ld hl, wDayCareMon
	jr z, .copyMonData
    cp DAYCARE_TO_PARTY2
	ld hl, wDayCareMon2
	jr z, .copyMonData
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
.addMonOffset2
	ldh a, [hWhichPokemon]
	call AddNTimes
.copyMonData
	push hl
	push de
	ld bc, BOXMON_STRUCT_LENGTH
	call CopyData
	pop de
	pop hl
	ld a, [wMoveMonType]
	and a ; BOX_TO_PARTY
	jr z, .findOTdest
	cp DAYCARE_TO_PARTY
	jr z, .findOTdest
    cp DAYCARE_TO_PARTY2
	jr z, .findOTdest
	ld bc, BOXMON_STRUCT_LENGTH
	add hl, bc
	ld a, [hl] ; hl = Level
	inc de
	inc de
	inc de
	ld [de], a ; de = BoxLevel
.findOTdest
	ld a, [wMoveMonType]
	cp PARTY_TO_DAYCARE
	ld de, wDayCareMonOT
	jr z, .findOTsrc
    cp PARTY_TO_DAYCARE2
	ld de, wDayCareMonOT2
	jr z, .findOTsrc
	dec a
	ld hl, wPartyMonOT
	ld a, [wPartyCount]
	jr nz, .addOToffset
	ld hl, wBoxMonOT
	ld a, [wBoxCount]
.addOToffset
	dec a
	call SkipFixedLengthTextEntries
	ld d, h
	ld e, l
.findOTsrc
	ld hl, wBoxMonOT
	ld a, [wMoveMonType]
	and a
	jr z, .addOToffset2
	ld hl, wDayCareMonOT
	cp DAYCARE_TO_PARTY
	jr z, .copyOT
    ld hl, wDayCareMonOT2
	cp DAYCARE_TO_PARTY2
	jr z, .copyOT
	ld hl, wPartyMonOT
.addOToffset2
	ldh a, [hWhichPokemon]
	call SkipFixedLengthTextEntries
.copyOT
	ld bc, NAME_LENGTH
	call CopyData
	ld a, [wMoveMonType]
; find nick dest
	cp PARTY_TO_DAYCARE
	ld de, wDayCareMonName
	jr z, .findNickSrc
    cp PARTY_TO_DAYCARE2
	ld de, wDayCareMonName2
	jr z, .findNickSrc
	dec a
	ld hl, wPartyMonNicks
	ld a, [wPartyCount]
	jr nz, .addNickOffset
	ld hl, wBoxMonNicks
	ld a, [wBoxCount]
.addNickOffset
	dec a
	call SkipFixedLengthTextEntries
	ld d, h
	ld e, l
.findNickSrc
	ld hl, wBoxMonNicks
	ld a, [wMoveMonType]
	and a
	jr z, .addNickOffset2
	ld hl, wDayCareMonName
	cp DAYCARE_TO_PARTY
	jr z, .copyNick
    ld hl, wDayCareMonName2
	cp DAYCARE_TO_PARTY2
	jr z, .copyNick
	ld hl, wPartyMonNicks
.addNickOffset2
	ldh a, [hWhichPokemon]
	call SkipFixedLengthTextEntries
.copyNick
	ld bc, NAME_LENGTH
	call CopyData
	pop hl
	ld a, [wMoveMonType]
	cp PARTY_TO_BOX
	jr z, .done
	cp PARTY_TO_DAYCARE
	jr z, .done
    cp PARTY_TO_DAYCARE2
	jr z, .done
	; returning mon to party, compute level and stats
	push hl
	srl a
	add $2
	ld [wMonDataLocation], a
	call LoadMonData
	farcall CalcLevelFromExperience
	ld a, d
	ld [wCurEnemyLevel], a
	pop hl
	ld bc, BOXMON_STRUCT_LENGTH
	add hl, bc ; hl = wPartyMon*Level
	ld [hli], a
	ld d, h
	ld e, l
	ld bc, (MON_HP_EXP - 1) - MON_STATS
	add hl, bc ; hl = wPartyMon*HPExp - 1
	ld b, $1
	; Fusion (Phase 2): withdrawing a fused mon from the box recomputes and
	; stores its stats - re-arm the max-base sentinel so the bonus survives the
	; round-trip. de = MON_STATS (MON_LEVEL+1, just written above) here.
	push bc
	push hl
	farcall PrepareFusionCalcStats
	pop hl
	pop bc
	call CalcStats
.done
	and a
	ret
