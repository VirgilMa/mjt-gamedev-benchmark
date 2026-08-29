--
-- $Id$
--

MODULE("BulletObject")
MODULE_DEPEND("BulletObject")
MODULE_DATA("BulletObject")

RegistClassMember(CBulletObjectMgr, "m_UId2OptBullet")
RegistClassMember(CBulletObjectMgr, "m_OptBulletAutoIncUId")

require("objects/bullet/CBulletObjectMgr")
require("objects/bullet/CClientBulletOptInc")
