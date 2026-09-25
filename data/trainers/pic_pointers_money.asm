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
	; pic pointer, base reward money (constants/balance_constants.asm)
	; money received after battle = base money × level of last enemy mon
	pic_money YoungsterPic,    MONEY_BASE_TRAINER
	pic_money BugCatcherPic,   MONEY_BASE_TRAINER
	pic_money LassPic,         MONEY_BASE_TRAINER
	pic_money SailorPic,       MONEY_BASE_TRAINER
	pic_money JrTrainerMPic,   MONEY_BASE_TRAINER
	pic_money JrTrainerFPic,   MONEY_BASE_TRAINER
	pic_money PokemaniacPic,   MONEY_BASE_TRAINER
	pic_money SuperNerdPic,    MONEY_BASE_TRAINER
	pic_money HikerPic,        MONEY_BASE_TRAINER
	pic_money BikerPic,        MONEY_BASE_TRAINER
	pic_money BurglarPic,      MONEY_BASE_TRAINER
	pic_money EngineerPic,     MONEY_BASE_TRAINER
	pic_money JoyPic,          MONEY_BASE_TRAINER
	pic_money FisherPic,       MONEY_BASE_TRAINER
	pic_money SwimmerPic,      MONEY_BASE_TRAINER
	pic_money CueBallPic,      MONEY_BASE_TRAINER
	pic_money GamblerPic,      MONEY_BASE_TRAINER
	pic_money BeautyPic,       MONEY_BASE_TRAINER
	pic_money PsychicPic,      MONEY_BASE_TRAINER
	pic_money RockerPic,       MONEY_BASE_TRAINER
	pic_money JugglerPic,      MONEY_BASE_TRAINER
	pic_money TamerPic,        MONEY_BASE_TRAINER
	pic_money BirdKeeperPic,   MONEY_BASE_TRAINER
	pic_money BlackbeltPic,    MONEY_BASE_TRAINER
	pic_money Rival1Pic,       MONEY_BASE_RIVAL1
	pic_money ProfOakPic,      MONEY_BASE_OAK
	pic_money JennyPic,        MONEY_BASE_TRAINER
	pic_money ScientistPic,    MONEY_BASE_TRAINER
	pic_money GiovanniPic,     MONEY_BASE_LEADER_GIOVANNI
	pic_money RocketPic,       MONEY_BASE_TRAINER
	pic_money CooltrainerMPic, MONEY_BASE_TRAINER
	pic_money CooltrainerFPic, MONEY_BASE_TRAINER
	pic_money BrunoPic,        MONEY_BASE_E4
	pic_money BrockPic,        MONEY_BASE_LEADER
	pic_money MistyPic,        MONEY_BASE_LEADER
	pic_money LtSurgePic,      MONEY_BASE_LEADER
	pic_money ErikaPic,        MONEY_BASE_LEADER
	pic_money KogaPic,         MONEY_BASE_LEADER
	pic_money BlainePic,       MONEY_BASE_LEADER
	pic_money SabrinaPic,      MONEY_BASE_LEADER
	pic_money GentlemanPic,    MONEY_BASE_TRAINER
	pic_money Rival2Pic,       MONEY_BASE_RIVAL2
	pic_money Rival3Pic,       MONEY_BASE_CHAMPION
	pic_money LoreleiPic,      MONEY_BASE_E4
	pic_money ChannelerPic,    MONEY_BASE_TRAINER
	pic_money AgathaPic,       MONEY_BASE_E4
	pic_money LancePic,        MONEY_BASE_E4
	pic_money Rival1Pic,       MONEY_BASE_MINIBOSS_RIVAL
	pic_money GiovanniPic,     MONEY_BASE_MINIBOSS_GIOVANNI
	pic_money JessieJamesPic,  MONEY_BASE_TRAINER
	pic_money FalknerPic,      MONEY_BASE_LEADER
	pic_money BugsyPic,        MONEY_BASE_LEADER
	pic_money WhitneyPic,      MONEY_BASE_LEADER
	pic_money MortyPic,        MONEY_BASE_LEADER
	pic_money ChuckPic,        MONEY_BASE_LEADER
	pic_money JasminePic,      MONEY_BASE_LEADER
	pic_money PrycePic,        MONEY_BASE_LEADER
	pic_money ClairPic,        MONEY_BASE_LEADER
	pic_money JaninePic,       MONEY_BASE_LEADER
	pic_money WillPic,         MONEY_BASE_E4
	pic_money KarenPic,        MONEY_BASE_E4
	pic_money KogaPic,         MONEY_BASE_LEADER ; KOGA_E4 reuses the gym Koga's pic
	pic_money RedPicFront,     MONEY_BASE_CHAMPION ; FINAL_AI - portrait overridden at runtime by ReadFinalAITrainer
	assert_table_length NUM_TRAINERS
