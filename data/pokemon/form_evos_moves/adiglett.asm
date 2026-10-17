AdiglettFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from DiglettEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_level_form 1, 26, DUGTRIO
	db 0
; Learnset - verbatim copy of DIGLETT's (DiglettEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 12, ROCK_THROW
	db 15, GROWL
	db 19, DIG
	db 24, SAND_ATTACK
	db 31, SLASH
	db 35, ROCK_SLIDE
	db 40, EARTHQUAKE
	db 55, FISSURE
	db 0
