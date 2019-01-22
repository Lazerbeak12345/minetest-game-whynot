craftguide = {
	custom_crafts = {},
	craft_types = {},
}

local mt = minetest
local player_data = {}
local init_items = {}
local recipes_cache = {}
local fuel_cache = {}
local searches = {}

local progressive_mode = mt.settings:get_bool("craftguide_progressive_mode")
local sfinv_only       = mt.settings:get_bool("craftguide_sfinv_only")

local reg_items = mt.registered_items
local get_result = mt.get_craft_result
local show_formspec = mt.show_formspec

-- Intllib
local S = dofile(mt.get_modpath("craftguide") .. "/intllib.lua")

-- Lua 5.3 removed `table.maxn`, use this alternative in case of breakage:
-- https://github.com/kilbith/xdecor/blob/master/handlers/helpers.lua#L1
local maxn, sort, concat = table.maxn, table.sort, table.concat
local vector_add, vector_mul = vector.add, vector.multiply
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil
local fmt = string.format

local DEFAULT_SIZE = 10
local MIN_LIMIT, MAX_LIMIT = 10, 12
DEFAULT_SIZE = min(MAX_LIMIT, max(MIN_LIMIT, DEFAULT_SIZE))

local GRID_LIMIT = 5

local fmt_label   = "label[%f,%f;%s]"
local fmt_image   = "image[%f,%f;%f,%f;%s]"
local fmt_tooltip = "tooltip[%f,%f;%f,%f;%s]"

local group_stereotypes = {
	wool         = "wool:white",
	dye          = "dye:white",
	water_bucket = "bucket:bucket_water",
	vessel       = "vessels:glass_bottle",
	coal         = "default:coal_lump",
	flower       = "flowers:dandelion_yellow",
	mesecon_conductor_craftable = "mesecons:wire_00000000_off",
}

local function __func()
	return debug.getinfo(2, "n").name
end

function craftguide.register_craft_type(name, def)
	local func = "craftguide." .. __func() .. "(): "
	assert(name, func .. "'name' field missing")
	assert(def.description, func .. "'description' field missing")
	assert(def.icon, func .. "'icon' field missing")

	if not craftguide.craft_types[name] then
		craftguide.craft_types[name] = def
	end
end

craftguide.register_craft_type("digging", {
	description = S("Digging"),
	icon = "default_tool_steelpick.png",
})

