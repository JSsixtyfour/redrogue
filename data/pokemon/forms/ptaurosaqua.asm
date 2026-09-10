; Paldean Tauros (Aqua Breed) - TAUROS form 3. The binding case: this base
; uses all three form slots (Combat/Blaze/Aqua).
;
; Fighting/Water, both valid Gen 1 types.
; Special split: modern SpA 55 / SpD 65, take the HIGHER -> spc 65.
; Same stat spread as Blaze Breed; only the secondary type differs.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Tauros.
	form_record TAUROS, 3

	db DEX_TAUROS ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  75, 110, 105,  85,  65
	;   hp  atk  def  spd  spc

	db FIGHTING, WATER ; type
	db 45 ; catch rate
	db 211 ; base exp

	INCBIN "gfx/pokemon/front/ptaurosaqua.pic", 0, 1 ; sprite dimensions
	dw PTaurosAquaPicFront, PTaurosAquaPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        HORN_DRILL,   BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         THUNDERBOLT,  \
	     THUNDER,      EARTHQUAKE,   FISSURE,      MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         FIRE_BLAST,   SKULL_BASH,   REST,         SUBSTITUTE,   \
	     STRENGTH,     FLAMETHROWER
	; end

	db BANK(PTaurosAquaPicFront) ; pic bank

	dname "P-AQUA"

	form_end
