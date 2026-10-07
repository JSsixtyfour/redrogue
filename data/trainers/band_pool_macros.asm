; Macros for data/trainers/band_pools.asm (generated from PARTY_ROSTER.md).
; Moved out of pools.asm 2026-10-07 (party roster Phase 2) so party_specs.asm,
; which is assembled BEFORE pools.asm, can run its own pass. No bytes here.
;
; band_pools.asm is INCLUDEd four times; BAND_POOL_PASS picks what each macro
; emits:
;   3  `DEF BAND_HAS_<name> EQU 1` per pool, aliases included (party_specs.asm,
;      first). banded_round_spec reads BAND_HAS_<Char>_Ace<band> and
;      BAND_HAS_<Char>_Off<band> to decide whether a band has an ace slot and an
;      off-type slot. Only presence is known this early: the POOL_BAND_* ids
;      below do not exist yet, which is why this is a separate pass.
;   0  `const POOL_BAND_<name>` per pool (inside pools.asm's const_def)
;   1  one TrainerPoolTable row per pool
;   2  the entry lists with their four run labels
; so a pool is written once and its flag, id, row and list cannot disagree.
MACRO band_pool
	REDEF BAND_CUR EQUS "\1"
	IF BAND_POOL_PASS == 3
	DEF BAND_HAS_\1 EQU 1
	ELIF BAND_POOL_PASS == 0
	const POOL_BAND_\1
	ELIF BAND_POOL_PASS == 1
	trainer_pool BandPool_\1
	ELIF BAND_POOL_PASS == 2
BandPool_\1:
	ENDC
ENDM

; \1 = new name, \2 = an identical pool already defined. An alias, no bytes.
MACRO band_same
	IF BAND_POOL_PASS == 3
	DEF BAND_HAS_\1 EQU 1
	ELIF BAND_POOL_PASS == 0
	DEF POOL_BAND_\1 EQU POOL_BAND_\2
	ENDC
ENDM

MACRO band_johto
	IF BAND_POOL_PASS == 2
BandPool_{BAND_CUR}_Johto:
	ENDC
ENDM

MACRO band_warp
	IF BAND_POOL_PASS == 2
BandPool_{BAND_CUR}_Warp:
	ENDC
ENDM

MACRO band_end
	IF BAND_POOL_PASS == 2
BandPool_{BAND_CUR}_End:
	ENDC
ENDM

; \1 = species, \2 = optional form index. Evolved by level (fodder, off-type).
MACRO band_mon
	IF BAND_POOL_PASS == 2
	IF _NARG >= 2
	pool_mon \1, \2
	ELSE
	pool_mon \1
	ENDC
	ENDC
ENDM

; \1 = species, \2 = optional form index. Used AS WRITTEN (an ace): the form
; spec carries POOL_FORM_KEEP, so ScaleTrainer_evolution never touches it.
MACRO band_ace
	IF BAND_POOL_PASS == 2
	IF _NARG >= 2
	pool_mon \1, POOL_FORM_KEEP | (\2)
	ELSE
	pool_mon \1, POOL_FORM_ROLL_KEEP
	ENDC
	ENDC
ENDM
