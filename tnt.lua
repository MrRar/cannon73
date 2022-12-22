-- Loss probabilities array (one in X will be lost)
local loss_prob = {}

loss_prob["default:cobble"] = 3
loss_prob["default:dirt"] = 4

local node_destruction = minetest.settings:get_bool("cannon73_node_destruction", true)

-- Fill a list with data for content IDs, after all nodes are registered
local cid_data = {}
minetest.register_on_mods_loaded(function()
	for name, def in pairs(minetest.registered_nodes) do
		cid_data[minetest.get_content_id(name)] = {
			name = name,
			drops = def.drops,
			flammable = def.groups.flammable,
			on_blast = def.on_blast,
		}
	end
end)

local function rand_pos(center, pos, radius)
	local def
	local reg_nodes = minetest.registered_nodes
	local i = 0
	repeat
		-- Give up and use the center if this takes too long
		if i > 4 then
			pos.x, pos.z = center.x, center.z
			break
		end
		pos.x = center.x + math.random(-radius, radius)
		pos.z = center.z + math.random(-radius, radius)
		def = reg_nodes[minetest.get_node(pos).name]
		i = i + 1
	until def and not def.walkable
end

local function eject_drops(drops, pos, radius)
	local drop_pos = vector.new(pos)
	for _, item in pairs(drops) do
		local count = math.min(item:get_count(), item:get_stack_max())
		while count > 0 do
			local take = math.max(1,math.min(radius * radius,
					count,
					item:get_stack_max()))
			rand_pos(pos, drop_pos, radius)
			local dropitem = ItemStack(item)
			dropitem:set_count(take)
			local obj = minetest.add_item(drop_pos, dropitem)
			if obj then
				obj:get_luaentity().collect = true
				obj:set_acceleration({x = 0, y = -10, z = 0})
				obj:set_velocity({x = math.random(-3, 3),
						y = math.random(0, 10),
						z = math.random(-3, 3)})
			end
			count = count - take
		end
	end
end

local function add_drop(drops, item)
	item = ItemStack(item)
	local name = item:get_name()
	if loss_prob[name] ~= nil and math.random(1, loss_prob[name]) == 1 then
		return
	end

	local drop = drops[name]
	if drop == nil then
		drops[name] = item
	else
		drop:set_count(drop:get_count() + item:get_count())
	end
end

local basic_flame_on_construct -- cached value
local function destroy(drops, npos, cid, c_air, c_fire,
		on_blast_queue, on_construct_queue,
		ignore_protection, ignore_on_blast, owner)
	if not ignore_protection and minetest.is_protected(npos, owner) then
		return cid
	end

	local def = cid_data[cid]

	if not def then
		return c_air
	elseif not ignore_on_blast and def.on_blast then
		on_blast_queue[#on_blast_queue + 1] = {
			pos = vector.new(npos),
			on_blast = def.on_blast
		}
		return cid
	elseif def.flammable then
		on_construct_queue[#on_construct_queue + 1] = {
			fn = basic_flame_on_construct,
			pos = vector.new(npos)
		}
		return c_fire
	else
		local node_drops = minetest.get_node_drops(def.name, "")
		for _, item in pairs(node_drops) do
			add_drop(drops, item)
		end
		return c_air
	end
end

local function calc_velocity(pos1, pos2, old_vel, power)
	-- Avoid errors caused by a vector of zero length
	if vector.equals(pos1, pos2) then
		return old_vel
	end

	local vel = vector.direction(pos1, pos2)
	vel = vector.normalize(vel)
	vel = vector.multiply(vel, power)

	-- Divide by distance
	local dist = vector.distance(pos1, pos2)
	dist = math.max(dist, 1)
	vel = vector.divide(vel, dist)

	-- Add old velocity
	vel = vector.add(vel, old_vel)

	-- randomize it a bit
	vel = vector.add(vel, {
		x = math.random() - 0.5,
		y = math.random() - 0.5,
		z = math.random() - 0.5,
	})

	-- Limit to terminal velocity
	dist = vector.length(vel)
	if dist > 250 then
		vel = vector.divide(vel, dist / 250)
	end
	return vel
end

