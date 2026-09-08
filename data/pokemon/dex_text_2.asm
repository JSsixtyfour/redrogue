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
	next "coat, the more"

	page "electricity it"
	next "can store"
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
