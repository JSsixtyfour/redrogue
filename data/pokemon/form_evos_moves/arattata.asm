ArattataFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from RattataEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_level_form 1, 20, RATICATE
	db 0
; Learnset - verbatim copy of RATTATA's (RattataEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 7, QUICK_ATTACK
	db 9, BITE
	db 14, HYPER_FANG
	db 19, FOCUS_ENERGY
	db 24, DIG
	db 28, SUPER_FANG
	db 0
