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
	text "A sweet aroma"
	next "gently wafts from"
	next "the leaf on its"

	page "head. It loves to"
	next "soak up the sun's"
	next "warm rays"
	dex

_BayleefDexEntry::
	text "The scent that"
	next "wafts from the"
	next "leaves round its"

	page "neck has a spicy,"
	next "stimulating"
	next "effect"
	dex

_MeganiumDexEntry::
	text "The aroma that"
	next "rises from its"
	next "petals soothes"

	page "the feelings of"
	next "people locked in"
	next "battle"
	dex

_WeavileDexEntry::
	text "It works with"
	next "others to corner"
	next "prey, then shreds"

	page "it with its sharp,"
	next "claw-like feathers"
	next "in an instant"
	dex

_MamoswineDexEntry::
	text "Thick fur and"
	next "a coat of fat"
	next "keep it warm in"

	page "any climate. It"
	next "roams in herds"
	next "across the snow"
	dex

_MismagiusDexEntry::
	text "Said to cast"
	next "spells that make"
	next "the afflicted"

	page "hear only"
	next "unpleasant,"
	next "eerie sounds"
	dex

_CyndaquilDexEntry::
	text "The flames that"
	next "burst from its"
	next "back are proof"

	page "of its rage. It"
	next "is timid, and"
	next "always curls up"
	dex

_QuilavaDexEntry::
	text "If it stands"
	next "on its hind legs,"
	next "it can spray"

	page "flames from its"
	next "back for even"
	next "greater power"
	dex

_TyphlosionDexEntry::
	text "It shrouds"
	next "itself in a"
	next "heat haze as it"

	page "storms toward"
	next "foes, leaving"
	next "nothing behind"
	dex

_TotodileDexEntry::
	text "Despite its"
	next "small body, its"
	next "jagged jaws are"

	page "very powerful."
	next "It won't let go"
	next "once it bites"
	dex

_CroconawDexEntry::
	text "Once it bites"
	next "down, it will"
	next "not let go until"

	page "its target loses"
	next "consciousness."
	next "It has sharp fangs"
	dex

_FeraligatrDexEntry::
	text "It swings its"
	next "great jaws wide"
	next "to intimidate"

	page "enemies. It attacks"
	next "with amazing"
	next "speed and power"
	dex

_SentretDexEntry::
	text "Stands on its"
	next "tail and looks"
	next "all around itself"

	page "constantly. If it"
	next "senses danger, it"
	next "flees at once"
	dex

_FurretDexEntry::
	text "It is very"
	next "slender so it"
	next "can slip through"

	page "narrow spaces"
	next "without difficulty,"
	next "even underground"
	dex

_HoothootDexEntry::
	text "It always"
	next "stands on one leg,"
	next "even while it"

	page "sleeps. It starts"
	next "tilting its head"
	next "at sundown"
	dex

_NoctowlDexEntry::
	text "It can rotate"
	next "its head 180"
	next "degrees. It flies"

	page "silently and is"
	next "a great hunter"
	next "in the dark"
	dex

_LedybaDexEntry::
	text "It is timid."
	next "In the cold, it"
	next "huddles together"

	page "with others of"
	next "its kind to keep"
	next "from freezing"
	dex

_LedianDexEntry::
	text "It flies through"
	next "the dark using"
	next "the spots on its"

	page "back as a beacon,"
	next "flapping about"
	next "as it does so"
	dex

_SpinarakDexEntry::
	text "It spins a"
	next "web that is"
	next "nearly invisible"

	page "in the dark of"
	next "night. Prey get"
	next "stuck fast in it"
	dex

_AriadosDexEntry::
	text "It marks its"
	next "web-building"
	next "territory with"

	page "thread that"
	next "carries its"
	next "unique scent"
	dex

_CrobatDexEntry::
	text "Once it targets"
	next "prey, it chases"
	next "it persistently"

	page "using its four"
	next "wings to fly at"
	next "high speed"
	dex

_ChinchouDexEntry::
	text "It flashes the"
	next "lights on its"
	next "head to check"

	page "its surroundings."
	next "It never loses"
	next "sight of prey"
	dex

_LanturnDexEntry::
	text "Its light"
	next "organ shines so"
	next "brightly, it can"

	page "illuminate the"
	next "sea's surface"
	next "even from deep"
	dex

_TogepiDexEntry::
	text "It is said to"
	next "share good luck"
	next "when it is kindly"

	page "treated. Its"
	next "shell is full of"
	next "joy for the future"
	dex

