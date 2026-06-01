UpdateSprites::
	ldh a, [hUpdateSpritesEnabled]
	dec a
	ret nz
	homecall _UpdateSprites
	ret
