HvoltorbFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from VoltorbEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_level_form 1, 30, ELECTRODE
	db 0
; Learnset - verbatim copy of VOLTORB's (VoltorbEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
    db 10, ABSORB
    db 14, THUNDERSHOCK
    db 16, STUN_SPORE
	db 18, SONICBOOM
	db 22, SELFDESTRUCT
	db 26, SWIFT
	db 30, LIGHT_SCREEN
	db 35, THUNDERBOLT
	db 44, EXPLOSION
	db 50, THUNDER
	db 0
