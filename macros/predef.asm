MACRO? predef_id
	ld a, (\1Predef - PredefPointers) / 3
ENDM

; Predef's entry is the rst $28 vector (home/header.asm): 3 B per site, not 5.
DEF RST_PREDEF EQU $28

MACRO? predef
	predef_id \1
	rst RST_PREDEF
ENDM

MACRO? predef_jump
	predef_id \1
	jp Predef
ENDM


MACRO? tx_pre_id
	ld a, (\1_id - TextPredefs) / 2 + 1
ENDM

MACRO? tx_pre
	tx_pre_id \1
	call PrintPredefTextID
ENDM

MACRO? tx_pre_jump
	tx_pre_id \1
	jp PrintPredefTextID
ENDM

MACRO? db_tx_pre
	db (\1_id - TextPredefs) / 2 + 1
ENDM
