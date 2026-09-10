; Galarian Weezing - WEEZING form 1.
;
; Poison/Fairy. SECONDARY Fairy is DROPPED, leaving POISON/POISON like vanilla
; Weezing.
; Special split: modern SpA 85 / SpD 70, take the HIGHER -> spc 85.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Weezing.
	form_record WEEZING, 1

	db DEX_WEEZING ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  65,  90, 120,  60,  85
	;   hp  atk  def  spd  spc

	db POISON, POISON ; type
	db 60 ; catch rate
	db 173 ; base exp

	INCBIN "gfx/pokemon/front/gweezing.pic", 0, 1 ; sprite dimensions
	dw GWeezingPicFront, GWeezingPicBack

	db TACKLE, SMOG, SLUDGE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        HYPER_BEAM,   RAGE,         THUNDERBOLT,  THUNDER,      \
	     MIMIC,        DOUBLE_TEAM,  BIDE,         SELFDESTRUCT, FIRE_BLAST,   \
	     REST,         EXPLOSION,    SUBSTITUTE,   FLAMETHROWER
	; end

	db BANK(GWeezingPicFront) ; pic bank

	dname "G-WEEZING"

	form_end
