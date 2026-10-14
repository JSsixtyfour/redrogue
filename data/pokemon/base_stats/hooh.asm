	db DEX_HO_OH ; pokedex id

	db 106, 130,  90,  90, 154
	;   hp  atk  def  spd  spc

	db FIRE, FLYING ; type
	db 3 ; catch rate
	db 220 ; base exp

	INCBIN "gfx/pokemon/front/hooh.dim" ; sprite dimensions
	dw HoOhPicFront, HoOhPicBack

	db EMBER, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Moltres (legendary Fire/Flying)
	tmhm FLAMETHROWER, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     FIRE_BLAST,   SWIFT,        SKY_ATTACK,   REST,         SUBSTITUTE,   \
	     FLY,          STRENGTH,     MEGA_DRAIN,   SOLARBEAM,    DRAGON_RAGE,  \
         THUNDER,      EARTHQUAKE,   PSYCHIC_M,    FLASH,        DREAM_EATER,  \
         THUNDERBOLT,  BODY_SLAM,    LIGHT_SCREEN, THUNDER_WAVE, RAZOR_WIND,   \
         PSYWAVE
	; end

	db BANK(HoOhPicFront) ; pic bank
