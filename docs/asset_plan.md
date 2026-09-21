# 에셋 계획과 교체 절차

## 원칙: ID 와 파일의 분리
- 코드·데이터는 **에셋 ID** 만 참조한다 (`char.guardian.walk`, `enemy.sap_snail.attack`, `tile.willow.ground`, `icon.skill.guardian.q`, `sfx.hammer_hit`, `font.ui.main` …).
- `assets/asset_manifest.json` 이 ID → 파일 경로·규격·상태를 갖는다. `AssetRegistry`(autoload) 가 해석한다.
- 해석 순서: **`asset_overrides/<id>.<ext>`(실행 파일 옆, 재빌드 없이 교체)** → `final_path` → `path`(임시) → 런타임 대체 도형(자홍/검정 체크, 경고 로그).
- 상태: `placeholder`(생성한 임시 도형) · `final`(확정) · `derived`(팩 프레임을 가공한 파생) · `planned`(ID 만 예약, 파일 없음).

## 에셋팩 v4 연결 (2026-09-21, Release `assets-raw-v4`)
131 ID · 1,069장 · 오디오 17개를 `_run_v4/_run_v4_audio` 가 v1~v3 위에 애니메이션 단위로 병합했다. 현황: **최종 394 · 파생 5 · 임시 0 · 예정 0** (총 399). 남은 파생 5는 수호목수·사수의 범용 `cast`(Q/E/R 전용 시트가 있어 실제로는 쓰이지 않음)와 보스 3종 `down`(보스는 다운 상태가 없음).

| 묶음 | 연결 |
|---|---|
| F1 직업 3종 8상태 | `char.sawtooth/sapshaman/hydro.{walk,attack,cast,cast_q,cast_e,cast_r,hit,down}` 최종, idle 은 v1 유지. 접점 attack/Q/R 2, E 3 |
| F2 적 9종 | walk/hit/death 최종 (사망 4프레임 유지) |
| F3 보스 2종 | 두꺼비 walk/hit/death/molt, 뿌리왕 walk/hit/death + `root_regrow` 를 클라이언트 MOLT 상태 시트 `boss.root_king.molt` 로도 등록 |
| P 보정 | 버들강 벽 13장(외곽 볼록 모서리 → 바깥 링 귀퉁이), 바닥 8변형 모자이크, 물가 12장(오목 모서리 → 물 사각형 귀퉁이), 카드 2종(안쪽 투명 `content_rect` → 텍스트 여백), 거목 `active_all` 2프레임 루프(`vfx.great_tree_active`), 마을 소품 3종(복구 단계 프레임) |
| F4 VFX | 새 직업 스킬 12종 + 예고 원/직선(시각 경계 `visual_bounds_px` 로 반경 배율) |
| F5 지역 2·3 | 습지·뿌리댐 바닥 모자이크·벽 9·물 2·물가 4, 보스 소품 8(3상태), 댐·톱니·목재, 뗏목·비밀·포탑, 습지 버섯·그루터기 변형 2 |
| F6 | 스킬 아이콘 9, 유물 26, 직업 아이콘·초상 5, 적 아이콘 12, 보스 초상 3, NPC 스프라이트·초상 6 |
| G 오디오 | `assets/final/audio/` 에 복사. wav 효과음 12(Master 버스, 설정 SFX 음량 + gain_db), ogg 음악 3·환경음 2(`AudioDirector`: 루프 오프셋 = loop_start_sample/44100, 설정 BGM·환경음 음량 + gain_db). 마을 `bgm.hub`+`amb.wind`, 전투 `bgm.combat_normal`, 보스방 `bgm.boss`, 물 있는 방 `amb.water`, 버튼 `sfx.ui_click` |

