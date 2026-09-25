; Wild-area boss levels. INCLUDEd in place by
; custom_functions/procedural_cave_gen.asm (PCGetBossLevel reads it with a plain
; [hl]; every procedural stage farcalls PCGetBossLevel). Part of the balance
; system, see constants/balance_constants.asm.

PCBossLevelTable:
; one entry per round (0-8, based on wBattleCount / 10)
; designed to be ~15-20 levels above typical reward pokemon at the same
; battle count (reward pokemon cap at 50; boss reaches up to 80)
	db 11  ; round 0 (battles  0-9)
	db 22  ; round 1 (battles 10-19)
	db 25  ; round 2 (battles 20-29)
	db 30  ; round 3 (battles 30-39)
	db 44  ; round 4 (battles 40-49)
	db 44  ; round 5 (battles 50-59)
	db 48  ; round 6 (battles 60-69)
	db 51  ; round 7 (battles 70-79)
	db 60  ; round 8 (battles 80-89)
