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
; from the player's visible types for unseen slots. Omniscience is now a
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
	jr c, .realMove
; Fair play: the slot is known only if THIS party member revealed it. The mask
; layout is documented at wAISeenPlayerMoveMask (ram/wram.asm).
	ld a, [wPlayerMonNumber]
	ld e, a
	srl a ; a = mask byte
	ld hl, wAISeenPlayerMoveMask
	add l
	ld l, a
	jr nc, .gotByte
	inc h
.gotByte
	ld a, [hl]
	bit 0, e
	jr z, .gotNibble
	swap a ; odd party slot: its bits are the high nibble
.gotNibble
	and $0f
	ld b, a ; b = this mon's revealed slots
	ld e, c
	inc e
.testSlot
	rrca ; carry = the bit just rotated out; dec leaves it alone
	dec e
	jr nz, .testSlot
	jr nc, .guess ; not revealed by this mon
.realMove
	ld hl, wBattleMonMoves
	ld a, c
	ld d, 0
	ld e, a
	add hl, de
	ld a, [hl]
.exit ; named for hookability (project convention); a holds the result here
	ret

; Unseen slot. Each of the player's visible types is assumed to have a STAB move
; until this mon reveals a damaging move of that type, or runs out of unrevealed
; slots to hold it (2026-11-03: the guess used to belong to slots 0 and 1, so
; showing an off-type move in slot 0 made a Psychic-type stop being a Psychic
; threat, measured on a real Erika fight). Types are on screen, so this is still
; fair play; it keeps a threat check from reading "no threat" just because the
; mon has not used its STAB yet. Pending types fill the unrevealed slots in
; order, first type first. A guess fills only a slot that holds a real move, so
; a one-move mon does not carry a phantom attack.
.guess
	ld hl, wBattleMonMoves
	ld d, 0
	ld e, c
	add hl, de
	ld a, [hl]
	and a
	jr z, .exit ; empty slot: nothing to guess (a = 0)
; d, e = the types still pending; AI_GUESS_NO_TYPE = none. A mono-type has one.
	ld a, [wBattleMonType1]
	ld d, a
	ld a, [wBattleMonType2]
	cp d
	jr nz, .gotSecondType
	ld a, AI_GUESS_NO_TYPE
.gotSecondType
	ld e, a
; Strike every type a revealed damaging move already shows. Bit 4 is a sentinel:
; it reaches bit 0 after the fourth shift. A status move returns AI_GUESS_NO_TYPE,
; which can only "strike" a type that is already gone.
	push bc
	set 4, b
	ld hl, wBattleMonMoves
.strikeSlot
	srl b ; carry = this slot was revealed
	ld a, [hli]
	jr nc, .strikeNext
	push hl
	call AIMoveDamagingType
	pop hl
	cp d
	jr nz, .notFirstType
	ld d, AI_GUESS_NO_TYPE
.notFirstType
	cp e
	jr nz, .strikeNext
	ld e, AI_GUESS_NO_TYPE
.strikeNext
	ld a, b
	dec a
	jr nz, .strikeSlot
	pop bc
; Earlier unrevealed slots take the pending types first.
	ld a, d
	cp AI_GUESS_NO_TYPE
	jr nz, .walkEarlierSlots
	ld d, e
	ld e, a
.walkEarlierSlots
	ld hl, wBattleMonMoves
	inc c
.earlierSlot
	dec c
	jr z, .pickGuess
	srl b ; carry = revealed, so it holds no guess
	ld a, [hli]
	jr c, .earlierSlot
	and a
	jr z, .earlierSlot ; empty slot, likewise
	ld d, e
	ld e, AI_GUESS_NO_TYPE
	jr .earlierSlot
.pickGuess
	ld a, d
	cp NUM_TYPES
	jr nc, .unknown
	ld e, a
	ld d, 0
	ld hl, AIStabGuessByType
	add hl, de
	ld a, [wBattleMonLevel]
	cp AI_GUESS_STRONG_LEVEL
	jr nc, .gotGuessRow
	ld e, NUM_TYPES ; d is still 0: the weaker row follows the strong one
	add hl, de
.gotGuessRow
	ld a, [hl]
	jr .exit ; every return goes through .exit, the hookable result point
.unknown
	xor a
	jr .exit

; INPUT:  a = move id (nonzero).
; OUTPUT: a = its type if it deals damage (fixed damage included), else
;         AI_GUESS_NO_TYPE. Preserves bc, de. Clobbers hl.
AIMoveDamagingType:
	push de
	dec a
	ld l, a
	ld h, 0
	add hl, hl
	ld d, h
	ld e, l
	add hl, hl
	add hl, de ; (id - 1) * 6
	ASSERT MOVE_LENGTH == 6
	ld de, Moves + 1 ; effect, then power, then type
	ASSERT BANK(Moves) == BANK(@)
	add hl, de
	pop de
	ld a, [hli]
	cp SPECIAL_DAMAGE_EFFECT
	jr z, .damaging ; Night Shade: power 0, fixed damage
	ld a, [hl]
	and a
	jr nz, .damaging
	ld a, AI_GUESS_NO_TYPE
	ret
