; custom_functions/tm_bag.asm
;
; Roguelike TM/HM bag: infinite-use ownership stored as a
; 7-byte SRAM bitfield (sTMBitfield).
;
; Bit index layout (0-54):
;   0-49  = TM01-TM50  (index = item_id - TM01)
;   50-54 = HM01-HM05  (index = NUM_TMS + item_id - HM01)
;   55    = spare

; ============================================================
; IsTMHMItem
; Test whether item b is a TM or HM.
; OUTPUT: carry set = yes, carry clear = no
; CLOBBERS: a
; ============================================================
IsTMHMItem::
	ld a, [wCurItem]    ; farcall clobbers b before reaching here; GiveItem sets wCurItem first
	cp TM01
	jr nc, .checkTMRange
	cp HM01
	jr c, .no
	cp HM01 + NUM_HMS
	jr nc, .no
	scf
	ret
.checkTMRange
	cp TM01 + NUM_TMS
	jr nc, .no
	scf
	ret
.no
	and a
	ret

; ============================================================
; _TMHMIndex  (private)
; INPUT:  a = TM/HM item ID
; OUTPUT: a = bit index 0-54
; CLOBBERS: b
; ============================================================
_TMHMIndex:
	ld b, a
	sub TM01        ; TM: result 0-49, C clear
	ret nc
	ld a, b         ; restore for HM
	sub HM01        ; HM: 0-4
	add NUM_TMS     ; shift to 50-54
	ret

; ============================================================
; _TMBitInfo  (private)
; Identical pattern to _StageBitInfo in random_stage_selection.asm.
; INPUT:  a = bit index 0-54 (from _TMHMIndex)
; OUTPUT: hl = &sTMBitfield[index>>3]
;         b  = 1 << (index & 7)
; CLOBBERS: d, e
; Caller must enable SRAM before calling.
; ============================================================
_TMBitInfo:
	ld e, a             ; e = full index (preserved across shift loop)
	and 7               ; bit position within byte
	ld d, a
	inc d               ; d = bit_pos+1 (so dec-to-0 = 0 loop iterations for bit_pos=0)
	ld a, 1             ; starting mask
.shift
	dec d
	jr z, .shiftDone
	rlca                ; shift mask left
	jr .shift
.shiftDone
	ld b, a             ; b = 1 << bit_pos
	ld a, e
	srl a
	srl a
	srl a               ; a = byte offset = index >> 3
	ld hl, sTMBitfield
	ld d, 0
	ld e, a
	add hl, de          ; hl = correct byte
	ret

; ============================================================
; AcquireTMHM
; Mark TM/HM item b as owned in sTMBitfield.
; Called from GiveItem when a TM or HM is given to the player.
; Does NOT add to the item bag.
; INPUT: b = item_id (must be a TM or HM)
; ============================================================
AcquireTMHM::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, [wCurItem]    ; farcall clobbers b; GiveItem sets wCurItem before calling
	call _TMHMIndex     ; a = bit index
	call _TMBitInfo     ; hl = byte addr, b = mask
	ld a, [hl]
	or b
	ld [hl], a
	xor a
	ld [rRAMG], a
	ret

; ============================================================
; HasTMHM
; Check whether the TM/HM item in wCurItem is owned.
; INPUT:  wCurItem = item_id (farcall-safe, same convention as RemoveTMHM)
; OUTPUT: Z set = not owned, Z clear = owned
; CLOBBERS: a, d, e, hl
; ============================================================
HasTMHM::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, [wCurItem]
	call _TMHMIndex
	call _TMBitInfo     ; hl = byte addr, b = mask
	ld a, [hl]
	and b               ; Z set = bit 0 = not owned
	push af
	xor a
	ld [rRAMG], a
	pop af
	ret

; ============================================================
; RemoveTMHM
; Clear TM/HM ownership bit in sTMBitfield (sell/remove).
; Uses wCurItem (farcall-safe, same convention as AcquireTMHM).
; INPUT: wCurItem = item_id (must be a TM or HM)
; ============================================================
RemoveTMHM::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, [wCurItem]
	call _TMHMIndex
	call _TMBitInfo     ; hl = byte addr, b = 1<<bit_pos (mask)
	ld a, b
	cpl                 ; a = ~mask
	ld b, a
	ld a, [hl]
	and b               ; clear the owned bit
	ld [hl], a
	xor a
	ld [rRAMG], a
	ret

; ============================================================
; ClearTMBitfield
; Wipe all TM/HM ownership. Call at run reset.
; ============================================================
ClearTMBitfield::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld hl, sTMBitfield
	xor a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	xor a
	ld [rRAMG], a
	ret

; ============================================================
; BuildTMPocketList
; Scan sTMBitfield and build a display list in wTMPocketBuf.
; Format: count + {item_id, qty=1} pairs + $FF sentinel. Uses ITEMLISTMENU.
; Qty display suppressed by BIT_TM_POCKET check in PrintListMenuEntries.
; Caps at 55 entries (all TMs/HMs).
; ============================================================
BuildTMPocketList::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld de, wTMPocketBuf + 1   ; de = write pointer (skip count byte at start)
	ld b, 0                    ; b = owned count
	ld c, 0                    ; c = bit index (0 to NUM_TM_HM-1)
