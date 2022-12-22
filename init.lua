local POWDER_ITEM
for i, name in pairs({"tnt:gunpowder", "mcl_mobitems:gunpowder", "default:coal_lump"}) do
	if minetest.registered_items[name] then
		POWDER_ITEM = name
		break
	end
end

if not POWDER_ITEM then
	minetest.register_craftitem("cannon73:gunpowder", {
		description = "Cannon Gunpowder",
		inventory_image = "cannon73_gunpowder.png",
	})
	POWDER_ITEM = "cannon73:gunpowder"
end

local IRON_INGOT_ITEM
for i, name in pairs({"default:steel_ingot", "mcl_core:iron_ingot"}) do
	if minetest.registered_items[name] then
		IRON_INGOT_ITEM = name
		break
	end
end

local boom = dofile(minetest.get_modpath("cannon73") .. "/tnt.lua")

local function cannon_ent_init(pos, placer)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	inv:set_size("cannon73", 2)

	local obj_ref = minetest.add_entity(pos, "cannon73:cannon")
	if not obj_ref then return end
	local luaentity = obj_ref:get_luaentity()
	luaentity._owner_name = placer and placer:get_player_name() or "singleplayer"

	local placer_yaw = placer and placer:get_look_horizontal() or 0
	if placer_yaw > 0 then
		luaentity.object:set_yaw(placer_yaw)
	else
		luaentity.object:set_yaw(placer_yaw + math.pi * 2)
	end
	luaentity._pitch = 500
	luaentity:refresh_pitch()

	return luaentity
end

local function cannon_fire(self, player_name)
	local pos = self.object:get_pos()
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local powder = inv:get_stack("cannon73", 1)
	if powder:get_name() ~= POWDER_ITEM then return end
	local projectile = inv:get_stack("cannon73", 2)
	if not minetest.is_creative_enabled(player_name) then
		inv:set_stack("cannon73", 1, nil)
		inv:set_stack("cannon73", 2, nil)
	end
	local power = powder:get_count() * 4

	local obj
	local item_def = minetest.registered_items[projectile:get_name()]
	if item_def and item_def._cannon_entity then
		obj = minetest.add_entity(pos, item_def._cannon_entity)
	else
		obj = minetest.add_entity(pos, "cannon73:item_projectile")
		if obj then
			obj:set_properties({ wield_item = projectile:get_name() })
			local luaentity = obj:get_luaentity()
			luaentity._item_stack = projectile
			luaentity._radius = 3
		end
	end
	if not obj then return end
	local luaentity = obj:get_luaentity()
	luaentity._owner_name = player_name
	if luaentity.name ~= "cannon73:item_projectile" then
		luaentity._radius = 3 + projectile:get_count()
	end
	obj:set_acceleration(vector.new(0, -10, 0))
	local beta = (1000 - self._pitch - 500) / 1000 * math.pi
	local alpha = self.object:get_yaw() + math.pi / 2

	local dir = vector.new(
			math.cos(beta) * math.cos(alpha),
			math.sin(beta),
			math.cos(beta) * math.sin(alpha))
	obj:set_velocity(vector.multiply(dir, power))

	minetest.sound_play("cannon73_shoot",
			{ pos = pos, gain = 1.5, max_hear_distance = 2 * 64 })

	minetest.add_particlespawner({
		amount = 16,
		time = 0.1,
		pos = vector.add(pos, vector.multiply(dir, 1)),
		minvel = vector.new(-5, -5, -5),
		maxvel = vector.new(5, 5, 5),
		minexptime = 6 * 5 * 0.03 / 2,
		maxexptime = 6 * 5 * 0.03,
		minsize = 8,
		maxsize = 16,
		texture = "cannon73_smoke.png",
		animation = {
			type = "sheet_2d",
			frames_w = 6,
			frames_h = 5,
			frame_length = 0.03,
		}
	})

	minetest.add_particlespawner({
		amount = 6,
		time = 2,
		pos = vector.add(pos, vector.multiply(dir, 1)),
		minvel = vector.new(-0.5, 1, -0.5),
		maxvel = vector.new(0.5, 2, 0.5),
		minexptime = 6 * 5 * 0.1 / 2,
		maxexptime = 6 * 5 * 0.1,
		minsize = 8,
		maxsize = 16,
		texture = "cannon73_smoke.png",
		animation = {
			type = "sheet_2d",
			frames_w = 6,
			frames_h = 5,
			frame_length = 0.1,
		}
	})
