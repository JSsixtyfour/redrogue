	db DEX_TOGETIC ; pokedex id

	db  55,  40,  85,  40, 105
	;   hp  atk  def  spd  spc

	db NORMAL, FLYING ; type
	db 75 ; catch rate
	db 114 ; base exp

	INCBIN "gfx/pokemon/front/togetic.dim" ; sprite dimensions
	dw TogeticPicFront, TogeticPicBack

	db GROWL, POUND, NO_MOVE, NO_MOVE ; level 1 learnset - CHARM replaced with POUND
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  RAZOR_WIND,   EGG_BOMB,     SWIFT,        SOFTBOILED,   \
	     SKY_ATTACK,   SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         \
	     SOLARBEAM,    THUNDERBOLT,  THUNDER,      PSYCHIC_M,    LIGHT_SCREEN, \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         METRONOME,    \
	     FIRE_BLAST,   SKULL_BASH,   REST,         THUNDER_WAVE, PSYWAVE,      \
	     TRI_ATTACK,   SUBSTITUTE,   FLASH,        FLAMETHROWER, FLY,          \
	     HYPER_BEAM,   DREAM_EATER
	; end

	db BANK(TogeticPicFront) ; pic bank
