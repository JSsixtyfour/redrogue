# Party roster

The source of truth for every banded trainer team: which species each boss-type trainer can field,
band by band. `tools/gen_party_roster.py` turns this file into `data/trainers/band_pools.asm`, and
`make audit` fails if the two disagree. **Edit this file, never the asm**, then run:

```
python3 tools/gen_party_roster.py
```

Started 2026-10-07 from the shipping gym pools, which matched the old `LEADER_REVIEW.md` sheet
(v2, 2026-09-28) entry for entry. Team sizes, levels and moveset rows are not set here: they are
the per-round knobs in `constants/balance_constants.asm` (`GYM_R<n>_*` for gym leaders) and the
mix rows in `data/trainers/party_specs.asm`.

## How to edit

- **Bands.** Each band covers two rounds: band 1 is rounds 1-2 (gyms 1-2), band 2 rounds 3-4,
  band 3 rounds 5-6, band 4 rounds 7-8.
- **Aces:** one is rolled at random for the last slot of every team. Used **exactly as written**,
  never evolved, so write the form you want at that band's levels. List one twice to double its
  odds. **Optional:** a band with no `- Aces:` line has no ace, and every slot is fodder.
- **Fodder:** fills the other slots, **evolved by level** by the trainer engine, so list base
  forms (`Geodude`, not `Golem`). A pick that matches the ace species is rerolled.
- **Off-type:** fills **one** slot, and is the fallback when every on-type fodder species is
  already on the team. Also evolved by level. **Optional**, like Aces: gym leaders have none in
  band 1. Fodder is the only list every band must have.
- **(johto)** entries only appear when Johto is on, **(warp)** entries only when Time Warp is on.
  Untagged entries are always available, so every Aces list needs at least one untagged entry
  (Johto-only gym leaders excepted). An ace list with nothing eligible does not skip the ace: it
  fields the list's first entry whatever its run.
- **Names** are species names (`Nidoran M`, `Mr Mime`, `Porygon2`) or form names (`Hisuian
  Growlithe`, `Galarian Meowth`, `Espeon`, `Aqua Tauros`, `Sandy Shocks`); a form name is spelled
  as its file in `data/pokemon/forms/` reads. An unknown name is an error.
- **Order matters only for the asm:** within a list, the generator keeps your order per run.
  Identical lists within one character become a zero-byte alias automatically.
- **Sets (optional, any character):** a `#### Sets: <tiers>` heading inside a character's block,
  followed by a `| Species | Move, Move, Move, Move | Notes |` table, adds curated movesets to
  the corpus (`tools/gen_movesets.py`, run from Windows). The heading's tiers decide who can
  draw them: a corpus grade (`TIER_HARD`, ...) puts them in the shared pool, a character's own
  bit (`TIER_GAMBLER`, or the reserved `TIER_SIGNATURE_6/7`) keeps them for a mix that asks for
  it. A character with a Sets table needs a row for every species it can field, evolutions
  included, or `make audit` fails. Today only the Gambler has one.
- Anything that is not a `### Name` header, a `**Band n...**` line, one of the three list
  bullets or a Sets table is free prose and is ignored.

The gym leaders' team sizes and levels, straight from `constants/balance_constants.asm`:

<!-- BEGIN GENERATED: gym curve -->
<!-- Rewritten by tools/gen_party_roster.py from GYM_R<n>_MONS/BASE/STEP in constants/balance_constants.asm. Do not edit by hand. -->

| Band | Rounds | Team size | Slot 0 L | Ace L |
|---|---|---|---|---|
| 1 | 1-2 | 2-2 | 9-15 | 11-18 |
| 2 | 3-4 | 3-3 | 19-27 | 25-31 |
| 3 | 5-6 | 4-4 | 31-38 | 37-44 |
| 4 | 7-8 | 5-6 | 43-47 | 51-57 |

<!-- END GENERATED: gym curve -->

## Gym leaders

**Brock edits applied (2026-09-28):** Brock is Rock only (Sandshrew/Diglett are real off-type);
Aerodactyl out of the gym 1-2 aces; Sudowoodo added to gym 5-8 fodder; Steelix is ace-only: the
engine evolves Onix at L43, so from gyms 7-8 (fodder L44+) Steelix is an ace and Onix leaves the
fodder.

### Brock (ROCK)  (yours)

**Band 1: rounds 1-2**
- Aces: Onix, Sudowoodo (johto)
- Fodder: Geodude, Kabuto, Omanyte, Rhyhorn, Shuckle (johto), Corsola (johto), Larvitar (johto)

**Band 2: rounds 3-4**
- Aces: Golem, Aerodactyl, Rhydon, Sudowoodo (johto)
- Fodder: Geodude, Kabuto, Omanyte, Rhyhorn, Onix, Corsola (johto), Shuckle (johto), Larvitar (johto), Hisuian Growlithe (warp), Galarian Meowth (warp)
- Off-type: Zubat, Pinsir, Lickitung

**Band 3: rounds 5-6**
- Aces: Golem, Rhydon, Kabutops, Omastar, Tyranitar (johto), Steelix (johto), Kleavor (warp)
- Fodder: Geodude, Kabuto, Omanyte, Rhyhorn, Onix, Aerodactyl, Sudowoodo (johto), Corsola (johto), Shuckle (johto), Skarmory (johto), Slugma (johto), Hisuian Growlithe (warp), Galarian Meowth (warp)
- Off-type: Zubat, Pinsir, Lickitung, Vulpix, Mankey, Chansey, Sandshrew

**Band 4: rounds 7-8**
- Aces: Golem, Rhydon, Kabutops, Omastar, Tyranitar (johto), Steelix (johto), Kleavor (warp), Rhyperior (warp)
- Fodder: Geodude, Kabuto, Omanyte, Rhyhorn, Aerodactyl, Sudowoodo (johto), Corsola (johto), Shuckle (johto), Skarmory (johto), Slugma (johto), Hisuian Growlithe (warp), Galarian Meowth (warp)
- Off-type: Zubat, Pinsir, Lickitung, Vulpix, Mankey, Chansey, Sandshrew, Diglett, Slowpoke

### Misty (WATER)

**Band 1: rounds 1-2**
- Aces: Starmie, Tentacruel, Vaporeon
- Fodder: Seel, Psyduck, Krabby, Kabuto, Shellder, Omanyte, Poliwag, Tentacool, Horsea, Goldeen, Magikarp, Eevee, Slowpoke, Squirtle, Remoraid (johto), Wooper (johto), Marill (johto), Totodile (johto), Corsola (johto), Wiglett (warp)

**Band 2: rounds 3-4**
- Aces: Starmie, Gyarados, Slowbro, Blastoise, Vaporeon
- Fodder: Kabuto, Omanyte, Krabby, Shellder, Psyduck, Poliwag, Tentacool, Horsea, Goldeen, Magikarp, Eevee, Slowpoke, Squirtle, Seel, Remoraid (johto), Wooper (johto), Marill (johto), Totodile (johto), Corsola (johto), Wiglett (warp)
- Off-type: Dratini, Nidoran F, Jigglypuff, Diglett, Ponyta

**Band 3: rounds 5-6**
- Aces: Starmie, Lapras, Slowbro, Kingdra (johto), Aqua Tauros (warp)
- Fodder: Seel, Kabuto, Omanyte, Staryu, Shellder, Krabby, Psyduck, Poliwag, Tentacool, Horsea, Goldeen, Magikarp, Lapras, Eevee, Slowpoke, Squirtle, Chinchou (johto), Qwilfish (johto), Remoraid (johto), Mantine (johto), Wooper (johto), Marill (johto), Totodile (johto), Corsola (johto), Wiglett (warp)
- Off-type: Nidoran F, Dratini, Jigglypuff, Diglett, Ponyta

**Band 4: rounds 7-8**
- Aces: Starmie, Lapras, Slowbro, Kingdra (johto), Suicune (johto)
- Fodder: Seel, Kabuto, Omanyte, Krabby, Staryu, Shellder, Psyduck, Poliwag, Tentacool, Horsea, Goldeen, Magikarp, Lapras, Eevee, Slowpoke, Squirtle, Chinchou (johto), Qwilfish (johto), Remoraid (johto), Mantine (johto), Wooper (johto), Marill (johto), Totodile (johto), Corsola (johto), Wiglett (warp), Aqua Tauros (warp)
- Off-type: Nidoran F, Dratini, Jigglypuff, Diglett, Ponyta, Exeggcute

### LtSurge (ELECTRIC)

**Band 1: rounds 1-2**
- Aces: Raichu, Magneton, Electabuzz, Lanturn (johto)
- Fodder: Pikachu, Voltorb, Magnemite, Mareep (johto), Chinchou (johto), Alolan Geodude (warp)

**Band 2: rounds 3-4**
- Aces: Raichu, Electabuzz, Magneton, Electrode, Ampharos (johto), Alolan Golem (warp)
- Fodder: Pikachu, Voltorb, Magnemite, Mareep (johto), Chinchou (johto), Alolan Geodude (warp), Sandy Shocks (warp)
- Off-type: Spearow, Porygon, Lickitung, Doduo, Rattata, Tangela, Magikarp

**Band 3: rounds 5-6**
- Aces: Jolteon, Electivire (warp), Magnezone (warp), Alolan Golem (warp)
- Fodder: Pikachu, Voltorb, Magnemite, Electabuzz, Mareep (johto), Chinchou (johto), Alolan Geodude (warp), Sandy Shocks (warp)
- Off-type: Spearow, Porygon, Lickitung, Seel, Doduo, Bellsprout, Poliwag, Rattata, Tangela, Magikarp, Quagsire (johto)

