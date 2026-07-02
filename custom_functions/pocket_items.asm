; custom_functions/pocket_items.asm
; Recovery, Stat, Valuable pocket tables, give/remove, and display list builders.
; All entry points use wCurItem/wItemQuantity (set before farcall by GiveItem)
; instead of b/c registers — farcall clobbers those on entry.

RecoveryItemTable::
    db POTION, SUPER_POTION, HYPER_POTION, MAX_POTION, FULL_RESTORE
    db ANTIDOTE, BURN_HEAL, ICE_HEAL, AWAKENING, PARLYZ_HEAL, FULL_HEAL
    db REVIVE, MAX_REVIVE
    db FRESH_WATER, SODA_POP, LEMONADE
    db ETHER, MAX_ETHER, ELIXER, MAX_ELIXER
    db POKE_FLUTE  ; infinite use — count never decremented on field use
    db $FF

StatItemTable::
    db MOON_STONE, FIRE_STONE, THUNDER_STONE, WATER_STONE, LEAF_STONE
    db HP_UP, PROTEIN, IRON, CARBOS, CALCIUM
    db RARE_CANDY, PP_UP
    db $FF

ValuableItemTable::
    db PEARL, BIG_PEARL, NUGGET, BIG_NUGGET
    db $FF

; ============================================================
; _ScanTable (same-bank private)
; Scan a $FF-terminated table for wCurItem.
; INPUT: hl = table address
; OUTPUT: carry set = found, c = index; carry clear = not found
; CLOBBERS: a, c, d
; ============================================================
_ScanTable:
    ld a, [wCurItem]
    ld d, a
    ld c, 0
.scan
    ld a, [hli]
    cp $FF
    jr z, .no
    cp d
    jr z, .yes
    inc c
    jr .scan
.yes
    scf
    ret
.no
    and a
    ret

; ============================================================
; GiveRecoveryItem / GiveStatItem / GiveValuableItem
; Add wItemQuantity of wCurItem to the count array.
; Self-contained: re-scans table (farcall clobbers c on entry).
; OUTPUT: carry set = item was in this pocket and stored;
;         carry clear = not in this pocket
; ============================================================
GiveRecoveryItem::
    ld hl, RecoveryItemTable
    call _ScanTable
    ret nc
    ld hl, wRecoveryItemCounts
    jr _AddToCount

GiveStatItem::
    ld hl, StatItemTable
    call _ScanTable
    ret nc
    ld hl, wStatItemCounts
    jr _AddToCount

GiveValuableItem::
    ld hl, ValuableItemTable
    call _ScanTable
    ret nc
    ld hl, wValuableItemCounts
    ; fallthrough

_AddToCount:
    ld b, 0
    add hl, bc          ; hl = &count[c]
    ld a, [wItemQuantity]
    add [hl]
    cp 100
    jr c, .ok
    ld a, 99
.ok
    ld [hl], a
    scf
    ret

; ============================================================
; RemovePocketItem — decrement count by wItemQuantity (0=remove all).
; Poke Flute is never decremented.
; ============================================================
RemovePocketItem::
    ld a, [wCurItem]
    cp POKE_FLUTE
    ret z
    ld hl, RecoveryItemTable
    call _ScanTable
    jr c, .removeRecovery
    ld hl, StatItemTable
    call _ScanTable
    jr c, .removeStat
    ld hl, ValuableItemTable
    call _ScanTable
    ret nc
    ld hl, wValuableItemCounts
    jr .doRemove
.removeRecovery
    ld hl, wRecoveryItemCounts
    jr .doRemove
.removeStat
    ld hl, wStatItemCounts
.doRemove
    ld b, 0
    add hl, bc
    ld a, [wItemQuantity]
    and a
    jr z, .all
    ld b, a
    ld a, [hl]
    sub b
    jr nc, .store
    xor a
    jr .store
.all
    xor a
.store
    ld [hl], a
    ret

