_G.AddBulletTrail = _G.AddBulletTrail or {}

-- The original sniper_trail particle has no color setting, so trails are drawn
-- as a colored beam instead. Set this to true to go back to the original
-- particle trail (the color sliders then have no effect).
AddBulletTrail.USE_PARTICLE_TRAIL = false

-- Beam look. Length is the same distance the original particle trail used.
AddBulletTrail.TRAIL_LENGTH = 1000
AddBulletTrail.TRAIL_RADIUS = 0.3

-- Fade timing. The beam stays fully visible for the hold time (the delay),
-- then fades out over the fade time. Both can be changed in the mod's options
-- menu; these are only the defaults and the fallback if the settings are missing.
AddBulletTrail.DEFAULT_HOLD = 0.25 -- seconds at full strength before fading starts
AddBulletTrail.DEFAULT_FADE = 0.6 -- seconds the fade-out takes

-- Safety cap so long delays + full-auto fire can't pile up hundreds of beams.
AddBulletTrail.MAX_TRAILS = 150

AddBulletTrail.Trails = AddBulletTrail.Trails or {}

local HookAddBulletTrail = NewRaycastWeaponBase.fire
local idstr_trail = Idstring("trail")
local idstr_simulator_length = Idstring("simulator_length")
local idstr_size = Idstring("size")

-- Original behaviour: the white sniper_trail particle effect.
function AddBulletTrail:SpawnParticleTrail(weapon_base, direction)
	weapon_base.TRAIL_EFFECT = Idstring("effects/particles/weapons/sniper_trail")
	weapon_base._trail_effect_table = {
		effect = weapon_base.TRAIL_EFFECT,
		position = Vector3(),
		normal = Vector3()
	}
	weapon_base._trail_length = World:effect_manager():get_initial_simulator_var_vector2(weapon_base.TRAIL_EFFECT, idstr_trail, idstr_simulator_length, idstr_size)
	local col_ray = {
		distance = self.TRAIL_LENGTH
	}
	NPCSniperRifleBase._spawn_trail_effect(weapon_base, direction, col_ray)
end

-- Queues a beam from the muzzle. It is drawn, held and faded out by
-- AddBulletTrail:UpdateTrails() in gamesetup.lua.
function AddBulletTrail:SpawnBeamTrail(weapon_base, direction)
	local muzzle = weapon_base._obj_fire
	if not muzzle then
		return
	end
	local from = Vector3()
	muzzle:m_position(from)

	local settings = self.Settings or {}
	local trails = self.Trails
	while #trails >= self.MAX_TRAILS do
		table.remove(trails, 1) -- drop the oldest beam
	end
	table.insert(trails, {
		from = from,
		to = from + direction * self.TRAIL_LENGTH,
		age = 0,
		hold = tonumber(settings.hold) or self.DEFAULT_HOLD,
		fade = math.max(0.01, tonumber(settings.fade) or self.DEFAULT_FADE),
		radius = self.TRAIL_RADIUS
	})
end

-- Wraps a weapon class's own fire function so every weapon leaves a trail.
-- A weapon is never wrapped twice, and a weapon that fires twice in the same
-- moment (a subclass calling its parent) only gets one trail.
function AddBulletTrail:WrapFire(class_table)
	if not class_table or not rawget(class_table, "fire") then
		return
	end
	local original = rawget(class_table, "fire")
	if self.WrappedFire and self.WrappedFire[original] then
		return
	end
	self.WrappedFire = self.WrappedFire or {}

	local function wrapped(weapon_base, from_pos, direction, ...)
		if direction and self:IsWeaponEnabled(weapon_base._name_id) then
			local now = TimerManager and TimerManager:game():time() or 0
			if weapon_base._abt_last_fire ~= now then
				weapon_base._abt_last_fire = now
				local ok, err = pcall(function()
					if self.USE_PARTICLE_TRAIL or self.DRAW_FAILED or not Draw then
						self:SpawnParticleTrail(weapon_base, direction)
					else
						self:SpawnBeamTrail(weapon_base, direction)
					end
				end)
				if not ok then
					log("[AddBulletTrail] trail failed: " .. tostring(err))
				end
			end
		end
		return original(weapon_base, from_pos, direction, ...)
	end

	self.WrappedFire[original] = true
	self.WrappedFire[wrapped] = true
	class_table.fire = wrapped
end

-- The main weapon class (rifles, SMGs, pistols, shotguns that use its fire).
-- Fire functions that do not exist on it yet are inherited, so make it its own.
if not rawget(NewRaycastWeaponBase, "fire") and NewRaycastWeaponBase.fire then
	local inherited = NewRaycastWeaponBase.fire
	NewRaycastWeaponBase.fire = function(...)
		return inherited(...)
	end
end
AddBulletTrail:WrapFire(NewRaycastWeaponBase)