function craftguide.register_craft(def)
	local func = "craftguide." .. __func() .. "(): "
	assert(def.type, func .. "'type' field missing")
	assert(def.width, func .. "'width' field missing")
	assert(def.output, func .. "'output' field missing")
	assert(def.items, func .. "'items' field missing")

	craftguide.custom_crafts[#craftguide.custom_crafts + 1] = def
end

craftguide.register_craft({
	type   = "digging",
	width  = 1,
	output = "default:cobble",
	items  = {"default:stone"},
})

local function cache_recipes(output)
	local recipes = mt.get_all_craft_recipes(output) or {}
	for i = 1, #craftguide.custom_crafts do
		local custom_craft = craftguide.custom_crafts[i]
		if custom_craft.output:match("%S*") == output then
			recipes[#recipes + 1] = custom_craft
		end
	end

	if #recipes > 0 then
		recipes_cache[output] = recipes
		return true
	end
end

local function get_burntime(item)
	return get_result({method = "fuel", width = 1, items = {item}}).time
end

local function cache_fuel(item)
	local burntime = get_burntime(item)
	if burntime > 0 then
		fuel_cache[item] = burntime
		return true
	end
end

local function extract_groups(str)
	return str:sub(7):split(",")
end

local function item_has_groups(item_groups, groups)
	for i = 1, #groups do
		local group = groups[i]
		if not item_groups[group] then
			return
		end
	end

	return true
end

local function groups_to_item(groups)
	if #groups == 1 then
		local group = groups[1]
		if group_stereotypes[group] then
			return group_stereotypes[group]
		elseif reg_items["default:" .. group] then
			return "default:" .. group
		end
	end

	for name, def in pairs(reg_items) do
		if item_has_groups(def.groups, groups) then
			return name
		end
	end

	return ""
end

local function get_tooltip(item, groups, cooktime, burntime)
	local tooltip

	if groups then
		local groupstr = {}
		for i = 1, #groups do
			groupstr[#groupstr + 1] = mt.colorize("yellow", groups[i])
		end

		groupstr = concat(groupstr, ", ")
		tooltip = S("Any item belonging to the group(s):") .. " " .. groupstr
	else
		tooltip = reg_items[item].description
	end

	if cooktime then
		tooltip = tooltip .. "\n" .. S("Cooking time:") .. " " ..
			mt.colorize("yellow", cooktime)
	end

	if burntime then
		tooltip = tooltip .. "\n" .. S("Burning time:") .. " " ..
			mt.colorize("yellow", burntime)
	end

	return "tooltip[" .. item .. ";" .. tooltip .. "]"
end

local function get_recipe_fs(data, iY)
	local fs = {}
	local recipe = data.recipes[data.rnum]
	local width = recipe.width
	local xoffset = data.iX / 2.15
	local cooktime, shapeless

	if recipe.type == "cooking" then
		cooktime, width = width, 1
	elseif width == 0 then
		shapeless = true
		width = min(3, #recipe.items)
	end

	local rows = ceil(maxn(recipe.items) / width)
	local rightest, btn_size, s_btn_size = 0, 1.1

	if width > GRID_LIMIT or rows > GRID_LIMIT then
		fs[#fs + 1] = fmt(fmt_label,
			(data.iX / 2) - 2,
			iY + 2.2,
			S("Recipe is too big to be displayed (@1x@2)", width, rows))

		return concat(fs)
	end

	for i, item in pairs(recipe.items) do
		local X = ceil((i - 1) % width + xoffset - width) -
			(sfinv_only and 0 or 0.2)
		local Y = ceil(i / width + (iY + 2) - min(2, rows))

		if width > 3 or rows > 3 then
			btn_size = width > 3 and 3 / width or 3 / rows
			s_btn_size = btn_size
			X = btn_size * (i % width) + xoffset - 2.65
			Y = btn_size * floor((i - 1) / width) + (iY + 3) - min(2, rows)
		end

		if X > rightest then
			rightest = X
		end

		local groups
		if item:sub(1,6) == "group:" then
			groups = extract_groups(item)
			item = groups_to_item(groups)
		end

		local label = groups and "\nG" or ""

		fs[#fs + 1] = fmt("item_image_button[%f,%f;%f,%f;%s;%s;%s]",
			X,
			Y + (sfinv_only and 0.7 or 0.2),
			btn_size,
			btn_size,
			item,
			item:match("%S*"),
			label)

		local burntime = fuel_cache[item]

		if groups or cooktime or burntime then
			fs[#fs + 1] = get_tooltip(item, groups, cooktime, burntime)
		end
	end

	local custom_recipe = craftguide.craft_types[recipe.type]

	if custom_recipe or shapeless or recipe.type == "cooking" then
		local icon = custom_recipe and custom_recipe.icon or
				shapeless and "shapeless" or "furnace"
		if not custom_recipe then
			icon = "craftguide_" .. icon .. ".png^[resize:16x16"
		end

		fs[#fs + 1] = fmt(fmt_image,
			rightest + 1.2,
			iY + (sfinv_only and 2.2 or 1.7),
			0.5,
			0.5,
			icon)

		local tooltip = custom_recipe and custom_recipe.description or
				shapeless and S("Shapeless") or S("Cooking")

		fs[#fs + 1] = fmt(fmt_tooltip,
			rightest + 1.2,
			iY + (sfinv_only and 2.2 or 1.7),
			0.5,
			0.5,
			tooltip)
	end

	local arrow_X  = rightest + (s_btn_size or 1.1)
	local output_X = arrow_X + 0.9

	fs[#fs + 1] = fmt(fmt_image,
		arrow_X,
		iY + (sfinv_only and 2.85 or 2.35),
		0.9,
		0.7,
		"craftguide_arrow.png")

	if recipe.type == "fuel" then
		fs[#fs + 1] = fmt(fmt_image,
			output_X,
			iY + (sfinv_only and 2.68 or 2.18),
			1.1,
			1.1,
			"craftguide_fire.png")
	else
		local output_name = recipe.output:match("%S+")
		local burntime = fuel_cache[output_name]

		fs[#fs + 1] = fmt("item_image_button[%f,%f;%f,%f;%s;%s;]",
			output_X,
			iY + (sfinv_only and 2.7 or 2.2),
			1.1,
			1.1,
			recipe.output,
			output_name)

		if burntime then
			fs[#fs + 1] = get_tooltip(output_name, nil, nil, burntime)

			fs[#fs + 1] = fmt(fmt_image,
				output_X + 1,
				iY + (sfinv_only and 2.83 or 2.33),
				0.6,
				0.4,
				"craftguide_arrow.png")

			fs[#fs + 1] = fmt(fmt_image,
				output_X + 1.6,
				iY + (sfinv_only and 2.68 or 2.18),
				0.6,
				0.6,
				"craftguide_fire.png")
		end
	end

	fs[#fs + 1] = fmt("button[%f,%f;%f,%f;%s;%s %u %s %u]",
		data.iX - (sfinv_only and 2.2 or 2.6),
		iY + (sfinv_only and 3.9 or 3.3),
		2.2,
		1,
		"alternate",
		data.show_usages and S("Usage") or S("Recipe"),
		data.rnum,
		S("of"),
		#data.recipes)

	return concat(fs)
end

local function make_formspec(player_name)
	local data = player_data[player_name]
	local iY = sfinv_only and 4 or data.iX - 5
	local ipp = data.iX * iY

	data.pagemax = max(1, ceil(#data.items / ipp))

	local fs = {}
	if not sfinv_only then
		fs[#fs + 1] = "size[" .. (data.iX - 0.35) .. "," .. (iY + 4) .. ";]"
		fs[#fs + 1] = "no_prepend[]"
		fs[#fs + 1] = "background[1,1;1,1;craftguide_bg.png;true]"
		fs[#fs + 1] = "tooltip[size_inc;" .. S("Increase window size") .. "]"
		fs[#fs + 1] = "tooltip[size_dec;" .. S("Decrease window size") .. "]"
		fs[#fs + 1] = "image_button[" .. (data.iX * 0.47) ..
				",0.12;0.8,0.8;craftguide_zoomin_icon.png;size_inc;]"
		fs[#fs + 1] = "image_button[" .. ((data.iX * 0.47) + 0.6) ..
				",0.12;0.8,0.8;craftguide_zoomout_icon.png;size_dec;]"
	end

	fs[#fs + 1] = [[
		image_button[2.4,0.12;0.8,0.8;craftguide_search_icon.png;search;]
		image_button[3.05,0.12;0.8,0.8;craftguide_clear_icon.png;clear;]
		field_close_on_enter[filter;false]
	]]

	fs[#fs + 1] = "tooltip[search;" .. S("Search") .. "]"
	fs[#fs + 1] = "tooltip[clear;" .. S("Reset") .. "]"
	fs[#fs + 1] = "tooltip[prev;" .. S("Previous page") .. "]"
	fs[#fs + 1] = "tooltip[next;" .. S("Next page") .. "]"
	fs[#fs + 1] = "image_button[" .. (data.iX - (sfinv_only and 2.6 or 3.1)) ..
			",0.12;0.8,0.8;craftguide_prev_icon.png;prev;]"
	fs[#fs + 1] = "label[" .. (data.iX - (sfinv_only and 1.7 or 2.2)) .. ",0.22;" ..
			mt.colorize("yellow", data.pagenum) .. " / " .. data.pagemax .. "]"
	fs[#fs + 1] = "image_button[" .. (data.iX - (sfinv_only and 0.7 or 1.2) -
			(data.iX >= 11 and 0.08 or 0)) ..
			",0.12;0.8,0.8;craftguide_next_icon.png;next;]"
	fs[#fs + 1] = "field[0.3,0.32;2.5,1;filter;;" .. mt.formspec_escape(data.filter) .. "]"

	if #data.items == 0 then
		fs[#fs + 1] = fmt(fmt_label,
			(data.iX / 2) - 1,
			2,
			S("No item to show"))
	end

	local first_item = (data.pagenum - 1) * ipp
	for i = first_item, first_item + ipp - 1 do
		local name = data.items[i + 1]
		if not name then
			break
		end

		local X = i % data.iX
		local Y = (i % ipp - X) / data.iX + 1

		fs[#fs + 1] = fmt("item_image_button[%f,%f;%f,%f;%s;%s_inv;]",
			X - (sfinv_only and 0 or (X * 0.05)),
			Y,
			1.1,
			1.1,
			name,
			name)
	end

	if data.recipes and #data.recipes > 0 then
		fs[#fs + 1] = get_recipe_fs(data, iY)
	end

	return concat(fs)
end

local show_fs = function(player, player_name)
	if sfinv_only then
		sfinv.set_player_inventory_formspec(player)
	else
		local data = player_data[player_name]
		data.formspec = make_formspec(player_name)
		show_formspec(player_name, "craftguide", data.formspec)
	end
end

local function filter_items(data)
	local filter = data.filter
	if searches[filter] then
		data.items = searches[filter]
		return
	end

	local items_list = progressive_mode and data.progressive_items or init_items
	local filtered_list, c = {}, 0

	for i = 1, #items_list do
		local item = items_list[i]
		local item_desc = reg_items[item].description:lower()

		if item:find(filter, 1, true) or item_desc:find(filter, 1, true) then
			c = c + 1
			filtered_list[c] = item
		end
	end

	if not progressive_mode then
		-- Cache the results only if searched 2 times
		if searches[filter] == nil then
			searches[filter] = false
		else
			searches[filter] = filtered_list
		end
	end

	data.items = filtered_list
end

local function item_in_recipe(item, recipe)
	local item_groups = reg_items[item].groups
	for _, recipe_item in pairs(recipe.items) do
		if recipe_item == item then
			return true
		elseif recipe_item:sub(1,6) == "group:" then
			local groups = extract_groups(recipe_item)
			if item_has_groups(item_groups, groups) then
				return true
			end
		end
	end
end

local function get_item_usages(item)
	local usages = {}
	for _, recipes in pairs(recipes_cache) do
		for i = 1, #recipes do
			local recipe = recipes[i]
			if item_in_recipe(item, recipe) then
				usages[#usages + 1] = recipe
			end
		end
	end

	if fuel_cache[item] then
		usages[#usages + 1] = {type = "fuel", width = 1, items = {item}}
	end

	return usages
end

local function get_inv_items(player)
	local inv = player:get_inventory()
	local stacks = inv:get_list("main")
	local craftlist = inv:get_list("craft")

	for i = 1, #craftlist do
		stacks[#stacks + 1] = craftlist[i]
	end

	local inv_items = {}
	for i = 1, #stacks do
		local stack = stacks[i]
		if not stack:is_empty() then
			local name = stack:get_name()
			if not inv_items[name] and reg_items[name] then
				inv_items[#inv_items + 1] = name
			end
		end
	end

	return inv_items
end

local function item_in_inv(item, inv_items)
	if item:sub(1,6) == "group:" then
		local groups = extract_groups(item)
		for i = 1, #inv_items do
			local item_groups = reg_items[inv_items[i]].groups
			if item_has_groups(item_groups, groups) then
				return true
			end
		end
	else
		for i = 1, #inv_items do
			if inv_items[i] == item then
				return true
			end
		end
	end
end

local function progressive_default_filter(recipes, player)
	local inv_items = get_inv_items(player)
	if #inv_items == 0 then
		return {}
	end

	local filtered = {}
	for i = 1, #recipes do
		local recipe = recipes[i]
		local recipe_in_inv = true
		for _, item in pairs(recipe.items) do
			if not item_in_inv(item, inv_items) then
				recipe_in_inv = false
			end
		end

		if recipe_in_inv then
			filtered[#filtered + 1] = recipe
		end
	end

	return filtered
end

local progressive_filters = {{
	name = "Default filter",
	func = progressive_default_filter,
}}

function craftguide.add_progressive_filter(name, func)
	progressive_filters[#progressive_filters + 1] = {
		name = name,
		func = func,
	}
end

function craftguide.set_progressive_filter(name, func)
	progressive_filters = {{
		name = name,
		func = func,
	}}
end

function craftguide.get_progressive_filters()
	return progressive_filters
end

local function apply_progressive_filters(recipes, player)
	for i = 1, #progressive_filters do
		local func = progressive_filters[i].func
		recipes = func(recipes, player)
	end

	return recipes
end

local function get_progressive_items(player)
	local items = {}
	for i = 1, #init_items do
		local item = init_items[i]
		local recipes = recipes_cache[item]

		if recipes then
			recipes = apply_progressive_filters(recipes, player)
			if #recipes > 0 then
				items[#items + 1] = item
			end
		end
	end

	return items
end

local function init_data(player, name)
	local p_items = progressive_mode and get_progressive_items(player) or nil
	player_data[name] = {
		filter  = "",
		pagenum = 1,
		iX      = sfinv_only and 8 or DEFAULT_SIZE,
		items   = p_items or init_items,
		progressive_items = p_items,
	}
end

local function reset_data(data)
	data.filter      = ""
	data.pagenum     = 1
	data.query_item  = nil
	data.show_usages = nil
	data.recipes     = nil
	data.items       = progressive_mode and data.progressive_items or init_items
end

local function get_init_items()
	local c = 0
	for name, def in pairs(reg_items) do
		local is_fuel = cache_fuel(name)
		if not (def.groups.not_in_craft_guide == 1 or
				def.groups.not_in_creative_inventory == 1) and
				def.description and def.description ~= "" and
				(cache_recipes(name) or is_fuel) then
			c = c + 1
			init_items[c] = name
		end
	end

	sort(init_items)
end

mt.register_on_mods_loaded(get_init_items)

local function on_receive_fields(player, fields)
	local player_name = player:get_player_name()
	local data = player_data[player_name]

	if fields.clear then
		reset_data(data)
		show_fs(player, player_name)

	elseif fields.alternate then
		if #data.recipes == 1 then
			return
		end

		local num_next = data.rnum + 1
		data.rnum = data.recipes[num_next] and num_next or 1
		show_fs(player, player_name)

	elseif (fields.key_enter_field == "filter" or fields.search) and
			fields.filter ~= "" then
		local fltr = fields.filter:lower()
		if not progressive_mode and data.filter == fltr then
			return
		end

		data.filter = fltr
		data.pagenum = 1
		filter_items(data)
		show_fs(player, player_name)

	elseif fields.prev or fields.next then
		if data.pagemax == 1 then
			return
		end

		data.pagenum = data.pagenum - (fields.prev and 1 or -1)
		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end

		show_fs(player, player_name)

	elseif (fields.size_inc and data.iX < MAX_LIMIT) or
			(fields.size_dec and data.iX > MIN_LIMIT) then
		data.pagenum = 1
		data.iX = data.iX + (fields.size_inc and 1 or -1)
		show_fs(player, player_name)

	else
		local item
		for field in pairs(fields) do
			if field:find(":") then
				item = field
				break
			end
		end

		if not item then
			return
		elseif item:sub(-4) == "_inv" then
			item = item:sub(1,-5)
		end

		local is_fuel = fuel_cache[item]
		local recipes = recipes_cache[item]

		if progressive_mode and recipes then
			recipes = apply_progressive_filters(recipes, player)
		end

		local no_recipes = not recipes or #recipes == 0
		if no_recipes and not is_fuel then
			return
		end

		if item ~= data.query_item then
			data.show_usages = nil
		else
			data.show_usages = not data.show_usages
		end

		if is_fuel and no_recipes then
			data.show_usages = true
		end

		if data.show_usages then
			recipes = get_item_usages(item)

			if progressive_mode then
				recipes = apply_progressive_filters(recipes, player)
			end

			if #recipes == 0 then
				return
			end
		end

		data.query_item = item
		data.recipes = recipes
		data.rnum = 1

		show_fs(player, player_name)
	end
end

if sfinv_only then
	sfinv.register_page("craftguide:craftguide", {
		title = "Craft Guide",

		get = function(self, player, context)
			local formspec = make_formspec(player:get_player_name())
			return sfinv.make_formspec(player, context, formspec)
		end,

		on_enter = function(self, player, context)
			local player_name = player:get_player_name()
			local data = player_data[player_name]

			if not data then
				init_data(player, player_name)
			elseif progressive_mode then
				data.progressive_items = get_progressive_items(player)
				filter_items(data)
			end
		end,

		on_player_receive_fields = function(self, player, context, fields)
			on_receive_fields(player, fields)
		end,
	})
else
	mt.register_on_player_receive_fields(function(player, formname, fields)
		if formname == "craftguide" then
			on_receive_fields(player, fields)
		end
	end)

	local function on_use(user)
		local player_name = user:get_player_name()
		local data = player_data[player_name]

		if not data then
			init_data(user, player_name)
			data = player_data[player_name]
			data.formspec = make_formspec(player_name)
		elseif progressive_mode then
			data.progressive_items = get_progressive_items(user)
			filter_items(data)
			data.formspec = make_formspec(player_name)
		end

		show_formspec(player_name, "craftguide", data.formspec)
	end

	mt.register_craftitem("craftguide:book", {
		description = S("Crafting Guide"),
		inventory_image = "craftguide_book.png",
		wield_image = "craftguide_book.png",
		stack_max = 1,
		groups = {book = 1},
		on_use = function(itemstack, user)
			on_use(user)
		end
	})

	mt.register_node("craftguide:sign", {
		description = S("Crafting Guide Sign"),
		drawtype = "nodebox",
		tiles = {"craftguide_sign.png"},
		inventory_image = "craftguide_sign_inv.png",
		wield_image = "craftguide_sign_inv.png",
		paramtype = "light",
		paramtype2 = "wallmounted",
		sunlight_propagates = true,
		groups = {oddly_breakable_by_hand = 1, flammable = 3},
		node_box = {
			type = "wallmounted",
			wall_top    = {-0.4375, 0.4375, -0.3125, 0.4375, 0.5, 0.3125},
			wall_bottom = {-0.4375, -0.5, -0.3125, 0.4375, -0.4375, 0.3125},
			wall_side   = {-0.5, -0.3125, -0.4375, -0.4375, 0.3125, 0.4375}
		},

		on_construct = function(pos)
			local meta = mt.get_meta(pos)
			meta:set_string("infotext", S("Crafting Guide Sign"))
		end,

		on_rightclick = function(pos, node, user, itemstack)
			on_use(user)
		end
	})

	mt.register_craft({
		output = "craftguide:book",
		type = "shapeless",
		recipe = {"default:book"}
	})

	mt.register_craft({
		type = "fuel",
		recipe = "craftguide:book",
		burntime = 3
	})

	mt.register_craft({
		output = "craftguide:sign",
		type = "shapeless",
		recipe = {"default:sign_wall_wood"}
	})

	mt.register_craft({
		type = "fuel",
		recipe = "craftguide:sign",
		burntime = 10
	})

	if rawget(_G, "sfinv_buttons") then
		sfinv_buttons.register_button("craftguide", {
			title = S("Crafting Guide"),
			tooltip = S("Shows a list of available crafting recipes, cooking recipes and fuels"),
			image = "craftguide_book.png",
			action = function(player)
				on_use(player)
			end,
		})
	end
end

if not progressive_mode then
	mt.register_chatcommand("craft", {
		description = S("Show recipe(s) of the pointed node"),
		func = function(name)
			local player = mt.get_player_by_name(name)
			local ppos   = player:get_pos()
			local dir    = player:get_look_dir()
			local eye_h  = {x = ppos.x, y = ppos.y + 1.625, z = ppos.z}
			local node_name

			for i = 1, 10 do
				local look_at = vector_add(eye_h, vector_mul(dir, i))
				local node = mt.get_node(look_at)

				if node.name ~= "air" then
					node_name = node.name
					break
				end
			end

			if not node_name then
				return false, mt.colorize("red", "[craftguide] ") ..
						S("No node pointed")
			elseif not player_data[name] then
				init_data(player, name)
			end

			local data = player_data[name]
			reset_data(data)

			local recipes = recipes_cache[node_name]
			local no_recipes = not next(recipes)
			local is_fuel = fuel_cache[node_name]

			if no_recipes and not is_fuel then
				return false, mt.colorize("red", "[craftguide] ") ..
					S("No recipe for this node:") .. " " ..
					mt.colorize("yellow", node_name)
			end

			if is_fuel and no_recipes then
				recipes = get_item_usages(node_name)

				if #recipes > 0 then
					data.show_usages = true
				end
			end

			data.query_item = node_name
			data.recipes = recipes

			return true, show_fs(player, name)
		end,
	})
end

mt.register_on_leaveplayer(function(player)
	if player then
		local name = player:get_player_name()
		player_data[name] = nil
	end
end)

--[[ Custom recipes (>3x3) test code

mt.register_craftitem(":secretstuff:custom_recipe_test", {
	description = "Custom Recipe Test",
})

local cr = {}
for x = 1, 6 do
	cr[x] = {}
	for i = 1, 10 - x do
		cr[x][i] = {}
		for j = 1, 10 - x do
			cr[x][i][j] = "group:sand"
		end
	end

	mt.register_craft({
		output = "secretstuff:custom_recipe_test",
		recipe = cr[x]
	})
end
]]