local function entity_physics(pos, radius, drops)
	local objs = minetest.get_objects_inside_radius(pos, radius)
	for _, obj in pairs(objs) do
		local obj_pos = obj:get_pos()
		if not obj_pos then break end -- In MCL2 get_objects_inside_radius returns invalid ObjectRefs (?)
		local dist = math.max(1, vector.distance(pos, obj_pos))

		local damage = (4 / dist) * radius
		if obj:is_player() then
			local dir = vector.normalize(vector.subtract(obj_pos, pos))
			local moveoff = vector.multiply(dir, 2 / dist * radius)
			obj:add_velocity(moveoff)

			obj:set_hp(obj:get_hp() - damage)
		else
			local luaobj = obj:get_luaentity()

			-- object might have disappeared somehow
			if luaobj then
				local do_damage = true
				local do_knockback = true
				local entity_drops = {}
				local objdef = minetest.registered_entities[luaobj.name]

				if objdef and objdef.on_blast then
					do_damage, do_knockback, entity_drops = objdef.on_blast(luaobj, damage)
				end

				if do_knockback then
					local obj_vel = obj:get_velocity()
					obj:set_velocity(calc_velocity(pos, obj_pos,
							obj_vel, radius * 10))
				end
				if do_damage then
					if not obj:get_armor_groups().immortal then
						obj:punch(obj, 1.0, {
							full_punch_interval = 1.0,
							damage_groups = {fleshy = damage},
						}, nil)
					end
				end
				for _, item in pairs(entity_drops) do
					add_drop(drops, item)
				end
			end
		end
	end
end

local function add_effects(pos, radius, drops, node_destruction)
	if node_destruction then
		minetest.add_particle({
			pos = pos,
			velocity = vector.new(),
			acceleration = vector.new(),
			expirationtime = 0.03 * 16,
			size = radius * 10,
			collisiondetection = false,
			vertical = false,
			texture = "cannon73_boom.png",
			glow = 15,
			animation = {
				type = "sheet_2d",
				frames_w = 4,
				frames_h = 4,
				frame_length = 0.03,
			}
		})
	end--else
		minetest.add_particlespawner({
			amount = 64,
			time = 0.01,
			pos = pos,
			minvel = vector.new(-20, -20, -20),
			maxvel = vector.new(20, 20, 20),
			minacc = vector.new(),
			maxacc = vector.new(),
			minexptime = 9 * 0.03 * 1.5,
			maxexptime = 9 * 0.03,
			minsize = radius * 0.5,
			maxsize = radius * 2,
			texture = "cannon73_spark.png",
			glow = 15,
			animation = {
				type = "sheet_2d",
				frames_w = 9,
				frames_h = 1,
				frame_length = 0.03,
			}
		})
	--end
	minetest.add_particlespawner({
		amount = 64,
		time = 0.5,
		minpos = vector.subtract(pos, radius / 2),
		maxpos = vector.add(pos, radius / 2),
		minvel = vector.new(-10, -10, -10),
		maxvel = vector.new(10, 10, 10),
		minacc = vector.new(),
		maxacc = vector.new(),
		minexptime = 6 * 5 * 0.03 / 2,
		maxexptime = 6 * 5 * 0.03,
		minsize = radius * 3,
		maxsize = radius * 5,
		texture = "cannon73_smoke.png",
		animation = {
			type = "sheet_2d",
			frames_w = 6,
			frames_h = 5,
			frame_length = 0.03,
		}
	})

	-- We just dropped some items. Look at the items entities and pick
	-- one of them to use as texture
	local texture
	local node
	local most = 0
	for name, stack in pairs(drops) do
		local count = stack:get_count()
		if count > most then
			most = count
			local def = minetest.registered_nodes[name]
			if def then
				node = { name = name }
				if def.tiles and type(def.tiles[1]) == "string" then
					texture = def.tiles[1]
				end
			end
		end
	end

	if not texture then return end
	minetest.add_particlespawner({
		amount = 64,
		time = 0.1,
		minpos = vector.subtract(pos, radius / 2),
		maxpos = vector.add(pos, radius / 2),
		minvel = vector.new(-3, 0, -3),
		maxvel = vector.new(3, 5, 3),
		minacc = vector.new(0, -10, 0),
		maxacc = vector.new(0, -10, 0),
		minexptime = 0.8,
		maxexptime = 2.0,
		minsize = radius * 0.33,
		maxsize = radius,
		texture = texture,
		-- ^ only as fallback for clients without support for `node` parameter
		node = node,
		collisiondetection = true,
	})
end

