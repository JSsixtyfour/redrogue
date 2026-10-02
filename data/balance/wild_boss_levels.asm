; Wild-area boss levels. INCLUDEd in place by
; custom_functions/procedural_cave_gen.asm (PCGetBossLevel reads it with a plain
; [hl]; every procedural stage farcalls PCGetBossLevel). Part of the balance
; system, see constants/balance_constants.asm.

PCBossLevelTable:
; one entry per round (0-8, wBattleCount / ROUND_BATTLES). Curve D
; (BALANCE_PHASE5_PLAN.md D, 2026-09-28): the boss matches that round's gym
; leader ace; the last entry (Victory Road) is 59. Shifted -4 on 2026-10-02
; with the trainer tables; Curve E then raised the leader aces 2-3, so the boss
; now sits 2-3 under the ace (BALANCE_LEVEL_SPIKE.md: still open whether a lone
; boss this far over the player is right).
	db 11  ; round 0
	db 19  ; round 1
	db 26  ; round 2
	db 32  ; round 3
	db 38  ; round 4
	db 43  ; round 5
	db 48  ; round 6
	db 53  ; round 7
	db 59  ; round 8