.damaging
	inc hl
	ld a, [hl]
	ret

; SwapMovesInMenu (core.asm) just swapped two of the active mon's move slots:
; swap their revealed bits too, so wAISeenPlayerMoveMask keeps marking the
; MOVES that were shown, not the slots they happened to sit in (Codex
; follow-up R2, 2026-09-29: a reveal used to jump to the never-used move that
; took its slot). Slots are 1-based in wMenuItemToSwap and hCurrentMenuItem,
; both still set at the hook. Farcall target from bank $0F; no register
; contract. Clobbers af, bc, de, hl.
AISwapRevealedMoveSlots::
	ld a, [wPlayerMonNumber]
	ld c, a
	srl a ; mask byte
	ld hl, wAISeenPlayerMoveMask
	add l
	ld l, a
	jr nc, .gotByte
	inc h
.gotByte
	ld a, [hl]
	bit 0, c
	jr z, .oriented
	swap a ; this mon's bits into the low nibble
.oriented
	ld e, a
	ld a, [wMenuItemToSwap]
	call .slotBit
	ld b, a
	ldh a, [hCurrentMenuItem]
	call .slotBit
	ld d, a
	ld a, e
	and b
	jr z, .firstClear
	ld a, e
	and d
	ret nz ; both revealed: nothing moves
	jr .toggle
.firstClear
	ld a, e
	and d
	ret z ; neither revealed
.toggle
	ld a, b
	or d
	xor e ; exactly one of the two bits was set: move it to the other slot
	bit 0, c
	jr z, .store
	swap a
.store
	ld [hl], a
	ret
; a = 1-based slot -> a = its bit. Preserves bc, de, hl.
.slotBit
	push bc
	ld b, a
	ld a, 1
.shift
	dec b
	jr z, .gotBit
	add a
	jr .shift
.gotBit
	pop bc
	ret

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

DEF AI_GUESS_NO_TYPE EQU $ff ; above every real type id

; Below this level an unseen slot assumes the weaker row: a level 10 Squirtle has
; Water Gun, not Surf. The level curated sets may first carry a grade A TM move.
DEF AI_GUESS_STRONG_LEVEL EQU TM_GATE_LEVEL_A

; TUNING KNOB: the move an unseen slot is assumed to hold, per player type.
; Typical Gen 1 threats of each type; 0 = no guess. Indexed by type id, then
; by level: AIGetPlayerMoveN adds NUM_TYPES to reach the weaker row, so the two
; rows must stay adjacent. Bug, Ghost and Dragon repeat: Leech Life is already
; weak here, and Night Shade and Dragon Rage are fixed damage.
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
; The weaker row, below AI_GUESS_STRONG_LEVEL.
	db POUND        ; NORMAL
	db LOW_KICK     ; FIGHTING
	db PECK         ; FLYING
	db ACID         ; POISON
	db BONE_CLUB    ; GROUND
	db ROCK_THROW   ; ROCK
	db 0            ; BIRD (unused type)
	db LEECH_LIFE   ; BUG
	db NIGHT_SHADE  ; GHOST
	assert @ - AIStabGuessByType == NUM_TYPES + UNUSED_TYPES, "weaker row: physical rows"
	ds UNUSED_TYPES_END - UNUSED_TYPES, 0
	db EMBER        ; FIRE
	db WATER_GUN    ; WATER
	db VINE_WHIP    ; GRASS
	db THUNDERSHOCK ; ELECTRIC
	db CONFUSION    ; PSYCHIC_TYPE
	db AURORA_BEAM  ; ICE
	db DRAGON_RAGE  ; DRAGON
	assert @ - AIStabGuessByType == NUM_TYPES * 2, "weaker row must cover every type"

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

; B10: carry if move id e (nonzero) has power, counting fixed-damage moves.
; Night Shade has power 0, so it is caught by SPECIAL_DAMAGE_EFFECT (the same
; exemption as ai_damage.asm); Sonicboom and the rest have power 1.
; Farcall target for AIMonHasDamagingPP (bank $2C), which cannot read Moves.
; Runs per reserve move in the switch ranking, so it multiplies by shifts:
; AddNTimes loops once per move id (measured +6k cycles a ranking).
; Clobbers af, de, hl.
AIMoveIdDealsDamage::
	ld a, e
	dec a
	ld l, a
	ld h, 0
	add hl, hl
	ld d, h
	ld e, l
	add hl, hl
	add hl, de ; (id - 1) * 6
	ASSERT MOVE_LENGTH == 6
	ld de, Moves + 1 ; effect, then power
	ASSERT BANK(Moves) == BANK(@)
	add hl, de
	ld a, [hli]
	cp SPECIAL_DAMAGE_EFFECT
	jr z, .damaging ; Night Shade: power 0, fixed damage
	ld a, [hl]
	cp 1 ; carry iff power 0
	ccf
	ret
.damaging
	scf
	ret
