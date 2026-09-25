; Lobby Psychic (engine/events/lobby_psychic.asm). The leader's name is in
; wNameBuffer and the price in wPriceTemp when these print.
_PsychicOfferText::
	text "I sense a GYM"
	line "beyond that door…"

	para "For ¥@"
	text_bcd wPriceTemp, 3 | LEADING_ZEROES | LEFT_ALIGN
	text ", I'll"
	line "reveal its LEADER."
	done

_PsychicRefuseText::
	text "The spirits can"
	line "wait, then."
	done

_PsychicNoMoneyText::
	text "The spirits don't"
	line "work for free."
	done

_PsychicRevealText::
	text "I see it now…"

	para "@"
	text_ram wNameBuffer
	text " awaits!"

	para "Look upon your"
	line "TRAINER CARD."
	done

_PsychicAlreadyText::
	text "@"
	text_ram wNameBuffer
	text " awaits"
	line "you. The spirits"
	cont "have spoken."
	done

_PsychicNoGymText::
	text "The spirits are"
	line "quiet today…"
	done

; Door 1's sign on a gym cycle once foresight is bought (LobbyDoor1SignText).
_LobbyGymForesightSignText::
	text "GYM AHEAD:"
	line "@"
	text_ram wNameBuffer
	text_end

_WitchIntroText::
	text "Kekeke...."
    para "I have a"
	line "challenge for you"
    cont "if you dare"
	done

_WitchChallenge1Text::
	text "This zone hands"
	line "out no free"
	cont "#MON"
	prompt

_WitchChallenge2Text::
	text "No hidden item"
	line "in this zone"
	prompt

_WitchChallenge3Text::
	text "No money from"
	line "battles this zone"
	prompt

_WitchChallenge4Text::
	text "Rolls favor"
	line "common #MON"
	cont "this zone"
	prompt

_WitchChallenge5Text::
	text "Foes will be"
	line "tougher, higher"
	cont "level"
	prompt

_WitchChallenge6Text::
	text "Foes will be"
	line "rarer breeds"
	prompt

_WitchChallenge7Text::
	text "Your party stays"
	line "smaller this"
	cont "zone"
	prompt

_WitchChallenge8Text::
	text "Your #MON will"
	line "feel sluggish"
	prompt

_WitchChallenge9Text::
	text "Your whole team"
	line "starts poisoned"
	prompt

_WitchChallenge10Text::
	text "Drag a fight out"
	line "too long and"
	cont "you'll pay for it"
	prompt

_WitchChallenge11Text::
	text "This zone's boss"
	line "keeps fearsome"
	cont "company"
	prompt

_WitchChallenge12Text::
	text "Every hit you"
	line "land hurts you"
	cont "too"
	prompt

_WitchChallenge13Text::
	text "Step into my"
	line "GAMBLER'S"
	cont "PARADISE"
	prompt

_WitchChallenge14Text::
	text "Repeat a move and"
	line "my bargain bites"
	cont "back."
	prompt

_WitchChallenge15Text::
	text "No medicine for"
	line "you outside of"
	cont "battle."
	prompt

_WitchChallenge16Text::
	text "Blows of muscle"
	line "will cost you"
	cont "blood."
	prompt

_WitchChallenge17Text::
	text "Blows of the mind"
	line "will cost you"
	cont "blood."
	prompt

_WitchChallenge18Text::
	text "Your moves will"
	line "tire twice as"
	cont "quickly."
	prompt

_WitchPrize1Text::
	text "Win and your"
	line "reward #MON"
	cont "will be rarer"

	para "Do we have a"
	line "bargain?"
	done

_WitchPrize2Text::
	text "Win and your"
	line "item finds"
	cont "get rarer"

	para "Do we have a"
	line "bargain?"
	done

_WitchPrize3Text::
	text "Win and I'll"
	line "boost your prize"
	cont "money"

	para "Do we have a"
	line "bargain?"
	done

