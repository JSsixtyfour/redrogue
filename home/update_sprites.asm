UpdateSprites::
	ldh a, [hUpdateSpritesEnabled]
	dec a
	ret nz
	homecall _UpdateSprites
	ret

; predef LearnMove for a caller with the map on screen: the forget-move box then
; hides the sprites it covers (see BIT_LEARN_MOVE_HIDES_SPRITES in LearnMove).
; OUT: b = 1 if the move was learned. Clobbers everything else.
LearnMoveOverMap::
	ld hl, wStatusFlags7
	set BIT_LEARN_MOVE_HIDES_SPRITES, [hl]
	predef LearnMove
	ld hl, wStatusFlags7
	res BIT_LEARN_MOVE_HIDES_SPRITES, [hl]
	ret
