; Scream Tail - JIGGLYPUFF form 1.
;
; Paired with Jigglypuff (paradox 'ancient Jigglypuff'): Fairy/Psychic.
; PRIMARY Fairy becomes NORMAL; secondary Psychic is unaffected.
; Special split: modern SpA 65 / SpD 115, take the HIGHER -> spc 115.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Jigglypuff, same
; as the Espeon precedent.
	form_record JIGGLYPUFF, 1

	db DEX_JIGGLYPUFF ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db 115,  65,  99, 111, 115
	;   hp  atk  def  spd  spc

	db NORMAL, PSYCHIC_TYPE ; type
	db 170 ; catch rate
	db 76 ; base exp

	INCBIN "gfx/pokemon/front/screamtail.pic", 0, 1 ; sprite dimensions
	dw ScreamTailPicFront, ScreamTailPicBack

	db SING, POUND, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     BLIZZARD,     \
	     SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         SOLARBEAM,    \
	     THUNDERBOLT,  THUNDER,      PSYCHIC_M,    FLAMETHROWER, MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         FIRE_BLAST,   SKULL_BASH,   \
	     REST,         THUNDER_WAVE, PSYWAVE,      TRI_ATTACK,   SUBSTITUTE,   \
	     STRENGTH,     FLASH,        LIGHT_SCREEN
	; end

	db BANK(ScreamTailPicFront) ; pic bank

	dname "SCREAMTAIL"

	form_end
