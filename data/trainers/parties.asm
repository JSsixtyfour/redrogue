; ===========================================================================
; Trainer party layouts. The FIRST byte of each team selects the layout, and
; every team is terminated by a 0 in the LEVEL position.
;
;   db <level>, <species>, ..., 0
;       Shared level. Every mon on the team is that level.
;
;   db TRAINERPARTY_LEVELS, <level>, <species>, ..., 0     ; $ff
;       Per-mon levels. The vanilla "special trainer" layout.
;
;   db TRAINERPARTY_FORMS, <level>, <species>, <form>, ..., 0   ; $fe
;       Per-mon levels AND regional forms (Species Groups Phase 2R, increment
;       8c). <form> is 0 for an ordinary mon, or 1..NUM_FORM_SLOTS to pick that
;       species' form record from data/pokemon/forms/.
;
;       e.g.  db TRAINERPARTY_FORMS
;             db 25, DUGTRIO, 1     ; Alolan Dugtrio  (adugtrio.asm)
;             db 24, GRIMER,  1     ; Alolan Grimer   (agrimer.asm)
;             db 26, TAUROS,  3     ; Paldean Tauros (Aqua)
;             db 22, PIDGEY,  0     ; ordinary Pidgey
;             db 0
;
;       The form index is the SECOND argument of that record's `form_record`
;       line - grep `form_record` in data/pokemon/forms/ to find it. A form on a
;       species with no matching record is simply ignored, not an error.
;
;       ⚠ These teams ignore the species-group unlocks on purpose: a handcrafted
;       team is authored content, not a roll, so it shows exactly what you wrote
;       regardless of whether the player has unlocked Johto or Time Warp. Only
;       the RANDOM rollers are gated (RogueFormsUnlocked).
;
;   db TRAINERPARTY_SPEC_ONLY                                       ; $fd
;       No authored team: written by `spec_covered_stub` below.
; ===========================================================================

; A class whose party_specs.asm list covers EVERY wTrainerNo any caller can hand
; it: InitGymBattle (1-24), InitElite4Battle (1-12), ChampionsRoom (Rival3 1-5,
; Lance 10-12) and the map object_events (set 1 or 2). RogueBuildParty always
; finds a spec first, so the authored teams these blocks used to hold were
; unreachable and were deleted (party roster Phase 0, 2026-10-07, ~2.3 KB of
; bank "Trainer Parties"). test_party_spec_coverage.py holds the coverage.
;
; The label stays, one byte long, so each class keeps its own TrainerDataPointers
; target (test_laundry_scope reads them to prove the table is aligned). If a
; caller ever does hand one of these classes an uncovered number, ReadTrainer
; treats the marker like any non-authored first byte: debug builds stop on
; `rst $38` there, and release builds roll an ordinary roster for the class
; rather than walking off the end of its data into the next class's teams.
;
; NOT stubbed: GiovanniData (sets 25-27 are past his spec list), Rival1/2Data
; (fixed rival scripts), ProfOakData (ChampionsRoom, no spec yet),
; JessieJamesData (its spec is gated to Wild Area maps by StageEventSpecAllowed,
; so off those maps the authored team is a real fallback). The mini-boss
; classes are stubbed too (party roster Phase 4): their specs are keyed on the
; round, not wTrainerNo, so every set number is covered.
MACRO spec_covered_stub
	db TRAINERPARTY_SPEC_ONLY
ENDM

