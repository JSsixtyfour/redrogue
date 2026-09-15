PwooperFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of WOOPER's (WooperEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset - WATER_GUN/TAIL_WHIP already granted at level 1; RAIN_DANCE
; does not exist in Gen 1, filled with METRONOME.
	db 11, SLAM
	db 21, AMNESIA
	db 31, EARTHQUAKE
	db 41, METRONOME ; was RAIN_DANCE
	db 51, MIST
	db 51, HAZE
	db 0
