;replace random mew encounters with ditto if dex diploma not attained
DisallowWildMew:
	ld a, [wCurPartySpecies]	;get the current pokemon in question
	cp MEW	;is it mew? zet zero flag if true
	ret nz	;if not mew, then return
	;else we have a potential mew encounter on our hands
	;CheckEvent EVENT_90B
	jr z, .replace_mew	;if event 90B is zero, then diploma has not been granted. mew is not allowed.
	;CheckEvent EVENT_8C0
	jr z, .mew_allowed	;mew can appear if not already encountered
.replace_mew
	ld a, DITTO	;load the ditto constant
	ld [wCurPartySpecies], a	;overwrite mew with ditto
	ld [wEnemyMonSpecies2], a
	ret
.mew_allowed
;	;the slot that triggered the mew encounter has it's likelihood of a mew cut in half
;	;idea is to give mew a 0.6% encounter rate (lowest in the game)
;	ld a, [hRandomSub]
;	bit 0, a
;	jr nz, .replace_mew
	;going to encounter mew now
	;SetEvent EVENT_8C0 ;mew has been encountered now
	;ReSetEvent EVENT_8C2 ;turn on mew notification
	ret

	
	

;CheckIfPkmnReal:
;;set the carry if pokemon number in 'a' is found on the list of legit pokemon
;	push hl
;	push de
;	push bc
;	ld hl, ListRealPkmn
;	ld de, $0001
;	call IsInArray
;	pop bc
;	pop de
;	pop hl

;This function loads a random trainer class (value of $01 to $2F)
GetRandTrainer:
.reroll
	call Random
	and $30
	cp $30
	jr z, .reroll
	push bc
	ld b, a
	call Random
	and $0F
	add b
	pop bc
	and a
	jr z, .reroll
	add $C8
	ld [wEngagedTrainerClass], a
	ld a, 1
	ld [wEngagedTrainerSet], a
	ret

;gets a random pokemon and puts its hex ID in register a and wcf91
GetRandMon:
	push hl
	push bc
	; Challenge 6 (INCREASED_RARITY_FOES): bump class by 1 tier (lower b = rarer).
	; b=4=pokeball, b=3=greatball, b=2=ultraball, b=1=masterball. Cap at b=1.
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .noRarityBump
	ld a, [wWitchChallenge]
	cp CHALLENGE_INCREASED_RARITY_FOES
	jr nz, .noRarityBump
	ld a, b
	cp 2
	jr c, .noRarityBump    ; already masterball (b=1), can't go rarer
	dec b
.noRarityBump
    ld a, b
    cp a, $4
    jr z, trainer_pokeball_class_selection
    cp a, $3
    jr z, trainer_greatball_class_selection
    cp a, $2
    jr z, trainer_ultraball_class_selection
    cp a, $1
    jr z, trainer_masterball_class_selection
    
; common

trainer_pokeball_class_selection:
ld hl, pokeball_class
push hl
ld a, pokeball_pokemon_line_amount
push af
jp pokemon_class_selection_trainer

trainer_greatball_class_selection:
ld hl, greatball_class
push hl
ld a, greatball_pokemon_line_amount
push af
jp pokemon_class_selection_trainer

trainer_ultraball_class_selection:
ld hl, ultraball_class
push hl
ld a, ultraball_pokemon_line_amount
push af
jp pokemon_class_selection_trainer

trainer_masterball_class_selection:
ld hl, masterball_class
push hl
ld a, masterball_pokemon_line_amount
push af

pokemon_class_selection_trainer:
call Random                 ; get a random number to determine pokemon
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
pop af                      ; restore line amount to multiply by amount in class
ldh [hMultiplier], a        ; place amount of class in multiplier
call Multiply               ; multiply random number by amount in class
ldh a, [hProduct+2]         ; high byte = floor(random*N/256), always in [0,N-1]
ld c, a
ld b, $0

pop hl                      ; restore base pointer
add hl, bc                  ; add product to get address of pokemon
           
ld a, [hl]                  ; load pokemon from address
ld [wCurPartySpecies], a    ; place pokemon in Current Party Speciies

.done
pop bc
pop hl
RET
	
;generates a randomized 6-party enemy trainer roster
; difficulty ramps up every 10 battles won: within each round of 10,
; wBattleCount mod 10 = 1-4 are the first 4 route trainers, 5 is the final
; (strongest) route trainer, 6-9 are the gym trainers, and 10 is the gym
; leader (handled separately by InitGymBattle, never reaches GetRandRoster).
; wBattleCount/10 (integer) gives the "round" (0-7 for gyms 1-8, 8 for
; Victory Road), matching up with the gym leader's tier for that round.
; route trainers (1-5) use trainer_difficulty_settings, gym trainers (6-9)
; use the separate, higher-level trainer_difficulty_settings_gym table.
GetRandRoster:
	push bc
	push de
    push hl
    ld a, [wBattleCount]	; load how many battles the player has won
    cp 90
    jr c, .noClampRound
    ld a, 89                ; clamp to round 9's settings (Victory Road/Elite Four)
.noClampRound
    ld b, 0                 ; b = round index (0-8)
.getRoundIndex
    cp 10
    jr c, .gotRoundIndex
    sub 10
    inc b
    jr .getRoundIndex
