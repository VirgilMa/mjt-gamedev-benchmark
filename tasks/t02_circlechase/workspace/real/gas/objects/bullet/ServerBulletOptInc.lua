--


CServerBulletOpt = class()

RegistClassMember(CServerBulletOpt, "m_UId")

RegistClassMember(CServerBulletOpt, "m_Level")
RegistClassMember(CServerBulletOpt, "m_BulletMoveData")
RegistClassMember(CServerBulletOpt, "m_AutoDestroyTime")
RegistClassMember(CServerBulletOpt, "m_DamageEyeSight")

RegistClassMember(CServerBulletOpt, "m_SkillEnabled")

RegistClassMember(CServerBulletOpt, "m_ShareHitTimeTb")
RegistClassMember(CServerBulletOpt, "m_BeforDestroyActionFunc")
RegistClassMember(CServerBulletOpt, "m_BulletDistToGround")
RegistClassMember(CServerBulletOpt, "m_BulletOnGroundMoveZ")
RegistClassMember(CServerBulletOpt, "m_BulletDelayMoveTime")
RegistClassMember(CServerBulletOpt, "m_BulletMoveNextMoveStop")
RegistClassMember(CServerBulletOpt, "m_BulletMoveStopMoving")
RegistClassMember(CServerBulletOpt, "m_BulletForeverMove")
RegistClassMember(CServerBulletOpt, "m_SummonSkillId")
RegistClassMember(CServerBulletOpt, "m_TimesHurtMul")
RegistClassMember(CServerBulletOpt, "m_TimesHurtAdj")
RegistClassMember(CServerBulletOpt, "m_IsOptBullet")
RegistClassMember(CServerBulletOpt, "_m_TemplateId_For_Debug")
RegistClassMember(CServerBulletOpt, "m_Destroying")
RegistClassMember(CServerBulletOpt, "m_OwnerId")
RegistClassMember(CServerBulletOpt, "m_AttachToPlayerId")
RegistClassMember(CServerBulletOpt, "m_DirX")
RegistClassMember(CServerBulletOpt, "m_DirY")
RegistClassMember(CServerBulletOpt, "m_DirZ")
RegistClassMember(CServerBulletOpt, "m_DelayBulletMoveTick")
RegistClassMember(CServerBulletOpt, "m_Share")

RegistClassMember(CServerBulletOpt, "m_OnHitSkill")
RegistClassMember(CServerBulletOpt, "m_IsTargetReached")
RegistClassMember(CServerBulletOpt, "m_HitActionFunc")
RegistClassMember(CServerBulletOpt, "m_OptFloorHit")
RegistClassMember(CServerBulletOpt, "m_State")
RegistClassMember(CServerBulletOpt, "m_BulletCollisionFixOff")

RegistClassTickMember(CServerBulletOpt)

require("objects/bullet/ServerBulletOpt")