**Band 4: rounds 7-8**
- Aces: Jolteon, Zapdos, Raikou (johto), Electivire (warp)
- Fodder: Pikachu, Voltorb, Magnemite, Electabuzz, Mareep (johto), Chinchou (johto), Alolan Geodude (warp), Sandy Shocks (warp)
- Off-type: Spearow, Porygon, Lickitung, Seel, Doduo, Bellsprout, Poliwag, Rattata, Tangela, Magikarp, Quagsire (johto)

### Erika (GRASS)

**Band 1: rounds 1-2**
- Aces: Gloom, Weepinbell, Tangela
- Fodder: Bulbasaur, Oddish, Bellsprout, Tangela, Paras, Chikorita (johto), Hoppip (johto), Sunkern (johto)

**Band 2: rounds 3-4**
- Aces: Vileplume, Victreebel, Venusaur, Meganium (johto), Bellossom (johto), Leafeon (warp), Tangrowth (warp)
- Fodder: Bulbasaur, Oddish, Bellsprout, Tangela, Paras, Exeggcute, Chikorita (johto), Hoppip (johto), Sunkern (johto), Toedscool (warp), Hisuian Voltorb (warp)
- Off-type: Dratini, Cubone, Clefairy, Vulpix, Seel

**Band 3: rounds 5-6**
- Aces: Vileplume, Victreebel, Venusaur, Exeggutor, Meganium (johto), Bellossom (johto), Tangrowth (warp)
- Fodder: Bulbasaur, Oddish, Bellsprout, Exeggcute, Tangela, Paras, Chikorita (johto), Hoppip (johto), Sunkern (johto), Toedscool (warp), Hisuian Voltorb (warp)
- Off-type: Chansey, Dratini, Cubone, Clefairy, Vulpix, Seel, Eevee

**Band 4: rounds 7-8**
- Aces: Exeggutor, Victreebel, Venusaur, Meganium (johto), Tangrowth (warp)
- Fodder: Bulbasaur, Oddish, Bellsprout, Exeggcute, Tangela, Paras, Chikorita (johto), Hoppip (johto), Sunkern (johto), Leafeon (warp), Toedscool (warp), Hisuian Voltorb (warp)
- Off-type: Chansey, Dratini, Cubone, Clefairy, Vulpix, Seel, Eevee

### Koga (POISON)

**Band 1: rounds 1-2**
- Aces: Arbok, Golbat, Venomoth
- Fodder: Gastly, Ekans, Nidoran M, Nidoran F, Zubat, Grimer, Koffing, Venonat, Bulbasaur, Oddish, Bellsprout, Weedle, Tentacool, Spinarak (johto)

**Band 2: rounds 3-4**
- Aces: Weezing, Muk, Venomoth
- Fodder: Gastly, Ekans, Nidoran M, Nidoran F, Zubat, Grimer, Koffing, Venonat, Bulbasaur, Oddish, Bellsprout, Weedle, Tentacool, Spinarak (johto), Galarian Slowpoke (warp), Hisuian Sneasel (warp), Paldean Wooper (warp)
- Off-type: Paras, Tangela, Drowzee, Voltorb, Magmar, Lapras, Scyther, Rhyhorn, Vulpix, Chansey, Ditto, Pidgey, Eevee, Porygon, Pineco (johto), Stantler (johto), Chinchou (johto), Girafarig (johto), Chikorita (johto), Shuckle (johto)

**Band 3: rounds 5-6**
- Aces: Weezing, Muk, Nidoking, Nidoqueen, Gengar, Crobat (johto)
- Fodder: Gastly, Ekans, Nidoran M, Nidoran F, Zubat, Grimer, Koffing, Venonat, Bulbasaur, Oddish, Bellsprout, Weedle, Tentacool, Qwilfish (johto), Spinarak (johto), Galarian Slowpoke (warp), Hisuian Sneasel (warp), Paldean Wooper (warp)
- Off-type: Paras, Tangela, Drowzee, Voltorb, Magmar, Lapras, Scyther, Rhyhorn, Vulpix, Chansey, Ditto, Pidgey, Eevee, Porygon, Tauros, Pineco (johto), Stantler (johto), Chinchou (johto), Girafarig (johto), Chikorita (johto), Shuckle (johto)

**Band 4: rounds 7-8**
- Aces: Nidoking, Nidoqueen, Gengar, Crobat (johto)
- Fodder: Ekans, Nidoran M, Nidoran F, Zubat, Grimer, Koffing, Venonat, Gastly, Bulbasaur, Oddish, Bellsprout, Tentacool, Qwilfish (johto), Spinarak (johto), Galarian Slowpoke (warp), Hisuian Sneasel (warp), Paldean Wooper (warp)
- Off-type: Paras, Tangela, Drowzee, Voltorb, Magmar, Lapras, Scyther, Rhyhorn, Vulpix, Chansey, Ditto, Pidgey, Eevee, Porygon, Tauros, Pineco (johto), Stantler (johto), Chinchou (johto), Girafarig (johto), Chikorita (johto), Shuckle (johto)

### Blaine (FIRE)

**Band 1: rounds 1-2**
- Aces: Magmar, Charmeleon, Flareon
- Fodder: Vulpix, Growlithe, Ponyta, Charmander, Cyndaquil (johto), Slugma (johto), Houndour (johto)

**Band 2: rounds 3-4**
- Aces: Arcanine, Rapidash, Charizard, Ninetales, Houndoom (johto), Alolan Marowak (warp), Magmortar (warp)
- Fodder: Vulpix, Growlithe, Ponyta, Charmander, Magmar, Cyndaquil (johto), Slugma (johto), Houndour (johto)
- Off-type: Clefairy, Doduo, Tangela, Koffing, Geodude, Voltorb, Mankey, Kabuto, Oddish, Grimer, Meowth, Paras, Octillery (johto)

**Band 3: rounds 5-6**
- Aces: Arcanine, Rapidash, Charizard, Ninetales, Houndoom (johto), Alolan Marowak (warp), Magmortar (warp), Blaze Tauros (warp)
- Fodder: Vulpix, Growlithe, Ponyta, Charmander, Magmar, Flareon, Cyndaquil (johto), Slugma (johto), Houndour (johto)
- Off-type: Clefairy, Doduo, Tangela, Koffing, Geodude, Voltorb, Mankey, Kabuto, Oddish, Grimer, Kangaskhan, Chansey, Mr Mime, Meowth, Paras, Tauros, Octillery (johto)

**Band 4: rounds 7-8**
- Aces: Moltres, Arcanine, Charizard, Entei (johto), Galarian Moltres (warp), Alolan Marowak (warp)
- Fodder: Vulpix, Growlithe, Ponyta, Charmander, Magmar, Moltres, Flareon, Cyndaquil (johto), Slugma (johto), Houndour (johto), Blaze Tauros (warp)
- Off-type: Clefairy, Doduo, Tangela, Koffing, Geodude, Voltorb, Mankey, Kabuto, Oddish, Grimer, Kangaskhan, Chansey, Mr Mime, Meowth, Paras, Articuno, Tauros, Octillery (johto)

### Sabrina (PSYCHIC)

**Band 1: rounds 1-2**
- Aces: Mr Mime, Venomoth, Hypno
- Fodder: Abra, Drowzee, Slowpoke, Exeggcute, Natu (johto), Girafarig (johto), Galarian Ponyta (warp)

**Band 2: rounds 3-4**
- Aces: Kadabra, Hypno, Mr Mime, Jynx, Starmie
- Fodder: Abra, Drowzee, Slowpoke, Exeggcute, Mr Mime, Jynx, Natu (johto), Girafarig (johto), Galarian Ponyta (warp)
- Off-type: Gastly, Venonat, Eevee, Jigglypuff, Psyduck, Sandshrew, Porygon, Sentret (johto), Cyndaquil (johto)

**Band 3: rounds 5-6**
- Aces: Alakazam, Exeggutor, Slowbro, Starmie, Slowking (johto), Espeon (johto), Mr Rime (warp)
- Fodder: Abra, Drowzee, Mr Mime, Jynx, Slowpoke, Exeggcute, Staryu, Espeon (johto), Natu (johto), Girafarig (johto), Alolan Raichu (warp), Galarian Ponyta (warp)
- Off-type: Gastly, Venonat, Eevee, Jigglypuff, Psyduck, Sandshrew, Scyther, Hitmonlee, Porygon, Lapras, Sentret (johto), Cyndaquil (johto)

**Band 4: rounds 7-8**
- Aces: Alakazam, Exeggutor, Slowbro, Starmie, Slowking (johto), Espeon (johto), Mr Rime (warp), Galarian Articuno (warp)
- Fodder: Abra, Drowzee, Mr Mime, Jynx, Slowpoke, Exeggcute, Staryu, Espeon (johto), Natu (johto), Girafarig (johto), Alolan Raichu (warp), Galarian Ponyta (warp)
- Off-type: Gastly, Venonat, Eevee, Jigglypuff, Psyduck, Sandshrew, Scyther, Hitmonlee, Moltres, Snorlax, Porygon, Lapras, Sentret (johto), Cyndaquil (johto)

### Giovanni (GROUND)

**Band 1: rounds 1-2**
- Aces: Onix, Sandslash, Dugtrio, Marowak
- Fodder: Nidoran M, Nidoran F, Diglett, Sandshrew, Geodude, Cubone, Rhyhorn, Phanpy (johto), Wooper (johto), Larvitar (johto), Swinub (johto), Paldean Wooper (warp), Toedscool (warp)

