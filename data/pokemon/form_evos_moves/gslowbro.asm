GslowbroFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from SlowbroEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db 0
; Learnset - verbatim copy of SLOWBRO's (SlowbroEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 5, GROWL
	db 9, BUBBLE
	db 10, CONFUSION 
	db 18, DISABLE
	db 22, HEADBUTT
	db 25, PSYBEAM
	db 28, WATER_GUN
    db 30, SLUDGE
	db 36, WITHDRAW
	db 40, AMNESIA
	db 45, PSYCHIC_M
	db 0
