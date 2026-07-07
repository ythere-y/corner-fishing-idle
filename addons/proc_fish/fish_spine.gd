class_name ProcFishSpine
extends RefCounted
## 脊椎链（2D chain）：一串关节 + 角度约束求解，程序化鱼/蛇/蜥蜴的通用骨架。
## 移植自 .reference/animal-proc-anim 的 Chain.pde + Util.pde（constrainAngle / relativeAngleDiff / simplifyAngle）。
## 纯几何、零业务：头部去追一个目标点 target，其余关节按 angle_constraint 柔性跟随。
## 由 ProcFish 持有；绘制时读 joints / angles 生成鱼身多边形。

var joints: PackedVector2Array = PackedVector2Array()   # 关节世界坐标，joints[0] = 头
var angles: PackedFloat32Array = PackedFloat32Array()   # 每个关节朝向（弧度），angles[0] = 头朝向
var link_size: float = 32.0                             # 相邻关节间距
var angle_constraint: float = PI / 8.0                  # 相邻关节最大转角差：小=僵硬(大鱼)，大=灵活(小鱼)


## origin=初始头位置；joint_count>=2；link=关节间距；constraint=每节最大转角（默认 TAU 即不约束）。
func _init(origin: Vector2, joint_count: int, link: float, constraint: float = TAU) -> void:
	link_size = link
	angle_constraint = constraint
	joints.resize(0)
	angles.resize(0)
	joints.append(origin)
	angles.append(0.0)
	# 初始沿 +Y 方向直直排开（与参考一致；第一帧 resolve 后即贴合目标）
	for i in range(1, joint_count):
		joints.append(joints[i - 1] + Vector2(0.0, link_size))
		angles.append(0.0)


func size() -> int:
	return joints.size()


## 头追 pos，其余关节逐节角度约束跟随（参考 Chain.resolve）。
func resolve(pos: Vector2) -> void:
	angles[0] = (pos - joints[0]).angle()
	joints[0] = pos
	for i in range(1, joints.size()):
		var cur_angle := (joints[i - 1] - joints[i]).angle()
		angles[i] = _constrain_angle(cur_angle, angles[i - 1], angle_constraint)
		joints[i] = joints[i - 1] - Vector2.from_angle(angles[i]) * link_size


# —— 角度工具（移植 Util.pde）——

## 把 angle 收进 anchor ± constraint 范围内。
static func _constrain_angle(angle: float, anchor: float, constraint: float) -> float:
	var diff := _relative_angle_diff(angle, anchor)
	if absf(diff) <= constraint:
		return _simplify_angle(angle)
	if diff > constraint:
		return _simplify_angle(anchor - constraint)
	return _simplify_angle(anchor + constraint)


## 从 angle 转到 anchor 需要的有向弧度差；把坐标空间旋到 anchor=PI 避开 0/2π 接缝。
static func _relative_angle_diff(angle: float, anchor: float) -> float:
	angle = _simplify_angle(angle + PI - anchor)
	return PI - angle


## 收进 [0, 2π)。
static func _simplify_angle(angle: float) -> float:
	angle = fmod(angle, TAU)
	if angle < 0.0:
		angle += TAU
	return angle