; ============================================================
; GetPocketItemCount — returns count of wCurItem, 0 if uncategorized.
; ============================================================
GetPocketItemCount::
    ld hl, RecoveryItemTable
    call _ScanTable
    jr c, .recovery
    ld hl, StatItemTable
    call _ScanTable
    jr c, .stat
    ld hl, ValuableItemTable
    call _ScanTable
    jr nc, .zero
    ld hl, wValuableItemCounts
    jr .read
.recovery
    ld hl, wRecoveryItemCounts
    jr .read
.stat
    ld hl, wStatItemCounts
.read
    ld b, 0
    add hl, bc
    ld a, [hl]
    ret
.zero
    xor a
    ret

; ============================================================
; BuildXxxPocketList — scan count array + item table, emit entries for
; items with count > 0 into the display buffer.
; HRAM used: hSpriteOffset (remaining iterations), hSpriteHeight/Width (out ptr)
; ============================================================
BuildRecoveryPocketList::
    ld a, NUM_RECOVERY_ITEMS
    ldh [hSpriteOffset], a
    ld hl, RecoveryItemTable
    ld de, wRecoveryItemCounts
    ld a, HIGH(wRecoveryPocketBuf + 1)
    ldh [hSpriteHeight], a
    ld a, LOW(wRecoveryPocketBuf + 1)
    ldh [hSpriteWidth], a
    ld b, 0
    call _BuildPocketScan
    ld a, b
    ld [wRecoveryPocketBuf], a
    ret

BuildStatPocketList::
    ld a, NUM_STAT_ITEMS
    ldh [hSpriteOffset], a
    ld hl, StatItemTable
    ld de, wStatItemCounts
    ld a, HIGH(wStatPocketBuf + 1)
    ldh [hSpriteHeight], a
    ld a, LOW(wStatPocketBuf + 1)
    ldh [hSpriteWidth], a
    ld b, 0
    call _BuildPocketScan
    ld a, b
    ld [wStatPocketBuf], a
    ret

BuildValuablePocketList::
    ld a, NUM_VALUABLE_ITEMS
    ldh [hSpriteOffset], a
    ld hl, ValuableItemTable
    ld de, wValuableItemCounts
    ld a, HIGH(wValuablePocketBuf + 1)
    ldh [hSpriteHeight], a
    ld a, LOW(wValuablePocketBuf + 1)
    ldh [hSpriteWidth], a
    ld b, 0
    call _BuildPocketScan
    ld a, b
    ld [wValuablePocketBuf], a
    ret

; ============================================================
; _BuildPocketScan (private)
; Walk item table (hl) and count array (de) in parallel.
; Emit {item_id, count} pairs to output pointer stored in HRAM.
; HRAM: hSpriteOffset = remaining count, hSpriteHeight:hSpriteWidth = out ptr.
; b = output item count (increments here). Caller writes to buf[0] after.
; ============================================================
_BuildPocketScan:
.loop
    ldh a, [hSpriteOffset]
    and a
    jr z, .done
    ; read item_id and count
    ld a, [hli]         ; a = item_id, hl advances
    ld c, a             ; c = item_id
    ld a, [de]
    inc de              ; a = count, de advances
    and a
    jr z, .skip
    ; emit entry: write to output pointer
    push hl
    push de
    push bc             ; c = item_id, a = count
    push af             ; save count
    ldh a, [hSpriteHeight]
    ld h, a
    ldh a, [hSpriteWidth]
    ld l, a             ; hl = output write ptr
    pop af              ; count
    ld d, a             ; d = count (temp)
    ld a, c             ; item_id
    ld [hli], a
    ld a, d             ; count
    ld [hli], a
    ld a, h
    ldh [hSpriteHeight], a
    ld a, l
    ldh [hSpriteWidth], a
    pop bc
    pop de
    pop hl
    inc b               ; output item count++
.skip
    ldh a, [hSpriteOffset]
    dec a
    ldh [hSpriteOffset], a
    jr .loop
.done
    ; Write $FF sentinel at current output pointer
    ldh a, [hSpriteHeight]
    ld h, a
    ldh a, [hSpriteWidth]
    ld l, a
    ld a, $FF
    ld [hl], a
    ret
