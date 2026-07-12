_ItemUseText001::
	text "<PLAYER> used@"
	text_end

_ItemUseText002::
	text_ram wStringBuffer
	text "!"
	done

_GotOnBicycleText1::
	text "<PLAYER> got on the@"
	text_end

_GotOnBicycleText2::
	text_ram wStringBuffer
	text "!"
	prompt

_GotOffBicycleText1::
	text "<PLAYER> got off@"
	text_end

_GotOffBicycleText2::
	text "the @"
	text_ram wStringBuffer
	text "."
	prompt

_ThrewAwayItemText::
	text "Threw away"
	line "@"
	text_ram wNameBuffer
	text "."
	prompt

_IsItOKToTossItemText::
	text "Is it OK to toss"
	line "@"
	text_ram wStringBuffer
	text "?"
	prompt

_TooImportantToTossText::
	text "That's too impor-"
	line "tant to toss!"
	prompt

_AlreadyKnowsText::
	text_ram wNameBuffer
	text " knows"
	line "@"
	text_ram wStringBuffer
	text "!"
	prompt

_ConnectCableText::
	text "Okay, connect the"
	line "cable like so!"
	prompt

_TradedForText::
	text "<PLAYER> traded"
	line "@"
	text_ram wInGameTradeGiveMonName
	text " for"
	cont "@"
	text_ram wInGameTradeReceiveMonName
	text "!@"
	text_end

_WannaTrade1Text::
	text "I'm looking for"
	line "@"
	text_ram wInGameTradeGiveMonName
	text "! Wanna"

	para "trade one for"
	line "@"
	text_ram wInGameTradeReceiveMonName
	text "? "
	done

_NoTrade1Text::
	text "Awww!"
	line "Oh well..."
	done

_WrongMon1Text::
	text "What? That's not"
	line "@"
	text_ram wInGameTradeGiveMonName
	text "!"

	para "If you get one,"
	line "come back here!"
	done

_Thanks1Text::
	text "Hey thanks!"
	done

_AfterTrade1Text::
	text "Isn't my old"
	line "@"
	text_ram wInGameTradeReceiveMonName
	text " great?"
	done

_WannaTrade2Text::
	text "Hello there! Do"
	line "you want to trade"

	para "your @"
	text_ram wInGameTradeGiveMonName
	text_start
	line "for @"
	text_ram wInGameTradeReceiveMonName
	text "?"
	done

_NoTrade2Text::
	text "Well, if you"
	line "don't want to..."
	done

_WrongMon2Text::
	text "Hmmm? This isn't"
	line "@"
	text_ram wInGameTradeGiveMonName
	text "."

	para "Think of me when"
	line "you get one."
	done

_Thanks2Text::
	text "Thanks!"
	done

_AfterTrade2Text::
	text "The @"
	text_ram wInGameTradeGiveMonName
	text " you"
	line "traded to me"

	para "went and evolved!"
	done

_WannaTrade3Text::
	text "Hi! Do you have"
	line "@"
	text_ram wInGameTradeGiveMonName
	text "?"

	para "Want to trade it"
	line "for @"
	text_ram wInGameTradeReceiveMonName
	text "?"
	done

_NoTrade3Text::
	text "That's too bad."
	done

_WrongMon3Text::
	text "...This is no"
	line "@"
	text_ram wInGameTradeGiveMonName
	text "."

	para "If you get one,"
	line "trade it with me!"
	done

_Thanks3Text::
	text "Thanks pal!"
	done

_AfterTrade3Text::
	text "How is my old"
	line "@"
	text_ram wInGameTradeReceiveMonName
	text "?"

	para "My @"
	text_ram wInGameTradeGiveMonName
	text " is"
	line "doing great!"
	done

; TRADE_DIALOGSET_LEGENDARY (set 4) - gym-leader legendary trade (Challenge 11).
; give = the player's masterball-class mon; receive = the legendary (Mew/Mewtwo).
; Placeholder wording - customize freely; keep names on their own line to avoid
; overflow (player give-mon names can be up to 10 chars).
_WannaTrade4Text::
	text "I seek a"
	line "@"
	text_ram wInGameTradeGiveMonName
	text "!"

	para "Trade it for my"
	line "@"
	text_ram wInGameTradeReceiveMonName
	text "?"
	done

_NoTrade4Text::
	text "A pity. My offer"
	line "still stands."
	done

_WrongMon4Text::
	text "That is no"
	line "@"
	text_ram wInGameTradeGiveMonName
	text "."

	para "Bring one to me."
	done

_Thanks4Text::
	text "A worthy trade!"
	done

_AfterTrade4Text::
	text "Guard"
	line "@"
	text_ram wInGameTradeReceiveMonName
	text " well."
	done

_NothingToCutText::
	text "There isn't"
	line "anything to CUT!"
	prompt

_UsedCutText::
	text_ram wNameBuffer
	text " hacked"
	line "away with CUT!"
	prompt