.gotRoundIndex
    ; a = remainder within the round (1-9).
    ; 1-5 = route trainers, 6-9 = gym trainers -> pick the matching table.
    ld hl, trainer_difficulty_settings
    cp 6
    jr c, .pickedTable
    ld hl, trainer_difficulty_settings_gym
.pickedTable
    ; the final trainer of each tier (5 = last route trainer, 9 = last gym
    ; trainer) gets the level bonus and rarer class distribution, signalled
    ; via wRogueFlagsBitfield bit 1 for GetRandRosterLoop
    cp 5
    jr z, .isFinalTrainer
    cp 9
    jr nz, .notFinalTrainer
.isFinalTrainer
    ld a, [wRogueFlagsBitfield]
    set 1, a
    jr .gotFlag
.notFinalTrainer
    ld a, [wRogueFlagsBitfield]
    res 1, a ; clears out the flag for bonus level so a regular trainer doesn't receive it
.gotFlag
    ld [wRogueFlagsBitfield], a

    ld a, b                 ; each settings block is 11 bytes
    ld d, a                 ; d = b
    add a, a                ; *2
    add a, a                ; *4
    add a, a                ; *8
    add a, d                ; *9
    add a, d                ; *10
    add a, d                ; *11
    ld c, a                 ; offset is placed in c
    ld b, 0
    add hl, bc              ; offset it added to pointer to get round
	jp GetRandRosterLoop


GetRandRosterLoop:
	ld c, [hl]   ; load level range
    inc hl      ; move to next byte, minimum level
    ld e, [hl]  ; load minimum level
    inc hl      ; move to next byte, normal class counts start
    ld a, [wRogueFlagsBitfield]
    bit 1, a
    jr z, .overloopSetup
; final route trainer: apply the level bonus and use the rarer class distribution
    inc hl
    inc hl
    inc hl
    inc hl      ; hl = level bonus byte
    ld a, [hl]
    add a, e
    ld e, a
    inc hl      ; hl = final-trainer class counts
.overloopSetup

;.highest_level_set:
	;push bc
	;ld a, d     ; places highest level in a
;    sub a, e    ; subtract minimum level from a
;	ld c, a     ; place difference in c
;.calibrate1	    ; subtract result from the highest party level or make it zero if it underflows
;	ld a, d     ; places highest level in a
;	sub a, c    ; subtract to get lowest level
;    dec c       ; lower c if the result is below 2
;	jr c, .calibrate1 
;	ld e, a	    ; places calibrated level in e
	;pop bc
    ;push bc
	;push de
    ld b, 0x4   ; overarching loop

	.overloop
    ld  a, [hl] ; load number of pokemon/loops
    cp  a, 0
    jr  z, .miniloop    ; overarching class loop
    ld  d, a
    
    .loop
    ; Gambler's Paradise: draw species from the themed pool instead of the
    ; normal rarity-class roll. Level logic below is unchanged.
    ld a, [wTrainerClass]
    cp GAMBLER
    jr nz, .useRandMon
    call GetGamblerMon
    jr .gotMon
.useRandMon
    call GetRandMon
.gotMon
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
    call Rangerandom
	add a, e   ; minimum level added to random number
	ld [wCurEnemyLevel], a  ; place level of pokemon in
	call RogueApplyTrainerLevelModifiers
	; Resolve the selected species against its final trainer level before it is
	; copied into the enemy party. GetRandMon returns the species through
	; wCurPartySpecies, while EvolveMonByLevel expects it in d. Preserve every
	; live roster-loop register: b/d are loop counters, e is the minimum level,
	; and hl points into the difficulty settings.
	; Gambler species must remain unchanged so OverrideGamblerMoves can find the
	; selected species in its fixed themed moveset table below.
	ld a, [wTrainerClass]
	cp GAMBLER
	jr z, .skipEvolution
	push hl
	push bc
	push de
	ld a, [wCurPartySpecies]
	ld d, a
	call ScaleTrainer_evolution
	pop de
	pop bc
	pop hl
.skipEvolution
	;push hl                 ; preserve h1
	call AddPartyMon    ; add the pokemon
    ; Gambler's Paradise: replace the just-added mon's rolled moves with its
    ; fixed themed moveset (and correct PP).
    ld a, [wTrainerClass]
    cp GAMBLER
    call z, OverrideGamblerMoves
	dec d           ; decrease loop/run through pokemon
    jr nz, .loop    ; pokeball class loop

.miniloop
    inc hl          ; next class
    dec b           ; decrease overarching loop
    jr nz, .overloop    ; overarching class loop

;end of loop
	pop de
	pop bc
    pop hl
	xor a	;set the zero flag before returning
	ret

; ============================================================
; GetGamblerMon
; Picks a random species from GamblerMonMovesets into wCurPartySpecies.
; Same bank as this file, so the table is read with a plain [hl].
; Preserves hl/bc/de (GetRandRosterLoop state); clobbers a.
; ============================================================
GetGamblerMon:
	push hl
	push bc
	push de
	ld c, GAMBLER_POOL_SIZE
	call Rangerandom        ; a = [0, GAMBLER_POOL_SIZE-1]
	ld c, a
	add a                   ; a = index*2
	add a                   ; a = index*4
	add c                   ; a = index*5 (stride 5); max 21*5=105, no overflow
	ld c, a
	ld b, 0
	ld hl, GamblerMonMovesets
	add hl, bc
	ld a, [hl]              ; entry byte 0 = species
	ld [wCurPartySpecies], a
	pop de
	pop bc
	pop hl
	ret

