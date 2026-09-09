	db DEX_PINECO ; pokedex id

	db  50,  65,  90,  15,  35
	;   hp  atk  def  spd  spc

	db BUG, BUG ; type
	db 190 ; catch rate
	db 60 ; base exp

	INCBIN "gfx/pokemon/front/pineco.pic", 0, 1 ; sprite dimensions
	dw PinecoPicFront, PinecoPicBack

	db TACKLE, METRONOME, NO_MOVE, NO_MOVE ; level 1 learnset - PROTECT filled with METRONOME
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         MEGA_DRAIN,   SOLARBEAM,    DIG,          \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SKULL_BASH,   \
	     REST,         SUBSTITUTE,   CUT,          LIGHT_SCREEN
	; end

	db BANK(PinecoPicFront) ; pic bank
