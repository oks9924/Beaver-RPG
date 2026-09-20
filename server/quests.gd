class_name QuestEngine
extends RefCounted
## 퀘스트·인연·비밀·결말 진행 (13절). 계정 progression 안의 순수 데이터만 다루며 서버가 이벤트를 넣는다.
## 보상은 reward_id 로 한 번만 지급되고(재접속·중복 요청 무관), 선택 임무 실패는 메인 진행을 막지 않는다.

static func ensure(prog: Dictionary) -> void:
	for k in ["quests", "npc_bonds", "unlocks", "build_records", "secrets_found", "endings_seen", "rewards_claimed"]:
		if not prog.has(k):
			prog[k] = {} if k in ["quests", "npc_bonds"] else []
	refresh_availability(prog)


static func _defs() -> Array:
	return ContentDB.quests.get("quests", [])


static func get_def(qid: String) -> Dictionary:
	for q: Dictionary in _defs():
		if String(q.get("id", "")) == qid:
			return q
	return {}


## 선행 조건이 끝난 퀘스트를 'available' 로, auto_accept 는 바로 'active' 로
static func refresh_availability(prog: Dictionary) -> void:
	var qs: Dictionary = prog["quests"]
	for q: Dictionary in _defs():
		var qid := String(q["id"])
		if qs.has(qid):
			continue
		var ok := true
		for req: String in q.get("requires", []):
			if String(qs.get(req, {}).get("state", "")) != "done":
				ok = false
		if ok:
			qs[qid] = {"state": "active" if bool(q.get("auto_accept", false)) else "available", "progress": 0, "run_progress": 0}


static func on_run_start(prog: Dictionary) -> void:
	ensure(prog)
	for qid: String in prog["quests"].keys():
		prog["quests"][qid]["run_progress"] = 0
		prog["quests"][qid].erase("run_failed")


static func accept(prog: Dictionary, qid: String) -> bool:
	ensure(prog)
	var st: Dictionary = prog["quests"].get(qid, {})
	if st.is_empty() or String(st.get("state", "")) != "available":
		return false
	st["state"] = "active"
	return true


## 이벤트 → 활성 퀘스트 진행. ev: {"type", "target"(선택), "count"(증가량 또는 absolute 값), "absolute"(bool)}
## 돌려주는 값: 이번 이벤트로 목표를 달성한 퀘스트 id 목록
static func on_event(prog: Dictionary, ev: Dictionary) -> Array:
	ensure(prog)
	var completed: Array = []
	var etype := String(ev.get("type", ""))
	for q: Dictionary in _defs():
		var qid := String(q["id"])
		var st: Dictionary = prog["quests"].get(qid, {})
		if st.is_empty() or String(st.get("state", "")) != "active":
			continue
		var obj: Dictionary = q.get("objective", {})
		if String(obj.get("type", "")) != etype:
			continue
		var target := String(obj.get("target", ""))
		if target != "" and not String(ev.get("target", "")).begins_with(target):
			continue
		if bool(st.get("run_failed", false)):
			continue
		var per_run := bool(obj.get("per_run", false))
		var key := "run_progress" if per_run else "progress"
		if bool(ev.get("absolute", false)):
			st[key] = maxi(int(st.get(key, 0)), int(ev.get("count", 0)))
		else:
			st[key] = int(st.get(key, 0)) + int(ev.get("count", 1))
		if int(st[key]) >= int(obj.get("count", 1)):
			st["state"] = "complete"
			completed.append(qid)
	return completed


static func fail_for_run(prog: Dictionary, qid: String) -> void:
	ensure(prog)
	var st: Dictionary = prog["quests"].get(qid, {})
	if not st.is_empty() and String(st.get("state", "")) == "active":
		st["run_failed"] = true


