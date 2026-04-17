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

	
	

CheckIfPkmnReal:
;set the carry if pokemon number in 'a' is found on the list of legit pokemon
	push hl
	push de
	push bc
	ld hl, ListRealPkmn
	ld de, $0001
	call IsInArray
	pop bc
	pop de
	pop hl

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
    jr z, pokeball_class_selection_trainer
    cp a, $3
    jr z, greatball_class_selection_trainer
    
; common
pokeball_class_selection_trainer:
call Random                 ; get a random number to determine pokemon
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
ld a, $1D                   ; multiply by amount of this class
ldh [hMultiplier], a        ; place amount of class in multiplier
call Multiply               ; multiply random number by amount in class
ldh   a, [hProduct+2]       ; load product into a
ldh [hDividend], a          ; place product in divident
ldh   a, [hProduct+3]
ldh [hDividend+1], a

ld a, $FF                   ; load 255
ld b, $2
ldh [hDivisor], a           ; place 255 as divisor
call Divide
ldh   a, [hQuotient+3]      ; load in quotient
ldh [hMultiplicand], a      ; set quotient as multiplier
ld a, $2
ldh [hMultiplier], a        ; load 2, which is the size of each struct in array
xor a
ldh [hMultiplicand+1], a    ; clear out other digits
ldh [hMultiplicand+2], a
call Multiply               ; multiply result by size of struct to add to base address
ld hl, hProduct+1           ; load pokemon pointer
ld c,[hl]                   ; load offset to add to pointer, to get address
ld b, $0

ld hl, pokeball_class+2     ; load base pointer
add hl, bc                  ; add product to get address of pokemon
ld a, [hl]                  ; load pokemon from address
ld [wCurPartySpecies], a    ; place pokemon in Current Party Speciies

pop bc
pop hl
RET

; rare

greatball_class_selection_trainer:
call Random
ldh [hMultiplicand+2], a
xor a
ldh [hMultiplicand], a
ldh [hMultiplicand+1], a
ld a, $1C
ldh [hMultiplier], a
call Multiply
ldh   a, [hProduct+2]
ldh [hDividend], a
ldh   a, [hProduct+3]
ldh [hDividend+1], a

ld a, $FF
ld b, $2
ldh [hDivisor], a
call Divide
ldh   a, [hQuotient+3]
ldh [hMultiplicand], a
ld a, $2
ldh [hMultiplier], a
xor a
ldh [hMultiplicand+1], a
ldh [hMultiplicand+2], a
call Multiply
ld hl, hProduct+1
ld c,[hl]
ld b, $0

ld hl, greatball_class+1
add hl, bc                  ; add product to get address of pokemon
ld a, [hl]                  ; load pokemon from address
ld [wCurPartySpecies], a    ; place pokemon in Current Party Speciies
pop bc
pop hl
RET
;
;ultraball_class_selection:
;
;call Random
;ldh [hMultiplicand+2], a
;xor a
;ldh [hMultiplicand], a
;ldh [hMultiplicand+1], a
;ld a, $10
;ldh [hMultiplier], a
;call Multiply
;ldh   a, [hProduct+2]
;ldh [hDividend], a
;ldh   a, [hProduct+3]
;ldh [hDividend+1], a
;
;ld a, $FF
;ld b, $2
;ldh [hDivisor], a
;call Divide
;ldh   a, [hQuotient+3]
;ldh [hMultiplicand], a
;ld a, $2
;ldh [hMultiplier], a
;xor a
;ldh [hMultiplicand+1], a
;ldh [hMultiplicand+2], a
;call Multiply
;ld hl, hProduct+1
;ld c,[hl]
;ld b, $0
;
;ld hl, ultraball_class+1
;add hl, bc
;ld a, [hld]
;cp b
;jr z, ultraball_load
;jp ultraball_class_selection
;
;
;ultraball_load:
;ld [hl], 0x1
;inc [hl]
;ld d, [hl]
;
;RET
;
;masterball_class_selection:
;
;rogue_pokemon_randomized_batch::
;   call Random
;   call Random_Pokemon_Selection
;   ld hl, wRoguePokemon1
;   ld [hl], d
;   call Random
;   call Random_Pokemon_Selection
;   ld hl, wRoguePokemon2
;   ld [hl], d
;   call Random
;   call Random_Pokemon_Selection
;   ld hl, wRoguePokemon3
;   ld [hl], d
;   
;RET
;.loop
;	ld a, b
;	and a
;	jr z, .endloop
;	inc hl
;	dec b
;	ld a, [hl]
;	and a
;	jr nz, .loop
;	ld h, d
;	ld l, e
;	jr .loop
;.endloop
;	ld a, [hl]
	pop bc
	pop hl
	ld [wCurPartySpecies], a
	ret
	
