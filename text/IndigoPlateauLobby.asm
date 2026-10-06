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
	line "out no #MON"
	prompt

_WitchChallenge2Text::
	text "No item in"
	line "this zone"
	prompt

_WitchChallenge3Text::
	text "No money from"
	line "battles this zone"
	prompt

_WitchChallenge4Text::
	text "Luck favors"
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

; wPartyLimit is precomputed at roll time (WitchPrepChallengeParams).
_WitchChallenge7Text::
	text "You may only"
	line "bring @"
	text_decimal wPartyLimit, 1, 1
	text " #MON"
	cont "to this zone."

	para "Bring more and"
	line "the bargain fails!"
	prompt

; Shown on the first step into a zone with too many #MON (WitchCheckPartyLimit).
; wPartyLimit is still the limit she quoted.
_WitchBargainBrokenText::
	text "CHALLENGE FAILED!"

	para "You brought more"
	line "than @"
	text_decimal wPartyLimit, 1, 1
	text " #MON."
	cont "No prize for you!"
	done

_WitchChallenge8Text::
	text "Your #MON will"
	line "run at half SPEED"
	prompt

_WitchChallenge9Text::
	text "Your whole team"
	line "will be poisoned"
	cont "the whole zone"
	prompt

; wBattleTurnLimit is precomputed at roll time (WitchPrepChallengeParams).
_WitchChallenge10Text::
	text "After @"
	text_decimal wBattleTurnLimit, 1, 2
	text " turns,"
	line "a battle will"
	cont "drain HP"
	prompt

_WitchChallenge11Text::
	text "This zone's boss"
	line "keeps LEGENDARY"
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
	text "ATK moves cost"
	line "your #MON HP"
	prompt

_WitchChallenge17Text::
	text "SPC moves cost"
	line "your #MON HP"
	prompt

_WitchChallenge18Text::
	text "Your moves will"
	line "cost 2 PP"
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
    
    para "Fees vary by move"
	line "Interested?"
	done
    
_PCMoveTutorByeText::
    text "Until next time."
	done
    
_PCMoveTutorNotEnoughMoneyText::
    text "You lack the"
	line "funds for my"
    cont "services."
	prompt
    
_PCMoveTutorSaidYesText::
	text "Which #MON"
	line "should I tutor?"
	prompt
    
_PCMoveTutorWhichMoveText::
	text "Which move should"
	line "it learn?"
	done

_PCMoveTutorConfirmText::
	text_ram wStringBuffer
	text_start
	line "For ¥@"
	text_bcd hMoney, 3 | LEADING_ZEROES | LEFT_ALIGN
	text "?"
	cont "Teach this move?"
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
    
    para "for just ¥{x:SALESMAN_PRICE_POKEBALL_BCD}000!"
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
    
    para  "for just ¥{x:SALESMAN_PRICE_GREATBALL_BCD}000!"
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
    
    para  "for just ¥{x:SALESMAN_PRICE_ULTRABALL_BCD}000!"
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

; Miniboss door signs, indexed by door, boss type, then item category.
_LobbyDoor1RivalHealingText::
	text "DOOR 1: RIVAL"
	line "ENCOUNTER"
	cont "HEALING ITEMS@"
	text_end

_LobbyDoor1RivalStatText::
	text "DOOR 1: RIVAL"
	line "ENCOUNTER"
	cont "STAT BOOSTS@"
	text_end

_LobbyDoor1RivalTMText::
	text "DOOR 1: RIVAL"
	line "ENCOUNTER"
	cont "TM ITEMS@"
	text_end

_LobbyDoor1RivalMoneyText::
	text "DOOR 1: RIVAL"
	line "ENCOUNTER"
	cont "MONEY@"
	text_end

_LobbyDoor1GiovanniHealingText::
	text "DOOR 1: GIOVANNI"
	line "ENCOUNTER"
	cont "HEALING ITEMS@"
	text_end

_LobbyDoor1GiovanniStatText::
	text "DOOR 1: GIOVANNI"
	line "ENCOUNTER"
	cont "STAT BOOSTS@"
	text_end

_LobbyDoor1GiovanniTMText::
	text "DOOR 1: GIOVANNI"
	line "ENCOUNTER"
	cont "TM ITEMS@"
	text_end

_LobbyDoor1GiovanniMoneyText::
	text "DOOR 1: GIOVANNI"
	line "ENCOUNTER"
	cont "MONEY@"
	text_end

_LobbyDoor1KarateHealingText::
	text "DOOR 1:"
	line "KARATE MASTER"
	cont "ENCOUNTER"
	cont "HEALING ITEMS@"
	text_end

_LobbyDoor1KarateStatText::
	text "DOOR 1:"
	line "KARATE MASTER"
	cont "ENCOUNTER"
	cont "STAT BOOSTS@"
	text_end

_LobbyDoor1KarateTMText::
	text "DOOR 1:"
	line "KARATE MASTER"
	cont "ENCOUNTER"
	cont "TM ITEMS@"
	text_end

_LobbyDoor1KarateMoneyText::
	text "DOOR 1:"
	line "KARATE MASTER"
	cont "ENCOUNTER"
	cont "MONEY@"
	text_end

_LobbyDoor2RivalHealingText::
	text "DOOR 2: RIVAL"
	line "ENCOUNTER"
	cont "HEALING ITEMS@"
	text_end

_LobbyDoor2RivalStatText::
	text "DOOR 2: RIVAL"
	line "ENCOUNTER"
	cont "STAT BOOSTS@"
	text_end

_LobbyDoor2RivalTMText::
	text "DOOR 2: RIVAL"
	line "ENCOUNTER"
	cont "TM ITEMS@"
	text_end

_LobbyDoor2RivalMoneyText::
	text "DOOR 2: RIVAL"
	line "ENCOUNTER"
	cont "MONEY@"
	text_end

_LobbyDoor2GiovanniHealingText::
	text "DOOR 2: GIOVANNI"
	line "ENCOUNTER"
	cont "HEALING ITEMS@"
	text_end

_LobbyDoor2GiovanniStatText::
	text "DOOR 2: GIOVANNI"
	line "ENCOUNTER"
	cont "STAT BOOSTS@"
	text_end

_LobbyDoor2GiovanniTMText::
	text "DOOR 2: GIOVANNI"
	line "ENCOUNTER"
	cont "TM ITEMS@"
	text_end

_LobbyDoor2GiovanniMoneyText::
	text "DOOR 2: GIOVANNI"
	line "ENCOUNTER"
	cont "MONEY@"
	text_end

_LobbyDoor2KarateHealingText::
	text "DOOR 2:"
	line "KARATE MASTER"
	cont "ENCOUNTER"
	cont "HEALING ITEMS@"
	text_end

_LobbyDoor2KarateStatText::
	text "DOOR 2:"
	line "KARATE MASTER"
	cont "ENCOUNTER"
	cont "STAT BOOSTS@"
	text_end

_LobbyDoor2KarateTMText::
	text "DOOR 2:"
	line "KARATE MASTER"
	cont "ENCOUNTER"
	cont "TM ITEMS@"
	text_end

_LobbyDoor2KarateMoneyText::
	text "DOOR 2:"
	line "KARATE MASTER"
	cont "ENCOUNTER"
	cont "MONEY@"
	text_end
