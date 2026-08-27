SECTION "bank1", ROMX

INCLUDE "data/sprites/facings.asm"
INCLUDE "engine/events/black_out.asm"
INCLUDE "data/pokemon/mew.asm"
INCLUDE "engine/battle/safari_zone.asm"
INCLUDE "engine/movie/title.asm"
INCLUDE "engine/pokemon/load_mon_data.asm"
INCLUDE "data/items/prices.asm"
INCLUDE "data/items/names.asm"
; Shin Red import Phase 6: data/text/unused_names.asm moved to its own floating
; section below. "bank1" overflowed in the debug build when
; CheckSpriteAvailability gained its rounded-up tile test.
INCLUDE "engine/gfx/sprite_oam.asm"
INCLUDE "engine/gfx/oam_dma.asm"
INCLUDE "engine/link/print_waiting_text.asm"
INCLUDE "engine/overworld/sprite_collisions.asm"
INCLUDE "engine/debug/debug_menu.asm"
INCLUDE "engine/overworld/movement.asm"
INCLUDE "engine/link/cable_club.asm"
INCLUDE "engine/menus/main_menu.asm"
INCLUDE "engine/movie/oak_speech/oak_speech.asm"
INCLUDE "engine/overworld/special_warps.asm"
INCLUDE "engine/debug/debug_party.asm"
INCLUDE "engine/menus/naming_screen.asm"
INCLUDE "engine/movie/oak_speech/oak_speech2.asm"
INCLUDE "engine/items/subtract_paid_money.asm"
INCLUDE "engine/menus/swap_items.asm"
INCLUDE "engine/events/pokemart.asm"
INCLUDE "engine/pokemon/learn_move.asm"
INCLUDE "engine/events/pokecenter.asm"
INCLUDE "engine/events/set_blackout_map.asm"
INCLUDE "engine/menus/display_text_id_init.asm"
INCLUDE "engine/menus/draw_start_menu.asm"
INCLUDE "engine/link/cable_club_npc.asm"
INCLUDE "engine/menus/text_box.asm"
INCLUDE "engine/menus/players_pc.asm"
INCLUDE "engine/events/display_pokedex.asm"


; Declares its own floating SECTION (see the file header). Kept out of "bank1",
; which has almost no slack: the only thing in bank1 that references it is the
; SELECT hook in DisplayOptionMenu, and that reaches it by farcall.
INCLUDE "engine/menus/extra_options.asm"

; Declares its own floating SECTION (see the file header). Reached only by
; callfar (from engine/battle/core.asm and engine/battle/experience.asm), so
; it doesn't need to live in any particular bank.
INCLUDE "engine/battle/exp_bar.asm"

; Declares its own floating SECTION (see the file header). Reached only by
; farcall (from scripts/Daycare.asm and scripts/IndigoPlateauLobby.asm), so it
; doesn't need to live in any particular bank.
INCLUDE "engine/events/daycare_upgrade.asm"

; Declares its own floating SECTION (see the file header). Kept out of
; "Battle Core", which had no room left; reached by farcall from
; engine/battle/effects.asm.
INCLUDE "custom_functions/apply_self_stat_penalty.asm"
INCLUDE "custom_functions/apply_single_badge_boost.asm"
INCLUDE "engine/battle/ai/ai_core.asm"

; Pinned to bank $2C (see the file header). Switching is decided once per
; TURN, not once per move, so unlike every AILayer* routine it is not forced
; into bank $0E by the scoring-loop dispatch.
INCLUDE "engine/battle/ai/ai_switching.asm"

; Also pinned to bank $2C, and a separate section from the switching engine so
; either can be relocated without dragging the other. The plan system's bank
; $0E half is INCLUDEd into trainer_ai.asm as engine/battle/ai/ai_plan.asm.
INCLUDE "engine/battle/ai/ai_plans.asm"

; Also pinned to bank $2C. Enemy trainer DV/stat-exp rolling (AI Overhaul
; Phase 6) - moved out of engine/pokemon/add_mon.asm (bank $03, only 38
; bytes free) into its own section here; add_mon.asm keeps only the minimal
; call sites.
INCLUDE "engine/battle/ai/ai_roster.asm"