### v4 소품 상태 ↔ 서버 상태 매핑 (팩 INTEGRATION 요구)
| ID (프레임 라벨) | 서버 상태 → 프레임 |
|---|---|
| `prop.raft` (intact, damaged) | RAFT `state` 2(적 접근·정지) → 1, 그 외 0 |
| `prop.secret` (closed, open) | 항상 0, `secret_found` 이벤트에 1을 3초 표시 |
| `prop.turret` (folded, deployed, firing) | TURRET `state` 1(사격 중) → 2, 그 외 1 |
| `prop.dam` (gap, partly, completed) | DAM `progress`(체력 비율) > 0.66 → 2, > 0.33 → 1, 그 외 0 |
| `prop.boss.pillar` (intact, notch, snapped) | IC-01 PILLAR `state` ≥ 1(약화) → 1, 아니면 0. 파괴되면 오브젝트 제거 |
| `prop.boss.gate` (closed, half, open) | IC-02 GATE 현재 비트 1 → 2, 0 → 0 |
| `prop.boss.claw_link` (open, latched, broken) | IC-03 `state` 0/1/2 그대로 |
| `prop.boss.corridor` (blocked, clear, collapsed) | IC-04 `state` 0(열림) → 1 clear, ≥1(차단) → 0 blocked |
| `prop.boss.rope` (slack, taut, snapped) | IC-05 ROPE `state` ≥ 1(연결) → 1, 아니면 0 |
| `prop.boss.debris` (fresh, partly, few) | IC-05 DEBRIS `progress` × 3 |
| `prop.boss.anchor` (intact, strained, broken) | IC-05 ANCHOR `state` ≥ 1(고정) → 0 intact, 아니면 1 strained |
| `prop.boss.platform` (stable, tilting, broken) | IC-05 PLATFORM `state` 2(안전) → 0, 그 외 1 |
| `prop.dam.gear`, `prop.dam.timber` | 대응 오브젝트 없음 — 등록만 (RK 기믹은 v2 장치 시트) |

보스 소품은 v2 기믹 장치 시트(activation/success/failure)가 우선이고, 장치 시트가 없을 때만 위 프레임을 그린다(두 그림을 겹치지 않는다).

## 에셋팩 v3 연결 (2026-09-21, Release `assets-raw-v3`)
두 팩(`beaver_assets_v3a` 361장, `beaver_assets_v3bce` 158장)을 `tools/import_asset_pack.gd` 의 `_run_v3a/_run_v3b` 가 v1·v2 위에 **애니메이션 단위로** 덮어쓴다. 현황: 최종 205 · 파생 89 · 임시 93 · 예정 5 (총 392, `check_assets` 문제 0).

| 묶음 | 연결 방식 (코드) |
|---|---|
| A 캐릭터 동작 (사수 8, 수호목수 4, 적 3종×3+돌진, 가재 4+빈 껍질) | 4방향 시트로 합성. `EntityView` 가 `interact`(갉기), 피격 2프레임(`flash()` 뒤 0.28초), 이동·사망·탈피를 상태별로 고른다. `husk_all` 은 256px 단일 텍스처 `prop.boss.husk` |
| B VFX 16 | `direction: all` 스트립. `animation.mode`(one_shot / loop / select_frame / state_sequence)·`hold_last`·`segments` 를 매니페스트에 보존. `WorldView.spawn_effect` 가 모드별로 재생하고, 덫은 설치[0]→대기[1,2]→서버 발동 이벤트에 [3], 거목은 성장 후 활성 프레임을 보호 시간 동안 유지 |
| C 타일 6·소품 13 | 바닥 4변형은 4×4 시드 모자이크 1장. 강둑 9장은 방 경계 바깥 2줄 링, 물가 4장은 물 사각형 네 변, 물 2프레임은 0.5초 교대(`AssetRegistry.get_frame_texture`). 소품은 열=상태 시트이고 `_draw_frame` 이 서버 진행률·상태로 프레임을 고른다. 마을 소품은 복구 단계 프레임 |
| D 아이콘 24 | 스킬·회복·회피·유물 10·상태 6. HUD 가 직업 데이터의 아이콘 ID 를 읽고, 둔화/출혈/보호막 상태 아이콘 행을 표시 |
| E UI 9 | 패널·버튼 3상태(12px 9-slice, `UIKit.theme`), 보상·경로 카드(`UIKit.card_button`), 체력바·보스바(`TextureBar`: 채움 뒤 + 틀 앞, `fill_rect_px` 클리핑), 로고(로그인), 초상 틀(NPC 대화), 앱 아이콘(project.godot) |

