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
    call GetRandMon
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
    call Rangerandom
	add a, e   ; minimum level added to random number
	ld [wCurEnemyLevel], a  ; place level of pokemon in
	;push hl                 ; preserve h1
	call AddPartyMon    ; add the pokemon
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
	;CheckEvent EVENT_90C
	ret z
	
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
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	