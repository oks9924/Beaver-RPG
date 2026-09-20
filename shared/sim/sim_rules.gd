class_name SimRules
## 서버 판정과 클라이언트 예측이 공유하는 순수 수학 규칙. 노드·렌더링에 의존하지 않는다.


static func move(pos: Vector2, dir: Vector2, speed: float, dt: float, bounds: Rect2, radius: float, obstacles: Array) -> Vector2:
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	var next := pos + dir * speed * dt
	next.x = clampf(next.x, bounds.position.x + radius, bounds.end.x - radius)
	next.y = clampf(next.y, bounds.position.y + radius, bounds.end.y - radius)
	for ob: Dictionary in obstacles:
		var c := Vector2(float(ob.get("x", 0)), float(ob.get("y", 0)))
		var r := float(ob.get("r", 0)) + radius
		var d := next - c
		if d.length_squared() < r * r:
			# 중심을 지나쳐 반대편으로 뚫고 나가지 않도록, 출발점이 있던 쪽으로 밀어낸다.
			if d.dot(pos - c) <= 0.0:
				d = pos - c
			if d.length_squared() < 0.000001:
				d = Vector2.RIGHT
			next = c + d.normalized() * r
	return next


## 부채꼴 판정: origin 에서 facing 방향, 반경 range, 각도 angle_deg 안에 target 원이 걸치는가.
static func arc_hit(origin: Vector2, facing: Vector2, range_: float, angle_deg: float, target: Vector2, target_radius: float) -> bool:
	var d := target - origin
	var dist := d.length()
	if dist - target_radius > range_:
		return false
	if dist < target_radius:
		return true
	var ang := rad_to_deg(absf(facing.angle_to(d)))
	var extra := rad_to_deg(asin(clampf(target_radius / maxf(dist, 0.001), 0.0, 1.0)))
	return ang <= angle_deg * 0.5 + extra


static func circle_hit(center: Vector2, radius: float, target: Vector2, target_radius: float) -> bool:
	return center.distance_to(target) <= radius + target_radius


## 피해 계산 순서 (7절): 기본 피해 × 스킬 계수 → 가산 강화 → 치명타 → 방어 → 취약.
## 툴팁과 코드가 같은 순서를 쓰도록 이 함수 하나로 통일한다.
static func damage(base: float, coef: float, flat_add: float, crit_mult: float, defense_reduction: float, vulnerability: float, caps: Dictionary) -> float:
	var dr_cap := float(caps.get("damage_reduction_max", 0.6))
	var v := base * coef + flat_add
	v *= maxf(crit_mult, 1.0)
	v *= 1.0 - clampf(defense_reduction, 0.0, dr_cap)
	v *= 1.0 + maxf(vulnerability, 0.0)
	return maxf(v, 0.0)


## 전방 방어(통나무 방패)가 적용되는지: 공격자가 방어자의 정면 arc 안에 있는가.
static func in_front_arc(defender_pos: Vector2, defender_facing: Vector2, attacker_pos: Vector2, arc_deg: float) -> bool:
	var d := attacker_pos - defender_pos
	if d.length_squared() < 0.0001:
		return true
	return rad_to_deg(absf(defender_facing.angle_to(d))) <= arc_deg * 0.5


static func facing_from(aim: Vector2, fallback: Vector2) -> Vector2:
	if aim.length_squared() > 0.0001:
		return aim.normalized()
	return fallback


## 4방향 애니메이션 행 선택: down=0, up=1, left=2, right=3
static func dir_row(facing: Vector2) -> int:
	if absf(facing.x) > absf(facing.y):
		return 3 if facing.x > 0 else 2
	return 0 if facing.y >= 0 else 1
