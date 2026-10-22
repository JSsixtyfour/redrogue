; Paldean Tauros (Aqua Breed) - TAUROS form 3. The binding case: this base
; uses all three form slots (Combat/Blaze/Aqua).
;
; Fighting/Water, both valid Gen 1 types.
; Stats are 75/110/105/100/60, shared by all three breeds (the modern breeds
; share one spread too). Speed 100 and spc 60 are set so the total matches
; vanilla Tauros's 450. Only the secondary type differs from Blaze Breed.
; Moves/growth/catch rate/base exp copied verbatim from Tauros. The tmhm list is
; Tauros's minus Ice Beam, Blizzard, Thunder and Thunderbolt (canon SV losses, 2026-10-21)
	form_record TAUROS, 3

	db DEX_TAUROS ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  75, 110, 105, 100,  60
	;   hp  atk  def  spd  spc

	db FIGHTING, WATER ; type
	db 45 ; catch rate
	db 211 ; base exp

	INCBIN "gfx/pokemon/front/ptaurosaqua.dim" ; sprite dimensions
	dw PTaurosAquaPicFront, PTaurosAquaPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        HORN_DRILL,   BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         EARTHQUAKE,   FISSURE,      MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         SURF,         SKULL_BASH,   REST,         \
	     SUBSTITUTE,   STRENGTH,     BUBBLEBEAM,   MEGA_KICK,    WATER_GUN
	; end

	db BANK(PTaurosAquaPicFront) ; pic bank

	dname "A-TAUROS"

	form_end PAL_CYANMON
