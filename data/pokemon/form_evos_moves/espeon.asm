EspeonFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from JolteonEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db 0
; Learnset - verbatim copy of JOLTEON's (JolteonEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 8, SAND_ATTACK
	db 16, CONFUSION
	db 23, QUICK_ATTACK
	db 30, SWIFT
	db 32, PSYBEAM
	db 40, LIGHT_SCREEN
	db 45, PSYCHIC_M
	db 50, RECOVER
	db 0