_TogeticDexEntry::
	text "It is said to"
	next "appear before"
	next "kindhearted,"

	page "caring people"
	next "and share happy"
	next "memories with them"
	dex

_NatuDexEntry::
	text "It stares at"
	next "the sun all day"
	next "long, standing"

	page "still on one leg."
	next "It is said to see"
	next "into the future"
	dex

_XatuDexEntry::
	text "It stands rooted"
	next "in one spot all"
	next "day, watching"

	page "the sky. It is"
	next "said to see the"
	next "past and future"
	dex

_MareepDexEntry::
	text "Its fluffy wool"
	next "rubs together"
	next "and generates"

	page "static electricity."
	next "The fluffier the"
	next "coat, the more it holds"
	dex

_FlaaffyDexEntry::
	text "Its wool has"
	next "started to thin"
	next "out. It stores"

	page "electricity in"
	next "its rubbery,"
	next "bare hide"
	dex

_AmpharosDexEntry::
	text "Its long tail"
	next "shines brightly."
	next "In the past,"

	page "people used the"
	next "light to send"
	next "signals to others"
	dex

_BellossomDexEntry::
	text "Basking in a"
	next "warm, nurturing"
	next "sun makes its"

	page "petals grow more"
	next "vivid. It dances"
	next "in a slow rhythm"
	dex

_MarillDexEntry::
	text "Its tail is"
	next "wrapped in a"
	next "waterproof film"

	page "and floats on the"
	next "surface as it"
	next "swims about"
	dex

_AzumarillDexEntry::
	text "It uses its"
	next "long, sensitive"
	next "ears to detect"

	page "the movements of"
	next "prey in even the"
	next "murkiest waters"
	dex

_SudowoodoDexEntry::
	text "It disguises"
	next "itself as a tree"
	next "to avoid being"

	page "attacked. It"
	next "hates water and"
	next "hides on rainy days"
	dex

_PolitoedDexEntry::
	text "The curl on its"
	next "forehead is a"
	next "sign of status"

	page "among its kind."
	next "The longer, the"
	next "more respected"
	dex

_HoppipDexEntry::
	text "If it senses"
	next "danger, it"
	next "immediately"

	page "links arms with"
	next "others nearby to"
	next "avoid being blown"
	dex

_SkiploomDexEntry::
	text "Its cottony"
	next "fluff bursts open"
	next "with the smallest"

	page "impact, letting"
	next "seeds ride on"
	next "the wind currents"
	dex

_JumpluffDexEntry::
	text "It floats on"
	next "seasonal winds"
	next "and spreads its"

	page "seeds as it flies"
	next "over city streets"
	next "and fields alike"
	dex

_AipomDexEntry::
	text "It uses its"
	next "tail as a fifth"
	next "hand, freeing up"

	page "its front paws"
	next "for grabbing food"
	next "off tall branches"
	dex

_SunkernDexEntry::
	text "It cannot move"
	next "on its own, so it"
	next "waits, motionless,"

	page "for the wind to"
	next "carry it to a"
	next "spot to sprout"
	dex

_SunfloraDexEntry::
	text "Its face"
	next "resembles the"
	next "sun. In sunny"

	page "weather, it can"
	next "be seen dancing"
	next "energetically"
	dex

_YanmaDexEntry::
	text "Its four wings"
	next "beat separately,"
	next "letting it hover"

	page "and change flight"
	next "direction in an"
	next "instant"
	dex

_WooperDexEntry::
	text "In water, it"
	next "hunts by wiggling"
	next "its tail. On land,"

	page "it coats its body"
	next "in a slimy film"
	next "to stay hydrated"
	dex

_QuagsireDexEntry::
	text "It relies on"
	next "smell to identify"
	next "things, since its"

	page "eyesight is quite"
	next "poor. It is often"
	next "seen just floating"
	dex

_MurkrowDexEntry::
	text "It is said that"
	next "if it spots a"
	next "shiny object, it"

	page "will bring it back"
	next "to its nest as a"
	next "collected treasure"
	dex

_SlowkingDexEntry::
	text "When a shellfish"
	next "bit onto its head"
	next "long ago, a bizarre"

	page "chemical reaction"
	next "occurred, endowing"
	next "it with wisdom"
	dex

_MisdreavusDexEntry::
	text "Its shrill,"
	next "shrieking cry"
	next "sends a shiver"

	page "down the spine"
	next "of anyone who"
	next "hears it"
	dex

_GirafarigDexEntry::
	text "Its tail has a"
	next "second brain and"
	next "will bite anyone"

	page "who approaches"
	next "from behind"
	next "carelessly"
	dex

