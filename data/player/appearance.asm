; Selectable player appearances.
;
; wPlayerAppearance holds an index into PlayerAppearanceTable. Index 0 (RED) is
; the vanilla look and is what a zero-filled new game produces.
;
; THREE BANK INVARIANTS make the accessors below trivial. Every one of them is
; enforced by an ASSERT so a stray INCBIN cannot break them silently:
;   1. overworld sprites -> BANK(RedSprite)    (SECTION "Player Sprites")
;   2. front pics        -> BANK(RedPicFront)  (SECTION "Trainer Pics")
;   3. back pics         -> BANK(RedPicBack)   (SECTION "Player Back Pics")
; This matters because the accessors are reached by farcall from HOME, from the
; battle engine and from the menu banks, and Bankswitch preserves only de — it
; pops bc and clobbers a — so a per-entry bank byte could not be handed back.
;
; Most classes have no walking sprite of their own (their overworld counterpart
; is a battle-only trainer class, or the sprite that exists depicts them riding
; or swimming rather than walking), so they borrow a visually similar one. Those
; substitutions are noted per row.

MACRO player_appearance
; \1 = overworld walking sprite, \2 = battle front pic,
; \3 = battle back pic, \4 = display name
	dw \1
	dw \2
	dw \3
	dw \4
	ASSERT BANK(\1) == BANK(RedSprite),   "player appearance sprite must be in SECTION \"Player Sprites\""
	ASSERT BANK(\2) == BANK(RedPicFront), "player appearance front pic must be in SECTION \"Trainer Pics\""
	ASSERT BANK(\3) == BANK(RedPicBack),  "player appearance back pic must be in SECTION \"Player Back Pics\""
ENDM

DEF PLAYER_APPEARANCE_ENTRY_SIZE EQU 8

PlayerAppearanceTable::
	table_width PLAYER_APPEARANCE_ENTRY_SIZE, PlayerAppearanceTable
	;                  overworld sprite,    front pic,       back pic,      name
	player_appearance RedSprite,          RedPicFront,     RedPicBack,    .red
	player_appearance HikerSprite,        BikerPic,        BikerPicBack,  .biker        ; BikerSprite is a rider on a motorcycle
	player_appearance CooltrainerMSprite, BirdKeeperPic,   BirdKeeperPicBack, .birdKeeper
	player_appearance HikerSprite,        BlackbeltPic,    BlackbeltPicBack, .blackbelt
	player_appearance YoungsterSprite,    BugCatcherPic,   BugCatcherPicBack, .bugCatcher
	player_appearance SuperNerdSprite,    BurglarPic,      RedPicBack,    .burglar
	player_appearance CooltrainerMSprite, CooltrainerMPic, CooltrainerMPicBack, .coolTrainerM
	player_appearance HikerSprite,        CueBallPic,      RedPicBack,    .cueBall
	player_appearance SuperNerdSprite,    EngineerPic,     EngineerPicBack, .engineer
	player_appearance FisherSprite,       FisherPic,       RedPicBack,    .fisherman
	player_appearance GamblerSprite,      GamblerPic,      GamblerPicBack, .gambler
	player_appearance GentlemanSprite,    GentlemanPic,    GentlemanPicBack, .gentleman
	player_appearance HikerSprite,        HikerPic,        RedPicBack,    .hiker
	player_appearance CooltrainerMSprite, JrTrainerMPic,   JrTrainerMPicBack, .jrTrainerM
	player_appearance SuperNerdSprite,    JugglerPic,      RedPicBack,    .juggler
	player_appearance SuperNerdSprite,    PokemaniacPic,   RedPicBack,    .pokemaniac
	player_appearance YoungsterSprite,    PsychicPic,      RedPicBack,    .psychic
	player_appearance RockerSprite,       RockerPic,       RedPicBack,    .rocker
	player_appearance RocketSprite,       RocketPic,       RocketPicBack, .rocket
	player_appearance SailorSprite,       SailorPic,       RedPicBack,    .sailor
	player_appearance ScientistSprite,    ScientistPic,    ScientistPicBack, .scientist
	player_appearance SuperNerdSprite,    SuperNerdPic,    RedPicBack,    .superNerd
	player_appearance CooltrainerMSprite, SwimmerPic,      RedPicBack,    .swimmer      ; SwimmerSprite depicts swimming, not walking
	player_appearance RockerSprite,       TamerPic,        TamerPicBack,  .tamer
	player_appearance YoungsterSprite,    YoungsterPic,    RedPicBack,    .youngster
	; Female entries start here — see FIRST_FEMALE_APPEARANCE.
	player_appearance GreenSprite,        GreenPicFront,   GreenPicBack,  .green
	player_appearance BeautySprite,       BeautyPic,       BeautyPicBack, .beauty
	player_appearance ChannelerSprite,    ChannelerPic,    GreenPicBack,  .channeler
	player_appearance CooltrainerFSprite, JrTrainerFPic,   JrTrainerFPicBack, .jrTrainerF
	player_appearance CooltrainerFSprite, CooltrainerFPic, CooltrainerFPicBack, .coolTrainerF
	player_appearance CooltrainerFSprite, LassPic,         GreenPicBack,  .lass
	; Appended entries (any gender) start here; see PlayerAppearanceSelectOrder.
	player_appearance GamblerSprite,      OldManPic,       OldManPicBack, .oldMan       ; Viridian's old man walks with the Gambler sheet
	assert_table_length NUM_PLAYER_APPEARANCES

