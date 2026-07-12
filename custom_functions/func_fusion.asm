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
    ; TMHM_PARTY_MENU type: picks and returns immediately on A, no sub-menu.
    ; hUpdateSpritesEnabled = $ff required for party sprites to render.
    call SaveScreenTilesToBuffer1
    ld hl, .choosePrimaryText
    call PrintText
    ld a, $ff
    ldh [hUpdateSpritesEnabled], a
    xor a
    ld [wPartyAndBillsPCSavedMenuItem], a
    ld a, TMHM_PARTY_MENU
    ld [wPartyMenuTypeOrMessageID], a
    xor a
    ld [wMenuItemToSwap], a
    call DisplayPartyMenu
    push af
    call GBPalWhiteOutWithDelay3
    call ClearSprites
    call RunDefaultPaletteCommand
    call LoadScreenTilesFromBuffer1
    pop af
    jp c, .cancelled
    ldh a, [hWhichPokemon]
    ldh [hSpriteDataOffset], a          ; primary index

    ; --- Select SECONDARY ---
    call SaveScreenTilesToBuffer1
    ld hl, .chooseSecondaryText
    call PrintText
    ld a, $ff
    ldh [hUpdateSpritesEnabled], a
    xor a
    ld [wPartyAndBillsPCSavedMenuItem], a
    ld a, TMHM_PARTY_MENU
    ld [wPartyMenuTypeOrMessageID], a
    xor a
    ld [wMenuItemToSwap], a
    call DisplayPartyMenu
    push af
    call GBPalWhiteOutWithDelay3
    call ClearSprites
    call RunDefaultPaletteCommand
    call LoadScreenTilesFromBuffer1
    pop af
    jp c, .cancelled
    ldh a, [hWhichPokemon]
    ld b, a                              ; b = secondary candidate index
    ldh a, [hSpriteDataOffset]           ; a = primary index
    cp b
    jp z, .sameMon
    ld a, b                              ; restore secondary index to a
    ldh [hSpriteHeight], a              ; secondary index

    ; --- Cache secondary data while both mons are still in party ---
    ldh a, [hSpriteHeight]
    ld hl, wPartyMons
    ld bc, PARTYMON_STRUCT_LENGTH
    call AddNTimes                       ; hl = secondary struct base

    ; Save secondary species
    ld a, [hl]
    ld [wFusionSecondarySpecies], a

    ; Get secondary type1
    ld [wCurSpecies], a
    call GetMonHeader                    ; fills wMonHType1
    ld a, [wMonHType1]
    push af                              ; push 1: secondary type1

    ; Re-derive secondary base (GetMonHeader clobbered hl)
    ldh a, [hSpriteHeight]
    ld hl, wPartyMons
    ld bc, PARTYMON_STRUCT_LENGTH
    call AddNTimes

    ; Cache moves[0..1]
    ld bc, MON_MOVES
    add hl, bc
    ld a, [hli]
    push af                              ; push 2: secondary move[0]
    ld a, [hli]
    push af                              ; push 3: secondary move[1]
    ; hl = secondary_base + MON_MOVES + 2; advance to MON_PP
    ; MON_PP - (MON_MOVES + 2) = 19
    ld bc, MON_PP - MON_MOVES - 2
    add hl, bc
    ld a, [hli]
    push af                              ; push 4: secondary pp[0]
    ld a, [hl]
    push af                              ; push 5: secondary pp[1]

    ; --- Apply cached data to primary (de holds primary base throughout) ---
    ldh a, [hSpriteDataOffset]
    ld hl, wPartyMons
    ld bc, PARTYMON_STRUCT_LENGTH
    call AddNTimes                       ; hl = primary struct base
    ld d, h
    ld e, l

    ; pp[1] → primary MON_PP + 3
    ld h, d
    ld l, e
    ld bc, MON_PP + 3
    add hl, bc
    pop af
    ld [hl], a

    ; pp[0] → primary MON_PP + 2
    ld h, d
    ld l, e
    ld bc, MON_PP + 2
    add hl, bc
    pop af
    ld [hl], a

    ; move[1] → primary MON_MOVES + 3
    ld h, d
    ld l, e
    ld bc, MON_MOVES + 3
    add hl, bc
    pop af
    ld [hl], a

    ; move[0] → primary MON_MOVES + 2
    ld h, d
    ld l, e
    ld bc, MON_MOVES + 2
    add hl, bc
    pop af
    ld [hl], a

    ; type1 → primary MON_TYPE2
    ld h, d
    ld l, e
    ld bc, MON_TYPE2
    add hl, bc
    pop af
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

    ld hl, .fusionCompleteText
    call PrintText
    ret

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
