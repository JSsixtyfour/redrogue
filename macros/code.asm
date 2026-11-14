; Syntactic sugar macros

MACRO? lb ; r, hi, lo
	ld \1, ((\2) & $ff) << 8 + ((\3) & $ff)
ENDM

MACRO? ldpal
	ld \1, \2 << 6 | \3 << 4 | \4 << 2 | \5
ENDM

; Design patterns

MACRO ld_hli_a_string
	FOR n, CHARLEN(\1) - 1
		ld a, CHARVAL(STRCHAR(\1, n))
		ld [hli], a
	ENDR
	ld [hl], CHARVAL(STRCHAR(\1, CHARLEN(\1) - 1))
ENDM

MACRO dict
	IF \1 == 0
		and a
	ELSE
		cp \1
	ENDC
	jp z, \2
ENDM

; Run challenges (constants/ram_constants.asm RUN_CH_*): NZ when run challenge
; \1 is on for this run. 5 bytes, clobbers a only, so it drops in beside an
; existing witch `bit BIT_WITCH_ACCEPTED` / `cp CHALLENGE_*` test.
MACRO run_challenge
	ld a, [wRunChallenges + (\1) / 8]
	bit (\1) % 8, a
ENDM