**Band 2: rounds 3-4**
- Aces: Nidoking, Rhydon, Persian, Nidoqueen, Golem
- Fodder: Nidoran M, Nidoran F, Rhyhorn, Onix, Diglett, Sandshrew, Geodude, Cubone, Phanpy (johto), Wooper (johto), Larvitar (johto), Swinub (johto), Gligar (johto), Paldean Wooper (warp), Toedscool (warp)
- Off-type: Meowth, Kangaskhan, Magikarp, Machop, Charmander, Growlithe, Snubbull (johto), Murkrow (johto), Houndour (johto)

**Band 3: rounds 5-6**
- Aces: Nidoking, Rhydon, Persian, Nidoqueen, Golem
- Fodder: Nidoran M, Nidoran F, Rhyhorn, Onix, Diglett, Sandshrew, Geodude, Cubone, Phanpy (johto), Wooper (johto), Larvitar (johto), Swinub (johto), Gligar (johto), Paldean Wooper (warp), Toedscool (warp), Sandy Shocks (warp)
- Off-type: Meowth, Kangaskhan, Magikarp, Pinsir, Exeggcute, Hitmonchan, Hitmonlee, Koffing, Machop, Electabuzz, Tauros, Charmander, Growlithe, Snubbull (johto), Murkrow (johto), Houndour (johto)

**Band 4: rounds 7-8**
- Aces: Nidoking, Rhydon, Persian, Nidoqueen, Golem
- Fodder: Nidoran M, Nidoran F, Rhyhorn, Onix, Diglett, Sandshrew, Geodude, Cubone, Phanpy (johto), Wooper (johto), Larvitar (johto), Swinub (johto), Gligar (johto), Paldean Wooper (warp), Toedscool (warp), Sandy Shocks (warp)
- Off-type: Meowth, Kangaskhan, Magikarp, Pinsir, Exeggcute, Hitmonchan, Hitmonlee, Koffing, Machop, Electabuzz, Tauros, Charmander, Growlithe, Moltres, Snubbull (johto), Murkrow (johto), Houndour (johto)

### Falkner (FLYING)  (Draft)

**Band 1: rounds 1-2**
- Aces: Pidgeotto, Fearow, Noctowl (johto)
- Fodder: Pidgey, Spearow, Doduo, Farfetchd, Zubat, Hoothoot (johto), Natu (johto), Hoppip (johto), Ledyba (johto)

**Band 2: rounds 3-4**
- Aces: Pidgeot, Dodrio, Fearow, Noctowl (johto), Xatu (johto), Skarmory (johto)
- Fodder: Pidgey, Spearow, Doduo, Farfetchd, Zubat, Hoothoot (johto), Natu (johto), Hoppip (johto), Ledyba (johto)
- Off-type: Diglett, Growlithe, Poliwag, Sentret (johto)

**Band 3: rounds 5-6**
- Aces: Pidgeot, Dodrio, Aerodactyl, Skarmory (johto), Xatu (johto)
- Fodder: Pidgey, Spearow, Doduo, Farfetchd, Zubat, Aerodactyl, Hoothoot (johto), Natu (johto), Hoppip (johto), Ledyba (johto), Murkrow (johto), Yanma (johto), Gligar (johto), Skarmory (johto)
- Off-type: Diglett, Growlithe, Poliwag, Sandshrew, Magnemite, Machop, Sentret (johto)

**Band 4: rounds 7-8**
- Aces: Pidgeot, Dodrio, Aerodactyl, Crobat (johto), Skarmory (johto), Galarian Moltres (warp)
- Fodder: Pidgey, Spearow, Doduo, Farfetchd, Zubat, Aerodactyl, Hoothoot (johto), Natu (johto), Hoppip (johto), Ledyba (johto), Murkrow (johto), Yanma (johto), Gligar (johto), Skarmory (johto)
- Off-type: Diglett, Growlithe, Poliwag, Sandshrew, Magnemite, Machop, Snorlax, Lapras, Sentret (johto)

### Bugsy (BUG)  (Draft)

**Band 1: rounds 1-2**
- Aces: Butterfree, Beedrill, Scyther, Venomoth
- Fodder: Caterpie, Weedle, Paras, Venonat, Ledyba (johto), Spinarak (johto), Pineco (johto)

**Band 2: rounds 3-4**
- Aces: Scyther, Pinsir, Venomoth, Parasect, Heracross (johto), Ariados (johto)
- Fodder: Caterpie, Weedle, Paras, Venonat, Ledyba (johto), Spinarak (johto), Pineco (johto)
- Off-type: Oddish, Poliwag, Geodude, Sentret (johto)

**Band 3: rounds 5-6**
- Aces: Pinsir, Scyther, Venomoth, Scizor (johto), Heracross (johto), Forretress (johto)
- Fodder: Caterpie, Weedle, Paras, Venonat, Scyther, Pinsir, Ledyba (johto), Spinarak (johto), Yanma (johto), Pineco (johto), Heracross (johto), Shuckle (johto)
- Off-type: Oddish, Poliwag, Geodude, Onix, Sandshrew, Tangela, Sentret (johto)

**Band 4: rounds 7-8**
- Aces: Pinsir, Scizor (johto), Heracross (johto), Forretress (johto), Kleavor (warp)
- Fodder: Caterpie, Weedle, Paras, Venonat, Scyther, Pinsir, Ledyba (johto), Spinarak (johto), Yanma (johto), Pineco (johto), Heracross (johto), Shuckle (johto)
- Off-type: Oddish, Poliwag, Geodude, Onix, Sandshrew, Tangela, Chansey, Snorlax, Sentret (johto)

### Whitney (NORMAL)  (Draft)

**Band 1: rounds 1-2**
- Aces: Clefable, Wigglytuff, Raticate, Miltank (johto), Furret (johto)
- Fodder: Rattata, Clefairy, Jigglypuff, Meowth, Lickitung, Eevee, Sentret (johto), Snubbull (johto), Aipom (johto), Teddiursa (johto), Togepi (johto), Dunsparce (johto)

**Band 2: rounds 3-4**
- Aces: Clefable, Wigglytuff, Miltank (johto), Granbull (johto), Ursaring (johto), Girafarig (johto)
- Fodder: Rattata, Clefairy, Jigglypuff, Meowth, Lickitung, Eevee, Sentret (johto), Snubbull (johto), Aipom (johto), Teddiursa (johto), Togepi (johto), Dunsparce (johto), Girafarig (johto)
- Off-type: Drowzee, Marill (johto), Hoppip (johto), Natu (johto)

**Band 3: rounds 5-6**
- Aces: Clefable, Kangaskhan, Tauros, Snorlax, Miltank (johto), Ursaring (johto), Porygon2 (johto)
- Fodder: Rattata, Clefairy, Jigglypuff, Meowth, Lickitung, Chansey, Kangaskhan, Tauros, Ditto, Eevee, Snorlax, Porygon, Sentret (johto), Togepi (johto), Stantler (johto), Dunsparce (johto), Snubbull (johto), Aipom (johto), Teddiursa (johto), Girafarig (johto)
- Off-type: Drowzee, Pikachu, Slowpoke, Gastly, Marill (johto), Hoppip (johto), Natu (johto)

**Band 4: rounds 7-8**
- Aces: Snorlax, Miltank (johto), Miltank (johto), Blissey (johto), Ursaring (johto), Porygon2 (johto), Lickilicky (warp), Porygon Z (warp)
- Fodder: Rattata, Clefairy, Jigglypuff, Meowth, Lickitung, Chansey, Kangaskhan, Tauros, Ditto, Eevee, Snorlax, Porygon, Sentret (johto), Togepi (johto), Stantler (johto), Dunsparce (johto), Snubbull (johto), Aipom (johto), Teddiursa (johto), Girafarig (johto), Sylveon (warp)
- Off-type: Drowzee, Pikachu, Slowpoke, Gastly, Exeggcute, Lapras, Marill (johto), Hoppip (johto), Natu (johto)

### Morty (GHOST)  (Draft)

Agatha-style: Ghosts plus "spooky" Poisons and Dark (Normal here) mons in fodder, since only 2
Ghost lines exist without Time Warp.

**Band 1: rounds 1-2**
- Aces: Haunter, Golbat, Misdreavus (johto)
- Fodder: Gastly, Zubat, Ekans, Grimer, Koffing, Cubone, Misdreavus (johto), Spinarak (johto), Murkrow (johto), Houndour (johto), Hoothoot (johto), Girafarig (johto), Sudowoodo (johto)

**Band 2: rounds 3-4**
- Aces: Haunter, Gengar, Arbok, Marowak, Misdreavus (johto), Alolan Marowak (warp)
- Fodder: Gastly, Zubat, Ekans, Grimer, Koffing, Cubone, Misdreavus (johto), Spinarak (johto), Murkrow (johto), Houndour (johto), Hoothoot (johto), Girafarig (johto), Sudowoodo (johto)
- Off-type: Drowzee, Jynx, Exeggcute, Sneasel (johto)

**Band 3: rounds 5-6**
- Aces: Gengar, Crobat (johto), Houndoom (johto), Umbreon (johto), Mismagius (warp), Alolan Marowak (warp)
- Fodder: Gastly, Zubat, Ekans, Grimer, Koffing, Cubone, Lapras, Misdreavus (johto), Spinarak (johto), Murkrow (johto), Houndour (johto), Hoothoot (johto), Girafarig (johto), Sudowoodo (johto), Mantine (johto), Alolan Marowak (warp), Annihilape (warp)
- Off-type: Drowzee, Jynx, Exeggcute, Slowpoke, Sneasel (johto), Umbreon (johto)

