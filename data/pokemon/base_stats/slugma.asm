	db DEX_SLUGMA ; pokedex id

	db  40,  40,  40,  20,  70
	;   hp  atk  def  spd  spc

	db FIRE, FIRE ; type
	db 190 ; catch rate
	db 78 ; base exp

	INCBIN "gfx/pokemon/front/slugma.pic", 0, 1 ; sprite dimensions
	dw SlugmaPicFront, SlugmaPicBack

	db SMOG, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - modeled on Vulpix (Fire-type)
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         FIRE_BLAST,   \
	     SKULL_BASH,   REST,         SUBSTITUTE,   FLAMETHROWER
	; end

	db BANK(SlugmaPicFront) ; pic bank
