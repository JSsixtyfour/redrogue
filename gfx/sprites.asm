; Every overworld sprite the player can be assigned by PlayerAppearanceTable
; (data/player/appearance.asm) lives here, together with RedBikeSprite and
; SeelSprite. Reason: LoadPlayerSpriteGraphicsCommon (home/overworld.asm) copies
; the walking, bike AND surf sheets with a single hardcoded `BANK(RedSprite)`.
; Keeping all of them in one section makes that constant correct for every
; player appearance, so only the *pointer* has to vary at runtime and the HOME
; routine needs no bank plumbing.
; These sheets are still ordinary NPC sprites too — SpriteSheetPointerTable emits
; `db BANK(\1)` per entry, so NPC use of them re-resolves automatically.
; ADDING A NEW PLAYER APPEARANCE: its sprite must be moved into this section.
SECTION "Player Sprites", ROMX

RedSprite::              INCBIN "gfx/sprites/red.2bpp"
RedRunSprite::           INCBIN "gfx/sprites/red_run.2bpp" ; ported from Pokemon Yume
RedBikeSprite::          INCBIN "gfx/sprites/red_bike.2bpp"
SeelSprite::             INCBIN "gfx/sprites/seel.2bpp"
GreenSprite::            INCBIN "gfx/sprites/green.2bpp" ; ported from pret-based Pokemon Yume
GreenRunSprite::         INCBIN "gfx/sprites/green_run.2bpp" ; ported from Pokemon Yume
	ASSERT BANK(RedRunSprite) == BANK(RedSprite)
	ASSERT BANK(GreenRunSprite) == BANK(RedSprite)
BeautySprite::           INCBIN "gfx/sprites/beauty.2bpp"
ChannelerSprite::        INCBIN "gfx/sprites/channeler.2bpp"
CooltrainerFSprite::     INCBIN "gfx/sprites/cooltrainer_f.2bpp"
CooltrainerMSprite::     INCBIN "gfx/sprites/cooltrainer_m.2bpp"
FisherSprite::           INCBIN "gfx/sprites/fisher.2bpp"
GamblerSprite::          INCBIN "gfx/sprites/gambler.2bpp"
GentlemanSprite::        INCBIN "gfx/sprites/gentleman.2bpp"
HikerSprite::            INCBIN "gfx/sprites/hiker.2bpp"
RockerSprite::           INCBIN "gfx/sprites/rocker.2bpp"
RocketSprite::           INCBIN "gfx/sprites/rocket.2bpp"
SailorSprite::           INCBIN "gfx/sprites/sailor.2bpp"
ScientistSprite::        INCBIN "gfx/sprites/scientist.2bpp"
SuperNerdSprite::        INCBIN "gfx/sprites/super_nerd.2bpp"
YoungsterSprite::        INCBIN "gfx/sprites/youngster.2bpp"


SECTION "NPC Sprites 1", ROMX

SwimmerSprite::          INCBIN "gfx/sprites/swimmer.2bpp"
SafariZoneWorkerSprite:: INCBIN "gfx/sprites/safari_zone_worker.2bpp"
GymGuideSprite::         INCBIN "gfx/sprites/gym_guide.2bpp"
GrampsSprite::           INCBIN "gfx/sprites/gramps.2bpp"
ClerkSprite::            INCBIN "gfx/sprites/clerk.2bpp"
FishingGuruSprite::      INCBIN "gfx/sprites/fishing_guru.2bpp"
GrannySprite::           INCBIN "gfx/sprites/granny.2bpp"
NurseSprite::            INCBIN "gfx/sprites/nurse.2bpp"
LinkReceptionistSprite:: INCBIN "gfx/sprites/link_receptionist.2bpp"
SilphPresidentSprite::   INCBIN "gfx/sprites/silph_president.2bpp"
SilphWorkerMSprite::     INCBIN "gfx/sprites/silph_worker_m.2bpp"
WardenSprite::           INCBIN "gfx/sprites/warden.2bpp"
CaptainSprite::          INCBIN "gfx/sprites/captain.2bpp"
KogaSprite::             INCBIN "gfx/sprites/koga.2bpp"
GuardSprite::            INCBIN "gfx/sprites/guard.2bpp"
PokeBallSprite::         INCBIN "gfx/sprites/poke_ball.2bpp"
FossilSprite::           INCBIN "gfx/sprites/fossil.2bpp"
BoulderSprite::          INCBIN "gfx/sprites/boulder.2bpp"
PaperSprite::            INCBIN "gfx/sprites/paper.2bpp"
PokedexSprite::          INCBIN "gfx/sprites/pokedex.2bpp"
ClipboardSprite::        INCBIN "gfx/sprites/clipboard.2bpp"
SnorlaxSprite::          INCBIN "gfx/sprites/snorlax.2bpp"
OldAmberSprite::         INCBIN "gfx/sprites/old_amber.2bpp"
GamblerAsleepSprite::    INCBIN "gfx/sprites/gambler_asleep.2bpp"