**Band 4: rounds 7-8**
- Aces: Gengar, Gengar, Crobat (johto), Houndoom (johto), Mismagius (warp), Alolan Marowak (warp), Annihilape (warp)
- Fodder: Gastly, Zubat, Ekans, Grimer, Koffing, Cubone, Lapras, Misdreavus (johto), Spinarak (johto), Murkrow (johto), Houndour (johto), Hoothoot (johto), Girafarig (johto), Sudowoodo (johto), Mantine (johto), Alolan Marowak (warp), Annihilape (warp)
- Off-type: Drowzee, Jynx, Exeggcute, Slowpoke, Sneasel (johto), Umbreon (johto)

### Chuck (FIGHTING)  (Draft)

**Band 1: rounds 1-2**
- Aces: Primeape, Poliwrath, Machoke, Hitmonchan
- Fodder: Mankey, Machop, Poliwag, Hitmonlee, Hitmonchan, Hitmontop (johto), Galarian Farfetchd (warp)

**Band 2: rounds 3-4**
- Aces: Primeape, Poliwrath, Machamp, Hitmonlee, Hitmonchan, Hitmontop (johto), Heracross (johto)
- Fodder: Mankey, Machop, Poliwag, Hitmonlee, Hitmonchan, Hitmontop (johto), Galarian Farfetchd (warp)
- Off-type: Geodude, Onix, Rhyhorn, Magnemite

**Band 3: rounds 5-6**
- Aces: Machamp, Poliwrath, Primeape, Heracross (johto), Hitmontop (johto), Combat Tauros (warp), Sirfetchd (warp)
- Fodder: Mankey, Machop, Poliwag, Hitmonlee, Hitmonchan, Hitmontop (johto), Heracross (johto), Galarian Farfetchd (warp), Combat Tauros (warp), Hisuian Sneasel (warp)
- Off-type: Geodude, Onix, Rhyhorn, Magnemite, Kangaskhan, Tauros, Teddiursa (johto)

**Band 4: rounds 7-8**
- Aces: Machamp, Machamp, Poliwrath, Heracross (johto), Hitmontop (johto), Annihilape (warp), Galarian Zapdos (warp)
- Fodder: Mankey, Machop, Poliwag, Hitmonlee, Hitmonchan, Hitmontop (johto), Heracross (johto), Galarian Farfetchd (warp), Combat Tauros (warp), Hisuian Sneasel (warp)
- Off-type: Geodude, Onix, Rhyhorn, Magnemite, Kangaskhan, Tauros, Snorlax, Lapras, Teddiursa (johto)

### Jasmine (STEEL)  (Draft)

The game has no Steel type, so her "on-type" set is the modern Steel species: Magnemite line,
Onix/Steelix, Skarmory, Scyther/Scizor, Pineco/Forretress, and the Steel forms (Alolan
Diglett/Sandshrew, Galarian Meowth/Perrserker). Ampharos is her lighthouse Amphy, so it is an
off-type ace the way Persian is for Giovanni.

**Band 1: rounds 1-2**
- Aces: Magneton, Onix, Forretress (johto)
- Fodder: Magnemite, Onix, Pineco (johto), Alolan Diglett (warp), Alolan Sandshrew (warp), Galarian Meowth (warp)

**Band 2: rounds 3-4**
- Aces: Magneton, Steelix (johto), Forretress (johto), Skarmory (johto), Scizor (johto)
- Fodder: Magnemite, Onix, Pineco (johto), Alolan Diglett (warp), Alolan Sandshrew (warp), Galarian Meowth (warp)
- Off-type: Geodude, Sandshrew, Mareep (johto), Marill (johto)

**Band 3: rounds 5-6**
- Aces: Steelix (johto), Scizor (johto), Skarmory (johto), Forretress (johto), Ampharos (johto), Magnezone (warp), Perrserker (warp)
- Fodder: Magnemite, Onix, Scyther, Pineco (johto), Skarmory (johto), Alolan Diglett (warp), Alolan Sandshrew (warp), Galarian Meowth (warp)
- Off-type: Geodude, Sandshrew, Rhyhorn, Mareep (johto), Marill (johto), Phanpy (johto), Chinchou (johto)

**Band 4: rounds 7-8**
- Aces: Steelix (johto), Steelix (johto), Scizor (johto), Skarmory (johto), Forretress (johto), Ampharos (johto), Magnezone (warp)
- Fodder: Magnemite, Scyther, Pineco (johto), Skarmory (johto), Alolan Diglett (warp), Alolan Sandshrew (warp), Galarian Meowth (warp)
- Off-type: Geodude, Sandshrew, Rhyhorn, Snorlax, Lapras, Mareep (johto), Marill (johto), Phanpy (johto), Chinchou (johto)

### Pryce (ICE)  (Draft)

**Band 1: rounds 1-2**
- Aces: Dewgong, Jynx, Piloswine (johto), Sneasel (johto)
- Fodder: Seel, Shellder, Jynx, Swinub (johto), Sneasel (johto), Alolan Vulpix (warp), Alolan Sandshrew (warp)

**Band 2: rounds 3-4**
- Aces: Dewgong, Cloyster, Jynx, Lapras, Piloswine (johto), Alolan Ninetales (warp), Alolan Sandslash (warp)
- Fodder: Seel, Shellder, Jynx, Swinub (johto), Sneasel (johto), Alolan Vulpix (warp), Alolan Sandshrew (warp)
- Off-type: Psyduck, Poliwag, Wooper (johto), Marill (johto)

**Band 3: rounds 5-6**
- Aces: Lapras, Cloyster, Dewgong, Jynx, Piloswine (johto), Mamoswine (warp), Weavile (warp), Glaceon (warp)
- Fodder: Seel, Shellder, Jynx, Lapras, Swinub (johto), Sneasel (johto), Alolan Vulpix (warp), Alolan Sandshrew (warp), Galarian Mr Mime (warp)
- Off-type: Psyduck, Poliwag, Slowpoke, Tentacool, Krabby, Wooper (johto), Marill (johto)

**Band 4: rounds 7-8**
- Aces: Lapras, Cloyster, Articuno, Mamoswine (warp), Weavile (warp), Glaceon (warp), Mr Rime (warp)
- Fodder: Seel, Shellder, Jynx, Lapras, Swinub (johto), Sneasel (johto), Alolan Vulpix (warp), Alolan Sandshrew (warp), Galarian Mr Mime (warp)
- Off-type: Psyduck, Poliwag, Slowpoke, Tentacool, Krabby, Snorlax, Wooper (johto), Marill (johto), Quagsire (johto)

### Clair (DRAGON)  (Draft)

Only 2 Dragon lines exist without Time Warp (Dratini, Horsea/Kingdra), so like Morty her
fodder includes "dragon-like" non-Dragons (Gyarados, Charizard, Aerodactyl, Lapras), the way
Lance's pool does.

**Band 1: rounds 1-2**
- Aces: Dragonair, Seadra, Charmeleon
- Fodder: Dratini, Horsea, Magikarp, Charmander

**Band 2: rounds 3-4**
- Aces: Dragonair, Gyarados, Charizard, Aerodactyl, Kingdra (johto), Alolan Exeggutor (warp)
- Fodder: Dratini, Horsea, Magikarp, Charmander
- Off-type: Ekans, Onix, Mareep (johto)

**Band 3: rounds 5-6**
- Aces: Dragonite, Gyarados, Charizard, Aerodactyl, Kingdra (johto), Alolan Exeggutor (warp)
- Fodder: Dratini, Horsea, Magikarp, Charmander, Aerodactyl, Lapras, Alolan Exeggutor (warp)
- Off-type: Ekans, Onix, Seel, Magnemite, Mareep (johto), Phanpy (johto)

**Band 4: rounds 7-8**
- Aces: Dragonite, Dragonite, Gyarados, Charizard, Aerodactyl, Kingdra (johto), Alolan Exeggutor (warp)
- Fodder: Dratini, Horsea, Magikarp, Charmander, Aerodactyl, Lapras, Alolan Exeggutor (warp)
- Off-type: Ekans, Onix, Seel, Magnemite, Snorlax, Mareep (johto), Phanpy (johto), Larvitar (johto)

### Janine (POISON)  (Draft)

Kept distinct from Koga: her HGSS team (Crobat, Weezing, Ariados, Venomoth) plus the Johto
Poisons and the Poison forms, with ninja-themed off-types.

**Band 1: rounds 1-2**
- Aces: Golbat, Venomoth, Weezing, Ariados (johto)
- Fodder: Zubat, Venonat, Koffing, Grimer, Ekans, Nidoran F, Nidoran M, Tentacool, Weedle, Spinarak (johto), Qwilfish (johto)

**Band 2: rounds 3-4**
- Aces: Weezing, Venomoth, Muk, Crobat (johto), Ariados (johto)
- Fodder: Zubat, Venonat, Koffing, Grimer, Ekans, Nidoran F, Nidoran M, Tentacool, Weedle, Spinarak (johto), Qwilfish (johto)
- Off-type: Drowzee, Sneasel (johto), Murkrow (johto), Houndour (johto)

**Band 3: rounds 5-6**
- Aces: Weezing, Venomoth, Muk, Tentacruel, Crobat (johto), Ariados (johto), Hisuian Sneasel (warp), Galarian Weezing (warp)
- Fodder: Zubat, Venonat, Koffing, Grimer, Ekans, Nidoran F, Nidoran M, Tentacool, Spinarak (johto), Qwilfish (johto), Hisuian Sneasel (warp), Paldean Wooper (warp)
- Off-type: Drowzee, Scyther, Sneasel (johto), Murkrow (johto), Houndour (johto), Umbreon (johto), Misdreavus (johto)

