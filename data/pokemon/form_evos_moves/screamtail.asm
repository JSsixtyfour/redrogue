ScreamtailFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of JIGGLYPUFF's (JigglypuffEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 3, POUND
	db 5, DEFENSE_CURL
	db 14, DISABLE
	db 16, DOUBLESLAP
	db 24, REST
	db 30, BODY_SLAM
	db 38, LOVELY_KISS,
	db 43, DOUBLE_EDGE
	db 0
