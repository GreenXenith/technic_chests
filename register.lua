local S = rawget(_G, "intllib") and intllib.Getter() or function(s) return s end

local pipeworks = rawget(_G, "pipeworks")
local fs_helpers = rawget(_G, "fs_helpers")

local allow_label = ""
local tube_entry = ""
local shift_edit_field = 0

if not minetest.get_modpath("pipeworks") then
	-- Pipeworks is not installed. Simulate using a dummy table...
	pipeworks = {}
	fs_helpers = {}
	local pipeworks_meta = {}
	setmetatable(pipeworks, pipeworks_meta)
	local dummy = function()
		end
	pipeworks_meta.__index = function(table, key)
			print("[technic_chests] WARNING: variable or method '"..key.."' not present in dummy pipeworks table - assuming it is a method...")
			pipeworks[key] = dummy
			return dummy
		end
	pipeworks.after_place = dummy
	pipeworks.after_dig = dummy
	fs_helpers.cycling_button = function() return "" end
else
	fs_helpers = pipeworks.fs_helpers
	allow_label = "label[0.9,0.36;Allow splitting incoming stacks from tubes]"
	shift_edit_field = 3
	tube_entry = "^pipeworks_tube_connection_metallic.png"
end

local chest_mark_colors = {
	{"black", S("Black")},
	{"blue", S("Blue")},
	{"brown", S("Brown")},
	{"cyan", S("Cyan")},
	{"dark_green", S("Dark Green")},
	{"dark_grey", S("Dark Grey")},
	{"green", S("Green")},
	{"grey", S("Grey")},
	{"magenta", S("Magenta")},
	{"orange", S("Orange")},
	{"pink", S("Pink")},
	{"red", S("Red")},
	{"violet", S("Violet")},
	{"white", S("White")},
	{"yellow", S("Yellow")},
}


local function colorid_to_postfix(id)
	return chest_mark_colors[id] and "_"..chest_mark_colors[id][1] or ""
end


local function get_color_buttons(coleft, lotop)
	local buttons_string = ""
	for y = 0, 3 do
		for x = 0, 3 do
			local file_name = "technic_colorbutton"..(y * 4 + x)..".png"
			buttons_string = buttons_string.."image_button["
				..(coleft + 0.1 + x * 0.7)..","..(lotop + 0.1 + y * 0.7)
				..";0.8,0.8;"..file_name..";color_button"
				..(y * 4 + x + 1)..";]"
		end
	end
	return buttons_string
end


local function check_color_buttons(pos, meta, chest_name, fields)
	for i = 1, 16 do
		if fields["color_button"..i] then
			local node = minetest.get_node(pos)
			node.name = chest_name..colorid_to_postfix(i)
			minetest.swap_node(pos, node)
			meta:set_string("color", i)
			return
		end
	end
end

