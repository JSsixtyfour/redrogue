; Sylveon - VAPOREON form 2.
;
; Fairy (single type). PRIMARY Fairy becomes NORMAL. Paired with Vaporeon per
; the plan's stat-shape pairing.
; Special split: modern SpA 130 / SpD 95, take the HIGHER -> spc 130.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Vaporeon, same
; as the Espeon precedent.
	form_record VAPOREON, 2

	db DEX_VAPOREON ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  95,  65,  65,  60, 130
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 45 ; catch rate
	db 196 ; base exp

	INCBIN "gfx/pokemon/front/sylveon.pic", 0, 1 ; sprite dimensions
	dw SylveonPicFront, SylveonPicBack

	db TACKLE, SAND_ATTACK, QUICK_ATTACK, WATER_GUN ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,        \
	     SKULL_BASH,   REST,         SUBSTITUTE,   SURF
	; end

	db BANK(SylveonPicFront) ; pic bank

	dname "SYLVEON"

	form_end
