; Sylveon - VAPOREON form 2.
;
; Fairy (single type). PRIMARY Fairy becomes NORMAL. Paired with Vaporeon per
; the plan's stat-shape pairing.
; Special split: modern SpA 130 / SpD 95, take the HIGHER -> spc 130.
; HP is 110, not modern 95: every Gen 1 eeveelution rearranges one shared
; pool of 130 / 110 / 65 / 65 / 60 (see umbreon.asm), so the total is 430.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Vaporeon, same
; as the Espeon precedent.
	form_record VAPOREON, 2

	db DEX_VAPOREON ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  110, 65,  65,  60, 130
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 45 ; catch rate
	db 196 ; base exp

	INCBIN "gfx/pokemon/front/sylveon.dim" ; sprite dimensions
	dw SylveonPicFront, SylveonPicBack

	db TACKLE, SAND_ATTACK, QUICK_ATTACK, SWIFT ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     MEGA_KICK,    ICE_BEAM,     CUT,          HYPER_BEAM,   RAGE,         \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,        \
	     SKULL_BASH,   REST,         SUBSTITUTE,   FLAMETHROWER, WATER_GUN,    \
         DIG,          THUNDERBOLT,  FLASH,        PSYCHIC_M,    LIGHT_SCREEN, \
         METRONOME,    MEGA_DRAIN,   PSYWAVE,      TRI_ATTACK,   FLASH         \      
	; end

	db BANK(SylveonPicFront) ; pic bank

	dname "SYLVEON"

	form_end PAL_PINKMON
