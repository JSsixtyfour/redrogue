	db DEX_SLOWKING ; pokedex id

	db  95,  75,  80,  30, 110
	;   hp  atk  def  spd  spc

	db WATER, PSYCHIC_TYPE ; type
	db 70 ; catch rate
	db 164 ; base exp

	INCBIN "gfx/pokemon/front/slowking.dim" ; sprite dimensions
	dw SlowkingPicFront, SlowkingPicBack

	db CONFUSION, TACKLE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - from tmp/kep/data/pokemon/base_stats/slowking.asm, minus
	; TELEPORT (not a valid TM/HM move here - KEP's TM list differs from ours)
	tmhm MEGA_PUNCH,   LIGHT_SCREEN, MEGA_KICK,    TOXIC,        BODY_SLAM,    \
	     TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     \
	     BLIZZARD,     HYPER_BEAM,   PAY_DAY,      SUBMISSION,   COUNTER,      \
	     SEISMIC_TOSS, RAGE,         EARTHQUAKE,   FISSURE,      DIG,          \
	     PSYCHIC_M,    FLAMETHROWER, MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         METRONOME,    FIRE_BLAST,   SWIFT,        SKULL_BASH,   \
	     DREAM_EATER,  REST,         THUNDER_WAVE, PSYWAVE,      TRI_ATTACK,   \
	     SUBSTITUTE,   SURF,         STRENGTH,     FLASH
	; end

	db BANK(SlowkingPicFront) ; pic bank
