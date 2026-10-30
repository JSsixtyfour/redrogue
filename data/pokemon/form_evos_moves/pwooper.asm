PwooperFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). Paldean
; Wooper -> Clodsire (QUAGSIRE form 1) at 20, the level Wooper evolves at.
	evo_level_form 1, 20, QUAGSIRE
	db 0
; Learnset - hand-written 2026-10-29 from Paldean Wooper's SV list, mapped to
; Gen 1 moves: Poison Tail -> ACID, Toxic Spikes -> POISON_GAS, Mud Shot ->
; DIG, Poison Jab/Sludge Wave -> SLUDGE. POISON_STING/TAIL_WHIP are its
; level 1 moves.
	db 4, TACKLE
	db 11, ACID
	db 16, SLAM
	db 21, AMNESIA
	db 22, DIG
	db 24, SLUDGE
	db 36, TOXIC
	db 40, EARTHQUAKE
	db 0