; ============================================================
; OverrideGamblerMoves
; Overwrites the last-added enemy mon's 4 moves and their PP with the fixed
; gambler moveset for its species (looked up in GamblerMonMovesets by the
; species still held in wCurPartySpecies). Runs right after AddPartyMon.
; PP must be rewritten because WriteMonMoves set PP for the rolled moves, and
; empty slots (mon didn't know 4 moves yet) would otherwise have 0 PP.
; Preserves hl/bc/de (GetRandRosterLoop state).
; ============================================================
OverrideGamblerMoves:
	push hl
	push bc
	push de
	; find this species' 5-byte entry
	ld a, [wCurPartySpecies]
	ld b, a
	ld hl, GamblerMonMovesets
.findLoop
	ld a, [hl]
	and a
	jr z, .done             ; hit sentinel (species not in table) - bail safely
	cp b
	jr z, .found
	ld a, l
	add 5
	ld l, a
	jr nc, .findLoop
	inc h
	jr .findLoop
.found
	inc hl                  ; hl -> move1 of entry
	; hl(dest) = last enemy mon's MON_MOVES = wEnemyMon1Moves + (count-1)*struct
	push hl
	ld a, [wEnemyPartyCount]
	dec a
	ld hl, wEnemyMon1Moves
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes          ; hl -> this mon's MON_MOVES
	pop de                  ; de -> source moveset (move1)
	ld b, NUM_MOVES
.copyLoop
	ld a, [de]
	ld [hl], a              ; MON_MOVES[slot] = move id
	push bc                 ; save move counter
	push de                 ; save source ptr
	push hl                 ; save dest MON_MOVES[slot]
	; look up this move's base PP (byte 5 of its Moves struct)
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes          ; hl -> move struct (Moves bank)
	ld de, wBuffer
	ld a, BANK(Moves)
	call FarCopyData        ; wBuffer = move struct
	pop hl                  ; hl = MON_MOVES[slot]
	push hl
	ld bc, MON_PP - MON_MOVES
	add hl, bc              ; hl -> MON_PP[slot]
	ld a, [wBuffer + 5]     ; base PP
	ld [hl], a
	pop hl                  ; hl = MON_MOVES[slot]
	pop de                  ; source ptr
	pop bc                  ; move counter
	inc hl                  ; next MON_MOVES slot
	inc de                  ; next source move
	dec b
	jr nz, .copyLoop
.done
	pop de
	pop bc
	pop hl
	ret

; one 7-byte block per round (round = wBattleCount / 10, capped at 8).
; each round's trainers ramp up to just under that round's gym leader tier:
; gym tiers are 8-10, 18-21, 21-24, 29, 37-43, 37-43, 40-47, 42-50
;
; each 11-byte block:
;   0: level range
;   1: minimum level
;   2-5: normal class counts (pokeball, greatball, ultraball, masterball)
;   6: level bonus for the final (5th) route trainer of the round
;      (wBattleCount mod 10 == 5), making it "somewhat stronger"
;   7-10: class counts for that final route trainer - same total as 2-5,
;      but shifted toward rarer classes
trainer_difficulty_settings:
;round 1 (-> Gym 1, 8-10)
db 0x3  ; level range
db 0x2  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x0  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 2 (-> Gym 2, 18-21)
db 0x4  ; level range
db 0xC  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 3 (-> Gym 3, 21-24)
db 0x4  ; level range
db 0x11 ; minimum level
db 0x2  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, 29)
db 0x5  ; level range
db 0x16 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, 37-43)
db 0x6  ; level range
db 0x1C ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x4  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, 37-43)
db 0x6  ; level range
db 0x21 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, 40-47)
db 0x6  ; level range
db 0x26 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, 42-50)
db 0x7  ; level range
db 0x2A ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon
;round 9 (-> Victory Road, no gym leader; also covers Elite Four overflow)
db 0x8  ; level range
db 0x2E ; minimum level
db 0x0  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x4  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x0  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon

; gym trainers (wBattleCount mod 10 == 6-9): same 11-byte layout as
; trainer_difficulty_settings, but with higher levels that approach the
; round's gym leader tier. The 4th gym trainer (mod 10 == 9), fought right
; before the leader, gets the level bonus + rarer class distribution.
;   0: level range
;   1: minimum level
;   2-5: normal class counts (pokeball, greatball, ultraball, masterball)
;   6: level bonus for the final (4th) gym trainer of the round
;   7-10: class counts for that final gym trainer - same total as 2-5,
;      but shifted toward rarer classes
trainer_difficulty_settings_gym:
;round 1 (-> Gym 1, 8-10)
db 0x3  ; level range
db 0x5  ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 2 (-> Gym 2, 18-21)
db 0x4  ; level range
db 0x10 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 3 (-> Gym 3, 21-24)
db 0x4  ; level range
db 0x15 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, 29)
db 0x5  ; level range
db 0x1A ; minimum level
db 0x0  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, 37-43)
db 0x6  ; level range
db 0x22 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, 37-43)
db 0x6  ; level range
db 0x26 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, 40-47)
db 0x6  ; level range
db 0x2A ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, 42-50)
db 0x7  ; level range
db 0x2E ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon
;round 9 (-> Victory Road, no gym leader; also covers Elite Four overflow)
db 0x8  ; level range
db 0x36 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x0  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x4  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x0  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x5  ; final trainer: masterball class pokemon

