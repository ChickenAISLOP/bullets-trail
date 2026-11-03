_G.AddBulletTrail = _G.AddBulletTrail or {}
AddBulletTrail.Outlines = AddBulletTrail.Outlines or {}

-- Hit effects: ONE effect (chosen in the menu) plays on an enemy you hit.
-- Only particles are shown. The enemy is not tased, burned, stunned, slowed,
-- hurt or hidden, and nothing is animated.
--   taser   : the game's electric shock sparks  (stay on the enemy)
--   fire    : flames on the enemy               (stay on the enemy)
--   smoke   : smoke coming off the enemy        (stay on the enemy)
--   explode : an explosion at the hit spot      (one burst per hit)
--   flash   : a bright flash at the hit spot    (one burst per hit)
-- The particle files are looked up by name. Several names are tried in order
-- and the first one that exists in your game is used, so if one effect looks
-- wrong or does nothing, edit its `candidates` list below.
AddBulletTrail.Effects = AddBulletTrail.Effects or {}
AddBulletTrail.BurstTimes = AddBulletTrail.BurstTimes or {}
AddBulletTrail.BURST_COOLDOWN = 0.2 -- seconds between bursts on the same enemy

-- Also draw the Flash and the Smoke as simple colored shapes. This works even
-- when the game has no particle file under the names below, so these two can
-- never be invisible. Set to false to use only the game's particle files.
AddBulletTrail.DRAWN_FX = true
AddBulletTrail.DrawFx = AddBulletTrail.DrawFx or {}

-- kind "attach": plays on the enemy's bones until the effect time is over.
--   Every bone listed that exists gets its own copy (more bones = bigger, more
--   visible effect). all = true plays EVERY file found in `candidates`
--   together; otherwise only the first one found is used.
-- kind "burst" : one burst at the hit spot per hit.
AddBulletTrail.EFFECT_DEFS = {
	taser = {
		kind = "attach",
		restart = true, -- play again on every hit (after the short pause)
		all = true,
		bones = { "Spine2", "Spine1", "Hips", "Head", "LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg" },
		candidates = {
			"effects/payday2/particles/character/taser_hit",
			"effects/payday2/particles/character/taser_stop"
		}
	},
	fire = {
		kind = "attach",
		bones = { "Hips", "Spine1", "Spine2", "Head", "LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg" },
		candidates = {
			"effects/payday2/particles/explosions/molotov_grenade_enemy_on_fire",
			"effects/payday2/particles/explosions/molotov_grenade",
			"effects/payday2/particles/weapons/flamethrower/flamethrower_fire"
		}
	},
	smoke = {
		-- black cigarette-like smoke, a new wisp on every hit. Particle files
		-- cannot be colored, so this one is always drawn (see AddDrawFx).
		kind = "burst",
		candidates = {}
	},
	explode = {
		kind = "burst",
		candidates = {
			"effects/payday2/particles/explosions/grenade_explosion",
			"effects/particles/explosions/explosion_grenade",
			"effects/payday2/particles/explosions/explosion_grenade",
			"effects/payday2/particles/explosions/c4_explosion"
		}
	},
	flash = {
		kind = "burst",
		candidates = {
			"effects/payday2/particles/explosions/flashbang",
			"effects/payday2/particles/explosions/flashbang_explosion",
			"effects/particles/explosions/flashbang",
			"effects/particles/explosions/explosion_flashbang",
			"effects/payday2/particles/explosions/stun_grenade"
		}
	}
}