end

minetest.register_entity("cannon73:cannon", {
	initial_properties = {
		pointable = false,
		visual = "mesh",
		mesh = "cannon73_cannon.b3d",
		textures = { "cannon73_cannon.png" },
	},
	_check_node_timer = 0,
	on_blast = function(cannon, damage)
		return true, false, {}
	end,
	on_activate = function(self, staticdata, dtime)
		self.object:set_armor_groups({ immortal = 1 })
		local node = minetest.get_node(self.object:get_pos())
		if node.name ~= "cannon73:cannon" then
			self.object:remove()
			return
		end
		local static_data = minetest.deserialize(staticdata)
		if static_data then
			self._owner_name = static_data.owner_name or "singleplayer"
			self._pitch = static_data.pitch or 500
			self:refresh_pitch()
		end
	end,
	refresh_pitch = function(cannon)
		cannon.object:set_bone_position(
				"barrel",
				vector.new(0, 0, 0),
				vector.new((cannon._pitch / 1000) * 180 - 90, 0, 0))
	end,
	get_staticdata = function(cannon)
		return minetest.serialize({
			owner_name = cannon._owner_name,
			pitch = cannon._pitch,
		})
	end,
	on_step = function(self, dtime)
		self._check_node_timer = self._check_node_timer + dtime
		if self._check_node_timer > 4 then
			self._check_node_timer = 0
			local node_name = minetest.get_node(self.object:get_pos()).name
			if node_name ~= "cannon73:cannon" then
				self.object:remove()
			end
		end
	end,
})

local formspec_state = {}

local function cannon_on_rightclick(pos, node, clicker, itemstack, pointed_thing)
	local obj_refs = minetest.get_objects_inside_radius(pos, 0)
	local self
	for i, obj_ref in pairs(obj_refs) do
		local luaentity = obj_ref:get_luaentity()
		if luaentity then
			if luaentity.name == "cannon73:cannon" then
				self = luaentity
			end
		end
	end
	if not self then
		self = cannon_ent_init(pos, clicker)
	end
	if not self then return end
	formspec_state[clicker] = self
	local yaw = self.object:get_yaw()
	local pitch = self._pitch
	local pos = self.object:get_pos()
	local formspec =
		"formspec_version[3]" -- MT 5.1+
		.. "size[12,12]"
		.. "no_prepend[]"
		.. "bgcolor[#0000]"
		.. "listcolors[#fff1;#fff1;#0001]"
		.. "label[6,0.5;Yaw]"
		.. "scrollbar[1.25,1;10,0.75;horizontal;yaw;" .. 1000 - (yaw / (math.pi * 2) * 1000) .. "]"
		.. "vertlabel[0.2,4;Pitch]"
		.. "scrollbar[0.5,1.75;0.75,9;vertical;pitch;" .. pitch .. "]"
		.. "label[4.5,2.3;Projectile]"
		.. "list[nodemeta:" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ";cannon73;4.7,3;1,1;1]"
		.. "list[current_player;main;1.5,5;8,5;]"
		.. "button_exit[7.2,3;2,1;fire;Fire]"

	if minetest.is_creative_enabled(clicker:get_player_name()) then
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		local powder = inv:get_stack("cannon73", 1)
		local count = 0
		if powder:get_name() == POWDER_ITEM then
			count = powder:get_count()
		end
		formspec = formspec
			.. "label[2,2.3;Powder]"
			.. "field[2.2,3;1,0.5;powder_count;;" .. count .. "]"
	else
		local description = minetest.registered_items[POWDER_ITEM].description
		formspec = formspec
			.. "label[2,2.3;Powder]"
			.. "list[nodemeta:" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ";cannon73;2.2,3;1,1;0]"
			.. "tooltip[2.2,3;1,1;" .. description .. "]"
	end
	minetest.show_formspec(clicker:get_player_name(), "cannon73:aim", formspec)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if
		formname == "cannon73:aim"
		and formspec_state[player]
	then
		local cannon = formspec_state[player]
		if fields.yaw then
			local yaw = (1000 - minetest.explode_scrollbar_event(fields.yaw).value) / 1000 * math.pi * 2
			cannon.object:set_yaw(yaw)
		end
		if fields.pitch then
			cannon._pitch = minetest.explode_scrollbar_event(fields.pitch).value
			cannon:refresh_pitch()
		end
		if fields.powder_count then
			local pos = cannon.object:get_pos()
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			local count = tonumber(fields.powder_count) or 0
			inv:set_stack("cannon73", 1, POWDER_ITEM  .. " " .. count)
		end
		if fields.fire then
			cannon_fire(cannon, player:get_player_name())
		end
		if fields.quit then
			formspec_state[player] = nil
		end
		return true
	end
