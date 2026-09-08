	db DEX_SUDOWOODO ; pokedex id

	db  70, 100, 115,  30,  65
	;   hp  atk  def  spd  spc

	db ROCK, ROCK ; type
	db 65 ; catch rate
	db 135 ; base exp

	INCBIN "gfx/pokemon/front/sudowoodo.pic", 0, 1 ; sprite dimensions
	dw SudowoodoPicFront, SudowoodoPicBack

	db ROCK_THROW, MIMIC, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         SELFDESTRUCT, SKULL_BASH,   REST,         EXPLOSION,    \
	     ROCK_SLIDE,   SUBSTITUTE,   STRENGTH
	; end

	db BANK(SudowoodoPicFront) ; pic bank
