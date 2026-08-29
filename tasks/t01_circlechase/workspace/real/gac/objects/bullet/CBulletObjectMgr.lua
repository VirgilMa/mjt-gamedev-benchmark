function CBulletObjectMgr:Ctor()	
	self.m_UId2OptBullet = {}
	self.m_OptBulletAutoIncUId = 0
end

function CBulletObjectMgr:StartUp()
	MODULE_STATUS("BulletObject", STATUS_STARTING)
	
	MsgHub_AfterGacCoreUpdate:AddListener(self)
	MsgHub_GacExitCurrentRole:AddListener(self)
			
	MODULE_STATUS("BulletObject", STATUS_RUNNING)
end

function CBulletObjectMgr:ShutDown()
	MODULE_STATUS("BulletObject", STATUS_STOPPED)
end

function CBulletObjectMgr:OnAfterGacCoreUpdate()
    for k, v in pairs(self.m_UId2OptBullet) do 
		SAFE_CALL( v.AfterGacCoreUpdate, v )
	end
end

function CBulletObjectMgr:OnGacExitCurrentRole()
	for k, v in pairs(self.m_UId2OptBullet) do 
		v:Destroy()
	end
	table.clear(self.m_UId2OptBullet)

	table.clear(g_CreateEnemyBullet2Cnt)
	table.clear(g_CreateNoEnemyBullet2Cnt)
end

local CLIENT_BULLET_OPT_UID_CAPACITY = 2 ^ 30
local CLIENT_BULLET_OPT_BASE_UID = 2 ^ 30
function CBulletObjectMgr:GenOptBulletUId()
	self.m_OptBulletAutoIncUId = self.m_OptBulletAutoIncUId + 1
	if self.m_OptBulletAutoIncUId >= CLIENT_BULLET_OPT_UID_CAPACITY then 
		self.m_OptBulletAutoIncUId = 1
	end
	return self.m_OptBulletAutoIncUId + CLIENT_BULLET_OPT_BASE_UID
end

function CBulletObjectMgr:IsPureClientBullet(bulletObj)
	return bulletObj:GetUId() > CLIENT_BULLET_OPT_BASE_UID
end

function CBulletObjectMgr:AddOptBullet(bulletObj)
	local id = bulletObj:GetUId()
	if id < 0 then
		id = self:GenOptBulletUId()
		bulletObj.m_UId = id
	end
	local obj = self.m_UId2OptBullet[id]
	if obj then 
		obj:Destroy()
		LogCallContext_lua()
	end
	self.m_UId2OptBullet[id] = bulletObj
end

function CBulletObjectMgr:RemoveOptBullet(bulletObj)
	local id = bulletObj:GetUId()
	self.m_UId2OptBullet[id] = nil
end

function CBulletObjectMgr:GetOptBulletByUId(uid)
	return self.m_UId2OptBullet[uid]
end
