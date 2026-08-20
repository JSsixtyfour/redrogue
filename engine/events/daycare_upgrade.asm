; =============================================================================
; Daycare retrieval upgrades (Shin Red import Phase 10)
;
; Ported from shinpokered's DaycareMoveLearning / DaycareEvolution
; (its scripts/daycarem.asm), adapted to this fork. Deviations from the
; reference, all deliberate:
;   * shinpokered sets bit 6 of its wFlags_D733 around both routines. That bit
;     is a joenote-only addition (ghost battle / "learn skipped moves as if in
;     a battle" / sprite refresh during the move-forget list) and has no
;     equivalent here, so it is not ported.
;   * shinpokered also seeds wStartBattleLevels so its own evolution path
;     re-learns skipped moves. This fork's evolution path only learns moves at
;     exactly [wCurEnemyLevel], so instead we run our own move-learning pass
;     again after each evolution - see DaycareRetrieveUpgrade below.
;   * shinpokered starts its level cursor AT the deposit level. We start one
;     level above it, matching what the WriteMonMoves call this replaces did
;     (it skipped every move whose level was <= wDayCareStartLevel), so a mon
;     is never re-prompted for a move it already declined before the deposit.
;
; This section floats; every entry point is reached by farcall from a map
; script, so it does not need to live in any particular bank.
; =============================================================================

SECTION "Daycare Upgrade", ROMX

; -----------------------------------------------------------------------------
; DaycareRetrieveUpgrade
; Call right after MoveMon has appended the retrieved mon to the party, and
; BEFORE the caller's HP-to-max write (evolving changes MaxHP).
;
; Teaches every level-up move the mon would have learned while it was away,
; prompting for one to forget when its moveset is full, then evolves it if it
; passed an evolution level - up to twice, learning the new form's missed moves
; between and after each evolution.
;
; INPUT:  the retrieved mon is the LAST party mon (MoveMon always appends)
;         [wDayCareStartLevel] = the level it had when it was deposited
;           NOTE: slot 2 (the Indigo lobby Lady) keeps its own copy in
;           wDayCareStartLevel2 and copies it into wDayCareStartLevel just
;           before calling. That is safe: wDayCareStartLevel is rewritten from
;           wDayCareMonBoxLevel at the top of every slot-1 interaction and is
;           only read again inside that same interaction, so it holds nothing
;           worth preserving between conversations.
; OUTPUT: nothing. [hWhichPokemon] = the mon's party index on return.
; Call with farcall.
; -----------------------------------------------------------------------------
DaycareRetrieveUpgrade::
; Same save/zero/restore of the text-delay flags that BridgeTeachMoveToCurrent
; (engine/events/bridge_gift_menu.asm) already does around an out-of-battle
; predef LearnMove.
	ld a, [wLetterPrintingDelayFlags]
	push af
	xor a
	ld [wLetterPrintingDelayFlags], a

	call .learnMissedMoves
	call .tryEvolve
	jr z, .finish              ; species unchanged - nothing evolved
	call .learnMissedMoves     ; the new form's moves across the same span
	call .tryEvolve            ; a second, chained evolution
	jr z, .finish
	call .learnMissedMoves

.finish
	pop af
	ld [wLetterPrintingDelayFlags], a
	ret

; ---------------------------------------------------------------------------
; Walks the level cursor from [wDayCareStartLevel] + 1 up to the mon's current
; level, running the normal level-up learn flow at each step. That flow is what
; supplies the forget-a-move prompt the plain WriteMonMoves call never had.
; ---------------------------------------------------------------------------
.learnMissedMoves
	ld a, [wPartyCount]
	dec a
	ldh [hWhichPokemon], a
	ld bc, PARTYMON_STRUCT_LENGTH
	ld hl, wPartyMon1Level
	call AddNTimes
	ld a, [hl]
	ld e, a                    ; e = the mon's level now
	ld a, [wDayCareStartLevel]
	ld d, a                    ; d = level cursor
.learnLoop
	ld a, d
	cp e
	ret nc                     ; cursor has caught up with the current level
	inc d
	ld a, d
	ld [wCurEnemyLevel], a
; Re-established every pass: LearnMoveFromLevelUp uses wCurPartySpecies and
; wPokedexNum as its own scratch, so neither can be assumed to survive a pass.
	ldh a, [hWhichPokemon]
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl]
	ld [wPokedexNum], a        ; LearnMoveFromLevelUp reads the species here
	xor a
	ld [wMonDataLocation], a   ; PLAYER_PARTY_DATA
	push de
	predef LearnMoveFromLevelUp
	pop de
	jr .learnLoop

; ---------------------------------------------------------------------------
; One evolution attempt, run exactly the way an after-battle evolution runs.
; Returns with Z SET if the species did not change, Z CLEAR if it evolved.
;
; Z is taken from a before/after species comparison rather than from
; wEvolutionOccurred, because this fork's CancelledEvolution leaves
; wEvolutionOccurred set to 1 (shinpokered sets it to 2 there and tests for
; that). wEvolutionOccurred is still the right test for "did the evolution
; SCREEN appear", which is what the restore below keys off - a cancelled
; evolution trashes the screen just as much as a completed one.
; ---------------------------------------------------------------------------
.tryEvolve
	ld a, [wPartyCount]
	dec a
	ldh [hWhichPokemon], a
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl]
; The pre-evolution species is kept on OUR stack frame rather than in a register.
; EvolutionAfterBattle looks like it preserves de (it pushes de on entry and pops
; it at .done), but .done then runs `call nz, PlayDefaultMusic` AFTER that pop on
; exactly the path an evolution takes, and the screen restore below walks de as a
; copy cursor too. TryEvolvingMon does leave the stack balanced, so a value
; pushed here survives no matter what it does to the registers.
	push af
	xor a
	ld [wMonDataLocation], a   ; PLAYER_PARTY_DATA
	ld [wForceEvolution], a    ; 0 = allow EVOLVE_LEVEL entries
; wCurItem IS wCurPartySpecies - one byte, two labels (see the
; project_wcuritem_species_alias note). EvolutionAfterBattle's EVOLVE_ITEM
; branch compares the entry's evolution stone against [wCurItem], so leaving
; the mon's own species ID sitting there can fire a stone evolution the player
; never triggered. Park a 0 in it for the duration and put the live species
; back afterwards.
	ld [wCurPartySpecies], a

	callfar TryEvolvingMon
	ld a, [wEvolutionOccurred]
	and a
	jr z, .noScreenToRestore
; The evolution screen replaced the map. Buffer2 still holds the screen the
; daycare script saved with SaveScreenTilesToBuffer2 when the conversation
; opened, which is the same buffer its party-menu path restores from.
	call WaitForSoundToFinish
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
.noScreenToRestore
	xor a
	ld [wEvolutionOccurred], a
	ld a, [wPartyCount]
	dec a
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl]
	ld [wCurPartySpecies], a   ; restore the aliased byte to the live species
	pop bc                     ; b = the species pushed before the attempt
	                           ; (pop does not touch flags, and a still holds
	                           ; the species as it stands now)
	cp b                       ; Z set = species unchanged = nothing evolved
	ret
