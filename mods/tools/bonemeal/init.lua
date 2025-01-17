
bonemeal = {}

local path = minetest.get_modpath("bonemeal")
local min, max, random = math.min, math.max, math.random


-- translation support
local S
if minetest.get_translator ~= nil then
	S = minetest.get_translator("bonemeal") -- 5.x translation function
else -- boilerplate function
	S = function(s) return s end
end


-- creative check
local creative_mode_cache = minetest.settings:get_bool("creative_mode")
function bonemeal.is_creative(name)
	return creative_mode_cache or minetest.check_player_privs(name, {creative = true})
end


-- default crops
local crops = {
	{"farming:cotton_", 8, "farming:seed_cotton"},
	{"farming:wheat_", 8, "farming:seed_wheat"}
}


-- special pine check for nearby snow
local function pine_grow(pos)

	if minetest.find_node_near(pos, 1,
		{"default:snow", "default:snowblock", "default:dirt_with_snow"}) then

		default.grow_new_snowy_pine_tree(pos)
	else
		default.grow_new_pine_tree(pos)
	end
end


-- special function for cactus growth
local function cactus_grow(pos)
	default.grow_cactus(pos, minetest.get_node(pos))
end

-- special function for papyrus growth
local function papyrus_grow(pos)
	default.grow_papyrus(pos, minetest.get_node(pos))
end


-- default saplings
local saplings = {
	{"default:sapling", default.grow_new_apple_tree, "soil"},
	{"default:junglesapling", default.grow_new_jungle_tree, "soil"},
	{"default:emergent_jungle_sapling", default.grow_new_emergent_jungle_tree, "soil"},
	{"default:acacia_sapling", default.grow_new_acacia_tree, "soil"},
	{"default:aspen_sapling", default.grow_new_aspen_tree, "soil"},
	{"default:pine_sapling", pine_grow, "soil"},
	{"default:bush_sapling", default.grow_bush, "soil"},
	{"default:acacia_bush_sapling", default.grow_acacia_bush, "soil"},
	{"default:large_cactus_seedling", default.grow_large_cactus, "sand"},
	{"default:blueberry_bush_sapling", default.grow_blueberry_bush, "soil"},
	{"default:pine_bush_sapling", default.grow_pine_bush, "soil"},
	{"default:cactus", cactus_grow, "sand"},
	{"default:papyrus", papyrus_grow, "soil"}
}

-- helper tables ( "" denotes a blank item )
local green_grass = {
	"default:grass_2", "default:grass_3", "default:grass_4",
	"default:grass_5", "", ""
}

local dry_grass = {
	"default:dry_grass_2", "default:dry_grass_3", "default:dry_grass_4",
	"default:dry_grass_5", "", ""
}

-- loads mods then add all in-game flowers except waterlily
local flowers = {}

