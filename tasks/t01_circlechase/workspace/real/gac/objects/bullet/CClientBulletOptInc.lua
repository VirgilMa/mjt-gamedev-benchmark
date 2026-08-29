--
-- $Id$
--

CClientBulletOpt = class(CClientCharacter)

RegistClassMember(CClientBulletOpt, "m_UId")
RegistClassMember(CClientBulletOpt, "m_ClientBornTime")
RegistClassMember(CClientBulletOpt, "m_EffectList")
RegistClassMember(CClientBulletOpt, "m_FxId")
RegistClassMember(CClientBulletOpt, "m_StyleEffect")
RegistClassMember(CClientBulletOpt, "m_StyleCharMod")

RegistClassMember(CClientBulletOpt, "m_OldX")
RegistClassMember(CClientBulletOpt, "m_OldY")
RegistClassMember(CClientBulletOpt, "m_OldZ")
RegistClassMember(CClientBulletOpt, "m_Degree")
RegistClassMember(CClientBulletOpt, "m_NeedCreate")

RegistClassMember(CClientBulletOpt, "m_ReplaceTexPath")
RegistClassMember(CClientBulletOpt, "m_ReplaceRendererIdx")
RegistClassMember(CClientBulletOpt, "m_AppearReplaceValue")

RegistClassMember(CClientBulletOpt, "m_IsAILoaded")
RegistClassMember(CClientBulletOpt, "m_AINameList")
RegistClassMember(CClientBulletOpt, "m_DesignDataInteractCache")
RegistClassMember(CClientBulletOpt, "m_EnableRestoreCameraOnDestroy")

RegistClassMember(CClientBulletOpt, "m_IsEnemyBullet")

require 'objects/bullet/CClientBulletOpt'
require 'objects/bullet/CClientBulletTrajectoryImp'

