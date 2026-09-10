; Glaceon - VAPOREON form 1.
;
; Ice (single type). Paired with Vaporeon per the plan's stat-shape pairing
; (see espeon.asm for the rationale behind pairing eeveelutions by stat shape
; rather than base-species lineage).
; Special split: modern SpA 130 / SpD 95, take the HIGHER -> spc 130.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Vaporeon, same
; as the Espeon precedent.
	form_record VAPOREON, 1

	db DEX_VAPOREON ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  65,  60, 110,  65, 130
	;   hp  atk  def  spd  spc

	db ICE, ICE ; type
	db 45 ; catch rate
	db 196 ; base exp

	INCBIN "gfx/pokemon/front/glaceon.pic", 0, 1 ; sprite dimensions
	dw GlaceonPicFront, GlaceonPicBack

	db TACKLE, SAND_ATTACK, QUICK_ATTACK, WATER_GUN ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,        \
	     SKULL_BASH,   REST,         SUBSTITUTE,   SURF
	; end

	db BANK(GlaceonPicFront) ; pic bank

	dname "GLACEON"

	form_end
