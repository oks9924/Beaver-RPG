# 기술 구조 (단계 0~4)

## 핵심 가정
- 엔진: **Godot 4.4.1 stable**, 타입 지정 GDScript. 서버와 클라이언트는 같은 프로젝트를 공유하되 다른 프로세스로 실행된다.
- 서버는 `dedicated_server` feature(export preset) 또는 `-- --server` 인자로 기동하며, 클라이언트 노드·렌더링에 의존하지 않는다.
- 통신: ENet 고수준 멀티플레이. 입력은 `unreliable_ordered`, 상태 전이·보상·오류는 `reliable`. 채널 분리는 후속 작업.
- 서버 시뮬레이션 30Hz, 전투 스냅샷 15Hz, 허브 스냅샷 10Hz (`data/rules.json` 에서 조절).
- 클라이언트는 입력 의도(이동 벡터·조준·버튼 비트)만 보낸다. 피해·체력·재화·위치·난수는 서버가 확정한다.

## 모듈 경계
| 모듈 | 경로 | 역할 |
|---|---|---|
| 프로토콜 | `shared/protocol.gd` | 버전, 메시지 종류, 오류 코드, 스냅샷 인덱스, 상태 enum |
| RPC 창구 | `shared/net.gd` | `/root/Net` 에서 `c_msg/c_input`(클→서), `s_msg/s_snapshot`(서→클) 만 정의 |
| 에셋 프레임 | `assets/asset_registry.gd` `get_frame_texture(id, i)` | 상태 선택형 시트(타일 변형·소품 상태·UI 레이어)에서 프레임 하나를 잘라 캐시. `WorldView._draw_frame` 과 `_prop_sprite` 가 쓴다 |
| 로그라이크 규칙 | `data/pacts.json`, `data/elites.json`, `rules.danger/director/rarity_weights/room_par` | 서약(열기)·정예 접두·시간 위험도·디렉터 증원·희귀도·시간 문. `ExpeditionInstance.effective_profile` 이 인원 → 난이도 → 서약 → 위험도 순으로 곱한다. 설계 근거는 `docs/roguelike_design.md` |
| 스냅샷 코덱 | `shared/snapshot_codec.gd` | 방 스냅샷을 고정 폭 정수(위치 0.25px·시간 0.05s·체력 0.25)로 인코딩. 4인 방 최대 약 530B 로 ENet MTU(1392B) 안. 허브 스냅샷·모르는 키는 `var_to_bytes` 로 그대로. `decode()` 가 같은 모양의 Dictionary 를 복원하므로 소비자는 인코딩을 모른다 |
| 콘텐츠 데이터 | `shared/content_db.gd`, `data/*.json` | 직업·적·방·인원 프로필·규칙. 숫자는 코드에 넣지 않는다 |
| 판정 수학 | `shared/sim/sim_rules.gd` | 이동·충돌·부채꼴/원 판정·피해 계산 순서. 서버 판정과 클라이언트 예측이 공유 |
| 에셋 | `assets/asset_registry.gd`, `assets/asset_manifest.json` | ID → 파일 해석, 임시/최종 분리 (docs/asset_plan.md) |
| 서버 진입 | `server/server_main.gd` | ENet 서버, 세션, 메시지 분배, 틱, 메트릭, 정상 종료 |
| 인증 | `server/auth_service.gd` | 서버 내부 계정, PBKDF2-HMAC-SHA256, 재접속 토큰(SHA-256 해시 저장) |
| 저장 | `server/store/*.gd` | `StoreBase` 인터페이스 + `JsonFileStore`(원자적 rename, .bak) |
| 공용 월드 | `server/world/hub_world.gd` | 서버 소유 마을, 접속자 0명이어도 유지, 통계·구조물 단계 |
| 원정 | `server/expedition/*.gd` | 모집판·인스턴스·전투방 시뮬레이션·유물/강화 합성(`run_mods.gd`)·보스 컨트롤러 3종 |
| 퀘스트·내실 | `server/quests.gd` | 퀘스트 상태·인연·비밀·결말 판정 (계정 progression 만 다룸) |
| 클라이언트 | `client/*.gd` | 접속/로그인/마을/원정 준비/전투 HUD/결과, 예측·보간, 봇 모드 |