end)

minetest.register_on_leaveplayer(function(ObjectRef, timed_out)
	formspec_state[ObjectRef] = nil
end)

minetest.register_node("cannon73:cannon", {
	description = "Cannon",
	tiles = { "blank.png^[resize:16x16" },
	drawtype = "allfaces_optional",
	inventory_image = "cannon73_cannon_inv.png",
	wield_image = "cannon73_cannon_inv.png",
	use_texture_alpha = true,
	paramtype = "light",
	is_ground_content = false,
	groups = {
		choppy = 2,
		oddly_breakable_by_hand = 2,
		flammable = 2,
		handy = 1,
		axey = 1,
	},
	_mcl_hardness = 2,
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		cannon_ent_init(pos, placer)
		return
	end,
	on_rightclick = cannon_on_rightclick,
	on_destruct = function(pos)
		local obj_refs = minetest.get_objects_inside_radius(pos, 0)
		for i, obj_ref in pairs(obj_refs) do
			local luaentity = obj_ref:get_luaentity()
			if luaentity and luaentity.name == "cannon73:cannon" then
				obj_ref:remove()
			end
		end

		if minetest.is_creative_enabled("") then return end

		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()

		local items = {
			inv:get_stack("cannon73", 1),
			inv:get_stack("cannon73", 2),
		}
		for i, item in pairs(items) do
			local obj = minetest.add_item(pos, item)
			if obj then
				obj:get_luaentity().collect = true
				obj:set_acceleration(vector.new(0, -10, 0))
			end
		end
	end,
	mesecons = {effector = {
		action_on = function (pos, node)
			local obj_refs = minetest.get_objects_inside_radius(pos, 0)
			local cannon
			for i, obj_ref in pairs(obj_refs) do
				local luaentity = obj_ref:get_luaentity()
				if luaentity and luaentity.name == "cannon73:cannon" then
					cannon = luaentity
					break
				end
			end
			if not cannon then return end
			cannon_fire(cannon, cannon._owner_name)
		end
	}}
})

minetest.register_abm({
	label = "cannon73: Create cannon entity if missing",
	nodenames = { "cannon73:cannon" },
	interval = 4.0,
	chance = 1,
	action = function(pos, node, active_object_count, active_object_count_wider)
		local obj_refs = minetest.get_objects_inside_radius(pos, 0)
		local entity_found = false
		for i, obj_ref in pairs(obj_refs) do
			local luaentity = obj_ref:get_luaentity()
			if luaentity and luaentity.name == "cannon73:cannon" then
				entity_found = true
				break
			end
		end
		if not entity_found then
			cannon_ent_init(pos)
		end
	end,
})

