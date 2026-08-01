; Special-form / type-variant system (Bridge System, Phase B3).
;
; Mirrors func_ghost_variant.asm / func_fusion.asm exactly: two more per-mon
; flags live in the otherwise-dead MON_CATCH_RATE byte, so they survive box
; deposits, trades, battle-loading and saves for free (the shared struct
; layout carries them). No new WRAM is used - the type of a variant is stored
; in the mon's own MON_TYPE2 field, and the special-form capabilities are a
; ROM table keyed on species.
;
;   bit 0 = ghost variant   (func_ghost_variant.asm)
;   bit 1 = fusion          (func_fusion.asm)
;   bit 2 = type variant    (this file)  -- one bit for ALL secondary-type
;                                           re-skins; the actual type is read
;                                           back from the mon's stored MON_TYPE2
;   bit 3 = special form    (this file)  -- one bit; the actual capability set
;                                           is looked up per-species in
;                                           SpecialFormCaps below
;
; All three catch-rate flag bits are cleared at the same three mon-creation
; copy sites as ghost/fusion (add_mon.asm + the two enemy/box copies in
; battle/core.asm) so no species spawns pre-flagged by coincidence.

DEF BIT_TYPE_VARIANT EQU 2 ; bit within MON_CATCH_RATE
DEF BIT_SPECIAL_FORM EQU 3 ; bit within MON_CATCH_RATE

; capability bits returned by GetSpecialFormCaps (a bitfield)
DEF SF_DOUBLE_ATK  EQU 0 ; double the physical offensive stat (Thick Club)
DEF SF_DOUBLE_SPC  EQU 1 ; double the special offensive stat  (Light Ball)
DEF SF_NO_EVOLVE   EQU 2 ; refuse every evolution path (Light Ball)
DEF SF_NEVER_MISS  EQU 3 ; attacker's moves never miss        (No Guard)
DEF SF_ALWAYS_HIT  EQU 4 ; moves against this mon never miss   (No Guard)
DEF SF_ALWAYS_CRIT EQU 5 ; attacker's moves always crit

; ---------------------------------------------------------------------------
; ApplyTypeVariant
; Flags the mon at de as a type variant and stores its new secondary type.
; The status-screen type override and the battle/status palettes are all
; derived from that stored MON_TYPE2 (see the hooks in print_type.asm /
; palettes.asm), so this one call is all a gift routine needs.
; INPUT:  de = struct base (MON_SPECIES field), a = secondary type (WATER/ROCK)
; CLOBBERS: af, hl  (de preserved)
; ---------------------------------------------------------------------------
ApplyTypeVariant::
	push af
	ld hl, MON_CATCH_RATE
	add hl, de
	set BIT_TYPE_VARIANT, [hl]
	ld hl, MON_TYPE2
	add hl, de
	pop af
	ld [hl], a
	ret

; ---------------------------------------------------------------------------
; IsTypeVariant
; INPUT:  de = struct base
; OUTPUT: Z set = not a type variant, Z clear = is one
; CLOBBERS: af, hl  (de preserved)  -- de-input for the same farcall-clobbers-hl
; reason documented at length in IsFusionMon (func_fusion.asm).
; ---------------------------------------------------------------------------
IsTypeVariant::
	ld hl, MON_CATCH_RATE
	add hl, de
	bit BIT_TYPE_VARIANT, [hl]
	ret

; ---------------------------------------------------------------------------
; GetTypeVariantPalette
; INPUT:  de = struct base
; OUTPUT: a = 0 if NOT a type variant; otherwise the palette id to use,
;         derived from the stored MON_TYPE2 (WATER->blue, ROCK->gray,
;         anything else defaults to blue but still counts as a variant).
;         Callers test `and a / jr z` to skip.
; CLOBBERS: af, hl  (de preserved)
; ---------------------------------------------------------------------------
GetTypeVariantPalette::
	ld hl, MON_CATCH_RATE
	add hl, de
	bit BIT_TYPE_VARIANT, [hl]
	jr nz, .variant
	xor a
	ret
.variant
	ld hl, MON_TYPE2
	add hl, de
	ld a, [hl]
	cp ROCK
	jr z, .rock
	ld a, PAL_BLUEMON ; WATER and any future secondary type -> blue
	ret
.rock
	ld a, PAL_GRAYMON
	ret

; ---------------------------------------------------------------------------
; ApplySpecialForm
; Flags the mon at de as a special form. Its actual capabilities are looked
; up per-species (SpecialFormCaps), so nothing species-specific is stored -
; the gift routine just picks the right species and sets this one flag.
; INPUT:  de = struct base
; CLOBBERS: f, hl  (a, de preserved)
; ---------------------------------------------------------------------------
ApplySpecialForm::
	ld hl, MON_CATCH_RATE
	add hl, de
	set BIT_SPECIAL_FORM, [hl]
	ret

; ---------------------------------------------------------------------------
; GetSpecialFormCaps
; INPUT:  de = struct base
; OUTPUT: a = capability bitfield (SF_* bits), or 0 if the mon is not a
;         special form (or its species has no table entry).
; CLOBBERS: af, hl  (bc, de preserved)
; ---------------------------------------------------------------------------
GetSpecialFormCaps::
	ld hl, MON_CATCH_RATE
	add hl, de
	bit BIT_SPECIAL_FORM, [hl]
	jr z, .none
	ld a, [de]        ; a = species (MON_SPECIES is the struct base)
	push bc
	ld c, a
	ld hl, SpecialFormCaps
.loop
	ld a, [hli]       ; species id from table
	and a
	jr z, .notFound   ; 0 terminator
	cp c
	ld a, [hli]       ; caps byte (advance past it either way)
	jr z, .foundPop
	jr .loop
.foundPop
	pop bc
	ret
.notFound
	pop bc
.none
	xor a
	ret

; species (internal id) -> capability bitfield. Terminated by a 0 species.
SpecialFormCaps:
	db CUBONE,    1 << SF_DOUBLE_ATK
	db MAROWAK,   1 << SF_DOUBLE_ATK
	db PIKACHU,   (1 << SF_DOUBLE_ATK) | (1 << SF_DOUBLE_SPC) | (1 << SF_NO_EVOLVE)
	db MACHOP,    (1 << SF_NEVER_MISS) | (1 << SF_ALWAYS_HIT)
	db FARFETCHD, 1 << SF_ALWAYS_CRIT
	db 0 ; terminator