## 원정 런 흐름 (단계 2)
- `ExpeditionInstance.start_run()` 이 지역 템플릿(`data/regions.json`)과 시드로 5층 경로를 만든다. 같은 시드·콘텐츠 버전이면 경로·보상 후보가 재현된다 (지도·보상·전투 난수 스트림 분리).
- `IN_ROOM → REWARD(3지선다, 25초) → ROUTE_VOTE(25초, 동률 시드 추첨) 또는 단일 노드 진입 → IN_ROOM | NODE_MENU(사건 투표·상점·휴식, 45초) → … → 보스 → RESULT`.
- 인스턴스는 보낼 메시지를 `outbox` 에 쌓고 `ServerMain._flush_outbox` 가 전송·위치 갱신·체크포인트 저장을 한다.
- 안전 지점(REWARD/ROUTE_VOTE/NODE_MENU)마다 `expeditions.json` 에 체크포인트를 저장한다. 서버 재시작 시 유예(600초) 안의 체크포인트를 복구하고, 전투 중 저장본은 복원하지 않는다(마지막 안전 지점부터).
- 안전 지점에서는 공개 파티에 새 멤버가 합류할 수 있다. 합류 묶음(완료 노드 2개당 유물 1개, 파티 평균 도토리)을 받고, 다음 방부터 N 을 재산정한다. 지나간 보상은 소급하지 않는다.
- 플레이어 수치 보정은 `RunMods.build()` 가 유물·강화·런 레벨·영구 보너스를 합쳐 `mods`(가산)와 `procs`(원인 ID·내부 대기시간) 로 만든다.

## 전투방 시스템 (단계 2)
- `CombatRoom` 은 플레이어·적(역할별 AI: approach/charger/ranged)·투사체·상호작용물(objects)·구조물·수문·목표(annihilate/hold_point/device/boss)를 갖는다.
- 상호작용은 공통 F 유지 규칙: 서버가 `interactable` 오브젝트의 `progress` 를 올리고 완료 시 종류별 처리. 담당자가 놓아도 진행도가 남는다(장치·갉기).
- 보스는 `BossIronclaw` 가 방에 부착되어 자체 상태 기계(추격·예고·공격·회복·경직·결박·탈피·노출)와 기믹 스케줄러를 돌린다. 기믹은 미체험 우선, 연속 재사용 금지, 양립 불가 조합 회피, 반복 상한 2.

## 단계 3·4 추가 구조
- **직업**: `data/classes.json` 의 스킬 `effect.type` 을 `CombatRoom._apply_cast` 가 해석한다 (dash, heavy_strike, whirl, heal_zone, root_zone, flood_zone, turret, jet, dam …). 직업 자원(열의·씨앗·수압)은 `p["resource"]` 하나로 스냅샷에 실린다. 스킬 변형·진화·특성·유물·시너지는 전부 `mods` 키(`RunMods.MOD_KEYS`)와 `procs` 로 합쳐지며, 코드는 `m.get("<slot>_<효과>")` 로만 읽는다.
- **지역·경로**: `ExpeditionInstance.build_route(seed)` 가 `regions.json` 의 `next` 를 따라 3지역 층을 이어 붙인다 (18층, 지역 보스 3). 노드마다 `region` 이 있어 지역 전환 시 적 풀·안내가 바뀐다. `tools/check_routes.gd` 가 시드 100개를 점검한다.
- **적 행동**: 역할 approach/charger/ranged/stationary/leaper/dummy + 정의 플래그(`armor_front`, `aura`, `summon`, `attack.combo`, `attack.on_hit`{slow/root/bleed}, `structure_dps_mult`). 정예는 방 정의 `elite` 로 첫 웨이브에 등장한다.
- **보스**: `BossIronclaw` 가 공통 컨트롤러다(패턴 모양 arc/line(돌진·즉발)/circle_at_target/leap/projectile_fan, 경직 게이지, 단계, 위험 구역, 운반 시스템, 스케줄러). `BossLanternToad`, `BossRootKing` 은 이를 상속해 `_mechanic_start/_step/_end/_object` 훅만 구현한다. 보스 id → `server/expedition/boss_<id>.gd`.
- **퀘스트**: 서버가 방·원정 결과와 마을 행동을 `QuestEngine.on_event` 이벤트로 바꾼다. 보상은 `reward_id` 로 한 번만 지급, 선택 임무 실패는 런 단위(`run_failed`)라 메인을 막지 않는다.
- **중단/이어하기**: 안전 지점에서 `EXPEDITION_PAUSE` → `paused` 체크포인트 저장, 멤버는 마을로. 모집판은 계정별로 만들어져 멤버에게만 `resume` 항목이 보이고, `BOARD_JOIN` 이 복귀 경로다.
- **난이도**: `rules.difficulties` 배율을 `ExpeditionInstance.effective_profile()` 이 인원 프로필에 곱한다. 보상·숙련 경험치도 배율을 따른다.
- **튜토리얼**: `tutorial` 원정은 방 하나(`rooms.json: tutorial`)이며 서버가 실제 행동(이동·처치·회피·스킬·갉기·건설·수문)으로 단계를 넘긴다.