;generates a randomized 6-party enemy trainer roster
GetRandRoster:
	push bc
	push de
    push hl
    ld hl, trainer_difficulty_settings
    ld a, [wBattleCount]	; load how many battles the player has won
    cp a, $4   
    jr c, GetRandRosterLoop ; jump if have won less than 5 battles
    ld de, $6
    add hl, de
    cp a, $5
    jr c, GetRandRosterLoop ; jump if have won less than 6 battles
	jp GetRandRosterLoop


GetRandRosterLoop:
	ld c, [hl]   ; load level range
    inc hl      ; move to next byte, minimum level
    ld e, [hl]  ; load minimum level

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
    inc hl      ; move to next byte, number pokeball class pokemon
    
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
    
trainer_difficulty_settings:
;firsttrainers
db 0x3  ; level range
db 0x2  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x0  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
;firstboss
db 0x0  ; Level range
db 0x5  ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon

; get a random number in a certain range
; c is the range
Rangerandom::
push bc
call Random                 ; get a random number to determine pokemon
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
ld a, c                     ; multiply by amount of this class
ldh [hMultiplier], a        ; place amount of class in multiplier
call Multiply               ; multiply random number by amount in class
ldh   a, [hProduct+2]       ; load product into a
ldh [hDividend], a          ; place product in divident
ldh   a, [hProduct+3]
ldh [hDividend+1], a

ld a, $FF                   ; load 255
ld b, $2
ldh [hDivisor], a           ; place 255 as divisor
call Divide
ldh   a, [hQuotient+3]      ; load in quotient
pop bc
ret

GetWeightedLevel:
	ld a, [wPartyCount]
	dec a
	jp z, GetHighestLevel

	push hl
	push bc
	push de
	
	ld hl, wBoxDataEnd+5	;need 6 bytes of working space
	
	ld de, wPartyMenuHPBarColors
	ld a, [wPartyCount]
	ld c, a
.loop
	ld a, [de]
	ld [hld], a
	inc de
	dec c
	jr nz, .loop

	ld a, [wPartyCount]
	ld c, a
.loop2
	inc hl
	dec c
	jr nz, .loop2
	
	ld d, h
	ld e, l
	
.sortingpass
	ld h, d
	ld l, e
	ld a, [wPartyCount]	;if in this sorting pass loop, then this number is 2 to 6
	dec a
	ld c, a
.loop3A
	ld a, [hld]
	cp [hl]
	jr c, .swapping
	dec c
	jr z, .weight	;if an entire pass was made with no swapping, then the bytes are sorted
	jr .loop3A
.swapping
	;current [HL] is greater than [HL+1] which is in A
	;need to swap them
	ld b, a
	ld a, [hli]
	ld [hld], a
	ld a, b
	ld [hl], a
	;did the swap
	;if this is the end of the pass, do another pass
	dec c
	jr z, .sortingpass
	;else keep looping through this pass
.loop3B
	ld a, [hld]
	cp [hl]
	jr c, .swapping
	dec c
	jr z, .sortingpass	;if the pass is complete, then then do another pass because a swap was done
	jr .loop3B
	
.weight
	ld h, d
	ld l, e
	ld a, [wPartyCount]
	ld c, a
	dec c	
	ld d, 1
	ld e, 1
.loop4
	dec hl
	ld a, [hl]
.loop4sub1
	srl a
	dec e
	jr nz, .loop4sub1
	ld [hl], a
	inc d
	ld e, d
	dec c
	jr nz, .loop4

.summation
	ld de, $0000
	ld a, [wPartyCount]
	ld c, a