**Band 4: rounds 7-8**
- Aces: Weezing, Tentacruel, Nidoqueen, Crobat (johto), Crobat (johto), Alolan Muk (warp), Hisuian Sneasel (warp)
- Fodder: Zubat, Venonat, Koffing, Grimer, Ekans, Nidoran F, Nidoran M, Tentacool, Spinarak (johto), Qwilfish (johto), Hisuian Sneasel (warp), Paldean Wooper (warp)
- Off-type: Drowzee, Scyther, Snorlax, Sneasel (johto), Murkrow (johto), Houndour (johto), Umbreon (johto), Misdreavus (johto)

## Mini-bosses

The Rival, Giovanni and the Karate Master, fought in place of a route's final trainer (or on the
Dojo stage). One team per round (1-9), on the same bands as the wild-area trainers: **band 4
covers rounds 7-9**, and round 9 is the Victory Road rival. Round 1 is never reached (mini-bosses
start at round 2). Team size is that round's largest route team (2/3/4/4/5/5/6/6/6), levels are
`MINIBOSS_R<n>_BASE` + `MINIBOSS_R<n>_STEP` per slot, and the moveset row is the gym leader's row
for the band. The round comes from the battle count, not from the trainer's set number, so the
same team scales wherever the mini-boss is met.

Seeded 2026-10-07 from the matching gym leader (Giovanni from Giovanni, the Karate Master from
Chuck) plus each mini-boss's old curated signature species; edit freely.

### RivalMiniBoss (Rival)

His ace is always his own starter, evolved to the ace's level, exactly as the Champion rival's is:
it is pinned in `party_specs.asm`, so this block has no `- Aces:` line. The fodder is drawn from
his teams in the original games, base forms only, and his starter's own line is never drawn twice.
Magikarp waits for band 2, when the fodder levels are high enough to field a Gyarados.

**Band 1: rounds 1-2**
- Fodder: Pidgey, Rattata, Spearow, Abra, Growlithe, Exeggcute, Rhyhorn, Zubat, Gastly, Magnemite, Sneasel (johto)

**Band 2: rounds 3-4**
- Fodder: Pidgey, Rattata, Spearow, Abra, Growlithe, Exeggcute, Rhyhorn, Magikarp, Zubat, Gastly, Magnemite, Sneasel (johto)

**Band 3: rounds 5-6**
- Fodder: Pidgey, Rattata, Spearow, Abra, Growlithe, Exeggcute, Rhyhorn, Magikarp, Zubat, Gastly, Magnemite, Sneasel (johto)

**Band 4: rounds 7-9**
- Fodder: Pidgey, Rattata, Spearow, Abra, Growlithe, Exeggcute, Rhyhorn, Magikarp, Zubat, Gastly, Magnemite, Sneasel (johto)

### GiovanniMiniBoss (Giovanni)

The Rocket boss on the road. Fodder and off-type are his gym's; the aces are his old mini-boss
signatures (Rhydon, Dugtrio, Nidoking, Nidoqueen, Sandslash, Marowak) plus Persian and Kangaskhan.

**Band 1: rounds 1-2**
- Aces: Onix, Sandslash, Dugtrio, Marowak
- Fodder: Nidoran M, Nidoran F, Diglett, Sandshrew, Geodude, Cubone, Rhyhorn, Phanpy (johto), Wooper (johto), Larvitar (johto), Swinub (johto), Paldean Wooper (warp), Toedscool (warp)

**Band 2: rounds 3-4**
- Aces: Nidoking, Nidoqueen, Rhydon, Dugtrio, Marowak, Sandslash, Persian, Kangaskhan
- Fodder: Nidoran M, Nidoran F, Rhyhorn, Onix, Diglett, Sandshrew, Geodude, Cubone, Phanpy (johto), Wooper (johto), Larvitar (johto), Swinub (johto), Gligar (johto), Paldean Wooper (warp), Toedscool (warp)
- Off-type: Meowth, Kangaskhan, Magikarp, Machop, Charmander, Growlithe, Snubbull (johto), Murkrow (johto), Houndour (johto)

**Band 3: rounds 5-6**
- Aces: Nidoking, Nidoqueen, Rhydon, Dugtrio, Marowak, Sandslash, Persian, Kangaskhan
- Fodder: Nidoran M, Nidoran F, Rhyhorn, Onix, Diglett, Sandshrew, Geodude, Cubone, Phanpy (johto), Wooper (johto), Larvitar (johto), Swinub (johto), Gligar (johto), Paldean Wooper (warp), Toedscool (warp), Sandy Shocks (warp)
- Off-type: Meowth, Kangaskhan, Magikarp, Pinsir, Exeggcute, Hitmonchan, Hitmonlee, Koffing, Machop, Electabuzz, Tauros, Charmander, Growlithe, Snubbull (johto), Murkrow (johto), Houndour (johto)

**Band 4: rounds 7-9**
- Aces: Nidoking, Nidoqueen, Rhydon, Dugtrio, Marowak, Sandslash, Persian, Kangaskhan
- Fodder: Nidoran M, Nidoran F, Rhyhorn, Onix, Diglett, Sandshrew, Geodude, Cubone, Phanpy (johto), Wooper (johto), Larvitar (johto), Swinub (johto), Gligar (johto), Paldean Wooper (warp), Toedscool (warp), Sandy Shocks (warp)
- Off-type: Meowth, Kangaskhan, Magikarp, Pinsir, Exeggcute, Hitmonchan, Hitmonlee, Koffing, Machop, Electabuzz, Tauros, Charmander, Growlithe, Snubbull (johto), Murkrow (johto), Houndour (johto)

### KarateMiniBoss (Karate Master)

The Fighting Dojo's master. Fodder and off-type are Chuck's; the aces are Chuck's plus the old
mini-boss signatures (Hitmonlee, Hitmonchan, Machamp, Primeape, Poliwrath), so the Dojo's reward
Pokemon still headline his team.

**Band 1: rounds 1-2**
- Aces: Primeape, Poliwrath, Machoke, Hitmonchan, Hitmonlee
- Fodder: Mankey, Machop, Poliwag, Hitmonlee, Hitmonchan, Hitmontop (johto), Galarian Farfetchd (warp)

**Band 2: rounds 3-4**
- Aces: Primeape, Poliwrath, Machamp, Hitmonlee, Hitmonchan, Hitmontop (johto), Heracross (johto)
- Fodder: Mankey, Machop, Poliwag, Hitmonlee, Hitmonchan, Hitmontop (johto), Galarian Farfetchd (warp)
- Off-type: Geodude, Onix, Rhyhorn, Magnemite

**Band 3: rounds 5-6**
- Aces: Machamp, Poliwrath, Primeape, Hitmonlee, Hitmonchan, Heracross (johto), Hitmontop (johto), Combat Tauros (warp), Sirfetchd (warp)
- Fodder: Mankey, Machop, Poliwag, Hitmonlee, Hitmonchan, Hitmontop (johto), Heracross (johto), Galarian Farfetchd (warp), Combat Tauros (warp), Hisuian Sneasel (warp)
- Off-type: Geodude, Onix, Rhyhorn, Magnemite, Kangaskhan, Tauros, Teddiursa (johto)

**Band 4: rounds 7-9**
- Aces: Machamp, Poliwrath, Primeape, Hitmonlee, Hitmonchan, Heracross (johto), Hitmontop (johto), Annihilape (warp), Galarian Zapdos (warp)
- Fodder: Mankey, Machop, Poliwag, Hitmonlee, Hitmonchan, Hitmontop (johto), Heracross (johto), Galarian Farfetchd (warp), Combat Tauros (warp), Hisuian Sneasel (warp)
- Off-type: Geodude, Onix, Rhyhorn, Magnemite, Kangaskhan, Tauros, Snorlax, Lapras, Teddiursa (johto)

## Wild-area trainers

The optional ambush battles in the Wild Area. One team per round (1-9), on the same bands as the
gym leaders except that **band 4 covers rounds 7-9**. Team size is that round's largest route team
(2/3/4/4/5/5/6/6/6), levels are `STAGE_EVENT_R<n>_BASE` + 1 per slot, and the moveset row is the
route row for the round.

**Aces are optional** here, per band: a band with an `- Aces:` line puts a rolled ace in the last
slot; a band without one is all fodder, as these trainers always were. A band that HAS aces needs
an untagged one, as for gym leaders: an ace pool with nothing eligible does not skip the ace, it
fields the list's first entry regardless of run, so a Johto-only ace list would leak into a
Kanto-only run.

### JessieJames (Jessie & James)

The paired villain. "Line" families expanded to every member; the single-species entries
(Lickitung, Shellder, Chansey, Scyther, Growlithe, Mr Mime, Pinsir, Porygon, Hitmonlee) are not
expanded, because several evolutions are Warp-group and arrive by evolving once that group
unlocks. Band 1 has no ace (a 2-3 mon ambush); bands 2-4 roll Arbok or Weezing, the team's
signature pair (seeded 2026-10-07, edit freely).

**Band 1: rounds 1-2**
- Fodder: Meowth, Ekans, Lickitung, Shellder, Chansey, Koffing, Scyther, Clefairy, Growlithe, Mr Mime, Magikarp, Bellsprout, Pidgey, Pinsir, Grimer, Porygon, Krabby, Hitmonlee, Machop, Rhyhorn, Zubat, Mankey, Yanma (johto), Stantler (johto), Sneasel (johto), Hoppip (johto)

**Band 2: rounds 3-4**
- Aces: Arbok, Weezing
- Fodder: Meowth, Ekans, Lickitung, Shellder, Chansey, Koffing, Scyther, Clefairy, Growlithe, Mr Mime, Magikarp, Bellsprout, Pidgey, Pinsir, Grimer, Porygon, Krabby, Hitmonlee, Machop, Rhyhorn, Zubat, Mankey, Yanma (johto), Stantler (johto), Sneasel (johto), Hoppip (johto)