local function set_formspec(pos, data, page)
	local meta = minetest.get_meta(pos)
	local node = minetest.get_node(pos)
	local formspec = data.base_formspec
	formspec = formspec..fs_helpers.cycling_button(
				meta,
				"image_button[0,0.35;1,0.6",
				"splitstacks",
				{
					pipeworks.button_off,
					pipeworks.button_on
				}
			)..allow_label

	if data.autosort then
		local status = meta:get_int("autosort")
		formspec = formspec.."button["..(data.hileft+2)..","..(data.height+1.1)..";3,0.8;autosort_to_"..(1-status)..";"..S("Auto-sort is %s"):format(status == 1 and S("On") or S("Off")).."]"
	end
	if data.infotext then
		local formspec_infotext = minetest.formspec_escape(meta:get_string("infotext"))
		if page == "main" then
			formspec = formspec.."image_button["..(shift_edit_field+data.hileft+2.1)..",0.1;0.8,0.8;"
					.."technic_pencil_icon.png;edit_infotext;]"
					.."label["..(shift_edit_field+data.hileft+3)..",0;"..formspec_infotext.."]"
		elseif page == "edit_infotext" then
			formspec = formspec.."image_button["..(shift_edit_field+data.hileft+2.1)..",0.1;0.8,0.8;"
					.."technic_checkmark_icon.png;save_infotext;]"
					.."field["..(shift_edit_field+data.hileft+3.3)..",0.2;4.8,1;"
					.."infotext_box;"..S("Edit chest description:")..";"
					..formspec_infotext.."]"
		end
	end
	if data.color then
		local colorID = meta:get_int("color")
		local colorName
		if chest_mark_colors[colorID] then
			colorName = chest_mark_colors[colorID][2]
		else
			colorName = S("None")
		end
		formspec = formspec.."label["..(data.coleft+0.2)..","..(data.lotop+3)..";"..S("Color Filter: %s"):format(colorName).."]"
	end
	if data.quickmove then
		local spos = pos.x .. "," .. pos.y .. "," .. pos.z
		formspec = formspec..
		"button["..(data.hileft+1)..","..(data.height+2.1)..";2,0.8;inv_tochest;To Chest]"..
		"button["..(data.hileft+1)..","..(data.height+4.1)..";2,0.8;inv_fromchest;To Inventory]"..
		"tooltip[inv_tochest;Move items from inventory to chest]"..
		"tooltip[inv_fromchest;Move items from chest to inventory]"..
--		"tooltip[quickmove;Item to move (empty for all)]"..
		"list[nodemeta:"..spos..";quickmove;"..(data.hileft+1.5)..","..(data.height+3)..";1,1]"..
		"liststring[nodemeta:"..spos..";quickmove]"
	end
	meta:set_string("formspec", formspec)
end

local function sort_inventory(inv)
	local inlist = inv:get_list("main")
	local typecnt = {}
	local typekeys = {}
	for _, st in ipairs(inlist) do
		if not st:is_empty() then
			local n = st:get_name()
			local w = st:get_wear()
			local m = st:get_metadata()
			local k = string.format("%s %05d %s", n, w, m)
			if not typecnt[k] then
				typecnt[k] = {st}
				table.insert(typekeys, k)
			else
				table.insert(typecnt[k], st)
			end
		end
	end
	table.sort(typekeys)
	inv:set_list("main", {})
	for _, k in ipairs(typekeys) do
		for _, item in ipairs(typecnt[k]) do
			inv:add_item("main", item)
		end
	end
end

local function is_chest(name)
	local chest_names = {
		"technic:gold_locked_chest",
		"technic:silver_locked_chest",
		"technic:mithril_locked_chest",
	}
	for i,n in ipairs(chest_names) do
		if name == n then
			return true
		end
	end
	return false
end

local function move_inv(frominv, toinv, filter)
	for i, v in ipairs(frominv:get_list("main") or {}) do
		if v:get_name() == filter or not filter then
			if toinv:room_for_item("main", v) then
				local leftover = toinv:add_item("main", v)

				frominv:remove_item("main", v)

				if leftover
				and not leftover:is_empty() then
					frominv:add_item("main", v)
				end
			end
		end
	end
end

