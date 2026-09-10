; Paldean Tauros (Combat Breed) - TAUROS form 1.
;
; Fighting (single type in modern games). Stats match vanilla Kantonian Tauros
; exactly - Combat Breed is the baseline the other two breeds trade Speed for
; bulk/offense against.
; Special split: modern SpA 40 / SpD 70, take the HIGHER -> spc 70.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Tauros.
	form_record TAUROS, 1

	db DEX_TAUROS ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  75, 100,  95, 110,  70
	;   hp  atk  def  spd  spc

	db FIGHTING, FIGHTING ; type
	db 45 ; catch rate
	db 211 ; base exp

	INCBIN "gfx/pokemon/front/ptauroscombat.pic", 0, 1 ; sprite dimensions
	dw PTaurosCombatPicFront, PTaurosCombatPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        HORN_DRILL,   BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         THUNDERBOLT,  \
	     THUNDER,      EARTHQUAKE,   FISSURE,      MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         FIRE_BLAST,   SKULL_BASH,   REST,         SUBSTITUTE,   \
	     STRENGTH,     FLAMETHROWER
	; end

	db BANK(PTaurosCombatPicFront) ; pic bank

	dname "P-COMBAT"

	form_end