## 상태 흐름
- 연결: `DISCONNECTED → CONNECTING → AUTHENTICATING(hello·로그인) → SYNCING → ONLINE`
- 위치: `HUB → PREPARING_EXPEDITION → IN_ROOM → RESULT → (IN_ROOM | HUB)`. `REWARD/ROUTE_VOTE/JOIN_PENDING/SUSPENDED` 는 enum 만 예약.
- 원정 인스턴스: `PREPARING → IN_ROOM → RESULT → (IN_ROOM | CLOSED)`. 전원 연결 끊김이면 `suspended` 로 틱을 멈춘다.

## 식별자와 저장 경계
| 데이터 | 소유 | 저장 | ID |
|---|---|---|---|
| 계정 | 서버 | `accounts.json` | 불변 `id`(16바이트 hex). 닉네임은 표시용, 대소문자 무시 유일 |
| 접속 세션 | 서버 메모리 | 없음 | ENet peer id(임시). 영구 식별자로 저장하지 않는다 |
| 공용 월드 | 서버 | `world.json` | `world_id`(최초 기동 시 생성, 설정으로 고정 가능) |
| 원정 인스턴스 | 서버 메모리 | 없음(단계 2에서 완료 방 체크포인트 저장 예정) | `exp_<seq>_<rand>` + 독립 시드 |
| 클라이언트 설정 | 클라이언트 | `user://client_settings.json` | 서버 목록·최근 접속·재접속 토큰·그래픽/조작 |

`schema_version` 을 계정·월드에 기록한다. 마이그레이션 코드는 아직 없다(스키마 1).

## 버전
- `PROTOCOL_VERSION=1`, `CONTENT_VERSION="0.2.0"`, `BUILD_VERSION="0.2.0-stage4"` (`shared/protocol.gd`). 콘텐츠 버전이 바뀌면 이전 체크포인트는 버린다.
- hello 에서 프로토콜·콘텐츠 버전이 다르면 게임 상태를 보내기 전에 `VERSION_MISMATCH` 와 요구 버전, 업데이트 URL 을 보내고 끊는다.

## 인원별 프로필
`data/party_scaling.json` 의 `PartyScalingProfile` 을 방 시작 시 연결된 인원 N(1~4)으로 고정한다. 다운·이탈로 즉시 낮추지 않고, 이미 생성된 적의 체력을 바꾸지 않는다. `A`(행동 가능한 연결 인원)는 전투방이 별도로 추적한다.

## 정원 정책
- `max_online_players`: 인증된 세션 수. 초과 시 로그인 단계에서 `SERVER_FULL`. 유예 중인 원정 슬롯을 가진 계정(재접속)은 정원과 무관하게 입장한다.
- `max_active_expeditions`: 준비 중·진행 중 인스턴스 합. 초과 시 `EXPEDITION_LIMIT`.
- `max_party_size=4` 고정. 5번째 참가는 `PARTY_FULL`. 유예 시간(120초) 동안 끊긴 멤버의 슬롯도 정원에 포함한다.
- 같은 계정 동시 로그인은 `ALREADY_ONLINE` 으로 거절한다(기존 세션 유지).

## 알려진 제한 (단계 1)
- ENet 전송에 DTLS 가 켜져 있지 않다. 비밀번호·토큰은 현재 평문 UDP 로 전송된다. **인터넷 공개 운영 전에** DTLS(ENetConnection.dtls_client/server + 인증서) 또는 별도 HTTPS 인증 경로가 필요하다.
- 저장소는 JSON 파일이다. 트랜잭션은 "단일 프로세스 + 원자적 파일 교체" 수준이며, SQLite(GDExtension) 어댑터는 `StoreBase` 인터페이스로 교체 예정.
- 전투 중 상태는 저장하지 않는다. 서버 재시작 시 마지막 안전 지점 체크포인트로 복구되며, 진행 중이던 전투는 다시 한다.
- 채팅 뮤트·운영자 차단, 운영 권한 인증은 미구현(속도 제한만 있음).
- Godot 는 SIGTERM 에 종료 훅을 부르지 않는다. 정상 종료는 `STOP` 파일(`scripts/stop_server.sh`) 을 쓴다. 강제 종료돼도 계정·월드 파일은 변경 시마다 즉시 원자적으로 저장되어 손실이 없다.
