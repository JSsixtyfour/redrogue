	db DEX_LUGIA ; pokedex id

	db 106,  90, 130, 110, 154
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, FLYING ; type
	db 3 ; catch rate
	db 220 ; base exp

	INCBIN "gfx/pokemon/front/lugia.dim" ; sprite dimensions
	dw LugiaPicFront, LugiaPicBack

	db GUST, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Zapdos/Alakazam (legendary Flying/Psychic)
	tmhm LIGHT_SCREEN, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         PSYCHIC_M,    MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         SWIFT,        SKY_ATTACK,   REST,         SUBSTITUTE,   \
	     FLY,          SURF,         STRENGTH,     FLASH,        ICE_BEAM,      \
         BLIZZARD,     MEGA_DRAIN,   DRAGON_RAGE,  EARTHQUAKE,   THUNDER,       \
         DREAM_EATER,  THUNDERBOLT,  BODY_SLAM,    LIGHT_SCREEN, BUBBLEBEAM,    \
         HYDRO_PUMP,   THUNDER_WAVE, PSYWAVE,      WATER_GUN,    RAZOR_WIND     \
	; end   

	db BANK(LugiaPicFront) ; pic bank
