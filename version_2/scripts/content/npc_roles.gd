class_name NpcRoles
extends RefCounted

## Village roles: what an NPC sells, what it says, and what it looks like.
##
## Dialogue is a small tree rather than a script: a root node with a handful of
## options, each of which either says something and returns, opens a shop, or
## hands out a quest. That is enough for a settlement to feel populated without
## a dialogue engine, and it keeps every line in one readable table.


class Role extends RefCounted:
	var id: StringName = &""
	var display := ""
	var color := Color(0.6, 0.6, 0.7)
	var accent := Color(0.9, 0.9, 0.9)
	var greeting: Array[String] = []
	var idle: Array[String] = []
	var farewell := "Safe travels."
	var shop_tags: Array[StringName] = []   ## what it stocks
	var shop_size := 8
	var markup := 1.6                       ## multiplier on the buy price
	var buys := 0.45                        ## fraction of value paid for goods
	var offers_quests := false
	var heals := false
	var repairs := false
	var teaches: Array[StringName] = []      ## recipe ids it can sell knowledge of


static var roles: Array[Role] = []
static var by_id := {}
static var _booted := false

const FIRST_NAMES := [
	"Ada", "Bex", "Cyra", "Doro", "Esk", "Fen", "Gral", "Hesh", "Ivo", "Juno",
	"Kess", "Lural", "Mott", "Nera", "Osk", "Pell", "Quen", "Rask", "Sable",
	"Tove", "Ulla", "Vint", "Wren", "Xan", "Yorl", "Zeb",
]
const SURNAMES := [
	"Ashcroft", "Blackwell", "Corradine", "Dunmoor", "Ellisar", "Farrow",
	"Greave", "Halloway", "Ironsend", "Jarrow", "Kettlemoss", "Lowmark",
	"Marrowgate", "Northgale", "Oakhollow", "Pyre", "Quillon", "Redfen",
	"Stonewake", "Thornbury", "Underhill", "Vesper", "Wainwright", "Yarrow",
]


static func boot() -> void:
	if _booted:
		return
	_booted = true
	_define_roles()


static func define(id: StringName, display: String) -> Role:
	var r := Role.new()
	r.id = id
	r.display = display
	roles.append(r)
	by_id[id] = r
	return r


static func get_role(id: StringName) -> Role:
	return by_id.get(id)


static func random_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()],
		SURNAMES[rng.randi() % SURNAMES.size()]]


## A village roster: always a merchant and a guard, then a random spread.
static func village_roster(count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var out: Array[StringName] = [&"merchant", &"guard"]
	var pool: Array[StringName] = [&"blacksmith", &"doctor", &"innkeeper",
		&"scientist", &"villager", &"villager", &"trader", &"crew_recruit"]
	while out.size() < count:
		out.append(pool[rng.randi() % pool.size()])
	return out


static func _define_roles() -> void:
	var m := define(&"merchant", "Merchant")
	m.color = Color(0.32, 0.38, 0.62)
	m.accent = Color(0.94, 0.80, 0.34)
	m.greeting = ["Everything on the shelf is for sale, and most of it works.",
		"Buying or selling? I do both, badly.",
		"You look like someone who is about to need rope."]
	m.idle = ["Prices are prices.", "No, I do not know what that one does."]
	m.shop_tags = [&"crafting", &"organic", &"fuel", &"ammo", &"food"]
	m.shop_size = 10
	m.offers_quests = true

	var b := define(&"blacksmith", "Blacksmith")
	b.color = Color(0.34, 0.30, 0.28)
	b.accent = Color(0.94, 0.52, 0.20)
	b.greeting = ["If it is bent I can straighten it. If it is broken, buy another.",
		"Ore or coin. Preferably ore.",
		"That pick has seen better seams."]
	b.idle = ["Mind the sparks.", "Tempering is waiting, mostly."]
	b.shop_tags = [&"bar", &"ore", &"tools", &"weapons", &"armor"]
	b.shop_size = 9
	b.repairs = true
	b.markup = 1.75

	var g := define(&"guard", "Guard")
	g.color = Color(0.30, 0.34, 0.40)
	g.accent = Color(0.78, 0.80, 0.86)
	g.greeting = ["Move along, and do not start anything.",
		"Something has been coming out of the caves at night.",
		"You are not from the settlement. That is fine. Behave."]
	g.idle = ["Quiet shift.", "Keep clear of the perimeter after dark."]
	g.offers_quests = true
	g.shop_tags = [&"ammo"]
	g.shop_size = 4

	var d := define(&"doctor", "Doctor")
	d.color = Color(0.86, 0.88, 0.92)
	d.accent = Color(0.90, 0.30, 0.34)
	d.greeting = ["Sit down before you fall down.",
		"You are bleeding on my floor.",
		"I can patch that. I cannot stop you doing it again."]
	d.idle = ["Drink water.", "Sleep is not optional, whatever you have been told."]
	d.shop_tags = [&"medical"]
	d.shop_size = 6
	d.heals = true

	var i := define(&"innkeeper", "Innkeeper")
	i.color = Color(0.52, 0.34, 0.24)
	i.accent = Color(0.94, 0.78, 0.42)
	i.greeting = ["Bed's upstairs, food's downstairs, questions cost extra.",
		"You have the look of somebody who has not eaten today.",
		"Room's yours till dawn."]
	i.idle = ["Mind the step.", "Stew's on."]
	i.shop_tags = [&"food", &"drink"]
	i.shop_size = 8

	var s := define(&"scientist", "Xenologist")
	s.color = Color(0.90, 0.92, 0.95)
	s.accent = Color(0.36, 0.86, 0.90)
	s.greeting = ["You have been places. Tell me about the places.",
		"Bring me something I have not catalogued and we will talk.",
		"The readings from the ruins do not make sense yet."]
	s.idle = ["Fascinating.", "That should not be possible, and yet."]
	s.shop_tags = [&"components", &"tech", &"alien"]
	s.shop_size = 7
	s.offers_quests = true
	s.markup = 2.1

	var t := define(&"trader", "Wandering Trader")
	t.color = Color(0.44, 0.30, 0.50)
	t.accent = Color(0.94, 0.86, 0.42)
	t.greeting = ["I will not be here tomorrow. Consider that a discount.",
		"Rare things, honest prices, no receipts.",
		"I came a long way with this. Make it worth the walk."]
	t.idle = ["Everything is negotiable.", "Do not ask where it came from."]
	t.shop_tags = [&"gem", &"fossil", &"alien", &"tech"]
	t.shop_size = 6
	t.markup = 2.4
	t.buys = 0.6

	var v := define(&"villager", "Settler")
	v.color = Color(0.56, 0.48, 0.38)
	v.accent = Color(0.72, 0.76, 0.60)
	v.greeting = ["Morning. Or evening. Hard to tell down here.",
		"We could use another pair of hands, if you are staying.",
		"Careful past the ridge."]
	v.idle = ["Crops are coming in.", "Somebody moved my shovel."]
	v.offers_quests = true

	var c := define(&"crew_recruit", "Drifter")
	c.color = Color(0.36, 0.42, 0.46)
	c.accent = Color(0.90, 0.62, 0.30)
	c.greeting = ["You have a ship. I have nothing. Seems like a fit.",
		"Take me with you and I will earn it.",
		"I am not from here either."]
	c.idle = ["Anywhere is better than here.", "When do we leave?"]
	c.offers_quests = true
