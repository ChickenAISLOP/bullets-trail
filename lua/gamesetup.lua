_G.AddBulletTrail = _G.AddBulletTrail or {}
AddBulletTrail.Trails = AddBulletTrail.Trails or {}
AddBulletTrail.Outlines = AddBulletTrail.Outlines or {}
AddBulletTrail.HitBoxes = AddBulletTrail.HitBoxes or {}

-- Draws every queued beam for one frame. A beam stays at full strength for its
-- hold time (the delay), then fades out smoothly over its fade time.
function AddBulletTrail:UpdateTrails(dt)
	local trails = self.Trails
	if #trails == 0 then
		return
	end

	local color = self.Settings.color
	local r, g, b = color.r / 255, color.g / 255, color.b / 255

	for i = #trails, 1, -1 do
		local trail = trails[i]
		trail.age = trail.age + dt
		local fade_progress = (trail.age - trail.hold) / trail.fade
		if fade_progress >= 1 then
			table.remove(trails, i)
		else
			local alpha = 1
			if fade_progress > 0 then
				-- smoothstep: eases in and eases out, so the beam lingers faintly
				-- at the end instead of snapping off. For a plain linear fade use:
				-- alpha = 1 - fade_progress
				alpha = 1 - fade_progress * fade_progress * (3 - 2 * fade_progress)
			end
			local brush = Draw:brush(Color(alpha, r, g, b))
			brush:cylinder(trail.from, trail.to, trail.radius)
		end
	end
end

-- The bones of an enemy rig the hit boxes are built from.
AddBulletTrail.BONE_NAMES = {
	"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"
}
AddBulletTrail.BoneIds = AddBulletTrail.BoneIds or {}

-- Looks up the bone objects of an enemy once; missing bones are skipped.
function AddBulletTrail:ResolveBones(unit)
	local bones = {}
	for _, name in ipairs(self.BONE_NAMES) do
		local id = self.BoneIds[name]
		if not id then
			id = Idstring(name)
			self.BoneIds[name] = id
		end
		local object = unit:get_object(id)
		if object then
			bones[name] = object
		end
	end
	return bones
end

-- Ends outlines when their time is up or the enemy died. The game draws the
-- contour itself; this only switches it off again.
function AddBulletTrail:UpdateOutlines(dt)
	local outlines = self.Outlines
	if next(outlines) == nil then
		return
	end

	for key, entry in pairs(outlines) do
		entry.age = entry.age + dt
		local unit = entry.unit

		local finished = not alive(unit) or entry.age >= entry.time
		if not finished then
			local damage_ext = unit:character_damage()
			finished = damage_ext and damage_ext.dead and damage_ext:dead() or false
		end

		if finished then
			self:RemoveOutline(key, entry)
		end
	end
end

-- Draws the hit boxes: one thin white box per body part, the parts you hit in
-- red with a translucent fill (only the red ones when "Only Red Hit Box" is on). Each box is built by BuildPartBoxes() in
-- copdamage.lua and follows the bones of its part.
local BOX_FACES = {
	{ 0, 2, 6, 4 }, { 1, 3, 7, 5 }, { 0, 1, 5, 4 },
	{ 2, 3, 7, 6 }, { 0, 1, 3, 2 }, { 4, 5, 7, 6 }
}

function AddBulletTrail:DrawHitBox(entry, alpha)
	local line_brush = Draw:brush(Color(alpha, 1, 1, 1))
	local hit_brush = Draw:brush(Color(alpha, 1, 0.15, 0.15))
	local face_brush = Draw:brush(Color(alpha * 0.35, 1, 0.1, 0.1))

	-- "Only Red Hit Box": parts you did not hit are not drawn at all
	local red_only = self.Settings.hitbox_red == "on"

	for _, box in ipairs(self:BuildPartBoxes(entry)) do
		if not red_only or entry.hits[box.group] then
		local axes, min, max = box.axes, box.min, box.max