; ============================================================
; Mini-boss level/fill helpers (see MINIBOSS_FRAMEWORK.md)
; Live in this (rogue) bank so GetRandMon and the difficulty table are plain
; reads. Called by BuildMiniBossTeam (trainer bank) via farcall; they take no
; pointer input (read wBattleCount, write wCurEnemyLevel / wCurPartySpecies),
; so crossing banks is safe.
; ============================================================

; wCurEnemyLevel = this round's min_level + random(range), capped at 100.
MiniBossSetLevel::
	call GetMiniBossTierPtr      ; hl -> {range, min, class, rare}
	ld a, [hli]                  ; range
	ld c, a                      ; Rangerandom count
	ld a, [hl]                   ; min level
	push af
	push hl
	call Rangerandom             ; a = [0, range-1]; preserves bc/de
	pop hl
	ld b, a
	pop af                       ; a = min level
	add b
	cp 101
	jr c, .ok
	ld a, 100
.ok
	ld [wCurEnemyLevel], a
	call RogueApplyTrainerLevelModifiers
	ret

; Applies all active trainer-level modifiers after a base level is written.
; No register arguments. Clobbers a and the Divide/Multiply HRAM scratch;
; preserves bc, de, and hl for callers that are walking trainer data.
RogueApplyTrainerLevelModifiers::
	call RogueApplyWitchLevelBonus
	call RogueApplyDifficulty
	ret

; Challenge 5 (INCREASED_LEVELS): add ~10% of level, minimum +1.
; This retains the existing multiplier and overflow behavior, but preserves
; the roster-loop registers so the helper is safe for every trainer path.
RogueApplyWitchLevelBonus::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_INCREASED_LEVELS
	ret nz
	push bc
	push de
	push hl
	ld a, [wCurEnemyLevel]
	ld b, a
	ldh [hMultiplicand+2], a
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand+1], a
	ld a, 26
	ldh [hMultiplier], a
	call Multiply              ; level * 26; hProduct+2 = high byte ≈ level/10
	ldh a, [hProduct+2]
	and a
	jr nz, .hasLvlBonus
	ld a, 1                    ; minimum +1
.hasLvlBonus
	add b
	jr nc, .lvlBonusOk
	ld a, 255
.lvlBonusOk
	ld [wCurEnemyLevel], a
	pop hl
	pop de
	pop bc
	ret

; Adjusts wCurEnemyLevel by the player's LEVELS setting (wOptions2 bits 0-2).
; No register arguments.  Clobbers a and the Divide HRAM scratch.
RogueApplyDifficulty::
	ld a, [wOptions2]
	and DIFFICULTY_MASK
	ret z                        ; DIFFICULTY_NORMAL: leave the level untouched
	push bc
	push de
	push hl
	ld e, a                      ; e = difficulty setting, 1..4

; divisor: 10 for EASY/HARD (10%), 5 for VERY EASY/VERY HARD (20%)
	cp DIFFICULTY_VERY_EASY
	jr z, .fifth
	cp DIFFICULTY_VERY_HARD
	jr z, .fifth
	ld a, 10
	jr .gotDivisor
.fifth
	ld a, 5
.gotDivisor
	ldh [hDivisor], a
	ld a, [wCurEnemyLevel]
	ld d, a                      ; d = base level
	ldh [hDividend], a
	ld b, $1                     ; 1-byte dividend, do not remove
	call Divide
	ldh a, [hQuotient + 3]
	ld c, a                      ; c = delta

	ld a, e
	cp DIFFICULTY_HARD
	jr nc, .harder               ; HARD (3) or VERY HARD (4) -> add
; EASY / VERY EASY -> subtract, floor at 1
	ld a, d
	sub c
	jr c, .floor
	and a
	jr nz, .store
.floor
	ld a, 1
	jr .store
.harder
	ld a, d
	add c
	jr c, .ceiling
	cp 101
	jr c, .store
.ceiling
	ld a, 100
.store
	ld [wCurEnemyLevel], a
	pop hl
	pop de
	pop bc
	ret

; ============================================================================
; Mid-battle evolution (Extreme Yellow import).
; A mon that levels up mid-battle evolves at once if the trainer still has
; Pokemon left, instead of waiting for EndOfBattle.
; ============================================================================

RogueTryMidBattleEvolution::
	farcall AnyEnemyPokemonAliveCheck
	ret z                       ; last opponent: let EndOfBattle evolve normally
	ldh a, [hIsInBattle]
	dec a
	ret z                       ; wild battle: no mid-battle evolution
	predef EvolutionAfterBattle
	ld a, [wEvolutionOccurred]
	and a
	ret z

; Only the active Pokemon needs its battle data refreshed.  Other party members
; may have evolved through Exp. All, but are refreshed when they are sent out.
	ld de, wBattleMonSpecies
	ld hl, wPartyMon1Species
	ld bc, PARTYMON_STRUCT_LENGTH
	ld a, [wPlayerMonNumber]
	call AddNTimes
	ld a, [de]
	cp [hl]
	jr z, .done                 ; a benched mon evolved, not the active one
	call RogueRefreshBattleMonAfterEvolution
.done
	xor a
	ld [wCanEvolveFlags], a     ; prevent a second evolution this battle
	ret

