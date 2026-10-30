; Pokédex flavour text, part 2 - every species added by Species Groups Phase 2.
;
; At 101 new species the combined dex text reaches ~22,000 bytes, which exceeds a
; single 16 KiB bank, so it HAS to be split. Splitting is safe here and nowhere
; else in the species data: dex entries reach their text through `text_far`,
; which is bank-aware, whereas the pointer tables elsewhere (EvosMovesPointerTable,
; PokedexEntryPointers) are bare 16-bit `dw` and must stay in one bank with the
; data they address.
;
; Everything in this file lives in SECTION "Pokédex Text 2" (see text.asm).
; Append new species here, not to dex_text.asm.

_ChikoritaDexEntry::
	text "It loves to bask"
	next "in the sunlight."
	next "It uses the leaf"

	page "on its head to"
	next "seek out warm"
	next "places"
	dex

_BayleefDexEntry::
	text "The scent that"
	next "wafts from the"
	next "leaves on its neck"

	page "causes anyone who"
	next "smells it to"
	next "become energetic"
	dex

_MeganiumDexEntry::
	text "Anyone who stands"
	next "beside it becomes"
	next "refreshed, just as"

	page "if they were"
	next "relaxing in a"
	next "sunny forest"
	dex

_WeavileDexEntry::
	text "They live in cold"
	next "regions, forming"
	next "groups of four or"

	page "five that hunt"
	next "prey with superb"
	next "coordination"
	dex

_MamoswineDexEntry::
	text "Its impressive"
	next "tusks are made of"
	next "ice. Its numbers"

	page "thinned when it"
	next "turned warm after"
	next "the ice age"
	dex

_MismagiusDexEntry::
	text "Its cries sound"
	next "like incantations."
	next "Those hearing it"

	page "are tormented by"
	next "headaches and"
	next "hallucinations"
	dex

_CyndaquilDexEntry::
	text "The fire that"
	next "spouts from its"
	next "back burns hottest"

	page "when it is angry."
	next "The flaring flames"
	next "intimidate foes"
	dex

_QuilavaDexEntry::
	text "Before battle, it"
	next "turns its back on"
	next "its opponent to"

	page "demonstrate how"
	next "ferociously its"
	next "fire blazes"
	dex

_TyphlosionDexEntry::
	text "When heat from its"
	next "body causes the"
	next "air around it to"

	page "shimmer, this is a"
	next "sign that it is"
	next "ready to battle"
	dex

_TotodileDexEntry::
	text "This rough critter"
	next "chomps at any"
	next "moving object it"

	page "sees. Turning your"
	next "back on it is not"
	next "recommended"
	dex

_CroconawDexEntry::
	text "The tips of its"
	next "fangs are slanted"
	next "backward. Once"

	page "those fangs clamp"
	next "down, the prey has"
	next "no hope of escape"
	dex

_FeraligatrDexEntry::
	text "Although it has a"
	next "massive body, its"
	next "powerful hind legs"

	page "enable it to move"
	next "quickly, even on"
	next "the ground"
	dex

_SentretDexEntry::
	text "When acting as a"
	next "lookout, it warns"
	next "others of danger"

	page "by screeching and"
	next "hitting the ground"
	next "with its tail"
	dex

_FurretDexEntry::
	text "It lives in narrow"
	next "burrows that fit"
	next "its slim body. The"

	page "deeper the nests"
	next "go, the more maze-"
	next "like they become"
	dex

_HoothootDexEntry::
	text "It begins to hoot"
	next "at the same time"
	next "every day. Some"

	page "trainers use them"
	next "in place of"
	next "clocks"
	dex

_NoctowlDexEntry::
	text "Its extremely soft"
	next "feathers make no"
	next "sound in flight."

	page "It silently sneaks"
	next "up on prey without"
	next "being detected"
	dex

_LedybaDexEntry::
	text "It is timid and"
	next "clusters together"
	next "with others. The"

	page "fluid secreted by"
	next "its feet indicates"
	next "its location"
	dex

_LedianDexEntry::
	text "In the daytime"
	next "when it gets warm,"
	next "it curls up inside"

	page "a big leaf and"
	next "drifts off into"
	next "a deep slumber"
	dex

