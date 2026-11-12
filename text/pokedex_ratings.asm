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
	text "Meet me at my LAB"
	line "to get your first"
	cont "#MON."
	done

; below 25%
_DexRatingText_Started::
	text "You still have"
	line "lots to do. Some"
	cont "#MON are best"
	cont "found by trading!"
	done

; 25-49%
_DexRatingText_Quarter::
	text "You're on track!"
	line "Explore the"
	cont "WILD AREAS for"
	cont "rare #MON."
	done

; 50-74%
_DexRatingText_Half::
	text "Wonderful!"
	line "Some #MON can"
	cont "only be found in"
	cont "certain modes."
	done

; 75-89%
_DexRatingText_ThreeQuarters::
	text "Outstanding!"
	line "Regional forms"
	cont "count as entries"
	cont "too."
	done

; 90% up to one short of complete
_DexRatingText_Nearly::
	text "I have nothing"
	line "left to say!"
	cont "You're the"
	cont "authority now!"
	done

; every identity owned
_DexRatingText_Complete::
	text "Your #DEX is"
	line "entirely"
	cont "complete!"
	cont "Congratulations!"
	done
