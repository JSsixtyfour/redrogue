; Galarian Slowpoke - SLOWPOKE form 1.
;
; Psychic (single type in modern games).
; Special split: modern SpA 40 / SpD 40, tie either way -> spc 40.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Slowpoke.
	form_record SLOWPOKE, 1

	db DEX_SLOWPOKE ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  90,  65,  65,  15,  40
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, PSYCHIC_TYPE ; type
	db 190 ; catch rate
	db 99 ; base exp

	INCBIN "gfx/pokemon/front/gslowpoke.pic", 0, 1 ; sprite dimensions
	dw GSlowpokePicFront, GSlowpokePicBack

	db CONFUSION, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     PAY_DAY,      RAGE,         \
	     EARTHQUAKE,   FISSURE,      DIG,          PSYCHIC_M,    LIGHT_SCREEN, \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         FIRE_BLAST,   \
	     SWIFT,        SKULL_BASH,   REST,         THUNDER_WAVE, PSYWAVE,      \
	     TRI_ATTACK,   SUBSTITUTE,   SURF,         STRENGTH,     FLASH,        \ 
         FLAMETHROWER
	; end

	db BANK(GSlowpokePicFront) ; pic bank

	dname "G-SLOWPOKE"

	form_end
