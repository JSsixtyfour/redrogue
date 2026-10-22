WugtrioFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from DugtrioEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db 0
; Learnset - verbatim copy of DUGTRIO's (DugtrioEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 10, SAND_ATTACK
	db 14, WATER_GUN
	db 20, SLAM
	db 22, BUBBLEBEAM
	db 27, DIG
	db 30, WRAP
	db 35, HEADBUTT
	db 45, HYDRO_PUMP
	db 0
