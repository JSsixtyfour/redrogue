; [wCurSpecies] = pokemon ID
; hl = dest addr
PrintMonType:
	call GetPredefRegisters
	push hl
	call GetMonHeader
	; Fusion (Phase 3): if wLoadedMon (the mon on the status screen) is the
	; fusion, override the just-loaded wMonHType2 with the secondary's type,
	; which an earlier feature (CreateFusion, custom_functions/func_fusion.asm)
	; baked into the primary's own MON_TYPE2 field at fusion-creation time -
	; read it back here rather than re-deriving it. de = struct base is
	; IsFusionMon's input (NOT hl - farcall clobbers hl as its own jump
	; vector; see IsFusionMon's doc comment in custom_functions/func_fusion.asm).
	; CAVEAT (documented, not a bug to fix): this function is ALSO called from
	; Hall of Fame display (engine/movie/hall_of_fame.asm), which does NOT use
	; wLoadedMon (it sets wCurSpecies from wHoFMonSpecies directly) - wLoadedMon
	; there is just stale leftover from whatever status screen was last viewed.
	; This check could theoretically misfire only if wLoadedMon happens to (a)
	; be flagged as fusion AND (b) hold the exact same species currently shown
	; in the Hall of Fame - a narrow, cosmetic-only edge case, accepted rather
	; than spending a scarce WRAM/HRAM byte on a dedicated context flag (both
	; regions were completely full as of the prior fusion stats work).
	ld de, wLoadedMon
	farcall IsFusionMon
	jr z, .notFusionForType
	ld a, [wLoadedMon + MON_TYPE2]
	ld [wMonHType2], a
.notFusionForType
	pop hl
	push hl
	ld a, [wMonHType1]
	call PrintType
	ld a, [wMonHType1]
	ld b, a
	ld a, [wMonHType2]
	cp b
	pop hl
	jr z, EraseType2Text
	ld bc, SCREEN_WIDTH * 2
	add hl, bc

; a = type
; hl = dest addr
PrintType:
	push hl
	jr PrintType_

; erase "TYPE2/" if the mon only has 1 type
EraseType2Text:
	ld a, ' '
	ld bc, $13
	add hl, bc
	ld bc, $6
	jp FillMemory

PrintMoveType:
	call GetPredefRegisters
	push hl
	ld a, [wPlayerMoveType]
; fall through

PrintType_:
	add a
	ld hl, TypeNames
	ld e, a
	ld d, $0
	add hl, de
	ld a, [hli]
	ld e, a
	ld d, [hl]
	pop hl
	jp PlaceString

INCLUDE "data/types/names.asm"
