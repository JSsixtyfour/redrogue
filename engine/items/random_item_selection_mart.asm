; This code is meant to handle items generated for the pokemart
; The code outputs 10 item IDs into ram
; need to push bc and de
Random_Healing_Mart_Selection::
ld a, 10

healing_item_loop:
dec a
duplicate_repeat:
push af
push hl
call Random

healing_item_determineClassSlot:
ldh a, [hRandomAdd]
ld b, a
ld c, NUM_HEALING_POKEBALL_CLASS
ld hl, healing_pokeball_class
ld a, item_pokeball_odds
cp b
jr nc, healing_item_selection
ld c, NUM_HEALING_GREATBALL_CLASS
ld hl, healing_greatball_class
ld a, item_greatball_odds
cp b
jr nc, healing_item_selection
ld a, item_ultraball_odds
ld hl, healing_ultraball_class
ld c, NUM_HEALING_ULTRABALL_CLASS
cp b
jr nc, healing_item_selection
ld hl, healing_masterball_class
ld c, NUM_HEALING_MASTERBALL_CLASS

healing_item_selection:
push hl
push bc
call Random                 ; get a random number to determine item
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
pop bc
ld a, c                     ; multiply by amount of this class
ldh [hMultiplier], a        ; place amount of class in multiplier
call Multiply               ; multiply random number by amount in class
ldh   a,  [hProduct+2]      ; load product into a
ldh [hDividend], a          ; place product in dividend
ldh   a, [hProduct+3]
ldh [hDividend+1], a

ld a, $FF                   ; load 255
ldh [hDivisor], a           ; place 255 as divisor
ld b, $2                    ; number of bytes
call Divide
ldh   a, [hQuotient+3]      ; load in quotient
ld c, a                     ; load offset to add to pointer, to get address
ld b, $0

pop hl                      ; class pointer array
add hl, bc                  ; add item offset to pointer

.healing_item_load
ld c, [hl]                  ; load item from address

pop hl
ld [hl], c                  ; load item to list
pop af
push hl

push af
ld d, a
ld a, $9
sub a, d
ld d, a

.duplicate_check_loop
xor a
cp d    ; see if we reached end of prior items
jr z, .nonrepeat_item       ; take if we've reached end of prior items

dec d                       ; decrease amount of items left
dec hl                      ; work one back through prior items
ld b, [hl]                  ; load prior item
ld a, c                     ; put current item in a
cp b                        ; compare current and prior item
jr nz, .duplicate_check_loop    ; if not the same, do the next one
pop af
pop hl                      ; restore hl
jp duplicate_repeat         ; if we're here it means the result was zero, thus they are identical, so restart the whole process for this item

.nonrepeat_item
pop af                      ; load loop count
pop hl                      ; load list
inc hl                      ; increase to next position in list
ld b, 0
cp b                        ; see if loop reached end
jr nz, healing_item_loop    ; jump to get next item if not done
ld [hl], $FF                ; add FF to end the list

RET

Random_StatTM_Mart_Selection::
ld a, 10

stattm_item_loop:
add a, -1
push af
push hl 
call Random
ldh a, [hRandomAdd]
ld b, a
ld a, $80
cp b
jr nc, stat_item_determineClassSlot

tm_item_determineClassSlot:
ldh a, [hRandomAdd]
ld b, a
ld c, NUM_TM_POKEBALL_CLASS
ld hl, tm_pokeball_class
ld a, item_pokeball_odds
cp b
jr nc, stattm_item_selection
ld c, NUM_TM_GREATBALL_CLASS
ld hl, tm_greatball_class
ld a, item_greatball_odds
cp b
jr nc, stattm_item_selection
ld a, item_ultraball_odds
ld hl, tm_ultraball_class
ld c, NUM_TM_ULTRABALL_CLASS
cp b
jr nc, stattm_item_selection
ld hl, tm_masterball_class
ld c, NUM_TM_MASTERBALL_CLASS
jp stattm_item_selection

stat_item_determineClassSlot:
ldh a, [hRandomAdd]
ld b, a
ld c, NUM_STAT_POKEBALL_CLASS
ld hl, stat_pokeball_class
ld a, item_pokeball_odds
cp b
jr nc, stattm_item_selection
ld c, NUM_STAT_GREATBALL_CLASS
ld hl, stat_greatball_class
ld a, item_greatball_odds
cp b
jr nc, stattm_item_selection
ld a, item_ultraball_odds
ld hl, stat_ultraball_class
ld c, NUM_STAT_ULTRABALL_CLASS
cp b
jr nc, stattm_item_selection
ld hl, stat_masterball_class
ld c, NUM_STAT_MASTERBALL_CLASS

stattm_item_selection:
push hl
push bc
call Random                 ; get a random number to determine item
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
pop bc
ld a, c                     ; multiply by amount of this class
ldh [hMultiplier], a        ; place amount of class in multiplier
call Multiply               ; multiply random number by amount in class
ldh   a,  [hProduct+2]      ; load product into a
ldh [hDividend], a          ; place product in dividend
ldh   a, [hProduct+3]
ldh [hDividend+1], a

ld a, $FF                   ; load 255
ldh [hDivisor], a           ; place 255 as divisor
ld b, $2                    ; number of bytes
call Divide
ldh   a, [hQuotient+3]      ; load in quotient
ld c, a                     ; load offset to add to pointer, to get address
ld b, $0

pop hl                      ; class pointer array
add hl, bc                  ; add item offset to pointer

.stattm_item_load
ld a, [hl]                  ; load item from address
pop hl
ld [hli], a                 ; load item to list
pop af                      ; load loop count
ld b, 0
cp b                        ; see if loop reached end
jr nz, stattm_item_loop_jump     ; jump to get next item if not done
ld [hl], $FF                   ; add FF to end the list

RET

stattm_item_loop_jump:
jp stattm_item_loop