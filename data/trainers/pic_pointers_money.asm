MACRO pic_money
	dw \1
	bcd3 \2
ENDM

TrainerPicAndMoneyPointers::
	table_width 5
	; pic pointer, base reward money
	; money received after battle = base money × level of last enemy mon
	pic_money YoungsterPic,    250
	pic_money BugCatcherPic,   250
	pic_money LassPic,         250
	pic_money SailorPic,       250
	pic_money JrTrainerMPic,   250
	pic_money JrTrainerFPic,   250
	pic_money PokemaniacPic,   250
	pic_money SuperNerdPic,    250
	pic_money HikerPic,        250
	pic_money BikerPic,        250
	pic_money BurglarPic,      250
	pic_money EngineerPic,     250
	pic_money JugglerPic,      250
	pic_money FisherPic,       250
	pic_money SwimmerPic,      250
	pic_money CueBallPic,      250
	pic_money GamblerPic,      250
	pic_money BeautyPic,       250
	pic_money PsychicPic,      250
	pic_money RockerPic,       250
	pic_money JugglerPic,      250
	pic_money TamerPic,        250
	pic_money BirdKeeperPic,   250
	pic_money BlackbeltPic,    250
	pic_money Rival1Pic,       300
	pic_money ProfOakPic,      1000
	pic_money ChiefPic,        250
	pic_money ScientistPic,    250
	pic_money GiovanniPic,     800
	pic_money RocketPic,       250
	pic_money CooltrainerMPic, 250
	pic_money CooltrainerFPic, 250
	pic_money BrunoPic,        800
	pic_money BrockPic,        800
	pic_money MistyPic,        800
	pic_money LtSurgePic,      800
	pic_money ErikaPic,        800
	pic_money KogaPic,         800
	pic_money BlainePic,       800
	pic_money SabrinaPic,      800
	pic_money GentlemanPic,    250
	pic_money Rival2Pic,       800
	pic_money Rival3Pic,       800
	pic_money LoreleiPic,      800
	pic_money ChannelerPic,    250
	pic_money AgathaPic,       800
	pic_money LancePic,        800
	assert_table_length NUM_TRAINERS
