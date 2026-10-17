AgravelerFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from GravelerEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_trade_form 1, 38, GOLEM
	db 0
; Learnset - verbatim copy of GRAVELER's (GravelerEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 6, DEFENSE_CURL
	db 12, ROCK_THROW
	db 25, THUNDERPUNCH
	db 26, HARDEN
	db 31, SELFDESTRUCT
	db 40, ROCK_SLIDE
	db 45, THUNDER
	db 48, EXPLOSION
	db 0
