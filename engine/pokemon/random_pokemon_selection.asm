




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
call Random
ldh [hMultiplicand+2], a
xor a
ldh [hMultiplicand], a
ldh [hMultiplicand+1], a
ld a, $1E
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

ld hl, pokeball_class+1
add hl, bc
ld a, [hld]
cp b
jr z, pokeball_load
jp pokeball_class_selection


pokeball_load:
ld [hl], 0x1
inc [hl]
ld d, [hl]

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