; Also pinned to bank $2C. AI Overhaul Phase 7 (fair play): records which
; player moves have been revealed. Its hook site, engine/battle/core.asm's
; PlayerCanExecuteMove, is in Battle Core (bank $0F, CLOSED per ROM_BIBLE.md),
; so only an 8-byte farcall lives there; the real logic lives here instead.
INCLUDE "engine/battle/ai/ai_fairplay.asm"

; FIGHT 2 is debug-only and too large for the nearly-full fixed bank1 section.
; Its only bank1 callers use farcall, so keep it in a floating section.
INCLUDE "engine/debug/debug_fight2.asm"

; RemovePokemon's HOME stub already uses jpfar, and the implementation only
; accesses RAM and its own local labels. Keep this infrequent routine out of
; bank $01 so per-frame 60 FPS sprite timing can remain in its native bank.
SECTION "Remove Pokemon", ROMX, BANK[$12]
INCLUDE "engine/pokemon/remove_mon.asm"


; Shin Red import Phase 6: moved out of the fixed "bank1" section, which
; overflowed by $27 bytes in the debug build once CheckSpriteAvailability gained
; its rounded-up tile test. This is leftover Japanese badge/ranking name data
; from vanilla with ZERO references anywhere in the tree, so it is entirely
; bank-independent. Relocated rather than deleted so nothing is lost.
SECTION "Unused Names", ROMX
INCLUDE "data/text/unused_names.asm"

SECTION "Pick Up Item", ROMX
INCLUDE "engine/events/pick_up_item.asm"

; Shin Red import Phase 5: same relocation reasoning as "Drain HP Effect"
; below - "bank3" (item_effects.asm) had zero free bytes, and this routine's
; only entry point is the ItemUsePokeFlute stub left in item_effects.asm.
SECTION "Poke Flute Item Use", ROMX
INCLUDE "engine/items/item_effects_pokeflute.asm"

; Moved out of "bank1" (which overflowed when the Player PC gained its
; CARTRIDGE option) into its own floating section. Safe to relocate: its only
; entry point is `jpfar DrainHPEffect_` from effects.asm, and every symbol it
; references is either HOME (PrintText), a WRAM address, or one of its own
; text stubs that moves with it - no same-bank dependencies.
SECTION "Drain HP Effect", ROMX
INCLUDE "engine/battle/move_effects/drain_hp.asm"

SECTION "bank3", ROMX

INCLUDE "engine/joypad.asm"
INCLUDE "data/maps/songs.asm"
INCLUDE "data/maps/map_header_banks.asm"
INCLUDE "engine/overworld/clear_variables.asm"
INCLUDE "engine/overworld/player_state.asm"
INCLUDE "engine/events/poison.asm"
INCLUDE "engine/overworld/tilesets.asm"
INCLUDE "data/maps/toggleable_objects.asm"
INCLUDE "engine/overworld/field_move_messages.asm"
INCLUDE "engine/items/inventory.asm"
INCLUDE "engine/overworld/wild_mons.asm"
INCLUDE "engine/items/item_effects.asm"
INCLUDE "engine/menus/draw_badges.asm"
INCLUDE "engine/overworld/update_map.asm"
INCLUDE "engine/overworld/cut.asm"
INCLUDE "engine/overworld/toggleable_objects.asm"
INCLUDE "engine/overworld/push_boulder.asm"
INCLUDE "engine/pokemon/add_mon.asm"
INCLUDE "engine/flag_action.asm"
INCLUDE "engine/events/heal_party.asm"
INCLUDE "engine/math/bcd.asm"
INCLUDE "engine/movie/oak_speech/init_player_data.asm"
INCLUDE "engine/overworld/pathfinding.asm"
INCLUDE "engine/gfx/hp_bar.asm"
INCLUDE "engine/events/hidden_events/bookshelves.asm"
INCLUDE "engine/events/hidden_events/indigo_plateau_statues.asm"
INCLUDE "engine/events/hidden_events/book_or_sculpture.asm"
INCLUDE "engine/events/hidden_events/elevator.asm"
INCLUDE "engine/events/hidden_events/town_map.asm"
INCLUDE "engine/events/hidden_events/pokemon_stuff.asm"


