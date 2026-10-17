AvulpixFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from VulpixEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_item_form 1, ICE_STONE, 1, NINETALES
	db 0
; Learnset - verbatim copy of VULPIX's (VulpixEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 7, QUICK_ATTACK
    db 10, LICK
	db 16, CONFUSE_RAY
    db 20, AURORA_BEAM
	db 25, REFLECT
	db 32, ICE_BEAM
	db 37, NIGHT_SHADE
	db 42, MIST
    db 45, BLIZZARD
	db 0