TrainerDataPointers:
	table_width 2
	dw YoungsterData
	dw BugCatcherData
	dw LassData
	dw SailorData
	dw JrTrainerMData
	dw JrTrainerFData
	dw PokemaniacData
	dw SuperNerdData
	dw HikerData
	dw BikerData
	dw BurglarData
	dw EngineerData
	dw NurseJoyData
	dw FisherData
	dw SwimmerData
	dw CueBallData
	dw GamblerData
	dw BeautyData
	dw PsychicData
	dw RockerData
	dw JugglerData
	dw TamerData
	dw BirdKeeperData
	dw BlackbeltData
	dw Rival1Data
	dw ProfOakData
	dw OfficerJennyData
	dw ScientistData
	dw GiovanniData
	dw RocketData
	dw CooltrainerMData
	dw CooltrainerFData
	dw BrunoData
	dw BrockData
	dw MistyData
	dw LtSurgeData
	dw ErikaData
	dw KogaData
	dw BlaineData
	dw SabrinaData
	dw GentlemanData
	dw Rival2Data
	dw Rival3Data
	dw LoreleiData
	dw ChannelerData
	dw AgathaData
	dw LanceData
	dw RivalMiniBossData    ; RIVAL_MINIBOSS
	dw GiovanniMiniBossData ; GIOVANNI_MINIBOSS
	dw JessieJamesData    ; JESSIE_JAMES
	dw FalknerData          ; FALKNER
	dw BugsyData            ; BUGSY
	dw WhitneyData          ; WHITNEY
	dw MortyData            ; MORTY
	dw ChuckData            ; CHUCK
	dw JasmineData          ; JASMINE
	dw PryceData            ; PRYCE
	dw ClairData            ; CLAIR
	dw JanineData           ; JANINE
	dw WillData             ; WILL
	dw KarenData            ; KAREN
	dw KogaE4Data           ; KOGA_E4
	dw Rival3Data           ; FINAL_AI - never read: ReadTrainer loads the archive before this lookup
	dw KarateMiniBossData   ; KARATE_MINIBOSS
	assert_table_length NUM_TRAINERS

; if first byte != $FF, then
	; first byte is level (of all pokemon on this team)
	; all the next bytes are pokemon species
	; null-terminated
; if first byte == $FF, then
	; first byte is $FF (obviously)
	; every next two bytes are a level and species
	; null-terminated

YoungsterData:

BugCatcherData:

LassData:

SailorData:
JrTrainerMData:

JrTrainerFData:

PokemaniacData:

SuperNerdData:

HikerData:

BikerData:

; Empty deliberately: Phase 7f gave BURGLAR a PartySpecPointers entry (a
; rogue-flavoured pool, scaled by round), so this authored fallback is never
; reached.
BurglarData:

EngineerData:

; Empty deliberately, like every other spec-driven class here: PartySpecPointers
; carries NURSE_JOY's real team (Phase 7f), and RogueBuildParty always finds a
; spec for it, so this authored fallback is never reached.
NurseJoyData:

FisherData:

SwimmerData:

CueBallData:

GamblerData:

BeautyData:

; Empty deliberately: Phase 7f gave PSYCHIC_TR a PartySpecPointers entry (a
; psychic-type pool, scaled by round), so this authored fallback is never
; reached.
PsychicData:

RockerData:

JugglerData:

TamerData:

BirdKeeperData:

BlackbeltData:
db 14, SPEAROW, 0

Rival1Data:

	db $FF, 5, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 5, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 5, RIVAL_STARTER_PLACEHOLDER, 0
; Route 22
	db $FF, 9, PIDGEY, 8, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 9, PIDGEY, 8, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 9, PIDGEY, 8, RIVAL_STARTER_PLACEHOLDER, 0
; Cerulean City
	db $FF, 18, PIDGEOTTO, 15, ABRA, 15, RATTATA, 17, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 18, PIDGEOTTO, 15, ABRA, 15, RATTATA, 17, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 18, PIDGEOTTO, 15, ABRA, 15, RATTATA, 17, RIVAL_STARTER_PLACEHOLDER, 0

ProfOakData:
; Unused
	db $FF, 66, TAUROS, 67, EXEGGUTOR, 68, ARCANINE, 69, BLASTOISE, 70, GYARADOS, 0
	db $FF, 66, TAUROS, 67, EXEGGUTOR, 68, ARCANINE, 69, VENUSAUR, 70, GYARADOS, 0
	db $FF, 66, TAUROS, 67, EXEGGUTOR, 68, ARCANINE, 69, CHARIZARD, 70, GYARADOS, 0

; Empty deliberately, like NurseJoyData above: PartySpecPointers carries
; OFFICER_JENNY's real team (Phase 7f).
OfficerJennyData:

ScientistData:
db 14, SPEAROW, 0

