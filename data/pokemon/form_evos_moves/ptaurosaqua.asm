PtaurosaquaFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from TaurosEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db 0
; Learnset - verbatim copy of TAUROS's (TaurosEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
    db 6, TAIL_WHIP
    db 10, DOUBLE_KICK
	db 13, HORN_ATTACK
	db 15, LEER
	db 19, STOMP
	db 27, HEADBUTT
    db 30, WATERFALL
	db 35, RAGE
	db 40, TAKE_DOWN
	db 45, THRASH
	db 50, DOUBLE_EDGE
    db 51, HYDRO_PUMP
	db 0
