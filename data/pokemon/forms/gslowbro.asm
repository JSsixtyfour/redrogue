; Galarian Slowbro - SLOWBRO form 1.
;
; Poison/Psychic, both valid Gen 1 types.
; Special split: modern SpA 100 / SpD 70, take the HIGHER -> spc 100.
; ATK is the biggest stat jump: 100 vs vanilla Slowbro's 75.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Slowbro.
	form_record SLOWBRO, 1

	db DEX_SLOWBRO ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  95, 100,  95,  30, 100
	;   hp  atk  def  spd  spc

	db POISON, PSYCHIC_TYPE ; type
	db 75 ; catch rate
	db 164 ; base exp

	INCBIN "gfx/pokemon/front/gslowbro.pic", 0, 1 ; sprite dimensions
	dw GSlowbroPicFront, GSlowbroPicBack

	db CONFUSION, DISABLE, HEADBUTT, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     BLIZZARD,     \
	     HYPER_BEAM,   PAY_DAY,      SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         EARTHQUAKE,   FISSURE,      DIG,          PSYCHIC_M,    \
	     LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     FIRE_BLAST,   SWIFT,        SKULL_BASH,   REST,         THUNDER_WAVE, \
	     PSYWAVE,      TRI_ATTACK,   SUBSTITUTE,   SURF,         STRENGTH,     \
	     FLASH,        FLAMETHROWER
	; end

	db BANK(GSlowbroPicFront) ; pic bank

	dname "G-SLOWBRO"

	form_end
