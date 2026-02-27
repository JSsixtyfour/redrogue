; This code is meant to handle any time a pokemon is selected at random, be it starters or for regular prizes
; The code outputs a pokemon ID into a
; masterball class check will be here, will require separate events to occur before active
Random_Pokemon_Selection:
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
ldh a, [hRandomAdd]
ld  b, a
sla a
sla a
sla a
sla a
sla a

sla b

sub a, b
ld b, a
; 32-2=30 pokemon in this class

sra b
sra b
sra b
sra b
sra b
sra b
sra b
; sra a ; forgo one shift right because structs are two bytes in size

ld hl, pokeball_class
add hl, bc
ld b, [hl]
xor a
cp b
jr z, pokeball_load
jp pokeball_class_selection


pokeball_load:
ld [hl], 0x1
inc [hl]
ld a, [hl]

RET

; rare

greatball_class_selection:
call Random
ldh a, [hRandomAdd]
ld b, a
sla a
sla a
sla a
sla a
sla a


sla b
sla b

; 32-4=28 pokemon in this class

sub a, b
ld b, a

sra b
sra b
sra b
sra b
sra b
sra b
sra b
; sra a ; forgo one shift right because structs are two bytes in size

ld hl, greatball_class
add hl, bc

ld b, [hl]
xor a
cp b
jr z, .greatball_load
jp greatball_class_selection


.greatball_load
ld [hl], 0x1
inc [hl]
ld a, [hl]

RET

ultraball_class_selection:

call Random

ldh a, [hRandomAdd]

sla a
sla a
sla a
sla a
ld b, a
; 16 in this class

sra b
sra b
sra b
sra b
sra b
sra b
sra b
; sra a ; forgo one shift right because structs are two bytes in size

ld hl, ultraball_class
add hl, bc
ld b, [hl]
xor a
cp b
jr z, ultraball_load
jp ultraball_class_selection


ultraball_load:
ld [hl], 0x1
inc [hl]
ld a, [hl]

RET

masterball_class_selection: