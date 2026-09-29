; This code is meant to handle items generated for the pokemart
; The code outputs 10 item IDs into ram
; need to push bc and de
Random_Healing_Mart_Selection::
; output-list pointer arrives in de, not hl - farcall clobbers hl/bc to do the
; bank switch, so the caller can't pass it directly in hl
ld h, d
ld l, e
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
; index = (rand * count) >> 8, the product's high byte: always < count. It was
; rand * count / 255, which is count itself on a roll of 255 and read the item
; one past the class list (measured 2026-09-28: a stray stone and a stray id 99
; in 480 clerk items).
ldh   a,  [hProduct+2]
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
; output-list pointer arrives in de, not hl - same reason as Random_Healing_Mart_Selection above
ld h, d
ld l, e
ld a, 10

stattm_item_loop:
dec a

stattm_duplicate_repeat:
push af
push hl
; Stat item or TM, then the rarity class: two SEPARATE rolls. Both used to read
; the same hRandomAdd byte, so a stat item (byte <= $80) could never reach the
; ultra/master classes (stones, Rare Candy) and a TM (byte > $80) could never
; be pokeball/great class. Measured 2026-09-28 over 480 items: stones 0.2%,
; Rare Candy 0%, TMs 100% ultra/master. The odds are CLERK_* knobs in
; constants/balance_constants.asm.
call Random
cp CLERK_STAT_SHARE
jr c, stat_item_determineClassSlot

tm_item_determineClassSlot:
call Random                 ; preserves bc/de/hl
ld b, a
ld c, NUM_TM_POKEBALL_CLASS
ld hl, tm_pokeball_class
ld a, CLERK_TM_POKEBALL_ODDS
cp b
jr nc, stattm_item_selection
ld c, NUM_TM_GREATBALL_CLASS
ld hl, tm_greatball_class
ld a, CLERK_TM_GREATBALL_ODDS
cp b
jr nc, stattm_item_selection
ld a, CLERK_TM_ULTRABALL_ODDS
ld hl, tm_ultraball_class
ld c, NUM_TM_ULTRABALL_CLASS
cp b
jr nc, stattm_item_selection
ld hl, tm_masterball_class
ld c, NUM_TM_MASTERBALL_CLASS
jp stattm_item_selection

stat_item_determineClassSlot:
call Random
ld b, a
ld c, NUM_STAT_POKEBALL_CLASS
ld hl, stat_pokeball_class
ld a, CLERK_STAT_POKEBALL_ODDS
cp b
jr nc, stattm_item_selection
ld c, NUM_STAT_GREATBALL_CLASS
ld hl, stat_greatball_class
ld a, CLERK_STAT_GREATBALL_ODDS
cp b
jr nc, stattm_item_selection
ld a, CLERK_STAT_ULTRABALL_ODDS
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
; index = (rand * count) >> 8, the product's high byte: always < count. It was
; rand * count / 255, which is count itself on a roll of 255 and read the item
; one past the class list (measured 2026-09-28: a stray stone and a stray id 99
; in 480 clerk items).
ldh   a,  [hProduct+2]
ld c, a                     ; load offset to add to pointer, to get address
ld b, $0

pop hl                      ; class pointer array
add hl, bc                  ; add item offset to pointer

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

.stattm_duplicate_check_loop
xor a
cp d    ; see if we reached end of prior items
jr z, .nonrepeat_item       ; take if we've reached end of prior items

dec d                       ; decrease amount of items left
dec hl                      ; work one back through prior items
ld b, [hl]                  ; load prior item
ld a, c                     ; put current item in a
cp b                        ; compare current and prior item
jr nz, .stattm_duplicate_check_loop    ; if not the same, do the next one
pop af
pop hl                      ; restore hl
jp stattm_duplicate_repeat         ; if we're here it means the result was zero, thus they are identical, so restart the whole process for this item

.nonrepeat_item
pop af                      ; load loop count
pop hl                      ; load list
inc hl                      ; increase to next position in list
ld b, 0
cp b                        ; see if loop reached end
jr nz, stattm_item_loop_jump    ; jump to get next item if not done
ld [hl], $FF                ; add FF to end the list

RET

stattm_item_loop_jump:
jp stattm_item_loop