; LoadBattleMonFromParty (engine/battle/core.asm) WITHOUT its trailing stat-mod
; reset, so boosts, drops, Substitute and status all survive the evolution.
RogueRefreshBattleMonAfterEvolution:
	ld a, [wPlayerMonNumber]
	ld bc, PARTYMON_STRUCT_LENGTH
	ld hl, wPartyMon1Species
	call AddNTimes
	ld de, wBattleMonSpecies
	ld bc, wBattleMonDVs - wBattleMonSpecies
	call CopyData
	ld bc, MON_DVS - MON_OTID
	add hl, bc
	ld de, wBattleMonDVs
	ld bc, MON_PP - MON_DVS
	call CopyData
	ld de, wBattleMonPP
	ld bc, NUM_MOVES
	call CopyData
	ld de, wBattleMonLevel
	ld bc, wBattleMonPP - wBattleMonLevel
	call CopyData

	ld a, [wBattleMonSpecies]
	ld [wBattleMonSpecies2], a
	ld [wCurSpecies], a
	call GetMonHeader
	ld hl, wPartyMonNicks
	ld a, [wPlayerMonNumber]
	call SkipFixedLengthTextEntries
	ld de, wBattleMonNick
	ld bc, NAME_LENGTH
	call CopyData
	ld hl, wBattleMonLevel
	ld de, wPlayerMonUnmodifiedLevel
	ld bc, 1 + NUM_STATS * 2
	call CopyData
	xor a
	ld [wCalculateWhoseStats], a
	farcall CalculateModifiedStats
	farcall ApplyBurnAndParalysisPenaltiesToPlayer
	farcall ApplyBadgeStatBoosts

; AnimateSendingOutMon draws the small "in battle" sprite while hIsInBattle is
; set.  Clear it across that one predef only, to get the full-size back pic.
	predef LoadMonBackPic
	xor a
	ldh [hStartTileID], a
	hlcoord 4, 11
	ldh a, [hIsInBattle]
	push af
	xor a
	ldh [hIsInBattle], a
	predef AnimateSendingOutMon
	pop af
	ldh [hIsInBattle], a

; EvolveMon started MUSIC_SAFARI_ZONE then hit SFX_STOP_ALL_MUSIC, and
; EvolutionAfterBattle deliberately skips PlayDefaultMusic while in battle
; (engine/pokemon/evos_moves.asm:281-287), so nothing is playing here.  It also
; skips the tileset reload (:242-244), so the HUD tile patterns need restoring.
	farcall PlayBattleMusic
	farcall LoadHudTilePatterns
	farcall DrawPlayerHUDAndHPBar
	call SaveScreenTilesToBuffer1
	ret

; wCurPartySpecies = one rarer-random mon (this round's base class, with a
; rare-bump chance); wCurEnemyLevel = this round's level.
; base class is GetRandMon's convention: 4=pokeball ... 1=masterball.
MiniBossRollFillMon::
	call MiniBossSetLevel
	call GetMiniBossTierPtr
	inc hl
	inc hl                       ; hl -> base class byte
	ld a, [hli]                  ; base class
	ld b, a
	ld a, [hl]                   ; rare chance (out of 256)
	ld c, a
	push bc
	call Random                  ; a = 0..255
	pop bc
	cp c
	jr nc, .noRare
	ld a, b
	cp 2
	jr c, .noRare                ; already masterball (b == 1)
	dec b                        ; one tier rarer
.noRare
	call GetRandMon              ; input b = class -> wCurPartySpecies (same bank)
	ret

; hl -> the 4-byte trainer_difficulty_settings_miniboss block for the current
; round (wBattleCount / 10, clamped to 9).
GetMiniBossTierPtr:
	ld a, [wBattleCount]
	cp 90
	jr c, .noClamp
	ld a, 89
.noClamp
	ld b, 0                      ; b = round
.rndLoop
	cp 10
	jr c, .gotRound
	sub 10
	inc b
	jr .rndLoop
.gotRound
	ld a, b
	add a                        ; *2
	add a                        ; *4
	ld c, a
	ld b, 0
	ld hl, trainer_difficulty_settings_miniboss
	add hl, bc
	ret

; One 4-byte block per round: db level_range, min_level, base_class, rare_chance.
; min_level sits BETWEEN the round's final route trainer and its gym trainers
; (see trainer_difficulty_settings / _gym above). base_class is GetRandMon's
; convention (4=pokeball, 3=greatball, 2=ultraball, 1=masterball); rare_chance/256
; = odds a fill mon is bumped one tier rarer. Fully tunable.
trainer_difficulty_settings_miniboss:
	db 3, 5,  3, 64   ; round 1 (between route-final ~4 and gym ~5)
	db 4, 15, 3, 80   ; round 2
	db 4, 20, 2, 64   ; round 3
	db 5, 25, 2, 80   ; round 4
	db 6, 33, 2, 96   ; round 5
	db 6, 37, 2, 112  ; round 6
	db 6, 41, 2, 128  ; round 7
	db 7, 45, 1, 96   ; round 8
	db 8, 52, 1, 112  ; round 9

; Rangerandom moved to home/random.asm (HOME bank) so every bank can reach it
; with a plain `call` - it used to live here (bank 07 / "rogue" section) and
; every cross-bank caller was using a plain `call` instead of `farcall`,
; silently executing whatever happened to be at that address in the caller's
; own bank instead of this function.

