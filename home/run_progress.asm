; ============================================================
; GetRunProgress  (Endless mode, ENDLESS_MODE_CHECKPOINT_D.md section 3.1)
;
; How far the RUN has come, for every reader that scales with it: levels,
; rarity, movesets, wild budgets and early-game gates. wBattleCount itself is
; circuit-local scheduling (a continuation sets it back to 1), so scheduling,
; elapsed-time and presentation readers keep reading the raw count
; (ENDLESS_MODE_CHECKPOINT_A.md section 7 classifies every reader).
;
; Out: a = wBattleCount at depth 0, so the original circuit is unchanged;
;      else min(255, wBattleCount + depth * ENDLESS_CIRCUIT_SPAN). The span is
;      a multiple of ROUND_BATTLES, so a mod ROUND_BATTLES is the raw step.
; Preserves bc/de/hl. Flags are NOT preserved, unlike the `ld a, [wBattleCount]`
; it replaces. In HOME because its readers span many banks.
; ============================================================
GetRunProgress::
	ld a, [wEndlessDepth]
	and a
	jr nz, .endless
	ld a, [wBattleCount]
	ret
.endless
	push bc
	ld b, a                       ; circuits completed beyond the first
	ld a, [wBattleCount]
.circuit
	add ENDLESS_CIRCUIT_SPAN
	jr c, .saturate               ; at most four passes before it saturates
	dec b
	jr nz, .circuit
	pop bc
	ret
.saturate
	ld a, $ff
	pop bc
	ret

; ============================================================
; GetRunRoundStep
;
; Out: b = round index, min(progress / ROUND_BATTLES, LAST_ROUND)
;      a = step within the round (progress mod ROUND_BATTLES), carry set
;
; For readers that use BOTH numbers. Clamp the ROUND, not the count: the old
; readers clamped the count to LAST_ROUND_BATTLECOUNT before dividing, which
; turns any progress past it into step FINAL_GYM_TRAINER_STEP (a final gym
; trainer), so every Endless route trainer would read the gym table. Past
; the authored rows the round holds at LAST_ROUND and the step stays real.
; At depth 0 the result is unchanged: those readers never see a count past
; LAST_ROUND_BATTLECOUNT. Preserves c/de/hl.
; ============================================================
GetRunRoundStep::
	call GetRunProgress
	ld b, 0
.round
	cp ROUND_BATTLES
	ret c
	sub ROUND_BATTLES
	inc b
	ASSERT LAST_ROUND == 8
	bit 3, b                      ; b == LAST_ROUND: the round stops here
	jr z, .round
.step
	cp ROUND_BATTLES
	ret c
	sub ROUND_BATTLES
	jr .step

; ============================================================
; WitchAllPrizesEarned  (PCWitchSetup, custom_functions/witch_setup.asm)
; Z set when every prize 1..NUM_WITCH_PRIZES has its wWitchPrizesEarned bit,
; which only a long (Endless) run can reach. In HOME because the witch's bank,
; $38, has no room for it. Clobbers a.
; ============================================================
	ASSERT NUM_WITCH_PRIZES > 8 && NUM_WITCH_PRIZES <= 16
WitchAllPrizesEarned::
	ld a, [wWitchPrizesEarned]
	inc a
	ret nz                        ; a low-byte prize is still missing
	ld a, [wWitchPrizesEarned + 1]
	and (1 << (NUM_WITCH_PRIZES - 8)) - 1
	cp (1 << (NUM_WITCH_PRIZES - 8)) - 1
	ret
