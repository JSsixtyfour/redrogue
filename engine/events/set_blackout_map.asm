SetLastBlackoutMap:
; Set the map to return to when
; blacking out or using Teleport or Dig.
; Safari rest houses don't count.

	push hl
	ld hl, SafariZoneRestHouses
	ldh a, [hCurMap]
	ld b, a
.loop
	ld a, [hli]
	cp -1
	jr z, .notresthouse
	cp b
	jr nz, .loop
	jr .done

.notresthouse
	ld a, [wLastMap]
	ld [wLastBlackoutMap], a
.done
	pop hl
	ret

INCLUDE "data/maps/rest_house_maps.asm"