**Band 3: rounds 5-6**
- Aces: Arbok, Weezing
- Fodder: Meowth, Ekans, Lickitung, Shellder, Chansey, Koffing, Scyther, Clefairy, Growlithe, Mr Mime, Magikarp, Bellsprout, Pidgey, Pinsir, Grimer, Porygon, Krabby, Hitmonlee, Machop, Rhyhorn, Zubat, Mankey, Yanma (johto), Stantler (johto), Sneasel (johto), Hoppip (johto)

**Band 4: rounds 7-9**
- Aces: Arbok, Weezing
- Fodder: Meowth, Ekans, Lickitung, Shellder, Chansey, Koffing, Scyther, Clefairy, Growlithe, Mr Mime, Magikarp, Bellsprout, Pidgey, Pinsir, Grimer, Porygon, Krabby, Hitmonlee, Machop, Rhyhorn, Zubat, Mankey, Yanma (johto), Stantler (johto), Sneasel (johto), Hoppip (johto)

### Psychic (The Psychic)

Themed on the type, the same brief Sabrina's pool follows. Band 1 has no ace; bands 2-4 roll Alakazam or Hypno (seeded 2026-10-07, edit freely).

**Band 1: rounds 1-2**
- Fodder: Abra, Slowpoke, Drowzee, Exeggcute, Mr Mime, Jynx, Psyduck, Staryu, Clefairy, Porygon, Natu (johto), Girafarig (johto)

**Band 2: rounds 3-4**
- Aces: Alakazam, Hypno
- Fodder: Abra, Slowpoke, Drowzee, Exeggcute, Mr Mime, Jynx, Psyduck, Staryu, Clefairy, Porygon, Natu (johto), Girafarig (johto)

**Band 3: rounds 5-6**
- Aces: Alakazam, Hypno
- Fodder: Abra, Slowpoke, Drowzee, Exeggcute, Mr Mime, Jynx, Psyduck, Staryu, Clefairy, Porygon, Natu (johto), Girafarig (johto)

**Band 4: rounds 7-9**
- Aces: Alakazam, Hypno
- Fodder: Abra, Slowpoke, Drowzee, Exeggcute, Mr Mime, Jynx, Psyduck, Staryu, Clefairy, Porygon, Natu (johto), Girafarig (johto)

### Burglar (The Burglar)

Sneaky, venomous, urban-pest flavour rather than a type theme (Gen 1 has no Dark type to draw on). Band 1 has no ace; bands 2-4 roll Muk or Persian (seeded 2026-10-07, edit freely).

**Band 1: rounds 1-2**
- Fodder: Rattata, Ekans, Grimer, Koffing, Zubat, Meowth, Sandshrew, Gastly, Mankey, Diglett, Murkrow (johto), Sneasel (johto)

**Band 2: rounds 3-4**
- Aces: Muk, Persian
- Fodder: Rattata, Ekans, Grimer, Koffing, Zubat, Meowth, Sandshrew, Gastly, Mankey, Diglett, Murkrow (johto), Sneasel (johto)

**Band 3: rounds 5-6**
- Aces: Muk, Persian
- Fodder: Rattata, Ekans, Grimer, Koffing, Zubat, Meowth, Sandshrew, Gastly, Mankey, Diglett, Murkrow (johto), Sneasel (johto)

**Band 4: rounds 7-9**
- Aces: Muk, Persian
- Fodder: Rattata, Ekans, Grimer, Koffing, Zubat, Meowth, Sandshrew, Gastly, Mankey, Diglett, Murkrow (johto), Sneasel (johto)

### NurseJoy (Nurse Joy)

"Healing and cute", seeded from the donor species in `reference/yellow_legacy/joy_jenny/options.asm`, taken as a pool rather than pasted as the donor's flat level-65 team. Sylveon is VAPOREON form 2 and the one deliberate non-base entry: it is Time Warp content, so it carries `(warp)`, which is the only thing that stops a Kanto-only run fielding one (a pinned form index is passed through ungated). Eevee cannot guarantee it, because Eevee picks its evolution at random. Consequence: a round-1 Time Warp run can field a level-5 Sylveon, accepted as the price of having it. Band 1 has no ace; bands 2-4 roll Chansey or Snorlax (seeded 2026-10-07, edit freely).

**Band 1: rounds 1-2**
- Fodder: Kangaskhan, Snorlax, Staryu, Porygon, Exeggcute, Chansey, Jigglypuff, Clefairy, Pikachu, Miltank (johto), Marill (johto), Togepi (johto), Sylveon (warp)

**Band 2: rounds 3-4**
- Aces: Chansey, Snorlax
- Fodder: Kangaskhan, Snorlax, Staryu, Porygon, Exeggcute, Chansey, Jigglypuff, Clefairy, Pikachu, Miltank (johto), Marill (johto), Togepi (johto), Sylveon (warp)

**Band 3: rounds 5-6**
- Aces: Chansey, Snorlax
- Fodder: Kangaskhan, Snorlax, Staryu, Porygon, Exeggcute, Chansey, Jigglypuff, Clefairy, Pikachu, Miltank (johto), Marill (johto), Togepi (johto), Sylveon (warp)

**Band 4: rounds 7-9**
- Aces: Chansey, Snorlax
- Fodder: Kangaskhan, Snorlax, Staryu, Porygon, Exeggcute, Chansey, Jigglypuff, Clefairy, Pikachu, Miltank (johto), Marill (johto), Togepi (johto), Sylveon (warp)

### OfficerJenny (Officer Jenny)

Police-dog and patrol flavour, same donor source as Nurse Joy. Every entry is at its BASE form (Growlithe not Arcanine, Pidgey not Pidgeot, and so on): the trainer evolution engine promotes each one at a high enough level, so listing the base fixes the round-1 case without weakening round 9. Hitmonchan has no evolution in either direction here, so it is its own base. The Kanto run is deliberately 9 deep: the retry cap is 8, so a tighter pool repeats a species outright. Band 1 has no ace; bands 2-4 roll Arcanine (seeded 2026-10-07, edit freely).

**Band 1: rounds 1-2**
- Fodder: Pidgey, Squirtle, Tangela, Gastly, Paras, Growlithe, Machop, Ponyta, Hitmonchan, Spinarak (johto), Hoppip (johto), Chikorita (johto), Totodile (johto), Marill (johto), Snubbull (johto), Remoraid (johto)

**Band 2: rounds 3-4**
- Aces: Arcanine
- Fodder: Pidgey, Squirtle, Tangela, Gastly, Paras, Growlithe, Machop, Ponyta, Hitmonchan, Spinarak (johto), Hoppip (johto), Chikorita (johto), Totodile (johto), Marill (johto), Snubbull (johto), Remoraid (johto)

**Band 3: rounds 5-6**
- Aces: Arcanine
- Fodder: Pidgey, Squirtle, Tangela, Gastly, Paras, Growlithe, Machop, Ponyta, Hitmonchan, Spinarak (johto), Hoppip (johto), Chikorita (johto), Totodile (johto), Marill (johto), Snubbull (johto), Remoraid (johto)

**Band 4: rounds 7-9**
- Aces: Arcanine
- Fodder: Pidgey, Squirtle, Tangela, Gastly, Paras, Growlithe, Machop, Ponyta, Hitmonchan, Spinarak (johto), Hoppip (johto), Chikorita (johto), Totodile (johto), Marill (johto), Snubbull (johto), Remoraid (johto)

## Champions

The final battle: the Champion rival, or Champion Lance (when he missed the Elite Four draw), or
Prof. Oak (Kanto Time Warp). One team each, so each has a single band. Six mons at
`CHAMPION_R1_BASE` + `CHAMPION_R1_STEP` per slot (`CHAMPION_BASE_LEVEL` / `CHAMPION_LEVEL_STEP`
in `constants/balance_constants.asm`), every slot a curated set (`MIX_E4_SETS`).

### Rival3 (Champion rival)

His ace is always his own starter, evolved, pinned in `party_specs.asm`, so this block has no
`- Aces:` line. Fodder entries are BASE forms, and that is load-bearing: NO_RIVAL_STARTER rejects
a draw equal to his starter, which is always a base species, so a base-form pool blocks the whole
line of whatever he picked (list Charmander, never Charmeleon; Seadra is entered as Horsea, and
the engine evolves it to Kingdra at these levels anyway). The accepted exceptions are the
eeveelutions and Scizor/Electivire: only an Eevee / Scyther / Electabuzz starter can double up
with those. Moved from `RivalThreePool` (party roster Phase 5, 2026-10-07), entry for entry.

**Band 1: the Champion**
- Fodder: Growlithe, Ponyta, Weedle, Charmander, Nidoran M, Electabuzz, Slowpoke, Pidgey, Bulbasaur, Squirtle, Rhyhorn, Nidoran F, Magmar, Scyther, Krabby, Geodude, Doduo, Eevee, Vaporeon, Jolteon, Flareon, Pinsir, Spearow, Abra, Horsea, Magikarp, Exeggcute, Sandshrew, Vulpix, Magnemite, Shellder, Machop, Aerodactyl, Tauros, Cubone, Clefairy, Gastly, Dratini, Zapdos, Rattata, Scizor (johto), Larvitar (johto), Houndour (johto), Skarmory (johto), Heracross (johto), Miltank (johto), Swinub (johto), Espeon (johto), Umbreon (johto), Electivire (warp), Glaceon (warp), Sylveon (warp), Leafeon (warp)