-- Called after the local player lands a hit on an enemy.
--  * "Hit Outline" on: the enemy gets the game's contour (outline glow,
--    visible through walls) for the outline duration.
--  * "Hit Effect" set: that one effect plays on the enemy.
-- Entries are expired by AddBulletTrail:UpdateOutlines() in
-- gamesetup.lua.
function AddBulletTrail:OnEnemyHit(damage_ext, attack_data)
	local settings = self.Settings
	if not settings or self.OUTLINE_FAILED then
		return
	end
	local glow_on = settings.outline == "glow"
	local hitbox_on = settings.hitbox == "on" and not self.HITBOX_FAILED
	local effect_on = settings.effect ~= "off" and self.EFFECT_DEFS[settings.effect] and not self.EFFECT_FAILED
	if not glow_on and not hitbox_on and not effect_on then
		return
	end
	if not attack_data or not managers or not managers.player then
		return
	end

	local player_unit = managers.player:player_unit()
	if not player_unit or attack_data.attacker_unit ~= player_unit then
		return
	end

	local unit = damage_ext._unit
	if not alive(unit) then
		return
	end
	local dead = damage_ext._dead and true or false

	-- enemies only, not civilians
	local ok, is_enemy = pcall(function()
		return unit:in_slot(managers.slot:get_mask("enemies"))
	end)
	if ok and is_enemy == false then
		return
	end

	if effect_on then
		local fx_ok, fx_err = pcall(self.AddEffect, self, damage_ext, unit, attack_data, dead)
		if not fx_ok then
			self.EFFECT_FAILED = true
			self:ClearEffects()
			log("[AddBulletTrail] hit effect failed and was turned off: " .. tostring(fx_err))
		end
	end

	-- the box and the outline are only for enemies that are still alive
	if dead then
		return
	end

	if hitbox_on then
		local box_ok, box_err = pcall(self.AddHitBox, self, damage_ext, unit, attack_data)
		if not box_ok then
			self.HITBOX_FAILED = true
			self.HitBoxes = {}
			log("[AddBulletTrail] hit box failed and was turned off: " .. tostring(box_err))
		end
	end

	if not glow_on then
		return
	end

	local duration = tonumber(settings.outline_time) or 0.5
	local key = unit:key()
	local entry = self.Outlines[key]

	if entry then
		-- hitting the enemy again just gives the outline more time
		entry.age = 0
		entry.time = duration
		if entry.glow_owned then
			self:AddGlow(unit)
		end
		return
	end

	local marked_ok, already_marked = pcall(function()
		return unit:contour():has_id("mark_enemy")
	end)
	already_marked = marked_ok and already_marked
	-- nothing to do for the plain outline if the enemy is already marked
	if already_marked then
		return
	end

	entry = {
		unit = unit,
		age = 0,
		time = duration,
		-- never touch the contour of an enemy that is already marked in the vanilla way
		glow_owned = glow_on and not already_marked and self:AddGlow(unit) or false
	}
	self.Outlines[key] = entry
end

