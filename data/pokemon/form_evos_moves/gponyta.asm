GponytaFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from PonytaEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_level_form 1, 40, RAPIDASH
	db 0
; Learnset - verbatim copy of PONYTA's (PonytaEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 8, TAIL_WHIP
    db 12, CONFUSION
	db 19, STOMP
	db 25, QUICK_ATTACK
	db 26, PSYBEAM
	db 35, AGILITY
	db 36, PSYCHIC_M
	db 40, TAKE_DOWN
	db 45, RECOVER
	db 0
