; Pokédex flavour text, part 2 - every species added by Species Groups Phase 2.
;
; At 101 new species the combined dex text reaches ~22,000 bytes, which exceeds a
; single 16 KiB bank, so it HAS to be split. Splitting is safe here and nowhere
; else in the species data: dex entries reach their text through `text_far`,
; which is bank-aware, whereas the pointer tables elsewhere (EvosMovesPointerTable,
; PokedexEntryPointers) are bare 16-bit `dw` and must stay in one bank with the
; data they address.
;
; Everything in this file lives in SECTION "Pokédex Text 2" (see text.asm).
; Append new species here, not to dex_text.asm.

_ChikoritaDexEntry::
	text "A sweet aroma"
	next "gently wafts from"
	next "the leaf on its"

	page "head. It loves to"
	next "soak up the sun's"
	next "warm rays"
	dex

_BayleefDexEntry::
	text "The scent that"
	next "wafts from the"
	next "leaves round its"

	page "neck has a spicy,"
	next "stimulating"
	next "effect"
	dex

_MeganiumDexEntry::
	text "The aroma that"
	next "rises from its"
	next "petals soothes"

	page "the feelings of"
	next "people locked in"
	next "battle"
	dex
