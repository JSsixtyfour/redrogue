; Pokedex form collection core (2026-11-03, POKEDEX_FORMS_CHECKPOINT_A_2026-11-03.md).
;
; Every Pokedex registration in the game funnels through DexRegisterMon, which
; credits EXACTLY the identity that was caught/seen:
;   - form 0                -> the base species' bit in wPokedexOwned/Seen
;   - a cataloged form      -> its DEX_FORM_* bit in wPokedexFormOwned/Seen
;   - any other form        -> its BASE species (Armored Mewtwo, the fossil
;                              ghosts: not Pokedex entries of their own, but
;                              they credit Mewtwo/Aerodactyl/Kabutops; user
;                              2026-11-03). Same for a selector with no record.
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
	jr c, .formIdentity
	; Not an identity of its own: base species credit. Armored Mewtwo and the
	; fossil ghosts are in the special collection instead, once actually owned.
	bit DEX_REG_OWNED_F, b
	call nz, SpecialCreditForm ; preserves bc, de
	jr .base
.formIdentity
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
;      e = 1          already owned: no page
;      A new non-identity form (Armored Mewtwo...) credited its base species and
;      reports e = 0: it gets the base species' page.
; CLOBBERS: all
; ---------------------------------------------------------------------------
DexRegisterCaught::
	; An optional encounter's package rides in the enemy's own flag byte.
	ld a, [wEnemyMonSpecies2]
	ld b, a
	ld a, [wEnemyMonCatchRate]
	ld c, a
	call SpecialCreditFlags
	ld b, DEX_REG_BOTH
	call DexRegisterEnemy
	ld a, e
	and a
	ret nz                     ; owned before
	ld a, [wEnemyMonSpecies2]
	ld d, a
	call GetEnemySpawnForm     ; e = form 0..3
	ld a, e
	and a
	ret z                      ; e = 0: new base species
	call DexFormIdentity
	ld e, 0
	ret nc                     ; credited as its base species: base page
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
; DexCountCollection: the whole collection's seen and owned totals, base species
; plus form identities. Only real identity bits count: the 4 pad bits after
; NUM_POKEMON (old debug saves set them) and the spare form slots are ignored.
; IN:  none
; OUT: wDexRatingNumMonsSeen / wDexRatingNumMonsOwned = totals, 16-bit BIG-endian
;      (PrintNumber / text_decimal order); de = owned total
; CLOBBERS: all
; ---------------------------------------------------------------------------
DexCountCollection::
	ASSERT NUM_POKEMON <= 255 && NUM_DEX_FORMS <= 255
	ld hl, wPokedexSeen
	ld de, wPokedexFormSeen
	call .total
	ld hl, wDexRatingNumMonsSeen
	ld [hl], b
	inc hl
	ld [hl], c
	ld hl, wPokedexOwned
	ld de, wPokedexFormOwned
	call .total
	ld hl, wDexRatingNumMonsOwned
	ld [hl], b
	inc hl
	ld [hl], c
	ld d, b
	ld e, c
	ret

; hl = base array, de = form array -> bc = set bits in both (identity bits only)
.total
	push de
	ld c, NUM_POKEMON
	call DexCountBits
	pop hl
	push af
	ld c, NUM_DEX_FORMS
	call DexCountBits
	pop bc                     ; b = base count
	add b
	ld c, a
	ld a, 0
	adc a
	ld b, a
	ret

; IN: hl = flag array, c = number of leading bits to count (1-255)
; OUT: a = how many of them are set. CLOBBERS: af, c, de, hl
DexCountBits:
	ld d, 0
.byte
	ld a, [hli]
	ld e, 8
.bit
	srl a
	jr nc, .clear
	inc d
.clear
	dec c
	jr z, .done
	dec e
	jr nz, .bit
	jr .byte
.done
	ld a, d
	ret

; ---------------------------------------------------------------------------
; DexFormKeyOf: identity -> its (species, form) key, for the Forms list/page.
; IN: e = DEX_FORM_* id (< NUM_DEX_FORMS). OUT: d = species, e = form 1..3.
; CLOBBERS: af, hl
; ---------------------------------------------------------------------------
DexFormKeyOf::
	ld d, 0
	ld hl, DexFormKeys
	add hl, de
	add hl, de
	ld a, [hli]
	ld d, a
	ld e, [hl]
	ret

; ---------------------------------------------------------------------------
; DexFormCounts: form identities only (the Forms list header).
; OUT: d = seen, e = owned. CLOBBERS: all
; ---------------------------------------------------------------------------
DexFormCounts::
	ld hl, wPokedexFormSeen
	ld c, NUM_DEX_FORMS
	call DexCountBits
	push af
	ld hl, wPokedexFormOwned
	ld c, NUM_DEX_FORMS
	call DexCountBits
	ld e, a
	pop af
	ld d, a
	ret

; ---------------------------------------------------------------------------
; DexDebugFillForms: debug "complete the Pokedex" for the form arrays. Sets
; exactly the NUM_DEX_FORMS identity bits, never the spare slots.
; CLOBBERS: all
; ---------------------------------------------------------------------------
DexDebugFillForms::
	ld c, 0
.loop
	ld hl, wPokedexFormOwned
	call DexBitAddr
	or [hl]
	ld [hl], a
	ld hl, wPokedexFormSeen
	call DexBitAddr
	or [hl]
	ld [hl], a
	inc c
	ld a, c
	cp NUM_DEX_FORMS
	jr c, .loop
	ret

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