GiovanniData:
    ; First Gym
	db $FF, 12, CUBONE, 14, SANDSLASH, 0
    db $FF, 12, DIGLETT, 14, DUGTRIO, 0
    db $FF, 12, SANDSHREW, 14, MAROWAK, 0
    ; Second Gym
	db $FF, 18, ONIX, 21, SANDSLASH, 0
	db $FF, 18, RHYHORN, 21, DUGTRIO, 0
	db $FF, 18, MEOWTH, 21, MAROWAK, 0
    ; Third Gym
	db $FF, 21, NIDORAN_M, 18, ONIX, 24, RHYDON, 0
	db $FF, 21, DIGLETT, 18, GEODUDE, 24, NIDOKING, 0
	db $FF, 21, NIDORAN_F, 18, RHYHORN, 24, PERSIAN, 0
    ; Fourth Gym
	db $FF, 29, PERSIAN, 24, ONIX, 29, RHYDON, 0
	db $FF, 29, NIDOQUEEN, 24, DUGTRIO, 29, GOLEM, 0
	db $FF, 29, GOLEM, 24, MAROWAK, 29, NIDOKING, 0
    ; Fifth Gym
	db $FF, 37, SANDSLASH, 39, EXEGGCUTE, 37, HITMONCHAN, 43, RHYDON, 0
	db $FF, 37, GRAVELER, 39, DUGTRIO, 37, ONIX, 43, NIDOKING, 0
	db $FF, 37, MAROWAK, 39, NIDOQUEEN, 37, HITMONLEE, 43, PERSIAN, 0
    ; Sixth Gym
    db $FF, 38, MAROWAK, 37, NIDOKING, 38, MACHAMP, 43, PERSIAN, 0
	db $FF, 38, DUGTRIO, 37, WEEZING, 38, TAUROS, 43, RHYDON, 0
	db $FF, 38, RHYDON, 37, SANDSLASH, 38, ELECTABUZZ, 43, NIDOQUEEN, 0
    ; Seventh Gym
    db $FF, 42, DUGTRIO, 40, CLOYSTER, 42, NIDOQUEEN, 41, DODRIO, 47, RHYDON, 0
	db $FF, 42, NIDOKING, 40, CHARIZARD, 42, RHYDON, 41, PINSIR, 47, PERSIAN, 0
	db $FF, 42, SANDSLASH, 40, ARCANINE, 42, GOLEM, 41, KANGASKHAN, 47, NIDOKING, 0
    ; Eighth Gym
    db $FF, 45, DUGTRIO, 42, NIDOQUEEN, 44, EXEGGUTOR, 45, TAUROS, 47, NIDOKING, 50, RHYDON, 0
	db $FF, 45, GENGAR, 42, DUGTRIO, 44, MOLTRES, 45, RHYDON, 47, NIDOQUEEN, 50, PERSIAN, 0
	db $FF, 45, NIDOKING, 42, ELECTABUZZ, 44, DUGTRIO, 45, GYARADOS, 47, KANGASKHAN, 50, GOLEM, 0

; Rocket Hideout B4F
	db $FF, 25, ONIX, 24, RHYHORN, 29, KANGASKHAN, 0
; Silph Co. 11F
	db $FF, 37, NIDORINO, 35, KANGASKHAN, 37, RHYHORN, 41, NIDOQUEEN, 0
; Viridian Gym
	db $FF, 45, RHYHORN, 42, DUGTRIO, 44, NIDOQUEEN, 45, NIDOKING, 50, RHYDON, 0

RocketData:

CooltrainerMData:

CooltrainerFData:
db 14, SPEAROW, 0
BrunoData:
	spec_covered_stub

BrockData:
	spec_covered_stub

MistyData:
	spec_covered_stub

LtSurgeData:
	spec_covered_stub

ErikaData:
	spec_covered_stub

KogaData:
	spec_covered_stub

BlaineData:
	spec_covered_stub

SabrinaData:
	spec_covered_stub

GentlemanData:
db 14, SPEAROW, 0
Rival2Data:
; SS Anne 2F
	db $FF, 19, PIDGEOTTO, 16, RATICATE, 18, KADABRA, 20, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 19, PIDGEOTTO, 16, RATICATE, 18, KADABRA, 20, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 19, PIDGEOTTO, 16, RATICATE, 18, KADABRA, 20, RIVAL_STARTER_PLACEHOLDER, 0