; Displayed under the pic on the character-select screen. The textbox there is
; 14 tiles of interior width, so keep every one of these to 14 characters.
.red           db "RED@"
.biker         db "BIKER@"
.birdKeeper    db "BIRD KEEPER@"
.blackbelt     db "BLACKBELT@"
.bugCatcher    db "BUG CATCHER@"
.burglar       db "BURGLAR@"
.coolTrainerM  db "COOLTRAINER♂@"
.cueBall       db "CUE BALL@"
.engineer      db "ENGINEER@"
.fisherman     db "FISHERMAN@"
.gambler       db "GAMBLER@"
.gentleman     db "GENTLEMAN@"
.hiker         db "HIKER@"
.jrTrainerM    db "JR.TRAINER♂@"
.juggler       db "JUGGLER@"
.pokemaniac    db "POKéMANIAC@"
.psychic       db "PSYCHIC@"
.rocker        db "ROCKER@"
.rocket        db "ROCKET@"
.sailor        db "SAILOR@"
.scientist     db "SCIENTIST@"
.superNerd     db "SUPER NERD@"
.swimmer       db "SWIMMER@"
.tamer         db "TAMER@"
.youngster     db "YOUNGSTER@"
.green         db "GREEN@"
.beauty        db "BEAUTY@"
.channeler     db "CHANNELER@"
.jrTrainerF    db "JR.TRAINER♀@"
.coolTrainerF  db "COOLTRAINER♀@"
.lass          db "LASS@"
.oldMan        db "OLD MAN@"

; Common entry point for all four accessors.
; Returns hl = &PlayerAppearanceTable[wPlayerAppearance].
GetPlayerAppearanceEntry:
	ld a, [wPlayerAppearance]
	cp NUM_PLAYER_APPEARANCES
	jr c, .valid
	xor a ; corrupt index (e.g. an SRAM slot from an older layout): fall back to RED
.valid
	ld hl, PlayerAppearanceTable
	ld bc, PLAYER_APPEARANCE_ENTRY_SIZE
	and a
	ret z
.loop
	add hl, bc
	dec a
	jr nz, .loop
	ret

; Each of these returns its pointer in de, and nothing else. de is the only
; register pair Bankswitch preserves, so they are safe to reach by farcall.
; Clobbers a, bc, hl.

GetPlayerWalkSprite:: ; bank is always BANK(RedSprite)
	ld hl, wMovementFlags
	res BIT_RUNNING, [hl]
	ld a, 0
	jr GetPlayerAppearanceField
GetPlayerFrontPic:: ; bank is always BANK(RedPicFront)
	ld a, 2
	jr GetPlayerAppearanceField
GetPlayerBackPic:: ; bank is always BANK(RedPicBack)
	ld a, 4
	jr GetPlayerAppearanceField
GetPlayerAppearanceName:: ; bank is BANK(PlayerAppearanceTable)
	ld a, 6

GetPlayerAppearanceField:
	push af
	call GetPlayerAppearanceEntry
	pop af
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld e, a
	ld d, [hl]
	ret

; Clear the running state whenever directional input stops. Generic player
; appearances need only the state change; Red and Green restore their walk art.
SwitchRunningToWalkingSprites::
	ld hl, wMovementFlags
	bit BIT_RUNNING, [hl]
	ret z
	res BIT_RUNNING, [hl]
	ld a, [wWalkBikeSurfState]
	and a
	ret nz
	ld a, [wPlayerAppearance]
	cp PLAYER_APPEARANCE_RED
	jr z, .loadWalk
	cp PLAYER_APPEARANCE_GREEN
	ret nz
.loadWalk
	call GetPlayerWalkSprite
	ld hl, vNPCSprites
	jp LoadPlayerSpriteGraphicsCommon

LoadRunningPlayerSpriteGraphics:
	ld hl, wMovementFlags
	set BIT_RUNNING, [hl]
	ld a, [wWalkBikeSurfState]
	and a
	ret nz ; surfing keeps its existing sheet
	ld a, [wPlayerAppearance]
	ld de, RedRunSprite
	cp PLAYER_APPEARANCE_RED
	jr z, .load
	ld de, GreenRunSprite
	cp PLAYER_APPEARANCE_GREEN
	ret nz ; every other appearance keeps its walking sheet
.load
	ld hl, vNPCSprites
	jp LoadPlayerSpriteGraphicsCommon


