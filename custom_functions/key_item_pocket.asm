; custom_functions/key_item_pocket.asm
;
; Key items: own vs carry split.
;   sKeyItemsBitfield: everything owned (SRAM, persists forever)
;   sKeyItemCarry[3]:  active loadout (SRAM, 3 item IDs, $00=empty)
;
; Owned but not carrying = stored in PC. Swap at the PC menu.
; Only CARRIED items are usable in battle/field.
;
; Bit assignments (stable once saves exist):
;   0=LEFTOVERS, 1=PP_TONIC, 2=KO_DEFIANCE, 3=EXP_ALL, 4-31 reserved
;
; All functions read wCurItem (not b) — farcall clobbers b.

KeyItemPocketTable::
    db LEFTOVERS,   KEY_ITEM_BIT_LEFTOVERS
    db PP_TONIC,    KEY_ITEM_BIT_PP_TONIC
    db KO_DEFIANCE, KEY_ITEM_BIT_KO_DEFIANCE
    db EXP_ALL,     KEY_ITEM_BIT_EXP_ALL
    db $FF

; ============================================================
; IsKeyPocketItem — does wCurItem belong here?
; OUTPUT: carry set = yes, c = bit_index; carry clear = no
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
    ld c, [hl]
    scf
    ret
.no
    and a
    ret

; ============================================================
; _KeyBitInfo (same-bank private)
; INPUT: c = bit_index; SRAM must be enabled by caller.
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
; _IsCarried (same-bank private; SRAM must be enabled)
; Is wCurItem in sKeyItemCarry?
; OUTPUT: NZ = carrying (a != 0), Z = not carrying
; ============================================================
_IsCarried:
    ld a, [wCurItem]
    ld d, a
    ld hl, sKeyItemCarry
    ld c, 3
.loop
    ld a, [hli]
    cp d
    ret z        ; Z cleared by cp if equal → but cp sets Z if equal, so ret z = return if found
    dec c
    jr nz, .loop
    xor a        ; Z = not carrying
    ret
; Note: when found, Z=1 from cp d (equal). Callers check: ret z = found → to .found label.
; When not found, xor a sets Z=1 (also Z). This means callers can't distinguish
; "found" from "not found" by Z flag alone from the return point after the loop.
; Restructure: use NZ for found.

; ============================================================
; _FindInCarry (same-bank private; SRAM must be enabled)
; Scan sKeyItemCarry for wCurItem.
; OUTPUT: carry set = found, hl = slot address; carry clear = not found
; ============================================================
_FindInCarry:
    ld a, [wCurItem]
    ld d, a
    ld hl, sKeyItemCarry
    ld c, 3
.loop
    ld a, [hl]
    cp d
    jr z, .found
    inc hl
    dec c
    jr nz, .loop
    and a        ; carry clear
    ret
.found
    scf
    ret

; ============================================================
; _FindEmptyCarry (same-bank private; SRAM must be enabled)
; Find first empty slot ($00) in sKeyItemCarry.
; OUTPUT: carry set = found empty, hl = slot address; carry clear = full
; ============================================================
_FindEmptyCarry:
    ld hl, sKeyItemCarry
    ld c, 3
.loop
    ld a, [hl]
    and a
    jr z, .found
    inc hl
    dec c
    jr nz, .loop
    and a        ; carry clear = full
    ret
.found
    scf
    ret

; ============================================================
; IsKeyItemOwned — is wCurItem in sKeyItemsBitfield?
; OUTPUT: Z=not owned, NZ=owned
; ============================================================
IsKeyItemOwned::
    call IsKeyPocketItem
    jr nc, .no
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
    xor a    ; Z = not owned
    ret

; ============================================================
; HasKeyPocketItem — is wCurItem in the ACTIVE CARRY (sKeyItemCarry)?
; Used by battle/field effects (e.g. TryKODefiance).
; OUTPUT: Z=not carrying, NZ=carrying
; ============================================================
HasKeyPocketItem::
    call IsKeyPocketItem
    jr nc, .notCarried
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    call _FindInCarry    ; carry set = found
    push af
    xor a
    ld [rRAMG], a
    pop af               ; restore carry
    ; Convert carry to NZ/Z: scf set = carrying (NZ), else Z
    jr c, .carried
    xor a                ; Z = not carrying
    ret
.carried
    ld a, 1              ; NZ = carrying
    ret
.notCarried
    xor a
    ret

