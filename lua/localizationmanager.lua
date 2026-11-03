_G.AddBulletTrail = _G.AddBulletTrail or {}
AddBulletTrail.ModPath = ModPath
AddBulletTrail.SaveFile = SavePath .. "AddBulletTrail.txt"
AddBulletTrail.Main_Options_Menu = "AddBulletTrail_Main_Options_Menu"
AddBulletTrail.Settings = AddBulletTrail.Settings or {}

-- Global switch. The order here is the order of the choices in the menu.
-- The trail works for every weapon; there are no weapon type settings.
AddBulletTrail.Modes = { "off", "all" }

-- Hit outline (enemies you hit). The order here is the order in the menu.
AddBulletTrail.OutlineModes = { "off", "glow" }

-- Hit effect: ONE effect that plays on enemies you hit. The order here is the
-- order of the choices in the menu.
AddBulletTrail.EffectModes = { "off", "taser", "fire", "smoke", "explode", "flash" }

-- Hit box (head / body / arms / legs box around enemies you hit) on / off.
AddBulletTrail.HitBoxModes = { "off", "on" }

-- "Only Red Hit Box" on / off. On = only the part you hit is drawn (red), the
-- white boxes of the other parts are hidden. Off = all parts are drawn.
AddBulletTrail.HitBoxRedModes = { "off", "on" }
AddBulletTrail.OUTLINE_TIME_MIN, AddBulletTrail.OUTLINE_TIME_MAX = 0.1, 5

Hooks:Add("LocalizationManagerPostInit", "AddBulletTrail_loc", function(loc)
	local strings = {
		["AddBulletTrail_menu_title"] = "Bullet Trail",
		["AddBulletTrail_menu_desc"] = "Bullet trails, hit outline, hit effects and hit boxes for every weapon.",
		["AddBulletTrail_mode_title"] = "Bullet Trail",
		["AddBulletTrail_mode_desc"] = "Turns the bullet trail on or off. When on, every weapon leaves a trail.",
		["AddBulletTrail_mode_off"] = "Off",
				["AddBulletTrail_mode_all"] = "On",
		["AddBulletTrail_color_r_title"] = "Trail Color: Red",
		["AddBulletTrail_color_g_title"] = "Trail Color: Green",
		["AddBulletTrail_color_b_title"] = "Trail Color: Blue",
		["AddBulletTrail_color_desc"] = "0 - 255. All three at 255 is white.",
		["AddBulletTrail_hold_title"] = "Fade Delay (seconds)",
		["AddBulletTrail_hold_desc"] = "How long the trail stays fully visible before it starts to fade. 0 = starts fading right away.",
		["AddBulletTrail_fade_title"] = "Fade Duration (seconds)",
		["AddBulletTrail_fade_desc"] = "How long the fade-out takes once it starts. Higher = the trail disappears more slowly.",
		["AddBulletTrail_outline_title"] = "Hit Outline",
		["AddBulletTrail_outline_desc"] = "Gives enemies you hit the game's contour (outline glow), which is also visible through walls.",
		["AddBulletTrail_outline_off"] = "Off",
		["AddBulletTrail_outline_glow"] = "On",
		["AddBulletTrail_outline_time_title"] = "Outline Duration (seconds)",
		["AddBulletTrail_outline_time_desc"] = "How long an enemy stays outlined after you hit it. Turn it down for a quick flash on every hit.",
		["AddBulletTrail_effect_title"] = "Hit Effect",
		["AddBulletTrail_effect_desc"] = "Pick ONE effect that plays on enemies you hit. Only a visual effect: nobody is actually burned, tased or hurt, and nothing is animated.",
		["AddBulletTrail_effect_off"] = "Off",
		["AddBulletTrail_effect_taser"] = "Taser Sparks",
		["AddBulletTrail_effect_fire"] = "Fire",
		["AddBulletTrail_effect_smoke"] = "Smoke",
		["AddBulletTrail_effect_explode"] = "Explosion",
		["AddBulletTrail_effect_flash"] = "Flash",
		["AddBulletTrail_effect_time_title"] = "Effect Duration (seconds)",
		["AddBulletTrail_effect_time_desc"] = "How long taser sparks and fire stay on an enemy after you hit it, and how long each smoke wisp lasts. Explosion and Flash are a single burst per hit.",
		["AddBulletTrail_hitbox_title"] = "Hit Box",
		["AddBulletTrail_hitbox_desc"] = "Draws a box around enemies you hit, split into head, body, arms and legs. The part you hit is highlighted in red.",
		["AddBulletTrail_hitbox_off"] = "Off",
		["AddBulletTrail_hitbox_on"] = "On",
		["AddBulletTrail_hitbox_red_title"] = "Only Red Hit Box",
		["AddBulletTrail_hitbox_red_desc"] = "On: only the part you hit is drawn, as a red box. Off: every part is drawn and the part you hit is red.",
		["AddBulletTrail_hitbox_red_off"] = "Off",
		["AddBulletTrail_hitbox_red_on"] = "On",
		["AddBulletTrail_hitbox_time_title"] = "Hit Box Duration (seconds)",
		["AddBulletTrail_hitbox_time_desc"] = "How long the box stays on an enemy after you hit it."
	}
	loc:add_localized_strings(strings)
end )

