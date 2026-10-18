; Scream Tail - JIGGLYPUFF form 1.
;
; Paired with Jigglypuff (paradox 'ancient Jigglypuff'): Fairy/Psychic.
; PRIMARY Fairy becomes NORMAL; secondary Psychic is unaffected.
; Special: spc 105, between the modern values (SpA 65 / SpD 115). Total 495,
; just under the pseudo-legendaries (500); taking SpD 115 put it at 505.
; Base exp 211 matches Sandy Shocks, its paradox partner: just under the
; legendary birds/beasts (215-217), level with Tangrowth.
; Moves/growth/catch rate/tmhm copied verbatim from Jigglypuff, same as the
; Espeon precedent.
	form_record JIGGLYPUFF, 1

	db DEX_JIGGLYPUFF ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db 115,  65,  99, 111, 105
	;   hp  atk  def  spd  spc

	db NORMAL, PSYCHIC_TYPE ; type
	db 170 ; catch rate
	db 211 ; base exp

	INCBIN "gfx/pokemon/front/screamtail.dim" ; sprite dimensions
	dw ScreamTailPicFront, ScreamTailPicBack

	db SING, POUND, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     BLIZZARD,     \
	     SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         HYPER_BEAM,    \
	     THUNDERBOLT,  THUNDER,      PSYCHIC_M,    FLAMETHROWER, MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         FIRE_BLAST,   SKULL_BASH,   \
	     REST,         THUNDER_WAVE, PSYWAVE,      TRI_ATTACK,   SUBSTITUTE,   \
	     STRENGTH,     FLASH,        LIGHT_SCREEN
	; end

	db BANK(ScreamTailPicFront) ; pic bank

	dname "SCREAMTAIL"

	form_end PAL_PINKMON
