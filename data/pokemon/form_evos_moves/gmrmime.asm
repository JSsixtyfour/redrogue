GmrmimeFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of MR_MIME's (MrMimeEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 15, CONFUSION
	db 23, LIGHT_SCREEN
	db 23, REFLECT
	db 27, DOUBLESLAP
	db 31, PSYBEAM
	db 39, MEDITATE
	db 43, PSYCHIC_M
	db 47, SUBSTITUTE
	db 50, BARRIER
	db 0
