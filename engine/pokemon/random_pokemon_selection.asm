; This code is meant to handle any time a pokemon is selected at random, be it starters or for regular prizes
; The code outputs a pokemon ID into a
; masterball class check will be here, will require separate events to occur before active
Random_Pokemon_Selection::
ldh a, [hRandomAdd]
ld  b, a
ld hl, pokemon_class_odds

.determineClassSlot
ld a, [hli]
cp b
jr nc, pokeball_class_selection
inc hl
ld a, [hli]
cp b
jr nc, greatball_class_selection
jp ultraball_class_selection

; common
pokeball_class_selection:
call Random                 ; get a random number to determine pokemon
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
ld a, $1E                   ; multiply by amount of this class
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

ld hl, pokeball_class+1     ; load base pointer
add hl, bc                  ; add product to get address of pokemon
ld a, [hld]                 ; load flag to see if offered before
cp b                        ; compare to see if pokemon was already offered
jr z, pokeball_load         ; look for new pokemon if already offered
jp pokeball_class_selection ; try again if already offered


pokeball_load:
ld [hl], 0x1                ; save 1 to flag for offered pokemon [probably need to update so this only triggers when chosen, instead of offered, could be a medium challenge though]
inc [hl]                    ; increase address to get to address of the pokemon
ld d, [hl]                  ; load pokemon from address

RET

; rare

greatball_class_selection:
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
add hl, bc
ld a, [hld]
cp b
jr z, greatball_load
jp greatball_class_selection


greatball_load:
ld [hl], 0x1
inc [hl]
ld d, [hl]

RET

ultraball_class_selection:

call Random
ldh [hMultiplicand+2], a
xor a
ldh [hMultiplicand], a
ldh [hMultiplicand+1], a
ld a, $10
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

ld hl, ultraball_class+1
add hl, bc
ld a, [hld]
cp b
jr z, ultraball_load
jp ultraball_class_selection


ultraball_load:
ld [hl], 0x1
inc [hl]
ld d, [hl]

RET

masterball_class_selection:

rogue_pokemon_randomized_batch::
   call Random
   call Random_Pokemon_Selection
   ld hl, wRoguePokemon1
   ld [hl], d
   call Random
   call Random_Pokemon_Selection
   ld hl, wRoguePokemon2
   ld [hl], d
   call Random
   call Random_Pokemon_Selection
   ld hl, wRoguePokemon3
   ld [hl], d
   
RET