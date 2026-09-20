# 꼬리원정대: 검은 물결 (Tail Expedition: Black Tide)

비버 주인공의 **1~4인 온라인 협동 로그라이크 RPG**. 설치형 PC 클라이언트가 상시 실행되는 **전용 서버**에 접속한다. 특정 플레이어의 초대나 접속에 의존하지 않고, 공용 마을은 서버가 소유·저장한다.

현재 상태: **단계 0~4 구현 (v0.2.0)** — 전용 서버·영구 월드, 5직업, 3지역·보스 3종(독립 기믹 15개 × 1~4인 프로필), 일반 적 12종, 유물 36개, NPC 6명·퀘스트 15개, 마을 시설 5개, 난이도·접근성·튜토리얼·중단/이어하기. **단계 5(실제 친구 4대 PC 검증)는 사용자가 수행**해야 하며 절차는 `docs/playtest_checklist.md`. 에셋팩 v1·v2(캐릭터·적·보스·기믹 장치)를 연결했고 타일·VFX·UI·아이콘·효과음은 임시 도형(교체 요청서 `docs/asset_request_v3.md`). 범위와 제한은 아래와 `docs/verification.md`.

![전투 화면](docs/screenshots/room_combat.png)

## 구성
```
project.godot / main.tscn / boot.gd   서버·클라이언트·도구 공용 진입점
shared/      프로토콜, RPC 창구, 콘텐츠 DB, 판정 수학
server/      전용 서버 (인증, JSON 저장소, 공용 마을, 원정 인스턴스, 전투방 시뮬레이션)
client/      설치형 클라이언트 (접속/로그인/마을/원정 모집판/전투 HUD/결과, 예측·보간, 봇 모드)
data/        직업·적·방·인원 프로필·규칙 JSON (숫자는 여기서만 조절)
assets/      asset_manifest.json(ID↔파일), asset_registry.gd, placeholders/(임시), fonts/(Noto Sans KR, OFL)
tools/       lint_all, run_tests, test_boss, check_assets, check_routes, gen_placeholders, import_asset_pack
tests/       integration/run_integration.sh (서버 + 다중 headless 클라이언트), run_party_matrix.sh (조합 검증), run_export_smoke.sh
scripts/     run_server.sh, run_client.sh, build.sh, deploy.sh, stop_server.sh, backup/restore, systemd 유닛
docs/        architecture.md, asset_plan.md, asset_request_v3.md, verification.md, deploy.md, playtest_checklist.md, playtest_notes.md
```

## 요구 사항
- Godot **4.4.1 stable** (편집기 바이너리). 빌드에는 같은 버전의 export templates.
- 서버: Windows 또는 Linux(x86_64). 클라이언트: Windows(주 대상), Linux.

## 개발용 실행
```bash
# 최초 1회: 클래스 캐시·임포트
godot --headless --path . --import
# 전용 서버 (기본 포트 7777, 데이터는 user://server_data)
scripts/run_server.sh --port=7777 --data-dir=./server_data --log-level=info
# 클라이언트 (창 필요). 접속 화면에서 127.0.0.1:7777 입력 또는:
scripts/run_client.sh --connect=127.0.0.1:7777
```
같은 PC 에서 클라이언트를 여러 개 띄워 다른 닉네임으로 가입하면 4인 원정을 시험할 수 있다.

## 플레이 흐름
서버 주소 입력 → 계정 생성/로그인(서버 내부 계정) → 공용 마을(WASD 이동, F 로 NPC 대화·퀘스트, 채팅, 시설 복구, 숙련 특성 선택) → 원정 모집판에서 직업·난이도를 고르고 **새 원정 만들기** 또는 **참가**(최대 4명, 혼자도 가능, 안전 지점 중도 합류) → 준비 완료 → 출정. 처음이면 **튜토리얼** 버튼(혼자, 5분).

원정(3지역 18층): 버들강 하류 → 검은 수액 습지 → 고대 뿌리댐. 전투방 → **보상 3지선다**(유물·스킬 강화·진화) → **경로 투표**(전투/정예/호위/사건/상점/휴식) → … → 지역 보스 → 다음 지역 → … → 뿌리왕 → 결말(기본/정화). 방 목표는 섬멸·거점·장치·호위 + 정예전. 완료한 방마다 체크포인트가 저장되고, 안전 지점에서 **원정 중단**하면 모집판의 **이어하기**로 같은 자리에서 계속한다.

직업 5종(중복 가능): 수호목수(보호), 톱니전사(연타·열의), 솔방울사수(원거리·표식), 수액주술사(회복·속박·씨앗), 물길공학자(포탑·급류·댐·수압). 스킬마다 변형 2개와 런 중 진화, 직업 숙련 1~10 과 대체 특성 3개.