_PinecoDexEntry::
	text "It hangs from"
	next "a branch,"
	next "motionless, so it"

	page "looks like a pine"
	next "cone. It drops"
	next "onto passersby"
	dex

_ForretressDexEntry::
	text "Its shell is"
	next "extremely hard,"
	next "and it will spray"

	page "a corrosive fluid"
	next "at anything that"
	next "tries to open it"
	dex

_DunsparceDexEntry::
	text "It normally"
	next "lives underground,"
	next "using its clawed"

	page "tail to dig long"
	next "tunnels through"
	next "the soft earth"
	dex

_GligarDexEntry::
	text "It flies with"
	next "silent, gliding"
	next "wings and clings"

	page "to the face of"
	next "its foes to"
	next "attack them"
	dex

_SteelixDexEntry::
	text "Its body is"
	next "made of a hard,"
	next "compressed"

	page "combination of"
	next "iron ore and"
	next "diamonds"
	dex

_SnubbullDexEntry::
	text "Even though"
	next "it has a scary"
	next "face, it is very"

	page "friendly. It is"
	next "popular for its"
	next "cute expressions"
	dex

_GranbullDexEntry::
	text "It has such"
	next "powerful jaws"
	next "that its own fangs"

	page "grow crooked. It"
	next "tires easily and"
	next "cannot chew long"
	dex

_QwilfishDexEntry::
	text "It swallows"
	next "water to swell"
	next "up. If threatened,"

	page "it shoots its"
	next "many poisonous"
	next "barbs at once"
	dex

_ScizorDexEntry::
	text "Its steel-hard"
	next "pincers can slice"
	next "clean through"

	page "thick logs. It"
	next "attacks by dive-"
	next "bombing from above"
	dex

_ShuckleDexEntry::
	text "It stuffs berries"
	next "into the gaps"
	next "in its shell and"

	page "waits for them"
	next "to slowly turn"
	next "into a sweet juice"
	dex

_HeracrossDexEntry::
	text "It uses its"
	next "single horn to"
	next "hurl anything"

	page "in its way, even"
	next "things far more"
	next "massive than itself"
	dex

_SneaselDexEntry::
	text "It has a"
	next "disagreeable,"
	next "combative"

	page "nature. It steals"
	next "eggs from other"
	next "Pokemon's nests"
	dex

_TeddiursaDexEntry::
	text "It always"
	next "licks its paws"
	next "which are soaked"

	page "with a honey-like"
	next "saliva, giving"
	next "off a sweet scent"
	dex

_UrsaringDexEntry::
	text "Its sharp"
	next "claws are perfect"
	next "for peeling"

	page "tree bark to seek"
	next "out insects to"
	next "eat underneath"
	dex

_SlugmaDexEntry::
	text "Molten flesh"
	next "oozes from all"
	next "over its body,"

	page "and drips away"
	next "as it slowly"
	next "crawls along"
	dex

_MagcargoDexEntry::
	text "Its shell"
	next "hardened after"
	next "its molten body"

	page "cooled. The shell"
	next "is very brittle"
	next "and cracks easily"
	dex

_SwinubDexEntry::
	text "It uses its"
	next "nose to root"
	next "around for food"

	page "buried underground."
	next "Its sense of"
	next "smell is superb"
	dex

_PiloswineDexEntry::
	text "Its long"
	next "shaggy fur"
	next "conceals a very"

	page "round body. It"
	next "cannot see well,"
	next "so it charges blind"
	dex

_CorsolaDexEntry::
	text "It lives in"
	next "warm seas. Its"
	next "coral body"

	page "grows larger"
	next "when the sea"
	next "water is warm"
	dex

_RemoraidDexEntry::
	text "It fires off"
	next "streams of water"
	next "at prey with the"

	page "accuracy of a"
	next "sharpshooter"
	next "using a rifle"
	dex

_OctilleryDexEntry::
	text "Once it has"
	next "cornered its"
	next "prey with its"

	page "tentacles, it"
	next "shoots a jet of"
	next "ink at point-blank"
	dex

_MantineDexEntry::
	text "It glides"
	next "gracefully through"
	next "open water as"

	page "if it were flying"
	next "through the sky."
	next "It never stops"
	dex

_SkarmoryDexEntry::
	text "Its body is"
	next "encased in hard"
	next "armor. It flies"

	page "at high speed to"
	next "protect its"
	next "flock from danger"
	dex

_HoundourDexEntry::
	text "It communicates"
	next "with others using"
	next "a variety of"

	page "cries, and works"
	next "in packs to"
	next "surround prey"
	dex

