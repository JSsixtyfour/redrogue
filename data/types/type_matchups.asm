; Type chart, GROUPED BY ATTACKING TYPE (2026-09-29, AI review option 2).
; TypeMatchupScan (engine/battle/core.asm) reads each group's attacker and
; row count, and jumps straight over every other attacker's rows, instead of
; comparing all 82 rows on every lookup (measured ~8k cycles per call before).
; Row order was the Gen 1 interleave; regrouping cannot change a result
; because the scan multiplies (x0, x1/2, x2) and multiplication commutes.
; Each attacker must appear in exactly ONE group: the scan stops at the first
; group that matches.

; Opens a group: the attacking type, then the number of rows before .end_<type>.
MACRO type_group
	db \1
	db (.end_\1 - @ - 1) / 2
ENDM

TypeEffects:
	type_group WATER
;	    defender,     *=
	db FIRE,         SUPER_EFFECTIVE
	db ROCK,         SUPER_EFFECTIVE
	db WATER,        NOT_VERY_EFFECTIVE
	db GRASS,        NOT_VERY_EFFECTIVE
	db GROUND,       SUPER_EFFECTIVE
	db DRAGON,       NOT_VERY_EFFECTIVE
.end_WATER

	type_group FIRE
;	    defender,     *=
	db GRASS,        SUPER_EFFECTIVE
	db ICE,          SUPER_EFFECTIVE
	db FIRE,         NOT_VERY_EFFECTIVE
	db WATER,        NOT_VERY_EFFECTIVE
	db BUG,          SUPER_EFFECTIVE
	db ROCK,         NOT_VERY_EFFECTIVE
	db DRAGON,       NOT_VERY_EFFECTIVE
.end_FIRE

	type_group GRASS
;	    defender,     *=
	db WATER,        SUPER_EFFECTIVE
	db GRASS,        NOT_VERY_EFFECTIVE
	db FIRE,         NOT_VERY_EFFECTIVE
	db GROUND,       SUPER_EFFECTIVE
	db BUG,          NOT_VERY_EFFECTIVE
	db POISON,       NOT_VERY_EFFECTIVE
	db ROCK,         SUPER_EFFECTIVE
	db FLYING,       NOT_VERY_EFFECTIVE
	db DRAGON,       NOT_VERY_EFFECTIVE
.end_GRASS

	type_group ELECTRIC
;	    defender,     *=
	db WATER,        SUPER_EFFECTIVE
	db ELECTRIC,     NOT_VERY_EFFECTIVE
	db GRASS,        NOT_VERY_EFFECTIVE
	db GROUND,       NO_EFFECT
	db FLYING,       SUPER_EFFECTIVE
	db DRAGON,       NOT_VERY_EFFECTIVE
.end_ELECTRIC

	type_group GROUND
;	    defender,     *=
	db FLYING,       NO_EFFECT
	db FIRE,         SUPER_EFFECTIVE
	db ELECTRIC,     SUPER_EFFECTIVE
	db GRASS,        NOT_VERY_EFFECTIVE
	db BUG,          NOT_VERY_EFFECTIVE
	db ROCK,         SUPER_EFFECTIVE
	db POISON,       SUPER_EFFECTIVE
.end_GROUND

	type_group ICE
;	    defender,     *=
	db ICE,          NOT_VERY_EFFECTIVE
	db WATER,        NOT_VERY_EFFECTIVE
	db GRASS,        SUPER_EFFECTIVE
	db GROUND,       SUPER_EFFECTIVE
	db FLYING,       SUPER_EFFECTIVE
	db DRAGON,       SUPER_EFFECTIVE
.end_ICE

	type_group PSYCHIC_TYPE
;	    defender,     *=
	db PSYCHIC_TYPE, NOT_VERY_EFFECTIVE
	db FIGHTING,     SUPER_EFFECTIVE
	db POISON,       SUPER_EFFECTIVE
.end_PSYCHIC_TYPE

	type_group NORMAL
;	    defender,     *=
	db ROCK,         NOT_VERY_EFFECTIVE
	db GHOST,        NO_EFFECT
.end_NORMAL

	type_group GHOST
;	    defender,     *=
	db GHOST,        SUPER_EFFECTIVE
	db NORMAL,       NO_EFFECT
	db PSYCHIC_TYPE, SUPER_EFFECTIVE
.end_GHOST

	type_group FIGHTING
;	    defender,     *=
	db NORMAL,       SUPER_EFFECTIVE
	db POISON,       NOT_VERY_EFFECTIVE
	db FLYING,       NOT_VERY_EFFECTIVE
	db PSYCHIC_TYPE, NOT_VERY_EFFECTIVE
	db BUG,          NOT_VERY_EFFECTIVE
	db ROCK,         SUPER_EFFECTIVE
	db ICE,          SUPER_EFFECTIVE
	db GHOST,        NO_EFFECT
.end_FIGHTING

	type_group POISON
;	    defender,     *=
	db GRASS,        SUPER_EFFECTIVE
	db POISON,       NOT_VERY_EFFECTIVE
	db GROUND,       NOT_VERY_EFFECTIVE
	db BUG,          SUPER_EFFECTIVE
	db ROCK,         NOT_VERY_EFFECTIVE
	db GHOST,        NOT_VERY_EFFECTIVE
.end_POISON

	type_group FLYING
;	    defender,     *=
	db ELECTRIC,     NOT_VERY_EFFECTIVE
	db FIGHTING,     SUPER_EFFECTIVE
	db BUG,          SUPER_EFFECTIVE
	db GRASS,        SUPER_EFFECTIVE
	db ROCK,         NOT_VERY_EFFECTIVE
.end_FLYING

	type_group BUG
;	    defender,     *=
	db FIRE,         NOT_VERY_EFFECTIVE
	db GRASS,        SUPER_EFFECTIVE
	db FIGHTING,     NOT_VERY_EFFECTIVE
	db FLYING,       NOT_VERY_EFFECTIVE
	db PSYCHIC_TYPE, SUPER_EFFECTIVE
	db GHOST,        NOT_VERY_EFFECTIVE
	db POISON,       SUPER_EFFECTIVE
.end_BUG

	type_group ROCK
;	    defender,     *=
	db FIRE,         SUPER_EFFECTIVE
	db FIGHTING,     NOT_VERY_EFFECTIVE
	db GROUND,       NOT_VERY_EFFECTIVE
	db FLYING,       SUPER_EFFECTIVE
	db BUG,          SUPER_EFFECTIVE
	db ICE,          SUPER_EFFECTIVE
.end_ROCK

	type_group DRAGON
;	    defender,     *=
	db DRAGON,       SUPER_EFFECTIVE
.end_DRAGON

	db -1 ; end
