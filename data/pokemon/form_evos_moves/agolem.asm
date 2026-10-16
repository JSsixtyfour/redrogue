AgolemFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 6, DEFENSE_CURL
	db 12, ROCK_THROW
	db 25, THUNDERPUNCH
	db 26, HARDEN
	db 31, SELFDESTRUCT
	db 40, ROCK_SLIDE
	db 45, THUNDER
	db 48, EXPLOSION
	db 0
