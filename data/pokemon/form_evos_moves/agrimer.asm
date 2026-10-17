AgrimerFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from GrimerEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_level_form 1, 38, MUK
	db 0
; Learnset - verbatim copy of GRIMER's (GrimerEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 10, BITE
	db 11, ACID
	db 19, POISON_GAS
	db 24, ACID_ARMOR
	db 27, MINIMIZE
	db 33, SLUDGE
	db 37, BODY_SLAM
	db 42, TOXIC
	db 45, SCREECH
	db 0
