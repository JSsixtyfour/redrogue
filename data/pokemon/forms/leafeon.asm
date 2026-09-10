; Leafeon - FLAREON form 1.
;
; Grass (single type). Paired with Flareon per the plan's stat-shape pairing:
; both are physical attackers with a 130 stat in their respective bulk/attack
; column (Flareon ATK 130, Leafeon DEF 130).
; Special split: modern SpA 60 / SpD 65, take the HIGHER -> spc 65.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Flareon, same
; as the Espeon precedent.
	form_record FLAREON, 1

	db DEX_FLAREON ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  65, 110, 130,  95,  65
	;   hp  atk  def  spd  spc

	db GRASS, GRASS ; type
	db 45 ; catch rate
	db 198 ; base exp

	INCBIN "gfx/pokemon/front/leafeon.pic", 0, 1 ; sprite dimensions
	dw LeafeonPicFront, LeafeonPicBack

	db TACKLE, SAND_ATTACK, QUICK_ATTACK, EMBER ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     FIRE_BLAST,   SWIFT,        SKULL_BASH,   REST,         SUBSTITUTE,   \
         FLAMETHROWER
	; end

	db BANK(LeafeonPicFront) ; pic bank

	dname "LEAFEON"

	form_end
