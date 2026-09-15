GslowkingFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of SLOWKING's (SlowkingEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset - from tmp/kep/data/pokemon/evos_moves.asm, already Gen 1 valid.
; CONFUSION/DISABLE/HEADBUTT already granted at level 1.
	db 10, BIDE
	db 18, DISABLE
	db 22, HEADBUTT
	db 27, GROWL
	db 33, WATER_GUN
	db 44, AMNESIA
	db 55, PSYCHIC_M
	db 0