_SpinarakDexEntry::
	text "If prey becomes"
	next "ensnared in its"
	next "nest of spun"

	page "string, it waits"
	next "motionlessly until"
	next "it becomes dark"
	dex

_AriadosDexEntry::
	text "Rather than mak-"
	next "ing a nest in one"
	next "specific spot, it"

	page "wanders in search"
	next "of food after"
	next "darkness falls"
	dex

_CrobatDexEntry::
	text "As a result of its"
	next "pursuit of faster,"
	next "yet more silent"

	page "flight, a new set"
	next "of wings grew on"
	next "its hind legs"
	dex

_ChinchouDexEntry::
	text "Its antennae, whi-"
	next "ch evolved from a"
	next "fin, have both po-"

	page "sitive and neg-"
	next "ative charges flo-"
	next "wing through them"
	dex

_LanturnDexEntry::
	text "This #MON uses"
	next "the bright part of"
	next "its body, which"

	page "changed from a"
	next "dorsal fin, to"
	next "lure prey"
	dex

_TogepiDexEntry::
	text "It is considered"
	next "to be a symbol of"
	next "good luck. Its"

	page "shell is said to"
	next "be filled with"
	next "happiness"
	dex

_TogeticDexEntry::
	text "Although it does"
	next "not flap its wings"
	next "very much, it can"

	page "stay up in the air"
	next "as it tags along"
	next "after its trainer"
	dex

_NatuDexEntry::
	text "It is extremely"
	next "good at climbing"
	next "tree trunks and"

	page "likes to eat the"
	next "new sprouts on"
	next "the trees"
	dex

_XatuDexEntry::
	text "Once it begins to"
	next "meditate at sun-"
	next "rise, the entire"

	page "day will pass"
	next "before it will"
	next "move again"
	dex

_MareepDexEntry::
	text "It stores lots of"
	next "air in its soft"
	next "fur, allowing it"

	page "to stay cool in"
	next "summer and warm"
	next "in winter"
	dex

_FlaaffyDexEntry::
	text "Because of its"
	next "rubbery, electric-"
	next "ity-resistant"

	page "skin, it can store"
	next "lots of electric-"
	next "ity in its fur"
	dex

_AmpharosDexEntry::
	text "When it gets dark,"
	next "the light from its"
	next "bright, shiny tail"

	page "can be seen from"
	next "far away on the"
	next "ocean's surface"
	dex

_BellossomDexEntry::
	text "When these dance"
	next "together, their"
	next "petals rub against"

	page "each other,"
	next "making pretty,"
	next "relaxing sounds"
	dex

_MarillDexEntry::
	text "The fur on its"
	next "body naturally"
	next "repels water. It"

	page "can stay dry, even"
	next "when it plays in"
	next "the water"
	dex

_AzumarillDexEntry::
	text "The bubble-like"
	next "pattern on its"
	next "stomach helps it"

	page "camouflage itself"
	next "when it's in the"
	next "water"
	dex

_SudowoodoDexEntry::
	text "If a tree branch"
	next "shakes when there"
	next "is no wind, it's a"

	page "SUDOWOODO, not a"
	next "tree. It hides"
	next "from the rain"
	dex

_PolitoedDexEntry::
	text "When it expands"
	next "its throat to"
	next "croak out a tune,"

	page "nearby POLIWAG and"
	next "POLIWHIRL gather"
	next "immediately"
	dex

_HoppipDexEntry::
	text "It can be carried"
	next "away on even the"
	next "gentlest breeze."

	page "It may even float"
	next "all the way to the"
	next "next town"
	dex

_SkiploomDexEntry::
	text "As soon as it"
	next "rains, it closes"
	next "its flower and"

	page "hides in the shade"
	next "of a tree to avoid"
	next "getting wet"
	dex

_JumpluffDexEntry::
	text "Even in the fierc-"
	next "est wind, it can"
	next "control its fluff"

	page "to make its way to"
	next "any place in the"
	next "world it wants"
	dex