minetest.after(0.1, function()

	for node, def in pairs(minetest.registered_nodes) do

		if def.groups
		and def.groups.flower
		and not node:find("waterlily")
		and not node:find("xdecor:potted_")
		and not node:find("df_farming:") then
			flowers[#flowers + 1] = node
		end
	end
end)


-- default biomes deco
local deco = {
	{"default:dirt", green_grass, flowers},
	{"default:dirt_with_grass", green_grass, flowers},
	{"default:dry_dirt", dry_grass, {}},
	{"default:dry_dirt_with_dry_grass", dry_grass, {}},
	{"default:dirt_with_dry_grass", dry_grass, flowers},
	{"default:sand", {}, {"default:dry_shrub", "", "", ""} },
	{"default:desert_sand", {}, {"default:dry_shrub", "", "", ""} },
	{"default:silver_sand", {}, {"default:dry_shrub", "", "", ""} },
	{"default:dirt_with_rainforest_litter", {}, {"default:junglegrass", "", "", ""}}
}


--
-- local functions
--


-- particles
local function particle_effect(pos)

	minetest.add_particlespawner({
		amount = 4,
		time = 0.15,
		minpos = pos,
		maxpos = pos,
		minvel = {x = -1, y = 2, z = -1},
		maxvel = {x = 1, y = 4, z = 1},
		minacc = {x = -1, y = -1, z = -1},
		maxacc = {x = 1, y = 1, z = 1},
		minexptime = 1,
		maxexptime = 1,
		minsize = 1,
		maxsize = 3,
		texture = "bonemeal_particle.png",
		glow = 5
	})
end


-- tree type check
local function grow_tree(pos, object)

	if type(object) == "table" and object.axiom then

		-- grow L-system tree
		minetest.remove_node(pos)
		minetest.spawn_tree(pos, object)

	elseif type(object) == "string" and minetest.registered_nodes[object] then

		-- place node
		minetest.set_node(pos, {name = object})

	elseif type(object) == "function" then

		-- function
		object(pos)
	end
end


-- sapling check
local function check_sapling(pos, sapling_node, light_ok)

	-- what is sapling placed on?
	local under =  minetest.get_node({
		x = pos.x,
		y = pos.y - 1,
		z = pos.z
	})

	local can_grow, grow_on

	-- check list for sapling and function
	for n = 1, #saplings do

		if saplings[n][1] == sapling_node then

			grow_on = saplings[n][3] or ""

			-- backwards compatibility, add 'group:' to older grouping
			if grow_on == "soil" or grow_on == "sand" then
				grow_on = "group:" .. grow_on
			end

			-- sapling grows on top of specific node group
			if grow_on:find("group:") then

				local group = grow_on:split(":")[2]

				if minetest.get_item_group(under.name, group) > 0 then
					can_grow = true
				end

			-- sapling grows on specific node
			elseif grow_on == under.name then
				can_grow = true
			end

			-- check if we can grow sapling at current light level
			if can_grow and (light_ok or saplings[n][4] == true) then

				particle_effect(pos)

				grow_tree(pos, saplings[n][2])

				return true
			end
		end
	end
end


-- crops check
local function check_crops(pos, nodename, strength, light_ok)

	local mod, crop, stage, nod, def

	-- grow registered crops
	for n = 1, #crops do

		-- check if crop can grow in current light level
		if (light_ok or crops[n][4] == true)
		and (nodename:find(crops[n][1])
		or nodename == crops[n][3]) then

			-- separate mod and node name
			mod = nodename:split(":")[1] .. ":"
			crop = nodename:split(":")[2]

			-- get stage number or set to 0 for seed
			if crop:split("_")[3] then
				stage = crop:split("_")[3]
			else
				stage = crop:split("_")[2]
			end

			stage = tonumber(stage) or 0

			stage = min(stage + strength, crops[n][2])

			-- check for place_param setting
			nod = crops[n][1] .. stage
			def = minetest.registered_nodes[nod]

			-- make sure crop exists or isn't fully grown already
			if not def or nod == nodename then
				return false
			end

			def = def and def.place_param2 or 0

			minetest.set_node(pos, {name = nod, param2 = def})

			particle_effect(pos)

			minetest.get_node_timer(pos):start(10) -- restart any timers

			return true
		end
	end
end


-- check soil for specific decoration placement
local function check_soil(pos, nodename, strength)

	-- set radius according to strength
	local side = strength - 1
	local tall = max(strength - 2, 0)

	-- get area of land with free space above
	local dirt = minetest.find_nodes_in_area_under_air(
		{x = pos.x - side, y = pos.y - tall, z = pos.z - side},
		{x = pos.x + side, y = pos.y + tall, z = pos.z + side}, {nodename})

	-- set default grass and decoration
	local grass, decor

	-- choose grass and decoration to use on dirt patch
	for n = 1, #deco do

		-- do we have a grass match?
		if nodename == deco[n][1] then

			grass = deco[n][2] or {}
			decor = deco[n][3] or {}
		end
	end

	local pos2, nod, def

	-- loop through soil
	for _, n in pairs(dirt) do

		if random(5) == 5 then

			if decor and #decor > 0 then

				-- place random decoration (rare)
				local dnum = #decor or 1

				nod = decor[random(dnum)] or ""
			end
		else
			if grass and #grass > 0 then

				-- place random grass (common)
				local dgra = #grass or 1

				nod = #grass > 0 and grass[random(dgra)] or ""
			end
		end

		pos2 = n

		pos2.y = pos2.y + 1

		if nod and nod ~= "" then

			-- get crop param2 value
			def = minetest.registered_nodes[nod]
			def = def and def.place_param2

			-- if param2 not preset then get from existing node
			if not def then

				local node = minetest.get_node_or_nil(pos2)

				def = node and node.param2 or 0
			end

			minetest.set_node(pos2, {name = nod, param2 = def})
		end

		particle_effect(pos2)
	end
end


-- helper function
local function use_checks(user, pointed_thing)

	-- make sure we use on node
	if pointed_thing.type ~= "node" then
		return false
	end

	-- get position and node info
	local pos = pointed_thing.under
	local node = minetest.get_node(pos)
	local def = minetest.registered_items[node.name]
	local dirt = def and def.groups

	-- does node exist
	if not dirt then
		return false
	end

	-- if we're using on ground, move position up
	if dirt.soil or dirt.sand or dirt.can_bonemeal then
		pos = pointed_thing.above
	end

	-- check if protected
	if minetest.is_protected(pos, user:get_player_name()) then
		return false
	end

	return node
end


-- global functions


-- add to sapling list
-- {sapling node, schematic or function name, "soil"|"sand"|specific_node|"group:"}
--e.g. {"default:sapling", default.grow_new_apple_tree, "soil"}

function bonemeal:add_sapling(list)

	for n = 1, #list do
		saplings[#saplings + 1] = list[n]
	end
end


-- add to crop list to force grow
-- {crop name start_, growth steps, seed node (if required)}
-- e.g. {"farming:wheat_", 8, "farming:seed_wheat"}
function bonemeal:add_crop(list)

	for n = 1, #list do
		crops[#crops + 1] = list[n]
	end
end


-- add grass and flower/plant decoration for specific dirt types
--  {dirt_node, {grass_nodes}, {flower_nodes}
-- e.g. {"default:dirt_with_dry_grass", dry_grass, flowers}
-- if an entry already exists for a given dirt type, it will add new entries and all empty
-- entries, allowing to both add decorations and decrease their frequency.
function bonemeal:add_deco(list)

	for l = 1, #list do

		for n = 1, #deco do

			-- update existing entry
			if list[l][1] == deco[n][1] then

				-- adding grass types
				for _, extra in pairs(list[l][2]) do

					if extra ~= "" then

						for _, entry in pairs(deco[n][2]) do

							if extra == entry then
								extra = false
								break
							end
						end
					end

					if extra then
						deco[n][2][#deco[n][2] + 1] = extra
					end
				end

				-- adding decoration types
				for _, extra in ipairs(list[l][3]) do

					if extra ~= "" then

						for __, entry in pairs(deco[n][3]) do

							if extra == entry then
								extra = false
								break
							end
						end
					end

					if extra then
						deco[n][3][#deco[n][3] + 1] = extra
					end
				end

				list[l] = false
				break
			end
		end

		if list[l] then
			deco[#deco + 1] = list[l]
		end
	end
end


-- definitively set a decration scheme
-- this function will either add a new entry as is, or replace the existing one
function bonemeal:set_deco(list)

	for l = 1, #list do

		for n = 1, #deco do

			-- replace existing entry
			if list[l][1] == deco[n][1] then

				deco[n][2] = list[l][2]
				deco[n][3] = list[l][3]

				list[l] = false

				break
			end
		end

		if list[l] then
			deco[#deco + 1] = list[l]
		end
	end
end


-- global on_use function for bonemeal
function bonemeal:on_use(pos, strength, node)

	-- get node pointed at
	local node = node or minetest.get_node(pos)

	-- return if nothing there
	if node.name == "ignore" then
		return
	end

	-- make sure strength is between 1 and 4
	strength = strength or 1
	strength = max(strength, 1)
	strength = min(strength, 4)

	-- papyrus and cactus
	if node.name == "default:papyrus" then

		default.grow_papyrus(pos, node)

		particle_effect(pos)

		return true

	elseif node.name == "default:cactus" then

		default.grow_cactus(pos, node)

		particle_effect(pos)

		return true
	end

	-- grow grass and flowers
	if minetest.get_item_group(node.name, "soil") > 0
	or minetest.get_item_group(node.name, "sand") > 0
	or minetest.get_item_group(node.name, "can_bonemeal") > 0 then

		check_soil(pos, node.name, strength)

		return true
	end

	-- light check depending on strength (strength of 4 = no light needed)
	local light_ok = true

	if (minetest.get_node_light(pos) or 0) < (12 - (strength * 3)) then
		light_ok = nil
	end

	-- check for sapling growth
	if random(5 - strength) == 1
	and check_sapling(pos, node.name, light_ok) then
		return true
	end

	-- check for crop growth
	if check_crops(pos, node.name, strength, light_ok) then
		return true
	end
end


--
-- items
--


-- mulch (strength 1)
minetest.register_craftitem("bonemeal:mulch", {
	description = S("Mulch"),
	inventory_image = "bonemeal_mulch.png",

	on_use = function(itemstack, user, pointed_thing)

		-- use helper function to do checks and return position and node
		local node = use_checks(user, pointed_thing)

		if node then

			-- call global on_use function with strength of 1
			bonemeal:on_use(pointed_thing.under, 1, node)

			-- take item if not in creative
			if not bonemeal.is_creative(user:get_player_name()) then
				itemstack:take_item()
			end
		end

		return itemstack
	end
})


-- bonemeal (strength 2)
minetest.register_craftitem("bonemeal:bonemeal", {
	description = S("Bone Meal"),
	inventory_image = "bonemeal_item.png",

	on_use = function(itemstack, user, pointed_thing)

		-- use helper function to do checks and return position and node
		local node = use_checks(user, pointed_thing)

		if node then

			-- call global on_use function with strength of 2
			bonemeal:on_use(pointed_thing.under, 2, node)

			-- take item if not in creative
			if not bonemeal.is_creative(user:get_player_name()) then
				itemstack:take_item()
			end
		end

		return itemstack
	end
})


-- fertiliser (strength 3)
minetest.register_craftitem("bonemeal:fertiliser", {
	description = S("Fertiliser"),
	inventory_image = "bonemeal_fertiliser.png",

	on_use = function(itemstack, user, pointed_thing)

		-- use helper function to do checks and return position and node
		local node = use_checks(user, pointed_thing)

		if node then

			-- call global on_use function with strength of 3
			bonemeal:on_use(pointed_thing.under, 3, node)

			-- take item if not in creative
			if not bonemeal.is_creative(user:get_player_name()) then
				itemstack:take_item()
			end
		end

		return itemstack
	end
})


-- bone
minetest.register_craftitem("bonemeal:bone", {
	description = S("Bone"),
	inventory_image = "bonemeal_bone.png",
	groups = {bone = 1}
})

-- gelatin powder
minetest.register_craftitem("bonemeal:gelatin_powder", {
	description = S("Gelatin Powder"),
	inventory_image = "bonemeal_gelatin_powder.png",
	groups = {food_gelatin = 1, flammable = 2}
})


--
-- crafting recipes
--


-- gelatin powder
minetest.register_craft({
	output = "bonemeal:gelatin_powder 4",
	recipe = {
		{"group:bone", "group:bone", "group:bone"},
		{"bucket:bucket_water", "bucket:bucket_water", "bucket:bucket_water"},
		{"bucket:bucket_water", "default:torch", "bucket:bucket_water"}
	},
	replacements = {
		{"bucket:bucket_water", "bucket:bucket_empty 5"}
	}
})

-- bonemeal (from bone)
minetest.register_craft({
	output = "bonemeal:bonemeal 2",
	recipe = {{"group:bone"}}
})

-- bonemeal (from player bones)
if minetest.settings:get_bool("bonemeal.disable_deathbones_recipe") ~= true then

	minetest.register_craft({
		output = "bonemeal:bonemeal 4",
		recipe = {{"bones:bones"}}
	})
end

-- bonemeal (from coral skeleton)
minetest.register_craft({
	output = "bonemeal:bonemeal 2",
	recipe = {{"default:coral_skeleton"}}
})

-- mulch
minetest.register_craft({
	output = "bonemeal:mulch 4",
	recipe = {
		{"group:tree", "group:leaves", "group:leaves"},
		{"group:leaves", "group:leaves", "group:leaves"},
		{"group:leaves", "group:leaves", "group:leaves"}
	}
})

minetest.register_craft({
	output = "bonemeal:mulch",
	recipe = {
		{"group:seed", "group:seed", "group:seed"},
		{"group:seed", "group:seed", "group:seed"},
		{"group:seed", "group:seed", "group:seed"}
	}
})

-- fertiliser
minetest.register_craft({
	output = "bonemeal:fertiliser 2",
	recipe = {{"bonemeal:bonemeal", "bonemeal:mulch"}}
})


-- add bones to dirt
minetest.override_item("default:dirt", {
	drop = {
		max_items = 1,
		items = {
			{
				items = {"bonemeal:bone"},
				rarity = 40
			},
			{
				items = {"default:dirt"}
			}
		}
	}
})


-- add support for other mods
dofile(path .. "/mods.lua")

-- lucky block support
if minetest.get_modpath("lucky_block") then
	dofile(path .. "/lucky_block.lua")
end


print ("[MOD] Bonemeal loaded")
