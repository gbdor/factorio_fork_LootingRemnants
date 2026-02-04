-- LootingRemnants
-- darkfrei 2020-12-03 (original), refactored

local IGNORES = require("cfg/ignores")
local CONSTANTS = require("cfg/constants")


local settings_loot_proba = settings.startup[constants.MOD_NAME .. "-loot-proba"].value
local settings_loot_min = settings.startup[constants.MOD_NAME .. "-loot-min"].value
local settings_loot_max = settings.startup[constants.MOD_NAME .. "-loot-max"].value

if settings_loot_max < settings_loot_min then
	error(string.format("[%s.%s] loot max (%d) < loot min (%d)", constants.MOD_NAME, FILENAME, settings_loot_max, settings_loot_min))
end


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
			log(string.format("[LootingRemnants] Skipping proto '%s' that has an exclusion for mods %s", prototype.name, serpent.line(mods)))
			return true 
		end
	end
	return false
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
				log(string.format("[LootingRemnants] Skipping blacklisted item '%s' from recipe '%s'", ing.name, recipe.name))
			else
				local actual_cost = ing.amount/(recipe.results.amount or 1) 
				local cur_loot_item = {
					item        = ing.name,
					probability = settings_loot_proba,
					count_min   = settings_loot_min*actual_cost
					count_max   = settings_loot_max*actual_cost
				}

				table.insert(loot, cur_loot_item)
			end
		end
	end

	log(string.format("[LootingRemnants] Recipe '%s' provides loot %s", recipe.name, serpent.block(loot)))
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
				log(string.format("[LootingRemnants] Skipping recipe '%s' — multiple item outputs", recipe.name))
				return nil
			end
			found = output
		end
	end

	if not found then
		log(string.format("[LootingRemnants] Skipping recipe '%s' — no item outputs", recipe.name))
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
		-- log(string.format("[LootingRemnants] Skipping non-placeable item '%s' in recipe '%s'", output.name, recipe.name))
		return
	end

	local entity_name = item_proto.place_result
	local entity_proto = find_entity_prototype(entity_name, seen_types)
	if not entity_proto then
		-- log(string.format("[LootingRemnants] No minable prototype found for entity '%s' in recipe '%s'", entity_name, recipe.name))
		return
	end

	if is_excepted(entity_proto) then return end

	if entity_proto.loot then
		log(string.format("[LootingRemnants] Skipping entity '%s' in recipe '%s' — already has loot %s", entity_name, recipe.name, serpent.block(entity_proto.loot)))
		return
	end

	local loot = build_loot(recipe)
	if loot then
		entity_proto.loot = loot
		log(string.format("[LootingRemnants] Assigned %d loot entries to '%s' in recipe '%s'", #loot, entity_name, recipe.name))
	else
		log(string.format("[LootingRemnants] No valid loot built for entity '%s' in recipe '%s'", entity_name, recipe.name))
	end
end

-----------------------------------
-- MAIN LOOP
-----------------------------------

local seen_types = {}

for _, recipe in pairs(data.raw.recipe) do

    -- Skip recycling recipes
    if string.sub(recipe.name, -10) == "-recycling" then
    	-- log(string.format("[LootingRemnants] Skipping recycling recipe '%s'", recipe.name))

    elseif is_excepted(recipe) then
    	log(string.format("[LootingRemnants] Skipping excepted recipe '%s'", recipe.name))

    else
    	process_recipe(recipe, seen_types)
    end
  end

-- Log all prototype types that were encountered
local type_list = {}
for t in pairs(seen_types) do table.insert(type_list, t) end
-- log("[LootingRemnants] Entity prototype types encountered: " .. serpent.line(type_list))