local function place_node(pos, name, player, on_place)
	local itemstack = ItemStack(name)
	local x, y, z = pos.x, pos.y, pos.z
	local pointed_thing = {
		type = "node",
		intersection_point = vector.new(x + 0.5, y, z + 0.5),
		above = pos,
		under = vector.new(x, y - 1, z),
	}
	on_place(itemstack, player, pointed_thing)
end

local function item_projectile_unload_payload(player, pos, item_stack)
	local name = item_stack:get_name()
	local craftitem_def = minetest.registered_craftitems[name]
	local node_def = minetest.registered_nodes[name]
	local count = item_stack:get_count()
	local item_def = minetest.registered_items[name]
	local on_place
	if item_def then on_place = item_def.on_place end
	if craftitem_def and on_place then
		local itemstack = ItemStack(name)
		local x, y, z = pos.x, pos.y, pos.z
		local pointed_thing = {
			type = "node",
			intersection_point = vector.new(x + 0.5, y, z + 0.5),
			above = pos,
			under = vector.new(x, y - 1, z),
		}

		-- See if the item produces an entity
		local old_add_entity = minetest.add_entity
		local add_entity_was_called = false
		minetest.add_entity = function(...)
			add_entity_was_called = true
			return old_add_entity(...)
		end
		on_place(itemstack, player, pointed_thing)
		minetest.add_entity = old_add_entity
		if add_entity_was_called then
			for i = 2, count do
				on_place(itemstack, player, pointed_thing)
			end
			return
		end
	elseif node_def then
		if count == 1 and minetest.get_node(pos).name == "air" then
			place_node(pos, name, player, on_place)
			return
		end
		local starting_radius = math.min(math.ceil(math.pow(count, 1 / 3) / 2 - 0.5), 3)
		local pos_list
		for radius = starting_radius, 3 do
			local pos1 = vector.subtract(pos, radius)
			local pos2 = vector.add(pos, radius)
			local count_list
			pos_list, count_list = minetest.find_nodes_in_area(pos1, pos2, { "air" })
			if count_list.air >= count then
				break
			end
		end
		for i, pos in pairs(pos_list) do
			place_node(pos, name, player, on_place)
			if i >= count then break end
		end
		return
	end

	local obj = minetest.add_item(pos, item_stack)
	if obj then
		obj:get_luaentity().collect = true
		obj:set_acceleration(vector.new(0, -10, 0))
		obj:set_velocity(vector.new(
			math.random(-3, 3),
			math.random(0, 10),
			math.random(-3, 3)
		))
	end
end

local function projectile_on_step(self, dtime)
	local pos = self.object:get_pos()
	self._time_to_live = self._time_to_live - dtime
	local old_pos = self._old_pos
	self._old_pos = pos
	local ray = minetest.raycast(old_pos, pos)
	local explode_pos
	for pointed_thing in ray do
		if pointed_thing.type == "node" then
			local node = minetest.get_node(pointed_thing.under)
			local def = minetest.registered_nodes[node.name]
			if
				def and not def.walkable
				and self._time_to_live < 2 or node.name ~= "cannon73:cannon"
			then
				explode_pos = pointed_thing.under
				break
			end
		elseif pointed_thing.type == "object" then
			local obj_ref = pointed_thing.ref
			if obj_ref:is_player() then
				explode_pos = pointed_thing.intersection_point
				break
			end

			local luaentity = obj_ref:get_luaentity()
			if luaentity then
				local name = luaentity.name
				if
					name ~= self.name
					and name ~= "__builtin:item"
					and name ~= "cannon73:cannon"
				then
					explode_pos = pointed_thing.intersection_point
					break
				end
			end
		end
	end

	if
		self._time_to_live > 0
		and not explode_pos
	then return end

	explode_pos = explode_pos or pos

	if not explode_pos and self.name ~= "cannon73:shell" then
		self.object:remove()
		return
	end

	local explode_pos = vector.subtract(explode_pos,
			vector.normalize(self.object:get_velocity()))

	if self.name == "cannon73:item_projectile" then
		local player = minetest.get_player_by_name(self._owner_name)
		if player then
			item_projectile_unload_payload(player, explode_pos, self._item_stack)
		end
	end

	boom(explode_pos, {
		radius = self._radius,
		node_destruction = self.name == "cannon73:shell",
		disable_drops = minetest.is_creative_enabled(""),
		entity_damage = self.name ~= "cannon73:item_projectile",
	})
	self.object:remove()
