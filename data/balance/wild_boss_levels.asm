; Wild-area boss levels. INCLUDEd in place by
; custom_functions/procedural_cave_gen.asm (PCGetBossLevel reads it with a plain
; [hl]; every procedural stage farcalls PCGetBossLevel). Part of the balance
; system, see constants/balance_constants.asm.

PCBossLevelTable:
; one entry per round (0-8, wBattleCount / ROUND_BATTLES). Curve F
; (2026-10-02, BALANCE_LEVEL_SPIKE.md): the boss is the HIGHEST level of
; anything in its round, above the leader (user rule: it is a lone wild mon),
; about +5 over the rolled starter. Row 0 is unreachable (wild areas start at
; count ROUND_BATTLES); the last entry (Victory Road) is 59.
	db 11  ; round 0
	db 19  ; round 1
	db 23  ; round 2
	db 30  ; round 3
	db 36  ; round 4
	db 42  ; round 5
	db 48  ; round 6
	db 55  ; round 7
	db 59  ; round 8
