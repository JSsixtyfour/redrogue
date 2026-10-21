; Move-effect dispatch tables for the AI layers (Phase 6, 2026-10-21 AI review).
;
; The layers used to find a move's handler with IsInArray over (effect, pointer)
; rows: about 60 cycles per row, and an ordinary attack, which has no handler,
; walked the whole table before missing. Measured 22-34k cycles of a 175-215k
; T3 decision. These macros keep the readable one-row-per-effect source and
; build, at assembly time:
;   <Name>Index:    one byte per effect id 0..NUM_MOVE_EFFECTS, 0 = no handler,
;                   else a 1-based index into <Name>Handlers
;   <Name>Handlers: one dw per DISTINCT handler or value (one shared by many
;                   effects, like the stat-down one, is stored once)
; Look up with AIDispatchLookup (engine/battle/ai/ai_score_helpers.asm).
;
;	ai_dispatch_begin AIRedundantEffect
;	ai_dispatch ATTACK_DOWN1_EFFECT, AIRedundant_StatDown
;	...
;	ai_dispatch_end
; A second row for the same effect is an assembly error, not a silent shadow.

MACRO ai_dispatch_begin
	DEF AI_DISPATCH_NAME EQUS "\1"
	DEF AI_DISPATCH_COUNT = 0
ENDM

MACRO ai_dispatch
	ASSERT (\1) <= NUM_MOVE_EFFECTS, "ai_dispatch: effect \1 is past NUM_MOVE_EFFECTS"
	ASSERT !DEF({AI_DISPATCH_NAME}_EFF_{d:\1}), "ai_dispatch: a second row for \1"
	IF !DEF({AI_DISPATCH_NAME}_IDX_\2)
		DEF AI_DISPATCH_COUNT += 1
		DEF {AI_DISPATCH_NAME}_IDX_\2 EQU AI_DISPATCH_COUNT
		DEF {AI_DISPATCH_NAME}_HANDLER_{d:AI_DISPATCH_COUNT} EQUS "\2"
	ENDC
	DEF {AI_DISPATCH_NAME}_EFF_{d:\1} EQU {AI_DISPATCH_NAME}_IDX_\2
ENDM

; A table of constant WORDS by effect rather than handlers (AIMoveClass, the
; plan classes): ai_dispatch_begin, then ai_effect_value rows, then
; ai_dispatch_end. Rows deduplicate by value, since a value may be an
; expression like `AICLASS_DRAIN | AICLASS_DAMAGE`; handler labels cannot be
; compared at assembly time, so ai_dispatch rows deduplicate by name instead.
MACRO ai_effect_value
	ASSERT (\1) <= NUM_MOVE_EFFECTS, "ai_effect_value: effect \1 is past NUM_MOVE_EFFECTS"
	ASSERT !DEF({AI_DISPATCH_NAME}_EFF_{d:\1}), "ai_effect_value: a second row for \1"
	DEF AI_DISPATCH_FOUND = 0
	FOR AI_DISPATCH_I, 1, AI_DISPATCH_COUNT + 1
		IF {AI_DISPATCH_NAME}_HANDLER_{d:AI_DISPATCH_I} == (\2)
			DEF AI_DISPATCH_FOUND = AI_DISPATCH_I
		ENDC
	ENDR
	IF AI_DISPATCH_FOUND == 0
		DEF AI_DISPATCH_COUNT += 1
		DEF {AI_DISPATCH_NAME}_HANDLER_{d:AI_DISPATCH_COUNT} EQU \2
		DEF AI_DISPATCH_FOUND = AI_DISPATCH_COUNT
	ENDC
	DEF {AI_DISPATCH_NAME}_EFF_{d:\1} EQU AI_DISPATCH_FOUND
ENDM

MACRO ai_dispatch_end
	ASSERT AI_DISPATCH_COUNT < 128, "ai_dispatch: AIDispatchLookup doubles the index in one byte"
{AI_DISPATCH_NAME}Index:
	FOR AI_DISPATCH_EFF, NUM_MOVE_EFFECTS + 1
		IF DEF({AI_DISPATCH_NAME}_EFF_{d:AI_DISPATCH_EFF})
			db {AI_DISPATCH_NAME}_EFF_{d:AI_DISPATCH_EFF}
		ELSE
			db 0
		ENDC
	ENDR
{AI_DISPATCH_NAME}Handlers:
	FOR AI_DISPATCH_I, 1, AI_DISPATCH_COUNT + 1
		dw {AI_DISPATCH_NAME}_HANDLER_{d:AI_DISPATCH_I}
	ENDR
	PURGE AI_DISPATCH_NAME, AI_DISPATCH_COUNT
ENDM
