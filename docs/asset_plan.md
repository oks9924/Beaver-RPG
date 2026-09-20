# 에셋 계획과 교체 절차

## 원칙: ID 와 파일의 분리
- 코드·데이터는 **에셋 ID** 만 참조한다 (`char.guardian.walk`, `enemy.sap_snail.attack`, `tile.willow.ground`, `icon.skill.guardian.q`, `sfx.hammer_hit`, `font.ui.main` …).
- `assets/asset_manifest.json` 이 ID → 파일 경로·규격·상태를 갖는다. `AssetRegistry`(autoload) 가 해석한다.
- 해석 순서: **`asset_overrides/<id>.<ext>`(실행 파일 옆, 재빌드 없이 교체)** → `final_path` → `path`(임시) → 런타임 대체 도형(자홍/검정 체크, 경고 로그).
- 상태: `placeholder`(생성한 임시 도형) · `final`(확정) · `derived`(팩 프레임을 가공한 파생) · `planned`(ID 만 예약, 파일 없음).

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
| 타일·VFX·UI·스킬/유물 아이콘·방 소품·마을 소품·효과음 | `tile.*`, `vfx.*`, `ui.*`, `icon.skill.*`, `icon.relic.*`, `prop.*`(기믹 장치 제외), `sfx.*` | 없음 (팩 미제공) | placeholder 유지 (64개) |
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
