AgrimerFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of GRIMER's (GrimerEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 10, HARDEN
	db 16, ACID
	db 19, POISON_GAS
	db 24, ACID_ARMOR
	db 27, MINIMIZE
	db 33, SLUDGE
	db 37, BODY_SLAM
	db 42, TOXIC
	db 45, SCREECH
	db 0
