; Mini-boss level tier. INCLUDEd in place by custom_functions/func_enc_gen.asm:
; it must stay in that section (MiniBossSetLevel reads it with a plain [hl]).
; Part of the balance system, see constants/balance_constants.asm.

; One 4-byte block per round: db level_range, min_level, base_class, rare_chance.
; min_level sits BETWEEN the round's final route trainer and its gym trainers
; (see trainer_difficulty_settings / _gym above). base_class is GetRandMon's
; convention (4=pokeball, 3=greatball, 2=ultraball, 1=masterball); rare_chance/256
; = odds a fill mon is bumped one tier rarer. Fully tunable.
trainer_difficulty_settings_miniboss:
	db 3, 5,  3, 64   ; round 1 (between route-final ~4 and gym ~5)
	db 4, 15, 3, 80   ; round 2
	db 4, 20, 2, 64   ; round 3
	db 5, 25, 2, 80   ; round 4
	db 6, 33, 2, 96   ; round 5
	db 6, 37, 2, 112  ; round 6
	db 6, 41, 2, 128  ; round 7
	db 7, 45, 1, 96   ; round 8
	db 8, 52, 1, 112  ; round 9
