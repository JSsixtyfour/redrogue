# Battle Changes in Red Rogue

Every way battles differ from Pokémon Red and Blue, with exact numbers. Anything not listed here
should play like the original games ("vanilla" below).

Many of the fixes come from [other ROM hacks](#where-these-changes-come-from). If you know Shin
Pokémon Red, check [what Red Rogue did not take from it](#not-taken-from-shin-pokémon-red).

| Tag | Meaning |
|---|---|
| **FIX** | An original-game bug now does what it was clearly meant to do |
| **RULE** | A deliberate rule change |
| **RUN** | Only happens if you earn or choose it during a run |

**Contents:** [What to know first](#what-to-know-first) · [Damage](#damage-and-type-chart) ·
[Crits](#critical-hits) · [Accuracy](#accuracy-and-evasion) · [Stats](#stats-stages-and-badges) ·
[Status](#status) · [Substitute](#substitute) · [Moves](#move-by-move) · [Turn order](#turn-order-and-switching) ·
[Enemies](#enemy-pokémon-and-ai) · [EXP](#exp-and-levelling) · [Items and escape](#items-catching-and-escape) ·
[Run effects](#run-effects) · [Still vanilla](#still-vanilla-do-not-get-caught) · [Known issues](#known-issues) ·
[Sources](#where-these-changes-come-from) · [Change log](#change-log)

---

## What to know first

1. **Ghost hits Psychic for 2x.** Vanilla had it doing nothing.
2. **100% accurate moves never miss.** The 1/256 miss is gone.
3. **Focus Energy works:** 4x crit rate, where vanilla cut it to a quarter.
4. **Badges give no stat boosts.**
5. **Sleep Clause is enforced on both sides.**
6. **Enemies spend PP and have real DVs.** On higher AI tiers they also have stat experience.
7. **Enemy stat-lowering moves lost their hidden 25% miss chance.** Their Growl and Screech land more often.
8. **Substitute blocks sleep, Thunder Wave, Leech Seed and secondary confusion.**
9. **Trainers never use items.** They switch, and a switch goes before every move.
10. **Special Key Items only in battle** and no running from trainers or from wild-area battles.

All 151 original Pokémon keep their vanilla base stats, types and EXP growth rates, but many learnsets
and starting moves are different. These changes can be viewed a Pokemon's status screen on Pokedex entry.

---

## Damage and type chart

| Change | Vanilla | Red Rogue | Tag |
|---|---|---|---|
| Ghost attacking Psychic | 0x | **2x** | FIX |
| All other matchups | | Unchanged (Bug and Poison still hit each other for 2x, and so on) | |
| Dual types | One multiply per matching type, so a 2x and 0.5x pair could lose 1 damage | Both types combined, applied once | FIX |
| "Super effective" text and sound | Could report only the last matching type | Reports the true combined result | FIX |
| Multi-hit moves | Effectiveness text on every hit | Once, on the first hit | FIX |
| Reflect / Light Screen on a huge stat | Wrapped around and made the defender *weaker* | Doubled stat capped at 999 | FIX |
| Very low Defense or Special after scaling | Could divide by zero and freeze the game | Treated as at least 1 | FIX |
| Psywave (enemy) | Could deal 0 | Always at least 1, same range as yours | FIX |

Fixed-damage moves still ignore type immunity: see [Still vanilla](#still-vanilla-do-not-get-caught).

## Critical hits

| Change | Vanilla | Red Rogue | Tag |
|---|---|---|---|
| Focus Energy | 1/4 of normal crit rate | **4x** normal crit rate, capped at 255/256 | FIX |
| Crit while Transformed | Used the user's own original stats | Uses the copied stats | FIX |
| Crit above level 127 | Doubled level wrapped around, so crits did *less* damage | Full crit damage (Endless mode) | FIX |
| Base Speed of a regional or alternate form | | The form's own base Speed sets its crit rate | RULE |

Crit rate still comes from base Speed, the high-crit move list is unchanged, and crits still ignore all
stat stages, screens, burn and paralysis drops, good and bad.

## Accuracy and evasion

| Change | Vanilla | Red Rogue | Tag |
|---|---|---|---|
| Hit roll | Must be *below* the threshold | *At or below*, so every move gains 1/256 (0.39 points) | FIX |
| Enemy stat-lowering status moves | Extra 25% miss chance against you | Removed | RULE |
| Rage, Thrash, Petal Dance | Lost accuracy on every repeated turn under an accuracy drop | Reset to 100% each turn | FIX |

| Listed | Vanilla | Red Rogue |
|---:|---:|---:|
| 100% | 99.61% | **100%** |
| 95% | 94.53% | 94.92% |
| 90% | 89.45% | 89.84% |
| 85% | 84.38% | 84.77% |
| 80% | 79.69% | 80.08% |
| 75% | 74.61% | 75.00% |
| 70% | 69.53% | 69.92% |
| 55% | 54.69% | 55.08% |
| 30% | 29.69% | 30.08% |

Neutral accuracy and evasion. Base accuracy values are the same as vanilla for every move.

## Stats, stages and badges

| Change | Vanilla | Red Rogue | Tag |
|---|---|---|---|
| Badge stat boosts | x1.125 from four badges | **None.** The same x1.125 is earned through [run effects](#run-effects) | RULE |
| Boost stacking | Any stat change re-boosted all four stats, again and again | Only the stat that changed is recalculated | FIX |
| Stat-raising move while burned or paralyzed | Re-applied the penalty to the **opponent** | Re-applies your own, on that stat only | FIX |
| Stat-lowering move on a burned or paralyzed target | Halved Attack / quartered Speed again every time | Penalty re-applied only to the stat that was lowered | FIX |
| Haze and earned boosts | Wiped until you switched | Put back after Haze | FIX |

Example: Leer on a burned target no longer halves its Attack again, and Agility on a paralyzed user
no longer cuts the opponent's Speed.

## Status

**Sleep Clause (RULE).** A side cannot put a second opposing Pokémon to sleep while one *it already put
to sleep* is still asleep.
- It is checked after the hit roll, and the move fails.
- It applies to both sides, in every battle, wild ones included.
- Your own Rest never counts and is never blocked.
- It ends when that Pokémon wakes, is cured or faints. Sleep from an earlier battle does not count.
- The move menu warns you the first time in a battle. You can pick the move again anyway.

| Change | Vanilla | Red Rogue | Tag |
|---|---|---|---|
| Sleep move on a recharging target | Never missed and overwrote other statuses | Normal accuracy and status checks | FIX |
| Frozen Pokémon | Skipped move selection | Picks a move, so if a Fire move thaws it first, it acts that turn | FIX |
| Your Fire move thawing a frozen wild Pokémon | Could change unrelated memory | Only thaws the wild Pokémon | FIX |
| Freezing a recharging Pokémon | Could leave your Pokémon stuck | Recharge is cleared on both sides | FIX |
| Full paralysis or confusion during Fly/Dig | Left the Pokémon invulnerable | Invulnerability ends | FIX |
| Rest | Kept burn/paralysis stat drops and the Toxic counter | Clears both | FIX |
| A trainer's burned or paralyzed Pokémon sent back in | Full Attack or Speed again | Keeps its drop (half Attack, quarter Speed), as yours does | FIX |
| Haze | Cured the target only | Cures **both** sides and resets both Toxic counters | FIX |
| Haze on a Pokémon locked into Bide, Thrash, Rage or a recharge | Could leave it unable to act | It keeps going | FIX |
| Disable | 0 to 7 blocked turns on a slower target | 1 to 8, always at least one | FIX |
| Disable against enemies | Could pick a move with no PP | Only moves with PP | FIX |
| Struggle with Disable and PP Ups | Could leave you with no legal move | Struggles | FIX |

A Pokémon that Haze wakes or thaws still loses that turn, as in vanilla.

## Substitute

| Change | Vanilla | Red Rogue | Tag |
|---|---|---|---|
| Sleep moves | Went through | **Blocked** | FIX |
| Thunder Wave and other paralysis moves | Went through | **Blocked** | FIX |
| Leech Seed | Went through | **Blocked** | RULE |
| Secondary confusion (Psybeam, Confusion) | Went through | **Blocked** | FIX |
| Absorb, Mega Drain, Leech Life on a Substitute | Damaged it and healed | Damage it, **no healing** | RULE |
| Dream Eater on a Substitute | Worked | Misses | FIX |
| Damage exactly equal to its HP | Left it up with 0 HP | Breaks it | FIX |
| Making one when it costs all your HP | Left you at 0 HP | Fails | FIX |
| Multi-hit move breaks it | Remaining hits stopped | Remaining hits land on the Pokémon | FIX |
| Explosion / Selfdestruct breaks it | User survived | User faints | FIX |
| Recoil move breaks it | No recoil | Recoil applies | FIX |
| Confusion self-hit, Jump Kick crash | Hit the *opponent's* Substitute | Hit the user's own HP | FIX |

Hyper Beam still skips its recharge when it breaks a Substitute.

## Move by move

| Move | Vanilla | Red Rogue | Tag |
|---|---|---|---|
| **Bide** | Added "last damage dealt" once per turn, whoever it was dealt to, so one hit could count twice | Adds each hit it takes, as it lands. Multi-hit moves count every hit | FIX |
| **Counter** | Could reflect an earlier round's damage onto a Pokémon that just switched in, or reflect damage the target did to itself | Only damage from this round's attack. Confusion self-hits, crashes and switch-ins are safe | FIX |
| **Struggle** | Normal type, could not hit Ghosts | Typeless: hits everything for neutral damage, no STAB for Normal types. Counter can reflect it | RULE |
| **Wrap, Bind, Clamp, Fire Spin** | Trapped a target even if it was immune | Do not trap a target their type cannot affect | FIX |
| A trainer switches out of *your* trapping move | It carried on against the next Pokémon, and its PP could wrap from 0 to 63 | It ends, and you lose that turn | FIX |
| Same moves vs a recharging target | Cleared its recharge even on a miss | Only when they hit | FIX |
| **Recover, Softboiled, Rest** | Failed when missing exactly 255 or 511 HP | Work | FIX |
| **Transform** | Two Transform users could loop forever | Fails if either Pokémon is already transformed. Clears the user's Disable | RULE |
| Levelling up while transformed | Replaced the copied moves and stats with your own | Keeps them. You gain the level and the HP | FIX |
| Transform, special forms | | The user keeps its own variant flags | RULE |
| **Metronome** | Any move | Cannot pick Whirlwind, Teleport or Super Transform | RULE |
| Metronome / Mirror Move while transformed | Could corrupt stored PP | Fixed | FIX |
| A wild Pokémon's Metronome or Mirror Move | Could change unrelated memory, or crash the game | Only its own PP is refunded | FIX |
| **Roar** | | Replaced by the gift-only **Super Transform**: Transform that also copies max HP, current HP and full PP | RUN |
| **Whirlwind, Teleport** | | Unobtainable, no effect | RULE |
| **Pay Day** | Wrong above level 127 | Fixed | FIX |

No other move had its power, type, accuracy or base PP changed.

### Trapping moves and Counter

A trapping move rolls its damage once and deals the same amount on every continuation turn, so the game
has to remember that number between rounds. Every other move's damage is forgotten when the round ends.
The number is also dropped when you switch, so Counter cannot hit your replacement with it.

## Turn order and switching

| Change | Vanilla | Red Rogue | Tag |
|---|---|---|---|
| Trainer switching | Happened at that Pokémon's place in the speed order | **Before every move** (Gen 2 style) | RULE |
| Trainer switching while locked in | Possible | Not while recharging, or during Rage, Bide, Thrash, Petal Dance, Fly, Dig, a charging move or its own trapping move | FIX |
| When the enemy decides | After you picked | **Before your menu opens.** It cannot react to your switch or item | RULE |
| Next enemy Pokémon | First healthy one in party order | Chosen for the matchup | RULE |
| Witch recoil and Life Orb | | Applied before the enemy faint check, so a knockout still costs you, as vanilla recoil does | RUN |

Quick Attack first, Counter last, then Speed, with a 50/50 tie: unchanged. The one exception to the
enemy deciding first is a single postgame boss, which does read your choice.

## Enemy Pokémon and AI

**PP.** Enemies spend PP, trainers' Pokémon keep it after switching, and they Struggle when they run
out. Vanilla enemies had infinite PP, so endless Wrap is no longer possible.

**Items.** Trainers use none.

**Wild Pokémon,** wild-area bosses included, pick their moves at random, as in vanilla.

**AI tier** depends on difficulty and on the round (R). A round is usually **8 battles: a route
(4 trainers), then a gym (3 trainers and the leader).** Rounds 4 and 7 skip the route: those gyms follow
straight on from the one before.

Route and gym trainers:

| Difficulty | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R8 | Victory Road, Elite Four | Highest |
|---|---|---|---|---|---|---|---|---|---|---|
| Very Easy | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Easy | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 | 1 | 1 |
| Normal | 0 | 0 | 0 | 1 | 1 | 1 | 2 | 2 | 2 | 2 |
| Hard | 0 | 0 | 1 | 1 | 2 | 2 | 2 | 3 | 3 | 3 |
| Very Hard | 1 | 1 | 1 | 2 | 2 | 2 | 3 | 3 | 3 | 3 |

Mini-bosses, the last trainer of a route and the last trainer before a gym leader are one tier higher,
up to the "Highest" column.

Gym leaders (the next round's tier, plus one):

| Difficulty | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R8 |
|---|---|---|---|---|---|---|---|---|
| Very Easy | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Easy | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| Normal | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 |
| Hard | 1 | 2 | 2 | 3 | 3 | 3 | 3 | 3 |
| Very Hard | 2 | 2 | 3 | 3 | 3 | 3 | 3 | 3 |

Difficulty also changes enemy levels: -30%, -20%, -10%, 0%, +10% in the order above.

| Tier | Plays like | DVs (Atk/Def/Spd/Spc) | Stat experience, every stat |
|---|---|---|---|
| 0 Novice | Avoids useless moves and immunities | Fixed 9/8/8/8, as vanilla trainers | 0 |
| 1 Competent | Knows matchups, setup and status value | Random, each 10 to 15 | Level x 64 |
| 2 Skilled | Estimates damage, plans knockouts, switches out of bad matchups | Random, each 12 to 15 | Level x 128 |
| 3 Expert | Weighs your threats, multi-turn plans, calculated risks | Random, each 14 to 15 | Level x 256 |

**Switching.** Tiers 2 and 3 switch for a reason. At tiers 0 and 1 only Jugglers, female Cooltrainers,
Agatha, Morty and Karen switch, at random.

**What it knows.** Types, HP, status and stat stages, as you can see on screen. It knows a move of yours
only after you use it, and otherwise guesses from your species. While your Pokémon is transformed it knows
your moves, since they are copied from its own. Only the final boss knows everything.

**Player-side effects in enemy hands.** Enemy teams can field forms, variants and special forms. Their
Ghost variants have Ghost as their second type.

**Traded or high-level Pokémon never disobey you** (RULE).

## EXP and levelling

| Change | Vanilla | Red Rogue | Tag |
|---|---|---|---|
| Several Pokémon fought | EXP split between them | Each gets the **full** amount | RULE |
| EXP All | Key item | EXP Share option: every living party Pokémon gets 68.75% | RULE |
| Traded Pokémon | x1.5 EXP | No bonus | RULE |
| Wild battles | x1 | x1.5, same as trainers | RULE |
| Gaining several levels at once | Skipped moves in between | Learns every move along the way | FIX |
| Two moves at the same level | Only the first was offered | All are offered | FIX |
| HM moves | Could not be forgotten | Can be forgotten like any other move | RULE |
| Evolution | After battle | Can happen mid-battle | RULE |
| Level cap | 100 | 235 (Endless mode) | RULE |

## Items, catching and escape

- *Limited bag in battle.** The ITEM list shows your active key items and the Poke Flute. Certain Key items can
  be used in battle. The rare Pokeflute is among them. (RULE)
- **Wild Pokémon cannot be caught,** except in the Safari Zone. (RULE)
- **END replaces RUN** and gives up the run, after a confirmation. (RULE)
- **No running** from trainers or wild-area battles. (RULE)
- **Ironman (optional):** a Pokémon that faints is released after the battle. REVIVE and MAX REVIVE are
  never offered with Ironman on: not in item balls, as rewards, or at the healing clerk. Their share goes
  to the other items of the same rarity (MAX ETHER and HYPER POTION; FULL RESTORE, MAX POTION and MAX
  ELIXER).

### Items that change battles (RUN)

| Item | Effect |
|---|---|
| KO Defiance | When your **last** Pokémon faints, it returns at half HP with status and stat stages cleared. Limited charges. Not in the first rival fight. Revived from sleep, it does not act that turn |
| Turn Rewind | Restores only *your* active Pokémon's HP, PP, status and stages from the start of last turn. The enemy keeps its state. Not after switching |
| Element Boy | +10 / 15 / 20% damage for one chosen type |
| Stat Booster | 2x to 4x stat experience by tier |
| DV Booster | Pokémon you receive have every DV at least 6 / 10 / 13 by tier |
| M.Gene (a gift, used up) | Rerolls one Pokémon's DVs, each at least 13 |
| Leftovers, PP Tonic | HP / PP recovery after a battle you win |

## Run effects

### Gifts (whole party unless marked "one Pokémon")

| Gift | Effect |
|---|---|
| Crit Mastery | Crits deal +20% |
| Crit Training (one Pokémon) | +25 points of crit chance |
| Cute Boost | Moves below 60 power deal +50% |
| STAB Mastery | STAB moves deal a further +10% |
| Type Expert | Super-effective moves deal +20% (both types counted) |
| Repeat! | Using the same move again with the same Pokémon deals +15% |
| Target Practice | +26/256 hit chance (about 10 points) |
| Wild Strength / Defense Training / Coffee Boost | x1.125 Attack / Defense / Speed |
| Spiked Drink | Your secondary status chances are x1.2 |
| Deadly Venom | Your poison moves badly poison |
| Dulled Senses | No move recoil. Struggle, crashes and Life Orb still hurt |
| Nurturing Care / Big Root | +10% healing / +30% draining (they multiply) |
| Shadow Step | Everyone enters at +1 evasion |
| Staggering Blows (one Pokémon) | +20 points of flinch chance on flinching moves |
| Life Orb (one Pokémon) | +30% damage, costs 1/10 max HP per damaging hit |
| Body Armor (one Pokémon) | x1.5 Defense, cannot use 0-power moves (Struggles if it has no others) |
| Growth Ray (one Pokémon) | x1.125 max HP and Attack, x0.875 Speed |
| Shrink Ray (one Pokémon) | x1.125 Speed, x0.875 Attack, enters at +1 evasion |
| Poison Ward / Immunity (one Pokémon) | Cannot be poisoned / cannot get any major status, which also blocks its own Rest |

Fixed-damage moves, one-hit KOs and Counter are not boosted.

### Special forms (either side can have them)

| Pokémon | Trait |
|---|---|
| Cubone, Marowak (Thick Club) | 2x Attack for physical damage |
| Pikachu (Light Ball) | 2x on physical and special, cannot evolve |
| Machop line (No Guard) | Its moves and moves against it never miss, even through Fly/Dig. Mist, Substitute and Dream Eater's rules still apply |
| Farfetch'd | Always crits |
| Nidoran F line | 25% chance to move first (player only), after Quick Attack and Counter rules |
| Growlithe, Arcanine | Lowers enemy Attack one stage on entry (player only). Substitute and Mist block it |
| Hitmonlee (Limber) | Cannot be paralyzed |
| Hitmonchan (Mystic) | Attack and Special swapped |
| Butterfree (pink) | About 1.3x accuracy |

Doubled stats are capped at 1023.

### Witch prizes (permanent for the run)

+10% EXP · crit threshold x1.25 · +26/256 hit chance · x1.125 Special · super-effective damage you take
x0.75 · your 2 to 5 hit moves always hit 4 or 5 times · +10% prize money · rarity and shop bonuses.

### Witch and Dorm PC challenges that affect battle

| Challenge | Effect on you |
|---|---|
| Slowed | Speed halved |
| Double PP | Your moves cost 2 PP |
| Same-move penalty | Lose 1/8 max HP for repeating a move |
| Recoil (all / physical / special) | Lose 1/4 of the damage you deal |
| Turn limit | After 6 + round turns, lose 1/16 max HP every turn |
| No healing | No medicine outside battle |
| Higher levels / rarer foes | Enemy levels about +10% / one rarity class higher |

## Still vanilla: do not get caught

- **Frozen Pokémon never thaw on their own.** Damaging Fire moves other than Fire Spin, items and Haze only.
- **Sleep lasts 1 to 7 turns, and the turn you wake up is lost.**
- **Trapping moves stop the target from acting.**
- **Hyper Beam has no recharge** if it knocks out the target, breaks a Substitute or misses.
- **Toxic and Leech Seed share a counter,** so together they ramp each other.
- **One-hit KOs fail against a faster target.** Level does not matter.
- **Seismic Toss, Night Shade, Sonic Boom, Dragon Rage, Psywave and Super Fang ignore immunities.**
- **Counter ignores the type chart** and only answers Normal, Fighting and typeless moves.
- **One Special stat.** Screens last until you switch. Crits ignore stages and screens.
- **Jump Kick and Hi Jump Kick lose only 1 HP when they miss.**
- **Rage does not stop** until the user faints.
- **A multi-hit move rolls damage and crit once,** and every hit deals the same.
- **With EXP Share off, a trainer's switch resets who gets EXP:** only Pokémon that were out since the
  current enemy came in.
- **Do not reorder moves with SELECT while transformed:** it reorders your real moves too.
- **Poison still hurts outside battle,** 1 HP every four steps.

## Known issues

None at the moment.

---

## Where these changes come from

| Source | Battle changes |
|---|---|
| [Shin Pokémon Red](https://github.com/jojobear13/shinpokered) (jojobear13) | Most of the **FIX** rows: accuracy, Substitute, Haze, Rest, Disable, Transform, healing moves, trapping moves, Counter, Bide, the stat cap, crits above level 127, badge and burn/paralysis stat handling, typeless Struggle, dual-type effectiveness, frozen Pokémon picking a move |
| Xillicis | Removing the enemy's 25% stat-move miss |
| [Yellow Legacy](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy) (cRz-Shadows) and [pureRGB](https://github.com/Vortyne/pureRGB) (Vortyne) | Learning every move when several levels are gained at once |
| [Extreme Yellow](https://github.com/RainbowMetalPigeon/ExtremeYellow) (RainbowMetalPigeon) | Mid-battle evolution, the idea of difficulty modes |
| pureRGB, [pokecrystal](https://github.com/pret/pokecrystal), [Pokémon Yume](https://github.com/PokefanMarcel/yumepokered) (PokefanMarcel) | Parts of the trainer AI |
| Smogon | The Sleep Clause rule |
| Red Rogue | The rest: trainer AI, enemy turn planning, enemy stats, forms, gifts, items and challenges |

### Not taken from Shin Pokémon Red

- Acting on the turn you wake up, and 3-turn Rest
- Rage ending after 2 to 3 turns
- Hyper Beam recharging after a knockout
- Fixed-damage moves respecting immunities
- Leech Seed and Toxic no longer ramping each other
- Full Jump Kick crash damage
- The reworked crit formula, and separate damage rolls for each hit of a multi-hit move
- Psywave rerolls
- Locked move order while transformed
- Absorb and Mega Drain missing a Substitute (here they damage it without healing)

---

## Change log

Newest first. Maintainers: every battle change adds a row here and updates its section above. Use `-` for
the commit until there is one.

| Date | Commit | Change |
|---|---|---|
| 2026-11-26 | - | **Ironman: no REVIVE or MAX REVIVE.** With Ironman on, item balls, rewards and the healing clerk no longer offer them. The other healing items in their tiers become a little more common |
| 2026-11-25 | afb4e92b | **Shiny Pokémon:** wild ones can now appear shiny, at the same odds as ones you receive, and stay shiny if caught or if they join you. A reward's INFO screen shows whether it is shiny, and Pokémon sent to the PC box can be shiny too. With a full party, Bill's DUPLICATE and the PokéManiac's prize now put the exact Pokémon in the box, where most of it used to be rolled again |
| 2026-11-25 | [`2d0797d9`](https://github.com/JSsixtyfour/redrogue/commit/2d0797d9) | **Flora's Spore gift** now gives the Pokémon it names. Where it could be Vileplume or Bellossom, the list, the description and the Pokémon you received were each picked separately |
| 2026-11-25 | [`f88ae9b8`](https://github.com/JSsixtyfour/redrogue/commit/f88ae9b8) | **Wild Metronome and Mirror Move** no longer change unrelated memory. After a Pokémon was sent to the PC box, it could crash the game at the end of a battle. Thawing a wild Pokémon with a Fire move had the same fault |
| 2026-11-24 | [`9ba706d6`](https://github.com/JSsixtyfour/redrogue/commit/9ba706d6) | **Trapping moves:** yours now check their own type against the target. They no longer hold a target they cannot damage (Wrap on a Ghost), and no longer fail because of the target's own move |
| 2026-11-24 | [`9ba706d6`](https://github.com/JSsixtyfour/redrogue/commit/9ba706d6) | **A trainer's burned or paralyzed Pokémon** keeps its Attack or Speed drop when sent back in. Rest on one no longer leaves it at 2x Attack or 4x Speed |
| 2026-11-24 | [`9ba706d6`](https://github.com/JSsixtyfour/redrogue/commit/9ba706d6) | **Transform:** the enemy AI knows a transformed Pokémon's copied moves, and using one no longer reveals one of its real moves |
| 2026-11-24 | [`464fa595`](https://github.com/JSsixtyfour/redrogue/commit/464fa595) | **KO Defiance** on a sleeping Pokémon no longer lets it use a move it never chose (a fainted teammate's, or a crash on turn 1) |
| 2026-11-24 | [`06ef9bbc`](https://github.com/JSsixtyfour/redrogue/commit/06ef9bbc) | **Bide:** with 5 or 6 Pokémon, opening the party menu while an enemy stored energy made Bide unleash about 41,000 damage (present since 2026-05-11). Fixed |
| 2026-11-24 | [`06ef9bbc`](https://github.com/JSsixtyfour/redrogue/commit/06ef9bbc) | **Bide** counts each hit as it lands. **Counter** no longer reaches back to an earlier round, a switch-in, a confusion self-hit, a Jump Kick crash, or a Wrap you switched out of |
| 2026-11-20 | [`e4e644c6`](https://github.com/JSsixtyfour/redrogue/commit/e4e644c6) | Sleep Clause warning in the move menu |
| 2026-11-05 | [`e24a9056`](https://github.com/JSsixtyfour/redrogue/commit/e24a9056) | Frozen Pokémon pick a move, fixes a crash |
| 2026-10-22 | [`fc49fb9a`](https://github.com/JSsixtyfour/redrogue/commit/fc49fb9a) | Enemy decides before your menu, switches go before moves |
| 2026-10-20 | [`185d71e9`](https://github.com/JSsixtyfour/redrogue/commit/185d71e9), [`8e4c90dd`](https://github.com/JSsixtyfour/redrogue/commit/8e4c90dd) | Enemies spend PP. Transform fails on a transformed Pokémon |
| 2026-10-19 | [`7bd2ea4b`](https://github.com/JSsixtyfour/redrogue/commit/7bd2ea4b) | Substitute: self-damage, exact damage, drain healing, No Guard rules |
| 2026-10-16 | [`7d6f8ed6`](https://github.com/JSsixtyfour/redrogue/commit/7d6f8ed6) | Struggle, Rest, Rage/Thrash accuracy, Disable, Haze, Explosion and recoil through Substitute |
| 2026-10-15 | [`fdd77b7c`](https://github.com/JSsixtyfour/redrogue/commit/fdd77b7c) | Sleep Clause |
| 2026-10-09 | [`3f1d22e3`](https://github.com/JSsixtyfour/redrogue/commit/3f1d22e3) | Trainers no longer use items |
| 2026-09-28 | [`1e94adf8`](https://github.com/JSsixtyfour/redrogue/commit/1e94adf8), [`3ab01ff1`](https://github.com/JSsixtyfour/redrogue/commit/3ab01ff1) | Ghost beats Psychic. Dual-type effectiveness combined |
| 2026-09-27 | [`b63f0277`](https://github.com/JSsixtyfour/redrogue/commit/b63f0277) | Multi-hit moves continue through a broken Substitute |
| 2026-09-02 | [`f8d93201`](https://github.com/JSsixtyfour/redrogue/commit/f8d93201) | Badge boosts replaced by earned boosts |
| 2026-09-01 | [`cd105f64`](https://github.com/JSsixtyfour/redrogue/commit/cd105f64) | Stat-lowering moves no longer stack burn/paralysis penalties |
| 2026-08-25 | [`52ce8b22`](https://github.com/JSsixtyfour/redrogue/commit/52ce8b22) | Substitute blocks Thunder Wave |
| 2026-08-20 | [`8f5fb4dd`](https://github.com/JSsixtyfour/redrogue/commit/8f5fb4dd) | Focus Energy, badge boost stacking, enemy 25% stat-move miss removed |
| 2026-08-18 | [`b5b98483`](https://github.com/JSsixtyfour/redrogue/commit/b5b98483), [`12ac6627`](https://github.com/JSsixtyfour/redrogue/commit/12ac6627), [`230e5a24`](https://github.com/JSsixtyfour/redrogue/commit/230e5a24) | Accuracy, Struggle typeless, healing moves, Substitute vs sleep/Leech Seed/confusion, 999 cap, trapping immunity, and other Shin Pokémon Red fixes |
