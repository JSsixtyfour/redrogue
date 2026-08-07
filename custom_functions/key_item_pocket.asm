; custom_functions/key_item_pocket.asm
;
; Key items: paired own+active bits in sKeyItemsBitfield byte 0.
;   Even bit = owned, odd bit = active (in bag, usable).
;   Active bit is always own_bit + 1 (callers can inc c to get it).
;
; GiveItem auto-activates if < KEY_ITEM_MAX_ACTIVE items are active.
; PC WITHDRAW/DEPOSIT for manual management.
; Max 3 items active at once. Effects check IsKeyItemActive, not ownership.
;
; All functions read wCurItem (not b) — farcall clobbers b.

KeyItemPocketTable::
    db LEFTOVERS,   KEY_ITEM_BIT_LEFTOVERS_OWNED
    db PP_TONIC,    KEY_ITEM_BIT_PP_TONIC_OWNED
    db KO_DEFIANCE, KEY_ITEM_BIT_KO_DEFIANCE_OWNED
    db EXP_ALL,     KEY_ITEM_BIT_EXP_ALL_OWNED
    db SHINY_CHARM,   KEY_ITEM_BIT_SHINY_CHARM_OWNED
    db AMULET_COIN,   KEY_ITEM_BIT_AMULET_COIN_OWNED
    db TURN_REWIND,   KEY_ITEM_BIT_TURN_REWIND_OWNED
    db RARE_SCOPE,    KEY_ITEM_BIT_RARE_SCOPE_OWNED
    db RARE_LENS,     KEY_ITEM_BIT_RARE_LENS_OWNED
    db DV_BOOSTER,    KEY_ITEM_BIT_DV_BOOSTER_OWNED
    db STAT_BOOSTER,  KEY_ITEM_BIT_STAT_BOOSTER_OWNED
    db DOOR_DICE,     KEY_ITEM_BIT_DOOR_DICE_OWNED
    db MON_DICE,      KEY_ITEM_BIT_MON_DICE_OWNED
    db ITEM_DICE,     KEY_ITEM_BIT_ITEM_DICE_OWNED
    db ELEMENT_PRISM, KEY_ITEM_BIT_ELEMENT_PRISM_OWNED
    db $FF

; ============================================================
; IsKeyPocketItem — does wCurItem belong in the key items pocket?
; OUTPUT: carry set = yes, c = own_bit_index; carry clear = no
; ============================================================
IsKeyPocketItem::
    ld a, [wCurItem]
    ld d, a
    ld hl, KeyItemPocketTable
.scan
    ld a, [hli]
    cp $FF
    jr z, .no
    cp d
    jr z, .yes
    inc hl
    jr .scan
.yes
    ld c, [hl]    ; c = own_bit_index
    scf
    ret
.no
    and a
    ret

; ============================================================
; GetKeyItemTierForCurItem — upgrade tier (0-3) of wCurItem, 0 if it is not a
; key item. Lives here rather than beside the Credit Exchange's own copy so the
; bag/PC display (custom_functions/tm_bag.asm) can reach it with a plain call:
; both are in the "rogue" bank, whereas engine/events/credit_mart.asm is not,
; and farcall's Bankswitch destroys bc before the callee runs, so an index
; cannot be passed across banks in c.
;
; sKeyItemTiers packs 2 bits per item: item N -> bits 2N/2N+1 of byte N>>2.
; IsKeyPocketItem returns the OWN bit index (0,2,4,...), so index = c >> 1.
; OUTPUT: a = tier (0-3). Clobbers bc/de/hl.
; ============================================================
GetKeyItemTierForCurItem::
    call IsKeyPocketItem
    jr nc, .notKeyItem
    srl c                     ; c = key item index
    ld a, c
    and 3
    add a
    ld b, a                   ; b = shift = (index & 3) * 2
    ld a, c
    srl a
    srl a
    ld l, a                   ; byte offset = index >> 2
    ld h, 0
    ld de, sKeyItemTiers
    add hl, de
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, [hl]
    ld c, a
    xor a
    ld [rRAMG], a             ; never leave SRAM enabled across a return
    ld a, c
    inc b
.shift
    dec b
    jr z, .gotTier
    srl a
    jr .shift
.gotTier
    and 3
    ret
