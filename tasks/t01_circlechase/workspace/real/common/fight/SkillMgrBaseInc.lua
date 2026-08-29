require("objects/character/CCharacterInc")

CSkillMgrBase = class()
RegistClassMember(CSkillMgrBase, "m_StepSkills")
RegistClassMember(CSkillMgrBase, "m_SkillLvSourceTb")
RegistClassMember(CSkillMgrBase, "m_XueHeComboSkills")
RegistClassMember(CSkillMgrBase, "m_XueHeComboLastSkill")
RegistClassMember(CSkillMgrBase, "m_XueHeComboSkillsGP") -- 专门为玩法搞的一组
RegistClassMember(CSkillMgrBase, "m_XueHeComboLastSkillGP") -- 专门为玩法搞的一组
RegistClassMember(CSkillMgrBase, "m_SkillType2SkillCls")
RegistClassMember(CSkillMgrBase, "m_SkillCls2SkillType")
RegistClassMember(CSkillMgrBase, "m_SkillUpData")

RegistClassMember(CSkillMgrBase, "m_AttMode2MissFuncTbl")
RegistClassMember(CSkillMgrBase, "m_AttMode2CritialFuncTbl")
RegistClassMember(CSkillMgrBase, "m_AttMode2MissFormulaId")
RegistClassMember(CSkillMgrBase, "m_AttMode2CritialFormulaId")

RegistClassMember(CSkillMgrBase, "m_EffectCheckFuntionTable")
RegistClassMember(CSkillMgrBase, "DEFAULT_MAX_SKILL_TARGET_NUM")
RegistClassMember(CSkillMgrBase, "DEFAULT_MAX_SKILL_PLAYER_TARGET_NUM")
RegistClassMember(CSkillMgrBase, "m_MAX_TARGET_NUM")
RegistClassMember(CSkillMgrBase, "m_MAX_PLAYER_TARGET_NUM")
RegistClassMember(CSkillMgrBase, "m_MAX_SKILL_TARGET_NUM_FOR_SET")

RegistClassMember(CSkillMgrBase, "m_SkillGuideData")
RegistClassMember(CSkillMgrBase, "m_SkillExploreGuideData")
RegistClassMember(CSkillMgrBase, "m_TestIgnoreCD")
RegistClassMember(CSkillMgrBase, "m_MainSkillInfo")
RegistClassMember(CSkillMgrBase, "m_PlateformWhiteSkillTbl")
RegistClassMember(CSkillMgrBase, "m_YHFStatusSkills")
RegistClassMember(CSkillMgrBase, "m_IdentityMainSkilTbl")


RegistClassMember(CSkillMgrBase, "m_TempMonsterPartIgnoreIdMap")
RegistClassMember(CSkillMgrBase, "m_TempMonsterPartChemiIgnoreIdMap")
RegistClassMember(CSkillMgrBase, "m_JiangHuJueXingClsInfo")
RegistClassMember(CSkillMgrBase, "m_GameplayIDToBigBuildGroupTagMap")
RegistClassMember(CSkillMgrBase, "m_BigBuildGroupTagToRankIDsMap")

RegistClassMember(CSkillMgrBase, "m_SkillFeatureId2True")
RegistClassMember(CSkillMgrBase, "m_SkillFeatureName2Id")

RegistClassMember(CSkillMgrBase, "_m_Debug")

RegistClassMember(CSkillMgrBase, "m_SkillLvSourceCache")
RegistClassMember(CSkillMgrBase, "m_SkillLvSourceCache2")

RegistClassMember(CSkillMgrBase, "m_PuGongList")

RegistClassMember(CSkillMgrBase, "m_SkillCls2SubWeaponId")

CSkillObject = class()
g_SkillCondition = nil

require("fight/SkillMgrBase")
