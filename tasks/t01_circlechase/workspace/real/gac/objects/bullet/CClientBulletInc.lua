--
-- $Id$
--

CClientBullet = class(CFollowerCharacter)

RegistClassMember(CClientBullet, "m_ClientBornTime")
RegistClassMember(CClientBullet, "m_EffectList")
RegistClassMember(CClientBullet, "m_FxId")
RegistClassMember(CClientBullet, "m_StyleEffect")
RegistClassMember(CClientBullet, "m_StyleCharMod")

--龙吟惊雷剑气处理
RegistClassMember(CClientBullet, "m_LongYinQJItem")

RegistClassMember(CClientBullet, "m_IsEnemyBullet")

RegistClassMember(CClientBullet, "m_IsHitPosCorrect")
RegistClassMember(CClientBullet, "m_NeedCreate")

RegistClassMember(CClientBullet, "m_ReplaceTexPath")
RegistClassMember(CClientBullet, "m_ReplaceRendererIdx")

RegistClassMember(CClientBullet, "m_UseWeaponCharDef_WeaponId")
RegistClassMember(CClientBullet, "m_UseWeaponCharDef_Index")
RegistClassMember(CClientBullet, "m_AppearReplaceValue")

RegistClassMember(CClientBullet, "m_IsHitClientNpc")
RegistClassMember(CClientBullet, "m_UgcFxID")
RegistClassMember(CClientBullet, "m_UgcFxScale")
RegistClassMember(CClientBullet, "m_PositionChangeCallback")
RegistClassMember(CClientBullet, "m_DestroyCallback")
RegistClassMember(CClientBullet, "m_HasHeadInfo")

RegistClassMember(CClientBullet, "m_FxOffsetX")
RegistClassMember(CClientBullet, "m_FxOffsetY")
RegistClassMember(CClientBullet, "m_FxOffsetZ")
RegistClassMember(CClientBullet, "m_DesignDataInteractCache")
RegistClassMember(CClientBullet, "m_IsUgcBullet")
RegistClassMember(CClientBullet, "m_FruitId")
RegistClassMember(CClientBullet, "m_FruitData")
RegistClassMember(CClientBullet, "m_FruitBulletPlantObj")
-- RegistClassMember(CClientBullet, "m_CachedOwnerId")
-- RegistClassMember(CClientBullet, "m_CachedOwnerCharacter")

RegistClassMember(CClientBullet, "m_ReportedClientHitTargets")

g_CreateEnemyBullet2Cnt = {}
g_CreateNoEnemyBullet2Cnt = {}

require "objects/character/BulletCommonInc"
require 'objects/bullet/CClientBullet'
if OPTIMIZE_MODE_EX_BULLET then
require 'objects/bullet/CClientBullet_Override'
end