; ============================================================
; AcquireKeyPocketItem
; Set ownership bit. Try to equip (fill a carry slot).
; If carry full: ownership bit is set but not carried (sent to PC).
; Signals result via hSpriteOffset: 0 = equipped, $FF = sent to PC.
; ============================================================
AcquireKeyPocketItem::
    call IsKeyPocketItem
    ret nc
    ; c = bit_index
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    push bc
    call _KeyBitInfo
    ld a, [hl]
    or b
    ld [hl], a           ; set ownership bit
    ; Already carrying? (don't double-add)
    call _FindInCarry
    pop bc
    jr c, .alreadyCarried
    ; Find empty carry slot
    call _FindEmptyCarry
    jr nc, .sentToPC
    ; Empty slot found — equip it
    ld a, [wCurItem]
    ld [hl], a
.alreadyCarried
    xor a
    ld [rRAMG], a
    xor a
    ldh [hSpriteOffset], a   ; 0 = equipped / already had it
    ret
.sentToPC
    xor a
    ld [rRAMG], a
    ld a, $FF
    ldh [hSpriteOffset], a   ; $FF = sent to PC (carry full)
    ret

; ============================================================
; EquipKeyItem — add wCurItem to sKeyItemCarry if room.
; OUTPUT: carry set = now equipped; carry clear = no room or already had it
; ============================================================
EquipKeyItem::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    call _FindInCarry
    jr c, .alreadyCarried
    call _FindEmptyCarry
    jr nc, .full
    ld a, [wCurItem]
    ld [hl], a
    xor a
    ld [rRAMG], a
    scf
    ret
.alreadyCarried
.full
    xor a
    ld [rRAMG], a
    and a    ; carry clear
    ret

; ============================================================
; UnequipKeyItem — remove wCurItem from sKeyItemCarry.
; Item remains owned in sKeyItemsBitfield (goes to PC storage).
; OUTPUT: carry set = removed; carry clear = wasn't carrying
; ============================================================
UnequipKeyItem::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    call _FindInCarry
    jr nc, .notCarried
    xor a
    ld [hl], a           ; clear this carry slot
    ld [rRAMG], a
    scf
    ret
.notCarried
    xor a
    ld [rRAMG], a
    and a    ; carry clear
    ret

; ============================================================
; ClearKeyItemsBitfield — wipe ownership AND carry slots.
; Call on true new game ONLY (not on death/run-reset).
; ============================================================
ClearKeyItemsBitfield::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld hl, sKeyItemsBitfield
    xor a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hl], a
    ld hl, sKeyItemCarry
    xor a
    ld [hli], a
    ld [hli], a
    ld [hl], a
    xor a
    ld [rRAMG], a
    ret

; ============================================================
; BuildKeyItemPocketList — display list for the BAG KEY ITEMS pocket.
; Shows only the 3 CARRIED items (sKeyItemCarry).
; Format: count + {item_id, 1} pairs + $FF.
; ============================================================
BuildKeyItemPocketList::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, HIGH(wKeyItemPocketBuf + 1)
    ldh [hSpriteHeight], a
    ld a, LOW(wKeyItemPocketBuf + 1)
    ldh [hSpriteWidth], a
    ld b, 0
    ld c, 0          ; slot index (0-2)
.bagScan
    ld a, c
    cp 3
    jr z, .bagDone
    ld hl, sKeyItemCarry
    ld d, 0
    ld e, c
    add hl, de
    ld a, [hl]       ; item_id in this carry slot
    and a
    jr z, .bagSkip   ; $00 = empty
    push bc
    push af          ; item_id
    ldh a, [hSpriteHeight]
    ld h, a
    ldh a, [hSpriteWidth]
    ld l, a
    pop af
    ld [hli], a      ; item_id
    ld a, 1
    ld [hli], a      ; qty
    ld a, h
    ldh [hSpriteHeight], a
    ld a, l
    ldh [hSpriteWidth], a
    pop bc
    inc b
.bagSkip
    inc c
    jr .bagScan
.bagDone
    ld a, b
    ld [wKeyItemPocketBuf], a
    ldh a, [hSpriteHeight]
    ld h, a
    ldh a, [hSpriteWidth]
    ld l, a
    ld a, $FF
    ld [hl], a
    xor a
    ld [rRAMG], a
    ret

; ============================================================
; BuildKeyItemPCList — display list for the PC KEY ITEMS screen.
; Shows ALL OWNED items. qty=2 means currently carried (equipped),
; qty=1 means owned but stored in PC.
; ============================================================
BuildKeyItemPCList::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, HIGH(wKeyItemPocketBuf + 1)
    ldh [hSpriteHeight], a
    ld a, LOW(wKeyItemPocketBuf + 1)
    ldh [hSpriteWidth], a
    ld b, 0          ; output count
    ld c, 0          ; table index
.pcScan
    ; Get {item_id, bit_index} at table[c]
    push bc
    ld hl, KeyItemPocketTable
    ld d, 0
    ld e, c
    sla e            ; *2 (2 bytes per entry)
    add hl, de
    ld a, [hli]      ; a = item_id
    cp $FF
    jr z, .pcDone
    ld d, a          ; d = item_id
    ld a, [hl]       ; a = bit_index
    ld c, a
    ; Check if owned
    call _KeyBitInfo ; hl = &bitfield[c>>3], b = mask
    ld a, [hl]
    and b
    pop bc
    jr z, .pcNotOwned
    ; Owned — check if carrying
    push bc
    push de
    ; Temporarily set wCurItem so _FindInCarry works
    ld a, [wCurItem]
    push af          ; save original wCurItem
    ld a, d
    ld [wCurItem], a
    call _FindInCarry ; carry set = carrying
    pop af
    ld [wCurItem], a  ; restore wCurItem
    ld a, 1          ; default qty=1 (stored in PC)
    jr nc, .pcEmit
    ld a, 2          ; qty=2 = currently carrying
.pcEmit
    push af          ; save qty
    ldh a, [hSpriteHeight]
    ld h, a
    ldh a, [hSpriteWidth]
    ld l, a
    ld a, d          ; item_id
    ld [hli], a
    pop af           ; qty
    ld [hli], a
    ld a, h
    ldh [hSpriteHeight], a
    ld a, l
    ldh [hSpriteWidth], a
    pop de
    pop bc
    inc b
    inc c
    jr .pcScan
.pcNotOwned
    inc c
    jr .pcScan
.pcDone
    pop bc
    ld a, b
    ld [wKeyItemPocketBuf], a
    ldh a, [hSpriteHeight]
    ld h, a
    ldh a, [hSpriteWidth]
    ld l, a
    ld a, $FF
    ld [hl], a
    xor a
    ld [rRAMG], a
    ret
