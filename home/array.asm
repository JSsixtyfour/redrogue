; skips a text entries, each of size NAME_LENGTH (like trainer name, OT name, rival name, ...)
; hl: base pointer, will be incremented by NAME_LENGTH * a
SkipFixedLengthTextEntries::
	and a
	ret z
	ld bc, NAME_LENGTH
.skipLoop
	add hl, bc
	dec a
	jr nz, .skipLoop
	ret

AddNTimes::
; add bc to hl a times
; Returns a = 0; bc and de preserved. Small a keeps the linear loop (24 cycles per
; step). From 16 up it shift-adds, one step per BIT of a, capped near 550 cycles:
; the AI's Moves-table lookups (a = move id, avg ~78) cost ~1,900 cycles each as a
; loop, which was 13.8% of AI decision time (AI_PERF_INVESTIGATION.md §9).
	and a
	ret z
	cp 16
	jr nc, .shiftAdd
.loop
	add hl, bc
	dec a
	jr nz, .loop
	ret

.shiftAdd
	push bc
.bit
	srl a                ; carry = this bit; Z = no higher bits left
	jr nc, .skip
	add hl, bc           ; leaves Z alone
.skip
	jr z, .done
	sla c
	rl b                 ; bc *= 2 (mod 2^16, same wrap as the loop)
	jr .bit
.done
	pop bc
	ret
