_ChampionsRoomRivalIntroText::
	text "<RIVAL>: Hey!"

	para "I was looking"
	line "forward to seeing"
	cont "you, <PLAYER>!"

	para "My rival should"
	line "be strong to keep"
	cont "me sharp!"

	para "While working on"
	line "#DEX, I looked"
	cont "all over for"
	cont "powerful #MON!"

	para "Not only that, I"
	line "assembled teams"
	cont "that would beat"
	cont "any #MON type!"

	para "And now!"

	para "I'm the #MON"
	line "LEAGUE champion!"

	para "<PLAYER>! Do you"
	line "know what that"
	cont "means?"

	para "I'll tell you!"

	para "I am the most"
	line "powerful trainer"
	cont "in the world!"
	done

_RivalDefeatedText::
	text "NO!"
	line "That can't be!"
	cont "You beat my best!"

	para "After all that"
	line "work to become"
	cont "LEAGUE champ?"

	para "My reign is over"
	line "already?"
	cont "It's not fair!"
	prompt

_RivalVictoryText::
	text "Hahaha!"
	line "I won, I won!"

	para "I'm too good for"
	line "you, <PLAYER>!"

	para "You did well to"
	line "even reach me,"
	cont "<RIVAL>, the"
	cont "#MON genius!"

	para "Nice try, loser!"
	line "Hahaha!"
	prompt

_ChampionsRoomRivalAfterBattleText::
	text "Why?"
	line "Why did I lose?"

	para "I never made any"
	line "mistakes raising"
	cont "my #MON..."

	para "Darn it! You're"
	line "the new #MON"
	cont "LEAGUE champion!"

	para "Although I don't"
	line "like to admit it."
	done

_ChampionsRoomOakText::
	text "OAK: <PLAYER>!"
	done

_ChampionsRoomOakCongratulatesPlayerText::
	text "OAK: So, you won!"
	line "Congratulations!"
	cont "You're the new"
	cont "#MON LEAGUE"
	cont "champion!"

	para "You've grown up so"
	line "much since you"
	cont "first left with"
	cont "@"
	text_ram wNameBuffer
	text "!"

	para "<PLAYER>, you have"
	line "come of age!"
	done

_ChampionsRoomOakDisappointedWithRivalText::
	text "OAK: <RIVAL>! I'm"
	line "disappointed!"

	para "I came when I"
	line "heard you beat"
	cont "the ELITE FOUR!"

	para "But, when I got"
	line "here, you had"
	cont "already lost!"

	para "<RIVAL>! Do you"
	line "understand why"
	cont "you lost?"

	para "You have forgotten"
	line "to treat your"
	cont "#MON with"
	cont "trust and love!"

	para "Without them, you"
	line "will never become"
	cont "a champ again!"
	done

_ChampionsRoomOakComeWithMeText::
	text "OAK: <PLAYER>!"

	para "You understand"
	line "that your victory"
	cont "was not just your"
	cont "own doing!"

	para "The bond you share"
	line "with your #MON"
	cont "is marvelous!"

	para "<PLAYER>!"
	line "Come with me!"
	done

; ============================================================
; Lance as an alternate Champion (Phase 7e)
; ============================================================

_ChampionsRoomLanceIntroText::
	text "LANCE: <PLAYER>!"

	para "You made it"
	line "through the"
	cont "ELITE FOUR!"

	para "I am LANCE, the"
	line "DRAGON master!"

	para "My #MON have"
	line "never lost to"
	cont "a challenger!"

	para "Show me the bond"
	line "you share with"
	cont "your own #MON!"
	done

_LanceDefeatedText::
	text "LANCE: What?!"
	line "My dragons..."
	cont "defeated?!"

	para "I trained them"
	line "with all my"
	cont "heart!"

	para "You are truly a"
	line "#MON master!"
	prompt

_LanceVictoryText::
	text "LANCE: Ha!"

	para "My DRAGONITE is"
	line "unbeatable!"

	para "Come back when"
	line "you're ready,"
	cont "<PLAYER>!"
	prompt

_ChampionsRoomLanceAfterBattleText::
	text "LANCE: Amazing!"

	para "Not even my"
	line "dragons could"
	cont "stop you!"

	para "You are the new"
	line "#MON LEAGUE"
	cont "champion!"
	done

_ChampionsRoomOakDisappointedWithLanceText::
	text "OAK: LANCE! I'm"
	line "surprised!"

	para "I heard you"
	line "swept the"
	cont "ELITE FOUR!"

	para "But <PLAYER> has"
	line "bested you here!"

	para "LANCE, this is"
	line "how #MON"
	cont "training should"
	cont "always be!"

	para "Never stop"
	line "striving to"
	cont "improve!"
	done

; ============================================================
; Oak as an alternate Champion (Phase 7e)
; ============================================================

_ChampionsRoomOakChampionIntroText::
	text "OAK: <PLAYER>!"

	para "I couldn't"
	line "resist testing"
	cont "you myself!"

	para "A lifetime of"
	line "studying #MON"
	cont "taught me much!"

	para "But knowledge"
	line "alone won't win"
	cont "a #MON battle!"

	para "Show me what"
	line "you've learned,"
	cont "<PLAYER>!"
	done

_OakChampionDefeatedText::
	text "OAK: Ha ha ha!"

	para "Just as I"
	line "hoped!"

	para "You've surpassed"
	line "your old"
	cont "professor!"
	prompt

_OakChampionVictoryText::
	text "OAK: Not bad,"
	line "<PLAYER>!"

	para "But there's still"
	line "more for you to"
	cont "learn!"
	prompt

_ChampionsRoomOakChampionAfterBattleText::
	text "OAK: Wonderful!"

	para "You've done what"
	line "I always"
	cont "believed you"
	cont "could!"

	para "Congratulations,"
	line "<PLAYER>!"

	para "You are the new"
	line "#MON LEAGUE"
	cont "champion!"
	done

_ChampionsRoomOakChampionCongratulatesText::
	text "OAK: <PLAYER>!"

	para "I never thought"
	line "my own #MON"
	cont "would lose to"
	cont "you!"

	para "You've grown up so"
	line "much since you"
	cont "first left with"
	cont "@"
	text_ram wNameBuffer
	text "!"

	para "The bond you"
	line "share with your"
	cont "#MON is"
	cont "marvelous!"

	para "<PLAYER>, you have"
	line "come of age!"
	done