미연결: `enemy.thorn_boar.charge`(서버에 지속 돌진 상태 없음), `icon.status.mark/stagger/wet`(플레이어 스냅샷에 그 상태 없음), `tile.willow.bridge`, `tile.hub.planks`. 남은 임시·파생 항목과 보정 요청은 `docs/asset_request_v4.md`.

## 에셋 레지스트리 현황 (2026-09-20, 팩 v1·v2 연결 후)
- 상태: `placeholder`(생성한 임시 도형) · `final`(팩에서 받은 확정 프레임) · `derived`(팩 프레임을 가공해 이 환경에서 만든 파생 동작·아이콘) · `planned`(ID 만 예약).
- 매니페스트 항목마다 `provided`(제공됨) / `linked`(연결됨: 코드가 이 ID 를 실제로 그림) / `verified`(검증됨: `screen` = 실제 화면에서 확인, `check` = 검수 도구만 통과, `not_run`) 를 기록한다. `source` 에 원본 팩·액터·동작·가공 방법을 남긴다.
- 원본 팩(약 210MB)은 저장소에 넣지 않는다. GitHub Release `assets-raw-v1`(비버_RPG_에셋팩_v1.zip, 비버_RPG_전투애니메이션_v2.zip, 인계 MD)에 있다. 저장소에는 합성한 시트(`assets/final/`, 218장 약 59MB)와 팩 문서·매니페스트·Godot 리소스(`assets/packs/`, `.gdignore`)만 둔다.

| 종류 | ID | 원본(팩 액터) | 상태 |
|---|---|---|---|
| 수호목수 | `char.guardian.{idle,walk,attack,cast_q,cast_e,cast_r}` | v1 `player_guardian` | 제공됨·연결됨·검증됨(화면) — final |
| 수호목수 파생 | `char.guardian.{cast,hit,down}` | v1 프레임 가공(틴트/회전) | 연결됨·검증됨(화면) — derived |
| 솔방울사수 | `char.pinecone.idle` (final) + walk/attack/cast*/hit/down (derived: bob·lean·pulse) | v1 `player_ranger` | 제공됨(대기만)·연결됨 — 이동·공격은 파생이라 최종 아님 |
| 톱니·수액주술사·수력공 | `char.{sawtooth,sapshaman,hydro}.*` | v1 `player_{berserker,shaman,engineer}` 대기 자세 | 제공됨(대기만)·미연결(직업 미구현) |
| 일반 적 3종 | `enemy.{sap_snail,thorn_boar,black_bird}.{idle,attack}` (final) + walk/hit/death (derived) | v1·v2 `enemy_{sap_slug,thorn_boar,black_crow}` | 제공됨·연결됨·검증됨(화면) |
| 예비 적 9종 | `enemy.{shell_soldier,spore_mushroom,root_puppet,reed_frog,river_leech,lantern_moth,woodjaw_beetle,gear_crab,sap_totem}.*` | v1·v2 | 제공됨·미연결(적 정의 없음) |
| 철턱 가재 | `boss.ironclaw.{idle,attack,claw_sweep,straight_charge,rock_throw,ground_slam,cast,stagger,exposed}` (final) + walk/molt/hit/death/down (derived) | v1·v2 `boss_ironclaw` (512→256 축소) | 제공됨·연결됨·검증됨(화면) |
| 예비 보스 2종 | `boss.{lantern_toad,root_king}.*` | v1·v2 | 제공됨·미연결(보스 미구현) |
| 기믹 장치 IC-01~05 | `prop.mechanic.ic_0N.{activation,success,failure}` | v2 `mechanic_ic_0N` (256, 4프레임 단일 행) | 제공됨·연결됨·검증됨(화면: 서버 오브젝트 kind→시트) |
| 예비 기믹 장치 TF/RK | `prop.mechanic.{tf,rk}_0N.*` | v2 | 제공됨·미연결 |
| 아이콘·초상 | `icon.class.*`(5), `icon.enemy.*`(12), `portrait.*`(8), `ui.app_icon` | 팩 idle 첫 프레임 잘라 축소 | derived·연결됨 |
| 타일·VFX·UI·스킬/유물 아이콘·방 소품·마을 소품·NPC·효과음 | `tile.*`(3지역), `vfx.*`, `ui.*`, `icon.skill.*`(15), `icon.relic.*`(36), `prop.*`(기믹 장치 제외), `npc.*`, `portrait.npc.*`, `sfx.*` | 없음 (팩 미제공, `docs/asset_request_v3.md` 로 요청) | placeholder 유지 (135개) |
| 폰트 | `font.ui.main` | Noto Sans KR Regular (OFL) | final |
| 예정 | `bgm.*`, `amb.*` | | planned (5) |