-- Finds the particle files of an effect: the first candidate that exists in
-- the game's database (every one that exists when def.all is set). Remembered
-- after the first lookup. The files that were chosen are written to the BLT log.
function AddBulletTrail:ResolveEffect(mode)
	local def = self.EFFECT_DEFS[mode]
	if not def or #def.candidates == 0 then
		return {}
	end
	if def.resolved_list then
		return def.resolved_list
	end

	local names = {}
	if mode == "taser" and tweak_data and tweak_data.common_effects and tweak_data.common_effects.taser_hit then
		names[1] = tweak_data.common_effects.taser_hit
	end
	for _, name in ipairs(def.candidates) do
		names[#names + 1] = name
	end

	local found, seen = {}, {}
	for _, name in ipairs(names) do
		local ids = type(name) == "string" and Idstring(name) or name
		local ok, exists = pcall(function()
			return DB:has("effect", ids)
		end)
		local id_key = tostring(ids)
		if not ok then
			-- the lookup itself failed: trust the first name only
			found[#found + 1] = ids
			log("[AddBulletTrail] effect '" .. tostring(mode) .. "' uses (unchecked): " .. tostring(name))
			break
		elseif exists and not seen[id_key] then
			seen[id_key] = true
			found[#found + 1] = ids
			log("[AddBulletTrail] effect '" .. tostring(mode) .. "' uses: " .. tostring(name))
			if not def.all then
				break
			end
		end
	end

	if #found == 0 then
		log("[AddBulletTrail] no particle file found for effect '" .. tostring(mode) .. "'")
	end
	def.resolved_list = found
	return found
end

-- Drawn shapes (flash burst, smoke puffs): see DRAWN_FX at the top.
function AddBulletTrail:AddDrawFx(kind, position, life)
	if not Draw or self.DRAWFX_FAILED then
		return
	end
	local list = self.DrawFx
	while #list >= 40 do
		table.remove(list, 1)
	end
	list[#list + 1] = {
		kind = kind,
		pos = Vector3(position.x, position.y, position.z),
		age = 0,
		life = life or 0.3
	}
end

function AddBulletTrail:UpdateDrawFx(dt)
	local list = self.DrawFx
	if #list == 0 or self.DRAWFX_FAILED then
		return
	end
	local ok, err = pcall(function()
		for i = #list, 1, -1 do
			local fx = list[i]
			fx.age = fx.age + dt
			local progress = fx.age / fx.life
			if progress >= 1 then
				table.remove(list, i)
			else
				if fx.kind == "zap" then
					local fade = 1 - progress
					Draw:brush(Color(fade, 1, 1, 1)):sphere(fx.pos, 3 + progress * 8)
					Draw:brush(Color(fade * 0.6, 0.35, 0.7, 1)):sphere(fx.pos, 6 + progress * 20)
				elseif fx.kind == "smoke" then
					-- thin black wisps rising and swaying, one after the other
					for n = 0, 4 do
						local p = progress - n * 0.08
						if p > 0 then
							local sway = fx.age * 3 + n * 2.1
							local pos = fx.pos + Vector3(math.sin(sway) * 5 * p, math.cos(sway) * 5 * p, p * 55)
							Draw:brush(Color(0.55 * (1 - p), 0, 0, 0)):sphere(pos, 2.5 + p * 7)
						end
					end
				else
					local fade = (1 - progress) * (1 - progress)
					Draw:brush(Color(fade, 1, 1, 1)):sphere(fx.pos, 8 + progress * 30)
					Draw:brush(Color(fade * 0.4, 1, 0.95, 0.7)):sphere(fx.pos, 18 + progress * 70)
				end
			end
		end
	end)
	if not ok then
		self.DRAWFX_FAILED = true
		self.DrawFx = {}
		log("[AddBulletTrail] drawn flash / smoke failed and was turned off: " .. tostring(err))
	end
end

local idstr_spine1 = Idstring("Spine1")
local idstr_hips = Idstring("Hips")

-- Grey puffs rising from the enemy's torso while smoke is active.
function AddBulletTrail:DrawSmoke(entry)
	if not Draw or self.DRAWFX_FAILED or not alive(entry.unit) then
		return
	end
	local ok, err = pcall(function()
		local object = entry.unit:get_object(idstr_spine1) or entry.unit:get_object(idstr_hips)
		if not object then
			return
		end
		local base = object:position()
		for i = 1, 6 do
			local phase = ((entry.clock or 0) * 0.7 + i / 6) % 1
			local angle = i * 2.4
			local pos = base + Vector3(math.sin(angle) * 10, math.cos(angle) * 10, 15 + phase * 70)
			Draw:brush(Color((1 - phase) * 0.35, 0.55, 0.55, 0.55)):sphere(pos, 8 + phase * 18)
		end
	end)
	if not ok then
		self.DRAWFX_FAILED = true
		self.DrawFx = {}
		log("[AddBulletTrail] drawn flash / smoke failed and was turned off: " .. tostring(err))
	end
end

-- Bright electric arcs jumping between the enemy's bones while the taser is
-- active. Flickers every frame. Make the numbers bigger for a brighter taser.
AddBulletTrail.TASER_ARCS = 5 -- arcs per frame
function AddBulletTrail:DrawTaser(entry)
	if not Draw or self.DRAWFX_FAILED or not alive(entry.unit) then
		return
	end
	local objects = entry.objects
	if not objects or #objects < 2 then
		return
	end
	local ok, err = pcall(function()
		local core = Draw:brush(Color(1, 0.9, 1, 1))
		local glow = Draw:brush(Color(0.45, 0.3, 0.65, 1))
		local spot = Draw:brush(Color(0.9, 1, 1, 1))
		local count = #objects
		for _ = 1, self.TASER_ARCS do
			if math.random() < 0.75 then
				local a = objects[math.random(count)]:position()
				local b = objects[math.random(count)]:position()
				local last = a
				for step = 1, 4 do
					local point = b
					if step < 4 then
						local t = step / 4
						point = a + (b - a) * t + Vector3(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
					end
					core:cylinder(last, point, 0.5)
					glow:cylinder(last, point, 1.6)
					last = point
				end
			end
		end
		spot:sphere(objects[math.random(count)]:position(), 3)
	end)
	if not ok then
		self.DRAWFX_FAILED = true
		self.DrawFx = {}
		log("[AddBulletTrail] drawn taser failed and was turned off: " .. tostring(err))
	end
end

-- Plays the chosen effect on the enemy (this client only).
function AddBulletTrail:AddEffect(damage_ext, unit, attack_data, dead)
	local mode = self.Settings.effect
	local def = self.EFFECT_DEFS[mode]
	if not def then
		return
	end

	local effects = self:ResolveEffect(mode)
	local drawn = Draw and not self.DRAWFX_FAILED
		and (mode == "smoke" or mode == "taser" or (self.DRAWN_FX and mode == "flash")) and true or false
	if #effects == 0 and not drawn then
		return
	end

	local key = unit:key()
	local now = TimerManager and TimerManager:game():time() or 0

	if def.kind == "burst" then
		-- one explosion / flash per hit, with a short pause so full-auto does not spam
		local last = self.BurstTimes[key]
		if last and now - last < self.BURST_COOLDOWN then
			return
		end
		self.BurstTimes[key] = now

		local position = attack_data.col_ray and attack_data.col_ray.position
		if not position then
			local spine = unit:get_object(Idstring("Spine1"))
			position = spine and spine:position() or unit:position()
		end
		for _, effect in ipairs(effects) do
			World:effect_manager():spawn({
				effect = effect,
				position = position,
				normal = Vector3(0, 0, 1)
			})
		end
		if drawn then
			if mode == "smoke" then
				self:AddDrawFx("smoke", position, math.max(0.6, tonumber(self.Settings.effect_time) or 1))
			else
				self:AddDrawFx("flash", position)
			end
		end
		return
	end

	-- fire / smoke / taser stay on the enemy (also after it died), one at a time
	local entry = self.Effects[key]
	if entry and entry.mode == mode then
		entry.age = 0 -- already playing, keep it going
		-- the taser plays again on every hit; the pause stops full-auto from spamming
		if not def.restart or now - (entry.spawned or 0) < self.BURST_COOLDOWN then
			return
		end
	end
	if entry then
		self:KillEffect(key, entry) -- replace it with a fresh one
	end

	-- bright flash at the hit spot for the taser
	if drawn and mode == "taser" then
		local hit = attack_data.col_ray and attack_data.col_ray.position
		if hit then
			self:AddDrawFx("zap", hit, 0.15)
		end
	end

	-- one copy on every bone of the list that exists
	local ids = {}
	local objects = {}
	for _, name in ipairs(def.bones) do
		local parent = unit:get_object(Idstring(name))
		if parent then
			objects[#objects + 1] = parent
			for _, effect in ipairs(effects) do
				ids[#ids + 1] = World:effect_manager():spawn({ effect = effect, parent = parent })
			end
		end
	end
	if #ids == 0 and not drawn then
		return
	end
	self.Effects[key] = { unit = unit, ids = ids, mode = mode, age = 0, clock = 0, drawn = drawn, objects = objects, spawned = now }
end

function AddBulletTrail:KillEffect(key, entry)
	self.Effects[key] = nil
	for _, id in ipairs(entry.ids or {}) do
		pcall(function()
			World:effect_manager():fade_kill(id)
		end)
	end
end

function AddBulletTrail:ClearEffects()
	for key, entry in pairs(self.Effects) do
		self:KillEffect(key, entry)
	end
	self.DrawFx = {}
end

-- Ends fire / smoke / sparks when their time is up or the enemy is gone (removed
-- from the world). A dead enemy keeps its effect until the time is up.
function AddBulletTrail:UpdateEffects(dt)
	local now = TimerManager and TimerManager:game():time() or 0
	for key, last in pairs(self.BurstTimes) do
		if now - last > 5 then
			self.BurstTimes[key] = nil
		end
	end

	self:UpdateDrawFx(dt)

	if next(self.Effects) == nil then
		return
	end
	local duration = tonumber(self.Settings.effect_time) or 1
	for key, entry in pairs(self.Effects) do
		entry.age = entry.age + dt
		entry.clock = (entry.clock or 0) + dt
		local unit = entry.unit
		local finished = not alive(unit) or entry.age >= duration
		if finished then
			self:KillEffect(key, entry)
		elseif entry.drawn and entry.mode == "taser" then
			self:DrawTaser(entry)
		end
	end
end

-- Turns on the game's own enemy outline for this client only (not synced).
function AddBulletTrail:AddGlow(unit)
	local ok, added = pcall(function()
		local contour = unit:contour()
		if not contour then
			return false
		end
		-- the 4th argument asks for white; older versions ignore it and use
		-- the default marked-enemy color
		local color_ok = pcall(contour.add, contour, "mark_enemy", false, 1, Vector3(1, 1, 1))
		if not color_ok then
			contour:add("mark_enemy", false, 1)
		end
		return true
	end)
	return ok and added or false
end

function AddBulletTrail:RemoveOutline(key, entry)
	self.Outlines[key] = nil
	if entry.glow_owned and alive(entry.unit) then
		pcall(function()
			entry.unit:contour():remove("mark_enemy", false)
		end)
	end
end

-- Hit box: a box around the enemy in the 3D world, split into head, body,
-- arms and legs. The part you hit is highlighted in red. It is drawn by
-- AddBulletTrail:UpdateHitBoxes() in gamesetup.lua.
AddBulletTrail.HitBoxes = AddBulletTrail.HitBoxes or {}

-- Hit box parts. Every part gets its OWN tight box that is turned to follow
-- its bones. Arms and legs are split into an upper and a lower box, so a bent
-- arm or leg (crouching, aiming, dashing, any animation) is hugged by two
-- boxes instead of one big slab, and the head box sits on the head only.
--   group  : the part that gets highlighted / reported (head, body, left_arm ...)
--   points : bones the box has to enclose
--   axis   : { from_bone, to_bone } the box's long axis runs along this line
--   side   : cm added left / right of the bones
--   depth  : cm added in front of / behind the bones
--   below  : cm added past the "from" end,  above : cm added past the "to" end
-- All of these numbers are for a normal sized cop and are scaled up or down
-- automatically for bigger / smaller models (see GetBodyScale). If a box
-- still looks too big or too small in-game, these are the only numbers you
-- need to change.
AddBulletTrail.HITBOX_PARTS = {
	{ id = "head", group = "head", points = { "Head" }, axis = { "Neck", "Head" },
		side = 8, depth = 9.5, below = 1, above = 21 },
	{ id = "body", group = "body", points = { "Hips", "Spine1", "Spine2", "Neck", "LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg" },
		axis = { "Hips", "Neck" }, side = 6, depth = 11, below = 3, above = 0 },

	{ id = "left_arm_upper", group = "left_arm", points = { "LeftArm", "LeftForeArm" },
		axis = { "LeftArm", "LeftForeArm" }, side = 4.5, depth = 4.5, below = 2, above = 1 },
	{ id = "left_arm_lower", group = "left_arm", points = { "LeftForeArm", "LeftHand" },
		axis = { "LeftForeArm", "LeftHand" }, side = 4, depth = 4, below = 1, above = 8 },
	{ id = "right_arm_upper", group = "right_arm", points = { "RightArm", "RightForeArm" },
		axis = { "RightArm", "RightForeArm" }, side = 4.5, depth = 4.5, below = 2, above = 1 },
	{ id = "right_arm_lower", group = "right_arm", points = { "RightForeArm", "RightHand" },
		axis = { "RightForeArm", "RightHand" }, side = 4, depth = 4, below = 1, above = 8 },

	{ id = "left_leg_upper", group = "left_leg", points = { "LeftUpLeg", "LeftLeg" },
		axis = { "LeftUpLeg", "LeftLeg" }, side = 7, depth = 8, below = 2, above = 1 },
	{ id = "left_leg_lower", group = "left_leg", points = { "LeftLeg", "LeftFoot" },
		axis = { "LeftLeg", "LeftFoot" }, side = 6, depth = 9, below = 1, above = 8 },
	{ id = "right_leg_upper", group = "right_leg", points = { "RightUpLeg", "RightLeg" },
		axis = { "RightUpLeg", "RightLeg" }, side = 7, depth = 8, below = 2, above = 1 },
	{ id = "right_leg_lower", group = "right_leg", points = { "RightLeg", "RightFoot" },
		axis = { "RightLeg", "RightFoot" }, side = 6, depth = 9, below = 1, above = 8 }
}

-- Length of Hips -> Neck on a normal sized cop (cm). Bigger or smaller models
-- (bulldozers, custom player models, ...) have their boxes scaled by how
-- much longer / shorter their own torso is.
AddBulletTrail.REFERENCE_TORSO = 50
AddBulletTrail.SCALE_MIN = 0.5
AddBulletTrail.SCALE_MAX = 3

local function normalized_or_nil(v)
	local length = v:length()
	if length < 0.001 then
		return nil
	end
	return v * (1 / length)
end

local function cross(a, b)
	return Vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

function AddBulletTrail:GetBonePositions(entry)
	if not entry.bones or not alive(entry.unit) then
		entry.bones = self:ResolveBones(entry.unit)
	end
	local points = {}
	for name, object in pairs(entry.bones) do
		points[name] = object:position()
	end
	return points
end

-- How much bigger / smaller than a normal cop this model is. Normal sized
-- models (within 15 %) are left exactly as they are.
function AddBulletTrail:GetBodyScale(points)
	local hips, neck = points.Hips, points.Neck
	if not hips or not neck then
		return 1
	end
	local scale = (neck - hips):length() / self.REFERENCE_TORSO
	if scale > 0.85 and scale < 1.15 then
		return 1
	end
	return math.max(self.SCALE_MIN, math.min(self.SCALE_MAX, scale))
end

-- The direction that points to the enemy's right, taken from the enemy's OWN
-- body (shoulder line, hip line) and not from the unit's root, so the boxes
-- turn with a leaning / twisting / dashing model. Returns it squared to
-- `up`. Falls back to the root's axes when the body gives nothing usable.
local function pick_right(up, candidates)
	local best, best_score
	for _, candidate in ipairs(candidates) do
		local flat = normalized_or_nil(candidate - up * mvector3.dot(candidate, up))
		if flat then
			-- the more square the candidate is to `up`, the better it is
			local score = 1 - math.abs(mvector3.dot(candidate, up) / math.max(candidate:length(), 0.001))
			if score > 0.35 then
				return flat
			end
			if not best or score > best_score then
				best, best_score = flat, score
			end
		end
	end
	return best
end

-- Builds the current box of every part: its three axes and the min / max of
-- the box along each of them. Used for drawing AND for deciding which part
-- a hit belongs to, so the red box always is the one the bullet is inside.
function AddBulletTrail:BuildPartBoxes(entry)
	local unit = entry.unit
	local points = self:GetBonePositions(entry)
	local rotation = unit:rotation()
	local scale = self:GetBodyScale(points)
	local boxes = {}

	-- candidate "right" directions, best first: shoulder line, hip line,
	-- then the unit's own right and forward
	local body_right = {}
	if points.LeftArm and points.RightArm then
		body_right[#body_right + 1] = points.RightArm - points.LeftArm
	end
	if points.LeftUpLeg and points.RightUpLeg then
		body_right[#body_right + 1] = points.RightUpLeg - points.LeftUpLeg
	end
	body_right[#body_right + 1] = rotation:x()
	body_right[#body_right + 1] = rotation:y()

	for _, part in ipairs(self.HITBOX_PARTS) do
		local list = {}
		for _, name in ipairs(part.points) do
			if points[name] then
				list[#list + 1] = points[name]
			end
		end

		-- a box needs all of its bones; a half-found limb would give a wrong box
		if #list == #part.points then
			local up
			local from, to = points[part.axis[1]], points[part.axis[2]]
			if from and to then
				up = normalized_or_nil(to - from)
			end
			up = up or Vector3(0, 0, 1)

			local right = pick_right(up, body_right) or rotation:x()
			local forward = cross(up, right)
			local axes = { right, forward, up }

			local min, max = {}, {}
			for axis = 1, 3 do
				for index, point in ipairs(list) do
					local value = mvector3.dot(point, axes[axis])
					if index == 1 or value < min[axis] then
						min[axis] = value
					end
					if index == 1 or value > max[axis] then
						max[axis] = value
					end
				end
			end
			min[1], max[1] = min[1] - part.side * scale, max[1] + part.side * scale
			min[2], max[2] = min[2] - part.depth * scale, max[2] + part.depth * scale
			min[3], max[3] = min[3] - part.below * scale, max[3] + part.above * scale

			boxes[#boxes + 1] = {
				id = part.id,
				group = part.group or part.id,
				axes = axes,
				min = min,
				max = max,
				volume = (max[1] - min[1]) * (max[2] - min[2]) * (max[3] - min[3])
			}
		end
	end

	return boxes
end

-- How far (squared, in cm) a position is outside a box. 0 = inside.
local function box_excess(box, position)
	local sum = 0
	for axis = 1, 3 do
		local value = mvector3.dot(position, box.axes[axis])
		local difference = 0
		if value < box.min[axis] then
			difference = box.min[axis] - value
		elseif value > box.max[axis] then
			difference = value - box.max[axis]
		end
		sum = sum + difference * difference
	end
	return sum
end

-- Which part did this hit land on? The game decides what a headshot is.
-- For everything else the part whose box the bullet ended up in wins (the
-- smallest box if several overlap); a hit outside every box goes to the
-- nearest one. The head box is only used for real headshots.
function AddBulletTrail:ClassifyHit(damage_ext, entry, attack_data)
	local head_hit = attack_data.headshot and true or false
	if not head_hit then
		pcall(function()
			local body = attack_data.col_ray and attack_data.col_ray.body
			if body and damage_ext._ids_head_body_name then
				head_hit = body:name() == damage_ext._ids_head_body_name
			end
		end)
	end
	if head_hit then
		return "head"
	end

	local hit_pos = attack_data.col_ray and attack_data.col_ray.position
	if not hit_pos then
		return nil
	end

	local best, best_excess, best_volume
	for _, box in ipairs(self:BuildPartBoxes(entry)) do
		if box.group ~= "head" then
			local excess = box_excess(box, hit_pos)
			local better = not best
				or excess < best_excess - 0.0001
				or (math.abs(excess - best_excess) <= 0.0001 and box.volume < best_volume)
			if better then
				best, best_excess, best_volume = box.group, excess, box.volume
			end
		end
	end
	return best
end

-- Called for every hit you land. The box stays for the hit box duration;
-- every part you hit in that time stays highlighted.
function AddBulletTrail:AddHitBox(damage_ext, unit, attack_data)
	local key = unit:key()
	local entry = self.HitBoxes[key]
	if not entry then
		entry = { unit = unit, hits = {} }
		self.HitBoxes[key] = entry
	end
	entry.age = 0
	entry.time = tonumber(self.Settings.hitbox_time) or 1

	local part_id = self:ClassifyHit(damage_ext, entry, attack_data)
	if part_id then
		entry.hits[part_id] = true
	end
end

Hooks:PostHook(CopDamage, "damage_bullet", "AddBulletTrail_OutlineBullet", function(self, attack_data)
	local ok, err = pcall(AddBulletTrail.OnEnemyHit, AddBulletTrail, self, attack_data)
	if not ok then
		AddBulletTrail.OUTLINE_FAILED = true
		log("[AddBulletTrail] hit outline failed and was turned off: " .. tostring(err))
	end
end )

Hooks:PostHook(CopDamage, "damage_melee", "AddBulletTrail_OutlineMelee", function(self, attack_data)
	local ok, err = pcall(AddBulletTrail.OnEnemyHit, AddBulletTrail, self, attack_data)
	if not ok then
		AddBulletTrail.OUTLINE_FAILED = true
		log("[AddBulletTrail] hit outline failed and was turned off: " .. tostring(err))
	end
end )
