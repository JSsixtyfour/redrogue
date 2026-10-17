GarticunoFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from ArticunoEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db 0
; Learnset - verbatim copy of ARTICUNO's (ArticunoEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
    db 8,  GUST
	db 16, CONFUSION
	db 21, HYPNOSIS
	db 26, REFLECT
	db 30, PSYBEAM
	db 35, AGILITY
	db 45, PSYCHIC_M
	db 50, RECOVER
	db 55, SKY_ATTACK
	db 0