local function clamp_channel(value)
	return math.max(0, math.min(255, math.floor(value + 0.5)))
end

-- Fade timing limits (seconds), shared by the menu sliders and the save file.
AddBulletTrail.HOLD_MIN, AddBulletTrail.HOLD_MAX = 0, 3
AddBulletTrail.FADE_MIN, AddBulletTrail.FADE_MAX = 0.05, 5

local function clamp_time(value, min, max)
	return math.max(min, math.min(max, math.floor(value * 20 + 0.5) / 20))
end

function AddBulletTrail:Reset()
	self.Settings = {
		mode = "all",
		color = { r = 255, g = 255, b = 255 },
		hold = 0.25,
		fade = 0.6,
		outline = "glow",
		outline_time = 0.5,
		effect = "off",
		effect_time = 1,
		hitbox = "on",
		hitbox_red = "off",
		hitbox_time = 1
	}
end

function AddBulletTrail:Load()
	self:Reset()
	local file = io.open(self.SaveFile, "r")
	if not file then
		return
	end
	local content = file:read("*all")
	file:close()
	local ok, data = pcall(json.decode, content)
	if not ok or type(data) ~= "table" then
		return
	end
	for key, value in pairs(data) do
		if key == "mode" then
			if value == "selected" then
				-- old save file: weapon types no longer exist, so it is simply "on"
				self.Settings.mode = "all"
			elseif self:GetModeIndex(value) then
				self.Settings.mode = value
			end
		elseif key == "color" and type(value) == "table" then
			for _, channel in ipairs({ "r", "g", "b" }) do
				local number = tonumber(value[channel])
				if number then
					self.Settings.color[channel] = clamp_channel(number)
				end
			end
		elseif key == "hold" then
			local number = tonumber(value)
			if number then
				self.Settings.hold = clamp_time(number, self.HOLD_MIN, self.HOLD_MAX)
			end
		elseif key == "fade" then
			local number = tonumber(value)
			if number then
				self.Settings.fade = clamp_time(number, self.FADE_MIN, self.FADE_MAX)
			end
		elseif key == "outline" then
			if self:GetOutlineIndex(value) then
				self.Settings.outline = value
			end
		elseif key == "effect" then
			if self:GetEffectIndex(value) then
				self.Settings.effect = value
			end
		elseif key == "taser" then
			-- old save file: the taser on / off switch became the Hit Effect choice
			if value == "on" and data.effect == nil then
				self.Settings.effect = "taser"
			end
		elseif key == "effect_time" then
			local number = tonumber(value)
			if number then
				self.Settings.effect_time = clamp_time(number, self.OUTLINE_TIME_MIN, self.OUTLINE_TIME_MAX)
			end
		elseif key == "hitbox" then
			if self:GetHitBoxIndex(value) then
				self.Settings.hitbox = value
			end
		elseif key == "hitbox_red" then
			if self:GetHitBoxRedIndex(value) then
				self.Settings.hitbox_red = value
			end
		elseif key == "hitbox_time" then
			local number = tonumber(value)
			if number then
				self.Settings.hitbox_time = clamp_time(number, self.OUTLINE_TIME_MIN, self.OUTLINE_TIME_MAX)
			end
		elseif key == "outline_time" then
			local number = tonumber(value)
			if number then
				self.Settings.outline_time = clamp_time(number, self.OUTLINE_TIME_MIN, self.OUTLINE_TIME_MAX)
			end
		end
	end
