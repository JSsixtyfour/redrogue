GfarfetchdFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from FarfetchdEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db EVOLVE_LEVEL, 24, SIRFETCHD
	db 0
; Learnset - verbatim copy of FARFETCHD's (FarfetchdEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 7, LEER
	db 9, SHARPEN
	db 13, FURY_ATTACK
	db 18, WING_ATTACK
	db 23, SLASH
	db 28, SWORDS_DANCE
	db 31, DRILL_PECK
	db 39, AGILITY
	db 0
