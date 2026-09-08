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

_WeavileDexEntry::
	text "It works with"
	next "others to corner"
	next "prey, then shreds"

	page "it with its sharp,"
	next "claw-like feathers"
	next "in an instant"
	dex

_MamoswineDexEntry::
	text "Thick fur and"
	next "a coat of fat"
	next "keep it warm in"

	page "any climate. It"
	next "roams in herds"
	next "across the snow"
	dex

_MismagiusDexEntry::
	text "Said to cast"
	next "spells that make"
	next "the afflicted"

	page "hear only"
	next "unpleasant,"
	next "eerie sounds"
	dex

_CyndaquilDexEntry::
	text "The flames that"
	next "burst from its"
	next "back are proof"

	page "of its rage. It"
	next "is timid, and"
	next "always curls up"
	dex

_QuilavaDexEntry::
	text "If it stands"
	next "on its hind legs,"
	next "it can spray"

	page "flames from its"
	next "back for even"
	next "greater power"
	dex

_TyphlosionDexEntry::
	text "It shrouds"
	next "itself in a"
	next "heat haze as it"

	page "storms toward"
	next "foes, leaving"
	next "nothing behind"
	dex

_TotodileDexEntry::
	text "Despite its"
	next "small body, its"
	next "jagged jaws are"

	page "very powerful."
	next "It won't let go"
	next "once it bites"
	dex

_CroconawDexEntry::
	text "Once it bites"
	next "down, it will"
	next "not let go until"

	page "its target loses"
	next "consciousness."
	next "It has sharp fangs"
	dex

_FeraligatrDexEntry::
	text "It swings its"
	next "great jaws wide"
	next "to intimidate"

	page "enemies. It attacks"
	next "with amazing"
	next "speed and power"
	dex

_SentretDexEntry::
	text "Stands on its"
	next "tail and looks"
	next "all around itself"

	page "constantly. If it"
	next "senses danger, it"
	next "flees at once"
	dex

_FurretDexEntry::
	text "It is very"
	next "slender so it"
	next "can slip through"

	page "narrow spaces"
	next "without difficulty,"
	next "even underground"
	dex

_HoothootDexEntry::
	text "It always"
	next "stands on one leg,"
	next "even while it"

	page "sleeps. It starts"
	next "tilting its head"
	next "at sundown"
	dex

_NoctowlDexEntry::
	text "It can rotate"
	next "its head 180"
	next "degrees. It flies"

	page "silently and is"
	next "a great hunter"
	next "in the dark"
	dex
