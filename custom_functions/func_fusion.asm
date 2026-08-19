; Fusion system primitives.
; Mirrors custom_functions/func_ghost_variant.asm architecture.
;
; Storage: bit 1 of MON_CATCH_RATE (bit 0 is ghost variant).
; Secondary species ID stored globally in wFusionSecondarySpecies (saved WRAM).
; One fusion per run.

DEF BIT_FUSION EQU 1  ; bit within MON_CATCH_RATE (bit 0 = ghost variant)

; ---------------------------------------------------------------------------
; IsFusionMon
; Check if mon is fused.
; INPUT: de = pointer to the mon's struct base (MON_SPECIES field)
; OUTPUT: Z set = not fusion, Z clear (NZ) = is fusion
; CLOBBERS: af, hl
;
; Takes the struct pointer in DE, not HL, because callers in a different bank
; must reach this via `farcall`, and `farcall LABEL` (macros/farcall.asm)
; expands to `ld hl, LABEL / ld b, BANK(LABEL) / call Bankswitch` - it
; OVERWRITES hl with the callee's own address as the jump vector, it does not
; preserve the caller's hl. de is untouched by Bankswitch, so it's the only
; register safe to carry a pointer input across a farcall boundary (same
; reason PatchLegendaryBossSpecies takes its terminator-peek byte in e, not
; hl - see custom_functions/legendary_boss_helpers.asm). Same-bank callers
; can just `ld de, <ptr>` before a plain `call` same as any other input.
; ---------------------------------------------------------------------------
IsFusionMon::
	ld hl, MON_CATCH_RATE
	add hl, de
	bit BIT_FUSION, [hl]
	ret

; ---------------------------------------------------------------------------
; CacheFusionSecondaryBaseStats
; Loads wFusionSecondarySpecies's 5 base stats into wFusionSecondaryBaseStats
; via GetMonHeader, so _CalcStat (engine/pokemon/calc_stats.asm) can compare
; against them without ever calling GetMonHeader itself mid-read (that would
; clobber wMonHeader out from under the primary's own in-progress calc).
; Caller MUST re-populate wMonHeader for its real target mon afterward - this
; routine borrows it as scratch for the secondary and does not restore it.
; INPUT: none (reads wFusionSecondarySpecies)
; CLOBBERS: af, bc, de, hl, wCurSpecies (saved/restored), wMonHeader (NOT restored)
; ---------------------------------------------------------------------------
CacheFusionSecondaryBaseStats::
	ld a, [wCurSpecies]
	push af                          ; preserve caller's species
	ld a, [wFusionSecondarySpecies]
	ld [wCurSpecies], a
	call GetMonHeader                ; fills wMonHeader with the secondary's base stats
	ld hl, wMonHBaseHP                ; skip wMonHIndex - only need the 5 stat bytes
	ld de, wFusionSecondaryBaseStats
	ld bc, NUM_STATS
	call CopyData
	pop af
	ld [wCurSpecies], a               ; restore caller's species
	ret

; ---------------------------------------------------------------------------
; PrepareFusionCalcStats
; Call immediately before CalcStats (farcall from another bank; plain call
; within this bank) so the fusion's dynamic max-base stats apply to THIS
; recalc. If the mon is the fusion: caches the secondary's base stats (setting
; wFusionSecondaryBaseStats byte 0 nonzero = "active" for _CalcStat) AND
; reloads wMonHeader with the PRIMARY's base stats (CacheFusionSecondaryBaseStats
; clobbers wMonHeader with the secondary's). Otherwise: zeroes the sentinel.
; _CalcStats auto-clears the sentinel when it finishes, so the caller has no
; after-call cleanup - it only has to invoke this before CalcStats.
;
; Deriving the struct base: every CalcStats caller has de = the mon's stats
; destination (its MON_STATS field), so struct base = de - MON_STATS. That's
; uniform across all callers, which is why they can share this one helper.
;
; INPUT:  de = the mon's MON_STATS field (the stats dest passed to CalcStats)
; OUTPUT: de preserved; wMonHeader = the mon's (primary's) base stats;
;         sentinel set appropriately for the upcoming CalcStats
; CLOBBERS: af, bc, hl
; ---------------------------------------------------------------------------
PrepareFusionCalcStats::
	push de
	ld hl, -MON_STATS
	add hl, de
	ld d, h
	ld e, l                          ; de = struct base (MON_SPECIES)
	call IsFusionMon                 ; de = struct base; Z = not fusion (same bank)
	jr z, .notFusion
	ld a, [de]                       ; primary species (MON_SPECIES = struct offset 0)
	push af
	call CacheFusionSecondaryBaseStats  ; sets the cache (+ sentinel byte 0);
	                                     ; clobbers wMonHeader/de/bc/hl
	pop af
	ld [wCurSpecies], a
	call GetMonHeader                ; reload wMonHeader with the PRIMARY's base stats
	pop de                           ; restore caller's de (stats dest)
	ret
