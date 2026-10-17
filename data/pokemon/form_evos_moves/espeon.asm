EspeonFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from JolteonEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db 0
; Learnset - verbatim copy of JOLTEON's (JolteonEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 8, SAND_ATTACK
	db 23, QUICK_ATTACK
	db 26, THUNDERSHOCK
	db 30, DOUBLE_KICK
	db 36, THUNDERBOLT
	db 39, PIN_MISSILE
	db 41, AGILITY
	db 47, THUNDER_WAVE
	db 52, THUNDER
	db 0