SECTION "NPC Sprites 2", ROMX

BlueSprite::             INCBIN "gfx/sprites/blue.2bpp"
OakSprite::              INCBIN "gfx/sprites/oak.2bpp"
MonsterSprite::          INCBIN "gfx/sprites/monster.2bpp"
LittleGirlSprite::       INCBIN "gfx/sprites/little_girl.2bpp"
BirdSprite::             INCBIN "gfx/sprites/bird.2bpp"
MiddleAgedManSprite::    INCBIN "gfx/sprites/middle_aged_man.2bpp"
GirlSprite::             INCBIN "gfx/sprites/girl.2bpp"
DaisySprite::            INCBIN "gfx/sprites/daisy.2bpp"
BikerSprite::            INCBIN "gfx/sprites/biker.2bpp"
CookSprite::             INCBIN "gfx/sprites/cook.2bpp"
BikeShopClerkSprite::    INCBIN "gfx/sprites/bike_shop_clerk.2bpp"
MrFujiSprite::           INCBIN "gfx/sprites/mr_fuji.2bpp"
GiovanniSprite::         INCBIN "gfx/sprites/giovanni.2bpp"
WaiterSprite::           INCBIN "gfx/sprites/waiter.2bpp"
SilphWorkerFSprite::     INCBIN "gfx/sprites/silph_worker_f.2bpp"
MiddleAgedWomanSprite::  INCBIN "gfx/sprites/middle_aged_woman.2bpp"
BrunetteGirlSprite::     INCBIN "gfx/sprites/brunette_girl.2bpp"
LanceSprite::            INCBIN "gfx/sprites/lance.2bpp"
MomSprite::              INCBIN "gfx/sprites/mom.2bpp"
BaldingGuySprite::       INCBIN "gfx/sprites/balding_guy.2bpp"
LittleBoySprite::        INCBIN "gfx/sprites/little_boy.2bpp"
GameboyKidSprite::       INCBIN "gfx/sprites/gameboy_kid.2bpp"
FairySprite::            INCBIN "gfx/sprites/fairy.2bpp"
AgathaSprite::           INCBIN "gfx/sprites/agatha.2bpp"
BrunoSprite::            INCBIN "gfx/sprites/bruno.2bpp"
LoreleiSprite::          INCBIN "gfx/sprites/lorelei.2bpp"


SECTION "Room Sprites", ROMX

; Promoted still-sprite decorations — 12-"tile" walking sheets built from the
; existing 4-tile image. A "12" entry in SpriteSheetPointerTable is consumed
; as TWO 192-byte loads by engine/overworld/map_sprites.asm's
; .loadStillTilePattern path (12 tiles * TILE_SIZE = 192 bytes per load, see
; macros/gfx.asm's `tiles` EQUS), i.e. 384 bytes / 24 raw 8x8 tiles total —
; confirmed against BirdSprite/FairySprite/MonsterSprite/SeelSprite, all real
; 16x96px (384-byte) art despite being single-Pokemon "12" entries. The
; source 4-tile (64-byte) image is repeated SIX times, not three, to supply
; the full 384 bytes; they never animate (STAY), so every repeated frame
; renders identically to the source art.
VoltorbDecoSprite::
	INCBIN "gfx/sprites/poke_ball.2bpp"
	INCBIN "gfx/sprites/poke_ball.2bpp"
	INCBIN "gfx/sprites/poke_ball.2bpp"
	INCBIN "gfx/sprites/poke_ball.2bpp"
	INCBIN "gfx/sprites/poke_ball.2bpp"
	INCBIN "gfx/sprites/poke_ball.2bpp"

OmanyteDecoSprite::
	INCBIN "gfx/sprites/fossil.2bpp"
	INCBIN "gfx/sprites/fossil.2bpp"
	INCBIN "gfx/sprites/fossil.2bpp"
	INCBIN "gfx/sprites/fossil.2bpp"
	INCBIN "gfx/sprites/fossil.2bpp"
	INCBIN "gfx/sprites/fossil.2bpp"

SnorlaxDecoSprite::
	INCBIN "gfx/sprites/snorlax.2bpp"
	INCBIN "gfx/sprites/snorlax.2bpp"
	INCBIN "gfx/sprites/snorlax.2bpp"
	INCBIN "gfx/sprites/snorlax.2bpp"
	INCBIN "gfx/sprites/snorlax.2bpp"
	INCBIN "gfx/sprites/snorlax.2bpp"

; Imported from pret/pokeyellow (gfx/sprites/pikachu.png, gfx/sprites/chansey.png),
; converted locally with this repo's rgbgfx pipeline (--colors dmg).
PikachuSprite:: ; genuine 16x96px art, 384 bytes / 24 raw tiles — no padding needed
	INCBIN "gfx/sprites/pikachu.2bpp"

ChanseySprite:: ; pokeyellow's source art is only 16x48px (192 bytes / 12 raw
                ; tiles) — half of what a "12" entry consumes here (see note
                ; above). Repeated once to reach the required 384 bytes.
	INCBIN "gfx/sprites/chansey.2bpp"
	INCBIN "gfx/sprites/chansey.2bpp"

