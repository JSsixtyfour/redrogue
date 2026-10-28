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
call GetStatUltraballCount  ; a = 5 Kanto stones, or 8 with Johto/Warp active
ld d, a
ld b, NUM_STAT_POKEBALL_CLASS
ld c, NUM_STAT_GREATBALL_CLASS
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
; d/e are the ultraball/masterball class sizes the class branches read after
; their `pop bc`. Both the Rare Lens lookup below (its farcall answers in e)
; and RollSpreadClass clobber them.
push de
call ItemSelectionRarityBonus
ld a, c
ld hl, ItemClassWidths
call RollSpreadClass         ; c = class 1-4
pop de
dec c
jp z, item_pokeball_class_selection
dec c
jp z, item_greatball_class_selection
dec c
jp z, item_ultraball_class_selection
jp item_masterball_class_selection

; pokeball 52 / great 77 / ultra 76 / master 51
ItemClassWidths:
	db 3, item_pokeball_odds + 1, item_greatball_odds + 1, item_ultraball_odds + 1, 0

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
jp ItemSelectionCheck

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
; index = (rand * count) >> 8, always < count (see the ultraball branch).
ldh   a, [hProduct+2]
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
jp ItemSelectionCheck

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
; index = (rand * count) >> 8, always < count - the clerk roller's 2026-09-28
; fix. rand * count / 255 returned count itself on a roll of 255 and read one
; past the list, which since SUN/DUSK/ICE follow the Kanto stones would hand a
; Kanto-only run a SUN_STONE.
ldh   a, [hProduct+2]
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
jp ItemSelectionCheck

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
; index = (rand * count) >> 8, always < count (see the ultraball branch).
ldh   a, [hProduct+2]
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
jp ItemSelectionCheck

; All four tiers share the same rejection budget and guaranteed fallback.
ItemSelectionCheck:
    call AllTMCheck
    and a
    jr z, ItemSelectionAccept
    ld hl, wItemSelectionRetryCount
    inc [hl]
    ld a, [hl]
    cp MAX_ITEM_SELECTION_RETRIES
    jp c, Random_Item_Selection
    jp ItemSelectionFindUnownedTM

ItemSelectionAccept:
    xor a
    ld [wItemSelectionRetryCount], a
    ld a, b
    ld [wRogueItem], a
    ret

; Exhaustive fallback after unlucky rolls: choose uniformly among unowned
; entries in tiers which still have nonzero probability. A zero roll through
; the same rarity calculation identifies the lowest eligible tier, including
; gym, Witch, mini-boss and Rare Lens bonuses. Never downgrade a gym to common.
; No new RAM: count on the first pass, pick an unbiased ordinal, then locate it.
; If every eligible TM/HM is owned, give a NUGGET instead of a useless duplicate.
ItemSelectionFindUnownedTM::
    ASSERT tm_greatball_class - tm_pokeball_class == NUM_TM_POKEBALL_CLASS
    ASSERT tm_ultraball_class - tm_greatball_class == NUM_TM_GREATBALL_CLASS
    ASSERT tm_masterball_class - tm_ultraball_class == NUM_TM_ULTRABALL_CLASS
    ASSERT money_classes - tm_masterball_class == NUM_TM_MASTERBALL_CLASS
    ASSERT BANK(tm_pokeball_class) == BANK(ItemSelectionFindUnownedTM)
    call ItemSelectionRarityBonus
    xor a
    ld hl, ItemClassWidths
    call RollSpreadClass
    ld a, c
    ld hl, tm_pokeball_class
    ld c, NUM_TM_POKEBALL_CLASS + NUM_TM_GREATBALL_CLASS + NUM_TM_ULTRABALL_CLASS + NUM_TM_MASTERBALL_CLASS
    dec a
    jr z, .countStart
    ld hl, tm_greatball_class
    ld c, NUM_TM_GREATBALL_CLASS + NUM_TM_ULTRABALL_CLASS + NUM_TM_MASTERBALL_CLASS
    dec a
    jr z, .countStart
    ld hl, tm_ultraball_class
    ld c, NUM_TM_ULTRABALL_CLASS + NUM_TM_MASTERBALL_CLASS
    dec a
    jr z, .countStart
    ld hl, tm_masterball_class
    ld c, NUM_TM_MASTERBALL_CLASS
.countStart
    push hl
    ld e, 0
.count
    ld b, [hl]
    inc hl
    call .checkOwned
    and a
    jr nz, .next
    inc e
.next
    dec c
    jr nz, .count
    pop hl
    ld a, e
    and a
    ld b, NUGGET
    jp z, ItemSelectionAccept
    ld c, e
    call Rangerandom
    ld e, a
.select
    ld b, [hl]
    inc hl
    call .checkOwned
    and a
    jr nz, .select
    ld a, e
    and a
    jp z, ItemSelectionAccept
    dec e
    jr .select
