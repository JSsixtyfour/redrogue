; Espeon - JOLTEON form 1.
;
; The first FORM-SETTING form: reached by using a Sun Stone on an Eevee, which
; evolves it into JOLTEON and then has ApplyEvoStoneForm write form 1 (see
; EvoStoneForms in engine/pokemon/evos_moves.asm). Every other form so far is
; form-preserving, which costs nothing; this one changes species and form at
; once, which is why the mapping needs its own table.
;
; Paired with Jolteon rather than another base for a reason the plan records:
; Espeon shares Jolteon's 110 Speed, so the two read as the same shape of mon.
;
; Transcription rules applied:
;  - Espeon is Psychic in every generation, so no type rule fires.
;  - Special split: modern SpA 130 / SpD 95, take the HIGHER -> spc 130.
;  - Speed 110 matches Jolteon's 130? No: Espeon's modern Speed is 110, so the
;    spd column below is 110 while Jolteon's own row keeps 130.
;  - Catch rate 45 and base exp 197 kept in line with the Kanto eeveelutions.
	form_record JOLTEON, 1

	db DEX_JOLTEON ; pokedex id (documentation only - GetMonHeader overwrites
	               ; byte 0 with the species index right after the patch)

	db  65,  65,  60, 110, 130
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, PSYCHIC_TYPE ; type
	db 45 ; catch rate
	db 197 ; base exp

	INCBIN "gfx/pokemon/front/espeon.pic", 0, 1 ; sprite dimensions
	dw EspeonPicFront, EspeonPicBack

	db TACKLE, SAND_ATTACK, QUICK_ATTACK, CONFUSION ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - Jolteon's, minus the Electric-only machines, plus the
	; Psychic ones this form can actually use.
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         PSYCHIC_M,    MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         SWIFT,        SKULL_BASH,   REST,         SUBSTITUTE,   \
	     FLASH
	; end

	db BANK(EspeonPicFront) ; pic bank

	dname "ESPEON"

	form_end
