; This code is meant to handle any time an item is randomly generated for the player to pick up
; The code outputs an item ID into ram
; need to push bc and de

Random_Item_Selection::
ld a, [wRogueDoorSelection]
ld b, HEALING
cp a, b
jr z, healing_items
ld b, STAT
cp a, b
jr z, stat_items
ld b, TM
cp a, b
jr z, tm_items 

.money_items
ld b, NUM_MONEY_POKEBALL_CLASS
ld c, NUM_MONEY_GREATBALL_CLASS 
ld d, NUM_MONEY_ULTRABALL_CLASS 
ld e, NUM_MONEY_MASTERBALL_CLASS
push bc
jp item_determineClassSlot

healing_items:
ld b, NUM_HEALING_POKEBALL_CLASS
ld c, NUM_HEALING_GREATBALL_CLASS 
ld d, NUM_HEALING_ULTRABALL_CLASS 
ld e, NUM_HEALING_MASTERBALL_CLASS
push bc
jp item_determineClassSlot

stat_items:
ld b, NUM_STAT_POKEBALL_CLASS
ld c, NUM_STAT_GREATBALL_CLASS 
ld d, NUM_STAT_ULTRABALL_CLASS 
ld e, NUM_STAT_MASTERBALL_CLASS
push bc
jp item_determineClassSlot

tm_items:
ld b, NUM_TM_POKEBALL_CLASS
ld c, NUM_TM_GREATBALL_CLASS 
ld d, NUM_TM_ULTRABALL_CLASS 
ld e, NUM_TM_MASTERBALL_CLASS
push bc


item_determineClassSlot:
ldh a, [hRandomAdd]
ld  b, a
ld hl, item_class_odds
ld a, [hli]
cp b
jr nc, item_pokeball_class_selection
inc hl
ld a, [hli]
cp b
jr nc, item_greatball_class_selection
inc hl
ld a, [hli]
cp b
jr nc, item_ultraball_class_selection_jump
jp item_masterball_class_selection

item_ultraball_class_selection_jump:
jp item_ultraball_class_selection

; common
item_pokeball_class_selection:
call Random                 ; get a random number to determine item
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
pop bc
ld a, b                     ; multiply by amount of this class
ldh [hMultiplier], a        ; place amount of class in multiplier
call Multiply               ; multiply random number by amount in class
ldh   a,  [hProduct+2]   ; load product into a
ldh [hDividend], a          ; place product in dividend
ldh   a, [hProduct+3]
ldh [hDividend+1], a
;ldh   a, [hMultiplicand+2]
;ldh [hDividend+2], a

ld a, $FF                   ; load 255
ldh [hDivisor], a           ; place 255 as divisor
ld b, $2                    ; number of bytes
call Divide
ldh   a, [hQuotient+3]      ; load in quotient
ldh [hMultiplicand], a      ; set quotient as multiplier
ld a, $2
ldh [hMultiplier], a        ; load 2, which is the size of each struct in array
xor a
ldh [hMultiplicand+1], a    ; clear out other digits
ldh [hMultiplicand+2], a
call Multiply               ; multiply result by size of struct to add to base address
ld hl, hProduct+1           ; load address of offset
ld c,[hl]                   ; load offset to add to pointer, to get address
ld b, $0

ld hl,item_pokeball_classes ; class pointer array
ld a, [wRogueDoorSelection] ; load current door selection
sla a                       ; multiply by two, because pointers are two bytes, get offset
ld d, 0                     ; clear out
ld e, a                     ; place offset into e
add hl, de                  ; add offset to pointer
ld a, [hli]                 ; load first part of pointer into a and increment
ld h, [hl]                  ; load second part of point
ld l, a                     ; place first part into l
add hl, bc                  ; add item offset to pointer


.item_pokeball_load
ld a, [hl]                  ; load item from address
ld [wRogueItem], a            ; place item in 

RET

; rare

item_greatball_class_selection:
call Random
ldh [hMultiplicand+2], a
xor a
ldh [hMultiplicand], a
ldh [hMultiplicand+1], a
pop bc
ld a, c                     ; multiply by amount of this class
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

ld hl,item_greatball_classes ; class pointer array
ld a, [wRogueDoorSelection] ; load current door selection
sla a                       ; multiply by two, because pointers are two bytes, get offset
ld d, 0                     ; clear out
ld e, a                     ; place offset into e
add hl, de                  ; add offset to pointer
ld a, [hli]                 ; load first part of pointer into a and increment
ld h, [hl]                  ; load second part of point
ld l, a                     ; place first part into l
add hl, bc                  ; add item offset to pointer

.item_greatball_load
ld a, [hl]                  ; load item from address
ld [wRogueItem], a            ; place item in 

RET

item_ultraball_class_selection:

call Random
ldh [hMultiplicand+2], a
xor a
ldh [hMultiplicand], a
ldh [hMultiplicand+1], a
pop bc
ld a, d                     ; multiply by amount of this class
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

ld hl,item_ultraball_classes ; class pointer array
ld a, [wRogueDoorSelection] ; load current door selection
sla a                       ; multiply by two, because pointers are two bytes, get offset
ld d, 0                     ; clear out
ld e, a                     ; place offset into e
add hl, de                  ; add offset to pointer
ld a, [hli]                 ; load first part of pointer into a and increment
ld h, [hl]                  ; load second part of point
ld l, a                     ; place first part into l
add hl, bc                  ; add item offset to pointer


.item_ultraball_load
ld a, [hl]                  ; load item from address
ld [wRogueItem], a          ; place item in 

RET

item_masterball_class_selection:
call Random                 ; get a random number to determine item
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
pop bc
ld a, e                     ; multiply by amount of this class
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
ld hl, hProduct+1           ; load address of offset
ld c,[hl]                   ; load offset to add to pointer, to get address
ld b, $0

ld hl,item_masterball_classes ; class pointer array
ld a, [wRogueDoorSelection] ; load current door selection
sla a                       ; multiply by two, because pointers are two bytes, get offset
ld d, 0                     ; clear out
ld e, a                     ; place offset into e
add hl, de                  ; add offset to pointer
ld a, [hli]                 ; load first part of pointer into a and increment
ld h, [hl]                  ; load second part of point
ld l, a                     ; place first part into l
add hl, bc                  ; add item offset to pointer


.item_masterball_load
ld a, [hl]                  ; load item from address
ld [wRogueItem], a            ; place item in 

RET