; Relocated from bank $03. GetQuantityOfItemInBag is dispatched through the
; bank-aware predef table; this file's remaining cross-bank dependencies use
; HOME helpers or farcall.
SECTION "Bag Item Quantity", ROMX

INCLUDE "engine/items/get_bag_item_quantity.asm"


SECTION "Font Graphics", ROMX

INCLUDE "gfx/font.asm"


; Yume's Pokedex stat bars are loaded into a temporary BG tile range through
; BANK(), so keep their 17-tile payload out of the nearly full font bank.
SECTION "Pokedex Stats Bar Graphics", ROMX

StatsBarGraphics: INCBIN "gfx/pokedex/stats_bar.2bpp"
StatsBarGraphicsEnd:


SECTION "Battle Engine 1", ROMX

INCLUDE "engine/overworld/is_player_just_outside_map.asm"
INCLUDE "engine/pokemon/status_screen.asm"
INCLUDE "engine/menus/party_menu.asm"
INCLUDE "gfx/player.asm"
; Shin Red import Phase 6: engine/overworld/turn_sprite.asm
; (UpdateSpriteFacingOffsetAndDelayMovement) is no longer assembled. Its only caller
; was DisplayTextID in home/text_script.asm, removed this phase per Pokemon Yellow and
; shinpokered. The file is left in the tree for reference.
;INCLUDE "engine/overworld/turn_sprite.asm"
INCLUDE "engine/menus/start_sub_menus.asm"
INCLUDE "engine/items/tms.asm"
INCLUDE "engine/battle/end_of_battle.asm"
INCLUDE "engine/battle/wild_encounters.asm"
INCLUDE "engine/battle/move_effects/recoil.asm"
INCLUDE "engine/battle/move_effects/conversion.asm"
INCLUDE "engine/battle/move_effects/haze.asm"
INCLUDE "engine/battle/get_trainer_name.asm"
INCLUDE "engine/math/random.asm"


SECTION "Battle Engine 2", ROMX

INCLUDE "engine/gfx/load_pokedex_tiles.asm"
INCLUDE "engine/overworld/map_sprites.asm"
INCLUDE "engine/overworld/emotion_bubbles.asm"
INCLUDE "engine/events/evolve_trade.asm"
INCLUDE "engine/battle/move_effects/substitute.asm"
INCLUDE "engine/menus/pc.asm"


SECTION "Player Appearance", ROMX

INCLUDE "data/player/appearance.asm"


SECTION "Play Time", ROMX

INCLUDE "engine/play_time.asm"


SECTION "Doors and Ledges", ROMX

INCLUDE "engine/overworld/auto_movement.asm"
INCLUDE "engine/overworld/doors.asm"
INCLUDE "engine/overworld/ledges.asm"


SECTION "Pokémon Names", ROMX

INCLUDE "data/pokemon/names.asm"
INCLUDE "engine/movie/oak_speech/clear_save.asm"
INCLUDE "engine/events/elevator.asm"


SECTION "Hidden Events 1", ROMX

INCLUDE "engine/menus/oaks_pc.asm"
INCLUDE "engine/events/hidden_events/new_bike.asm"
INCLUDE "engine/events/hidden_events/oaks_lab_posters.asm"
INCLUDE "engine/events/hidden_events/safari_game.asm"
INCLUDE "engine/events/hidden_events/cinnabar_gym_quiz.asm"
INCLUDE "engine/events/hidden_events/magazines.asm"
INCLUDE "engine/events/hidden_events/bills_house_pc.asm"
INCLUDE "engine/events/hidden_events/oaks_lab_email.asm"


SECTION "Bill's PC", ROMX

INCLUDE "engine/pokemon/bills_pc.asm"


SECTION "Battle Engine 3", ROMX

INCLUDE "engine/battle/print_type.asm"
INCLUDE "engine/battle/save_trainer_name.asm"
INCLUDE "engine/battle/move_effects/focus_energy.asm"


SECTION "Battle Engine 4", ROMX

INCLUDE "engine/battle/move_effects/leech_seed.asm"


SECTION "Battle Engine 5", ROMX