; Character-select screen, reached by farcall from OakSpeech.
;
; Entry state (identical to the ProfOakPic beat earlier in OakSpeech, which is
; why this needs no rWX/rWY/LCDC handling of its own): screen cleared and faded
; out to white, hAutoBGTransferEnabled on, MUSIC_ROUTES2 playing.
; Exit state: wPlayerAppearance committed; screen still showing the chosen pic.
; OakSpeech fades out and clears immediately afterwards.
;
; One front pic is decompressed per keypress. Preloading all NUM_PLAYER_APPEARANCES
; of them is neither possible (there is only one sprite-buffer pair) nor needed.
ChoosePlayerCharacter::
	xor a ; PLAYER_APPEARANCE_RED
	ld [wPlayerAppearance], a
	call .drawPic
	call GBFadeInFromWhite
	ld hl, ChooseCharacterText
	call PrintText
	call .drawName
.inputLoop
	call DelayFrame
	call JoypadLowSensitivity
	ldh a, [hJoy5] ; newly pressed
	ld b, a
	and PAD_A | PAD_LEFT | PAD_RIGHT
	jr z, .inputLoop
	bit B_PAD_A, b
	jr nz, .chosen
	ld a, SFX_TINK
	call PlaySound
; find the current appearance's position in the select order -> c
	ld a, [wPlayerAppearance]
	ld hl, PlayerAppearanceSelectOrder
	ld c, 0
.find
	cp [hl]
	jr z, .found
	inc hl
	inc c
	jr .find ; every index is in the table (test_ai_lair_presentation checks it)
.found
	ld a, c
	bit B_PAD_LEFT, b
	jr nz, .previous
; next, wrapping past the end back to RED
	inc a
	cp NUM_PLAYER_APPEARANCES
	jr c, .lookup
	xor a
	jr .lookup
.previous
; previous, wrapping past RED round to the last entry
	and a
	jr nz, .noWrap
	ld a, NUM_PLAYER_APPEARANCES
.noWrap
	dec a
.lookup
	ld hl, PlayerAppearanceSelectOrder
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	ld [wPlayerAppearance], a
	call .drawPic
	call .drawName
	jr .inputLoop

.chosen
	ld a, SFX_PRESS_AB
	call PlaySound
	ret

.drawPic
	call GetPlayerFrontPic ; -> de
	lb bc, BANK(RedPicFront), $00 ; 0 = centred, at (6,4)
	ASSERT BANK(RedPicFront) == BANK(GreenPicFront)
	predef_jump DisplayPicCenteredOrUpperRight

.drawName
; Overwrite the interior of the text box PrintText left on screen with the
; current class name, leaving its border intact. The box spans rows 12-17 with
; borders on 12 and 17, and PrintText writes its two lines at rows 14 and 16, so
; the whole of rows 13-16 has to be cleared or the prompt's second line survives.
	hlcoord 1, 13
	lb bc, 4, 18
	call ClearScreenArea
	call GetPlayerAppearanceName ; -> de
	hlcoord 2, 14
	jp PlaceString

ChooseCharacterText:
	text_far _ChooseCharacterText
	text_end

; Order the character-select screen cycles through: males, then females. The
; PLAYER_APPEARANCE_* values are saved, so new entries are appended there and
; slotted into place here instead. Must hold every index exactly once, RED first
; (ChoosePlayerCharacter starts on it).
PlayerAppearanceSelectOrder:
	table_width 1
	db PLAYER_APPEARANCE_RED
	db PLAYER_APPEARANCE_BIKER
	db PLAYER_APPEARANCE_BIRD_KEEPER
	db PLAYER_APPEARANCE_BLACKBELT
	db PLAYER_APPEARANCE_BUG_CATCHER
	db PLAYER_APPEARANCE_BURGLAR
	db PLAYER_APPEARANCE_COOLTRAINER_M
	db PLAYER_APPEARANCE_CUE_BALL
	db PLAYER_APPEARANCE_ENGINEER
	db PLAYER_APPEARANCE_FISHERMAN
	db PLAYER_APPEARANCE_GAMBLER
	db PLAYER_APPEARANCE_GENTLEMAN
	db PLAYER_APPEARANCE_HIKER
	db PLAYER_APPEARANCE_JR_TRAINER_M
	db PLAYER_APPEARANCE_JUGGLER
	db PLAYER_APPEARANCE_OLD_MAN
	db PLAYER_APPEARANCE_POKEMANIAC
	db PLAYER_APPEARANCE_PSYCHIC
	db PLAYER_APPEARANCE_ROCKER
	db PLAYER_APPEARANCE_ROCKET
	db PLAYER_APPEARANCE_SAILOR
	db PLAYER_APPEARANCE_SCIENTIST
	db PLAYER_APPEARANCE_SUPER_NERD
	db PLAYER_APPEARANCE_SWIMMER
	db PLAYER_APPEARANCE_TAMER
	db PLAYER_APPEARANCE_YOUNGSTER
	db PLAYER_APPEARANCE_GREEN
	db PLAYER_APPEARANCE_BEAUTY
	db PLAYER_APPEARANCE_CHANNELER
	db PLAYER_APPEARANCE_JR_TRAINER_F
	db PLAYER_APPEARANCE_COOLTRAINER_F
	db PLAYER_APPEARANCE_LASS
	assert_table_length NUM_PLAYER_APPEARANCES
