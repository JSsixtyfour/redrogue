MACRO pic_money
; \1 = pic label, \2 = base reward money.
;
; The bank byte is what lets a trainer pic live in ANY bank. _LoadTrainerPic
; used to choose between two hardcoded banks with `cp JESSIE_JAMES`, which
; capped new trainer pics at whatever fit in "Trainer Pics" (85 bytes free, not
; enough for one more 56x56 pic). BANK() resolves at link time, so a pic that
; changes bank needs no edit here.
	dw \1
	db BANK(\1)
	bcd3 \2
ENDM

TrainerPicAndMoneyPointers::
	table_width 6
	; pic pointer, base reward money
	; money received after battle = base money × level of last enemy mon
	pic_money YoungsterPic,    75
	pic_money BugCatcherPic,   75
	pic_money LassPic,         75
	pic_money SailorPic,       75
	pic_money JrTrainerMPic,   75
	pic_money JrTrainerFPic,   75
	pic_money PokemaniacPic,   75
	pic_money SuperNerdPic,    75
	pic_money HikerPic,        75
	pic_money BikerPic,        75
	pic_money BurglarPic,      75
	pic_money EngineerPic,     75
	pic_money JoyPic,          75
	pic_money FisherPic,       75
	pic_money SwimmerPic,      75
	pic_money CueBallPic,      75
	pic_money GamblerPic,      75
	pic_money BeautyPic,       75
	pic_money PsychicPic,      75
	pic_money RockerPic,       75
	pic_money JugglerPic,      75
	pic_money TamerPic,        75
	pic_money BirdKeeperPic,   75
	pic_money BlackbeltPic,    75
	pic_money Rival1Pic,       100
	pic_money ProfOakPic,      300
	pic_money JennyPic,        75
	pic_money ScientistPic,    75
	pic_money GiovanniPic,     150
	pic_money RocketPic,       75
	pic_money CooltrainerMPic, 75
	pic_money CooltrainerFPic, 75
	pic_money BrunoPic,        200
	pic_money BrockPic,        200
	pic_money MistyPic,        200
	pic_money LtSurgePic,      200
	pic_money ErikaPic,        200
	pic_money KogaPic,         200
	pic_money BlainePic,       200
	pic_money SabrinaPic,      200
	pic_money GentlemanPic,    75
	pic_money Rival2Pic,       150
	pic_money Rival3Pic,       300
	pic_money LoreleiPic,      200
	pic_money ChannelerPic,    75
	pic_money AgathaPic,       200
	pic_money LancePic,        200
	pic_money Rival1Pic,       100
	pic_money GiovanniPic,     200
	pic_money JessieJamesPic,  75
	pic_money FalknerPic,      200
	pic_money BugsyPic,        200
	pic_money WhitneyPic,      200
	pic_money MortyPic,        200
	pic_money ChuckPic,        200
	pic_money JasminePic,      200
	pic_money PrycePic,        200
	pic_money ClairPic,        200
	pic_money JaninePic,       200
	pic_money WillPic,         200
	pic_money KarenPic,        200
	pic_money KogaPic,         200 ; KOGA_E4 reuses the gym Koga's pic
	pic_money RedPicFront,     300 ; FINAL_AI - portrait overridden at runtime by ReadFinalAITrainer
	assert_table_length NUM_TRAINERS