local function get_receive_fields(name, data)
	local lname = name:lower()
	return function(pos, formname, fields, sender)
		local meta = minetest.get_meta(pos)
		local page = "main"
		local player_inv = sender:get_inventory()
		local inv = meta:get_inventory()
		if fields.sort or (data.autosort and fields.quit and meta:get_int("autosort") == 1) then
			sort_inventory(meta:get_inventory())
		end
		if fields.edit_infotext then
			page = "edit_infotext"
		end
		if fields.autosort_to_1 then meta:set_int("autosort", 1) end
		if fields.autosort_to_0 then meta:set_int("autosort", 0) end
		if fields.infotext_box then
			meta:set_string("infotext", fields.infotext_box)
		end
		if data.color then
			-- This sets the node
			local nn = "technic:"..lname..(data.locked and "_locked" or "").."_chest"
			check_color_buttons(pos, meta, nn, fields)
		end
		if fields["fs_helpers_cycling:0:splitstacks"]
		  or fields["fs_helpers_cycling:1:splitstacks"] then
			if not pipeworks.may_configure(pos, sender) then return end
			fs_helpers.on_receive_fields(pos, fields)
		end
		if fields.inv_tochest then
			minetest.chat_send_all("fields.inv_tochest")
			if meta:get_string("item") == "" then
				minetest.log("action", sender:get_player_name().." moves all inventory contents to chest at "..minetest.pos_to_string(pos))
				move_inv(player_inv, inv, nil)
			else
				minetest.log("action", sender:get_player_name().." moves all "..meta:get_string("item").." in inventory to chest at "..minetest.pos_to_string(pos))
				move_inv(player_inv, inv, meta:get_string("item"))
			end
		end
		if fields.inv_fromchest then
			minetest.chat_send_all("fields.inv_fromchest")
			if meta:get_string("item") == "" then
				minetest.log("action", sender:get_player_name().." moves all contents to inventory from chest at "..minetest.pos_to_string(pos))
				move_inv(inv, player_inv, nil)
			else
				minetest.log("action", sender:get_player_name().." moves all "..meta:get_string("item").." to inventory from chest at "..minetest.pos_to_string(pos))
				move_inv(inv, player_inv, meta:get_string("item"))
			end
		end
		if fields.quit then
			inv:set_list("quickmove", {})
			meta:set_string("item", "")
		end
		meta:get_inventory():set_size("main", data.width * data.height)
		set_formspec(pos, data, page)
	end
end

