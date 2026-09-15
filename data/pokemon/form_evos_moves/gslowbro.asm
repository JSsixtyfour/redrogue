GslowbroFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of SLOWBRO's (SlowbroEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 5, GROWL
	db 5, WATER_GUN
	db 10, CONFUSION 
	db 18, DISABLE
	db 22, HEADBUTT
	db 25, PSYBEAM
	db 28, WATERFALL
	db 36, WITHDRAW
	db 40, AMNESIA
	db 45, PSYCHIC_M
	db 0