_AipomDexEntry::
	text "It uses its tail"
	next "to hang on to tree"
	next "branches. It uses"

	page "its momentum to"
	next "swing from one"
	next "branch to another"
	dex

_SunkernDexEntry::
	text "It is very weak."
	next "Its only means of"
	next "defense is to"

	page "shake its leaves"
	next "desperately at its"
	next "attacker"
	dex

_SunfloraDexEntry::
	text "As the hot season"
	next "approaches, the"
	next "petals on this"

	page "#MON's face"
	next "become more vivid"
	next "and lively"
	dex

_YanmaDexEntry::
	text "It can see in all"
	next "directions without"
	next "moving its big"

	page "eyes, helping it"
	next "spot attackers and"
	next "food right away"
	dex

_WooperDexEntry::
	text "A mucous"
	next "membrane covers"
	next "its body. Touching"

	page "it barehanded will"
	next "cause a shooting"
	next "pain"
	dex

_QuagsireDexEntry::
	text "Its body is always"
	next "slimy. It often"
	next "bangs its head on"

	page "the river bottom"
	next "as it swims but"
	next "seems not to care"
	dex

_MurkrowDexEntry::
	text "It hides any shiny"
	next "object it finds in"
	next "a secret location."

	page "MURKROW and"
	next "MEOWTH loot one"
	next "another's stashes"
	dex

_SlowkingDexEntry::
	text "Every time it ya-"
	next "wns, SHELLDER"
	next "injects more poi-"

	page "son into it. The"
	next "poison makes it"
	next "more intelligent"
	dex

_MisdreavusDexEntry::
	text "It loves to watch"
	next "people it's scar-"
	next "ed. It frightens"

	page "them by screaming"
	next "loudly or appear-"
	next "ing suddenly"
	dex

_GirafarigDexEntry::
	text "When it is in"
	next "danger, its tail"
	next "uses some sort of"

	page "mysterious powers"
	next "to drive away the"
	next "enemy"
	dex

_PinecoDexEntry::
	text "It spits out a"
	next "fluid that it uses"
	next "to glue tree bark"

	page "to its body. The"
	next "fluid hardens when"
	next "it touches air"
	dex

_ForretressDexEntry::
	text "Usually found"
	next "hanging on to a"
	next "fat tree trunk. It"

	page "shoots out bits of"
	next "its shell when it"
	next "sees action"
	dex

_DunsparceDexEntry::
	text "It hides deep"
	next "inside caves where"
	next "no light ever"

	page "reaches it and"
	next "remains virtually"
	next "motionless there"
	dex

_GligarDexEntry::
	text "It builds its nest"
	next "on a steep cliff."
	next "When it is done"

	page "gliding, it hops"
	next "along the ground"
	next "back to its nest"
	dex

_SteelixDexEntry::
	text "The many small"
	next "metal particles"
	next "that cover this"

	page "#MON's body"
	next "reflect bright"
	next "light well"
	dex

_SnubbullDexEntry::
	text "In truth, it is a"
	next "cowardly #MON."
	next "It growls eagerly"

	page "in order to hide"
	next "its fear from its"
	next "opponent"
	dex

_GranbullDexEntry::
	text "It can make most"
	next "any #MON run"
	next "away simply by"

	page "opening its mouth"
	next "wide to reveal its"
	next "big fangs"
	dex

_QwilfishDexEntry::
	text "When faced with a"
	next "larger opponent,"
	next "it swallows as"

	page "much water as it"
	next "can to match the"
	next "opponent's size"
	dex

_ScizorDexEntry::
	text "This #MON's"
	next "pincers, which"
	next "contain steel, can"

	page "crush any hard"
	next "object it gets a"
	next "hold of into bits"
	dex

_ShuckleDexEntry::
	text "The fluid secreted"
	next "by its toes carves"
	next "holes in rocks for"

	page "nesting and can be"
	next "mixed with BERRIES"
	next "to make a drink"
	dex

_HeracrossDexEntry::
	text "With its Herculean"
	next "powers, it can"
	next "easily throw arou-"

	page "nd an object that"
	next "is 100 times its"
	next "own weight"
	dex