.notFusion
	xor a
	ld [wFusionSecondaryBaseStats], a  ; sentinel off - not the fusion
	pop de
	ret

; ---------------------------------------------------------------------------
; CreateFusion
; Two-step party selection: pick primary then secondary.
; Bakes secondary's type1 and move slots 0-1 (+ their PP) into
; primary's move slots 2-3. Sets BIT_FUSION on primary's catch-rate
; byte. Saves secondary species to wFusionSecondarySpecies. Releases
; the secondary from the party.
; Call via farcall from any map script.
; HRAM scratch: hSpriteDataOffset = primary index, hSpriteHeight = secondary index
; ---------------------------------------------------------------------------
CreateFusion::
    ; One fusion per run
    ld a, [wFusionSecondarySpecies]
    and a
    jp nz, .alreadyFused
    ; Need at least 2 party members
    ld a, [wPartyCount]
    cp 2
    jp c, .notEnoughMons

    ; --- Select PRIMARY ---
    ; NORMAL_PARTY_MENU: plain "Choose a POKEMON." list, picks and returns the
    ; index in hWhichPokemon on A (the STATS/SWITCH sub-menu is a field-menu
    ; thing, not part of DisplayPartyMenu itself), with no item/TM "NOT ABLE"
    ; greying. hUpdateSpritesEnabled = $ff required for party sprites to render.
    call SaveScreenTilesToBuffer1
    ld hl, .choosePrimaryText
    call PrintText
    call WaitForTextScrollButtonPress   ; let the prompt be read before the
                                         ; party menu's ClearScreen wipes it
    ld a, $ff
    ldh [hUpdateSpritesEnabled], a
    xor a
    ld [wPartyAndBillsPCSavedMenuItem], a
    ld a, NORMAL_PARTY_MENU
    ld [wPartyMenuTypeOrMessageID], a
    xor a
    ld [wMenuItemToSwap], a
    call DisplayPartyMenu
    push af
    call GBPalWhiteOutWithDelay3
    call ClearSprites
    call RunDefaultPaletteCommand
    call LoadScreenTilesFromBuffer1
    call GBPalNormal                     ; un-white the palette the menu whited
                                         ; out (else the overworld + the
                                         ; "Fusion complete!" text stay invisible)
    pop af
    jp c, .cancelled
    ; Hold the primary index on the STACK across the second DisplayPartyMenu.
    ; hSpriteDataOffset (and the other hSprite* HRAM) is sprite-render scratch
    ; that the party menu's own icon drawing CLOBBERS - storing the primary
    ; index there before the second menu loses it, so the whole fusion bakes
    ; into the wrong mon (flag, type, and moves all land elsewhere). The stack
    ; survives the (balanced) menu call. Both indices are written to HRAM only
    ; AFTER both menus, when nothing else clobbers them.
    ldh a, [hWhichPokemon]
    push af                              ; [stack: primary index]

    ; --- Select SECONDARY ---
    call SaveScreenTilesToBuffer1
    ld hl, .chooseSecondaryText
    call PrintText
    call WaitForTextScrollButtonPress   ; let the prompt be read before the
                                         ; party menu's ClearScreen wipes it
    ld a, $ff
    ldh [hUpdateSpritesEnabled], a
    xor a
    ld [wPartyAndBillsPCSavedMenuItem], a
    ld a, NORMAL_PARTY_MENU
    ld [wPartyMenuTypeOrMessageID], a
    xor a
    ld [wMenuItemToSwap], a
    call DisplayPartyMenu
    push af                              ; [stack: primary index, secondary carry]
    call GBPalWhiteOutWithDelay3
    call ClearSprites
    call RunDefaultPaletteCommand
    call LoadScreenTilesFromBuffer1
    call GBPalNormal                     ; un-white the palette the menu whited
                                         ; out (else the overworld + the
                                         ; "Fusion complete!" text stay invisible)
    pop af                               ; [stack: primary index]; a = secondary carry
    jp c, .cancelledPopPrimary
    ldh a, [hWhichPokemon]
    ld b, a                              ; b = secondary index
    pop af                               ; [stack: empty]; a = primary index
    cp b
    jp z, .sameMon
    ldh [hSpriteDataOffset], a           ; primary index (safe now - both menus done)
    ld a, b
    ldh [hSpriteHeight], a              ; secondary index

    ; --- Cache secondary data while both mons are still in party ---
    ldh a, [hSpriteHeight]
    ld hl, wPartyMons
    ld bc, PARTYMON_STRUCT_LENGTH
    call AddNTimes                       ; hl = secondary struct base

    ; Save secondary species
    ld a, [hl]
    ld [wFusionSecondarySpecies], a

    ; Get secondary type1, then cache it + the secondary's moves/PP into
    ; wFusionSecondaryBaseStats, borrowed here as 5 bytes of scratch:
    ;   [0]=type1  [1]=move0  [2]=move1  [3]=pp0  [4]=pp1
    ; It's free until the stat recalc at the end of this routine refills it, and
    ; nothing reads it in between (only _CalcStat does, and none runs here).
    ld [wCurSpecies], a
    call GetMonHeader                    ; fills wMonHType1
    ld a, [wMonHType1]
    ld [wFusionSecondaryBaseStats + 0], a

    ; Re-derive secondary base (GetMonHeader clobbered hl); cache moves + PP.
    ldh a, [hSpriteHeight]
    ld hl, wPartyMons
    ld bc, PARTYMON_STRUCT_LENGTH
    call AddNTimes                       ; hl = secondary base
    ld bc, MON_MOVES
    add hl, bc                           ; hl = secondary MON_MOVES
    ld a, [hli]
    ld [wFusionSecondaryBaseStats + 1], a   ; move0
    ld a, [hli]
    ld [wFusionSecondaryBaseStats + 2], a   ; move1
    ld bc, MON_PP - MON_MOVES - 2
    add hl, bc                           ; hl = secondary MON_PP
    ld a, [hli]
    ld [wFusionSecondaryBaseStats + 3], a   ; pp0
    ld a, [hl]
    ld [wFusionSecondaryBaseStats + 4], a   ; pp1

    ; --- Apply cached data to primary (de = primary base throughout) ---
    ldh a, [hSpriteDataOffset]
    ld hl, wPartyMons
    ld bc, PARTYMON_STRUCT_LENGTH
    call AddNTimes                       ; hl = primary struct base
    ld d, h
    ld e, l                              ; de = primary base

    ; Read the primary's kept moves (slots 0-1) into b, c for the dedup check.
    ld hl, MON_MOVES
    add hl, de
    ld a, [hli]
    ld b, a                              ; b = primary move0
    ld c, [hl]                           ; c = primary move1

    ; Bake secondary move0 -> primary slot 2, UNLESS it's empty or already one of
    ; the primary's kept moves (option a: skip the dup, leave the primary's own
    ; move in that slot). move1 -> slot 3 the same way; a 1-move secondary falls
    ; out for free (move1 = 0 -> the empty check skips it).
    ld a, [wFusionSecondaryBaseStats + 1]   ; secondary move0
    and a
    jr z, .skipMove0
    cp b
    jr z, .skipMove0
    cp c
    jr z, .skipMove0
    ld hl, MON_MOVES + 2
    add hl, de
    ld [hl], a                           ; move0 -> primary slot 2
    ld hl, MON_PP + 2
    add hl, de
    ld a, [wFusionSecondaryBaseStats + 3]
    ld [hl], a                           ; pp0 -> primary slot 2
