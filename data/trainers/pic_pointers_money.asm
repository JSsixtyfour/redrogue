MACRO pic_money
	dw \1
	bcd3 \2
ENDM

TrainerPicAndMoneyPointers::
	table_width 5
	; pic pointer, base reward money
	; money received after battle = base money × level of last enemy mon
	pic_money YoungsterPic,    150
	pic_money BugCatcherPic,   150
	pic_money LassPic,         150
	pic_money SailorPic,       150
	pic_money JrTrainerMPic,   150
	pic_money JrTrainerFPic,   150
	pic_money PokemaniacPic,   150
	pic_money SuperNerdPic,    150
	pic_money HikerPic,        150
	pic_money BikerPic,        150
	pic_money BurglarPic,      150
	pic_money EngineerPic,     150
	pic_money JugglerPic,      150
	pic_money FisherPic,       150
	pic_money SwimmerPic,      150
	pic_money CueBallPic,      150
	pic_money GamblerPic,      150
	pic_money BeautyPic,       150
	pic_money PsychicPic,      150
	pic_money RockerPic,       150
	pic_money JugglerPic,      150
	pic_money TamerPic,        150
	pic_money BirdKeeperPic,   150
	pic_money BlackbeltPic,    150
	pic_money Rival1Pic,       200
	pic_money ProfOakPic,      600
	pic_money ChiefPic,        150
	pic_money ScientistPic,    150
	pic_money GiovanniPic,     500
	pic_money RocketPic,       150
	pic_money CooltrainerMPic, 150
	pic_money CooltrainerFPic, 150
	pic_money BrunoPic,        500
	pic_money BrockPic,        500
	pic_money MistyPic,        500
	pic_money LtSurgePic,      500
	pic_money ErikaPic,        500
	pic_money KogaPic,         500
	pic_money BlainePic,       500
	pic_money SabrinaPic,      500
	pic_money GentlemanPic,    150
	pic_money Rival2Pic,       500
	pic_money Rival3Pic,       500
	pic_money LoreleiPic,      500
	pic_money ChannelerPic,    150
	pic_money AgathaPic,       500
	pic_money LancePic,        500
	pic_money Rival1Pic,       300
	pic_money GiovanniPic,     300
	pic_money JessieJamesPic, 150
	assert_table_length NUM_TRAINERS