local function tnt_explode(pos, radius, ignore_protection, ignore_on_blast, owner)
	pos = vector.round(pos)

	-- Perform the explosion
	local vm = VoxelManip()
	local pr = PseudoRandom(os.time())
	local p1 = vector.subtract(pos, radius)
	local p2 = vector.add(pos, radius)
	local minp, maxp = vm:read_from_map(p1, p2)
	local a = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
	local data = vm:get_data()

	local drops = {}
	local on_blast_queue = {}
	local on_construct_queue = {}
	basic_flame_on_construct = minetest.registered_nodes["fire:basic_flame"].on_construct

	local c_air = minetest.CONTENT_AIR
	local c_ignore = minetest.CONTENT_IGNORE
	local c_fire = minetest.get_content_id("fire:basic_flame")
	for z = -radius, radius do
	for y = -radius, radius do
	local vi = a:index(pos.x + (-radius), pos.y + y, pos.z + z)
	for x = -radius, radius do
		local r = vector.length(vector.new(x, y, z))
		if (radius * radius) / (r * r) >= (pr:next(80, 125) / 100) then
			local cid = data[vi]
			local p = {x = pos.x + x, y = pos.y + y, z = pos.z + z}
			if cid ~= c_air and cid ~= c_ignore then
				data[vi] = destroy(drops, p, cid, c_air, c_fire,
					on_blast_queue, on_construct_queue,
					ignore_protection, ignore_on_blast, owner)
			end
		end
		vi = vi + 1
	end
	end
	end

	vm:set_data(data)
	vm:write_to_map()
	vm:update_map()
	vm:update_liquids()

	-- call check_single_for_falling for everything within 1.5x blast radius
	for y = -radius * 1.5, radius * 1.5 do
	for z = -radius * 1.5, radius * 1.5 do
	for x = -radius * 1.5, radius * 1.5 do
		local rad = {x = x, y = y, z = z}
		local s = vector.add(pos, rad)
		local r = vector.length(rad)
		if r / radius < 1.4 then
			minetest.check_single_for_falling(s)
		end
	end
	end
	end

	for _, queued_data in pairs(on_blast_queue) do
		local dist = math.max(1, vector.distance(queued_data.pos, pos))
		local intensity = (radius * radius) / (dist * dist)
		local node_drops = queued_data.on_blast(queued_data.pos, intensity)
		if node_drops then
			for _, item in pairs(node_drops) do
				add_drop(drops, item)
			end
		end
	end

	for _, queued_data in pairs(on_construct_queue) do
		queued_data.fn(queued_data.pos)
	end

	return drops
end

local function boom(pos, def)
	def = def or {}
	def.radius = def.radius or 1
	def.damage_radius = def.damage_radius or def.radius * 2
	local meta = minetest.get_meta(pos)
	local owner = meta:get_string("owner")

	local boom_pos
	if def.node_destruction then
		boom_pos = pos
	else
		local pos1 = vector.subtract(pos, 1)
		local pos2 = vector.add(pos, 1)
		local pos_list = minetest.find_nodes_in_area(pos1, pos2, {"air"})
		boom_pos = pos_list[1]
	end

	if boom_pos then
		minetest.set_node(boom_pos, {name = "cannon73:boom"})
	end

	local sound = def.node_destruction and "cannon73_shell" or "cannon73_ball"
	minetest.sound_play(sound, {pos = pos, gain = 2.5,
			max_hear_distance = math.min(def.radius * 20, 128)}, true)

	local drops = {}
	if def.node_destruction and node_destruction then
		drops = tnt_explode(pos, def.radius, def.ignore_protection,
				def.ignore_on_blast, owner)
	end

	if def.entity_damage then
		-- Append entity drops
		entity_physics(pos, def.damage_radius, drops)
		if not def.disable_drops then
			eject_drops(drops, pos, def.radius)
		end
	end
	
	add_effects(pos, def.radius, drops, def.node_destruction)
end

minetest.register_node("cannon73:boom", {
	drawtype = "airlike",
	inventory_image = "cannon73_boom.png",
	wield_image = "cannon73_boom.png",
	light_source = minetest.LIGHT_MAX,
	walkable = false,
	drop = "",
	groups = {dig_immediate = 3, not_in_creative_inventory = 1},
	-- unaffected by explosions
	on_blast = function() end,
	on_construct = function(pos)
		minetest.get_node_timer(pos):start(0)
	end,
	on_timer = function(pos, elapsed)
		minetest.remove_node(pos)
	end
})

return boom
