UmbreonFormEvosMoves:
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
	db 23, QUICK_ATTACK
	db 26, NIGHT_SHADE
	db 30, CONFUSE_RAY
	db 36, SWIFT
	db 39, BODY_SLAM
	db 41, RECOVER
	db 47, SCREECH
	db 50, DOUBLE_EDGE
	db 0