## 보상 수령: 한 번만. 기억 조각·인연·해금을 progression 에 반영하고 지급 내역을 돌려준다.
static func claim(prog: Dictionary, qid: String) -> Dictionary:
	ensure(prog)
	var q := get_def(qid)
	var st: Dictionary = prog["quests"].get(qid, {})
	if q.is_empty() or st.is_empty() or String(st.get("state", "")) != "complete":
		return {"ok": false, "error": "NOT_COMPLETE"}
	var rid := String(q.get("reward_id", "reward:" + qid))
	if (prog["rewards_claimed"] as Array).has(rid):
		st["state"] = "done"
		refresh_availability(prog)
		return {"ok": false, "error": "ALREADY_CLAIMED"}
	var reward: Dictionary = q.get("reward", {})
	prog["memory_shards"] = int(prog.get("memory_shards", 0)) + int(reward.get("memory_shards", 0))
	for npc: String in reward.get("bond", {}).keys():
		add_bond(prog, npc, int(reward["bond"][npc]))
	if reward.has("unlock") and not (prog["unlocks"] as Array).has(String(reward["unlock"])):
		prog["unlocks"].append(String(reward["unlock"]))
	prog["rewards_claimed"].append(rid)
	st["state"] = "done"
	refresh_availability(prog)
	return {"ok": true, "reward": reward, "quest": q}


static func add_bond(prog: Dictionary, npc: String, n: int) -> void:
	ensure(prog)
	prog["npc_bonds"][npc] = int(prog["npc_bonds"].get(npc, 0)) + n


static func bond_level(prog: Dictionary, npc: String) -> int:
	var pts := int(prog.get("npc_bonds", {}).get(npc, 0))
	var table: Array = ContentDB.rule("bond_levels", [0, 2, 5, 9])
	var lv := 0
	for i in table.size():
		if pts >= int(table[i]):
			lv = i
	return lv


## NPC 대화창용: 그 NPC 가 주는 퀘스트와 상태
static func npc_view(prog: Dictionary, npc: String) -> Array:
	ensure(prog)
	var out: Array = []
	for q: Dictionary in _defs():
		if String(q.get("giver", "")) != npc:
			continue
		var st: Dictionary = prog["quests"].get(String(q["id"]), {})
		if st.is_empty():
			continue   # 선행 미완
		var obj: Dictionary = q.get("objective", {})
		var prog_n := int(st.get("run_progress", 0)) if bool(obj.get("per_run", false)) else int(st.get("progress", 0))
		out.append({"id": q["id"], "kind": q.get("kind", ""), "name_ko": q.get("name_ko", ""), "desc_ko": q.get("desc_ko", ""), "state": st.get("state", ""), "progress": prog_n, "count": int(obj.get("count", 1)), "reward": q.get("reward", {}), "fail_ko": q.get("fail_ko", "")})
	return out


static func summary(prog: Dictionary) -> Dictionary:
	ensure(prog)
	var active: Array = []
	var complete: Array = []
	var done := 0
	for q: Dictionary in _defs():
		var st: Dictionary = prog["quests"].get(String(q["id"]), {})
		match String(st.get("state", "")):
			"active": active.append({"id": q["id"], "name_ko": q["name_ko"], "progress": int(st.get("run_progress", 0)) if bool(q.get("objective", {}).get("per_run", false)) else int(st.get("progress", 0)), "count": int(q.get("objective", {}).get("count", 1)), "giver": q.get("giver", "")})
			"complete": complete.append({"id": q["id"], "name_ko": q["name_ko"], "giver": q.get("giver", "")})
			"done": done += 1
	return {"active": active, "complete": complete, "done": done, "total": _defs().size()}


## 결말 판정 (13절): 정화 결말은 기억 잔향·비밀 조건을 모두 만족할 때
static func ending_for(prog: Dictionary, run_stats: Dictionary) -> Dictionary:
	var endings: Dictionary = ContentDB.rule("endings", {})
	var pur: Dictionary = endings.get("purified", {})
	var req: Dictionary = pur.get("requires", {})
	if not pur.is_empty() and int(run_stats.get("memories", 0)) >= int(req.get("memories_in_run", 99)) and (prog.get("secrets_found", []) as Array).size() >= int(req.get("secrets_total", 99)):
		return pur
	return endings.get("base", {"id": "base", "name_ko": "기본 결말", "text_ko": ""})