; Official pret/pokeyellow walking sheets. No map or player appearance uses them.
; NPC SpriteSheetPointerTable carries the source bank for each sheet.
SECTION "Jessie James Sprites", ROMX, BANK[$2C]
JessieSprite:: INCBIN "gfx/sprites/jessie.2bpp"
JamesSprite::  INCBIN "gfx/sprites/james.2bpp"

; Source-faithful pret/pokeyellow sheet. Yellow stores 12 raw tiles (192 B),
; while this fork's walking-sheet loader consumes 384 B for a 12-tile entry.
; Repeat the authored poses exactly as the existing Chansey import does.
OfficerJennySprite::
	INCBIN "gfx/sprites/officer_jenny.2bpp"
	INCBIN "gfx/sprites/officer_jenny.2bpp"

; Species-specific overworld sheets imported from Pokemon Yellow Legacy
; commit 15169d137e2ef778e8765f7f3381acc4093dc169. The three donor half-sheets
; were expanded to the full 16x96 format before conversion.
SECTION "Yellow Legacy Pokemon Sprites", ROMX, BANK[$3E]
DoduoSprite::    INCBIN "gfx/sprites/doduo.2bpp"
PsyduckSprite::  INCBIN "gfx/sprites/psyduck.2bpp"
NidorinoSprite:: INCBIN "gfx/sprites/nidorino.2bpp"
KabutoSprite::   INCBIN "gfx/sprites/kabuto.2bpp"
SpearowSprite::  INCBIN "gfx/sprites/spearow.2bpp"
CuboneSprite::   INCBIN "gfx/sprites/cubone.2bpp"
ArticunoSprite:: INCBIN "gfx/sprites/articuno.2bpp"
ZapdosSprite::   INCBIN "gfx/sprites/zapdos.2bpp"
MoltresSprite::  INCBIN "gfx/sprites/moltres.2bpp"
MewtwoSprite::   INCBIN "gfx/sprites/mewtwo.2bpp"

; Yellow Legacy batch 2 (2026-09-25), from Pokemon_Yellow_Legacy main. The
; walking-range loader always reads 384 bytes (sheet, then sheet + $C0 for the
; walk frames), so a standing-poses-only 16x48 sheet is included twice and a
; one-pose 16x16 sheet six times, as ChanseySprite and the Room Sprites do.
; INCBINs stay literal: the Makefile's dependency scan reads them as text.
FearowSprite::
	INCBIN "gfx/sprites/fearow.2bpp"
	ASSERT @ - FearowSprite == 24 tiles
KangaskhanSprite::
	INCBIN "gfx/sprites/kangaskhan.2bpp"
	ASSERT @ - KangaskhanSprite == 24 tiles
LaprasSprite::
	INCBIN "gfx/sprites/lapras.2bpp"
	ASSERT @ - LaprasSprite == 24 tiles
MachopSprite::
	INCBIN "gfx/sprites/machop.2bpp"
	ASSERT @ - MachopSprite == 24 tiles
MewSprite::
	INCBIN "gfx/sprites/mew.2bpp"
	ASSERT @ - MewSprite == 24 tiles
NidoranFSprite::
	INCBIN "gfx/sprites/nidoran_f.2bpp"
	ASSERT @ - NidoranFSprite == 24 tiles