.notKeyItem
    xor a
    ret

; ============================================================
; _KeyBitInfo (same-bank private)
; INPUT: c = bit_index (0-7); SRAM must be enabled by caller.
; OUTPUT: hl = &sKeyItemsBitfield[c>>3], b = 1<<(c&7)
; ============================================================
_KeyBitInfo:
    ld a, c
    and 7
    ld d, a
    inc d
    ld a, 1
.shift
    dec d
    jr z, .done
    rlca
    jr .shift
.done
    ld b, a
    ld a, c
    srl a
    srl a
    srl a
    ld hl, sKeyItemsBitfield
    ld d, 0
    ld e, a
    add hl, de
    ret

; ============================================================
; _CountActive (same-bank private; SRAM must be enabled)
; Count how many key items have their active bit set (bits 1,3,5,7).
; OUTPUT: a = count (0 to KEY_ITEM_MAX_ACTIVE)
; ============================================================
_CountActive:
    ld hl, sKeyItemsBitfield
    ld a, [hl]
    ld b, 0
    bit 1, a
    jr z, .s1
    inc b
.s1
    bit 3, a
    jr z, .s2
    inc b
.s2
    bit 5, a
    jr z, .s3
    inc b
.s3
    bit 7, a
    jr z, .s4
    inc b
.s4
    ld a, b
    ret

; ============================================================
; IsKeyItemOwned — is wCurItem owned (own bit set)?
; OUTPUT: Z=not owned, NZ=owned
; ============================================================
IsKeyItemOwned::
    call IsKeyPocketItem
    jr nc, .no
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    call _KeyBitInfo      ; c = own_bit
    ld a, [hl]
    and b
    push af
    xor a
    ld [rRAMG], a
    pop af
    ret
.no
    xor a
    ret

; ============================================================
; IsKeyItemActive — is wCurItem active (in bag, bit own+1 set)?
; Used by battle/field effects. Replaces HasKeyPocketItem.
; OUTPUT: Z=not active, NZ=active
; ============================================================
IsKeyItemActive::
    call IsKeyPocketItem
    jr nc, .no
    inc c               ; c = active_bit = own_bit + 1
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    call _KeyBitInfo
    ld a, [hl]
    and b
    push af
    xor a
    ld [rRAMG], a
    pop af
    ret
.no
    xor a
    ret

; Backward-compat alias — callers of HasKeyPocketItem updated to IsKeyItemActive
HasKeyPocketItem:: jp IsKeyItemActive

; ============================================================
; GetKeyItemPower — one-call combination of IsKeyItemActive +
; GetKeyItemTierForCurItem for the Key Item Effects hooks (see
; KEY_ITEM_EFFECTS_PLAN_PC.md). Both halves are same-bank here, so this is a
; plain internal call pair; callers elsewhere reach it with a single farcall
; instead of two, which matters because farcall's Bankswitch clobbers
; a/b/c/h/l on every crossing (project_farcall_home_clobbers_a).
; INPUT:  wCurItem = the key item to query
; OUTPUT: a = 0 if the item is not ACTIVE (not in the bag), otherwise
;         1 + tier (1, 2 or 3 = displayed TIER 1/2/3)
; CLOBBERS: bc/de/hl
; ============================================================
GetKeyItemPower::
    call IsKeyItemActive
    jr z, .notActive
    call GetKeyItemTierForCurItem
    inc a
    ret
.notActive
    xor a
    ret

; ============================================================
; OwnKeyItem — grant wCurItem. Sets own bit always.
; Also sets active bit if fewer than KEY_ITEM_MAX_ACTIVE items active.
; Replaces AcquireKeyPocketItem.
;
; Reports which happened via hSpriteOffset: 0 = equipped into the bag,
; $ff = owned but parked in the PC because all active slots were full.
; GiveItem (home/give.asm) reads exactly this to choose between its normal
; "got item" return and its carry-clear "sent to PC" return. This routine used
; to never write it, so GiveItem branched on whatever scratch value happened to
; be there - _BuildPocketScan below uses the same byte - which made a perfectly
; successful grant randomly report itself as a failure to the caller.
; ============================================================
OwnKeyItem::
AcquireKeyPocketItem::
    call IsKeyPocketItem
    ret nc                    ; not a key item
    ; c = own_bit
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    push bc
    call _KeyBitInfo          ; hl = byte addr, b = 1<<own_bit
    ld a, [hl]
    or b
    ld [hl], a                ; set owned bit
    call _CountActive
    pop bc                    ; restore c = own_bit
    cp KEY_ITEM_MAX_ACTIVE
    jr nc, .ownOnly           ; already 3 active — goes to PC
    ; Set active bit (own_bit + 1)
    inc c
    call _KeyBitInfo
    ld a, [hl]
    or b
    ld [hl], a
    xor a
    ldh [hSpriteOffset], a    ; 0 = equipped straight into the bag
    jr .finish
