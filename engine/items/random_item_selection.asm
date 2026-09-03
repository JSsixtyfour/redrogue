; This code is meant to handle any time an item is randomly generated
; The code outputs an item ID
; a = Specific type of item: HEALING, STAT, TM, MONEY
DEF MAX_ITEM_SELECTION_RETRIES EQU 20
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

; bonus rarity check — existing gym bonus
ld a, [wItemBonusRarity]
add a, b
ld b, a
jr nc, .no_overflow1
ld b, $FF
.no_overflow1
; Witch prize b (PRIZE_RARITY_ITEM): extra item class bonus — larger b = better
; tier. PERMANENT (2026-09-02): does NOT gate on BIT_WITCH_ACCEPTED - once
; earned it applies to every item roll for the rest of the run.
ld a, [wWitchPrizesEarned]
and 1 << (PRIZE_RARITY_ITEM - 1)
jr z, .no_overflow
ld a, b
add 51             ; same bump as the gym leader bonus
jr nc, .witchItemDone
ld a, $FF
.witchItemDone
ld b, a

; Mini-boss framework: stacks an ADDITIONAL bonus on top of wItemBonusRarity
; and any witch prize bonus above (see MINIBOSS_FRAMEWORK.md "rarity stacks
; additively").
ld a, [wRogueFlagsBitfield]
bit BIT_MINIBOSS_ACTIVE, a
jr z, .no_overflow
ld a, b
add MINIBOSS_ITEM_RARITY_BONUS
jr nc, .miniBossItemDone
ld a, $FF
.miniBossItemDone
ld b, a

; RARE LENS: additional bonus stacked on top of wItemBonusRarity/witch/mini-boss
; above (same additive-stacking shape). Deliberately NOT the same raw number as
; RARE SCOPE's mon-side bonus: item_pokeball_odds is 51 here versus 127 on the
; mon side, so a flat bonus calibrated for one threshold would make the other
; threshold's pokeball tier unreachable (exactly what the witch-prize +51 a few
; lines above does to THIS threshold). This table is scaled to item_pokeball_odds
; instead - see KEY_ITEM_EFFECTS_PLAN_PC.md §3c. GetKeyItemPower clobbers bc, so
; b (the roll accumulator) is saved across it. This file and key_item_pocket.asm
; are both in SECTION "rogue", so a plain call reaches it, no farcall needed.
push bc
ld a, RARE_LENS
ld [wCurItem], a
call GetKeyItemPower           ; a = 0 (not active) or 1-3 (displayed tier)
pop bc
and a
jr z, .no_overflow
dec a
ld hl, .RareLensBonusTable
ld e, a
ld d, 0
add hl, de
ld a, [hl]
add b
jr nc, .rareLensDone
ld a, $FF
.rareLensDone
ld b, a

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

.RareLensBonusTable:
	db 12, 25, 38

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
ld c, a                     ; high byte of product = floor(random*N/256), always in [0,N-1]
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
and a
jr z, .item_pokeball_accept  ; not owned - take it
ld hl, wItemSelectionRetryCount
inc [hl]
ld a, [hl]
cp MAX_ITEM_SELECTION_RETRIES
jp c, Random_Item_Selection  ; still under the cap - retry
; retry cap hit - give up and accept the (possibly-owned) item anyway
.item_pokeball_accept
xor a
ld [wItemSelectionRetryCount], a
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
and a
jr z, .item_greatball_accept ; not owned - take it
ld hl, wItemSelectionRetryCount
inc [hl]
ld a, [hl]
cp MAX_ITEM_SELECTION_RETRIES
jp c, Random_Item_Selection  ; still under the cap - retry
; retry cap hit - give up and accept the (possibly-owned) item anyway
.item_greatball_accept
xor a
ld [wItemSelectionRetryCount], a
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
and a
jr z, .item_ultraball_accept ; not owned - take it
ld hl, wItemSelectionRetryCount
inc [hl]
ld a, [hl]
cp MAX_ITEM_SELECTION_RETRIES
jp c, Random_Item_Selection  ; still under the cap - retry
; retry cap hit - give up and accept the (possibly-owned) item anyway
.item_ultraball_accept
xor a
ld [wItemSelectionRetryCount], a
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
and a
jr z, .item_masterball_accept ; not owned - take it
ld hl, wItemSelectionRetryCount
inc [hl]
ld a, [hl]
cp MAX_ITEM_SELECTION_RETRIES
jp c, Random_Item_Selection  ; still under the cap - retry
; retry cap hit - give up and accept the (possibly-owned) item anyway
.item_masterball_accept
xor a
ld [wItemSelectionRetryCount], a
ld a, b                     ; place item in a
ld [wRogueItem], a          ; place item in

RET

; a check to see if TM or HM is already owned by player
; returns a 0 if no and a 1 if yes
; b = item ID on entry
AllTMCheck::
    ld a, $c3       ; first TM item ID minus 1
    cp b
    jr nc, .notOwned          ; b <= $c3: not a TM/HM
    ld a, $FA       ; last TM/HM item ID
    cp b
    jr c, .notOwned           ; b > $FA: beyond TM/HM range
    ; TM/HM: check sTMBitfield via HasTMHM. HasTMHM lives in a different bank
    ; (the rogue bank) than this routine, so it MUST be reached via farcall -
    ; a plain `call` would jump to this bank's address and run garbage. farcall
    ; clobbers b, so pass the item ID through wCurItem (HasTMHM's farcall-safe
    ; input convention), not b.
    ld a, b
    ld [wCurItem], a
    push bc                  ; farcall clobbers b; callers reuse it as the item ID
    farcall HasTMHM          ; Z = not owned, NZ = owned (Bankswitch preserves flags)
    pop bc
    jr z, .notOwned
    ld a, 1
    ret
.notOwned
    ld a, 0
    ret

GymLeaderRandomItem::
    ld a, [wItemBonusRarity]
    add a, item_pokeball_odds       ; increased rarity for gym leaders, prevents a pokeball class TM
    ld [wItemBonusRarity], a
    ld a, [wRogueDoorSelection]
    push af                         ; restored below via pop - this call forces TM
                                     ; regardless of which door was actually
                                     ; picked, and the next route's own roll
                                     ; must not be left stuck on TM
    ld a, TM                        ; set to generate a random TM
    ld [wRogueDoorSelection], a
    farcall Random_Item_Selection
    ld a, [wItemBonusRarity]
    sub a, item_pokeball_odds       ; restores Bonus Rarity to normal
    ld [wItemBonusRarity], a
    pop af
    ld [wRogueDoorSelection], a
    ret