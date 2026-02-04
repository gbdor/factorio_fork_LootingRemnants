-- LootingRemnants
-- darkfrei 2020-12-03 (original), refactored


-----------------------------------
-- CONSTANTS and SETTINGS
-----------------------------------

local IGNORES = require("cfg/ignores")
local CONSTANTS = require("cfg/constants")


local settings_loot_proba = settings.startup[CONSTANTS.MOD_NAME .. "-loot-proba"].value
local settings_loot_min = settings.startup[CONSTANTS.MOD_NAME .. "-loot-min"].value
local settings_loot_max = settings.startup[CONSTANTS.MOD_NAME .. "-loot-max"].value
local settings_verbose = settings.startup[CONSTANTS.MOD_NAME .. "-verbose-logging"].value or false

if settings_loot_max < settings_loot_min then
	error(("[%s.%s] loot max (%d) < loot min (%d)"):format(CONSTANTS.MOD_NAME, FILENAME, settings_loot_max, settings_loot_min))
end

-----------------------------------
-- LOGGING
-----------------------------------

-- L is an alias to either log() if enabled, otherwise to a no-op function
-- call with L(("%s ..."):format(x, ..))
local L = settings_verbose and log or function() end

-- Prefix could be added with this hack
-- local P = "[prefix] "
-- local L = <setting> and log or function() end
-- L(P .. ("x=%s"):format(x))


-----------------------------------
-- HELPERS
-----------------------------------

-- Returns true if the prototype has an entry to exclude this mod
--[[
for example add the line
data.raw.car.car.exception_mods = {"Deconstruction", "LootingRemnants"} 
and this prototype will be ignored by this mods
--]]
local function is_excepted(prototype)
	local mods = prototype and prototype.exception_mods
	if type(mods) ~= "table" then return false end
	for _, name in pairs(mods) do
		if name == CONSTANTS.MOD_NAME then 
			L(("Skipping proto '%s' that has an exclusion for mods %s"):format(prototype.name, serpent.line(mods)))
			return true 
		end
	end
	return false
end


local function append_nospawn_items(nospawn_table, comma_separated_items_list)

	if type(comma_separated_items_list) ~= "string" then
		error(("Unable to parse exclude string'%s' - expecting comma-separated list"):format(comma_separated_items_list))
	end

	if comma_separated_items_list == "" then return end

	for itemname in string.gmatch(comma_separated_items_list,  "[^,%s]+") do
		L(("processing item '%s'"):format(itemname))
		nospawn_table[itemname] = true
	end

	L(("Updated no-spawn with '%s' -> %s"):format(comma_separated_items_list, serpent.line(nospawn_table)))
end


-- Finds the first minable entity prototype matching `entity_name` across all
-- of data.raw.  Also records any new prototype types it encounters into
-- `seen_types` as a side effect (used for the final log line).
local function find_entity_prototype(entity_name, seen_types)
	for type_name, type_table in pairs(data.raw) do
		local proto = type_table[entity_name]
		if proto and proto.minable then
			seen_types[type_name] = true
			return proto
		end
	end
	return nil
end


-- Returns the ingredient as { name, amount } if it is an item, or nil
-- if it is a fluid or other non-item type.
local function normalise_ingredient(ingredient)
	if ingredient.type ~= "item" then return nil end

	return {
		name   = ingredient.name,
		amount = ingredient.amount,
	}
end

-----------------------------------
-- LOOT BUILDING
-----------------------------------

-- Given a recipe, returns a loot table suitable for
-- assignment to a prototype, or nil if no valid loot entries remain.
local function build_loot(recipe)
	local loot = {}

	for _, raw_ingredient in pairs(recipe.ingredients) do
		local ing = normalise_ingredient(raw_ingredient)
		if ing then
			if IGNORES.ITEMS_NEVER_SPAWN[ing.name] then
				L(("Skipping blacklisted item '%s' from recipe '%s'"):format(ing.name, recipe.name))
			else
				local actual_cost = ing.amount/(recipe.results.amount or 1) 
				local cur_loot_item = {
					item        = ing.name,
					probability = settings_loot_proba,
					count_min   = settings_loot_min*actual_cost,
					count_max   = settings_loot_max*actual_cost
				}

				table.insert(loot, cur_loot_item)
			end
		end
	end

	L(("Recipe '%s' provides loot %s"):format(recipe.name, serpent.block(loot)))
	return (#loot > 0) and loot or nil
end

-----------------------------------
-- RECIPE EXTRACTION
-----------------------------------

-- Finds the single item output in a recipe's results.
-- Returns {name, amount} if exactly one item output exists (other non-item
-- outputs are ignored). Returns nil if there are zero or multiple item outputs.
local function get_recipe_item_output(recipe)
	if not recipe.results then return nil end

	local found = nil
	for _, output in pairs(recipe.results) do
		if output.type == "item" then
			if found then
				L(("Skipping recipe '%s' — multiple item outputs"):format(recipe.name))
				return nil
			end
			found = output
		end
	end

	if not found then
		L(("Skipping recipe '%s' — no item outputs"):format(recipe.name))
		return nil
	end

	return { name = found.name, amount = found.amount }
end

-----------------------------------
-- CORE: resolve recipe -> entity -> assign loot
-----------------------------------

-- Attempts to assign loot to the entity that `recipe` produces.
-- `seen_types` is passed through for prototype-type tracking.
local function process_recipe(recipe, seen_types)
	if not recipe.ingredients then return end

	local output = get_recipe_item_output(recipe)
	if not output then return end

	local item_proto = data.raw.item[output.name]
	if not item_proto or not item_proto.place_result then
		L(("Skipping non-placeable item '%s' in recipe '%s'"):format(output.name, recipe.name))
		return
	end

	local entity_name = item_proto.place_result
	local entity_proto = find_entity_prototype(entity_name, seen_types)
	if not entity_proto then
		L(("No minable prototype found for entity '%s' in recipe '%s'"):format(entity_name, recipe.name))
		return
	end

	if is_excepted(entity_proto) then return end

	if entity_proto.loot then
		L(("Skipping entity '%s' in recipe '%s' — already has loot %s"):format(entity_name, recipe.name, serpent.block(entity_proto.loot)))
		return
	end

	local loot = build_loot(recipe)
	if loot then
		entity_proto.loot = loot
		L(("Assigned %d loot entries to '%s' in recipe '%s'"):format(table_size(loot), entity_name, recipe.name))
	else
		L(("No valid loot built for entity '%s' in recipe '%s'"):format(entity_name, recipe.name))
	end
end

-----------------------------------
-- MAIN LOOP
-----------------------------------

local seen_types = {}


append_nospawn_items(IGNORES.ITEMS_NEVER_SPAWN, settings.startup[CONSTANTS.MOD_NAME .. "-extra-nospawn-items"].value)

for _, recipe in pairs(data.raw.recipe) do

    -- Skip recycling recipes
    if string.sub(recipe.name, -10) == "-recycling" then
    	L(("Skipping recycling recipe '%s'"):format(recipe.name))

    elseif is_excepted(recipe) then
    	L(("Skipping excepted recipe '%s'"):format(recipe.name))

    else
    	process_recipe(recipe, seen_types)
    end
  end

-- Log all prototype types that were encountered
local type_list = {}
for t in pairs(seen_types) do table.insert(type_list, t) end
log("Added loot to entities: " .. serpent.line(type_list))