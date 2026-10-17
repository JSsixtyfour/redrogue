AsandshrewFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from SandshrewEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_level_form 1, 22, SANDSLASH
	db 0
; Learnset - verbatim copy of SANDSHREW's (SandshrewEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 5,  DEFENSE_CURL
	db 8,  FURY_SWIPES
	db 10, SAND_ATTACK
	db 14, ROCK_THROW
	db 18, SWIFT
	db 20, ICE_PUNCH
	db 22, SLASH
	db 33, BLIZZARD
	db 40, MIST
	db 0