_HoundoomDexEntry::
	text "Its howl sends"
	next "a chill down the"
	next "spines of enemies"

	page "and prey alike."
	next "It hunts in"
	next "organized packs"
	dex

_KingdraDexEntry::
	text "It is said to"
	next "live in deep sea"
	next "caves. It swims"

	page "with powerful"
	next "twists of its"
	next "entire body"
	dex

_PhanpyDexEntry::
	text "It loves"
	next "water and is a"
	next "good swimmer."

	page "It swings its"
	next "long nose about"
	next "to protect itself"
	dex

_DonphanDexEntry::
	text "It curls up"
	next "and rolls into"
	next "its foes to"

	page "attack. Once it"
	next "starts rolling,"
	next "it can't stop"
	dex

_Porygon2DexEntry::
	text "An upgraded"
	next "version of"
	next "PORYGON. Its"

	page "movement is"
	next "smoother and more"
	next "sophisticated"
	dex

_StantlerDexEntry::
	text "Its magnificent"
	next "antlers were once"
	next "traded at high"

	page "prices as works"
	next "of art. Hunters"
	next "seek it for them"
	dex

_HitmontopDexEntry::
	text "It spins on"
	next "its head, then"
	next "delivers vicious"

	page "kicks while still"
	next "in a spinning"
	next "handstand"
	dex

_MiltankDexEntry::
	text "Milk from this"
	next "docile Pokemon"
	next "is packed with"

	page "nutrients. Baby"
	next "and old Pokemon"
	next "recover with it"
	dex

_BlisseyDexEntry::
	text "Its soft, plush"
	next "body always shares"
	next "an egg with anyone"

	page "who is troubled."
	next "It knows no"
	next "human words"
	dex

_RaikouDexEntry::
	text "Legends say it"
	next "embodies the"
	next "speed of"

	page "lightning. It runs"
	next "across the land"
	next "as it barks"
	dex

_EnteiDexEntry::
	text "It is said that"
	next "every time it"
	next "roars, a new"

	page "volcano erupts"
	next "somewhere in"
	next "the world"
	dex

_SuicuneDexEntry::
	text "It embodies"
	next "the compassion"
	next "of a pure spring"

	page "of water. It runs"
	next "across the land"
	next "with grace"
	dex

_LarvitarDexEntry::
	text "Born from an"
	next "egg buried in"
	next "the ground, it"

	page "grows by eating"
	next "soil for the"
	next "first ten years"
	dex

_PupitarDexEntry::
	text "Inside its"
	next "hard shell, its"
	next "body is molten"

	page "and constantly"
	next "changing shape"
	next "as it hardens"
	dex

_TyranitarDexEntry::
	text "It is said that"
	next "this Pokemon can"
	next "topple mountains"

	page "and level entire"
	next "valleys just by"
	next "rampaging about"
	dex

_LugiaDexEntry::
	text "It is said to"
	next "rest at the bottom"
	next "of the sea, and"

	page "a single wingbeat"
	next "can cause a"
	next "raging storm"
	dex

_HoOhDexEntry::
	text "Its feathers"
	next "glow in seven"
	next "colors depending"

	page "on the angle at"
	next "which they are"
	next "viewed"
	dex

_CelebiDexEntry::
	text "It is said to"
	next "have come from"
	next "the future by"

	page "crossing through"
	next "time to reach"
	next "this world"
	dex

_AnnihilapeDexEntry::
	text "Endless rage"
	next "has awakened a"
	next "vengeful spirit"

	page "within its body,"
	next "granting immense"
	next "destructive power"
	dex

_LickilickyDexEntry::
	text "Its saliva"
	next "carries a mild"
	next "poison. Anything"

	page "it licks with its"
	next "tongue will feel"
	next "numb for a while"
	dex

_SirfetchdDexEntry::
	text "The stalk it"
	next "wields as a"
	next "weapon has been"

	page "honed to a razor's"
	next "edge from years"
	next "of countless duels"
	dex

_MagnezoneDexEntry::
	text "It emits a"
	next "special magnetic"
	next "force from its"

	page "body that disrupts"
	next "compasses and"
	next "electronics"
	dex

_TangrowthDexEntry::
	text "Its vines move"
	next "on their own to"
	next "grab anything"

	page "that comes close,"
	next "then hold on"
	next "and never let go"
	dex

_RhyperiorDexEntry::
	text "Its rocky hide"
	next "is so tough that"
	next "even a direct"

	page "hit from molten"
	next "lava only feels"
	next "like a warm bath"
	dex