end

function AddBulletTrail:Save()
	local file = io.open(self.SaveFile, "w+")
	if file then
		file:write(json.encode(self.Settings))
		file:close()
	end
end

function AddBulletTrail:GetModeIndex(mode)
	for index, name in ipairs(self.Modes) do
		if name == (mode or self.Settings.mode) then
			return index
		end
	end
end

function AddBulletTrail:GetOutlineIndex(mode)
	for index, name in ipairs(self.OutlineModes) do
		if name == (mode or self.Settings.outline) then
			return index
		end
	end
end

function AddBulletTrail:GetHitBoxIndex(mode)
	for index, name in ipairs(self.HitBoxModes) do
		if name == (mode or self.Settings.hitbox) then
			return index
		end
	end
end

function AddBulletTrail:GetHitBoxRedIndex(mode)
	for index, name in ipairs(self.HitBoxRedModes) do
		if name == (mode or self.Settings.hitbox_red) then
			return index
		end
	end
end

function AddBulletTrail:GetEffectIndex(mode)
	for index, name in ipairs(self.EffectModes) do
		if name == (mode or self.Settings.effect) then
			return index
		end
	end
end

-- Every weapon is covered; the only switch is the global on / off.
function AddBulletTrail:IsWeaponEnabled(weapon_id)
	return self.Settings.mode ~= "off"
end

Hooks:Add("MenuManagerSetupCustomMenus", "AddBulletTrailOptionsSetup", function(...)
	MenuHelper:NewMenu(AddBulletTrail.Main_Options_Menu)
end )

