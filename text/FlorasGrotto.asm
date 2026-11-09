_FlorasGrottoFloraText::
	text "I'm FLORA, the"
	line "keeper of this"
	cont "grove."

	para "May I offer some"
	line "of its plenty?"
	prompt

_FlorasGrottoFloraAlreadyGotText::
	text "May sun shine down"
	line "upon you!"
	done

_FloraGift2Desc::
	text "@"
	text_ram wNameBuffer ; resolved species, filled by BridgePrintGiftDesc
	text " with"
	line "SPORE"
	done

_FloraGift3Desc::
	text "Evolves certain"
	line "#MON!"
	done
