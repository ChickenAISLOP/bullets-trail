_G.AddBulletTrail = _G.AddBulletTrail or {}

-- Weapon classes that have their own fire function (bows, crossbows, grenade
-- launchers, flamethrowers, saws, shotguns). This file is loaded after each
-- of their class files, so whichever of them exist get the trail too.
for _, class_name in ipairs({ "ProjectileWeaponBase", "FlamethrowerBase", "SawWeaponBase", "ShotgunBase" }) do
	local class_table = rawget(_G, class_name)
	if class_table and AddBulletTrail.WrapFire then
		AddBulletTrail:WrapFire(class_table)
	end
end
