; Ursaluna - URSARING form 1, evolved from Ursaring with a Moon Stone (canon:
; a Peat Block under a full moon). A distinct species stored as a form
; (numbered Pokedex row, DEX_FORM_URSALUNA).
;
; Ground/Normal, both valid Gen 1 types.
; No reference fork carries Ursaluna; stats are canon (130/140/105, Spe 50,
; SpA 45 / SpD 80 -> spc 80, the higher). Canon base exp 275 does not fit a
; byte, so 255. Catch rate 20 (canon). However, a Special of 80 gives it a higher
; BST total than Dragonite, so this was reduced to 70 to give it 5 less, could
; be adjusted further.
; Growth rate must match Ursaring's: the evolution keeps the experience total.
	form_record URSARING, 1

	db DEX_URSARING ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db 130, 140, 105,  50,  70
	;   hp  atk  def  spd  spc

	db GROUND, NORMAL ; type
	db 20 ; catch rate
	db 255 ; base exp

	INCBIN "gfx/pokemon/front/ursaluna.dim" ; sprite dimensions
	dw UrsalunaPicFront, UrsalunaPicBack

	db SCRATCH, LEER, LICK, FURY_SWIPES ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - Ursaring's plus Fissure
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  HYPER_BEAM,   SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  BIDE,         REST,         \
	     SUBSTITUTE,   STRENGTH,     SWIFT,        EARTHQUAKE,   ROCK_SLIDE,   \
	     CUT,          METRONOME,    SWORDS_DANCE, DIG,          FISSURE
	; end

	db BANK(UrsalunaPicFront) ; pic bank

	dname "URSALUNA"

	form_end PAL_BROWNMON