.ownOnly
    ld a, $ff
    ldh [hSpriteOffset], a    ; $ff = owned, but stored in the PC
.finish
    xor a
    ld [rRAMG], a
    ret

; ============================================================
; WithdrawKeyItem — activate wCurItem (PC → bag). Replaces EquipKeyItem.
; OUTPUT: carry set = now active; carry clear = bag full or already active
; ============================================================
WithdrawKeyItem::
EquipKeyItem::
    call IsKeyPocketItem
    jr nc, .fail
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    inc c                     ; c = active_bit
    push bc
    call _KeyBitInfo
    ld a, [hl]
    and b
    jr nz, .alreadyActive     ; already active
    call _CountActive
    cp KEY_ITEM_MAX_ACTIVE
    jr nc, .bagFull
    pop bc
    call _KeyBitInfo
    ld a, [hl]
    or b
    ld [hl], a                ; set active bit
    xor a
    ld [rRAMG], a
    scf
    ret
.alreadyActive
.bagFull
    pop bc
    xor a
    ld [rRAMG], a
.fail
    and a                     ; carry clear
    ret

; ============================================================
; DepositKeyItem — deactivate wCurItem (bag → PC). Replaces UnequipKeyItem.
; OUTPUT: carry set = deposited; carry clear = wasn't active
; ============================================================
DepositKeyItem::
UnequipKeyItem::
    call IsKeyPocketItem
    jr nc, .fail
    inc c                     ; c = active_bit
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    push bc
    call _KeyBitInfo
    ld a, [hl]
    and b
    jr z, .notActive
    pop bc
    call _KeyBitInfo
    ld a, b
    cpl
    ld b, a
    ld a, [hl]
    and b                     ; clear active bit
    ld [hl], a
    xor a
    ld [rRAMG], a
    scf
    ret
.notActive
    pop bc
    xor a
    ld [rRAMG], a
.fail
    and a
    ret

; ============================================================
; ClearKeyItemsBitfield — wipe all bits. Call on true new game only.
;
; Clears sKeyItemTiers as well as sKeyItemsBitfield: the two are adjacent in
; ram/sram.asm and are wiped as one 8-byte block. Leaving the tier array
; uninitialised meant it powered up holding whatever was in SRAM, and any item
; whose garbage tier happened to read >= MAX_KEY_ITEM_TIER was silently treated
; as fully upgraded and dropped from the Credit Exchange's upgrade list.
; ============================================================
ClearKeyItemsBitfield::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld hl, sKeyItemsBitfield
    ld b, 8       ; 4 bytes of ownership bits + 4 of upgrade tiers
    xor a
.clearLoop
    ld [hli], a
    dec b
    jr nz, .clearLoop
    ; ELEMENT PRISM's chosen type must init to $ff, NOT 0. Every other byte
    ; here means "none" at zero, but a type constant does not: 0 is NORMAL.
    ; Zeroing this would hand every fresh file a Normal-type prism the player
    ; never picked, silently biasing species rolls and buffing Normal moves.
    ; Same bug class as sKeyItemTiers' original miss (see
    ; project_credit_system_bug_classes) - uninitialized SRAM that happens to
    ; be a legal value fails quietly instead of loudly.
    ld a, $ff
    ld [sElementPrismType], a
    xor a
    ld [sPrismCartridges], a      ; no cartridges unlocked on a brand-new file
    ld [sPrismCartridges + 1], a
    ld [rRAMG], a
    ret