;GetWeightedLevel:
;	ld a, [wPartyCount]
;	dec a
;	jp z, GetHighestLevel
;
;	push hl
;	push bc
;	push de
;	
;	ld hl, wBoxDataEnd+5	;need 6 bytes of working space
;	
;	ld de, wPartyMenuHPBarColors
;	ld a, [wPartyCount]
;	ld c, a
;.loop
;	ld a, [de]
;	ld [hld], a
;	inc de
;	dec c
;	jr nz, .loop
;
;	ld a, [wPartyCount]
;	ld c, a
;.loop2
;	inc hl
;	dec c
;	jr nz, .loop2
;	
;	ld d, h
;	ld e, l
;	
;.sortingpass
;	ld h, d
;	ld l, e
;	ld a, [wPartyCount]	;if in this sorting pass loop, then this number is 2 to 6
;	dec a
;	ld c, a
;.loop3A
;	ld a, [hld]
;	cp [hl]
;	jr c, .swapping
;	dec c
;	jr z, .weight	;if an entire pass was made with no swapping, then the bytes are sorted
;	jr .loop3A
;.swapping
;	;current [HL] is greater than [HL+1] which is in A
;	;need to swap them
;	ld b, a
;	ld a, [hli]
;	ld [hld], a
;	ld a, b
;	ld [hl], a
;	;did the swap
;	;if this is the end of the pass, do another pass
;	dec c
;	jr z, .sortingpass
;	;else keep looping through this pass
;.loop3B
;	ld a, [hld]
;	cp [hl]
;	jr c, .swapping
;	dec c
;	jr z, .sortingpass	;if the pass is complete, then then do another pass because a swap was done
;	jr .loop3B
;	
;.weight
;	ld h, d
;	ld l, e
;	ld a, [wPartyCount]
;	ld c, a
;	dec c	
;	ld d, 1
;	ld e, 1
;.loop4
;	dec hl
;	ld a, [hl]
;.loop4sub1
;	srl a
;	dec e
;	jr nz, .loop4sub1
;	ld [hl], a
;	inc d
;	ld e, d
;	dec c
;	jr nz, .loop4
;
;.summation
;	ld de, $0000
;	ld a, [wPartyCount]
;	ld c, a
;.loop5
;	ld a, [hli]
;	add e
;	ld e, a
;	ld a, d
;	adc d
;	ld d, a
;	dec c
;	jr nz, .loop5	
;
;.multiplication	;do x32
;	ld c, 5
;.loop6
;	sla e
;	rl d
;	dec c
;	jr nz, .loop6
;
;.prepareDividend
;	ld a, d
;	ld [hDividend+0], a
;	ld a, e
;	ld [hDividend+1], a
;	xor a
;	ld [hDividend+2], a
;	ld [hDividend+3], a
;
;.getdivisor
;	ld a, [wPartyCount]
;	ld c, a
;	dec c
;	ld a, 32
;	ld b, 32
;.loop7
;	srl b
;	add b
;	dec c
;	jr nz, .loop7
;	ld [hDivisor], a
;
;	ld b, 2
;	call Divide
;	ld a, [hQuotient+3]
;	
;	pop de
;	pop bc
;	pop hl
;	ret
;	
;
;	
;GetHighestLevel:	;gets the highest party level into A
;; UPDATE, should look to current battle count
;	push hl
;	push bc
;	ld hl, wPartyMenuHPBarColors
;	ld a, [wPartyCount]	;1 to 6
;	ld b, a	;use b for countdown
;.loadHigher
;	ld a, [hl]
;.keepCurrent
;	dec b
;	jr z, .highestLVLfound
;	inc hl
;	cp a, [hl]
;	jr c, .loadHigher
;	jr .keepCurrent
;.highestLVLfound
;	pop bc
;	pop hl
;	ret
	
	
;implement a function to scale trainer levels
ScaleTrainer:
	call ScaleTrainer_level
	call ScaleTrainer_evolution
	ret
	
ScaleTrainer_level:
	;CheckEvent EVENT_90C
	ret z
	push bc

	ld a, [wGymLeaderNo]
	and a
	;jr nz, .hard	;if fighting a boss like a gym leader, use the harder level scaling
	;ld a, [wOptions]
	;bit BIT_BATTLE_HARD, a
	;jr z, .normal	;if it's a regular trainer but playing on hard mode, use the harder level scaling
;.hard
	;call GetHighestLevel
	;jr .got_level
.normal
	;call GetWeightedLevel
.got_level
	push af
	ld a, [wCurEnemyLevel]
	ld b, a
	pop af
	
	;at this line, B holds current enemy level and A holds highest/weighted party level
	cp b
	pop bc
	ret c
	ret z
	
	push bc
	ld [wCurEnemyLevel], a
	call Random
	and $03
	ld b, a
	ld a, [wGymLeaderNo]
	and a
	jr z, .notboss
	ld a, [wCurEnemyLevel]
	add b
	call PreventARegOverflow
	ld [wCurEnemyLevel], a
	call Random
	and $03
	ld b, a
.notboss
	ld a, [wCurEnemyLevel]
	add b
	call PreventARegOverflow
	ld [wCurEnemyLevel], a
	pop bc
	ret