.scan
	ld a, c
	cp NUM_TM_HM               ; done when all 55 bits checked
	jr z, .done
	; check if bit c is set in sTMBitfield (SRAM)
	push bc
	push de
	ld a, c
	call _TMBitInfo            ; hl = &sTMBitfield[c>>3], b = mask
	ld a, [hl]
	and b                      ; Z = not owned
	pop de
	pop bc
	jr z, .notOwned
	; owned — check buffer capacity
	ld a, b
	cp 55                      ; max 55 entries (all TMs/HMs); buffer is $80 bytes
	jr nc, .done
	; convert bit index c to item ID
	ld a, c
	cp NUM_TMS
	jr nc, .isHM
	add TM01                   ; TM: item_id = TM01 + index
	jr .addItem
.isHM
	sub NUM_TMS
	add HM01                   ; HM: item_id = HM01 + (index - NUM_TMS)
.addItem
	ld [de], a                 ; write item ID
	inc de
	ld a, 1
	ld [de], a                 ; write qty = 1
	inc de
	inc b                      ; count++
.notOwned
	inc c
	jr .scan
.done
	ld a, b
	ld [wTMPocketBuf], a       ; write count at start of buffer
	ld a, $ff
	ld [de], a                 ; write sentinel
	xor a
	ld [rRAMG], a
	ret

; ============================================================
; TeachTMHM
; Trigger the standard teach-move flow.
; Caller must set wCurItem to the TM/HM item ID before calling.
; NOTE: do NOT pass the item ID via b — farcall clobbers b with
; the bank number before this function executes.
; ============================================================
TeachTMHM::
	; wCurItem already set by DisplayListMenuID (do not touch it)
	farcall ItemUseTMHM
	ret