; Pokémon Tower 2F
	db $FF, 25, PIDGEOTTO, 23, GROWLITHE, 22, EXEGGCUTE, 20, KADABRA, 25, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 25, PIDGEOTTO, 23, GYARADOS, 22, GROWLITHE, 20, KADABRA, 25, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 25, PIDGEOTTO, 23, EXEGGCUTE, 22, GYARADOS, 20, KADABRA, 25, RIVAL_STARTER_PLACEHOLDER, 0
; Silph Co. 7F
	db $FF, 37, PIDGEOT, 38, GROWLITHE, 35, EXEGGCUTE, 35, ALAKAZAM, 40, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 37, PIDGEOT, 38, GYARADOS, 35, GROWLITHE, 35, ALAKAZAM, 40, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 37, PIDGEOT, 38, EXEGGCUTE, 35, GYARADOS, 35, ALAKAZAM, 40, RIVAL_STARTER_PLACEHOLDER, 0
; Route 22
	db $FF, 47, PIDGEOT, 45, RHYHORN, 45, GROWLITHE, 47, EXEGGCUTE, 50, ALAKAZAM, 53, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 47, PIDGEOT, 45, RHYHORN, 45, GYARADOS, 47, GROWLITHE, 50, ALAKAZAM, 53, RIVAL_STARTER_PLACEHOLDER, 0
	db $FF, 47, PIDGEOT, 45, RHYHORN, 45, EXEGGCUTE, 47, GYARADOS, 50, ALAKAZAM, 53, RIVAL_STARTER_PLACEHOLDER, 0

Rival3Data:
	spec_covered_stub

RivalMiniBossData:
	spec_covered_stub

GiovanniMiniBossData:
	spec_covered_stub

KarateMiniBossData:
	spec_covered_stub

LoreleiData:
	spec_covered_stub

ChannelerData:
db 14, SPEAROW, 0
AgathaData:
	spec_covered_stub

LanceData:
	spec_covered_stub

; Elite4OrderTable was moved to custom_functions/final_sequence.asm (the rogue
; bank) so it is same-bank with the code that reads it. A plain ld a,[hl] from
; the rogue bank was reading garbage, making every Elite Four room resolve to
; Lance. This file compiles into a DIFFERENT bank from the rogue bank, so the
; split is still required: it was "Battle Engine 7" (bank $0E) when that bug was
; fixed, and is "Trainer Parties" (bank $39) as of the 2026-09-10 Phase 0b
; relocation.

; Official pret/pokeyellow Jessie & James parties, in donor order. Superseded
; by Phase 7f's PartySpecPointers entry (the three-run Kanto/Johto/Time Warp
; pool from PROCEDURAL_WILD_AREA_PLAN.md's 7f section), which RogueBuildParty
; always finds first, so this authored fallback is kept for reference only and
; is never read by the stage-event cave/forest/facility/cemetery encounter.
JessieJamesData:
	db $FF, 14, EKANS,   14, MEOWTH, 14, KOFFING, 0
	db $FF, 25, KOFFING, 25, MEOWTH, 25, EKANS,   0
	db $FF, 27, MEOWTH,  27, ARBOK,  27, WEEZING, 0
	db $FF, 31, WEEZING, 31, ARBOK,  31, MEOWTH,  0


; Gym-leader expansion: the 8 Johto leaders, Janine, and the two Johto
; Elite Four members. Added 2026-09-10 (Phase 1). Spec-covered stubs, like
; every other leader's and Elite Four member's block (see spec_covered_stub).
FalknerData:
	spec_covered_stub
BugsyData:
	spec_covered_stub
WhitneyData:
	spec_covered_stub
MortyData:
	spec_covered_stub
ChuckData:
	spec_covered_stub
JasmineData:
	spec_covered_stub
PryceData:
	spec_covered_stub
ClairData:
	spec_covered_stub
JanineData:
	spec_covered_stub
WillData:
	spec_covered_stub
KarenData:
	spec_covered_stub
KogaE4Data:
	spec_covered_stub