보스 3종(각각 기본 패턴 4개 + 독립 기믹 5개, 1~4인 프로필): 철턱 가재(IC-01~05), 늪등불 두꺼비(TF-01~05: 등불·씨앗 운반·포자 결절·공명목·반딧불), 뿌리왕(RK-01~05: 균열·수로 조각·기생 뿌리·기억 잔향·압력 밸브). 데이터는 `data/bosses.json`, 컨트롤러는 `server/expedition/boss_*.gd`.

조작: WASD 이동, 마우스 조준, 좌클릭 기본 공격, Space 회피, Q/E/R 스킬, F 상호작용(구조·갉기·장치·수문·기믹·NPC), B 건설 / G 건설 종류, 1 회복, 중클릭 핑, Tab 큰 지도, Enter 채팅, Esc 설정(텍스트 크기·음량·흔들림·섬광 감소·키 재설정), F3 개발 화면, F11 전체화면.

## 빌드·배포
```bash
scripts/build.sh all      # build/windows/TailExpedition.exe, build/linux-server/, build/windows-server/
```
GitHub Actions(`.github/workflows/build.yml`)가 push 마다 린트·에셋 검수·단위·통합 테스트를 돌리고, `v*` 태그에서 Windows 클라이언트 zip 과 서버 묶음을 Release 로 올린다. 서버 설치·운영은 `docs/deploy.md`.

## 테스트
```bash
# 화면 캡처 데모 (가상 디스플레이에서도 가능): 자동 가입→출정→결과 후 종료
xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility -- --connect=127.0.0.1:7777 --demo=demo1 --shots=./shots
godot --headless --path . -- --tool=lint_all
godot --headless --path . -- --tool=check_assets
godot --headless --path . -- --tool=run_tests        # 단위 489개
godot --headless --path . -- --tool=test_boss        # 보스 3종 × 기믹 5개 × 인원 1~4 (420개)
godot --headless --path . -- --tool=check_routes     # 시드 100개 경로 점검 (GEN-01)
tests/integration/run_integration.sh /path/to/godot  # 서버 + 다중 클라이언트 (42개)
tests/integration/run_party_matrix.sh /path/to/godot # 동일 직업 4인·혼합·1인 조합 봇 완주
tests/integration/run_export_smoke.sh /path/to/godot # export 실행 파일 왕복
# 보스 연습: 서버를 --boss=lantern_toad 로 띄우면 모든 원정이 그 보스방 하나가 된다
```

## 에셋 교체
모든 코드는 에셋 **ID** 만 참조한다. 팩 원본은 GitHub Release `assets-raw-v1` 에 있고 `tools/import_asset_pack.gd` 가 시트를 합성한다. 최종 파일을 같은 규격으로 만들어 `asset_manifest.json` 의 `final_path` 에 연결하거나, 배포본 실행 파일 옆 `asset_overrides/<id>.png` 로 두면 재빌드 없이 교체된다. 절차와 규격은 `docs/asset_plan.md`.

## 구현된 것 / 아닌 것
구현(단계 0·1): 전용 서버·설정, 주소 접속·버전 검사, 계정·재접속 토큰, 서버 정원과 원정 정원 분리, 접속자 0명·재시작 후에도 유지되는 공용 마을, 모집판(1~4인), 인원별 프로필 고정, 서버 판정 전투, 다운·구조·전멸, 끊김 유예와 슬롯 복귀, 영구 기록, 에셋 ID 분리, 테스트·export·CI·운영 스크립트.

구현(단계 2): 원정 루프(보상·투표·사건·상점·휴식·체크포인트·안전 지점 합류), 갉기·건설·수문, 철턱 가재(패턴 4 + 기믹 5), 마을 복구·숙련·도감, 원정 2개 동시 격리, 에셋팩 v1·v2 연결.

구현(단계 3): 5직업(각 기본 공격·패시브·Q/E/R), 스킬 변형 2개씩과 진화, 숙련 1~10·대체 특성, 유물 세트 시너지, 건설 3종, 보호막·회복·포탑·투사체 상한, 조합 검증 스크립트, 스냅샷 크기 측정.

구현(단계 4): 3지역·방 유형 4종·정예방·호위, 일반 적 12종, 보스 3종·기믹 15개(60개 인원 프로필은 데이터 검사 + 스크립트 수행), 유물 36개, NPC 6명·퀘스트 15개(메인 3·선택 8·해금 4), 마을 시설 5개×3단계·통합 상한, 지역 비밀 9개, 결말 2종, 빌드 기록, 난이도 3단계, 설정·접근성·키 재설정, 원정 중단/이어하기, 튜토리얼, 미니맵·지도·핑.

미구현·미검증: **실제 4대 PC 친구 검증(단계 5)**, DTLS 암호화, SQLite 저장소, BGM·최종 타일/VFX/UI 에셋(요청서 참고), 원정 분량·밸런스의 실측(봇 기준만), 아군 이펙트 상세 튜닝. 기획서의 완료 판정 표(20절) 중 사람이 해야 하는 항목은 `docs/playtest_checklist.md` 에 정리했다.
