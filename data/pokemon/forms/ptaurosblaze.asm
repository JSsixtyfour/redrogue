; Paldean Tauros (Blaze Breed) - TAUROS form 2.
;
; Fighting/Fire, both valid Gen 1 types.
; Special split: modern SpA 55 / SpD 65, take the HIGHER -> spc 65.
; ATK/DEF are higher than Combat Breed, SPD lower - the fire/water breeds trade
; speed for bulk and power.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Tauros.
	form_record TAUROS, 2

	db DEX_TAUROS ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  75, 110, 105,  85,  65
	;   hp  atk  def  spd  spc

	db FIGHTING, FIRE ; type
	db 45 ; catch rate
	db 211 ; base exp

	INCBIN "gfx/pokemon/front/ptaurosblaze.pic", 0, 1 ; sprite dimensions
	dw PTaurosBlazePicFront, PTaurosBlazePicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        HORN_DRILL,   BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         THUNDERBOLT,  \
	     THUNDER,      EARTHQUAKE,   FISSURE,      MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         FIRE_BLAST,   SKULL_BASH,   REST,         SUBSTITUTE,   \
	     STRENGTH,     FLAMETHROWER
	; end

	db BANK(PTaurosBlazePicFront) ; pic bank

	dname "P-BLAZE"

	form_end
