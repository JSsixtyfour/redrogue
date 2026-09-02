; AI Overhaul Phase 6: tier-scaled enemy trainer DVs and stat exp.
;
; PINNED to bank $2C (same relocation bank as ai_switching.asm/ai_plans.asm -
; see ai_switching.asm's header for why $2C specifically: Red/Blue/Debug
; first-fit independently and Debug is tightest, so a floated section risks
; landing somewhere tight in one variant only).
;
; WHY THIS ISN'T IN engine/pokemon/add_mon.asm (bank $03) WITH ITS CALLERS:
; bank $03 had only 38 bytes free at the start of this phase - nowhere near
; enough for a DV roll, a stat-exp roll, and an HP fix. PHASE_6_SPEC.md
; called bank $03 "ample"; that was wrong (see AI_OVERHAUL_PLAN.md's Phase 6
; entry for the correction). This file holds all the real logic; add_mon.asm
; keeps only the minimal glue needed to call it (three small call sites,
; ~25 bytes total).
;
; CALLING CONVENTION: same farcall-return contract as ai_switching.asm
; (verified there from home/bankswitch.asm) - carry and de/hl survive a
; farcall return in both directions; a and bc do not. That is a statement
; about the farcall MACRO and Bankswitch itself, not a guarantee about what a
; CALLEE does internally: AIRollEnemyDVs below nested-farcalls AIGetTier,
; which can fall through to AIResolveTier, which uses d/e as its own scratch
; - so de is NOT safe to use as an output channel here, and callers that need
; de preserved across one of these farcalls must push/pop it explicitly
; rather than trust it survives untouched. AIRollEnemyDVs returns in hl for
; this reason (see its own header for the bug this caused when it didn't).
; Nothing here takes an argument in a (impossible - Bankswitch's first
; instruction clobbers a inbound); pointer arguments that must travel in from
; add_mon.asm go via de (the one register a farcall's own inbound trip never
; touches - though see above, an argument still is not safe from a callee's
; OWN internal use of de once the callee's body starts running).

SECTION "Trainer AI Roster", ROMX, BANK[$2C]

; Rolls tier-scaled DVs for one enemy trainer mon.
; INPUT:  none (reads wCurEnemyLevel is NOT needed here - DVs don't depend
;         on level). Resolves wAITier itself via AIGetTier.
; OUTPUT: h = Spd/Spc DV byte, l = Atk/Def DV byte - matching _AddPartyMon's
;         `.next4` contract (a = Atk/Def, b = Spd/Spc), which the caller
;         copies out of h/l. T0 or unresolved wAITier: the plain fixed
;         ATKDEFDV_TRAINER/SPDSPCDV_TRAINER pair (no Random call - so a T0
;         battle's RNG stream is byte-identical to before this phase).
;         T1-T3: two Random rolls, each nibble floored per tier.
; CLOBBERS: a, bc, de.
; CORRECTION: this originally returned via de, on the assumption that "de
; survives a farcall" (true of the macro/Bankswitch themselves). That missed
; a transitive case: AIGetTier can fall through to AIResolveTier on a
; battle's first resolution, and AIResolveTier uses d/e as its own scratch
; for the round-table lookup (`ld d,0 / ld e,a / add hl,de`). So de is NOT
; safe to use for this routine's output OR to assume untouched internally -
; hl is the output channel instead, and the CALLER (add_mon.asm) must
; separately push/pop de around the whole farcall, since de is its live
; struct-write cursor at that specific call site and this routine cannot
; guarantee preserving it just by not touching it directly. Verified by the
; actual failure this produced: struct writes after the DV call landed at
; garbage offsets (level=0, HP=0 for every generated mon) because the
; cursor was silently overwritten - not a crash, just wrong addresses.
AIRollEnemyDVs::
	farcall AIGetTier ; resolve wAITier - its `a` return cannot survive the trip
	ld a, [wAITier]
	and a
	jr z, .fixed ; unresolved: fall back to the old fixed pair
	dec a ; a = resolved tier (0-3)
	and a
	jr z, .fixed ; T0: no roll, exact old fixed-pair behavior
	dec a ; a = tier - 1 (T1=0, T2=1, T3=2): index into the floor table
	ld hl, AIEnemyDVFloorTable
	ld c, a
	ld b, 0
	add hl, bc
	ld c, [hl] ; c = floor for this tier (0-15), held across both rolls below
	call Random
	ld h, a ; h = first roll (raw) -> becomes floored Spd/Spc
	call Random
	ld l, a ; l = second roll (raw) -> becomes floored Atk/Def
	ld a, h
	call .applyFloor
	ld h, a ; h = floored Spd/Spc (final)
	ld a, l
	call .applyFloor
	ld l, a ; l = floored Atk/Def (final)
	ret
.fixed
	ld h, SPDSPCDV_TRAINER
	ld l, ATKDEFDV_TRAINER
	ret
; ApplyDVFloor's nibble-floor logic, reimplemented inline rather than called:
; ApplyDVFloor (engine/pokemon/add_mon.asm, bank $03) takes/returns its byte
; in `a`, which cannot survive a farcall in either direction (Bankswitch's
; first instruction clobbers `a` inbound, and only bc/a are destroyed on
; return - so `a` is never usable as a farcall argument or result). It is
; therefore not reachable from a different bank at all, by a farcall or a
; plain call - see project_cross_bank_call_bug_recurrence.
; INPUT: a = packed DV byte, c = floor (0-15). OUTPUT: a = floored byte.
; CLOBBERS: b.
.applyFloor
	push af
	and $0f
	cp c
	jr nc, .lowOk
	ld a, c
.lowOk
	ld b, a
	pop af
	swap a
	and $0f
	cp c
	jr nc, .highOk
	ld a, c
.highOk
	swap a
	or b
	ret

AIEnemyDVFloorTable:
	db 10, 12, 14 ; T1, T2, T3 (T0 uses the fixed ATKDEFDV_TRAINER pair, no roll)

; Finishes one enemy trainer mon's stats: rolls tier+level-scaled stat exp,
; calls CalcStats with it considered, then fixes current HP to match the
; freshly-raised MaxHP. Consolidates all three steps into one farcall site
; (from _AddPartyMon's .calcFreshStats) rather than three, to keep bank $03's
; footprint minimal - see this file's header.
; INPUT: de = &MaxHP (CalcStats' write destination) - this is the ONLY
;        pointer passed in, via de, because de is the one register pair a
;        farcall's inbound trip never touches (the farcall macro only sets
;        b/hl, and Bankswitch itself only additionally touches a/bc before
;        the jp). The stat-exp base pointer CalcStats needs in hl
;        (&HPExp - 1) is NOT passed separately - it is DERIVED from de below
;        via a compile-time-constant struct offset, since both are fixed
;        offsets from the same mon-struct base.
;        CORRECTION 1: an earlier draft of this routine tried to pass
;        &HPExp-1 via a bare stack push before the farcall, with this
;        routine popping it as its first instruction. That is broken:
;        Bankswitch itself pushes the OLD bank (`push af`) and its own
;        return trampoline address (`push bc` for `.Return`) onto the stack
;        between the caller's push and this routine's first instruction (see
;        home/bankswitch.asm), so a `pop` here retrieves Bankswitch's own
;        bookkeeping, not the caller's argument - corrupting the return
;        address and crashing (verified: this caused a PC=$0038-into-VRAM
;        style crash on every boot test, not just battle-related ones).
;        CORRECTION 2: a second draft derived hl = &HPExp-1 only on the
;        ENEMY branch, on the assumption that the player branch (b=0, "don't
;        consider stat exp") doesn't need hl at all. That is also wrong:
;        _CalcStat ALWAYS uses hl to reach the DVs field
;        (`ld bc, wPartyMon1DVs - (wPartyMon1HPExp - 1) / add hl, bc` runs
;        unconditionally, after the b=0/b=1 branch reconverges), regardless
;        of whether stat exp is considered. Leaving hl unset for the player
;        branch meant CalcStats read the farcall's own jump-target address
;        as if it were the stat-exp base pointer, corrupting the DV lookup
;        and producing a slightly-wrong HP for player mons (confirmed: HP
;        came out 1-2 points above the correctly-computed MaxHP on several
;        FIGHT2-generated player mons, with player mons on the OLD, correct
;        path always showing HP == MaxHP exactly). Fixed by deriving hl
;        unconditionally, before the player/enemy branch, since the
;        &HPExp-1 pointer is needed either way.
; Reads wMonDataLocation/wCurEnemyLevel/wAITier directly rather than taking
; them as arguments - none of a/b/c survive a farcall's inbound trip, and
; all three are global state anyway. wAITier is already resolved by this
; point: AIRollEnemyDVs (above) farcalls AIGetTier for every enemy mon
; earlier in the same _AddPartyMon call, well before this runs.
; CalcStats is HOME-resident (home/move_mon.asm), so it is plain-callable
; from here regardless of which ROMX bank is currently switched in.
; CLOBBERS: everything. The caller does not use de, hl, a, or bc again after
; this call returns.
AIFinishEnemyMonStats::
	push de ; de = &MaxHP, about to be advanced by CalcStats - save it
	pop hl
	ld bc, (MON_HP_EXP - 1) - MON_MAXHP
	add hl, bc ; hl = &HPExp - 1 (derived from de) - CalcStats always needs
	           ; this, for both branches below
	ld a, [wMonDataLocation]
	and $f
	ld b, $0
	jr z, .calcStatsNow ; player: b=0, hl already correctly positioned
	push hl ; save &HPExp - 1; the stat-exp writer needs &HPExp itself (hl+1)
	inc hl
	call .rollStatExp ; writes the 5-word stat-exp block at hl (=&HPExp)
	pop hl ; restore &HPExp - 1 for CalcStats
	ld b, $1
	push de
	call CalcStats
	pop hl ; hl = &MaxHP (byte 0), as captured before the call
	call .fixHP
	ret
.calcStatsNow
	call CalcStats
	ret

; Writes a tier+level-scaled 16-bit stat exp value into all 5 stat-exp words
; starting at hl (the caller positions hl at HPExp's MSB, the block start).
; T0 never reaches here (AIFinishEnemyMonStats only calls this on the enemy
; branch, and even then a resolved T0 just leaves the block at zero below -
; matching the "round 0 stays near-unchanged" requirement byte-for-byte).
; INPUT:  hl = pointer to the 5-word stat-exp block (HPExp MSB)
; OUTPUT: all 5 words at hl overwritten with the same scaled 16-bit value
; CLOBBERS: a, bc, hl
.rollStatExp
	ld a, [wAITier]
	and a
	ret z ; unresolved: leave stat exp at zero
	dec a ; a = resolved tier (0-3)
	and a
	ret z ; T0: leave stat exp at zero
	ld c, a ; c = tier (1/2/3), saved across the level load
	ld a, [wCurEnemyLevel]
	ld b, a ; bc = level << 8 to start (b=level, c=0 next)
	ld a, c
	ld c, 0
	cp AI_TIER_EXPERT
	jr z, .writeWords ; T3: level << 8, no shift
	srl b
	rr c
	cp AI_TIER_SKILLED
	jr z, .writeWords ; T2: level << 7
	srl b
	rr c ; T1: level << 6
.writeWords
	ld a, NUM_STATS
.wordLoop
	ld [hl], b
	inc hl
	ld [hl], c
	inc hl
	dec a
	jr nz, .wordLoop
	ret

; Copies MaxHP's 2 bytes over the mon's current-HP field, so a trainer mon
; whose stat exp raised its MaxHP does not enter battle already "damaged"
; relative to the HP _AddPartyMon's earlier .next4 block computed (that
; computation ran with b=0, before stat exp existed - see PHASE_6_SPEC.md
; section 4, "the ordering trap").
; INPUT:  hl = &MaxHP (byte 0, just written by CalcStats)
; CLOBBERS: a, bc, de, hl
.fixHP
	ld a, [hl]
	ld d, a
	inc hl
	ld a, [hl]
	ld e, a
	ld bc, MON_HP - MON_MAXHP
	add hl, bc
	ld [hl], e
	dec hl
	ld [hl], d
	ret

; Item AI, Phase 6 task 5c/5d: Gen 2's "items only on the ace" gate.
; Farcalled from TrainerAI (trainer_ai.asm, bank $0E - only 321 bytes free,
; the AI's ceiling) because it loops the whole enemy party; TrainerAI itself
; keeps only the T2+ tier check and this one call.
; OUTPUT: carry SET if the active enemy mon is this trainer's ace (every
; other party slot is fainted or nonexistent); carry CLEAR otherwise.
; CLOBBERS: a, bc, de, hl
AIActiveMonIsAce::
	ld a, [wEnemyPartyCount]
	ld b, a ; b = party count
	ld a, [wEnemyMonPartyPos]
	ld d, a ; d = active slot index (0-based)
	ld hl, wEnemyMon1HP
	xor a
	ld e, a ; e = loop index (0-based)
.loop
	ld a, e
	cp d
	jr z, .skip ; don't compare the active mon against itself
	ld a, [hli]
	or [hl]
	dec hl
	jr nz, .notAce ; found another living party member
.skip
	push bc
	push de
	ld bc, PARTYMON_STRUCT_LENGTH
	add hl, bc ; HP is at the same relative offset in every mon's struct, so
	           ; one full stride from this mon's HP lands on the next mon's
	pop de
	pop bc
	inc e
	ld a, e
	cp b
	jr c, .loop
.isAce ; F18, 2026-09-02: zero-byte label, testability only - call_routine
       ; cannot report a carry result (it restores every saved register,
       ; flags included, on return - see PYBOY_HARNESS_REFERENCE.md), so a
       ; pure-predicate routine with no other observable side effect needs a
       ; hookable address at each exit. Same precedent as
       ; AIGetPlayerMoveN.exit (ai_accessors.asm, Phase 7).
	scf
	ret
.notAce
	and a
	ret