; ============================================================
; BuildKeyItemBagList — list of ACTIVE items for the bag pocket display.
; Format: count + {item_id, 1} pairs + $FF sentinel.
; ============================================================
BuildKeyItemBagList::
BuildKeyItemPocketList::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, HIGH(wKeyItemPocketBuf + 1)
    ld [wPocketListWritePtr], a
    ld a, LOW(wKeyItemPocketBuf + 1)
    ld [wPocketListWritePtr + 1], a
    ld b, 0          ; output count
    ld c, 0          ; table index
.bagScan
    push bc
    ld hl, KeyItemPocketTable
    ld d, 0
    ld e, c
    sla e
    add hl, de
    ld a, [hli]
    cp $FF
    jr z, .bagDone
    ld d, a          ; d = item_id
    ld a, [hl]       ; a = own_bit
    ld c, a
    inc c            ; c = active_bit
    push de          ; save item_id — _KeyBitInfo clobbers both d and e
    call _KeyBitInfo ; hl = bitfield byte, b = mask; d,e clobbered
    ld a, [hl]
    and b
    jr z, .bagSkipPop ; not active
    ; Active — restore item_id and emit
    pop de
    ld a, [wPocketListWritePtr]
    ld h, a
    ld a, [wPocketListWritePtr + 1]
    ld l, a
    ld a, d          ; item_id
    ld [hli], a
    ld a, 1
    ld [hli], a      ; qty
    ld a, h
    ld [wPocketListWritePtr], a
    ld a, l
    ld [wPocketListWritePtr + 1], a
    pop bc
    inc b
    inc c
    jr .bagScan
.bagSkipPop
    pop de           ; balance push
.bagSkip
    pop bc
    inc c
    jr .bagScan
.bagDone
    pop bc
    ld a, b
    ld [wKeyItemPocketBuf], a
    ld a, [wPocketListWritePtr]
    ld h, a
    ld a, [wPocketListWritePtr + 1]
    ld l, a
    ld a, $FF
    ld [hl], a
    xor a
    ld [rRAMG], a
    ret

; ============================================================
; BuildKeyItemPCWithdrawList — list of OWNED-but-NOT-ACTIVE items.
; Used by the PC WITHDRAW screen.
; ============================================================
BuildKeyItemPCWithdrawList::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, HIGH(wKeyItemPocketBuf + 1)
    ld [wPocketListWritePtr], a
    ld a, LOW(wKeyItemPocketBuf + 1)
    ld [wPocketListWritePtr + 1], a
    ld b, 0
    ld c, 0
.wdScan
    push bc
    ld hl, KeyItemPocketTable
    ld d, 0
    ld e, c
    sla e
    add hl, de
    ld a, [hli]
    cp $FF
    jr z, .wdDone
    ld d, a          ; d = item_id
    ld a, [hl]       ; a = own_bit
    ld c, a
    push de          ; save item_id before _KeyBitInfo calls clobber d and e
    ; Check owned
    call _KeyBitInfo
    ld a, [hl]
    and b
    jr z, .wdSkipPop ; not owned
    ; Check NOT active
    inc c
    call _KeyBitInfo  ; d,e clobbered again (item_id still safe on stack)
    ld a, [hl]
    and b
    jr nz, .wdSkipPop ; already active (in bag)
    ; Emit — restore item_id from stack
    pop de
    ld a, [wPocketListWritePtr]
    ld h, a
    ld a, [wPocketListWritePtr + 1]
    ld l, a
    ld a, d          ; item_id
    ld [hli], a
    ld a, 1
    ld [hli], a
    ld a, h
    ld [wPocketListWritePtr], a
    ld a, l
    ld [wPocketListWritePtr + 1], a
    pop bc
    inc b
    inc c
    jr .wdScan
.wdSkipPop
    pop de           ; balance push
.wdSkip
    pop bc
    inc c
    jr .wdScan
.wdDone
    pop bc
    ld a, b
    ld [wKeyItemPocketBuf], a
    ld a, [wPocketListWritePtr]
    ld h, a
    ld a, [wPocketListWritePtr + 1]
    ld l, a
    ld a, $FF
    ld [hl], a
    xor a
    ld [rRAMG], a
    ret

; ============================================================
; BuildKeyItemPCList — alias for the PC screen (shows bag list).
; PC DEPOSIT uses the same list as the bag.
; ============================================================
BuildKeyItemPCList:: jp BuildKeyItemBagList
