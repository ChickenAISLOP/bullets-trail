_G.AddBulletTrail = _G.AddBulletTrail or {}

-- When you are a client, hits on enemies go through HuskCopDamage. Only hook
-- the functions it defines itself so a hit is never handled twice.
local function hook_husk(func_name, hook_id)
	if HuskCopDamage and rawget(HuskCopDamage, func_name) then
		Hooks:PostHook(HuskCopDamage, func_name, hook_id, function(self, attack_data)
			if not AddBulletTrail.OnEnemyHit then
				return
			end
			local ok, err = pcall(AddBulletTrail.OnEnemyHit, AddBulletTrail, self, attack_data)
			if not ok then
				AddBulletTrail.OUTLINE_FAILED = true
				log("[AddBulletTrail] hit outline failed and was turned off: " .. tostring(err))
			end
		end )
	end
end

hook_husk("damage_bullet", "AddBulletTrail_HuskOutlineBullet")
hook_husk("damage_melee", "AddBulletTrail_HuskOutlineMelee")
