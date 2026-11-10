_OaksLabRivalIPickedTheWrongPokemonText::
	text "Get your"
	line "reward in the"
	cont "next room."

	para "You'll need it to"
	line "keep pace with"
	cont "me."
	prompt

_OaksLabRivalAmIGreatOrWhatText::
	text "<RIVAL>: Take my"
	line "prize in the next"
	cont "room. You're going"
	cont "to need it!"
	prompt
    
_OaksLabRivalSmellYouLaterText::
	text "<RIVAL>: Okay!"
	line "I'll make my"
	cont "#MON fight to"
	cont "toughen it up!"

	para "<PLAYER>! Gramps!"
	line "Smell you later!"
	done
    
_OaksLabOakDontGoAwayYetText::
	text "OAK: Hey! Don't go"
	line "that way!"
	done

_OaksLabOakSelectMonText::
	text "OAK: Hey! Choose"
	line "a #MON first!"
	done

_NoTurningBack::
	text "OAK: Hey!"
	line "There's no turning"
	cont "back now!"
	done
    
_OaksLabRivalIllTakeThisOneText::
	text "<RIVAL>: I'll take"
	line "this one, then!"
	done
    
_OaksLabRivalReceivedMonText::
	text "<RIVAL> received"
	line "a @"
	text_ram wNameBuffer
	text "!@"
	text_end
    
_OaksLabRivalIllTakeYouOnText::
	text "<RIVAL>: Wait"
	line "<PLAYER>!"
	cont "Let's check out"
	cont "our #MON!"

	para "Come on, I'll take"
	line "you on!"
	done
    
_OaksLabRivalGrampsIsntAroundText::
	text "<RIVAL>: Yo"
	line "<PLAYER>! Gramps"
	cont "isn't around!"
	done

_OaksLabRivalThanksText::
	text "<RIVAL>: Thanks"
	line "for saving the"
	cont "best one for me"
	done

_OaksLabRivalImpatientText::
	text "<RIVAL>: Hey!"
	line "Gramps! What"
	cont "about me?"
	done

_OaksLabOakChooseMonText::
	text "OAK: Now, <PLAYER>,"
	line "which #MON do"
	cont "you want?"
	done

_OaksLabOakGoodLuckText::
	text "OAK: <PLAYER>,"
	line "raise your young"
	cont "#MON by making"
	cont "it fight!"
	done

_OaksLabGirlText::
	text "PROF.OAK is the"
	line "authority on"
	cont "#MON!"

	para "Many #MON"
	line "trainers hold him"
	cont "in high regard!"
	done

_OaksLabScientistText::
	text "I study #MON as"
	line "PROF.OAK's AIDE."
	done

_OaksLabOakGiftIntroText::
	text "OAK: <PLAYER>!"
	line "I have something"
	cont "special for you."
	prompt

_OaksLabOakAlreadyGotText::
	text "OAK: Come see me"
	line "sometimes."

	para "I want to know how"
	line "your #DEX is"
	cont "coming along."
	done

_OaksLabOakNormalText::
	text "OAK: There's a"
	line "time and place"
	cont "for everything!"

	para "But not now."
	done

_OaksLabGift1Desc::
	text "@"
	text_ram wNameBuffer ; resolved species, filled by BridgePrintGiftDesc
	text " with"
	line "EARTHQUAKE"
	done

_OaksLabGift2Desc::
	text "@"
	text_ram wNameBuffer ; resolved species, filled by BridgePrintGiftDesc
	text " with"
	line "AMNESIA"
	done

_OaksLabGift3Desc::
	text "@"
	text_ram wNameBuffer ; resolved species, filled by BridgePrintGiftDesc
	text " with"
	line "DRAGON type"
	done

_OaksLabGift4Desc::
	text "A special PIKACHU"
	line "with LIGHT BALL"
	done
