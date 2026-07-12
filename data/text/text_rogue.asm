_GreedyText::
    text "Better not get"
	line "greedy..."
	done

_RogueTradeOfferText::
	text "Your @"
	text_ram wNameBuffer
	text "@"
	line "for a @"
	text_ram wroguenpctradename
	text "?@"
	done

_PickPokeBallText::
	text "You want"
	line "@"
	text_ram wNameBuffer
	text "?@"
	text_end

_NoTurningBackText::
	text "There's no"
	line "turning back!"
	done

_PartyHPRecoveredText::
	text "Party HP"
	line "partly recovered!"
	prompt

_PartyPPRecoveredText::
	text "Party PP"
	line "partly recovered!"
	prompt

_PartyHPAndPPRecoveredText::
	text "Party HP/PP"
	line "partly recovered!"
	prompt

_LeftoversText::
	text "Your party"
	line "was healed!"
	prompt

_LeftoversDescriptionText::
	text "Heals your"
	line "team a bit"
	cont "after each"
	cont "battle!"
	done

_PPTonicText::
	text "Your party's"
	line "PP was"
	cont "restored!"
	prompt

_RecoilChallengeText::
	text "The bargain burns!"
	line "<TARGET> was hit"
	cont "by recoil!"
	done

_TurnLimitDrainText::
	text "Time's running"
	line "out! <TARGET> lost"
	cont "some HP!"
	done

_PPTonicDescriptionText::
	text "Restores PP"
	line "slightly after"
	cont "each battle."
	done

_ExpAllDescriptionText::
	text "Shares EXP"
	line "with the whole"
	cont "party after"
	cont "each battle."
	done

_KODefianceDescriptionText::
	text "Revives your"
	line "last mon if"
	cont "it would"
	cont "faint!"
	done

_KODefianceActivatedText::
	text "KO DEFIANCE"
	line "activated!"
	done