_WitchPrize4Text::
	text "Win and your"
	line "#MON gain"
	cont "extra EXP"

	para "Do we have a"
	line "bargain?"
	done

_WitchPrize5Text::
	text "Win and your"
	line "critical hits"
	cont "increase"

	para "Do we have a"
	line "bargain?"
	done

_WitchPrize6Text::
	text "Win and your"
	line "moves land"
	cont "more often"

	para "Do we have a"
	line "bargain?"
	done

_WitchPrize7Text::
	text "Win and your"
	line "SPECIAL rises"
	cont "for the whole run"

	para "Do we have a"
	line "bargain?"
	done

_WitchPrize8Text::
	text "Win and foes hit"
	line "your weak spots"
	cont "softer, for good"

	para "Do we have a"
	line "bargain?"
	done

_WitchPrize9Text::
	text "Win and your"
	line "multi-hit moves"
	cont "hit more often"

	para "Do we have a"
	line "bargain?"
	done

_WitchPrize10Text::
	text "Win and every"
	line "shop cuts you a"
	cont "permanent deal"

	para "Do we have a"
	line "bargain?"
	done

; Fixed teaser for CHALLENGE_LEGENDARY_BOSS (wWitchPrize = 0 sentinel).
; Shown instead of a random prize; the boss trades a LEGENDARY for one
; of your masterball-class #MON.
_WitchPrizeLegendaryText::
	text "Win and the boss"
	line "will trade you a"
	cont "LEGENDARY!"

	para "Do we have a"
	line "bargain?"
	done

_WitchPartyLimitText::
	text "The bargain won't"
	line "allow it. Your"
	cont "party is full."
	done

_WitchAcceptanceText::
	text "So mote it be"
	done
    
_WitchRefusalText::
	text "Huhuhu..."
	line "so you say"
	done
    
_PCMoveTutorGreetingText::
    text "I have a pathway"
	line "for your #MON"
	cont "to learn many"
    cont "abilities some"
    cont "might consider"
    cont "...unnatural."
    
    para "¥5000 per move."
	line "Interested?"
	done
    
_PCMoveTutorByeText::
    text "Until next time."
	done
    
_PCMoveTutorNotEnoughMoneyText::
    text "You lack the"
	line "funds for my"
    cont "services"
	done
    
_PCMoveTutorSaidYesText::
	text "Which #MON"
	line "should I tutor?"
	prompt
    
_PCMoveTutorWhichMoveText::
	text "Which move should"
	line "it learn?"
	done
    
_PCMoveTutorNoMovesText::
	text "I have nothing to"
	line "teach this"
	cont "#MON."
	done
    
_PCPokemonSalesmanIGotADealPokeballText::
	text "MAN: Hello, there!"
	line "Have I got a deal"
	cont "just for you!"

	para "I'll let you have"
	line "a swell"
    cont "@"
    text_ram wNameBuffer
    text "!"
    
    para "for just 2000!"
	line "What do you say?"
	done
    
_PCPokemonSalesmanIGotADealGreatballText::
	text "MAN: Hello, there!"
	line "Have I got a deal"
	cont "just for you!"

	para "I'll let you have"
	line "a swell"
    cont "@"
    text_ram wNameBuffer
    text "!"
    
    para  "for just 6000!"
	line "What do you say?"
	done
    
_PCPokemonSalesmanIGotADealUltraballText::
	text "MAN: Hello, there!"
	line "Have I got a deal"
	cont "just for you!"

	para "I'll let you have"
	line "a swell"
    cont "@"
    text_ram wNameBuffer
    text "!"
    
    para  "for just 9000!"
	line "What do you say?"
	done

_PCPokemonSalesmanNoText::
	text "No? I'm only"
	line "doing this as a"
	cont "favor to you!"
	done

_PCPokemonSalesmanNoMoneyText::
	text "You'll need more"
	line "money than that!"
	done

_PCPokemonSalesmanNoRefundsText::
	text "MAN: Well, I don't"
	line "give refunds!"
	done