; Pokedex form collection core (2026-11-03, POKEDEX_FORMS_CHECKPOINT_A_2026-11-03.md).
;
; Every Pokedex registration in the game funnels through DexRegisterMon, which
; credits EXACTLY the identity that was caught/seen:
;   - form 0                -> the base species' bit in wPokedexOwned/Seen
;   - a cataloged form      -> its DEX_FORM_* bit in wPokedexFormOwned/Seen
;   - any other form record -> nothing (Armored Mewtwo, the fossil ghosts: not
;                              Pokedex entries by design, user 2026-11-03)
; Owning Alolan Meowth therefore never credits ordinary Meowth, and vice versa.
;
; Pinned to bank $30 beside "Species Forms" (layout.link) so GetEnemySpawnForm
; is a plain call. All entry points are reached by farcall: inputs ride in d/e,
; the result rides back in e (Bankswitch clobbers a/b/c/h/l on the way).

	ASSERT (DEX_REG_BOTH & FORM_MASK) == 0, "DEX_REG_* bits overlap FORM_MASK"
	ASSERT BANK(DexRegisterMon) == BANK(GetEnemySpawnForm), \
	       "Dex Forms must share a bank with Species Forms (plain calls)"

; ---------------------------------------------------------------------------
; DexRegisterMon
; IN:  d = species (internal id)
;      e = form in FORM_MASK position (bits 5-6) | DEX_REG_OWNED / DEX_REG_SEEN
; OUT: e = 0             the identity was NOT owned before this call
;      e = 1             it was already owned
;      e = $FF           (species, form) is not a Pokedex identity; nothing set
;      Newly owned forms are reported as 0 like base species; a caller that must
;      tell them apart (the catch page) uses DexRegisterCaught.
; CLOBBERS: all
; Side effect: the base path leaves the Pokedex number in wPokedexNum, exactly
; as the inline code this replaced did.
; ---------------------------------------------------------------------------
DexRegisterMon::
	ld a, e
	and DEX_REG_BOTH
	ld b, a                    ; b = actions, survives to .apply
	ld a, e
	and FORM_MASK
	jr z, .base
	rlca                       ; bits 5-6 -> 0..3 (inverse of the 3x rrca encode)
	rlca
	rlca
	ld e, a
	call DexFormIdentity       ; preserves b
	jr nc, .notIdentity
	ld c, a
	ld hl, wPokedexFormOwned
	ld de, wPokedexFormSeen
	jr .apply

.base
	ld a, d
	ld [wPokedexNum], a
	push bc
	predef IndexToPokedex
	pop bc
	ld a, [wPokedexNum]
	dec a
	ld c, a
	ld hl, wPokedexOwned
	ld de, wPokedexSeen
	; fall through

; b = actions, c = bit index, hl = owned array, de = seen array
.apply
	push de
	call DexBitAddr            ; hl -> byte, a = mask; preserves b, c, d
	ld e, a
	and [hl]
	ld d, a                    ; d = previous owned bit (nonzero = owned)
	bit DEX_REG_OWNED_F, b
	jr z, .seen
	ld a, e
	or [hl]
	ld [hl], a
.seen
	pop hl
	bit DEX_REG_SEEN_F, b
	jr z, .done
	call DexBitAddr
	or [hl]
	ld [hl], a
.done
	ld e, 0
	ld a, d
	and a
	ret z
	inc e
	ret

.notIdentity
	ld e, $FF
	ret

; ---------------------------------------------------------------------------
; DexRegisterEnemySeen: the battle's "this enemy is now seen" registration
; (LoadEnemyMonData). Resolves the enemy's form itself, so Battle Core pays
; only the farcall. IN: none. OUT/CLOBBERS: as DexRegisterMon.
; ---------------------------------------------------------------------------
DexRegisterEnemySeen::
	ld b, DEX_REG_SEEN
	jr DexRegisterEnemy

; ---------------------------------------------------------------------------
; DexRegisterCaught: a ball just caught the wild enemy (ItemUseBall). Sets
; owned + seen for its exact identity.
; IN:  none
; OUT: e = 0          new base species: show its Pokedex page
;      e = $80 | id   new form identity id (no form page yet: the caller skips)
;      e = 1 / $FF    already owned / not an identity: no page
; CLOBBERS: all
; ---------------------------------------------------------------------------
DexRegisterCaught::
	ld b, DEX_REG_BOTH
	call DexRegisterEnemy
	ld a, e
	and a
	ret nz                     ; owned before, or not an identity
	ld a, [wEnemyMonSpecies2]
	ld d, a
	call GetEnemySpawnForm     ; e = form 0..3
	ld a, e
	and a
	ret z                      ; e = 0: new base species
	call DexFormIdentity       ; it registered, so it is cataloged
	or $80
	ld e, a
	ret

; b = DEX_REG_* actions. Clobbers all; result as DexRegisterMon.
DexRegisterEnemy:
	push bc
	call GetEnemySpawnForm     ; e = form 0..3; clobbers af, bc, hl
	pop bc
	ld a, e
	rrca                       ; 0..3 -> bits 5-6
	rrca
	rrca
	or b
	ld e, a
	ld a, [wEnemyMonSpecies2]
	ld d, a
	jp DexRegisterMon

; ---------------------------------------------------------------------------
; DexFormIdentity
; IN:  d = species, e = form index 1..3
; OUT: carry set, a = DEX_FORM_* id when (d, e) is cataloged; carry clear if not
; CLOBBERS: af, c, hl   (b, d, e preserved)
; ---------------------------------------------------------------------------
DexFormIdentity::
	ld hl, DexFormKeys
	ld c, 0
.loop
	ld a, [hli]
	and a                      ; 0 terminator; clears carry
	ret z
	cp d
	ld a, [hli]
	jr nz, .next
	cp e
	jr z, .found
.next
	inc c
	jr .loop
.found
	ld a, c
	scf
	ret

; IN: hl = flag array, c = bit index. OUT: hl -> the byte, a = the bit's mask.
; CLOBBERS: af, e, hl   (b, c, d preserved)
DexBitAddr:
	ld a, c
	srl a
	srl a
	srl a
	add l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	ld a, c
	and 7
	ld e, a
	inc e
	ld a, 1
.shift
	dec e
	ret z
	add a
	jr .shift

INCLUDE "data/pokemon/dex_forms.asm"
