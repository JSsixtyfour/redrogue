WiglettFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 10, SAND_ATTACK
	db 14, WATER_GUN
	db 20, SLAM
	db 22, BUBBLEBEAM
	db 24, SAND_ATTACK
	db 30, WRAP
	db 35, HEADBUTT
	db 45, HYDRO_PUMP
	db 0
