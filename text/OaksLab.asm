_OaksLabRivalIPickedTheWrongPokemonText::
	text "Get your"
	line "reward in the "
	cont "next room."
	cont "You'll need"
    cont "it to keep"
    cont "pace with me"
	prompt

_OaksLabRivalAmIGreatOrWhatText::
	text "<RIVAL>: Take my"
	line "prize in the next room"
    line "you're going"
    line "to need it"
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
	line "away yet!"
	done

_NoTurningBack::
    text "No turning back"
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

_OaksLabOakGiftIntroText::
	text "OAK: Ah,"
	line "<PLAYER>! Good"
	cont "timing."

	para "Take this before"
	line "you go!"
	prompt

_OaksLabOakAlreadyGotText::
	text "OAK: Study hard,"
	line "and take care of"
	cont "your #MON!"
	done

_OaksLabOakNormalText::
	text "OAK: There's a"
	line "time and place"
	cont "for everything!"

	para "But not now."
	done

_OaksLabGift1Desc::
	text "A spirited"
	line "#MON!"
	done

_OaksLabGift2Desc::
	text "Raises Attack"
	line "stat!"
	done

_OaksLabGift3Desc::
	text "Raises a level"
	line "instantly!"
	done