; ============================================================
; PocketSwitchROMX
; Full pocket-switch handling, called via farcall from the HOME-bank list
; menu (DisplayListMenuIDLoop) to keep that side small - validates the
; switch is allowed, plays the SFX, advances/retreats the pocket index
; (0=Recovery 1=Key Items 2=TM Pack 3=Stat 4=Valuable; wraps mod 5), updates
; wBagPocketsFlags, and points wListPointer at the new pocket's source
; (rebuilding the pocket's display buffer as needed).
; INPUT: d = direction (1 = forward/RIGHT, 0 = backward/LEFT) - NOT a; farcall
;        clobbers a via Bankswitch before this runs.
; OUTPUT: carry set = switch rejected (wrong menu, or PC withdrawing), state
;         untouched; carry clear = switch applied
; CLOBBERS: a, b, c, hl
; ============================================================
PocketSwitchROMX::
; 5 pockets: 0=Recovery 1=Key Items 2=TM Pack 3=Stat 4=Valuable (mod-5 cycling).
; Direction (1=forward/RIGHT, 0=backward/LEFT) arrives in d, NOT a: farcall routes
; through Bankswitch, whose first instruction (ldh a,[hLoadedROMBank]) clobbers a
; before this runs. farcall preserves de, and call PlaySound below preserves de too,
; so d is still the direction at the branch. (Same clobber as the PlaySound fix.)
	ld a, [wListMenuID]
	cp ITEMLISTMENU
	jr nz, .rejected
	ld hl, wBagPocketsFlags
	bit BIT_PC_WITHDRAWING, [hl]
	jr nz, .rejected
	ld a, SFX_TINK
	; PlaySound is a HOME routine that takes the sound ID in a and manages its own
	; audio bank internally. It must be a plain `call` from any bank: `farcall` routes
	; through Bankswitch, whose first instruction (ldh a,[hLoadedROMBank]) overwrites
	; the sound ID in a, so PlaySound plays a garbage ID whose bogus header sends the
	; channel-pointer write into sprite RAM (wSprite01StateData2), warping NPCs off-
	; screen. Every other PlaySound call site in the game uses a plain `call`.
	call PlaySound
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK      ; a = current pocket index (0-4)
	ld c, a
	ld a, d                    ; a = direction (d survives farcall + PlaySound)
	and a
	jr z, .backward
.forward                       ; 0->1->2->3->4->0
	ld a, c
	inc a
	cp NUM_POCKETS
	jr c, .gotIndex
	xor a
	jr .gotIndex
.backward                      ; 0->4->3->2->1->0
	ld a, c
	dec a
	cp $ff
	jr nz, .gotIndex
	ld a, NUM_POCKETS - 1
.gotIndex
	ld b, a
	ld a, [wBagPocketsFlags]
	and $F8                    ; clear bits 0-2 (pocket index), preserve bits 3-7
	or b
	ld [wBagPocketsFlags], a
	ld a, b                    ; a = new pocket index
	; Route to the right source / build the display list
	cp POCKET_RECOVERY
	jr z, .recoveryPocket
	cp POCKET_KEY_ITEMS
	jr z, .keyPocket
	cp POCKET_TM_PACK
	jr z, .tmPocket
	cp POCKET_STAT
	jr z, .statPocket
	; POCKET_VALUABLE
	call BuildValuablePocketList
	ld bc, wValuablePocketBuf
	jr .gotSource
.recoveryPocket
	call BuildRecoveryPocketList
	ld bc, wRecoveryPocketBuf
	jr .gotSource
.keyPocket
	call BuildKeyItemPocketList
	ld bc, wKeyItemPocketBuf
	jr .gotSource
.tmPocket
	call BuildTMPocketList
	ld bc, wTMPocketBuf
	jr .gotSource
.statPocket
	call BuildStatPocketList
	ld bc, wStatPocketBuf
.gotSource
	ld a, c
	ld hl, wListPointer
	ld [hli], a
	ld [hl], b
	and a
	ret
.rejected
	scf
	ret

; ============================================================
; PrintBagInfoText, GetCurrentMenuItem, GetTMHMContent, strings
; Moved here from home/list_menu.asm so they live in the same ROMX
; bank as PocketSwitchROMX and the strings they reference (avoiding
; cross-bank read issues). Call sites use farcall.
; All calls within these functions that target HOME functions (PlaceString,
; ClearScreenArea, etc.) are plain `call` — HOME code is always accessible
; from any bank.
; ============================================================

TMItContainsText:: ; moved from engine/menus/players_pc.asm (bank1) so the
	text_far _TMItContainsText   ; bank is active when PrintText reads [hl]
    text_end

; ◀ moved from $62 (vChars2/$60 region, overwritten by Town Map) to $c0
; (vChars1/$40 region, safe). The actual glyph still needs to be drawn at
; position $c0 in font.png — until then it shows whatever tile is there.
BagRecoveryText:
	db "◀ RECOVERY   ▶@"

BagKeyItemsText:
	db "◀ KEY ITEMS  ▶@"

BagTMPackText:
	db "◀ TM PACK    ▶@"

BagStatText:
	db "◀ STAT ITEMS ▶@"

BagValuableText:
	db "◀ VALUABLES  ▶@"

PrintBagInfoText::
	ld hl, wBagPocketsFlags
	bit BIT_PRINT_INFO_BOX, [hl]
	jr z, .notBag
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK      ; a = pocket index 0-4
	; Pick the label string for this pocket
	ld de, BagRecoveryText
	and a
	jr z, .mainPocket          ; POCKET_RECOVERY (0)
	cp POCKET_KEY_ITEMS
	jr nz, .notKey
	ld de, BagKeyItemsText
	jr .mainPocket
.notKey
	cp POCKET_TM_PACK
	jr nz, .notTM2
	ld de, BagTMPackText
	jr .mainPocket
.notTM2
	cp POCKET_STAT
	jr nz, .notStat2
	ld de, BagStatText
	jr .mainPocket
.notStat2
	ld de, BagValuableText
.mainPocket
	call GetCurrentMenuItem
	hlcoord 5, 14
	cp $ff ; CANCEL?
	jr z, .notTM
	cp HM_CUT
	jr c, .notTM
	call GetTMHMContent
	hlcoord 5, 14
	ld a, ' '
	ld b, 14 ; clear whole line
.clearLine
	ld [hli], a
	dec b
	jr nz, .clearLine
	ld de, wStringBuffer
	hlcoord 6, 14
.notTM
	jp PlaceString

.notBag
	ld a, [wListMenuID]
	cp ITEMLISTMENU
	jr z, .continue
	cp PRICEDITEMLISTMENU
	ret nz
.continue
	call GetCurrentMenuItem
	cp $ff
	jr z, .restoreDefaultText
	cp HM_CUT
	jr c, .restoreDefaultText
	call GetTMHMContent
	hlcoord 1, 14
	lb bc, 3, 18
	call ClearScreenArea
	ld hl, TMItContainsText
	call PrintText_NoCreatingTextBox
    ret
.restoreDefaultText
	ld de, wTextBoxBuffer
	hlcoord 1, 14
	ld b, 18
.placeTiles
	ld a, [de]
	inc de
	ld [hli], a
	dec b
	jr nz, .placeTiles
	hlcoord 1, 16
	ld b, 18
.placeTiles2
	ld a, [de]
	inc de
	ld [hli], a
	dec b
	jr nz, .placeTiles2
	ret

GetCurrentMenuItem::
	ld a, [wListScrollOffset]
	ld c, a
	ldh a, [hCurrentMenuItem]
	add c
	ld c, a
	ld hl, wListPointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	inc hl
	ld b, 0
	ld a, [wListMenuID]
	cp PRICEDITEMLISTMENU
	jr z, .continue
	sla c
.continue
	add hl, bc
	ld a, [hl]
	ret

GetTMHMContent::
	sub TM01
	jr nc, .skipAdding
	add NUM_TMS + NUM_HMS
.skipAdding
	inc a
	ld [wTempTMHM], a
	predef TMToMove
	ld a, [wTempTMHM]
	ld [wMoveNum], a
	call GetMoveName
	jp CopyToStringBuffer