PidgeySprite::
	INCBIN "gfx/sprites/pidgey.2bpp"
	ASSERT @ - PidgeySprite == 24 tiles
SlowpokeSprite::
	INCBIN "gfx/sprites/slowpoke.2bpp"
	ASSERT @ - SlowpokeSprite == 24 tiles

VaporeonSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/vaporeon.2bpp"
	INCBIN "gfx/sprites/vaporeon.2bpp"
	ASSERT @ - VaporeonSprite == 24 tiles
BulbasaurSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/bulbasaur.2bpp"
	INCBIN "gfx/sprites/bulbasaur.2bpp"
	ASSERT @ - BulbasaurSprite == 24 tiles
ClefairySprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/clefairy.2bpp"
	INCBIN "gfx/sprites/clefairy.2bpp"
	ASSERT @ - ClefairySprite == 24 tiles
JigglypuffSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/jigglypuff.2bpp"
	INCBIN "gfx/sprites/jigglypuff.2bpp"
	ASSERT @ - JigglypuffSprite == 24 tiles
MachokeSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/machoke.2bpp"
	INCBIN "gfx/sprites/machoke.2bpp"
	ASSERT @ - MachokeSprite == 24 tiles
MeowthSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/meowth.2bpp"
	INCBIN "gfx/sprites/meowth.2bpp"
	ASSERT @ - MeowthSprite == 24 tiles
MrMimeSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/mr_mime.2bpp"
	INCBIN "gfx/sprites/mr_mime.2bpp"
	ASSERT @ - MrMimeSprite == 24 tiles
NidoranMSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/nidoran_m.2bpp"
	INCBIN "gfx/sprites/nidoran_m.2bpp"
	ASSERT @ - NidoranMSprite == 24 tiles
OddishSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/oddish.2bpp"
	INCBIN "gfx/sprites/oddish.2bpp"
	ASSERT @ - OddishSprite == 24 tiles
PidgeotSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/pidgeot.2bpp"
	INCBIN "gfx/sprites/pidgeot.2bpp"
	ASSERT @ - PidgeotSprite == 24 tiles
PoliwrathSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/poliwrath.2bpp"
	INCBIN "gfx/sprites/poliwrath.2bpp"
	ASSERT @ - PoliwrathSprite == 24 tiles
SandshrewSprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/sandshrew.2bpp"
	INCBIN "gfx/sprites/sandshrew.2bpp"
	ASSERT @ - SandshrewSprite == 24 tiles
Seel2Sprite:: ; standing poses only, repeated as the walk frames
	INCBIN "gfx/sprites/seel2.2bpp"
	INCBIN "gfx/sprites/seel2.2bpp"
	ASSERT @ - Seel2Sprite == 24 tiles

; Bank $3E is full after the sheets above; the one-pose sheets follow in $37.
SECTION "Yellow Legacy Pokemon Sprites 2", ROMX, BANK[$37]
JolteonSprite:: ; one pose, repeated for all six frames
	INCBIN "gfx/sprites/jolteon.2bpp"
	INCBIN "gfx/sprites/jolteon.2bpp"
	INCBIN "gfx/sprites/jolteon.2bpp"
	INCBIN "gfx/sprites/jolteon.2bpp"
	INCBIN "gfx/sprites/jolteon.2bpp"
	INCBIN "gfx/sprites/jolteon.2bpp"
	ASSERT @ - JolteonSprite == 24 tiles
FlareonSprite:: ; one pose, repeated for all six frames
	INCBIN "gfx/sprites/flareon.2bpp"
	INCBIN "gfx/sprites/flareon.2bpp"
	INCBIN "gfx/sprites/flareon.2bpp"
	INCBIN "gfx/sprites/flareon.2bpp"
	INCBIN "gfx/sprites/flareon.2bpp"
	INCBIN "gfx/sprites/flareon.2bpp"
	ASSERT @ - FlareonSprite == 24 tiles
WigglytuffSprite:: ; one pose, repeated for all six frames
	INCBIN "gfx/sprites/wigglytuff.2bpp"
	INCBIN "gfx/sprites/wigglytuff.2bpp"
	INCBIN "gfx/sprites/wigglytuff.2bpp"
	INCBIN "gfx/sprites/wigglytuff.2bpp"
	INCBIN "gfx/sprites/wigglytuff.2bpp"
	INCBIN "gfx/sprites/wigglytuff.2bpp"
	ASSERT @ - WigglytuffSprite == 24 tiles