ScaleTrainer_evolution:
	push bc
	ld a, [wCurEnemyLevel]
	ld b, a
	;proceed to bias the enemy mon level against evolving for the sake of progression balance
	;B holds the enemy current level at this line
	push af
	cp 30
	jr c, .next
	srl b
.next
	srl b
	srl b
	sub b
	ld [wCurEnemyLevel], a
	call EvolveMonByLevel
	pop af
	ld [wCurEnemyLevel], a
	pop bc
	ret


	

;this will prevent an overflow of the A register
;typically for custom functions that increase enemy levels
;defaulted to 255 on an overflow
;call after a value was just added to register A
PreventARegOverflow:
	ret nc	;return if there was no overflow
	;else set A to the max
	ld a, $FF
	ret


;randomizes the 'mon in wCurPartySpecies to an unevolved 'mon then tries to evolve it	
;A bias is applied so that trainer 'mons need more levels to evolve
;Also, the stronger end of unevolved pokemon will only show up in level-30 or higher trainer teams
RandomizeRegularTrainerMons:
	;CheckEvent EVENT_8D8
	ret z
	push de
	ld de, ListNonLegendUnEvoPkmn_early
	ld a, [wCurEnemyLevel]
	push af
	ld b, a
	cp 30
	jr c, .check15
	ld de, ListNonLegendUnEvoPkmn
	srl b
	jr .next
.check15
	cp 15
	jr c, .next
	ld de, ListNonLegendUnEvoPkmn_mid
.next
	srl b
	srl b
	sub b
	ld [wCurEnemyLevel], a
	call GetRandMon
	call EvolveMonByLevel
	pop af
	ld [wCurEnemyLevel], a
	pop de
	ret


; Pokemon needs to be in d. Evolves it as many times as wCurEnemyLevel
; allows (used for enemy trainer mons AND reward/given mons - despite the
; "enemy" scratch vars it reads/writes, it has no actual enemy-specific logic).
EvolveMonByLevel:
	ld hl, EvosMovesPointerTable	;load the address of the pointer table, and worry about the bank later
	ld b, 0
	ld a, d
	dec a
	add a
	rl b
	ld c, a		;BC now contains the pokemon's offset in the pointer table
	add hl, bc	;and HL now points to the correct position in the pointer table
	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, 2
	call FarCopyData	;switches banks, then copies the 2-byte address that HL points to into wEvoDataBuffer
	ld hl, wEvoDataBuffer	;let's now point HL to said address
	ld a, [hli]
	ld h, [hl]
	ld l, a				;HL now points to the address of the pokemon's evolution list
	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, wEvoDataBufferEnd - wEvoDataBuffer
	call FarCopyData	;now copy the evolution list pointed to by HL into wEvoDataBuffer
	ld hl, wEvoDataBuffer	;we can now reference the evolution list by pointing HL to it

.evoloop
	ld a, [hli]
	and a
	ret z
	cp EVOLVE_LEVEL
	jr z, .lvl_evolve
	cp EVOLVE_TRADE
	jr z, .trade_evolve
	;else item evolve
	inc hl
	;only item evolve if lvl 35 or more
	ld b, 35
	ld a, [wCurEnemyLevel]
	cp b
	jr nc, .lvl_evolve ;after incrementing hl one space, maintains the same structure as lvl evolving
.trade_evolve
	inc hl	;increment to see if it level or stone evolves instead
	inc hl
	jr .evoloop

.lvl_evolve
	ld a, d
	cp EEVEE	;deal with eevee separately
	jr z, .handleeevee
	ld a, [hli]
	ld b, a
	ld a, [wCurEnemyLevel]
	cp b
	ret c
	ld a, [hl]
	ld [wCurPartySpecies], a
	ld d, a             ; carry the evolved species forward so chains (e.g. Charmander->Charmeleon->Charizard) cascade
	jp EvolveMonByLevel

.handleeevee
	call Random
	and $0F
	cp $03
	ret c	;eevee
	push af
	ld a, FLAREON
	ld [wCurPartySpecies], a
	pop af
	cp $07
	ret c ;flareon
	push af
	ld a, VAPOREON
	ld [wCurPartySpecies], a
	pop af
	cp $0B
	ret c ;vaporeon
	;else jolteon
	ld a, JOLTEON
	ld [wCurPartySpecies], a
	ret
	

;joenote - take the 'mon in wCurPartySpecies, find its previous evolution, and put it back in wCurPartySpecies
DevolveMon:	
	ld hl, EvosMovesPointerTable
.nextmonloop
	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, 2
	call FarCopyData	;switches banks, then copies the 2-byte address that HL points to into wEvoDataBuffer
	;note, HL is now already incremented
	ld a, [wEvoDataBuffer + 1]
	cp $FF
	ret z	;return if reached end of evolution pointer list

	push hl
	ld hl, wEvoDataBuffer	;let's now point HL to said address
	ld a, [hli]
	ld h, [hl]
	ld l, a				;HL now points to the address of the pokemon's evolution list

	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, wEvoDataBufferEnd - wEvoDataBuffer
	call FarCopyData	;now copy the evolution list pointed to by HL into wEvoDataBuffer

	ld hl, wEvoDataBuffer	;we can now reference the evolution list by pointing HL to it
	call .evosloop
	pop hl
	jr nz, .nextmonloop
	
	ld bc, 0 - EvosMovesPointerTable
	add hl, bc
	srl h
	rr l
	ld a, l
	ld [wCurPartySpecies], a
	ret
	
