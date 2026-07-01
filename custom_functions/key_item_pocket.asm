; custom_functions/key_item_pocket.asm
;
; Binary key items pocket: passive-effect items that persist between runs.
; Ownership tracked in sKeyItemsBitfield (SRAM, 4 bytes = 32 bit-slots).
; Active loadout: wKeyItemSlot1/2/3 in WRAM save data (max 3 carried at once).
;
; Items that belong here (see KEY_ITEM_BIT_* in ram_constants.asm):
;   LEFTOVERS (bit 0), PP_TONIC (bit 1), KO_DEFIANCE (bit 2), EXP_ALL (bit 3)
;   Future: Mom's Allowance, First Aid Kit, per-type attack boosters
;
; NOT in this pocket: Poke Flute (goes in regular items bag — infinite-use usable,
;   not a passive effect, doesn't need to persist between runs).

; Stable item-ID → bit-index mapping table.
; Format: {item_id, bit_index} pairs, $FF sentinel.
; NEVER reorder or remove entries once save data exists.
KeyItemPocketTable::
    db LEFTOVERS,   KEY_ITEM_BIT_LEFTOVERS
    db PP_TONIC,    KEY_ITEM_BIT_PP_TONIC
    db KO_DEFIANCE, KEY_ITEM_BIT_KO_DEFIANCE
    db EXP_ALL,     KEY_ITEM_BIT_EXP_ALL
    db $FF          ; sentinel

; ============================================================
; IsKeyPocketItem
; Test whether item b belongs in the key items pocket.
; INPUT: b = item_id
; OUTPUT: carry set = yes, c = bit_index
;         carry clear = no
; CLOBBERS: a, hl
; ============================================================
IsKeyPocketItem::
    ; farcall clobbers b before reaching here; read search target from wCurItem
    ; (GiveItem sets wCurItem at entry, before any farcalls)
    ld a, [wCurItem]
    ld d, a              ; d = item_id to find (save a for table reads)
    ld hl, KeyItemPocketTable
.scan
    ld a, [hli]          ; a = table item_id
    cp $FF
    jr z, .notFound      ; end of table
    cp d                 ; does it match?
    jr z, .found
    inc hl               ; skip bit_index byte
    jr .scan
.found
    ld c, [hl]           ; c = bit_index
    scf
    ret
.notFound
    and a                ; carry clear
    ret

; ============================================================
; _KeyBitInfo (private, analogous to _TMBitInfo)
; INPUT: c = bit_index (0-31)
; OUTPUT: hl = &sKeyItemsBitfield[bit_index >> 3]
;         b  = 1 << (bit_index & 7)
; CLOBBERS: a, d, e
; Caller must enable SRAM before calling.
; ============================================================
_KeyBitInfo:
    ld a, c
    and 7                ; bit position within byte
    ld d, a
    inc d                ; d = bit_pos+1
    ld a, 1
.shift
    dec d
    jr z, .shiftDone
    rlca
    jr .shift
.shiftDone
    ld b, a              ; b = 1 << bit_pos
    ld a, c
    srl a
    srl a
    srl a                ; a = byte offset = bit_index >> 3
    ld hl, sKeyItemsBitfield
    ld d, 0
    ld e, a
    add hl, de
    ret

; ============================================================
; HasKeyPocketItem
; Check if item b is owned (bit set in sKeyItemsBitfield).
; INPUT: b = item_id
; OUTPUT: Z set = not owned, Z clear (NZ) = owned
; CLOBBERS: a, c, d, e, hl
; ============================================================
HasKeyPocketItem::
    call IsKeyPocketItem
    ret nc               ; not a key pocket item → Z state from IsKeyPocketItem (set)
    ; c = bit_index
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    call _KeyBitInfo     ; hl = byte addr, b = mask
    ld a, [hl]
    and b                ; Z set = bit 0 = not owned
    push af
    xor a
    ld [rRAMG], a
    pop af
    ret

; ============================================================
; AcquireKeyPocketItem
; Mark item b as owned and add to carry slot if below the 3-item limit.
; INPUT: b = item_id (must be a key pocket item)
; ============================================================
AcquireKeyPocketItem::
    call IsKeyPocketItem
    ret nc               ; safety: not a key pocket item, ignore
    ; c = bit_index, b = item_id
    ; Set bit in sKeyItemsBitfield — save b (item_id) first since _KeyBitInfo clobbers it
    push bc              ; save c=bit_index, b=item_id across the bitfield write
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    call _KeyBitInfo     ; c=bit_index → hl = byte addr, b = mask (clobbers b!)
    ld a, [hl]
    or b
    ld [hl], a           ; set the ownership bit
    xor a
    ld [rRAMG], a
    pop bc               ; restores bc (note: b is still garbage from farcall — don't use it)
    ; Add to active carry slot if not already carrying it and slots available.
    ; Use wCurItem throughout since b is clobbered by the farcall entry.
    call IsCarryingKeyItem
    ret z                ; already carrying (Z=1, match found) → done
    ; Check carry count < 8 (no hard cap until PC swap UI exists)
    ld a, [wNumBagKeyItems]
    cp 8
    ret nc               ; carry limit reached
    ; Find first empty slot and fill with the CORRECT item_id from wCurItem
    ld a, [wCurItem]     ; real item_id (b is clobbered garbage from farcall)
    ldh [hSpriteOffset], a  ; borrow this free HRAM byte as temp
    ld hl, wKeyItemSlot1
    ld b, 8              ; 8 slots to search
.findEmptySlot
    ld a, [hl]
    and a
    jr z, .emptyFound
    inc hl
    dec b
    jr nz, .findEmptySlot
    ret                  ; all 8 filled (shouldn't happen given the count check above)
.emptyFound
    ldh a, [hSpriteOffset]
    ld [hl], a           ; write item_id to first empty slot
.added
    ld a, [wNumBagKeyItems]
    inc a
    ld [wNumBagKeyItems], a
    ret

; ============================================================
; IsCarryingKeyItem (private)
; Check if item b is in any carry slot.
; OUTPUT: NZ if yes, Z if no
; CLOBBERS: a
; ============================================================
IsCarryingKeyItem:
    ; b is clobbered by farcall — compare all 8 slots against wCurItem
    ld a, [wCurItem]
    ld d, a              ; d = item_id to find
    ld hl, wKeyItemSlot1
    ld b, 8
.checkSlot
    ld a, [hli]
    cp d
    ret z               ; Z=1 → found (already carrying)
    dec b
    jr nz, .checkSlot
    ; not found: ensure Z=0 (cp with last value, if no match then Z was cleared
    ; on the last iteration — but if b went to 0 and last slot was 0, cp d with
    ; 0 might accidentally set Z if d=0, but d=wCurItem which is a valid item
    ; id (non-zero). Safe.)
    ret

; ============================================================
; ClearKeyItemsBitfield
; Wipe all key item ownership. Call on true new game only
; (NOT on death/run-reset — key items persist between runs).
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
    xor a
    ld [rRAMG], a
    ret

; ============================================================
; BuildKeyItemPocketList
; Build a display list in wKeyItemPocketBuf from all carry slots.
; Format: count byte + {item_id, 1} pairs + $FF sentinel.
; ============================================================
BuildKeyItemPocketList::
    ld hl, wKeyItemPocketBuf + 1 ; skip count byte
    ld b, 0                       ; b = output count
    ld de, wKeyItemSlot1
    ld c, 8                       ; 8 slots to scan
.scanLoop
    ld a, [de]
    and a
    jr z, .skipSlot
    ld [hli], a           ; item_id
    push af
    ld a, 1
    ld [hli], a           ; qty = 1 (no quantity display, but format requires it)
    pop af
    inc b
.skipSlot
    inc de
    dec c
    jr nz, .scanLoop
    ld a, b
    ld [wKeyItemPocketBuf], a     ; write count
    ld a, $FF
    ld [hl], a                    ; write sentinel
    ret