function technic.chests:definition(name, data)
	local lname = name:lower()
	name = S(name)
	local d = {}
	for k, v in pairs(data) do d[k] = v end
	data = d

	data.lowidth = 8
	data.ovwidth = math.max(data.lowidth, data.width)
	data.hileft = (data.ovwidth - data.width) / 2
	data.loleft = (data.ovwidth - data.lowidth) / 2
	if data.color then
		if data.lowidth + 3 <= data.ovwidth then
			data.coleft = data.ovwidth - 3
			if data.loleft + data.lowidth > data.coleft then
				data.loleft = data.coleft - data.lowidth
			end
		else
			data.loleft = 0
			data.coleft = data.lowidth
			data.ovwidth = data.lowidth + 3
		end
	end
	data.lotop = data.height + 2
	data.ovheight = data.lotop + 4

	local locked_after_place = nil
	local front = {"technic_"..lname.."_chest_front.png"}
	data.base_formspec = "size["..data.ovwidth..","..data.ovheight.."]"..
			"label[0,0;"..S("%s Chest"):format(name).."]"..
			"list[context;main;"..data.hileft..",1;"..data.width..","..data.height..";]"..
			"list[current_player;main;"..data.loleft..","..data.lotop..";8,4;]"..
			"background[-0.19,-0.25;"..(data.ovwidth+0.4)..","..(data.ovheight+0.75)..";technic_chest_form_bg.png]"..
			"background["..data.hileft..",1;"..data.width..","..data.height..";technic_"..lname.."_chest_inventory.png]"..
			"background["..data.loleft..","..data.lotop..";8,4;technic_main_inventory.png]"..
			"listring[]"

	if data.sort then
		data.base_formspec = data.base_formspec.."button["..data.hileft..","..(data.height+1.1)..";1,0.8;sort;"..S("Sort").."]"
	end
	if data.color then
		data.base_formspec = data.base_formspec..get_color_buttons(data.coleft, data.lotop)
	end

	if data.locked then
		locked_after_place = function(pos, placer)
			local meta = minetest.get_meta(pos)
			meta:set_string("owner", placer:get_player_name() or "")
			meta:set_string("infotext",
					S("%s Locked Chest (owned by %s)")
					:format(name, meta:get_string("owner")))
			pipeworks.after_place(pos)
		end
		table.insert(front, "technic_"..lname.."_chest_lock_overlay.png")
	else
		locked_after_place = pipeworks.after_place
	end

	local desc
	if data.locked then
		desc = S("%s Locked Chest"):format(name)
	else
		desc = S("%s Chest"):format(name)
	end

	local tentry = tube_entry
	if tube_entry ~= "" then
		if lname == "wooden" then
			tentry = "^pipeworks_tube_connection_wooden.png"
		elseif lname == "mithril" then
			tentry = "^pipeworks_tube_connection_stony.png"
		end
	end
	local def = {
		description = desc,
		tiles = {
			"technic_"..lname.."_chest_top.png"..tentry,
			"technic_"..lname.."_chest_top.png"..tentry,
			"technic_"..lname.."_chest_side.png"..tentry,
			"technic_"..lname.."_chest_side.png"..tentry,
			"technic_"..lname.."_chest_side.png"..tentry,
			table.concat(front, "^")
		},
		paramtype2 = "facedir",
		groups = self.groups,
		tube = self.tube,
		legacy_facedir_simple = true,
		sounds = default.node_sound_wood_defaults(),
		after_place_node = locked_after_place,
		after_dig_node = pipeworks.after_dig,

		on_construct = function(pos)
			local meta = minetest.get_meta(pos)
			meta:set_string("infotext", S("%s Chest"):format(name))
			set_formspec(pos, data, "main")
			local inv = meta:get_inventory()
			inv:set_size("main", data.width * data.height)
			inv:set_size("quickmove", 1*1)
		end,
		can_dig = self.can_dig,
		on_receive_fields = get_receive_fields(name, data),
		on_metadata_inventory_move = self.on_inv_move,
		on_metadata_inventory_put = self.on_inv_put,
		on_metadata_inventory_take = self.on_inv_take,
		on_blast = function(pos)
			local drops = {}
			default.get_inventory_drops(pos, "main", drops)
			drops[#drops+1] = "technic:"..name:lower()..(data.locked and "_locked" or "").."_chest"
			minetest.remove_node(pos)
			return drops
		end,
	}
	if data.locked then
		def.allow_metadata_inventory_move = self.inv_move
		def.allow_metadata_inventory_put = self.inv_put
		def.allow_metadata_inventory_take = self.inv_take
		def.on_blast = function() end
		def.can_dig = function(pos,player)
			local meta = minetest.get_meta(pos);
			local inv = meta:get_inventory()
			return inv:is_empty("main") and default.can_interact_with_node(player, pos)
		end
		def.on_skeleton_key_use = function(pos, player, newsecret)
			local meta = minetest.get_meta(pos)
			local owner = meta:get_string("owner")
			local name = player:get_player_name()

			-- verify placer is owner of lockable chest
			if owner ~= name then
				minetest.record_protection_violation(pos, name)
				minetest.chat_send_player(name, "You do not own this chest.")
				return nil
			end

			local secret = meta:get_string("key_lock_secret")
			if secret == "" then
				secret = newsecret
				meta:set_string("key_lock_secret", secret)
			end

			return secret, "a locked chest", owner
		end
	end
	return def
end

function technic.chests:register(name, data)
	local def = technic.chests:definition(name, data)

	local nn = "technic:"..name:lower()..(data.locked and "_locked" or "").."_chest"
	minetest.register_node(":"..nn, def)

	if data.color then
		local mk_front
		if string.find(def.tiles[6], "%^") then
			mk_front = function (overlay) return def.tiles[6]:gsub("%^", "^"..overlay.."^") end
		else
			mk_front = function (overlay) return def.tiles[6].."^"..overlay end
		end
		for i = 1, 15 do
			local postfix = colorid_to_postfix(i)
			local colordef = {}
			for k, v in pairs(def) do
				colordef[k] = v
			end
			colordef.drop = nn
			colordef.groups = self.groups_noinv
			colordef.tiles = { def.tiles[1], def.tiles[2], def.tiles[3], def.tiles[4], def.tiles[5], mk_front("technic_chest_overlay"..postfix..".png") }
			minetest.register_node(":"..nn..postfix, colordef)
		end
	end

end
