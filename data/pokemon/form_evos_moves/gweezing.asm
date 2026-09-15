GweezingFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of WEEZING's (WeezingEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 23, ACID
	db 27, SMOKESCREEN
	db 33, SLUDGE
	db 38, AMNESIA
	db 40, SELFDESTRUCT
	db 45, HAZE
	db 48, EXPLOSION
	db 0
