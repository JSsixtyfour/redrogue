; Alolan Ninetales - NINETALES form 1.
;
; Ice/Fairy. SECONDARY Fairy is DROPPED, leaving ICE/ICE.
; Special split: modern SpA 81 / SpD 100, take the HIGHER -> spc 100.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Ninetales.
; Name ANINETALES has no hyphen: 'A-NINETALES' is 11 characters, one over cap.
	form_record NINETALES, 1

	db DEX_NINETALES ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  73,  67,  75, 109, 100
	;   hp  atk  def  spd  spc

	db ICE, ICE ; type
	db 75 ; catch rate
	db 178 ; base exp

	INCBIN "gfx/pokemon/front/aninetales.pic", 0, 1 ; sprite dimensions
	dw ANinetalesPicFront, ANinetalesPicBack

	db EMBER, TAIL_WHIP, QUICK_ATTACK, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         DIG,          MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         FIRE_BLAST,   SWIFT,        SKULL_BASH,   REST,         \
	     SUBSTITUTE,   FLAMETHROWER
	; end

	db BANK(ANinetalesPicFront) ; pic bank

	dname "ANINETALES"

	form_end