end

local ball_ent_def = {
	initial_properties = {
		collisionbox = { -0.25, -0.25, -0.25, 0.25, 0.25, 0.25 },
		hp_max = 20,
		visual = "mesh",
		mesh = "cannon73_ball.obj",
		textures = { "cannon73_ball.png" },
	},
	_time_to_live = 10,
	static_save = false,
	on_activate = function(self, staticdata, dtime)
		self._old_pos = self.object:get_pos()
	end,
	on_step = projectile_on_step,
}
minetest.register_entity("cannon73:ball", ball_ent_def)
local shell_def = table.copy(ball_ent_def)
shell_def._time_to_live = 3
minetest.register_entity("cannon73:shell", shell_def)

minetest.register_craftitem("cannon73:ball", {
	description = "Cannon Ball",
	inventory_image = "cannon73_ball_inv.png",
	_cannon_entity = "cannon73:ball"
})
minetest.register_craftitem("cannon73:shell", {
	description = "Cannon Shell",
	inventory_image = "cannon73_shell_inv.png",
	_cannon_entity = "cannon73:shell"
})

minetest.register_entity("cannon73:item_projectile", {
	initial_properties = {
		collisionbox = { -0.25, -0.25, -0.25, 0.25, 0.25, 0.25 },
		hp_max = 20,
		pointable = false,
		visual = "wielditem",
		visual_size = { x = 0.2, y = 0.2 },
		automatic_rotate = 2,
	},
	_time_to_live = 10,
	static_save = false,
	on_activate = function(self, staticdata, dtime)
		self._old_pos = self.object:get_pos()
	end,
	on_step = projectile_on_step,
})

if IRON_INGOT_ITEM then
	minetest.register_craft({
		output = "cannon73:cannon",
		recipe = {
			{ IRON_INGOT_ITEM, IRON_INGOT_ITEM, IRON_INGOT_ITEM },
			{ IRON_INGOT_ITEM, IRON_INGOT_ITEM, IRON_INGOT_ITEM },
			{ "group:wood",    "group:wood",    "" },
		},
	})
	minetest.register_craft({
		output = "cannon73:cannon",
		recipe = {
			{ IRON_INGOT_ITEM, IRON_INGOT_ITEM, IRON_INGOT_ITEM },
			{ IRON_INGOT_ITEM, IRON_INGOT_ITEM, IRON_INGOT_ITEM },
			{ "",              "group:wood",    "group:wood" },
		},
	})
	minetest.register_craft({
		output = "cannon73:shell",
		recipe = {
			{ "",              IRON_INGOT_ITEM, "" },
			{ IRON_INGOT_ITEM, POWDER_ITEM,     IRON_INGOT_ITEM },
			{ "",              IRON_INGOT_ITEM, "" },
		},
	})
	minetest.register_craft({
		output = "cannon73:ball",
		recipe = {
			{ "",              IRON_INGOT_ITEM, "" },
			{ IRON_INGOT_ITEM, IRON_INGOT_ITEM, IRON_INGOT_ITEM },
			{ "",              IRON_INGOT_ITEM, "" },
		},
	})
end
