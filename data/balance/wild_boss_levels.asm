; Wild-area boss levels. INCLUDEd in place by
; custom_functions/procedural_cave_gen.asm (PCGetBossLevel reads it with a plain
; [hl]; every procedural stage farcalls PCGetBossLevel). Part of the balance
; system, see constants/balance_constants.asm.

PCBossLevelTable:
; one entry per round (0-8, wBattleCount / ROUND_BATTLES). Curve D
; (BALANCE_PHASE5_PLAN.md D, 2026-09-28): the boss matches that round's gym
; leader ace; the last entry (Victory Road) is 63.
	db 15  ; round 0
	db 23  ; round 1
	db 30  ; round 2
	db 36  ; round 3
	db 42  ; round 4
	db 47  ; round 5
	db 52  ; round 6
	db 57  ; round 7
	db 63  ; round 8
