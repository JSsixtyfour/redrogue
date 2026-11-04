_OldMansHouseBaldingGuyText::
	text "A new trainer!"
	line "me help you on"
	cont "your way."
	prompt

_OldMansHouseBaldingGuyAlreadyGotText::
	text "Come back soon!"
	line "I'll teach you"
	cont "how to catch a"
	cont "#MON"
	done

_OldManGift1Desc::
	text "@"
	text_ram wNameBuffer ; resolved species, filled by BridgePrintGiftDesc
	text_end

_OldManGift2Desc::
	text "@"
	text_ram wNameBuffer ; resolved species, filled by BridgePrintGiftDesc
	text_end

_OldManGift3Desc::
	text "The REST"
	line "Technical Machine"
	done

_OldManGift9Desc::
	text "Get one extra"
	line "copy of an item"
	done

_OldManDuplicateChooseText::
	text "Pick an item to"
	line "duplicate."
	prompt

_OldManDuplicateUnsupportedText::
	text "That item cannot"
	line "hold more copies."
	prompt

_OldManDuplicateFullText::
	text "You already have"
	line "99 of that item!"
	prompt
