	db DEX_TOGETIC ; pokedex id

	db  55,  40,  85,  40, 105
	;   hp  atk  def  spd  spc

	db NORMAL, FLYING ; type
	db 75 ; catch rate
	db 114 ; base exp

	INCBIN "gfx/pokemon/front/togetic.pic", 0, 1 ; sprite dimensions
	dw TogeticPicFront, TogeticPicBack

	db GROWL, METRONOME, NO_MOVE, NO_MOVE ; level 1 learnset - CHARM filled with METRONOME
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     BLIZZARD,     \
	     SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         SOLARBEAM,    \
	     THUNDERBOLT,  THUNDER,      PSYCHIC_M,    LIGHT_SCREEN, MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         METRONOME,    FIRE_BLAST,   \
	     SKULL_BASH,   REST,         THUNDER_WAVE, PSYWAVE,      TRI_ATTACK,   \
	     SUBSTITUTE,   STRENGTH,     FLASH,        FLAMETHROWER, FLY
	; end

	db BANK(TogeticPicFront) ; pic bank
