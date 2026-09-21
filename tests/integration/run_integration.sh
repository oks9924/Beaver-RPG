#!/usr/bin/env bash
# 다중 프로세스 통합 테스트: 전용 서버 1개 + headless 클라이언트(봇) 여러 개.
# 검증: NET-01(서버 정원/원정 정원), NET-03(재접속), NET-04(빈 서버 접속·서버 재시작), NET-05(원정 2개 격리),
#       AUTH-01(잘못된 비밀번호·중복 로그인·버전 불일치), RUN-01(원정 한 사이클), SAVE-02(재시작 후 월드·계정 유지)
# 사용: tests/integration/run_integration.sh [godot 실행 파일]
set -u
GODOT="${1:-${GODOT:-godot}}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/tests/out/integration"
PORT=7811
rm -rf "$OUT"; mkdir -p "$OUT/data"
cd "$ROOT"
cat > "$OUT/server_config.json" <<CFG
{"port": $PORT, "max_online_players": 6, "max_active_expeditions": 2, "allow_registration": true, "data_dir": "$OUT/data", "log_level": "info", "metrics_interval_sec": 10, "password_iterations": 2000, "debug_route_layers": 2}
CFG

start_server() {
  "$GODOT" --headless --path "$ROOT" -- --server --config="$OUT/server_config.json" >> "$OUT/server.log" 2>&1 &
  SERVER_PID=$!
  for i in $(seq 1 40); do
    grep -q "listening on" "$OUT/server.log" 2>/dev/null && grep -q "hub '" "$OUT/server.log" && break
    sleep 0.25
  done
  echo "[it] server pid=$SERVER_PID"
}
stop_server() {
  kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; echo "[it] server stopped"
}
PIDS=()
bot() { # name scenario args...  (백그라운드로 띄우고 PID 를 PIDS 에 모은다)
  local name="$1"; shift
  "$GODOT" --headless --path "$ROOT" -- --bot="$1" --nick="$name" --addr=127.0.0.1:$PORT --out="$OUT/$name.json" "${@:2}" > "$OUT/$name.log" 2>&1 &
  PIDS+=($!)
}
wait_all() { for p in "${PIDS[@]}"; do wait "$p" 2>/dev/null; done; PIDS=(); }

echo "[it] === Phase 1: two isolated 2-player expeditions (NET-05, RUN-01) ==="
start_server
bot a1 expedition --create --starter --party=2 --timeout=200
bot b1 expedition --create --starter --party=2 --timeout=200
sleep 1.5
bot a2 expedition --join=host:a1 --timeout=200
bot b2 expedition --join=host:b1 --timeout=200
wait_all

echo "[it] === Phase 2: 4-player party, 5th client hub-only + PARTY_FULL, 7th SERVER_FULL, auth negatives, reconnect (NET-01, NET-03, AUTH-01) ==="
bot c1 expedition --create --starter --party=4 --timeout=240
sleep 1.0
bot c2 expedition --join=host:c1 --timeout=240
bot c3 expedition --join=host:c1 --timeout=240
bot c4 expedition --join=host:c1 --drop=4 --timeout=240
sleep 1.0
bot c5 hub_only --wait=6 --join=host:c1 --expect_join_error=PARTY_FULL --timeout=40
bot c6 hub_only --wait=10 --timeout=40
sleep 3
bot c7 hub_only --expect_auth_error=SERVER_FULL --timeout=30
bot dup expedition --nick=c1 --login_only --password=botpass1 --expect_auth_error=ALREADY_ONLINE --timeout=30
bot badpw persist_check --nick=a1 --login_only --password=wrongpass --expect_auth_error=BAD_CREDENTIALS --timeout=30
bot badver hub_only --proto=99 --expect_hello_error=VERSION_MISMATCH --timeout=30
wait_all

echo "[it] === Phase 3: empty server accepts logins; persistence across restart (NET-04, SAVE-02) ==="
bot p_before persist_check --nick=a1 --login_only --timeout=30; wait_all
stop_server
start_server
bot p_after persist_check --nick=a1 --login_only --timeout=30; wait_all
bot p_c4 persist_check --nick=c4 --login_only --timeout=30; wait_all
bot rc hub_only --recreate --timeout=40; wait_all
stop_server

python3 - "$OUT" <<'PY'
import json, sys, os
out = sys.argv[1]
def load(n):
    p = os.path.join(out, n + ".json")
    return json.load(open(p)) if os.path.exists(p) else {"ok": False, "errors": ["no output file"], "events": {}}
fails = []
def check(cond, msg):
    print(("  PASS " if cond else "  FAIL ") + msg)
    if not cond: fails.append(msg)
a1, a2, b1, b2 = load("a1"), load("a2"), load("b1"), load("b2")
for n, d in [("a1", a1), ("a2", a2), ("b1", b1), ("b2", b2)]:
    check(d.get("ok"), f"{n} completed expedition flow: errors={d.get('errors')}")
    check(d.get("room_n") == 2, f"{n} room N == 2 (got {d.get('room_n')})")
    check("room_result" in d, f"{n} received run result")
    check(d.get("events", {}).get("reward_picks", 0) >= 1, f"{n} picked a room reward")
