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
	text "LANCE: I've been"
	line "waiting for you."

	para "<PLAYER>!"

	para "I knew that you,"
	line "with your skills,"

	para "would eventually"
	line "reach me here."

	para "There's no need"
	line "for words now."

	para "We will battle"
	line "to determine who"

	cont "is the stronger"
	cont "of the two of us."

	para "As the most"
	line "powerful trainer"
	cont "and as the"
	cont "#MON LEAGUE"
	cont "CHAMPION…"

	para "I, LANCE the"
	line "dragon master,"
	cont "accept your"
	cont "challenge!"
	done

_LanceDefeatedText::
	text "…It's"
	line "over."

	para "But it's an odd"
	line "feeling."

	para "I'm not angry"
	line "that I lost. In"
	cont "fact, I feel"
	cont "happy."

	para "Happy that I"
	line "witnessed the"
	cont "rise of a great"
	cont "new CHAMPION!"
	prompt

_LanceVictoryText::
	text "Well"
	line "fought! Come"
	cont "challenge me"
	cont "again when you"
	cont "are ready."
	prompt

_ChampionsRoomLanceAfterBattleText::
	text "…Whew."

	para "You have become"
	line "truly powerful,"
	cont "<PLAYER>."

	para "Your #MON have"
	line "responded to your"

	para "strong and up-"
	line "standing nature."

	para "As a trainer, you"
	line "will continue to"

	para "grow strong with"
	line "your #MON."
	done

_ChampionsRoomOakDisappointedWithLanceText::
	text "PROF.OAK: Ah,"
	line "<PLAYER>!"

	para "It's been a long"
	line "while."

	para "You certainly"
	line "look more mature."

	para "Your conquest of"
	line "the LEAGUE is"
	cont "just fantastic!"

	para "Your dedication,"
	line "trust and love"
	cont "for your #MON"
	cont "made this happen."

	para "Your #MON were"
	line "outstanding too."

	para "Because they"
	line "believed in you"
	cont "as a trainer,"
	cont "they persevered."

	para "Congratulations,"
	line "<PLAYER>!"
	done

; ============================================================
; Oak as an alternate Champion (Phase 7e)
; ============================================================

_ChampionsRoomOakChampionIntroText::
	text "OAK: It's been a"
	line "long time since"
	cont "I've walked these"
	cont "halls."

	para "Seeing your"
	line "passion and love"
	cont "for your #MON"
	cont "inspired me to"
	cont "fight once again."

	para "Now, <PLAYER>, show"
	line "me everything"
	cont "you've learned!"
	done

_OakChampionDefeatedText::
	text "Ha ha!"
	line "Thank you for"
	cont "treating me to"
	cont "such a grand"
	cont "final battle."

	para "You're even"
	line "better than I"
	cont "imagined!"
	prompt

_OakChampionVictoryText::
	text "Ha!"
	line "Thank you!"
	cont "I haven't felt a"
	cont "rush like that in"
	cont "years!"
	prompt

_ChampionsRoomOakChampionAfterBattleText::
	text " "
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
	done

; The whole post-battle speech on an Oak-as-Champion run: three boxes, ending
; in the "Come with me!" his skipped COME_WITH_ME text used to carry.
_ChampionsRoomOakChampionCongratulatesText::
	text "OAK: <PLAYER>!"

	para "You've grown so"
	line "much since you"
	cont "left with"
	cont "@"
	text_ram wNameBuffer
	text "!"

	para "You're the new"
	line "champion!"
	cont "Come with me!"
	done
