	db DEX_SUNFLORA ; pokedex id

	db  75,  75,  55,  30, 105
	;   hp  atk  def  spd  spc

	db GRASS, GRASS ; type
	db 120 ; catch rate
	db 146 ; base exp

	INCBIN "gfx/pokemon/front/sunflora.pic", 0, 1 ; sprite dimensions
	dw SunfloraPicFront, SunfloraPicBack

	db ABSORB, POUND, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     RAGE,         MEGA_DRAIN,   SOLARBEAM,    MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         REST,         SUBSTITUTE,   CUT
	; end

	db BANK(SunfloraPicFront) ; pic bank
