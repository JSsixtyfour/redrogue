_CinnabarLabFossilRoomScientist1Text::
	text "Hiya!"

	para "I am important"
	line "doctor!"

	para "I study here rare"
	line "#MON fossils!"

	para "Here, sample our"
	line "research!"
	prompt

_CinnabarLabFossilRoomScientist1NoFossilsText::
	text "No! Is too bad!"
	done

_CinnabarLabFossilRoomScientist1GoForAWalkText::
	text "I take a little"
	line "time!"

	para "You go for walk a"
	line "little while!"
	done

_CinnabarLabFossilRoomScientist1FossilIsBackToLifeText::
	text "Where were you?"

	para "Your fossil is"
	line "back to life!"

	para "It was @"
	text_ram wStringBuffer
	text_start
	line "like I think!"
	prompt

_CinnabarLabFossilRoomScientist1SeesFossilText::
	text "Oh! That is"
	line "@"
	text_ram wNameBuffer
	text "!"

	para "It is fossil of"
	line "@"
	text_ram wStringBuffer
	text ", a"
	cont "#MON that is"
	cont "already extinct!"

	para "My Resurrection"
	line "Machine will make"
	cont "that #MON live"
	cont "again!"
	done

_CinnabarLabFossilRoomScientist1TakesFossilText::
	text "So! You hurry and"
	line "give me that!"

	para "<PLAYER> handed"
	line "over @"
	text_ram wNameBuffer
	text "!"
	prompt

_CinnabarLabFossilRoomScientist1GoForAWalkText2::
	text "I take a little"
	line "time!"

	para "You go for walk a"
	line "little while!"
	done

_CinnabarLabFossilRoomScientist1ComeAgainText::
	text "Aiyah! You come"
	line "again!"
	done

_FossilGift1Desc::
	text "Revived from a"
	line "HELIX FOSSIL!"
	done

_FossilGift2Desc::
	text "Gives one #MON"
	line "the ROCK type!"
	done

_FossilGift3Desc::
	text "Evolves certain"
	line "#MON!"
	done
    
_FossilGift4Desc::
    text "Revived from a"
	line "DOME FOSSIL!"
	done
    
_FossilGift5Desc::
    text "Revived from an"
	line "OLD AMBER!"
	done

_FossilGift6Desc::
    text "Created in this"
	line "laboratory!"
	done

_FossilGift7Desc::
    text "Does a random"
	line "attack!"
	done

_CinnabarLabFossilRoomScientist2Text::
	text "I rode my PONYTA"
	line "to work today!"
	done