Hooks:Add("MenuManagerPopulateCustomMenus", "AddBulletTrailOptionsPopulate", function(...)
	local main_menu = AddBulletTrail.Main_Options_Menu

	-- global switch
	MenuCallbackHandler.AddBulletTrail_mode_callback = function(self, item)
		local index = tonumber(item:value()) or AddBulletTrail:GetModeIndex("all")
		AddBulletTrail.Settings.mode = AddBulletTrail.Modes[index] or "all"
		AddBulletTrail:Save()
	end
	MenuHelper:AddMultipleChoice({
		id = "AddBulletTrail_mode",
		title = "AddBulletTrail_mode_title",
		desc = "AddBulletTrail_mode_desc",
		callback = "AddBulletTrail_mode_callback",
		items = { "AddBulletTrail_mode_off", "AddBulletTrail_mode_all" },
		value = AddBulletTrail:GetModeIndex() or 2,
		menu_id = main_menu,
		priority = 100
	})

	MenuHelper:AddDivider({
		id = "AddBulletTrail_divider_color",
		size = 16,
		menu_id = main_menu,
		priority = 99
	})

	-- trail color
	for index, channel in ipairs({ "r", "g", "b" }) do
		MenuCallbackHandler["AddBulletTrail_color_" .. channel .. "_callback"] = function(self, item)
			AddBulletTrail.Settings.color[channel] = clamp_channel(item:value())
			AddBulletTrail:Save()
		end
		MenuHelper:AddSlider({
			id = "AddBulletTrail_color_" .. channel,
			title = "AddBulletTrail_color_" .. channel .. "_title",
			desc = "AddBulletTrail_color_desc",
			callback = "AddBulletTrail_color_" .. channel .. "_callback",
			value = AddBulletTrail.Settings.color[channel],
			min = 0,
			max = 255,
			step = 1,
			show_value = true,
			menu_id = main_menu,
			priority = 98 - index
		})
	end

	MenuHelper:AddDivider({
		id = "AddBulletTrail_divider_time",
		size = 16,
		menu_id = main_menu,
		priority = 94
	})

	-- fade delay and fade duration
	MenuCallbackHandler.AddBulletTrail_hold_callback = function(self, item)
		AddBulletTrail.Settings.hold = clamp_time(item:value(), AddBulletTrail.HOLD_MIN, AddBulletTrail.HOLD_MAX)
		AddBulletTrail:Save()
	end
	MenuHelper:AddSlider({
		id = "AddBulletTrail_hold",
		title = "AddBulletTrail_hold_title",
		desc = "AddBulletTrail_hold_desc",
		callback = "AddBulletTrail_hold_callback",
		value = AddBulletTrail.Settings.hold,
		min = AddBulletTrail.HOLD_MIN,
		max = AddBulletTrail.HOLD_MAX,
		step = 0.05,
		show_value = true,
		menu_id = main_menu,
		priority = 93
	})

	MenuCallbackHandler.AddBulletTrail_fade_callback = function(self, item)
		AddBulletTrail.Settings.fade = clamp_time(item:value(), AddBulletTrail.FADE_MIN, AddBulletTrail.FADE_MAX)
		AddBulletTrail:Save()
	end
	MenuHelper:AddSlider({
		id = "AddBulletTrail_fade",
		title = "AddBulletTrail_fade_title",
		desc = "AddBulletTrail_fade_desc",
		callback = "AddBulletTrail_fade_callback",
		value = AddBulletTrail.Settings.fade,
		min = AddBulletTrail.FADE_MIN,
		max = AddBulletTrail.FADE_MAX,
		step = 0.05,
		show_value = true,
		menu_id = main_menu,
		priority = 92
	})

	MenuHelper:AddDivider({
		id = "AddBulletTrail_divider_outline",
		size = 16,
		menu_id = main_menu,
		priority = 91
	})

	-- outline for enemies you hit
	MenuCallbackHandler.AddBulletTrail_outline_callback = function(self, item)
		local index = tonumber(item:value()) or AddBulletTrail:GetOutlineIndex("glow")
		AddBulletTrail.Settings.outline = AddBulletTrail.OutlineModes[index] or "glow"
		AddBulletTrail:Save()
	end
	MenuHelper:AddMultipleChoice({
		id = "AddBulletTrail_outline",
		title = "AddBulletTrail_outline_title",
		desc = "AddBulletTrail_outline_desc",
		callback = "AddBulletTrail_outline_callback",
		items = { "AddBulletTrail_outline_off", "AddBulletTrail_outline_glow" },
		value = AddBulletTrail:GetOutlineIndex() or 2,
		menu_id = main_menu,
		priority = 90
	})

	MenuCallbackHandler.AddBulletTrail_outline_time_callback = function(self, item)
		AddBulletTrail.Settings.outline_time = clamp_time(item:value(), AddBulletTrail.OUTLINE_TIME_MIN, AddBulletTrail.OUTLINE_TIME_MAX)
		AddBulletTrail:Save()
	end
	MenuHelper:AddSlider({
		id = "AddBulletTrail_outline_time",
		title = "AddBulletTrail_outline_time_title",
		desc = "AddBulletTrail_outline_time_desc",
		callback = "AddBulletTrail_outline_time_callback",
		value = AddBulletTrail.Settings.outline_time,
		min = AddBulletTrail.OUTLINE_TIME_MIN,
		max = AddBulletTrail.OUTLINE_TIME_MAX,
		step = 0.05,
		show_value = true,
		menu_id = main_menu,
		priority = 89
	})

	-- hit effect: a single choice, so only one effect can be active at a time
	MenuCallbackHandler.AddBulletTrail_effect_callback = function(self, item)
		local index = tonumber(item:value()) or 1
		AddBulletTrail.Settings.effect = AddBulletTrail.EffectModes[index] or "off"
		AddBulletTrail:Save()
		-- switching effect clears whatever was still playing
		pcall(AddBulletTrail.ClearEffects, AddBulletTrail)
	end
	MenuHelper:AddMultipleChoice({
		id = "AddBulletTrail_effect",
		title = "AddBulletTrail_effect_title",
		desc = "AddBulletTrail_effect_desc",
		callback = "AddBulletTrail_effect_callback",
		items = {
			"AddBulletTrail_effect_off",
			"AddBulletTrail_effect_taser",
			"AddBulletTrail_effect_fire",
			"AddBulletTrail_effect_smoke",
			"AddBulletTrail_effect_explode",
			"AddBulletTrail_effect_flash"
		},
		value = AddBulletTrail:GetEffectIndex() or 1,
		menu_id = main_menu,
		priority = 88
	})

	MenuCallbackHandler.AddBulletTrail_effect_time_callback = function(self, item)
		AddBulletTrail.Settings.effect_time = clamp_time(item:value(), AddBulletTrail.OUTLINE_TIME_MIN, AddBulletTrail.OUTLINE_TIME_MAX)
		AddBulletTrail:Save()
	end
	MenuHelper:AddSlider({
		id = "AddBulletTrail_effect_time",
		title = "AddBulletTrail_effect_time_title",
		desc = "AddBulletTrail_effect_time_desc",
		callback = "AddBulletTrail_effect_time_callback",
		value = AddBulletTrail.Settings.effect_time,
		min = AddBulletTrail.OUTLINE_TIME_MIN,
		max = AddBulletTrail.OUTLINE_TIME_MAX,
		step = 0.05,
		show_value = true,
		menu_id = main_menu,
		priority = 84
	})

	MenuCallbackHandler.AddBulletTrail_hitbox_callback = function(self, item)
		local index = tonumber(item:value()) or AddBulletTrail:GetHitBoxIndex("on")
		AddBulletTrail.Settings.hitbox = AddBulletTrail.HitBoxModes[index] or "on"
		AddBulletTrail:Save()
	end
	MenuHelper:AddMultipleChoice({
		id = "AddBulletTrail_hitbox",
		title = "AddBulletTrail_hitbox_title",
		desc = "AddBulletTrail_hitbox_desc",
		callback = "AddBulletTrail_hitbox_callback",
		items = { "AddBulletTrail_hitbox_off", "AddBulletTrail_hitbox_on" },
		value = AddBulletTrail:GetHitBoxIndex() or 2,
		menu_id = main_menu,
		priority = 87
	})

	MenuCallbackHandler.AddBulletTrail_hitbox_red_callback = function(self, item)
		local index = tonumber(item:value()) or AddBulletTrail:GetHitBoxRedIndex("off")
		AddBulletTrail.Settings.hitbox_red = AddBulletTrail.HitBoxRedModes[index] or "off"
		AddBulletTrail:Save()
	end
	MenuHelper:AddMultipleChoice({
		id = "AddBulletTrail_hitbox_red",
		title = "AddBulletTrail_hitbox_red_title",
		desc = "AddBulletTrail_hitbox_red_desc",
		callback = "AddBulletTrail_hitbox_red_callback",
		items = { "AddBulletTrail_hitbox_red_off", "AddBulletTrail_hitbox_red_on" },
		value = AddBulletTrail:GetHitBoxRedIndex() or 1,
		menu_id = main_menu,
		priority = 86
	})

	MenuCallbackHandler.AddBulletTrail_hitbox_time_callback = function(self, item)
		AddBulletTrail.Settings.hitbox_time = clamp_time(item:value(), AddBulletTrail.OUTLINE_TIME_MIN, AddBulletTrail.OUTLINE_TIME_MAX)
		AddBulletTrail:Save()
	end
	MenuHelper:AddSlider({
		id = "AddBulletTrail_hitbox_time",
		title = "AddBulletTrail_hitbox_time_title",
		desc = "AddBulletTrail_hitbox_time_desc",
		callback = "AddBulletTrail_hitbox_time_callback",
		value = AddBulletTrail.Settings.hitbox_time,
		min = AddBulletTrail.OUTLINE_TIME_MIN,
		max = AddBulletTrail.OUTLINE_TIME_MAX,
		step = 0.05,
		show_value = true,
		menu_id = main_menu,
		priority = 85
	})
end )

Hooks:Add("MenuManagerBuildCustomMenus", "AddBulletTrailOptionsBuild", function(menu_manager, nodes)
	local main_menu = AddBulletTrail.Main_Options_Menu
	nodes[main_menu] = MenuHelper:BuildMenu(main_menu)
	MenuHelper:AddMenuItem(nodes["blt_options"], main_menu, "AddBulletTrail_menu_title", "AddBulletTrail_menu_desc")

end )

AddBulletTrail:Load()
