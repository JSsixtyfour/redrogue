HgrowlitheFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from GrowlitheEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_item_form 1, FIRE_STONE, 1, ARCANINE
	db 0
; Learnset - verbatim copy of GROWLITHE's (GrowlitheEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 10, EMBER
	db 20, LEER
	db 30, TAKE_DOWN
	db 35, FLAMETHROWER
	db 36, ROCK_SLIDE
	db 0