.skipMove0

    ld a, [wFusionSecondaryBaseStats + 2]   ; secondary move1
    and a
    jr z, .skipMove1
    cp b
    jr z, .skipMove1
    cp c
    jr z, .skipMove1
    ld hl, MON_MOVES + 3
    add hl, de
    ld [hl], a                           ; move1 -> primary slot 3
    ld hl, MON_PP + 3
    add hl, de
    ld a, [wFusionSecondaryBaseStats + 4]
    ld [hl], a                           ; pp1 -> primary slot 3
.skipMove1

    ; type1 -> primary MON_TYPE2
    ld hl, MON_TYPE2
    add hl, de
    ld a, [wFusionSecondaryBaseStats + 0]
    ld [hl], a

    ; Flag primary as fusion
    ld h, d
    ld l, e
    ld bc, MON_CATCH_RATE
    add hl, bc
    set BIT_FUSION, [hl]

    ; --- Recalculate the primary's stats now, so the max-base bonus applies
    ;     immediately instead of only after the first level-up. Done BEFORE
    ;     RemovePokemon so the primary's index/pointer (de = primary base) is
    ;     still valid; the recalculated stats then travel with the mon through
    ;     the removal's party shuffle. CalcStats uses wCurEnemyLevel for the
    ;     formula, so seed it from the primary's stored level first. ---
    ld h, d
    ld l, e
    push de                              ; save primary base
    ld bc, MON_LEVEL
    add hl, bc
    ld a, [hl]
    ld [wCurEnemyLevel], a
    pop de                               ; de = primary base
    ld hl, MON_STATS
    add hl, de
    ld d, h
    ld e, l                              ; de = primary MON_STATS (stats dest)
    call PrepareFusionCalcStats          ; same bank; sets sentinel + wMonHeader,
                                         ; preserves de
    ld hl, (MON_HP_EXP - 1) - MON_STATS
    add hl, de                           ; hl = primary HP_EXP - 1 (de unchanged)
    ld b, $1                             ; consider stat exp
    call CalcStats                       ; _CalcStats auto-clears the sentinel

    ; --- Release the secondary ---
    ldh a, [hSpriteHeight]
    ldh [hWhichPokemon], a
    xor a
    ld [wRemoveMonFromBox], a
    call RemovePokemon

    ; Restore the overworld after the two party menus. They overwrote the map /
    ; tileset / text-box tiles and left the map view stale, which soft-locks the
    ; player after the fusion until they open+close the party menu - because
    ; that menu's exit runs exactly this ReloadMapData. CloseTextDisplay (when
    ; the "Fusion complete!" box closes) then reloads the sprites on top.
    call ReloadMapData
    xor a
    ldh [hJoyIgnore], a                  ; re-enable the d-pad: the party menu
                                         ; left it masked, which soft-locks
                                         ; movement (START still works, walking
                                         ; doesn't) until the real party menu's
                                         ; exit clears it - do it ourselves here

    ld hl, .fusionCompleteText
    call PrintText
    ret

.cancelledPopPrimary
    pop af                               ; discard the saved primary index
    ; fall through
.cancelled
    ret

.alreadyFused
    ld hl, .alreadyFusedText
    call PrintText
    ret

.notEnoughMons
    ld hl, .notEnoughMonsText
    call PrintText
    ret

.sameMon
    ld hl, .sameMonText
    call PrintText
    ret

.choosePrimaryText
    text "Choose primary"
    line "POKEMON.@"
    text_end

.chooseSecondaryText
    text "Choose secondary"
    line "POKEMON.@"
    text_end

.alreadyFusedText
    text "Already fused"
    line "this run!@"
    text_end

.notEnoughMonsText
    text "Need at least"
    line "2 POKEMON!@"
    text_end

.sameMonText
    text "Can't fuse with"
    line "the same POKEMON!@"
    text_end

.fusionCompleteText
    text "Fusion complete!@"
    text_end

; ---------------------------------------------------------------------------
; DrawFusionStatusFrontPic
; Phase 4a: adds the fusion secondary's front sprite as a lower-right
; diagonal triangle on top of the status screen's front pic.
;
; CALLER CONTRACT: the status screen's normal
; LoadFlippedFrontSpriteByMonIndex call must have ALREADY run before this is
; called - that call draws the PRIMARY's flipped front sprite into vFrontPic
; ($9000, BG tile IDs $00-$30 in the menu's $8800-signed addressing) and
; fills the tilemap's upper-left triangle. This routine only adds the
; secondary on top of that; it does not touch the primary's tiles/pixels.
;
; Technique mirrors engine/events/hidden_events/rogue_pokemon.asm ::
; DisplayDiagonalTest (proven reference - hardcoded Charizard/Blastoise
; diagonal split at a different screen position, hlcoord 5,5). Same two
; ingredients: (1) load a second mon's front sprite into a free VRAM pic
; region, (2) overwrite part of wTileMap with that region's tile IDs.
;
; Step 1 loads wFusionSecondarySpecies's front sprite into vBackPic
; ($9310), which is unused by the status screen and maps to BG tile IDs
; $31-$61 (49 tiles, 7x7) in $8800 mode - directly after vFrontPic's
; $00-$30 range. wSpriteFlipped is forced on for the load so the secondary
; mirrors the same way the primary already does (both halves then face the
; same direction instead of mismatching at the seam).
;
; Step 2 is the diagonal overwrite itself. FIRST CUT - the diagonal
; threshold (sx+sy>=7) and the flip handling are TUNABLE and need emulator
; verification; this is un-tested math, not a confirmed-correct blend.
; Per-cell rule (screen coords sx,sy each 0-6, only where sx+sy>=7):
;     tile ID  = $31 + (6-sx)*7 + sy
;     address  = wTileMap + 1 + sx + sy*20
; This is a nested loop (outer sy 0..6, inner sx 0..6) unrolled into one
; block per sy, since for a fixed sy the qualifying sx run from (7-sy) to 6
; is contiguous: as sx steps up by 1, address steps up by 1 (inc hl) and
; tile ID steps down by 7 (sub 7), so each row is a simple counted loop
; from its starting (address, tile ID) pair - same shape as
; DisplayDiagonalTest's per-column blocks, just row-major instead of
; column-major and stepping by 1 instead of by SCREEN_WIDTH. sy=0 has zero
; qualifying sx (7-0=7 is out of the 0-6 range) so it's omitted entirely -
; the top row stays 100% primary.
;
; Per-row starting values (hand-verified against the formulas above):
;   sy=1: 1 tile,  start addr wTileMap+27,  start tile $32
;   sy=2: 2 tiles, start addr wTileMap+46,  start tile $3A
;   sy=3: 3 tiles, start addr wTileMap+65,  start tile $42
;   sy=4: 4 tiles, start addr wTileMap+84,  start tile $4A
;   sy=5: 5 tiles, start addr wTileMap+103, start tile $52
;   sy=6: 6 tiles, start addr wTileMap+122, start tile $5A
;
; INPUT: none (reads wFusionSecondarySpecies; assumes primary pic already
;        drawn per the caller contract above)
; CLOBBERS: af, bc, de, hl, wCurPartySpecies, wCurSpecies, wMonHeader,
;           wSpriteFlipped (restored to 0 before return)
; ---------------------------------------------------------------------------
; Split into two halves (see the tile-math notes above): the secondary's SLOW
; ROM sprite load happens BEFORE the primary is on screen (no "primary first,
; then secondary" flicker), and the FAST tilemap overlay happens after.
;
; PreloadFusionSecondaryPic
; Call BEFORE the status screen draws the primary pic. Loads the secondary's
; front sprite (flipped) into vBackPic, then restores wMonHeader / wCurSpecies /
; wCurPartySpecies to the PRIMARY. That restore is critical: (a) the primary pic
; draw that follows reads wMonHeader (leave it as the secondary and you draw the
; secondary's sprite as the "primary"); (b) StatusScreen2 draws the page-2 name
; from wMonHIndex via GetMonName, so a stale secondary there shows the wrong name.
; CLOBBERS: af, bc, de, hl, wSpriteFlipped (restored to 0)
PreloadFusionSecondaryPic::
    ; Shin Red import Phase 6: vBackPic is only "free" scratch on the OVERWORLD
    ; status screen. The battle party menu reaches StatusScreen too
    ; (engine/battle/core.asm, the "Stats" option), and there vBackPic holds the
    ; player's back pic - staging the secondary's front sprite into it would
    ; destroy the player's sprite, and core.asm's return path only reloads the
    ; ENEMY pic, so the corruption would persist until the next send-out. Skip
    ; the whole overlay in battle: the fusion mon shows its primary sprite only.
    ; OverlayFusionSecondaryPic below carries the same guard, and the two must
    ; stay in lockstep (overlaying without preloading would point the tilemap at
    ; whatever is in vBackPic).
    ldh a, [hIsInBattle]
    and a
    ret nz
    ld a, [wCurPartySpecies]
    push af                          ; primary species
    ld a, 1
    ld [wSpriteFlipped], a
    ld a, [wFusionSecondarySpecies]
    ld [wCurPartySpecies], a
    ld [wCurSpecies], a
    call GetMonHeader
    ld de, vBackPic
    call LoadMonFrontSprite
    xor a
    ld [wSpriteFlipped], a
    pop af                           ; primary species
    ld [wCurPartySpecies], a
    ld [wCurSpecies], a
    call GetMonHeader                ; restore the PRIMARY's header (wMonHIndex etc.)
    ret

; OverlayFusionSecondaryPic
; Call AFTER the primary pic is drawn. Overwrites the tilemap's lower-right
; triangle with the secondary's tile IDs (already staged in vBackPic by
; PreloadFusionSecondaryPic). CLOBBERS: af, b, hl
OverlayFusionSecondaryPic::
    ; Shin Red import Phase 6: paired with PreloadFusionSecondaryPic's guard
    ; above. In battle nothing was staged into vBackPic, so these tile IDs would
    ; point at the player's back pic.
    ldh a, [hIsInBattle]
    and a
    ret nz
    ; sy=1: 1 tile
    ld hl, wTileMap + 27
    ld a, $32
    ld [hl], a

    ; sy=2: 2 tiles
    ld hl, wTileMap + 46
    ld a, $3A
    ld b, 2
.row2
    ld [hl], a
    inc hl
    sub 7
    dec b
    jr nz, .row2

    ; sy=3: 3 tiles
    ld hl, wTileMap + 65
    ld a, $42
    ld b, 3
.row3
    ld [hl], a
    inc hl
    sub 7
    dec b
    jr nz, .row3

    ; sy=4: 4 tiles
    ld hl, wTileMap + 84
    ld a, $4A
    ld b, 4
.row4
    ld [hl], a
    inc hl
    sub 7
    dec b
    jr nz, .row4

    ; sy=5: 5 tiles
    ld hl, wTileMap + 103
    ld a, $52
    ld b, 5
.row5
    ld [hl], a
    inc hl
    sub 7
    dec b
    jr nz, .row5

    ; sy=6: 6 tiles
    ld hl, wTileMap + 122
    ld a, $5A
    ld b, 6
.row6
    ld [hl], a
    inc hl
    sub 7
    dec b
    jr nz, .row6

    ; --- push the tilemap edit to VRAM ---
    ld a, 1
    ldh [hAutoBGTransferEnabled], a
    call Delay3
    ret

; ---------------------------------------------------------------------------
; MergeFusionBackPic
; Phase 4c - FIRST CUT. Battle send-out equivalent of the status-screen
; diagonal (DrawFusionStatusFrontPic / OverlayFusionSecondaryPic above), but
; for the player's BACK pic instead of the front pic, and via VRAM tile
; overwrite instead of a tilemap swap (the back pic is one contiguous chunk
; of BG tiles, there's no per-cell tile-ID indirection to exploit the way the
; front pic's $8800-signed tilemap allows).
;
; CALLER CONTRACT: `predef LoadMonBackPic` (engine/battle/core.asm) must have
; ALREADY run before this is called. That leaves the PRIMARY's back pic in
; BOTH vBackPic (VRAM, 49 tiles, what's actually on screen) and sSpriteBuffer1
; (SRAM, 784 bytes = SPRITEBUFFERSIZE*2, LoadMonBackPic's merge scratch) -
; both column-major, tile (c,r) at byte offset (c*7+r)*16.
;
; This routine reruns LoadMonBackPic's own pipeline (UncompressMonSprite ->
; ScaleSpriteByTwo -> a replicated InterlaceMergeSpriteBuffers merge, see
; that routine and home/pics.asm for the originals) for the SECONDARY, but
; stops before the final CopyVideoData/VRAM write - so the merge result lands
; back in sSpriteBuffer1, overwriting the primary's copy there while vBackPic
; (VRAM) still shows the primary untouched. It then copies just the
; lower-right diagonal's tiles (columns 1-6, the run where column+row >= 7)
; from sSpriteBuffer1 into vBackPic, so the final on-screen pic is primary
; upper-left / secondary lower-right. Column 0 and the upper-left triangle
; are never touched and stay 100% primary.
;
; The diagonal threshold and the exact (offset,count) pairs below are
; TUNABLE and un-tested against the real animated back-pic sprite - this
; mirrors OverlayFusionSecondaryPic's front-pic math (sx+sy>=7) but the back
; pic is UNFLIPPED, so unlike the front-pic case there's no mirroring to
; account for; the six runs are simply the lower-right triangle read
; column-major:
;   column 1: tile offset 13, count 1
;   column 2: tile offset 19, count 2
;   column 3: tile offset 25, count 3
;   column 4: tile offset 31, count 4
;   column 5: tile offset 37, count 5
;   column 6: tile offset 43, count 6
; (byte offset = tile offset * 16; CopyVideoData takes a tile count in c)
;
; INPUT: none (reads wFusionSecondarySpecies; assumes LoadMonBackPic already
;        ran for the primary per the caller contract above)
; CLOBBERS: af, bc, de, hl, wCurPartySpecies, wCurSpecies, wMonHeader,
;           sSpriteBuffer0-2 (secondary's merge scratch), rRAMB, rROMB,
;           hLoadedROMBank, hSpriteInterlaceCounter
; ---------------------------------------------------------------------------
MergeFusionBackPic::
    ; --- Load the secondary's header, saving the primary's species to restore
    ;     at the end (step 6). ---
    ld a, [wCurPartySpecies]
    push af                          ; primary species
    ld a, [wFusionSecondarySpecies]
    ld [wCurPartySpecies], a
    ld [wCurSpecies], a
    call GetMonHeader                ; wMonHeader = secondary's attributes

    ; --- Run the secondary through LoadMonBackPic's own pipeline, stopping
    ;     short of the VRAM write. This does NOT touch vBackPic/VRAM - it
    ;     only fills sSpriteBuffer0-2 the same way LoadMonBackPic does. ---
    ld hl, wMonHBackSprite - wMonHeader
    call UncompressMonSprite
    predef ScaleSpriteByTwo

    ; --- Replicated InterlaceMergeSpriteBuffers merge (home/pics.asm), minus
    ;     the wSpriteFlipped nybble-swap block and minus the final
    ;     pop hl / CopyVideoData - the merged secondary just needs to land in
    ;     sSpriteBuffer1, not go to VRAM. ---
    xor a
    ld [rRAMB], a
    ld hl, sSpriteBuffer2 + (SPRITEBUFFERSIZE - 1) ; destination: end of buffer 2
    ld de, sSpriteBuffer1 + (SPRITEBUFFERSIZE - 1) ; source 2: end of buffer 1
    ld bc, sSpriteBuffer0 + (SPRITEBUFFERSIZE - 1) ; source 1: end of buffer 0
    ld a, SPRITEBUFFERSIZE / 2
    ldh [hSpriteInterlaceCounter], a
.interlaceLoop
    ld a, [de]
    dec de
    ld [hld], a   ; write byte of source 2
    ld a, [bc]
    dec bc
    ld [hld], a   ; write byte of source 1
    ld a, [de]
    dec de
    ld [hld], a   ; write byte of source 2
    ld a, [bc]
    dec bc
    ld [hld], a   ; write byte of source 1
    ldh a, [hSpriteInterlaceCounter]
    dec a
    ldh [hSpriteInterlaceCounter], a
    jr nz, .interlaceLoop
    ; secondary's merged 2bpp sprite is now in sSpriteBuffer1 (through
    ; sSpriteBuffer2); vBackPic/VRAM still holds the primary untouched.

    ; --- Copy the 6 diagonal column-runs from sSpriteBuffer1 (secondary) into
    ;     vBackPic (VRAM, currently the primary), overwriting the lower-right
    ;     triangle only. ---
    ldh a, [hLoadedROMBank]
    ld b, a
    ld hl, vBackPic + (13 * 16)
    ld de, sSpriteBuffer1 + (13 * 16)
    ld c, 1
    call CopyVideoData

    ldh a, [hLoadedROMBank]
    ld b, a
    ld hl, vBackPic + (19 * 16)
    ld de, sSpriteBuffer1 + (19 * 16)
    ld c, 2
    call CopyVideoData

    ldh a, [hLoadedROMBank]
    ld b, a
    ld hl, vBackPic + (25 * 16)
    ld de, sSpriteBuffer1 + (25 * 16)
    ld c, 3
    call CopyVideoData

    ldh a, [hLoadedROMBank]
    ld b, a
    ld hl, vBackPic + (31 * 16)
    ld de, sSpriteBuffer1 + (31 * 16)
    ld c, 4
    call CopyVideoData

    ldh a, [hLoadedROMBank]
    ld b, a
    ld hl, vBackPic + (37 * 16)
    ld de, sSpriteBuffer1 + (37 * 16)
    ld c, 5
    call CopyVideoData

    ldh a, [hLoadedROMBank]
    ld b, a
    ld hl, vBackPic + (43 * 16)
    ld de, sSpriteBuffer1 + (43 * 16)
    ld c, 6
    call CopyVideoData

    ; --- Restore the primary's header so nothing downstream (AnimateSendingOutMon,
    ;     PlayCry, etc.) is confused about which mon is active. ---
    pop af                           ; primary species
    ld [wCurPartySpecies], a
    ld [wCurSpecies], a
    call GetMonHeader
    ret
