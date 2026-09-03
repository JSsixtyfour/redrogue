; Species groups and rarity tiers for the Red Rogue reward pool.
;
; The reward pool used to be one flat 151-byte table (engine/pokemon/rarity.asm)
; whose tier boundaries lived in hand-summed EQU arithmetic, duplicated verbatim
; in scripts/IndigoPlateauLobby.asm. It is now a GROUP x TIER structure so that
; unlockable species groups (Johto, Kanto Time Warp) can be folded into every
; roll at runtime, alone or together, without touching any consumer.
;
; Adding a group: add a SPECIES_GROUP_* id and a BIT_GROUP_* bit, bump
; NUM_SPECIES_GROUPS, and add one `dw` row to RarityGroupTable plus its
; NUM_RARITY_TIERS tier rows. Nothing else needs to change.

; Group ids - index into RarityGroupTable (engine/pokemon/rarity.asm).
DEF SPECIES_GROUP_KANTO EQU 0
DEF SPECIES_GROUP_JOHTO EQU 1
DEF SPECIES_GROUP_WARP  EQU 2
DEF NUM_SPECIES_GROUPS  EQU 3

; Group enable bits. Used both in sRogueSpeciesGroupsEnabled (SRAM, the
; player's toggles) and in the runtime mask RogueGetActiveGroupMask returns.
; Bit position MUST equal the SPECIES_GROUP_* id above - RogueGetActiveGroupMask
; and RogueRollGroupForTier both convert between the two by shifting.
DEF BIT_GROUP_KANTO EQU SPECIES_GROUP_KANTO
DEF BIT_GROUP_JOHTO EQU SPECIES_GROUP_JOHTO
DEF BIT_GROUP_WARP  EQU SPECIES_GROUP_WARP

; Rarity tiers, in ascending order of value. Tier ids are an index into a
; group's tier table, so they are NOT the same as the 1-based class numbers the
; old `c` argument to Random_Pokemon_Selection uses (class 1 = pokeball = tier
; 0). RogueClassToTier does that conversion in one place.
DEF RARITY_TIER_POKEBALL   EQU 0
DEF RARITY_TIER_GREATBALL  EQU 1
DEF RARITY_TIER_ULTRABALL  EQU 2
DEF RARITY_TIER_MASTERBALL EQU 3
DEF RARITY_TIER_UBER       EQU 4
DEF NUM_RARITY_TIERS       EQU 5

; One tier entry: base count, total count, list pointer.
;   base count  = rollable base forms (the prefix of the list)
;   total count = base forms + evolved forms (the whole list)
; Only the base-form prefix is ever rolled directly; evolved forms are reached
; through EvolveMonByLevel, and exist in the list so a species can still be
; classified back to its tier. An empty tier is base=0, total=0, ptr=0.
DEF RARITY_TIER_ENTRY_SIZE EQU 4

; Rarity classes a caller may request explicitly via the `c` argument to
; Random_Pokemon_Selection: 1 = pokeball .. 4 = masterball. Uber is deliberately
; not requestable. Anything outside 1..NUM_SELECTABLE_CLASSES means "roll the
; class from the odds ladder" - see the range guard in Random_Pokemon_Selection,
; which exists because every farcall caller passes this argument in a register
; Bankswitch destroys, so `c` arrives as garbage at those sites.
DEF NUM_SELECTABLE_CLASSES EQU 4
