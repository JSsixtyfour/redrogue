; Galarian Slowking - SLOWKING form 1.
;
; Poison/Psychic, both valid Gen 1 types.
; Special split: modern SpA 110 / SpD 110, tie either way -> spc 110.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Slowking.
	form_record SLOWKING, 1

	db DEX_SLOWKING ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  95,  65,  80,  30, 110
	;   hp  atk  def  spd  spc

	db POISON, PSYCHIC_TYPE ; type
	db 70 ; catch rate
	db 164 ; base exp

	INCBIN "gfx/pokemon/front/gslowking.pic", 0, 1 ; sprite dimensions
	dw GSlowkingPicFront, GSlowkingPicBack

	db CONFUSION, DISABLE, HEADBUTT, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - from tmp/kep/data/pokemon/base_stats/slowking.asm, minus
	; TELEPORT (not a valid TM/HM move here - KEP's TM list differs from ours)
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     BLIZZARD,     \
	     HYPER_BEAM,   PAY_DAY,      SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         EARTHQUAKE,   FISSURE,      DIG,          PSYCHIC_M,    \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     FIRE_BLAST,   SWIFT,        SKULL_BASH,   REST,         THUNDER_WAVE, \
	     PSYWAVE,      TRI_ATTACK,   SUBSTITUTE,   SURF,         STRENGTH,     \
	     FLASH
	; end

	db BANK(GSlowkingPicFront) ; pic bank

	dname "G-SLOWKING"

	form_end