.loop5
	ld a, [hli]
	add e
	ld e, a
	ld a, d
	adc d
	ld d, a
	dec c
	jr nz, .loop5	

.multiplication	;do x32
	ld c, 5
.loop6
	sla e
	rl d
	dec c
	jr nz, .loop6

.prepareDividend
	ld a, d
	ld [hDividend+0], a
	ld a, e
	ld [hDividend+1], a
	xor a
	ld [hDividend+2], a
	ld [hDividend+3], a

.getdivisor
	ld a, [wPartyCount]
	ld c, a
	dec c
	ld a, 32
	ld b, 32
.loop7
	srl b
	add b
	dec c
	jr nz, .loop7
	ld [hDivisor], a

	ld b, 2
	call Divide
	ld a, [hQuotient+3]
	
	pop de
	pop bc
	pop hl
	ret
	

	
GetHighestLevel:	;gets the highest party level into A
; UPDATE, should look to current battle count
	push hl
	push bc
	ld hl, wPartyMenuHPBarColors
	ld a, [wPartyCount]	;1 to 6
	ld b, a	;use b for countdown
.loadHigher
	ld a, [hl]
.keepCurrent
	dec b
	jr z, .highestLVLfound
	inc hl
	cp a, [hl]
	jr c, .loadHigher
	jr .keepCurrent
.highestLVLfound
	pop bc
	pop hl
	ret
	
	
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
	call GetWeightedLevel
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
	call EnemyMonEvolve
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
	call EnemyMonEvolve
	pop af
	ld [wCurEnemyLevel], a
	pop de
	ret


;joenote - evolve an enemy mon in wCurPartySpecies based on wCurEnemyLevel
EnemyMonEvolve:
	ld hl, EvosMovesPointerTable	;load the address of the pointer table, and worry about the bank later
	ld b, 0
	ld a, [wCurPartySpecies]
	dec a
	add a
	rl b
	ld c, a		;BC now contains the pokemon's offset in the pointer table
	add hl, bc	;and HL now points to the correct position in the pointer table
	ld de, wEvoDataBufferEnd
	ld a, BANK(EvosMovesPointerTable)
	ld bc, 2
	call FarCopyData	;switches banks, then copies the 2-byte address that HL points to into wEvoDataBufferEnd
	ld hl, wEvoDataBufferEnd	;let's now point HL to said address
	ld a, [hli]
	ld h, [hl]
	ld l, a				;HL now points to the address of the pokemon's evolution list
	ld de, wEvoDataBufferEnd
	ld a, BANK(EvosMovesPointerTable)
	ld bc, wEvoDataBufferEnd - wEvoDataBufferEnd
	call FarCopyData	;now copy the evolution list pointed to by HL into wEvoDataBufferEnd
	ld hl, wEvoDataBufferEnd	;we can now reference the evolution list by pointing HL to it
	
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
	ld a, [wCurPartySpecies]
	cp EEVEE	;deal with eevee separately
	jr z, .handleeevee
	ld a, [hli]
	ld b, a
	ld a, [wCurEnemyLevel]
	cp b
	ret c
	ld a, [hl]
	ld [wCurPartySpecies], a
	jp EnemyMonEvolve

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
	ld de, wEvoDataBufferEnd
	ld a, BANK(EvosMovesPointerTable)
	ld bc, 2
	call FarCopyData	;switches banks, then copies the 2-byte address that HL points to into wEvoDataBufferEnd
	;note, HL is now already incremented
	ld a, [wEvoDataBufferEnd + 1]
	cp $FF
	ret z	;return if reached end of evolution pointer list

	push hl
	ld hl, wEvoDataBufferEnd	;let's now point HL to said address
	ld a, [hli]
	ld h, [hl]
	ld l, a				;HL now points to the address of the pokemon's evolution list

	ld de, wEvoDataBufferEnd
	ld a, BANK(EvosMovesPointerTable)
	ld bc, wEvoDataBufferEnd - wEvoDataBufferEnd
	call FarCopyData	;now copy the evolution list pointed to by HL into wEvoDataBufferEnd
	
	ld hl, wEvoDataBufferEnd	;we can now reference the evolution list by pointing HL to it
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
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	