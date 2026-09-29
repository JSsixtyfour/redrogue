; Player-state accessor seam (AI_OVERHAUL_PLAN.md). Every heuristic reads the
; player's state through these rather than touching wBattleMon* directly.
;
; Phase 7 (2026-08-26) landed the fair-play decision locked in
; 2026-08-25: hide the MOVESET only. Type, status and HP stay live at every
; tier forever - a human opponent can see all of those on screen, so hiding
; them would read as artificial rather than fair. AIGetTargetType1/2 and
; AIGetTargetStatus are therefore UNCHANGED and always return live data.
; AIGetPlayerMoveN is the one routine that decides what the AI knows about the
; player's MOVESET. Since the 2026-09-29 review (Phase 2) every tier plays fair:
; it reads wAISeenPlayerMoveMask, which marks only moves this party member has
; used this battle (populated by AITrackSeenPlayerMove, ai_fairplay.asm, bank
; $2C, hooked at engine/battle/core.asm's PlayerCanExecuteMove), plus a guess
; from the player's visible types for unseen slots 0/1. Omniscience is now a
; per-class opt-in (AIOmniscientClasses below), not a tier flag. No heuristic
; needed editing: every consumer already goes through this seam.
;
; INCLUDEd into "Battle Engine 7" (bank $0E), same bank as trainer_ai.asm and
; every AILayer* routine. These MUST be in this bank, for two independent
; reasons, and they were not until Phase 3 Step 2:
;
; 1. They are called from inside the per-move scoring loop, so the Phase 2a rule
;    applies (see ai_score_helpers.asm's header and ROM_BIBLE.md's 2026-08-25
;    entries): a plain same-bank `call` is the only cheap way to reach them, and
;    a plain `call` to another bank is undefined behaviour that assembles and
;    links silently.
;
; 2. AIGetPlayerMoveN takes its input in `a`, and `a` CANNOT survive a farcall -
;    Bankswitch's very first instruction is `ldh a, [hLoadedROMBank]`, which
;    overwrites the argument before the callee runs. So this routine is not
;    merely cheaper in-bank, it is impossible to call correctly out-of-bank
;    without changing its contract. See project_farcall_home_clobbers_a.
;
; BUG HISTORY: these lived in ai_core.asm (a separately-floated section that
; landed in bank $06) through Phase 2b, while AISmart_DreamEater in bank $0E did
; a plain `call AIGetTargetStatus`. That call resolved to $0E:7FA8 - inside this
; bank's empty tail - so on the release ROMs (padded $00 = `nop`) it slid
; through the padding and off the end of the bank into VRAM, and on the debug
; ROM (padded $FF) it hit `rst $38`. It never fired in testing only because no
; scenario gave an enemy a Dream Eater move, which is the same
; "the covered path was the no-op path" gap that hid the Phase 2a bugs.

; OUTPUT: a = the player mon's first type.
AIGetTargetType1::
	ld a, [wBattleMonType1]
	ret

; OUTPUT: a = the player mon's second type.
AIGetTargetType2::
	ld a, [wBattleMonType2]
	ret

; OUTPUT: a = the player mon's status byte.
AIGetTargetStatus::
	ld a, [wBattleMonStatus]
	ret

; INPUT:  a = move slot 0-3
; OUTPUT: a = the move id the AI believes is in that slot, 0 if none/unknown.
; Clobbers bc, de, hl. No farcall: the whole decision is in this bank.
;
; The only consumer is _AIScanPlayerMovesForKO (ai_threat.asm), a damage-threat
; scan. That matters for the type guess below: a guessed move can only ever
; feed a damage estimate, never Disable/Mirror Move style logic that needs the
; player's REAL move.
AIGetPlayerMoveN::
	ld c, a
	call AIPlayerMovesAreKnown
	jr c, .omniscient
; Fair play: the slot is known only if THIS party member revealed it. The mask
; layout is documented at wAISeenPlayerMoveMask (ram/wram.asm).
	ld b, 1
	ld a, c
	and a
	jr z, .gotSlotBit
.shiftSlotBit
	sla b
	dec a
	jr nz, .shiftSlotBit
.gotSlotBit
	ld a, [wPlayerMonNumber]
	srl a ; a = mask byte, carry = odd party slot (high nibble)
	jr nc, .gotNibble
	swap b
.gotNibble
	ld e, a
	ld d, 0
	ld hl, wAISeenPlayerMoveMask
	add hl, de
	ld a, [hl]
	and b
	jr z, .guess ; not revealed by this mon
.omniscient
	ld hl, wBattleMonMoves
	ld a, c
	ld d, 0
	ld e, a
	add hl, de
	ld a, [hl]
.exit ; named for hookability (project convention); a holds the result here
	ret

; Unseen slot. Slot 0 guesses a STAB move of the player's first type, slot 1
; of its second type (mono-types get one guess). Types are on screen, so this
; is still fair play; it keeps a turn-1 threat check from reading "no threat"
; just because nothing has been used yet. A guess fills only a slot that holds
; a real move, so a one-move mon does not carry a permanent phantom attack, and
; each guess disappears the moment that slot's real move is revealed.
.guess
	ld a, c
	cp 2
	jr nc, .unknown ; slots 2-3: no guess
	ld hl, wBattleMonMoves
	ld d, 0
	ld e, c
	add hl, de
	ld a, [hl]
	and a
	jr z, .exit ; empty slot: nothing to guess (a = 0)
	ld a, c
	and a
	ld a, [wBattleMonType1] ; ld keeps the flags from `and a`
	jr z, .lookUpGuess
	ld a, [wBattleMonType2]
	ld b, a
	ld a, [wBattleMonType1]
	cp b
	jr z, .unknown ; mono-type: slot 0 already guessed this type
	ld a, b
.lookUpGuess
	cp NUM_TYPES
	jr nc, .unknown
	ld e, a ; d is still 0
	ld hl, AIStabGuessByType
	add hl, de
	ld a, [hl]
	jr .exit ; every return goes through .exit, the hookable result point
.unknown
	xor a
	jr .exit

; Carry SET if this trainer class sees the player's full moveset.
; Clobbers af, b, hl. Preserves c (AIGetPlayerMoveN's slot).
AIPlayerMovesAreKnown:
	ld a, [wTrainerClass]
	ld b, a
	ld hl, AIOmniscientClasses
.next
	ld a, [hli]
	cp $ff
	jr z, .no
	cp b
	jr nz, .next
	scf
	ret
.no
	and a
	ret

; TUNING KNOB: trainer classes that see the player's full moveset. Every other
; trainer plays fair at every tier. One line per class, e.g. a gym leader
; class or a miniboss; $ff terminates.
AIOmniscientClasses:
	db FINAL_AI ; the final trainer keeps full knowledge (user decision 2026-09-29)
	db $ff

; TUNING KNOB: the move an unseen slot is assumed to hold, per player type.
; Typical Gen 1 threats of each type; 0 = no guess. Indexed by type id.
AIStabGuessByType:
	db BODY_SLAM    ; NORMAL
	db SUBMISSION   ; FIGHTING
	db DRILL_PECK   ; FLYING
	db SLUDGE       ; POISON
	db EARTHQUAKE   ; GROUND
	db ROCK_SLIDE   ; ROCK
	db 0            ; BIRD (unused type)
	db LEECH_LIFE   ; BUG
	db NIGHT_SHADE  ; GHOST (its real Gen 1 threat; fixed damage)
	assert @ - AIStabGuessByType == UNUSED_TYPES, "AIStabGuessByType: physical rows"
	ds UNUSED_TYPES_END - UNUSED_TYPES, 0
	db FLAMETHROWER ; FIRE
	db SURF         ; WATER
	db RAZOR_LEAF   ; GRASS
	db THUNDERBOLT  ; ELECTRIC
	db PSYCHIC_M    ; PSYCHIC_TYPE
	db ICE_BEAM     ; ICE
	db DRAGON_RAGE  ; DRAGON (its only Gen 1 move; fixed damage)
	assert @ - AIStabGuessByType == NUM_TYPES, "AIStabGuessByType must cover every type"

; Fills wBuffer + AI_BUF_THREATTYPES (one byte per move slot, $ff = none) with
; the types of the player's DAMAGING moves as the AI believes them - revealed,
; type-guessed, or the full moveset for an omniscient class, all through
; AIGetPlayerMoveN. Power 0/1 moves are left out: status moves, and fixed-damage
; moves whose type does not scale their damage. Falls back to the player's first
; type when nothing damaging is believed, so a ranking always has an attacker.
; Farcall target for the send-out/switch ranking in bank $2C (no register
; inputs or outputs, so nothing to lose across Bankswitch).
; Clobbers af, bc, de, hl.
AIBuildPlayerThreatTypes::
	ld hl, wBuffer + AI_BUF_THREATTYPES
	ld b, NUM_MOVES
	ld a, $ff
.clear
	ld [hli], a
	dec b
	jr nz, .clear
	ld c, 0 ; move slot
.nextSlot
	push bc
	ld a, c
	call AIGetPlayerMoveN ; a = believed move id, 0 = none
	pop bc
	and a
	jr z, .advance
	push bc
	dec a
	ld hl, Moves + 2 ; power, then type
	ASSERT BANK(Moves) == BANK(@)
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld a, [hli]
	cp 2
	ld a, [hl] ; type; ld keeps the power test's flags
	pop bc
	jr c, .advance
; A type already listed adds nothing but another ~8k-cycle chart walk per
; candidate in the ranking, so list each type once.
	ld d, a
	ld hl, wBuffer + AI_BUF_THREATTYPES
	ld e, NUM_MOVES
.alreadyListed
	ld a, [hli]
	cp d
	jr z, .advance
	dec e
	jr nz, .alreadyListed
	ld a, d
	ld hl, wBuffer + AI_BUF_THREATTYPES
	ld d, 0
	ld e, c
	add hl, de
	ld [hl], a
.advance
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .nextSlot
	ld hl, wBuffer + AI_BUF_THREATTYPES
	ld b, NUM_MOVES
.anyThreat
	ld a, [hli]
	cp $ff
	ret nz
	dec b
	jr nz, .anyThreat
	ld a, [wBattleMonType1]
	ld [wBuffer + AI_BUF_THREATTYPES], a
	ret
