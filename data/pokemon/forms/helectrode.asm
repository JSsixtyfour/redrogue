; Hisuian Electrode - ELECTRODE form 1.
;
; Electric/Grass, both valid Gen 1 types.
; Special split: modern SpA 80 / SpD 80, tie either way -> spc 80.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Electrode.
; Name HELECTRODE has no hyphen: 'H-ELECTRODE' is 11 characters, one over cap.
	form_record ELECTRODE, 1

	db DEX_ELECTRODE ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  60,  50,  70, 150,  80
	;   hp  atk  def  spd  spc

	db ELECTRIC, GRASS ; type
	db 60 ; catch rate
	db 150 ; base exp

	INCBIN "gfx/pokemon/front/helectrode.pic", 0, 1 ; sprite dimensions
	dw HElectrodePicFront, HElectrodePicBack

	db TACKLE, SCREECH, SONICBOOM, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        TAKE_DOWN,    HYPER_BEAM,   RAGE,         THUNDERBOLT,  \
	     THUNDER,      LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         SELFDESTRUCT, SWIFT,        SKULL_BASH,   REST,         \
	     THUNDER_WAVE, EXPLOSION,    SUBSTITUTE,   FLASH
	; end

	db BANK(HElectrodePicFront) ; pic bank

	dname "HELECTRODE"

	form_end
