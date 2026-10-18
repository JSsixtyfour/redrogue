GslowkingFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from SlowkingEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	db 0
; Learnset - verbatim copy of SLOWKING's (SlowkingEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid.
; CONFUSION/DISABLE/HEADBUTT already granted at level 1.
	db 5, GROWL
    db 9, BUBBLE
    db 10, CONFUSION
	db 18, DISABLE
	db 22, HEADBUTT
    db 25, PSYBEAM
    db 30, ACID
	db 33, SLUDGE
	db 44, AMNESIA
	db 55, PSYCHIC_M
	db 0
