SECTION "NULL", ROM0
NULL::

INCLUDE "home/header.asm"


SECTION "High Home", ROM0

INCLUDE "home/lcd.asm"
INCLUDE "home/clear_sprites.asm"
INCLUDE "home/copy.asm"
; Moved from "Home" below: the Shin/Yellow-style audio-engine import
; (SHIN_IMPORT_PLAN.md Phase 1.1) added GetNextMusicByte/DetermineAudioFunction
; to home/audio.asm, overflowing "Home" ROM0 by 5 bytes in the _DEBUG build
; ("Home" only had 3 bytes free - see WRAM_BIBLE.md SS J1). array.asm (~17B,
; leaf, no callers outside its own two routines) is the documented cheap first
; move: both "High Home" and "Home" are always-mapped bank 0, so this is a
; free, zero-risk ROM0-to-ROM0 relocation (the HOME->ROMX bank-switch landmine
; does not apply here).
INCLUDE "home/array.asm"
; Same reason and same free, zero-risk ROM0-to-ROM0 relocation as array.asm
; above: the Shin Red import Phase 2 audio/SFX fixes (badge SFX bank force,
; warp-tile thud relocation, zero-delay-text SFX flag) overflowed "Home" by
; 11+ bytes. CountSetBits is a self-contained leaf (no calls out, only
; touches wNumSetBits) with no dependency on which ROM0 sub-section it lives
; in, so it moved here rather than trimming any of the new logic.
INCLUDE "home/count_set_bits.asm"
; Same free ROM0-to-ROM0 relocation as the two above (WRAM_BIBLE.md SS J1), to fund
; the badge/key-item fanfare branch in TextCommand_SOUND. HasEnoughMoney/
; HasEnoughCoins are 22 bytes of pure leaf - each is 4 instructions ending in
; jp StringCmp, nothing falls through into or out of them, and StringCmp stays
; in "Home" (both halves are the always-mapped bank 0, so the call is unaffected).
INCLUDE "home/money.asm"


SECTION "Home", ROM0

INCLUDE "home/cgb_speed.asm"

INCLUDE "home/start.asm"
INCLUDE "home/joypad.asm"

INCLUDE "data/maps/map_header_pointers.asm"

INCLUDE "home/overworld.asm"
INCLUDE "home/pokemon.asm"
INCLUDE "home/print_bcd.asm"
INCLUDE "home/pics.asm"

INCLUDE "data/tilesets/collision_tile_ids.asm"

INCLUDE "home/copy2.asm"
INCLUDE "home/text.asm"
INCLUDE "home/vcopy.asm"
INCLUDE "home/init.asm"
INCLUDE "home/vblank.asm"
INCLUDE "home/fade.asm"
INCLUDE "home/serial.asm"
INCLUDE "home/timer.asm"
INCLUDE "home/audio.asm"
INCLUDE "home/update_sprites.asm"

INCLUDE "data/items/marts.asm"

INCLUDE "home/overworld_text.asm"
INCLUDE "home/uncompress.asm"
INCLUDE "home/reset_player_sprite.asm"
INCLUDE "home/fade_audio.asm"
INCLUDE "home/text_script.asm"
INCLUDE "home/start_menu.asm"
INCLUDE "home/inventory.asm"
INCLUDE "home/list_menu.asm"
INCLUDE "home/names.asm"
INCLUDE "home/reload_tiles.asm"
INCLUDE "home/item.asm"
INCLUDE "home/textbox.asm"
INCLUDE "home/npc_movement.asm"
INCLUDE "home/trainers.asm"
INCLUDE "home/map_objects.asm"
INCLUDE "home/trainers2.asm"
INCLUDE "home/bankswitch.asm"
INCLUDE "home/yes_no.asm"
INCLUDE "home/pathfinding.asm"
INCLUDE "home/load_font.asm"
INCLUDE "home/tilemap.asm"
INCLUDE "home/delay.asm"
INCLUDE "home/names2.asm"
INCLUDE "home/item_price.asm"
INCLUDE "home/copy_string.asm"
INCLUDE "home/joypad2.asm"
INCLUDE "home/math.asm"
INCLUDE "home/print_text.asm"
INCLUDE "home/move_mon.asm"
INCLUDE "home/compare.asm"
INCLUDE "home/oam.asm"
INCLUDE "home/window.asm"
INCLUDE "home/print_num.asm"
INCLUDE "home/array2.asm"
INCLUDE "home/palettes.asm"
INCLUDE "home/reload_sprites.asm"
INCLUDE "home/give.asm"
INCLUDE "home/random.asm"
INCLUDE "home/predef.asm"
INCLUDE "home/hidden_events.asm"
INCLUDE "home/predef_text.asm"
