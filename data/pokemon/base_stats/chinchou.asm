	db DEX_CHINCHOU ; pokedex id

	db  75,  38,  38,  67,  56
	;   hp  atk  def  spd  spc

	db WATER, ELECTRIC ; type
	db 190 ; catch rate
	db 90 ; base exp

	INCBIN "gfx/pokemon/front/chinchou.pic", 0, 1 ; sprite dimensions
	dw ChinchouPicFront, ChinchouPicBack

	db BUBBLE, THUNDER_WAVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     BLIZZARD,     \
	     SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         THUNDERBOLT,  \
	     THUNDER,      MIMIC,        DOUBLE_TEAM,  LIGHT_SCREEN, REFLECT,      \
	     BIDE,         REST,         THUNDER_WAVE, SUBSTITUTE,   SURF,         \
	     STRENGTH,     FLASH
	; end

	db BANK(ChinchouPicFront) ; pic bank