check(a1.get("room_seed") != b1.get("room_seed"), "NET-05 two expeditions have different seeds")
check(a1.get("room_seed") == a2.get("room_seed") and b1.get("room_seed") == b2.get("room_seed"), "party members share the same room seed")
check(a1.get("events", {}).get("door_travels", 0) >= 1 and a2.get("events", {}).get("door_travels", 0) >= 1, "party walked through a dungeon door after the first room")
ka = a1.get("events", {}).get("kills", 0) + a2.get("events", {}).get("kills", 0)
kb = b1.get("events", {}).get("kills", 0) + b2.get("events", {}).get("kills", 0)
check(ka > 0 and kb > 0, f"RUN-01 both parties killed enemies (A={ka}, B={kb})")
sa, sb = a1.get("room_result", {}).get("stats", {}), b1.get("room_result", {}).get("stats", {})
rsa, rsb = a1.get("room_result", {}).get("run_stats", {}), b1.get("room_result", {}).get("run_stats", {})
check(rsa.get("enemies_killed") == ka, f"NET-05 party A run result counts only its own kills (result={rsa.get('enemies_killed')}, bots={ka})")
check(rsb.get("enemies_killed") == kb, f"NET-05 party B run result counts only its own kills (result={rsb.get('enemies_killed')}, bots={kb})")
c = {n: load(n) for n in ["c1", "c2", "c3", "c4", "c5", "c6", "c7", "dup", "badpw", "badver"]}
for n in ["c1", "c2", "c3", "c4"]:
    check(c[n].get("ok"), f"{n} completed 4-player expedition: errors={c[n].get('errors')}")
    check(c[n].get("room_n") == 4, f"{n} room N == 4 (got {c[n].get('room_n')})")
seeds = {c[n].get("room_seed") for n in ["c1", "c2", "c3", "c4"]}
check(len(seeds) == 1, f"NET-01 all 4 clients saw the same expedition seed {seeds}")
check(c["c5"].get("ok") and c["c5"].get("expected_error_seen"), f"NET-01 5th client entered hub but was rejected from the full party: {c['c5'].get('errors')} {c['c5'].get('last_error')}")
check(c["c6"].get("ok") and c["c6"]["events"].get("enter_hub", 0) >= 1, f"5th/6th clients can use the hub while a 4-player expedition runs: {c['c6'].get('errors')}")
check(c["c7"].get("ok"), f"NET-01 7th login rejected with SERVER_FULL (max_online=6): {c['c7'].get('auth')}")
check(c["dup"].get("ok"), f"AUTH-01 duplicate login rejected: {c['dup'].get('auth')}")
check(c["badpw"].get("ok"), f"AUTH-01 wrong password rejected: {c['badpw'].get('auth')}")
check(c["badver"].get("ok"), f"CLIENT-01 version mismatch rejected before game state: {c['badver'].get('hello')}")
check(c["c4"]["events"].get("reconnected_to_room", 0) >= 1 and c["c4"].get("reconnect_party_size") == 4, f"NET-03 dropped client rejoined the same expedition slot (party size {c['c4'].get('reconnect_party_size')})")
pb, pa, pc4 = load("p_before"), load("p_after"), load("p_c4")
check(pb.get("ok") and pb["events"].get("enter_hub", 0) == 1, "NET-04 login works with 0 players online after all clients left")
rc = load("rc")
check(rc.get("ok") and rc["events"].get("recreate_ok", 0) == 1, f"HUB-01 create → leave party → create again works without BAD_STATE: {rc.get('errors')} {rc.get('last_error')}")
check(pa.get("ok"), f"SAVE-02 login works after server restart: {pa.get('errors')}")
wb, wa = pb.get("hub_info", {}), pa.get("hub_info", {})
check(wb.get("world_id") and wb.get("world_id") == wa.get("world_id"), f"SAVE-02 same world id after restart ({wb.get('world_id')} -> {wa.get('world_id')})")
check(wa.get("boot_count", 0) == wb.get("boot_count", 0) + 1, f"SAVE-02 boot count incremented ({wb.get('boot_count')} -> {wa.get('boot_count')})")
check(wa.get("total_expeditions") == wb.get("total_expeditions") and wb.get("total_expeditions", 0) >= 3, f"SAVE-02 hub counters persisted (expeditions {wb.get('total_expeditions')} -> {wa.get('total_expeditions')})")
sb_, sa_ = pb.get("account", {}).get("stats", {}), pa.get("account", {}).get("stats", {})
check(sb_.get("kills") == sa_.get("kills") and sb_.get("rooms_cleared", 0) + sb_.get("wipes", 0) >= 1, f"SAVE-02 account stats persisted across restart ({sb_} -> {sa_})")
check(pa.get("account", {}).get("id") == a1.get("account_id"), "SAVE-02 same immutable account id after restart")
check(pc4.get("ok") and pc4.get("account", {}).get("id") == c["c4"].get("account_id"), "SAVE-02 reconnected player's account persisted")
print(f"\nintegration: {len(fails)} failures")
sys.exit(1 if fails else 0)
PY
RC=$?
echo "[it] server log summary:"; grep -E "WARN|ERROR|SCRIPT" "$OUT/server.log" | head -20
exit $RC
