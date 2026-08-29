--
require("fight/SkillMgrBaseInc")

RegistClassMember(CSkillObject, "m_SkillCls")
RegistClassMember(CSkillObject, "m_Owner")
RegistClassMember(CSkillObject, "m_State")
RegistClassMember(CSkillObject, "m_IsValid")

RegistClassMember(CSkillObject, "m_AOITrigger")
RegistClassMember(CSkillObject, "m_AOITriggerHitTb")
RegistClassMember(CSkillObject, "m_AOITriggerInvalidTime") --AOITrigger失效时间，惰性检查不用开tick
RegistClassMember(CSkillObject, "m_TimeoutEnterObjId") --失效时间之后进入aoitrigger的对象
RegistClassMember(CSkillObject, "m_bIsValid")
RegistClassMember(CSkillObject, "m_Step")

RegistClassMember(CSkillObject, "m_StepTick")
RegistClassMember(CSkillObject, "m_SourceId")
RegistClassMember(CSkillObject, "m_bSetBrotherSkillCD")

RegistClassMember(CSkillObject, "m_StepIntTime") -- 带时限的step技能的开始时间戳
RegistClassMember(CSkillObject, "m_StepIntTotalT") -- 带时限的step技能的时限总时长

RegistClassMember(CSkillObject, "m_SourceInfoExtra")
RegistClassMember(CSkillObject, "m_IsInExtraSkill") -- 进入“额外技能”状态，提前进入cd和技能结算逻辑。

RegistClassMember(CSkillObject, "m_InSkillEffects") -- 技能内的特效，技能被打断时会移除，正常结束不会移除

require("objects/bullet/CSkillObject")
