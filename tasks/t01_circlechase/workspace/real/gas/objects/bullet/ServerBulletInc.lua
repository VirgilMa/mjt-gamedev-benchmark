--


CServerBullet = class(CServerCharacter)

RegistClassMember(CServerBullet, "_m_MoveOnAboutToInsertToScene")

RegistClassMember(CServerBullet, "m_Level")
RegistClassMember(CServerBullet, "m_AOITriggers")
RegistClassMember(CServerBullet, "m_InitDegree")
RegistClassMember(CServerBullet, "m_AutoDestroyTime")
RegistClassMember(CServerBullet, "m_DamageEyeSight")

RegistClassMember(CServerBullet, "m_SkillWallData")
RegistClassMember(CServerBullet, "m_BornTime")
RegistClassMember(CServerBullet, "m_MyHelpAOITrigger")

RegistClassMember(CServerBullet, "m_SkillEnabled")
RegistClassMember(CServerBullet, "m_ExtraAddBuff")
RegistClassMember(CServerBullet, "m_ShareHitTimeTb")
RegistClassMember(CServerBullet, "m_BeforDestroyActionFunc")
RegistClassMember(CServerBullet, "m_HitActionFunc")
RegistClassMember(CServerBullet, "m_XXLYAttachMentId")

RegistClassMember(CServerBullet, "m_SummonerId")
RegistClassMember(CServerBullet, "m_SummonSkillId")
RegistClassMember(CServerBullet, "m_TimesHurtMul")
RegistClassMember(CServerBullet, "m_TimesHurtAdj")
RegistClassMember(CServerBullet, "m_IsOptBullet")
RegistClassMember(CServerBullet, "m_Share")
RegistClassMember(CServerBullet, "m_HitEnabled")
RegistClassMember(CServerBullet, "m_ReplaceTexPath")
RegistClassMember(CServerBullet, "m_ReplaceRendererIdx")
RegistClassMember(CServerBullet, "m_UseWeaponCharDef_WeaponId")
RegistClassMember(CServerBullet, "m_UseWeaponCharDef_Index")
RegistClassMember(CServerBullet, "m_AppearReplaceValue")
RegistClassMember(CServerBullet, "m_AttachToPlayerId") -- BulletAttachType
RegistClassMember(CServerBullet, "m_CurMoveFrame")
RegistClassMember(CServerBullet, "m_GenCGScope")
RegistClassMember(CServerBullet, "m_IsTargetReached")
RegistClassMember(CServerBullet, "m_IsNoAoiHitQuery")
RegistClassMember(CServerBullet, "m_UgcBulletData")
RegistClassMember(CServerBullet, "m_PropertyAppearance")
RegistClassMember(CServerBullet, "m_AppearUD")
RegistClassMember(CServerBullet, "m_FruitId")
RegistClassMember(CServerBullet, "m_FruitData")

-- 一些debug信息
RegistClassMember(CServerBullet, "m_OwnerCharacterType")
RegistClassMember(CServerBullet, "m_OwnerTemplateId")

-- 用于风墙命中检测
RegistClassMember(CServerBullet, "m_PreX")
RegistClassMember(CServerBullet, "m_PreY")

RegistClassMember(CServerBullet, "m_ClientHitZombie")
RegistClassMember(CServerBullet, "m_RefreshedMoveDataFlag")

RegistClassMember(CServerBullet, "m_PendingClientHitResult")

CServerBulletShare = class()
RegistClassMember(CServerBulletShare, "m_Bullet")
RegistClassMember(CServerBulletShare, "m_LiftTime")
RegistClassMember(CServerBulletShare, "m_LastHitTimeTb")
RegistClassMember(CServerBulletShare, "m_HitedPlayerCount")
RegistClassMember(CServerBulletShare, "m_HitedObjectCount")
RegistClassMember(CServerBulletShare, "m_ZAbove")
RegistClassMember(CServerBulletShare, "m_ZBelow")
RegistClassMember(CServerBulletShare, "m_ZAbovePixel")
RegistClassMember(CServerBulletShare, "m_ZBelowPixel")

require "objects/character/BulletCommonInc"
require("objects/bullet/ServerBullet")