.evosloop
	ld a, [hli]
	and a
	jr z, .notfound
	cp EVOLVE_ITEM
	jr nz, .not_item
	inc hl
.not_item
	inc hl
	ld a, [wCurPartySpecies]
	ld b, a
	ld a, [hli]
	cp b
	jr nz, .evosloop
	ret
.notfound
	ld a, 1
	and a
	ret
	
; d = Current Gym Leader/Battle, ie. OPP_BROCK
InitGymBattle::
    ld a, d
	ld [wCurOpponent], a
	ld a, [wBattleCount]
    ldh [hDividend], a          ; place battle count in dividend
    ld   a, 10
    ldh [hDivisor], a           ; place 10 as divisor
    ld b, $1                    ; b determines how many bytes the number is, do not remove!
    call Divide
    ldh   a, [hQuotient+3]      ; load in quotient
    sub a, 1                    ; subtract for multiplication to get base trainer number
    ldh [hMultiplicand+2], a    ; place number in for multiplication
    ld a, 3                     ; multiply by 3, which is the amount of teams per each ranking
    ldh [hMultiplier], a        ; place amount of class in multiplier
    call Multiply               ; multiply number by 3, to get our base number
    ldh   a, [hProduct+3]       ; load product into a
    add a, 1                    ; add one (not zero based), to get trainer number base
    push af
    ld c, 3                     ; amount of options per rankings
    call Rangerandom
    ld b, a                     ; load random number into b
    pop af
    add a, b                    ; add random number to base trainer to get party
    ld [wTrainerNo], a          ; set trainer no within gym leaders options
    ld a, 1
	ld [wIsTrainerBattle], a    ; start battle
	ld hl, wRogueFlagsBitfield
	res 0, [hl]                 ; route is next after this gym
	ret

; d = Current Elite Four member, ie. OPP_LORELEI
; Tier is derived LINEARLY from wBattleCount (86/87/88/89 -> tier 0-3), unlike
; InitGymBattle's round-based math - the Elite Four is fought at a fixed battle
; count range, not on the /10 grid gym leaders use. Does NOT touch wGymLeaderNo
; (leave it 0 - a nonzero value triggers gym-leader victory music and the
; Challenge 11 legendary-ace substitution) and does NOT touch wRogueFlagsBitfield
; bit 0 (route/gym alternation - irrelevant here, the final sequence has fixed
; room routing instead).
InitElite4Battle::
	ld a, d
	ld [wCurOpponent], a
	ld a, [wBattleCount]
	sub a, 86                   ; tier 0 at battle count 86
	cp a, 4
	jr c, .tierOk
	ld a, 3                     ; clamp to the last tier if called out of range
.tierOk
	ld b, a
	ld a, 3                     ; 3 teams per tier
	ldh [hMultiplicand+2], a
	ld a, b
	ldh [hMultiplier], a
	call Multiply                ; base = tier * 3
	ldh a, [hProduct+3]
	add a, 1                     ; +1 (party data is 1-based)
	push af
	ld c, 3                      ; amount of variants per tier
	call Rangerandom
	ld b, a                      ; random variant into b
	pop af
	add a, b                     ; base + random variant
	ld [wTrainerNo], a
	ld a, 1
	ld [wIsTrainerBattle], a     ; start battle
	ret


; If the species about to be loaded is the rival starter placeholder,
; replace it with the rival's actual rogue starter (wRivalStarter), evolved
; to match wCurEnemyLevel. Works for any trainer/location.
; Input: wCurPartySpecies = species byte just read from trainer data
PatchRivalStarterSpecies::
	push hl
	push bc
	push de
	ld a, [wCurPartySpecies]
	cp RIVAL_STARTER_PLACEHOLDER
	jr nz, .done
	ld a, [wRivalStarter]
	ld d, a
	call RivalStarterEvolve
.done
	pop de
	pop bc
	pop hl
	ret

; Input: d = base species, wCurEnemyLevel = level
; Output: wCurPartySpecies = species evolved up to 2 stages based on level
;         (item/trade evolutions and Eevee's stone evolutions are skipped,
;          since the rival can't perform those)
RivalStarterEvolve::
	ld a, d
	ld [wCurPartySpecies], a
	cp EEVEE
	ret z
	call EvolveStep
	ret nc
	call EvolveStep
	ret

; Input: d = species, wCurEnemyLevel = level
; Output: if a level-evolution threshold is met, carry set, d and
;         wCurPartySpecies updated to the evolved species; else carry clear
EvolveStep:
	push hl
	push bc
	ld hl, EvosMovesPointerTable
	ld b, 0
	ld a, d
	dec a
	add a
	rl b
	ld c, a
	add hl, bc
	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, 2
	call FarCopyData
	ld hl, wEvoDataBuffer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, 4
	call FarCopyData
	ld hl, wEvoDataBuffer
	ld a, [hl]
	cp EVOLVE_LEVEL
	jr nz, .noEvo
	inc hl
	ld a, [hl]
	ld b, a
	ld a, [wCurEnemyLevel]
	cp b
	jr c, .noEvo
	inc hl
	ld a, [hl]
	ld d, a
	ld [wCurPartySpecies], a
	pop bc
	pop hl
	scf
	ret
.noEvo
	pop bc
	pop hl
	and a
	ret