.checkOwned
    push hl
    push de
    call AllTMCheck
    pop de
    pop hl
    ret

; Shared by normal rolls and the exhaustive fallback; returns bonus in b and
; the existing random roll in c. Same-bank tables/calls; external helpers use
; their existing farcall convention. Does not consume another random number.
ItemSelectionRarityBonus:
; c = the roll, b = the rarity bonus. They used to be one byte (the bonus was
; added to the roll), which handed every point of bonus to masterball; the
; spread roll below splits it evenly over great, ultra and master.
ldh a, [hRandomAdd]
ld c, a

; bonus rarity check — existing gym bonus
ld a, [wItemBonusRarity]
ld b, a
; Witch prize b (PRIZE_RARITY_ITEM): extra item class bonus — larger b = better
; tier. PERMANENT (2026-09-02): does NOT gate on BIT_WITCH_ACCEPTED - once
; earned it applies to every item roll for the rest of the run.
; Each bonus skips only itself. These two used to jump straight to the class
; roll, so the mini-boss bonus needed the witch prize too and RARE LENS needed
; both.
ld a, [wWitchPrizesEarned]
and 1 << (PRIZE_RARITY_ITEM - 1)
jr z, .noWitchItemBonus
ld a, b
add 51             ; same bump as the gym leader bonus
jr nc, .witchItemDone
ld a, $FF
.witchItemDone
ld b, a
.noWitchItemBonus

; Mini-boss framework: stacks an ADDITIONAL bonus on top of wItemBonusRarity
; and any witch prize bonus above (see MINIBOSS_FRAMEWORK.md "rarity stacks
; additively").
ld a, [wRogueFlagsBitfield]
bit BIT_MINIBOSS_ACTIVE, a
jr z, .noMiniBossItemBonus
ld a, b
add MINIBOSS_ITEM_RARITY_BONUS
jr nc, .miniBossItemDone
ld a, $FF
.miniBossItemDone
ld b, a
.noMiniBossItemBonus

; RARE LENS: additional bonus stacked on top of wItemBonusRarity/witch/mini-boss
; above (same additive-stacking shape). Deliberately NOT the same raw number as
; RARE SCOPE's mon-side bonus: item_pokeball_odds is 51 here versus 127 on the
; mon side, so a flat bonus calibrated for one threshold would make the other
; threshold's pokeball tier unreachable (exactly what the witch-prize +51 a few
; lines above does to THIS threshold). This table is scaled to item_pokeball_odds
; instead - see KEY_ITEM_EFFECTS_PLAN_PC.md §3c. farcall clobbers bc, so b (the
; roll accumulator) is saved across it. This file is NOT in SECTION "rogue" with
; key_item_pocket.asm: relocated_home.asm, INCLUDEd just above it in main.asm,
; opens its own SECTION, so this lands in a different bank. It used to be a plain
; call, which ran whatever was mapped at that address here (fixed 2026-09-24).
push bc
ld a, RARE_LENS
ld [wCurItem], a
farcall GetKeyItemPowerInE     ; e = 0 (not active) or 1-3 (displayed tier)
ld a, e                        ; not a: Bankswitch returns the caller's bank in a
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
    ret

.RareLensBonusTable:
	db 12, 25, 38

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
    add a, item_pokeball_odds + 1   ; the whole pokeball band: a gym leader never gives a pokeball class TM
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
    sub a, item_pokeball_odds + 1   ; restores Bonus Rarity to normal
    ld [wItemBonusRarity], a
    pop af
    ld [wRogueDoorSelection], a
    ret
; ---------------------------------------------------------------------------
; GetStatUltraballCount
; OUTPUT: a = how many entries of stat_ultraball_class may be rolled: the 5
;         Kanto stones, or all 8 (+ SUN/DUSK/ICE) when the Johto or Time Warp
;         group is active. Shared by the route roller above and the Celadon
;         clerk (random_item_selection_mart.asm).
; PRESERVES: bc, de, hl (farcall clobbers bc/hl, so they are stacked)
; The mask comes back in e: RogueGetActiveGroupMask's `a` cannot survive a
; farcall (see RogueGetActiveGroupMaskFar), and rarity.asm is another bank.
; ---------------------------------------------------------------------------
GetStatUltraballCount:
	push bc
	push de
	push hl
	farcall RogueGetActiveGroupMaskFar ; e = active group mask
	ld a, e
	and (1 << BIT_GROUP_JOHTO) | (1 << BIT_GROUP_WARP)
	ld a, NUM_STAT_ULTRABALL_CLASS_KANTO ; ld leaves the flags from `and`
	jr z, .done
	ld a, NUM_STAT_ULTRABALL_CLASS
.done
	pop hl
	pop de
	pop bc
	ret