-- the eight corners; bit 1 = x, bit 2 = y, bit 4 = z
		local corners = {}
		for i = 0, 7 do
			local x = (i % 2 == 0) and min[1] or max[1]
			local y = (math.floor(i / 2) % 2 == 0) and min[2] or max[2]
			local z = (math.floor(i / 4) % 2 == 0) and min[3] or max[3]
			corners[i] = axes[1] * x + axes[2] * y + axes[3] * z
		end

		local hit = entry.hits[box.group]
		local brush = hit and hit_brush or line_brush
		local radius = hit and 0.9 or 0.4

		for i = 0, 7 do
			for _, bit in ipairs({ 1, 2, 4 }) do
				if math.floor(i / bit) % 2 == 0 then
					brush:cylinder(corners[i], corners[i + bit], radius)
				end
			end
		end

		if hit and not self.HITBOX_QUAD_FAILED then
			local ok = pcall(function()
				for _, face in ipairs(BOX_FACES) do
					face_brush:quad(corners[face[1]], corners[face[2]], corners[face[3]], corners[face[4]])
				end
			end)
			if not ok then
				self.HITBOX_QUAD_FAILED = true
			end
		end
		end
	end
end
-- Expires the boxes (time up, enemy dead or gone) and fades them out over the
-- last moments.
function AddBulletTrail:UpdateHitBoxes(dt)
	local boxes = self.HitBoxes
	if next(boxes) == nil then
		return
	end

	for key, entry in pairs(boxes) do
		entry.age = entry.age + dt
		local unit = entry.unit

		local finished = not alive(unit) or entry.age >= entry.time
		if not finished then
			local damage_ext = unit:character_damage()
			finished = damage_ext and damage_ext.dead and damage_ext:dead() or false
		end

		if finished then
			boxes[key] = nil
		else
			local fade = math.max(0.01, math.min(0.25, entry.time))
			local alpha = math.min(1, (entry.time - entry.age) / fade)
			self:DrawHitBox(entry, alpha)
		end
	end
end

Hooks:PostHook(GameSetup, "update", "AddBulletTrail_Update", function(self, t, dt)
	if AddBulletTrail.UpdateTrails and not AddBulletTrail.DRAW_FAILED then
		local ok, err = pcall(AddBulletTrail.UpdateTrails, AddBulletTrail, dt)
		if not ok then
			-- never let a drawing problem crash the heist; use the particle trail instead
			AddBulletTrail.DRAW_FAILED = true
			AddBulletTrail.Trails = {}
			log("[AddBulletTrail] beam drawing failed, using the particle trail: " .. tostring(err))
		end
	end

	if AddBulletTrail.UpdateHitBoxes and not AddBulletTrail.HITBOX_FAILED and Draw then
		local ok, err = pcall(AddBulletTrail.UpdateHitBoxes, AddBulletTrail, dt)
		if not ok then
			AddBulletTrail.HITBOX_FAILED = true
			AddBulletTrail.HitBoxes = {}
			log("[AddBulletTrail] hit box drawing failed and was turned off: " .. tostring(err))
		end
	end

	if AddBulletTrail.UpdateEffects and not AddBulletTrail.EFFECT_FAILED then
		local ok, err = pcall(AddBulletTrail.UpdateEffects, AddBulletTrail, dt)
		if not ok then
			AddBulletTrail.EFFECT_FAILED = true
			pcall(AddBulletTrail.ClearEffects, AddBulletTrail)
			log("[AddBulletTrail] hit effect failed and was turned off: " .. tostring(err))
		end
	end

	if AddBulletTrail.UpdateOutlines and not AddBulletTrail.OUTLINE_FAILED then
		local ok, err = pcall(AddBulletTrail.UpdateOutlines, AddBulletTrail, dt)
		if not ok then
			AddBulletTrail.OUTLINE_FAILED = true
			for key, entry in pairs(AddBulletTrail.Outlines) do
				pcall(AddBulletTrail.RemoveOutline, AddBulletTrail, key, entry)
			end
			log("[AddBulletTrail] hit outline failed and was turned off: " .. tostring(err))
		end
	end
end )
