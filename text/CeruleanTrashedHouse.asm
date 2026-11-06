_CeruleanTrashedHouseFishingGuruTheyStoleATMText::
	text "Stay safe out"
	line "there, <PLAYER>!"
	done

_CeruleanTrashedHouseFishingGuruWhatsLostIsLostText::
	text "These poor people"
	line "here were robbed."

	para "We're positive"
	line "that TEAM ROCKET"
	cont "is behind this"
	cont "terrible deed."

	para "Even our POLICE"
	line "FORCE has trouble"
	cont "with the ROCKETs!"
    
    para "Oh? You'd like to"
	line "help us? Here,"
	cont "take this..."
	prompt

_CeruleanTrashedHouseGirlText::
	text "TEAM ROCKET must"
	line "be trying to DIG"
	cont "their way into no"
	cont "good!"
	done

_CeruleanTrashedHouseWallHoleText::
	text "TEAM ROCKET left"
	line "a way out!"
	done

_TrashedGift1Desc::
	text "Restores 80 HP"
	done

_TrashedGift2Desc::
	text "A gift"
	line "@"
	text_ram wNameBuffer ; resolved species, filled by BridgePrintGiftDesc
	text_end

_TrashedGift3Desc::
	text "The BODY SLAM"
	line "Technical Machine"
	done
