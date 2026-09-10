; Alolan Muk - MUK form 1.
;
; Poison/Dark. SECONDARY Dark is DROPPED, leaving POISON/POISON like vanilla Muk.
; Special split: modern SpA 65 / SpD 100, take the HIGHER -> spc 100.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Muk.
	form_record MUK, 1

	db DEX_MUK ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db 105, 105,  75,  50, 100
	;   hp  atk  def  spd  spc

	db POISON, POISON ; type
	db 75 ; catch rate
	db 157 ; base exp

	INCBIN "gfx/pokemon/front/amuk.pic", 0, 1 ; sprite dimensions
	dw AMukPicFront, AMukPicBack

	db POUND, DISABLE, POISON_GAS, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    HYPER_BEAM,   RAGE,         MEGA_DRAIN,   \
	     THUNDERBOLT,  THUNDER,      MIMIC,        DOUBLE_TEAM,  BIDE,         \
	     SELFDESTRUCT, FIRE_BLAST,   REST,         EXPLOSION,    SUBSTITUTE,   \
         FLAMETHROWER
	; end

	db BANK(AMukPicFront) ; pic bank

	dname "A-MUK"

	form_end
