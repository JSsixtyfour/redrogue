; Hisuian Qwilfish - QWILFISH form 1.
;
; Dark/Poison. PRIMARY Dark becomes NORMAL; secondary Poison is unaffected.
; Special split: modern SpA 55 / SpD 55, tie either way -> spc 55.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Qwilfish.
; Placeholder blank art per PHASE_2R_SONNET_SPEC.md section 2 - record written
; anyway, sprite is a separate task.
	form_record QWILFISH, 1

	db DEX_QWILFISH ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  65,  95,  85,  85,  55
	;   hp  atk  def  spd  spc

	db NORMAL, POISON ; type
	db 45 ; catch rate
	db 100 ; base exp

	INCBIN "gfx/pokemon/front/hqwilfish.pic", 0, 1 ; sprite dimensions
	dw HQwilfishPicFront, HQwilfishPicBack

	db TACKLE, POISON_STING, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     MEGA_DRAIN,   MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SKULL_BASH,   REST,         SUBSTITUTE,   CUT,          SURF
	; end

	db BANK(HQwilfishPicFront) ; pic bank

	dname "H-QWILFISH"

	form_end