### ChampionLance (Champion Lance)

Lance on the Champion's throne. Until now he fielded the Elite Four Lance's tier-4 records; he
now has his own team at Champion levels. Seeded from the Elite Four Lance's pool (fodder at base
forms) with his signature dragons as aces; edit freely.

**Band 1: the Champion**
- Aces: Dragonite, Dragonite, Gyarados, Aerodactyl, Charizard, Kingdra (johto), Tyranitar (johto)
- Fodder: Dratini, Magikarp, Aerodactyl, Charmander, Horsea, Lapras, Exeggcute, Kangaskhan, Growlithe, Snorlax, Electabuzz, Larvitar (johto), Totodile (johto), Mareep (johto), Alolan Exeggutor (warp)

### ProfOak (Prof. Oak)

The Time Warp Champion. Seeded from his old authored team (Tauros, Exeggutor, Arcanine, Gyarados
and one Kanto starter's final form): those are his aces, plus Mew, which only he may field (his
spec sets ALLOW_UBER). The fodder is the same team at base forms plus a few classic Kanto
partners and the Johto starters; edit freely.

**Band 1: the Champion**
- Aces: Blastoise, Venusaur, Charizard, Tauros, Gyarados, Arcanine, Exeggutor, Mew
- Fodder: Tauros, Exeggcute, Growlithe, Magikarp, Bulbasaur, Charmander, Squirtle, Pidgey, Kangaskhan, Lapras, Chikorita (johto), Cyndaquil (johto), Totodile (johto)

## Gamblers

Gambler's Paradise (witch challenge 13) sends the next stage to the Game Corner, whose trainers
are Gamblers fielding themed teams with forced movesets, mostly one-hit KOs and trapping moves. Team sizes and levels are the route
trainer's (the roster path). Only the species and the moves come from here (party roster Phase 6,
2026-10-07; until then both were `data/trainers/gambler_movesets.asm`).

### Gambler (Gambler's Paradise)

**The pool** is one Fodder list, used in every round. Entries are **evolved by level** like any
fodder (Dragonair becomes Dragonite at 55, Onix becomes Steelix at 38), and the moves are looked
up on the species actually fielded. Duplicates are allowed, as they always were for gamblers.
No pinned forms: the roster rolls its own forms, and a set cannot name one.

**Band 1: every round**
- Fodder: Dugtrio, Rhydon, Marowak, Golem, Tauros, Nidoking, Dragonite, Dragonair, Rapidash, Arbok, Lickitung, Onix, Pinsir, Omastar, Kingler, Cloyster, Tentacruel, Moltres, Ninetales, Arcanine, Flareon, Tangela

#### Sets: TIER_GAMBLER | TIER_HARD

One row per set, four moves. `tools/gen_movesets.py` copies them into the curated corpus
(`data/trainers/movesets.asm`) with the tiers the heading names, and `MIX_GAMBLER` gives every
gambler slot one through `TIER_GAMBLER`. `TIER_HARD` also puts them in the shared pool: any
trainer whose moveset row draws hard sets (gym leaders and mini-bosses from gym 5 on, and the
gyms 7-8 gym trainers) can roll one for a species listed here. Drop `TIER_HARD` from the
heading to make them gambler-only again. **Every species the pool can field needs a row**, its evolutions included:
`gen_party_roster.py --check` (part of `make audit`) fails otherwise, and also fails when
`movesets.asm` is out of step with this table. A species may have more than one row; one is
picked at random.

Design rules (carried over from the old table): one OHKO move at most, and a trap may pair with
it; slow OHKO users carry a paralysis move (Body Slam, Thunder Wave, Glare) so the AI can flip
Gen 1's slower-misses rule before firing; fast ones skip setup and carry a nuke; every setup move
is backed by a real attack. Level timing is ignored: a move is fair if the species learns it at
any level or by TM/tutor. Notes cite this repo's data (`e:NNNN` = a line of
`data/pokemon/evos_moves.asm`, TM = its base stats tmhm list, tut = the tutor block).

| Species | Moves | Notes |
|---|---|---|
| Dugtrio | Fissure, Earthquake, Rock Slide, Slash | spd120 fast: FISSURE TM, EQ TM, ROCK_SLIDE TM, SLASH e:2357 |
| Rhydon | Fissure, Body Slam, Earthquake, Rock Slide | spd40 slow: FISSURE TM, BODY_SLAM TM(para), EQ e:231, ROCK_SLIDE e:230 |
| Marowak | Fissure, Body Slam, Earthquake, Fire Blast | spd45 slow: all TM |
| Golem | Fissure, Body Slam, Earthquake, Metronome | spd45 slow: all TM; METRONOME = gambler chaos |
| Tauros | Horn Drill, Body Slam, Earthquake, Fire Blast | spd110 fast: all TM |
| Nidoking | Horn Drill, Earthquake, Thunderbolt, Body Slam | spd85: all TM |
| Dragonite | Horn Drill, Wrap, Thunder Wave, Blizzard | HORN_DRILL TM, WRAP lv1, T-WAVE lv1(para), BLIZZARD TM |
| Dragonair | Horn Drill, Wrap, Thunder Wave, Thunderbolt | HORN_DRILL TM, WRAP lv1, T-WAVE lv1(para), TBOLT TM |
| Rapidash | Horn Drill, Fire Spin, Fire Blast, Body Slam | spd105 fast: HORN_DRILL TM, FIRE_SPIN e:3032, FIRE_BLAST e:3034, BODY_SLAM TM |
| Arbok | Wrap, Fissure, Glare, Earthquake | WRAP lv1, FISSURE TM, GLARE e:1139(para), EQ TM |
| Lickitung | Wrap, Fissure, Body Slam, Thunderbolt | spd30 slow: WRAP lv1, FISSURE TM, BODY_SLAM e:463(para), TBOLT TM |
| Onix | Fissure, Bind, Body Slam, Earthquake | FISSURE TM, BIND e:921, BODY_SLAM TM(para), EQ TM |
| Pinsir | Guillotine, Bind, Slash, Seismic Toss | GUILLOTINE e:846, BIND e:847, SLASH e:845, SEISMIC_TOSS e:842 |
| Omastar | Clamp, Horn Drill, Hydro Pump, Spike Cannon | CLAMP e:2005, HORN_DRILL TM, HYDRO_PUMP e:2006, SPIKE_CANNON e:2002 |
| Kingler | Guillotine, Crabhammer, Body Slam, Bubblebeam | GUILLOTINE e:2639, CRABHAMMER e:2637, BODY_SLAM TM(para), BUBBLEBEAM e:2634 |
| Cloyster | Clamp, Blizzard, Ice Beam, Spike Cannon | CLAMP lv1, BLIZZARD TM, ICE_BEAM TM, SPIKE_CANNON e:2658 |
| Tentacruel | Wrap, Hydro Pump, Bubblebeam, Constrict | WRAP e:2920, HYDRO_PUMP e:2921, BUBBLEBEAM e:2915, CONSTRICT e:2916(spd drop) |
| Moltres | Fire Spin, Fire Blast, Sky Attack, Agility | FIRE_SPIN e:1594, FIRE_BLAST e:1592, SKY_ATTACK e:1593, AGILITY e:1590 |
| Ninetales | Fire Spin, Fire Blast, Flamethrower, Confuse Ray | FIRE_SPIN e:1718, FIRE_BLAST TM, FLAMETHROWER e:1716, CONFUSE_RAY e:1714 |
| Arcanine | Fire Spin, Fire Blast, Body Slam, Take Down | FIRE_SPIN tut e:666, FIRE_BLAST TM, BODY_SLAM TM, TAKE_DOWN e:661 |
| Flareon | Fire Spin, Fire Blast, Body Slam, Quick Attack | FIRE_SPIN e:2095, FIRE_BLAST e:2096, BODY_SLAM TM, QUICK_ATTACK e:2089 |
| Tangela | Bind, Sleep Powder, Mega Drain, Stun Spore | BIND e:869, SLEEP_POWDER e:865, MEGA_DRAIN e:866, STUN_SPORE e:864 |
| Rhyperior | Horn Drill, Body Slam, Earthquake, Rock Slide | Rhydon evolves at L40 (trade rule). spd40 slow: HORN_DRILL e:4765/TM, BODY_SLAM TM(para), EQ e:4767/TM, ROCK_SLIDE e:4764/TM. Horn Drill, not Rhydon's Fissure, for variety |
| Lickilicky | Fissure, Body Slam, Thunderbolt, Ice Beam | Lickitung evolves at L32. spd50 slow: FISSURE TM, BODY_SLAM TM(para), TBOLT TM, ICE_BEAM TM. No trap: Wrap is not in its own learnset |
| Steelix | Fissure, Bind, Body Slam, Earthquake | Onix evolves at L38. Onix's set, all legal here: FISSURE TM, BIND e:4148, BODY_SLAM TM(para), EQ TM |
| Tangrowth | Bind, Sleep Powder, Mega Drain, Stun Spore | Tangela evolves at L44. Tangela's set, all legal here: BIND e:4747, SLEEP_POWDER e:4752, MEGA_DRAIN TM, STUN_SPORE e:4751 |

## Elite Four

Seven members, four of them per run (Will, Karen and Koga only with Johto on). One team per
member per tier, four tiers, all on one band: six mons at `E4_BASE_LEVEL` + tier + 2 per slot,
every slot a curated set (`MIX_E4_SETS`). Moved here from flat pools and pinned aces in party
roster Phase 7a (2026-10-07): until then one fight in three had no ace at all (the old variant
B); now every fight draws one from Aces. List an ace twice to double its odds.

### Lorelei (ICE)

