; CGB background attribute maps.
;
; This is a DELIBERATE, NEAR-VERBATIM PORT of shinpokered's
; engine/bg_map_attributes.asm (LoadBGMapAttributes), paired with its
; data/bg_map_attributes.asm packet data. It replaces a hand-written equivalent
; that was attempted first and went badly: three separate bugs in the transfer
; routine alone (two wrong VBlank/interrupt policies, and writing attributes to
; only one of the two BG maps). The reference version is known-good on real
; hardware, so the rule for this file is: keep it structurally identical to the
; original, and treat any divergence as something that needs justifying in a
; comment rather than as an improvement.
;
; The earlier attempt (a build-time rasteriser generating attribute maps from
; this fork's own SGB ATTR_BLK packets, plus a bespoke blit) is preserved in
; K:\Other computers\My Laptop\Red Rogue Files\cgb_attempt1_backup\ in case its
; screen-geometry advantage is ever wanted - Red Rogue's TrainerCard, PartyMenu
; and StatusScreen layouts do differ from shinpokered's, so some of these
; packets will colour a few tiles in the wrong place. That is a data problem to
; fix per-screen later, not a reason to re-hand-roll the engine.
;
; Deliberate divergences from the original, all forced:
;   * Modern rgbds idiom: ldh for $ffxx registers, LCDC_ENABLE instead of
;     rLCDC_ENABLE_MASK, B_IE_VBLANK instead of VBLANK.
;   * The original's audio-lag compensation calls its Func_3082; the equivalent
;     here is Audio1_UpdateMusic via farcall (see home/audio.asm).
;   * The original's HandleBadgeFaceAttributes / HandlePartyHPBarAttributes
;     post-passes are NOT ported. They hardcode shinpokered's trainer-card and
;     party-menu tile coordinates and read its wTrainerCardBadgeAttributes,
;     neither of which matches this fork. Porting them verbatim would write to
;     the wrong tiles. The packet-number argument is still consumed the same way
;     so they can be added later without changing the interface.
;
; Called by farcall, so the argument is in D (farcall expands to
; `ld b, BANK / ld hl, addr / call Bankswitch`, which destroys HL; Bankswitch
; preserves DE - verified in home/bankswitch.asm).

LoadBGMapAttributes::
; d = number of the attribute packet (1-indexed, see BGMapAttributesPointers)
	ld hl, BGMapAttributesPointers
	ld c, d
	ld a, c
	push af ; the original keeps this to pick the trainer-card / party-menu
	        ; post-pass; kept so the stack stays balanced with the original
	dec a
	add a
	ld e, a
	xor a
	ld d, a
	add hl, de
; hl = pointer to the packet's address
	ld a, [hli]
	ld e, a
	ld a, [hl]
	ld h, a
	ld a, e
	ld l, a
; hl = packet address

	di
	ld a, 1
	ldh [rVBK], a ; attributes live in VRAM bank 1
	push hl ; save the packet address; the whole thing runs again for vBGMap1
	ld a, [hl] ; attribute count: (n + 1) * 16 bytes
	ld c, a
	ld de, $10
	add hl, de ; skip the 16-byte header to the first attribute byte
	ld a, h
	ldh [rHDMA1], a
	ld a, l
	ldh [rHDMA2], a
	ld de, vBGMap0 ; same address, but bank 1 because rVBK is 1
	ld a, d
	ldh [rHDMA3], a
	ld a, e
	ldh [rHDMA4], a

	ldh a, [rLCDC]
	and LCDC_ENABLE
	jr z, .lcdOff ; LCD off: transfer immediately
.waitForVBlankLoop1
	ldh a, [rLY]
	cp LY_VBLANK
	jr nz, .waitForVBlankLoop1
.waitForAccessibleVRAMLoop1
	ldh a, [rSTAT]
	and %10 ; mode 2 or 3 means VRAM is busy
	jr nz, .waitForAccessibleVRAMLoop1
.lcdOff
	ld a, c
	ldh [rHDMA5], a ; initiate transfer
	call .updateAudio ; the transfer eats a VBlank; keep music from lagging

	pop hl ; packet address again, for vBGMap1
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a ; offset of the attribute data
	add hl, de
	ld a, h
	ldh [rHDMA1], a
	ld a, l
	ldh [rHDMA2], a
	ld de, vBGMap1
	ld a, d
	ldh [rHDMA3], a
	ld a, e
	ldh [rHDMA4], a

	ldh a, [rLCDC]
	and LCDC_ENABLE
	jr z, .lcdOff2
.waitForVBlankLoop2
	ldh a, [rLY]
	cp LY_VBLANK
	jr nz, .waitForVBlankLoop2
.waitForAccessibleVRAMLoop2
	ldh a, [rSTAT]
	and %10
	jr nz, .waitForAccessibleVRAMLoop2
.lcdOff2
	ld a, c
	ldh [rHDMA5], a

	pop af ; packet number; the original branches on it here for the
	       ; trainer-card and party-menu post-passes, which are not ported
	call .updateAudio
	; Clear the VBlank flag the waits above let pile up, so the handler does not
	; immediately fire on stale state the moment interrupts come back. This is
	; in the original and is easy to mistake for redundant.
	ldh a, [rIF]
	res B_IE_VBLANK, a
	ldh [rIF], a
	xor a
	ldh [rVBK], a ; every other VRAM writer assumes bank 0
	ei
	ret

.updateAudio
; The original calls its Func_3082 here for the same reason: the VBlank waits
; above run with interrupts disabled, so the music engine misses its update and
; audibly stutters on every screen transition without this.
	push hl
	push bc
	farcall Audio1_UpdateMusic
	pop bc
	pop hl
	ret

BGMapAttributesPointers:
	dw BGMapAttributes_Unknown1
	dw BGMapAttributes_Unknown2
	dw BGMapAttributes_GameFreakIntro
	dw BGMapAttributes_TrainerCard
	dw BGMapAttributes_PartyMenu
	dw BGMapAttributes_NidorinoIntro
	dw BGMapAttributes_TitleScreen
	dw BGMapAttributes_Slots
	dw BGMapAttributes_Pokedex
	dw BGMapAttributes_StatusScreen
	dw BGMapAttributes_Battle
	dw BGMapAttributes_WholeScreen
	dw BGMapAttributes_Unknown13

; Packet numbers for BGMapAttributesPointers above, 1-indexed.
DEF BGMAP_ATTR_GAMEFREAK_INTRO  EQU 3
DEF BGMAP_ATTR_TRAINER_CARD     EQU 4
DEF BGMAP_ATTR_PARTY_MENU       EQU 5
DEF BGMAP_ATTR_NIDORINO_INTRO   EQU 6
DEF BGMAP_ATTR_TITLE_SCREEN     EQU 7
DEF BGMAP_ATTR_SLOTS            EQU 8
DEF BGMAP_ATTR_POKEDEX          EQU 9
DEF BGMAP_ATTR_STATUS_SCREEN    EQU 10
DEF BGMAP_ATTR_BATTLE           EQU 11
DEF BGMAP_ATTR_WHOLE_SCREEN     EQU 12

; ============================================================================
; Red Rogue glue. Not part of the port.
;
; shinpokered calls LoadBGMapAttributes explicitly from each screen's setup
; code. This fork instead has one natural chokepoint - SendSGBPackets already
; receives the ATTR_BLK ("Blk") packet that describes the screen being set up -
; so the packet address is mapped to a packet number here rather than editing
; every screen. Screens with no entry simply keep whatever attributes the last
; screen left, which is the same behaviour as never calling the routine.
; ============================================================================

LoadCGBScreenAttributesForBlkPacket::
; de = the ATTR_BLK packet SendSGBPackets was about to hand to an SGB.
	ld hl, .blkPacketToAttrPacket
.search
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a
	or c
	ret z ; terminator: no attribute packet for this screen
	ld a, d
	cp b
	jr nz, .nextEntry
	ld a, e
	cp c
	jr z, .found
.nextEntry
	inc hl ; step over the packet number
	jr .search
.found
	ld d, [hl]
	jp LoadBGMapAttributes

.blkPacketToAttrPacket
	dw BlkPacket_WholeScreen
	db BGMAP_ATTR_WHOLE_SCREEN
	dw BlkPacket_Battle
	db BGMAP_ATTR_BATTLE
	dw BlkPacket_StatusScreen
	db BGMAP_ATTR_STATUS_SCREEN
	dw BlkPacket_Pokedex
	db BGMAP_ATTR_POKEDEX
	dw BlkPacket_Slots
	db BGMAP_ATTR_SLOTS
	dw BlkPacket_Titlescreen
	db BGMAP_ATTR_TITLE_SCREEN
	dw BlkPacket_NidorinoIntro
	db BGMAP_ATTR_NIDORINO_INTRO
	dw BlkPacket_GameFreakIntro
	db BGMAP_ATTR_GAMEFREAK_INTRO
	dw BlkPacket_TrainerCard
	db BGMAP_ATTR_TRAINER_CARD
	dw wPartyMenuBlkPacket
	db BGMAP_ATTR_PARTY_MENU
	dw 0 ; terminator

; CGB DMA ignores the low four bits of its source address. ShinRed places these
; packets at the start of bank $2e, so their 16-byte headers are naturally
; aligned. This port puts the loader first, so align the packet data explicitly;
; otherwise the transfer begins inside the header (observed as attribute $0d at
; tile-map entry 0, which selects the blank tile-data bank 1).
	align 4
INCLUDE "data/gfx/bg_map_attributes.asm"