### 이 환경에서 만든 파생 동작 (derived) 규칙
- 팩에 없는 동작만 만든다. 원본 프레임을 바꾸지 않고 시트 합성 단계에서 가공한다.
- `walk`/`idle 2프레임`: 1~2px 상하 bob. `attack`(대기만 있는 직업): 전방 기울임. `cast`: 밝기 펄스·틴트. `hit`: 붉은 틴트. `down`: 90° 회전 + 아래로 이동. `death`: 페이드. `molt`: 채도 낮춤.
- 파생본은 최종 에셋이 아니다. 팩에서 같은 ID 의 동작이 오면 `tools/import_asset_pack.gd` 를 다시 돌리면 `final` 로 바뀐다.

### 팩 임포트 절차 (`tools/import_asset_pack.gd`)
1. Release `assets-raw-v1` 의 두 zip 을 풀어 한 폴더에 `beaver_assets/`, `beaver_combat_v2/` 로 둔다 (각 폴더에 `manifest.json` 이 있어야 한다).
2. `godot --headless --path . -s tools/import_asset_pack.gd -- --packs=<그 폴더>` — 팩 프레임을 방향 행(down/up/left/right) × 프레임 열 시트로 합성해 `assets/final/<id>.png` 에 쓰고 매니페스트를 갱신한다. 보스 512 프레임은 256 으로 줄인다(원본은 팩에 남는다). `--only=<id 접두>` 로 일부만 다시 만들 수 있다.
3. `godot --headless --path . --import` 로 임포트 캐시를 만들고 `--tool=check_assets` 로 검수한다.
4. 데모 모드(`--connect=호스트:포트 --demo=<닉> --shots=<폴더>`)로 실제 화면을 캡처해 방향·앵커·프레임을 눈으로 확인한다.

### 팩 ID → 내부 ID 매핑 (인계 MD 표)
| 팩 ID | 내부 ID | 비고 |
|---|---|---|
| player_guardian | guardian | 수호목수 |
| player_ranger | pinecone | 솔방울사수 |
| player_berserker | sawtooth | 톱니 (미구현) |
| player_engineer | hydro | 수력공 (미구현) |
| player_shaman | sapshaman | 수액주술사 (미구현) |
| enemy_sap_slug | sap_snail | 수액 달팽이 |
| enemy_thorn_boar | thorn_boar | 가시 멧돼지 |
| enemy_black_crow | black_bird | 검은 새 |
| boss_ironclaw | ironclaw | 철턱 가재 |
| mechanic_ic_01..05 | prop.mechanic.ic_01..05 | 서버 오브젝트 PILLAR/GATE/CLAW_LINK/CORRIDOR/ANCHOR 에 대응 |
| 팩 `straight_charge` / `rock_throw` | 서버 패턴 `line_charge` / `rock_toss` | `EntityView` 가 패턴 이름으로 시트를 고른다 |

## 교체 절차
1. 같은 ID 의 규격(프레임 크기·열/행·앵커·방향 순서)에 맞춰 최종 파일을 만든다. 규격은 매니페스트 항목과 `spec` 을 따른다.
2. 다음 중 하나:
   - 프로젝트에 넣는 경우: 파일을 원하는 경로(예 `assets/final/beaver_guardian_walk.png`)에 두고 매니페스트의 `final_path` 를 채운 뒤 `status` 를 `final` 로 바꾼다.
   - 배포본에서 바로 바꾸는 경우: 실행 파일 옆 `asset_overrides/<id>.png` 로 둔다(예 `asset_overrides/char.guardian.walk.png`). 재빌드 없이 즉시 적용된다.
