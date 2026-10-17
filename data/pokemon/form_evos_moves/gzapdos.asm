GzapdosFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from ZapdosEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db 0
; Learnset - verbatim copy of ZAPDOS's (ZapdosEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
    db 10, DOUBLE_KICK
    db 18, LOW_KICK
    db 22, TAKE_DOWN
    db 30, COUNTER
    db 32, ROLLING_KICK
	db 35, AGILITY
	db 40, DRILL_PECK
	db 45, JUMP_KICK
    db 51, HI_JUMP_KICK
    db 55, MEGA_KICK
	db 0
