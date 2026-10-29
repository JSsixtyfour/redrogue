; Fossil Kabutops - KABUTOPS form 1 (FOSSIL_FORM). See fossilaerodactyl.asm.
; If Kabutops's base stats or tmhm change, copy them here.
	form_record KABUTOPS, 1 ; FOSSIL_FORM, literal as in fossilaerodactyl.asm

	db DEX_KABUTOPS ; pokedex id (documentation only)

	db  60, 115, 105,  80,  70
	;   hp  atk  def  spd  spc

	db ROCK, WATER ; type
	db 45 ; catch rate
	db 201 ; base exp

	INCBIN "gfx/pokemon/front/fossilkabutops.dim" ; sprite dimensions
	dw FossilKabutopsPicFront, FossilKabutopsPicBack

	db SCRATCH, HARDEN, ABSORB, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - Kabutops's
	tmhm CUT,          RAZOR_WIND,   SWORDS_DANCE, MEGA_KICK,    TOXIC,        \
	     BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    \
	     ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   SUBMISSION,   SEISMIC_TOSS, \
	     RAGE,         MEGA_DRAIN,   MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         SKULL_BASH,   REST,         ROCK_SLIDE,   SUBSTITUTE,   \
	     SURF
	; end

	db BANK(FossilKabutopsPicFront) ; pic bank

	dname "KABUTOPS"

	form_end PAL_PURPLEMON