3. `godot --headless --path . -- --tool=check_assets` 로 파일 존재·크기·알파·프레임 범위·참조를 검수한다.
4. 임시 파일은 그대로 두어도 된다(최종이 우선). 임시 도형을 최종 에셋이라 부르지 않는다.

## 규격 (16절 기본값)
- 플레이어·일반 적 128×128, 보스 256/512, 타일 64, 아이콘 64, 초상 256. 발 앵커 기본 `(0.5, 0.82)`.
- 스프라이트 시트: 행 = 방향(down, up, left, right), 열 = 프레임. 매니페스트 `animation.frames`, `fps`, `loop`, `event_frames`(공격 판정 프레임) 사용.
- 실제 렌더링 크기는 `render_size`, 판정은 `hitbox_ref` → `data/hitboxes.json` 으로 분리한다(서버 export 에는 판정만 남는다).
- 광원 좌상단, 3/4 탑다운 고정. 이미지 안에 읽어야 하는 글자를 넣지 않는다.

## 제작 순서 (17절)
1. 비버 기준 시트(체형·직업 실루엣·색·카메라) → 2. 수호목수·솔방울사수 정면/후면/측면 → 3. 최소 애니메이션을 게임 화면에서 확인 → 4. 버들강 타일, 일반 적 3종, 철턱 가재, 스킬 VFX → 5. MVP 연결·앵커·프레임 수정 → 6. 나머지 직업·지역.

## 이미지 생성 요청 템플릿
"둥근 몸, 짧은 팔다리, 큰 앞니와 넓은 납작 꼬리를 가진 비버 {직업}. 무기 {나무망치}. 따뜻한 숲색·수채화풍 부드러운 명암, 또렷한 윤곽. 3/4 탑다운 고정 카메라, 광원 좌상단. 방향 {정면/후면/좌/우}, 동작 {대기/걷기/공격/시전/피격/다운}, 128×128 투명 배경, 발 위치 y=105 고정, 프레임 간 무기·꼬리·얼굴 변형 금지, 글자·배경 무늬 금지."

## v5 팩 연결 (2026-09-21, 장비·제작·강화 UI)
- 출처: GitHub Release `assets-raw-v5` / `beaver_assets_v5.zip`. 팩 manifest 는 v4 와 같은 format_version=2 이며 actors 키가 점 ID 그대로다. importer `_run_v5()` 가 `actors` 를 훑어 프레임 1개는 texture, 여러 프레임 중 `vfx.` 는 one_shot 시트, 나머지(등급 테두리 5·빈 슬롯 4)는 select_frame 시트로 등록한다. 오디오는 `_run_pack_audio()` 공용.
- ID (32): `icon.gear.<base>` 17, `ui.frame.rarity`(5프레임, 등급 지수 0~4), `ui.badge.enhance`(24, +N 은 코드), `ui.slot.gear`(4프레임: 무기/갑옷/장신구/잠김), `ui.icon.locked`(32), `ui.icon.crafted`(24), `icon.material.sap_crystal`, `icon.blueprint.{weapon,armor,trinket}`, `vfx.enhance.{success 6f@12, fail 4f@10, destroy 8f@10}`(96/96/128), `sfx.enhance.{success,fail,destroy}`(ogg).
- 클라이언트: `HubScreen.GearIcon` 이 장비 아이콘 → 등급 테두리 → 제작 망치 → 강화 배지(+N) 순으로 겹쳐 그린다(팩이 없으면 글자만). 빈 슬롯은 `ui.slot.gear` 프레임, 도안은 `icon.blueprint.<slot>` + 잠김 자물쇠, 헤더에 재료 아이콘. 강화 결과는 서버 `ACCOUNT_UPDATE.gear_result{seq, result}` 를 받아 `UiFrameAnim` 이 한 번 재생하고 사라지며 `sfx.enhance.*` 를 같은 순간 재생한다. 같은 seq 는 다시 재생하지 않는다.
- 검수: `check_assets` 431 항목 문제 0, `run_tests` v5 검사(단일 24·시트 3·VFX 3·SFX 3·테두리 투명 영역).

