; Wild-area boss levels. INCLUDEd in place by
; custom_functions/procedural_cave_gen.asm (PCGetBossLevel reads it with a plain
; [hl]; every procedural stage farcalls PCGetBossLevel). Part of the balance
; system, see constants/balance_constants.asm.

PCBossLevelTable:
; one entry per round (0-8, wBattleCount / ROUND_BATTLES). Curve F
; (2026-10-02, BALANCE_LEVEL_SPIKE.md) set the boss well above the party (user
; rule: it is a lone wild mon). 2026-10-06: every row -2, since the boss sat
; ~6.5 over the team average on entry; it is now ~4.5 over. Row 0 is
; unreachable (wild areas start at count ROUND_BATTLES); the last entry
; (Victory Road) is 57.
	db 9  ; round 0
	db 17  ; round 1
	db 21  ; round 2
	db 28  ; round 3
	db 34  ; round 4
	db 40  ; round 5
	db 46  ; round 6
	db 53  ; round 7
	db 57  ; round 8