_SneaselDexEntry::
	text "This cunning"
	next "#MON hides"
	next "under the cover"

	page "of darkness,"
	next "waiting to attack"
	next "its prey"
	dex

_TeddiursaDexEntry::
	text "It always licks"
	next "honey. Its palm"
	next "tastes sweet"

	page "because of all the"
	next "honey it has"
	next "absorbed"
	dex

_UrsaringDexEntry::
	text "Although it has a"
	next "large body, it is"
	next "quite skilled at"

	page "climbing trees. It"
	next "eats and sleeps in"
	next "the treetops"
	dex

_SlugmaDexEntry::
	text "These group to-"
	next "gether in areas"
	next "that are hotter"

	page "than normal. If it"
	next "cools off, its"
	next "skin hardens"
	dex

_MagcargoDexEntry::
	text "Its body is as hot"
	next "as lava and is"
	next "always billowing."

	page "Flames will"
	next "occasionally burst"
	next "from its shell"
	dex

_SwinubDexEntry::
	text "It uses the tip of"
	next "its nose to dig"
	next "for food. Its nose"

	page "is so tough that"
	next "even frozen ground"
	next "poses no problem"
	dex

_PiloswineDexEntry::
	text "Although its legs"
	next "are short, its"
	next "rugged hooves"

	page "prevent it from"
	next "slipping, even on"
	next "icy ground"
	dex

_CorsolaDexEntry::
	text "The points on its"
	next "head absorb"
	next "nutrients from"

	page "clean water. They"
	next "cannot survive in"
	next "polluted water"
	dex

_RemoraidDexEntry::
	text "To escape from an"
	next "attacker, it may"
	next "shoot water out of"

	page "its mouth, then"
	next "use that force to"
	next "swim backward"
	dex

_OctilleryDexEntry::
	text "Its instinct is to"
	next "bury itself in"
	next "holes. It often"

	page "steals the nesting"
	next "holes of others to"
	next "sleep in them"
	dex

_MantineDexEntry::
	text "It swims along"
	next "freely, eating"
	next "things that swim"

	page "into its mouth."
	next "Its whole body is"
	next "very coarse"
	dex

_SkarmoryDexEntry::
	text "The feathers that"
	next "it sheds are very"
	next "sharp. It is said"

	page "that people once"
	next "used the feathers"
	next "as swords"
	dex

_HoundourDexEntry::
	text "Around dawn, its"
	next "ominous howl"
	next "echoes through the"

	page "area to announce"
	next "that this is its"
	next "territory"
	dex

_HoundoomDexEntry::
	text "The pungent-"
	next "smelling flame"
	next "that shoots from"

	page "its mouth results"
	next "from toxins burn-"
	next "ing in its body"
	dex

_KingdraDexEntry::
	text "It stores energy"
	next "by sleeping at"
	next "underwater depths"

	page "at which no other"
	next "life forms can"
	next "survive"
	dex

_PhanpyDexEntry::
	text "During the desert-"
	next "ed morning hours,"
	next "it comes ashore"

	page "where it deftly"
	next "uses its trunk to"
	next "take a shower"
	dex

_DonphanDexEntry::
	text "Because this"
	next "#MON's skin is"
	next "so tough, a normal"

	page "attack won't even"
	next "leave a scratch on"
	next "it"
	dex

_Porygon2DexEntry::
	text "This manmade"
	next "#MON evolved"
	next "from the latest"

	page "technology. It"
	next "may have unprog-"
	next "rammed reactions"
	dex

_StantlerDexEntry::
	text "The round balls"
	next "found on the"
	next "fallen antlers can"

	page "be ground into a"
	next "powder that aids"
	next "in sleeping"
	dex

_HitmontopDexEntry::
	text "After doing a"
	next "handstand to"
	next "throw off the"

	page "opponent's timing,"
	next "it presents its"
	next "fancy kick moves"
	dex

_MiltankDexEntry::
	text "In order to milk a"
	next "MILTANK, one must"
	next "have a knack for"

	page "rhythmically pull-"
	next "ing up and down"
	next "on its udders"
	dex

