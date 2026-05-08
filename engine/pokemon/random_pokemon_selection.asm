; This code is meant to handle any time a pokemon is selected at random, be it starters or for regular prizes
; The code outputs a pokemon ID into a
; masterball class check will be here, will require separate events to occur before active
; auto class by putting a number in c
Random_Pokemon_Selection::
; set class check
ld a, 0x1
cp c
jp z, pokeball_class_selection

ld a, 0x2
cp c
jp z, greatball_class_selection

ld a, 0x3
cp c
jp z, ultraball_class_selection

ld a, 0x4
cp c
jp z, masterball_class_selection

ldh a, [hRandomAdd]
ld b, a

.determineClassSlot
ld a, pokeball_odds
cp b
jr nc, pokeball_class_selection
ld a, greatball_odds
cp b
jr nc, greatball_class_selection
jp ultraball_class_selection


pokeball_class_selection:
ld hl, pokeball_class_selection
push hl
ld hl, pokeball_class
push hl
ld a, pokeball_pokemon_line_amount
push af
jp pokemon_selection

greatball_class_selection:
ld hl, greatball_class_selection
push hl
ld hl, greatball_class
push hl
ld a, greatball_pokemon_line_amount
push af
jp pokemon_selection

ultraball_class_selection:
ld hl, ultraball_class_selection
push hl
ld hl, ultraball_class
push hl
ld a, ultraball_pokemon_line_amount
push af
jp pokemon_selection

masterball_class_selection:
ld hl, masterball_class_selection
push hl
ld hl, masterball_class
push hl
ld a, masterball_pokemon_line_amount
push af
jp pokemon_selection

pokemon_selection:
call Random                 ; get a random number to determine pokemon
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
pop af                      ; restore line amount to multiply by amount in class
ldh [hMultiplier], a        ; place amount of class in multiplier
call Multiply               ; multiply random number by amount in class
ldh   a, [hProduct+2]       ; load product into a
ldh [hDividend], a          ; place product in divident
ldh   a, [hProduct+3]
ldh [hDividend+1], a

ld a, $FF                   ; load 255
ld b, $2                    ; b determines how many bytes the number is, do not remove!
ldh [hDivisor], a           ; place 255 as divisor
call Divide
ldh   a, [hQuotient+3]      ; load in quotient, which will be the offset
ld c, a                     ; place in c
ld b, $0


pop hl                      ; restore base pointer
add hl, bc                  ; add product to get address of pokemon

                      
ld d, [hl]                  ; load selected pokemon
call AllSpeciesCheck        ; check if pokemon already in box or party
xor a                       ; clear out a
pop hl                      ; reload selection class
cp c
jr z, .done                 ; if 0, you have found a suitable pokemon
jp hl                       ; if 1, you have selected an already existing team member and need to redo

.done
RET

rogue_pokemon_randomized_batch::
   ld hl, wRoguePokemon1
   xor a
   ld [hli], a          ; clear out prior pokemon
   ld [hli], a          ; clear out prior pokemon
   ld [hl], a           ; clear out prior pokemon
   
   call Random
   call Random_Pokemon_Selection
   ld hl, wRoguePokemon1
   ld [hl], d
   .roguepokemon2
   call Random
   call Random_Pokemon_Selection
   ld a, [wRoguePokemon1]
   cp d
   jr z, .roguepokemon2
   ld hl, wRoguePokemon2
   ld [hl], d
   .roguepokemon3
   call Random
   call Random_Pokemon_Selection
   ld a, [wRoguePokemon1]
   cp d
   jr z, .roguepokemon3
   ld a, [wRoguePokemon2]
   cp d
   jr z, .roguepokemon3
   ld hl, wRoguePokemon3
   ld [hl], d
   
RET

; a check to see if pokemon is already in players box or party
; returns a 0 if no and a 1 if yes

; UPDATE, need a way to check if evolution
AllSpeciesCheck::
    ld b, 0
    ld c, 0
    ld hl, wPartySpecies
    push hl
    
    .loop
    pop hl
    ld a, [hli]
    push hl
	cp $ff
	jr z, .box
    
    inc c
    ld hl, wAllSpecies - 1
    add hl, bc
    ld [hl], a ; load mon into allspecies
    jr .loop
    
    .box ;
    pop hl
    ld hl, wBoxSpecies
    push hl
    
    .loop2
    pop hl
    ld a, [hli]
    push hl
	cp $ff
	jr z, .begin_checking
    
    inc c
    ld hl, wAllSpecies - 1
    add hl, bc
    ld [hl], a ; load mon into allspecies
    jr .loop2
    
    .begin_checking
    pop hl
    ld hl, wAllSpecies
    
    .checkloop
    ld a, [hli]         ; load pokemon
    cp d                ; compare to selected random pokemon
    jr z, .rejection    ; if the same pokemon flag for rejection
    cp $ff              
    jr nz, .checkloop   ; if not end of list, loop
    
    ld c, $0               ; set c to 0 as the pokemon isn't on players team
    jp  .end
    
    .rejection
    ld c, $1            ; set c to 1 as the pokemon is already on players team
    
    .end
    RET