; Ghost Variant system
;
; A "ghost variant" is a flag on one specific mon instance (not a separate
; species) that forces its secondary type to GHOST and its palette to purple.
; Normal and ghost versions of the same species coexist fine, since the flag
; lives on the individual mon's own struct, not on anything species-keyed.
;
; STATUS: not wired into anything yet. ApplyGhostVariant/IsGhostVariant below
; are real and ready to call. The three display hooks (status screen type,
; battle palette, status screen palette) are written as commented-out
; reference snippets at the bottom, showing exactly what to insert where once
; this is ready to go live alongside the procedural cemetery stage work.
;
; Storage: bit 0 of the CatchRate byte (MON_CATCH_RATE) in
; box_struct/party_struct/battle_struct. That field is dead for any owned mon
; in this codebase - nothing reads MON_CATCH_RATE anywhere (confirmed by
; grep); the only "catch rate" actually used during play is
; wEnemyMonActualCatchRate, a separate wild-encounter-only scratch variable
; copied from the species' base stats, not this stored per-mon field. So
; repurposing it costs nothing, and since it's part of the shared struct
; layout, the flag survives box deposits, trades, and battle-loading for
; free - no separate save-side work needed.
;
; Gotcha (fixed): MON_CATCH_RATE isn't blank when a mon is created - the
; standard "populate a new mon's struct from its species' base stats" copy
; (engine/pokemon/add_mon.asm, and the matching enemy-mon battle-load copy
; in engine/battle/core.asm) writes the species' real catch rate into this
; byte, same as any other base stat. Plenty of species have an odd catch
; rate (e.g. Bulbasaur is 45), so without an explicit clear, those species
; would spawn pre-flagged as ghost variants by pure coincidence the moment
; the display hooks below go live. Both copy sites now `res 0, a` on the
; catch-rate value right before storing it, so every freshly created mon
; (player party or enemy) starts at "not ghost" regardless of species, and
; only ApplyGhostVariant ever sets the bit on purpose. This mod isn't
; planning to keep Pokemon catching as a mechanic - if catching is ever
; fully removed, MON_CATCH_RATE (and wEnemyMonActualCatchRate) become
; entirely free and those two `res 0, a` clears stop being load-bearing
; (they're harmless no-ops at that point, not worth removing urgently).
;
; Move selection (one of the 3 Gen 1 ghost moves - LICK, NIGHT_SHADE,
; CONFUSE_RAY) is intentionally NOT handled here. It doesn't need persistent
; storage of its own - it's just a normal write into one of the mon's 4
; existing move slots at creation time, same as any other move roll. That's
; the caller's job (wherever the boss actually gets generated).

DEF BIT_GHOST_VARIANT EQU 0 ; bit within the repurposed CatchRate byte

; ---------------------------------------------------------------------------
; ApplyGhostVariant
; Marks the mon at [hl] as a ghost variant and forces its secondary type.
; Call once, at creation time. Does not touch moves (see note above).
; INPUT: hl = pointer to the mon's struct (its Species field, i.e. the same
;             address you'd pass as the base of a box_struct/party_struct/
;             battle_struct - wBoxMonN, wPartyMonN, wEnemyMonN, wBattleMon,
;             wEnemyMon, wLoadedMon, etc. all qualify)
; CLOBBERS: af, de
; ---------------------------------------------------------------------------
ApplyGhostVariant::
	push hl
	ld de, MON_CATCH_RATE
	add hl, de
	set BIT_GHOST_VARIANT, [hl]     ; set bit to ghost variant
	pop hl
	push hl
	ld de, MON_TYPE2
	add hl, de
	ld [hl], GHOST
	pop hl
	ret

; ---------------------------------------------------------------------------
; IsGhostVariant
; INPUT: de = pointer to the mon's struct (see ApplyGhostVariant)
; OUTPUT: Z set if NOT a ghost variant, Z clear (NZ) if it IS
; CLOBBERS: af, hl
;
; Takes the struct pointer in DE, not HL. Found this the hard way while
; wiring the fusion system's equivalent check: `farcall LABEL`
; (macros/farcall.asm) expands to `ld hl, LABEL / ld b, BANK(LABEL) /
; call Bankswitch` - it OVERWRITES hl with the callee's own address as the
; jump vector, it does NOT preserve the caller's hl. So every integration
; snippet below that was written as `ld hl, <ptr> / farcall IsGhostVariant`
; was broken as originally documented - hl would arrive here holding this
; routine's own address, not the intended struct pointer. de survives
; Bankswitch untouched, so it's the only register safe to carry a pointer
; input across a farcall boundary. Fixed here AND in the snippets below,
; before anything actually calls this (grep confirmed no callers yet - see
; project-cross-bank-call-bugs memory for the general bug class).
; ---------------------------------------------------------------------------
IsGhostVariant::
	ld hl, MON_CATCH_RATE
	add hl, de
	bit BIT_GHOST_VARIANT, [hl]
	ret

; ===========================================================================
; INTEGRATION POINTS (not yet inserted - copy the relevant block into place
; once the procedural cemetery stage is ready to create ghost variants)
; ===========================================================================

; --- engine/battle/print_type.asm, PrintMonType ---
; Status Screen type display re-derives type fresh from the species table via
; GetMonHeader (wMonHType1/2), unlike battle - which already reads the
; per-instance stored type directly and needs no extra hook. Insert right
; after `call GetMonHeader` returns, before the existing `pop hl`:
;
;	ld de, wLoadedMon            ; the mon currently on screen (set earlier in
;	farcall IsGhostVariant       ; this same routine by LoadMonData) - farcall
;	jr z, .notGhostVariant       ; if print_type.asm ends up in a different
;	ld a, GHOST                  ; bank than this file (input is DE, not HL -
;	ld [wMonHType2], a           ; farcall clobbers hl as its own jump vector)
;.notGhostVariant

; --- engine/gfx/palettes.asm, SetPal_Battle ---
; Insert right after wPalPacket+5 (player) and +7 (enemy) are both set, before
; the final `ld hl, wPalPacket` / `ld de, BlkPacket_Battle` tail:
;
;	ld de, wBattleMon
;	farcall IsGhostVariant
;	jr z, .playerNotGhostVariant
;	ld a, PAL_PURPLEMON
;	ld [wPalPacket + 5], a
;.playerNotGhostVariant
;	ld de, wEnemyMon
;	farcall IsGhostVariant
;	jr z, .enemyNotGhostVariant
;	ld a, PAL_PURPLEMON
;	ld [wPalPacket + 7], a
;.enemyNotGhostVariant

; --- engine/gfx/palettes.asm, SetPal_StatusScreen ---
; Insert right after wPalPacket+3 is set, before the final
; `ld hl, wPalPacket` / `ld de, BlkPacket_StatusScreen` tail:
;
;	ld de, wLoadedMon
;	farcall IsGhostVariant
;	jr z, .notGhostVariant
;	ld a, PAL_PURPLEMON
;	ld [wPalPacket + 3], a
;.notGhostVariant