_BlisseyDexEntry::
	text "Biting into one"
	next "of the delicious"
	next "eggs that BLISSEY"

	page "provides will make"
	next "everyone around"
	next "smile with joy"
	dex

_RaikouDexEntry::
	text "This rough #MON"
	next "stores energy"
	next "inside its body,"

	page "then sweeps across"
	next "the land, shooting"
	next "off electricity"
	dex

_EnteiDexEntry::
	text "This brawny"
	next "#MON courses"
	next "around the earth,"

	page "spouting flames"
	next "hotter than a"
	next "volcano's magma"
	dex

_SuicuneDexEntry::
	text "This divine"
	next "#MON blows"
	next "around the world,"

	page "always in search"
	next "of a pure"
	next "reservoir"
	dex

_LarvitarDexEntry::
	text "Born deep under-"
	next "ground, this"
	next "#MON becomes a"

	page "pupa after eating"
	next "enough dirt to"
	next "make a mountain"
	dex

_PupitarDexEntry::
	text "It will not stay"
	next "still, even while"
	next "it's a pupa. It"

	page "already has arms"
	next "and legs under its"
	next "solid shell"
	dex

_TyranitarDexEntry::
	text "In just one of its"
	next "mighty hands, it"
	next "has the power to"

	page "make the ground"
	next "shake and moun-"
	next "tains crumble"
	dex

_LugiaDexEntry::
	text "It has an incred-"
	next "ible ability to"
	next "calm raging sto-"

	page "rms. It is said"
	next "that LUGIA appears"
	next "when storms start"
	dex

_HoOhDexEntry::
	text "It will reveal"
	next "itself before a"
	next "pure-hearted"

	page "trainer by shining"
	next "its bright rain-"
	next "bow-colored wings"
	dex

_CelebiDexEntry::
	text "Revered as a"
	next "guardian of the"
	next "forest, CELEBI"

	page "appears wherever"
	next "beautiful forests"
	next "exist"
	dex

_AnnihilapeDexEntry::
	text "When its anger"
	next "rose beyond a"
	next "critical point, it"

	page "gained power that"
	next "is unfettered by"
	next "its body's limits"
	dex

_LickilickyDexEntry::
	text "It wraps things"
	next "with its"
	next "extensible tongue."

	page "Getting too close"
	next "to it leaves you"
	next "soaked with drool"
	dex

_SirfetchdDexEntry::
	text "Only FARFETCH'D"
	next "that survive many"
	next "battles can evolve"

	page "When its leek"
	next "wilts, it retires"
	next "from combat"
	dex

_MagnezoneDexEntry::
	text "It evolved from"
	next "exposure to a"
	next "special magnetic"

	page "field. Three"
	next "units generate"
	next "magnetism"
	dex

_TangrowthDexEntry::
	text "It ensnares prey"
	next "by extending arms"
	next "made of vines."

	page "Losing arms to"
	next "predators does not"
	next "trouble it"
	dex

_RhyperiorDexEntry::
	text "It puts rocks in"
	next "holes in its palms"
	next "and uses its"

	page "muscles to shoot"
	next "them. Sometimes,"
	next "GEODUDE are shot"
	dex

_KleavorDexEntry::
	text "A violent creature"
	next "that fells trees"
	next "with crude stone"

	page "axes. If you meet"
	next "one, your only"
	next "option is to flee"
	dex

_MrRimeDexEntry::
	text "It's highly skilled"
	next "at tap-dancing. It"
	next "waves its cane of"

	page "ice in time with"
	next "its graceful"
	next "movements"
	dex

_ElectivireDexEntry::
	text "It pushes the tips"
	next "of its two tails"
	next "against the foe,"

	page "then lets loose"
	next "with over 20,000"
	next "volts of power"
	dex

_MagmortarDexEntry::
	text "It blasts"
	next "fireballs of over"
	next "3,600 degrees from"

	page "the ends of its"
	next "arms. It lives in"
	next "volcanic craters"
	dex

_PorygonZDexEntry::
	text "Additional"
	next "software was"
	next "installed to make"

	page "it better, but it"
	next "began acting"
	next "oddly"
	dex
