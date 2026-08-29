
function CBulletObjectMgr:Ctor()	
	self.m_OptBulletAutoIncUId = 0
	self.m_UId2OptBullet = {}
end

function CBulletObjectMgr:StartUp()
	MODULE_STATUS("BulletObject", STATUS_STARTING)
	
	self:LoadDesignData()
	
	MsgHub_GasPlayerAboutToLeaveScene:AddListener(self)
	MsgHub_GasFakePlayerAboutToLeaveScene:AddListener(self)

	g_ObjPoolMgr:RegisterPool(CServerBulletOpt, 1000)
			
	MODULE_STATUS("BulletObject", STATUS_RUNNING)
	flowchart.import("BulletAI")
end

function CBulletObjectMgr:ShutDown()
	
	MODULE_STATUS("BulletObject", STATUS_STOPPED)
end

function CBulletObjectMgr:LoadDesignData()
	for k, v in bddpairs(Bullet_Bullet) do
		if v.NoAoiHit and v.OnlyHitTarget == 1 and v.Speed <= MAX_BULLET_AOI_HIT_SPEED then
			assert(false, "OnlyHitTarget Do Not Need NoAoiHit " .. k)
		end
	end
	g_BulletObjectMgr:LoadZAboveBelow()
end

function CBulletObjectMgr:LoadZAboveBelow()
	local tbl = {}
	self.m_BulletDesignId2ZAboveBelow = tbl
	for k, v in bddpairs(Bullet_Bullet) do
        local bulletZAbove, bulletZBelow = -1, -1
        local hitZPair = v["HitZPair"]
        if hitZPair then
            bulletZAbove, bulletZBelow = hitZPair[1], hitZPair[2]
        else
            local zBias = v["HitZ"]
            if zBias and zBias > 0 then
                bulletZAbove, bulletZBelow = zBias, zBias
            end
        end
        tbl[k] = { bulletZAbove, bulletZBelow }
	end
end

function CBulletObjectMgr:OnGasPlayerAboutToLeaveScene(player)
	player:DestroyAllMyBullets()
	
	for _,v in ipairs(player.m_RealPets) do 
		v:DestroyAllMyBullets()
	end
end

function CBulletObjectMgr:OnGasFakePlayerAboutToLeaveScene(player)
	self:OnGasPlayerAboutToLeaveScene(player)
end

local SERVER_BULLET_OPT_UID_CAPACITY = 2 ^ 30
function CBulletObjectMgr:GenOptBulletUId()
	self.m_OptBulletAutoIncUId = self.m_OptBulletAutoIncUId + 1
	if self.m_OptBulletAutoIncUId >= SERVER_BULLET_OPT_UID_CAPACITY then 
		self.m_OptBulletAutoIncUId = 1
	end
	return self.m_OptBulletAutoIncUId
end

function CBulletObjectMgr:AddOptBullet(bulletObj)
	local id = self:GenOptBulletUId()
	local obj = self.m_UId2OptBullet[id]
	if obj then 
		obj:Destroy()
		LogCallContext_lua()
	end
	bulletObj.m_UId = id
	self.m_UId2OptBullet[id] = bulletObj
end

function CBulletObjectMgr:RemoveOptBullet(bulletObj)
	local id = bulletObj:GetUId()
	self.m_UId2OptBullet[id] = nil
end

function CBulletObjectMgr:GetOptBulletByUId(uid)
	return self.m_UId2OptBullet[uid]
end
