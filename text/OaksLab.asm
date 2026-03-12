_GreedyText::
    text "Better not get"
	line "greedy..."
	done

_PickPokeBallText::
	text "You want"
	line "@"
	text_ram wNameBuffer
	text "?@"
	text_end
    
_OaksLabRivalIPickedTheWrongPokemonText::
	text "Take your prize"
	line "#MON in the next"
	cont "room. You'll"
	cont "need it to "
    cont "keep pace"
    cont "with me"
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