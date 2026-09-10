; Alolan Raichu - RAICHU form 1.
;
; Electric/Psychic, both valid Gen 1 types.
; Special split: modern SpA 95 / SpD 85, take the HIGHER -> spc 95.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Raichu.
	form_record RAICHU, 1

	db DEX_RAICHU ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  60,  85,  50, 110,  95
	;   hp  atk  def  spd  spc

	db ELECTRIC, PSYCHIC_TYPE ; type
	db 75 ; catch rate
	db 122 ; base exp

	INCBIN "gfx/pokemon/front/araichu.pic", 0, 1 ; sprite dimensions
	dw ARaichuPicFront, ARaichuPicBack

	db THUNDERSHOCK, GROWL, THUNDER_WAVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  HYPER_BEAM,   PAY_DAY,      SUBMISSION,   SEISMIC_TOSS, \
	     RAGE,         THUNDERBOLT,  THUNDER,      MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         SWIFT,        SKULL_BASH,   REST,         \
	     THUNDER_WAVE, SUBSTITUTE,   FLASH,        LIGHT_SCREEN, SURF
	; end

	db BANK(ARaichuPicFront) ; pic bank

	dname "A-RAICHU"

	form_end
