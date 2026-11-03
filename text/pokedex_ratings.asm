; Prof. Oak's Pokedex rating (engine/events/pokedex_rating.asm). 2026-11-03:
; whole-collection totals (base species + forms) and seven percentage bands.
; Every rendered line is at most 17 tiles ('#' is the 4-tile "POKé").

_DexCompletionText::
	text "#DEX comp-"
	line "letion is:"

	para "@"
	text_decimal wDexRatingNumMonsSeen, 2, 3
	text " #MON seen"
	line "@"
	text_decimal wDexRatingNumMonsOwned, 2, 3
	text " #MON owned"
	cont "out of {d:NUM_DEX_IDENTITIES} total."

	para "PROF.OAK's"
	line "Rating:"
	prompt

; owned = 0
_DexRatingText_None::
	text "Your #DEX is"
	line "still empty!"
	cont "Catch #MON on"
	cont "your next run!"
	done

; below 25%
_DexRatingText_Started::
	text "A fine start!"
	line "Every run brings"
	cont "new #MON to"
	cont "discover."
	done

; 25-49%
_DexRatingText_Quarter::
	text "Good progress!"
	line "Explore caves and"
	cont "forests to find"
	cont "rarer #MON!"
	done

; 50-74%
_DexRatingText_Half::
	text "Over halfway!"
	line "Evolving your"
	cont "#MON fills in"
	cont "new entries too!"
	done

; 75-89%
_DexRatingText_ThreeQuarters::
	text "Wonderful work!"
	line "Regional forms"
	cont "are entries of"
	cont "their own, too!"
	done

; 90% up to one short of complete
_DexRatingText_Nearly::
	text "Incredible! Only"
	line "a handful of"
	cont "#MON remain"
	cont "undiscovered!"
	done

; every identity owned
_DexRatingText_Complete::
	text "Your #DEX is"
	line "fully complete!"
	cont "Congratulations!"
	done