INCLUDE "engine/battle/display_effectiveness.asm"
INCLUDE "gfx/trainer_card.asm"
INCLUDE "engine/items/tmhm.asm"
INCLUDE "engine/battle/scale_sprites.asm"
INCLUDE "engine/battle/move_effects/pay_day.asm"
INCLUDE "engine/slots/game_corner_slots2.asm"


SECTION "Battle Engine 6", ROMX

INCLUDE "engine/battle/move_effects/mist.asm"
INCLUDE "engine/battle/move_effects/one_hit_ko.asm"


SECTION "Slot Machines", ROMX

INCLUDE "engine/movie/title2.asm"
INCLUDE "engine/battle/link_battle_versus_text.asm"
INCLUDE "engine/slots/slot_machine.asm"
INCLUDE "engine/events/pewter_guys.asm"
INCLUDE "engine/math/multiply_divide.asm"
INCLUDE "engine/slots/game_corner_slots.asm"


SECTION "Battle Engine 7", ROMX

INCLUDE "data/moves/moves.asm"
INCLUDE "data/pokemon/base_stats.asm"
INCLUDE "engine/battle/scroll_draw_trainer_pic.asm"
INCLUDE "engine/battle/trainer_ai.asm"

; Shin Red import Phase 5: UndoBurnParStats needs to be farcall-reachable from
; both "bank3" (item_effects.asm) and here (trainer_ai.asm's AICureStatus), so
; it gets its own floating section rather than living in either.
SECTION "Stat Penalty Functions", ROMX
INCLUDE "engine/battle/stat_penalty_functions.asm"

; Moved out of "Battle Engine 7" to make room for the Gambler AI in trainer_ai.
; All entry points (DrawAllPokeballs / DrawEnemyPokeballs /
; SetupPlayerAndEnemyPokeballs) are callfar'd and PokeballTileGraphics is
; referenced via BANK(), so this file is bank-independent.
SECTION "HUD Pokeball GFX", ROMX
INCLUDE "engine/battle/draw_hud_pokeball_gfx.asm"

; Moved out of "Battle Engine 7" to make room for the final-sequence Elite
; Four/Champion team data growth (data/trainers/parties.asm). Both external
; entry points (PrepareRelearnableMoveList / PrepareMoveTutorList) are
; already reached via an explicit `ld b, Bank(...) / call Bankswitch`, and
; EvolutionAfterBattle/TryEvolvingMon are only ever reached via `predef`, so
; this file is bank-independent.
SECTION "Evos Moves", ROMX
INCLUDE "engine/pokemon/evos_moves.asm"

SECTION "Pokemon Data 1", ROMX    ; marcelnote - new, moved from Battle Engine 7

INCLUDE "data/pokemon/cries.asm" ; CryData is accessed with GetCryData which always Bankswitch


SECTION "Battle Core", ROMX

INCLUDE "engine/battle/core.asm"
INCLUDE "engine/battle/effects.asm"

SECTION "Battle Move Info", ROMX

INCLUDE "engine/battle/move_info.asm"

SECTION "Battle Pic Helpers", ROMX

INCLUDE "engine/battle/battle_pic_helpers.asm"

SECTION "Status View Navigation", ROMX

INCLUDE "engine/pokemon/status_view.asm"


SECTION "bank10", ROMX

INCLUDE "engine/menus/pokedex.asm"
INCLUDE "engine/movie/trade.asm"
INCLUDE "engine/movie/intro.asm"
INCLUDE "engine/movie/trade2.asm"


SECTION "Pokédex Rating", ROMX

INCLUDE "engine/events/pokedex_rating.asm"


SECTION "Hidden Events Core", ROMX

INCLUDE "engine/overworld/hidden_events.asm"


SECTION "Screen Effects", ROMX

INCLUDE "engine/gfx/screen_effects.asm"


SECTION "Predefs", ROMX

INCLUDE "engine/events/give_pokemon.asm"
INCLUDE "engine/predefs.asm"


SECTION "Battle Engine 8", ROMX

INCLUDE "engine/battle/init_battle_variables.asm"
INCLUDE "engine/battle/move_effects/paralyze.asm"
INCLUDE "engine/battle/move_effects/heal.asm"                 ; marcelnote - moved from Battle Engine 7
INCLUDE "engine/battle/move_effects/transform.asm"            ; marcelnote - moved from Battle Engine 7
INCLUDE "engine/battle/move_effects/reflect_light_screen.asm" ; marcelnote - moved from Battle Engine 7


SECTION "Hidden Events 2", ROMX

INCLUDE "engine/events/card_key.asm"
INCLUDE "engine/events/prize_menu.asm"
INCLUDE "engine/events/rogue_reward_menu.asm"
INCLUDE "engine/events/hidden_events/school_notebooks.asm"
INCLUDE "engine/events/hidden_events/fighting_dojo.asm"
INCLUDE "engine/events/hidden_events/indigo_plateau_hq.asm"
INCLUDE "engine/events/bridge_gift_menu.asm"


SECTION "Battle Engine 9", ROMX

INCLUDE "engine/battle/experience.asm"


SECTION "Diploma", ROMX

INCLUDE "engine/events/diploma.asm"


SECTION "Trainer Sight", ROMX

INCLUDE "engine/overworld/trainer_sight.asm"


SECTION "Battle Engine 10", ROMX

INCLUDE "engine/battle/common_text.asm"
INCLUDE "engine/pokemon/experience.asm"
INCLUDE "engine/events/oaks_aide.asm"


SECTION "Saffron Guards", ROMX

INCLUDE "engine/events/saffron_guards.asm"


SECTION "Starter Dex", ROMX

INCLUDE "engine/events/starter_dex.asm"


SECTION "Hidden Events 3", ROMX

INCLUDE "engine/pokemon/set_types.asm"
INCLUDE "engine/events/hidden_events/reds_room.asm"
INCLUDE "engine/events/hidden_events/route_15_binoculars.asm"
INCLUDE "engine/events/hidden_events/museum_fossils.asm"
INCLUDE "engine/events/hidden_events/school_blackboard.asm"
INCLUDE "engine/events/hidden_events/vermilion_gym_trash.asm"
INCLUDE "engine/events/hidden_events/rogue_pokemon.asm"


SECTION "Cinnabar Lab Fossils", ROMX

INCLUDE "engine/events/cinnabar_lab.asm"


SECTION "Hidden Events 4", ROMX

INCLUDE "engine/events/hidden_events/gym_statues.asm"
INCLUDE "engine/events/hidden_events/bench_guys.asm"
INCLUDE "engine/events/hidden_events/blues_room.asm"
INCLUDE "engine/events/hidden_events/pokecenter_pc.asm"


SECTION "Battle Engine 11", ROMX

INCLUDE "engine/battle/decrement_pp.asm"
INCLUDE "gfx/version.asm"


SECTION "bank1C", ROMX

INCLUDE "engine/movie/splash.asm"
INCLUDE "engine/movie/hall_of_fame.asm"
INCLUDE "engine/overworld/healing_machine.asm"
INCLUDE "engine/overworld/player_animations.asm"
INCLUDE "engine/battle/ghost_marowak_anim.asm"
INCLUDE "engine/battle/battle_transitions.asm"
INCLUDE "engine/items/town_map.asm"
INCLUDE "engine/gfx/mon_icons.asm"
INCLUDE "engine/gfx/palettes.asm"
INCLUDE "engine/menus/save.asm"


; Relocated from bank $1C. Both public entry points are dispatched through the
; bank-aware predef table; all internal code, data, and local pointer tables
; remain together in this section.
SECTION "In-Game Trades", ROMX

INCLUDE "engine/events/in_game_trades.asm"


SECTION "CGB Screen Attributes", ROMX
; Shin Red import Phase 3. Loader plus its ~3600 bytes of generated attribute
; tables, kept together in one bank: the loader reads the tables directly, and
; bank $1C (palettes.asm / SendSGBPackets) has nowhere near room for them. Called
; by farcall, so it does not care which bank the linker picks.

INCLUDE "engine/gfx/cgb_attributes.asm"
INCLUDE "custom_functions/func_gamma.asm"


; The enhanced attribute generator directly indexes these tables while running
; in the CGB helper bank. Keep its ROM reads local to that bank.
SECTION "Overworld CGB Tile Palettes", ROMX, BANK[$2C]
; Shin Red import Phase 3 (CGB color). The bank-$2C enhanced attribute engine
; directly reads these pointers and tables.

INCLUDE "data/gfx/overworld_tile_palettes.asm"


SECTION "Itemfinder 1", ROMX

INCLUDE "engine/movie/credits.asm"
INCLUDE "engine/pokemon/status_ailments.asm"
INCLUDE "engine/items/itemfinder.asm"


SECTION "Vending Machine", ROMX

INCLUDE "engine/events/vending_machine.asm"
INCLUDE "engine/pokemon/calc_stats.asm"


SECTION "Itemfinder 2", ROMX

INCLUDE "engine/menus/league_pc.asm"
INCLUDE "engine/events/hidden_items.asm"


SECTION "bank1E", ROMX

INCLUDE "engine/battle/animations.asm"
INCLUDE "engine/overworld/cut2.asm"
INCLUDE "engine/overworld/dust_smoke.asm"
INCLUDE "gfx/fishing.asm"
INCLUDE "data/moves/animations.asm"
INCLUDE "data/battle_anims/subanimations.asm"
INCLUDE "data/battle_anims/frame_blocks.asm"
INCLUDE "engine/movie/evolution.asm"
INCLUDE "engine/overworld/elevator.asm"
INCLUDE "engine/items/tm_prices.asm"

SECTION "Credit Exchange", ROMX

INCLUDE "engine/events/credit_mart.asm"


SECTION "rogue", ROMX

INCLUDE "custom_functions/random_stage_selection.asm"
INCLUDE "custom_functions/miniboss.asm"
INCLUDE "custom_functions/wild_area_selection.asm"
INCLUDE "custom_functions/bridge_selection.asm"
INCLUDE "custom_functions/final_sequence.asm"
INCLUDE "custom_functions/tm_bag.asm"
INCLUDE "custom_functions/key_item_pocket.asm"
INCLUDE "custom_functions/credit_award.asm"
INCLUDE "custom_functions/credit_popup.asm"
INCLUDE "custom_functions/pocket_items.asm"
INCLUDE "custom_functions/dice_items.asm"
INCLUDE "custom_functions/witch_battle_effects.asm"
INCLUDE "custom_functions/element_prism.asm"
INCLUDE "custom_functions/turn_rewind.asm"

INCLUDE "engine/pokemon/rarity.asm"
INCLUDE "engine/pokemon/random_pokemon_selection.asm"
INCLUDE "engine/rogue_pointers.asm"
INCLUDE "custom_functions/func_enc_gen.asm"
INCLUDE "custom_functions/legendary_boss_helpers.asm"
INCLUDE "data/trainers/gambler_movesets.asm"
INCLUDE "custom_functions/func_monlists.asm"
INCLUDE "custom_functions/func_ghost_variant.asm"
INCLUDE "custom_functions/func_fusion.asm"
INCLUDE "custom_functions/func_special_form.asm"
INCLUDE "custom_functions/func_shiny.asm"
INCLUDE "custom_functions/procedural_cave_gen.asm"
INCLUDE "custom_functions/procedural_cemetery_gen.asm"
INCLUDE "custom_functions/procedural_forest_gen.asm"
INCLUDE "custom_functions/procedural_facility_gen.asm"
INCLUDE "custom_functions/procedural_stage_hooks.asm"
INCLUDE "custom_functions/room_decor.asm"
INCLUDE "custom_functions/room_pc.asm"
INCLUDE "custom_functions/room_vendor.asm"
INCLUDE "custom_functions/relocated_home.asm"
INCLUDE "engine/items/item_rarity.asm"
INCLUDE "engine/items/random_item_selection.asm"
INCLUDE "engine/items/random_item_selection_mart.asm"
INCLUDE "engine/events/reward_poke_balls.asm"
INCLUDE "gfx/trade.asm"  ; marcelnote - moved from Battle Engine 7, LoadTradingGFXAndMonNames uses BANK()
INCLUDE "engine/gfx/save_screen_area_to_buffer3.asm"
INCLUDE "custom_functions/func_enhancedcolor.asm"
