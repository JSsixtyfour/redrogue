; This code is meant to handle any time an item is randomly generated
; The code outputs an item ID
; a = Specific type of item: HEALING, STAT, TM, MONEY
Random_Item_Selection::
call Random
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

; bonus rarity check
ld a, [wItemBonusRarity]
add a, b
ld b, a
jr nc, .no_overflow
ld b, $FF

.no_overflow
ld a, item_pokeball_odds
cp b
jr nc, item_pokeball_class_selection
ld a, item_greatball_odds
cp b
jr nc, item_greatball_class_selection
ld a, item_ultraball_odds
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

ld a, $FF                   ; load 255
ldh [hDivisor], a           ; place 255 as divisor
ld b, $2                    ; number of bytes
call Divide
ldh   a, [hQuotient+3]      ; load in quotient
ld c, a                     ; load offset to add to pointer, to get address
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
ld b, [hl]                  ; load item from address
call AllTMCheck
cp 0
jp nz, Random_Item_Selection    ; if repeat TM flag set, retry
ld a, b                     ; place item in a
ld [wRogueItem], a          ; place item in 

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

ld a, $FF                   ; load 255
ldh [hDivisor], a           ; place 255 as divisor
ld b, $2                    ; number of bytes
call Divide
ldh   a, [hQuotient+3]      ; load in quotient
ld c, a                     ; load offset to add to pointer, to get address
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
ld b, [hl]                  ; load item from address
call AllTMCheck
cp 0
jp nz, Random_Item_Selection    ; if repeat TM flag set, retry
ld a, b                     ; place item in a
ld [wRogueItem], a          ; place item in 

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

ld a, $FF                   ; load 255
ldh [hDivisor], a           ; place 255 as divisor
ld b, $2                    ; number of bytes
call Divide
ldh   a, [hQuotient+3]      ; load in quotient
ld c, a                     ; load offset to add to pointer, to get address
ld b, $0

ld hl,item_ultraball_classes ; class pointer array
ld a, [wRogueDoorSelection] ; load current door selection
sla a                       ; multiply by two, because pointers are two bytes, get offset
ld d, 0                     ; clear out
ld e, a                     ; place offset into e
add hl, de                  ; add offset to pointer
ld a, [hli]                 ; load first part of pointer into a and increment
ld h, [hl]                  ; load second part of pointer
ld l, a                     ; place first part into l
add hl, bc                  ; add item offset to pointer


.item_ultraball_load
ld b, [hl]                  ; load item from address
call AllTMCheck
cp 0
jp nz, Random_Item_Selection    ; if repeat TM flag set, retry
ld a, b                     ; place item in a
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
ldh [hDivisor], a           ; place 255 as divisor
ld b, $2                    ; number of bytes
call Divide
ldh   a, [hQuotient+3]      ; load in quotient
ld c, a                     ; load offset to add to pointer, to get address
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
ld b, [hl]                  ; load item from address
call AllTMCheck
cp 0
jp nz, Random_Item_Selection    ; if repeat TM flag set, retry
ld a, b                     ; place item in a
ld [wRogueItem], a          ; place item in 

RET

; a check to see if TM or HM is already owned by player
; returns a 0 if no and a 1 if yes
; b = item ID
; UPDATE, need a way to check if evolution
AllTMCheck::
    ld a, $c3       ; last item before TM and HM
    cp b            ; compare to current item
    jr nc, .notInBox          ; if b is not greater than a, skip
    ld a, $FA       ; last item before TM and HM
    cp b            ; compare to current item
    jr c, .notInBox  ; if greater than last TM, skip
    
    .tm
    ld hl, wNumBagItems
    .loop
	inc hl
	ld a, [hli]
	cp $ff
	jr z, .notInBag
	cp b
	jr nz, .loop
	ld a, 1
	ret
    .notInBag
    ld hl, wNumBoxItems
    .loop2
	inc hl
	ld a, [hli]
	cp $ff
	jr z, .notInBox
	cp b
	jr nz, .loop2
	ld a, 1
	ret
    .notInBox
	ld a, 0
	ret

GymLeaderRandomItem::
    ld a, [wItemBonusRarity]
    add a, item_pokeball_odds       ; increased rarity for gym leaders, prevents a pokeball class TM
    ld [wItemBonusRarity], a
    ld a, TM                        ; set to generate a random TM
    ld [wRogueDoorSelection], a
    farcall Random_Item_Selection
    ld a, [wItemBonusRarity]
    sub a, item_pokeball_odds       ; restores Bonus Rarity to normal
    ld [wItemBonusRarity], a
    ret