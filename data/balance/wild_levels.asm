; Wild-area wild encounter levels. INCLUDEd in place by
; custom_functions/procedural_cave_gen.asm (PCGetWildLevel reads it with a plain
; [hl]). Every procedural stage uses it. Part of the balance system, see
; constants/balance_constants.asm.

PCWildLevelTable:
	db 5, 9, 13, 17, 21, 25, 29, 33, 37 ; rounds 0-8, min level (add 0-2 for range)
