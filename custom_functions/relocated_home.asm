; custom_functions/relocated_home.asm
;
; Vanilla HOME routines relocated to ROMX to reclaim ROM0/HOME space for the
; procedural-cave merge (master's HOME bank was ~full; the procedural load hooks
; need ~26 bytes there). Each routine here is a self-contained leaf whose only
; cross-references are to HOME (always-mapped) targets, so it runs correctly from
; any bank; each HOME call site is converted to farcall.

SECTION "Relocated HOME Routines", ROMX

; Moved from home/overworld.asm. Ends in `jp AdvancePlayerSprite` (HOME target,
; always mapped -> safe from ROMX). Both callers in EnterMap's movement path are
; converted to farcall (the conditional one via jr z + farcall).
DoBikeSpeedup::
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	ldh a, [hCurMap]
	cp ROUTE_17 ; Cycling Road
	jr nz, .goFaster
	ldh a, [hJoyHeld]
	and PAD_UP | PAD_LEFT | PAD_RIGHT
	ret nz
.goFaster
	jp AdvancePlayerSprite
