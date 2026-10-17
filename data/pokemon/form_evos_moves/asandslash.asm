AsandslashFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of SANDSLASH's (SandslashEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 5,  DEFENSE_CURL
	db 8,  FURY_SWIPES
	db 10, SAND_ATTACK
	db 14, ROCK_THROW
	db 18, SWIFT
	db 20, ICE_PUNCH
	db 22, SLASH
	db 33, BLIZZARD
	db 40, MIST
	db 42, SWORDS_DANCE
	db 0
