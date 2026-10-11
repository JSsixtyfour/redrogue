AvulpixFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of VULPIX's (VulpixEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 7, QUICK_ATTACK
    db 10, LICK
	db 16, CONFUSE_RAY
    db 20, AURORA_BEAM
	db 25, REFLECT
	db 32, ICE_BEAM
	db 37, NIGHT_SHADE
	db 42, MIST
    db 45, BLIZZARD
	db 0
