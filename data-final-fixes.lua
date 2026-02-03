local constants = require("lua/constants")


-- darkfrei 2020-12-03: I want to rewrite it, but now just update

-- LootingRemnants

local entity_loot = {}
local entity_types = {}


-- read settings
local settings_loot_proba = settings.startup[constants.MOD_NAME .. "-loot-proba"].value
local settings_loot_min = settings.startup[constants.MOD_NAME .. "-loot-min"].value
local settings_loot_max = settings.startup[constants.MOD_NAME .. "-loot-max"].value

if settings_loot_max < settings_loot_min then
	error(string.format("[%s.%s] loot max (%d) < loot min (%d)", constants.MOD_NAME, FILENAME, settings_loot_max, settings_loot_min))
end



function is_exception_mod (exception_mods) -- exception for mod, just list of names of mods
	--[[
	for example add the line
	data.raw.car.car.exception_mods = {"Deconstruction", "LootingRemnants"} 
	and this prototype will be ignored by this mods
	--]]
	
	if not exception_mods then return false end
	
	if type (exception_mods) == "table" then
		for i, exception in pairs (exception_mods) do
			if exception == "LootingRemnants" then
				return true
			end
		end
	end
	return false
end


function is_value_in_list (value, list)
	for i, v in pairs (list) do
		if v == value then return true end
	end
	return false
end

-- local entity_types = {"container", "furnace", "boiler", "generator", "transport-belt", "mining-drill", "inserter", "pipe", "offshore-pump", "electric-pole", "radar", "lamp", "pipe-to-ground", "assembling-machine", "lab", "wall", "splitter", "underground-belt", "loader", "ammo-turret", "player-port", "solar-panel", "train-stop", "rail-signal", "rail-chain-signal", "gate", "land-mine", "logistic-robot", "construction-robot", "logistic-container", "rocket-silo", "roboport", "accumulator", "beacon", "storage-tank", "pump", "arithmetic-combinator", "decider-combinator", "constant-combinator", "power-switch", "programmable-speaker", "electric-energy-interface", "reactor", "heat-pipe", "electric-turret", "fluid-turret", "artillery-turret"}

function get_entity_prototype (entity_name)
	for prototype_type_name, prototype_type in pairs (data.raw) do
		for prototype_name, prototype in pairs (prototype_type) do
			if prototype.minable and prototype_name == entity_name then
				if not is_value_in_list (prototype_type_name, entity_types) then
					table.insert (entity_types, prototype_type_name)
				end
				return prototype
			end
		end
	end
end


for i, recipe in pairs (data.raw.recipe) do

	if string.sub(recipe.name , -10) =="-recycling" then 
		log(string.format("[LootingRemnants-gbd] Ignoring recipe (not building loot for output) : '%s'", recipe.name))
		goto end_of_loop 
	end

	local exception_recipe = is_exception_mod (recipe.exception_mods)
	
	local handler = recipe.normal or recipe -- nice, no?
	if not exception_recipe and handler.result and handler.ingredients then 
		-- not for Factorio 1.1
		log('old recipe with result: ' .. recipe.name)	
		local item_name = handler.result
		local item_prototype = data.raw.item[item_name]
		if item_prototype and item_prototype.place_result then
			local entity_name = item_prototype.place_result
			local prototype = get_entity_prototype (entity_name)
			if prototype and not is_exception_mod (prototype.exception_mods) then
				if not prototype.loot then
					local loot = {}
					for j, ingredient in pairs (handler.ingredients) do
						local ing_type = ingredient.type or 'item'
						if ing_type == 'item' then
							local result_count = handler.result_count or 1
							local ing_item_name = ingredient.name or ingredient[1]
							local count_min = 0
							local count_max = ingredient.amount or ingredient[2]
					if count_max < 1 then count_max = 1 end -- added in 0.1.4
					local probability = 1
					if count_max == 1 then 
						count_min = 1
					-- probability = 0.5 / result_count
				else
					-- count_max = count_max / result_count
				end
				
				table.insert (loot, {item=ing_item_name, probability=probability, count_min=count_min, count_max = count_max})
			end
		end
		if #loot > 0 then
			prototype.loot = loot
		end
	end
			else -- no prototype
			log ('no prototype recipe: ["'..recipe.name..'"] item_type: ["'..item_prototype.type..'"] item_name: ["'..item_name..'"] entity_name: ["'..entity_name..'"]')
		end
	end
elseif not exception_recipe and handler.results and handler.ingredients then
	log('new recipe with results: ' .. recipe.name)	
	local results = handler.results
	if #results == 1 then
		local item_name = results[1].name
		local result_type = results[1].type
		local result_amount = results[1].amount or 1
		local item_prototype = data.raw.item[item_name]
		if result_type == "item" and item_prototype and item_prototype.place_result then
			
			local entity_name = item_prototype.place_result
			local prototype = get_entity_prototype (entity_name)
			if prototype and not is_exception_mod (prototype.exception_mods) then
				print ('item: '..item_name..' type: ["'..item_prototype.type..'"] entity: '..prototype.name..' ["'..prototype.type..'"]')
				if not prototype.loot then
					local loot = {}
					for j, ingredient in pairs (handler.ingredients) do
						local ing_type = ingredient.type or 'item'
						if ing_type == 'item' then
							local ing_item_name = ingredient.name or ingredient[1]
							local ing_actual_cost = (ingredient.amount or ingredient[2])/result_amount

							local count_min = settings_loot_min*ing_actual_cost
							local count_max = settings_loot_max*ing_actual_cost
						end
					end
					table.insert (loot, {item=ing_item_name, probability=settings_loot_proba, count_min=count_min, count_max = count_max})
				end
				if loot and #loot > 0 then
					prototype.loot = loot
				end
			else -- no prototype or is_exception_mod
				log ('no prototype recipe: ["'..recipe.name..'"] item_type: ["'..item_prototype.type..'"] item_name: ["'..item_name..'"] entity_name: ["'..entity_name..'"]')
			end
		end
	end
else
	log('exception for recipe: ' .. recipe.name)	
		-- exception for recipe or to result or no ingredients
	end
	::end_of_loop::
end

log ('entity_types: ' .. serpent.line(entity_types))