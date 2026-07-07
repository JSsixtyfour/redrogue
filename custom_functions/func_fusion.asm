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
; INPUT: hl = pointer to the mon's struct base (MON_SPECIES field)
; OUTPUT: Z set = not fusion, Z clear (NZ) = is fusion
; CLOBBERS: af, de, hl
; ---------------------------------------------------------------------------
IsFusionMon::
	ld de, MON_CATCH_RATE
	add hl, de
	bit BIT_FUSION, [hl]
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
