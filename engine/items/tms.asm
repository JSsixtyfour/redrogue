; tests if mon [wCurPartySpecies] can learn move [wMoveNum]
; Fusion (Phase 5a): a fusion can learn any TM that EITHER of its two species
; can learn. Non-fusions take the stock path below, byte-for-byte unchanged.
;
; HISTORY (2026-07-16): this was reverted once, when WRAM corruption (wild
; battles triggering indoors, MissingNo encounters, crashes) showed up during
; TM testing. That corruption was later reproduced on a PRE-FUSION build
; (commit 02364531, which has the custom TM bag but no fusion code at all), so
; it lives in the custom TM system (tm_bag.asm / sTMBitfield), NOT here.
; Reinstated. Do not re-revert this routine for that symptom.
;
; hWhichPokemon is the party index at BOTH call sites: party_menu.asm sets it
; from its draw-loop counter (party_menu.asm:34-35) right before the
; .teachMoveMenu branch, and item_effects.asm reads it immediately after its
; own predef call. Neither call site passes a boxed mon.
;
; Post-conditions match stock exactly: wMonHeader holds the PRIMARY's header
; and wCurSpecies == wCurPartySpecies on every return path, so callers that
; lean on that ambient state (the draw loop's .printLevel path) see no change.
CanLearnTM:
	; de = party mon struct base (IsFusionMon's input - farcall preserves de but
	; NOT hl, so the pointer must travel in de).
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	farcall IsFusionMon
	jr nz, .fusionMon

; --- stock path: non-fusion mons ---
	ld a, [wCurPartySpecies]
	ld [wCurSpecies], a
	call GetMonHeader
	ld hl, wMonHLearnset
	push hl
	ld a, [wMoveNum]
	ld b, a
	ld c, $0
	ld hl, TechnicalMachines
.findTMloop
	ld a, [hli]
	cp b
	jr z, .TMfoundLoop
	inc c
	jr .findTMloop
.TMfoundLoop
	pop hl
	ld b, FLAG_TEST
	predef_jump FlagActionPredef

; --- fusion path: OR the two species' learnset bits ---
; We split the TM index into a byte offset and a bit mask by hand rather than
; calling FlagAction twice: the same bit is tested against two different
; learnsets, and keeping the mask in registers survives the GetMonHeader call
; that swaps wMonHLearnset out from under us between the two tests.
.fusionMon
	ld a, [wMoveNum]
	ld b, a
	ld c, $0
	ld hl, TechnicalMachines
.findTMloopFusion
	ld a, [hli]
	cp b
	jr z, .TMfoundFusion
	inc c
	jr .findTMloopFusion
.TMfoundFusion
; c = 0-based TM index. Mask and offset math mirrors engine/flag_action.asm:
; byte = index >> 3, mask = 1 << (index & 7), LSB-first.
	ld a, c
	and $07
	inc a
	ld b, $01
.maskLoop
	dec a
	jr z, .maskDone
	sla b
	jr .maskLoop
.maskDone
	ld e, b                          ; e = bit mask (preserved across GetMonHeader)
	ld a, c
	srl a
	srl a
	srl a
	ld d, a                          ; d = byte offset into the learnset

; test the PRIMARY species
	ld a, [wCurPartySpecies]
	ld [wCurSpecies], a
	call GetMonHeader
	ld hl, wMonHLearnset
	ld b, $00
	ld c, d
	add hl, bc
	ld a, [hl]
	and e
	jr nz, .fusionCanLearn           ; header is already the primary's - no restore needed

; test the SECONDARY species
	ld a, [wFusionSecondarySpecies]
	ld [wCurSpecies], a
	call GetMonHeader
	ld hl, wMonHLearnset
	ld b, $00
	ld c, d
	add hl, bc
	ld a, [hl]
	and e
	push af
	call .restorePrimaryHeader
	pop af
	and a
	jr nz, .fusionCanLearn
	ld c, $00                        ; neither species can learn it
	ret
.fusionCanLearn
	ld c, $01
	ret

.restorePrimaryHeader
	ld a, [wCurPartySpecies]
	ld [wCurSpecies], a
	jp GetMonHeader

; converts TM/HM number in [wTempTMHM] into move number
; HMs start at 51
TMToMove:
	ld a, [wTempTMHM]
	dec a
	ld hl, TechnicalMachines
	ld b, $0
	ld c, a
	add hl, bc
	ld a, [hl]
	ld [wTempTMHM], a
	ret

INCLUDE "data/moves/tmhm_moves.asm"
