GmoltresFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from MoltresEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db 0
; Learnset - verbatim copy of MOLTRES's (MoltresEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
    db 6,  GUST
	db 12, FURY_ATTACK
	db 15, WING_ATTACK
	db 20, RAGE
	db 23, SHARPEN
	db 25, NIGHT_SHADE
	db 30, SLAM
	db 35, AGILITY
	db 40, DRILL_PECK
	db 50, TRI_ATTACK
	db 55, SKY_ATTACK
	db 0
