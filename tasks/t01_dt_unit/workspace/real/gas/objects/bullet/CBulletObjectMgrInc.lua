--
-- $Id$
--

MODULE("BulletObject")
MODULE_DEPEND("BulletObject", "ServerObjPool")
MODULE_DATA("BulletObject")

RegistClassMember(CBulletObjectMgr, "m_OptBulletAutoIncUId")
RegistClassMember(CBulletObjectMgr, "m_UId2OptBullet")
RegistClassMember(CBulletObjectMgr, "m_BulletDesignId2ZAboveBelow")

require("objects/bullet/CBulletObjectMgr")
