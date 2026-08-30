CBulletTrackMgr = class()

MAX_BULLET_AOI_HIT_SPEED = 1910 

EnumBulletTracjectory = {
    None = 0,
    AIControl = 1,
    Missile = 2,
    ChasingMissile = 3,
    Line = 4,
    Direction_Opt = 5,
    Direction = 6,
    DirectionLine = 7,
    LineHook = 8,
    ParabolaPos = 9,
    ParabolaTarget = 10,
    Chase = 11,
    BezierCurvePos = 12,
    BezierCurveTarget = 13,
    Arc = 14,
    TractionAndCircling = 15,
    EffectBullet = 16,
    HavokMove = 17,
    Bezier = 19,
    HalfChase = 20,
    Circle = 21,
    Chase3D = 22,
    BezierCircle = 23,
    BaFangJue = 24,
    ParabolaExPos = 25,
    RepeatHitTarget = 27,
    ForwardChase2D = 28,
    BoatFrontMove2D = 29,
    Missile2 = 30,  --限制角速度的追踪
}

-- 一定需要目标的轨迹
EnumBulletTracjectoryNeedTarget = {
    [EnumBulletTracjectory.Missile] = true,
    [EnumBulletTracjectory.ChasingMissile] = true,
    [EnumBulletTracjectory.ParabolaTarget] = true,
    [EnumBulletTracjectory.Chase] = true,
    [EnumBulletTracjectory.BezierCurveTarget] = true,
    [EnumBulletTracjectory.EffectBullet] = true,
    [EnumBulletTracjectory.RepeatHitTarget] = true,
    [EnumBulletTracjectory.ForwardChase2D] = true,
}

require "objects/character/BulletDataInc"
require "objects/character/BulletCommon"
