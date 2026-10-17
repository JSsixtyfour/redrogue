ToedscoolFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An
; empty list means it never evolves, like any final Pokemon. Seeded by
; tools/seed_form_evolutions.py from TentacoolEvosMoves's list with the old
; implicit rules applied; hand-edit freely (a block with entries is never
; re-seeded).
	evo_level_form 1, 30, TENTACRUEL
	db 0
; Learnset - verbatim copy of TENTACOOL's (TentacoolEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 7, SUPERSONIC
	db 13, GROWTH
    db 15, VINE_WHIP
	db 17, POISONPOWDER
	db 22, STUN_SPORE
    db 25, MEGA_DRAIN
	db 27, CONSTRICT
	db 33, SOLARBEAM
	db 40, SCREECH
	db 47, WRAP
	db 48, SPORE
	db 0