The member's original team plus every species of the type, expanded with `tools/list_pool_candidates.py` (Trainer Revamp, TRAINER_REVAMP_FIXES_PLAN.md steps 4 and 7). Uber-tier species (Mew, Mewtwo, Celebi, Lugia, Ho-Oh) are left out: an Elite Four spec does not allow them.

Aces: the two signature aces the old records pinned (variant A and C), now one is drawn for every fight. Fodder: the old pool, entry for entry.

**Band 1: every tier**
- Aces: Lapras, Cloyster
- Fodder: Dewgong, Cloyster, Slowbro, Jynx, Lapras, Articuno, Exeggutor, Wigglytuff, Starmie, Omastar, Poliwrath, Swinub (johto), Piloswine (johto), Sneasel (johto), Slowking (johto), Mamoswine (warp), Mr Rime (warp), Weavile (warp), Galarian Mr Mime (warp), Alolan Ninetales (warp), Alolan Sandshrew (warp), Alolan Sandslash (warp), Glaceon (warp), Alolan Vulpix (warp)

### Bruno (FIGHTING)

The member's original team plus every species of the type, expanded with `tools/list_pool_candidates.py` (Trainer Revamp, TRAINER_REVAMP_FIXES_PLAN.md steps 4 and 7). Uber-tier species (Mew, Mewtwo, Celebi, Lugia, Ho-Oh) are left out: an Elite Four spec does not allow them.

Aces: the two signature aces the old records pinned (variant A and C), now one is drawn for every fight. Fodder: the old pool, entry for entry.

**Band 1: every tier**
- Aces: Machamp, Hitmontop (johto)
- Fodder: Hitmonchan, Hitmonlee, Machamp, Machoke, Machop, Mankey, Poliwrath, Primeape, Clefable, Muk, Slowbro, Rhydon, Golem, Onix, Kangaskhan, Blastoise, Exeggutor, Cloyster, Heracross (johto), Hitmontop (johto), Steelix (johto), Granbull (johto), Ursaring (johto), Annihilape (warp), Sirfetchd (warp), Galarian Farfetchd (warp), Hisuian Sneasel (warp), Combat Tauros (warp), Blaze Tauros (warp), Aqua Tauros (warp), Galarian Zapdos (warp), Alolan Golem (warp)

### Agatha (GHOST)

The member's original team plus every species of the type, expanded with `tools/list_pool_candidates.py` (Trainer Revamp, TRAINER_REVAMP_FIXES_PLAN.md steps 4 and 7). Uber-tier species (Mew, Mewtwo, Celebi, Lugia, Ho-Oh) are left out: an Elite Four spec does not allow them.

Aces: the two signature aces the old records pinned (variant A and C), now one is drawn for every fight. Fodder: the old pool, entry for entry.

**Band 1: every tier**
- Aces: Gengar, Alolan Marowak (warp)
- Fodder: Gastly, Haunter, Gengar, Arbok, Beedrill, Bellsprout, Bulbasaur, Ekans, Gloom, Golbat, Grimer, Ivysaur, Kakuna, Koffing, Muk, Nidoking, Nidoqueen, Nidoran F, Nidoran M, Nidorina, Nidorino, Oddish, Tentacool, Tentacruel, Venomoth, Venonat, Venusaur, Victreebel, Vileplume, Weedle, Weepinbell, Weezing, Zubat, Marowak, Ninetales, Jynx, Alakazam, Gyarados, Misdreavus (johto), Ariados (johto), Crobat (johto), Qwilfish (johto), Spinarak (johto), Annihilape (warp), Mismagius (warp), Alolan Marowak (warp), Alolan Grimer (warp), Alolan Muk (warp), Hisuian Qwilfish (warp), Galarian Slowbro (warp), Galarian Slowking (warp), Hisuian Sneasel (warp), Galarian Weezing (warp), Paldean Wooper (warp)

### Lance (DRAGON)

The member's original team plus every species of the type, expanded with `tools/list_pool_candidates.py` (Trainer Revamp, TRAINER_REVAMP_FIXES_PLAN.md steps 4 and 7). Uber-tier species (Mew, Mewtwo, Celebi, Lugia, Ho-Oh) are left out: an Elite Four spec does not allow them.

Aces: the two signature aces the old records pinned (variant A and C), now one is drawn for every fight. Fodder: the old pool, entry for entry.

**Band 1: every tier**
- Aces: Dragonite, Kingdra (johto)
- Fodder: Dragonair, Dragonite, Dratini, Gyarados, Aerodactyl, Charizard, Horsea, Seadra, Lapras, Exeggutor, Kangaskhan, Arcanine, Snorlax, Electabuzz, Kingdra (johto), Larvitar (johto), Pupitar (johto), Tyranitar (johto), Steelix (johto), Feraligatr (johto), Ampharos (johto), Alolan Exeggutor (warp), Electivire (warp)

### KogaE4 (POISON)

The Elite Four Koga's own pool, split from the gym KogaPool because the two roles now differ: Articuno is Elite Four only (and Beedrill gym only).

Aces: the two signature aces the old records pinned (variant A and C), now one is drawn for every fight. Fodder: the old pool, entry for entry.

**Band 1: every tier**
- Aces: Crobat (johto), Galarian Weezing (warp)
- Fodder: Ekans, Arbok, Nidoran M, Nidorino, Nidoking, Nidoran F, Nidorina, Nidoqueen, Zubat, Golbat, Grimer, Muk, Weezing, Koffing, Venonat, Venomoth, Gastly, Haunter, Gengar, Bulbasaur, Ivysaur, Venusaur, Oddish, Gloom, Vileplume, Bellsprout, Weepinbell, Victreebel, Weedle, Kakuna, Tentacool, Tentacruel, Parasect, Tangela, Hypno, Electrode, Magmar, Lapras, Scyther, Rhydon, Ninetales, Chansey, Ditto, Pidgey, Pidgeotto, Pidgeot, Vaporeon, Articuno, Crobat (johto), Qwilfish (johto), Ariados (johto), Spinarak (johto), Forretress (johto), Stantler (johto), Lanturn (johto), Scizor (johto), Girafarig (johto), Meganium (johto), Shuckle (johto), Alolan Grimer (warp), Alolan Muk (warp), Hisuian Qwilfish (warp), Galarian Slowbro (warp), Galarian Slowking (warp), Hisuian Sneasel (warp), Galarian Weezing (warp), Paldean Wooper (warp)

### Will (PSYCHIC)

Will - Elite Four, Psychic. Named additions (CLEFABLE/ ELECTABUZZ/MANTINE/FLAREON/CHANSEY/HYPNO) plus every PSYCHIC_TYPE species and form (tools/list_pool_candidates.py PSYCHIC_TYPE). ESPEON is this tree's JOLTEON form 1 (there is no ESPEON species - see [[project_forms_are_not_species]]), sitting in the Warp run with every other pinned form so it stays gated on a Kanto-only run. NATU is added alongside the brief's own XATU as its pre-evolution.

Aces: the two signature aces the old records pinned (variant A and C), now one is drawn for every fight. Fodder: the old pool, entry for entry.

**Band 1: every tier**
- Aces: Xatu (johto), Espeon (johto)
- Fodder: Exeggutor, Slowbro, Jynx, Alakazam, Clefable, Electabuzz, Flareon, Chansey, Hypno, Abra, Kadabra, Drowzee, Mr Mime, Slowpoke, Starmie, Natu (johto), Xatu (johto), Slowking (johto), Girafarig (johto), Mantine (johto), Espeon (warp), Mr Rime (warp), Galarian Articuno (warp), Scream Tail (warp), Galarian Mr Mime (warp), Galarian Ponyta (warp), Alolan Raichu (warp), Galarian Rapidash (warp), Galarian Slowbro (warp), Galarian Slowking (warp), Galarian Slowpoke (warp)

### Karen (DARK)

Karen - Elite Four, Dark. UMBREON is JOLTEON form 2 in this tree, pinned for the same reason WillPool pins Espeon.  Dark did not exist as a type until Generation 2, so no Gen 1 species in this dex was ever Dark-typed, and this tree has no DARK type to sweep with tools/list_pool_candidates.py - the Warp pins below are the real-world Dark-types named by hand (Alolan Persian/Meowth/Rattata/Raticate/ Muk/Grimer, Galarian Moltres, Hisuian Qwilfish).  An empty Kanto run is a real fault, not just thin content: with Johto locked every run of the pool would be ineligible, PartyGenRollFromPool takes its .giveUp branch, and that branch falls back to the pool's FIRST entry UNFILTERED - yielding a team of six identical Murkrow rather than a crash, which is exactly the kind of fault that survives a clean build. The Kanto run below (her own Gen 2 roster's Kanto half plus other Kanto-side additions) keeps that from ever happening, even though Karen is only expected to be drawn with Johto enabled.

Aces: the two signature aces the old records pinned (variant A and C), now one is drawn for every fight. Fodder: the old pool, entry for entry.

**Band 1: every tier**
- Aces: Houndoom (johto), Umbreon (johto)
- Fodder: Gengar, Vileplume, Arbok, Persian, Golbat, Magmar, Slowbro, Electrode, Rapidash, Flareon, Murkrow (johto), Houndour (johto), Houndoom (johto), Sneasel (johto), Tyranitar (johto), Larvitar (johto), Pupitar (johto), Misdreavus (johto), Ursaring (johto), Umbreon (warp), Alolan Persian (warp), Alolan Meowth (warp), Alolan Rattata (warp), Alolan Raticate (warp), Alolan Muk (warp), Alolan Grimer (warp), Galarian Moltres (warp), Hisuian Qwilfish (warp)
