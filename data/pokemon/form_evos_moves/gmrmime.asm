GmrmimeFormEvosMoves:
; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). Only
; Galarian Mr. Mime evolves; plain Mr. Mime's species list stays empty.
; Level 42 is canon (Sword/Shield).
	db EVOLVE_LEVEL, 42, MR_RIME
	db 0
; Learnset - Mr. Rime's (MrRimeEvosMoves), user decision 2026-10-27.
; CONFUSION/BARRIER/REFLECT are granted at level 1 by the form record.
; Learnset
	db 23, LIGHT_SCREEN
	db 23, REFLECT
	db 25, DOUBLESLAP
	db 28, AURORA_BEAM
	db 31, PSYBEAM
	db 39, ICE_BEAM
	db 44, PSYCHIC_M
	db 50, MIST
	db 0
