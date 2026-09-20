# 에셋 계획과 교체 절차

## 원칙: ID 와 파일의 분리
- 코드·데이터는 **에셋 ID** 만 참조한다 (`char.guardian.walk`, `enemy.sap_snail.attack`, `tile.willow.ground`, `icon.skill.guardian.q`, `sfx.hammer_hit`, `font.ui.main` …).
- `assets/asset_manifest.json` 이 ID → 파일 경로·규격·상태를 갖는다. `AssetRegistry`(autoload) 가 해석한다.
- 해석 순서: **`asset_overrides/<id>.<ext>`(실행 파일 옆, 재빌드 없이 교체)** → `final_path` → `path`(임시) → 런타임 대체 도형(자홍/검정 체크, 경고 로그).
- 상태: `placeholder`(생성한 임시 도형) · `final`(확정) · `planned`(ID 만 예약, 파일 없음).

## 지금 들어 있는 것 (모두 임시, 최종 에셋이 아님)
| 종류 | ID | 규격 | 생성 방법 |
|---|---|---|---|
| 수호목수 6동작 | `char.guardian.{idle,walk,attack,cast,hit,down}` | 128×128, 4방향 행(down/up/left/right), 열=프레임 | `tools/gen_placeholders.gd` 도형 |
| 수액 달팽이 5동작 | `enemy.sap_snail.{idle,walk,attack,hit,death}` | 128×128, 4방향 | 도형 |
| 타일 | `tile.willow.{ground,wall,water}` | 64×64 | 도형 |
| 소품 | `prop.willow.{log,rock}` | 128×128 | 도형 |
| VFX | `vfx.{telegraph_circle,hit_spark,hammer_swing,tail_shockwave,log_shield,great_tree,rescue_ring}` | 128/256 | 도형 |
| 아이콘 | `icon.class.*`, `icon.skill.guardian.{q,e,r}`, `icon.heal`, `icon.dodge`, `icon.enemy.sap_snail` | 64×64 | 도형 |
| UI | `ui.panel.default`, `ui.button.default`(9-slice 12px), `ui.app_icon` | 48/256 | 도형 |
| 초상 | `portrait.guardian` | 256×256 | 도형 |
| 효과음 11종 | `sfx.*` | 22.05kHz 16bit mono WAV | 합성음 |
| 솔방울사수 6동작 | `char.pinecone.*` | 128×128 | 도형 |
| 가시 멧돼지·검은 새 | `enemy.thorn_boar.*`, `enemy.black_bird.*` | 128×128 | 도형 |
| 철턱 가재 9동작 | `boss.ironclaw.{idle,walk,attack,stagger,molt,death,hit,cast,down}` | 256×256, 4방향 | 도형 |
| 기믹 소품 | `prop.boss.{pillar,gate,husk,corridor,rope,debris,anchor,platform,claw_link}` | 64~256 | 도형 |
| 방 소품 | `prop.gnaw_tree`, `prop.device`, `prop.lever`, `prop.log_cover`, `prop.hub.memory_tree` | 128/256 | 도형 |
| 유물·스킬·적 아이콘 | `icon.relic.*`(10), `icon.skill.pinecone.*`, `icon.enemy.*` | 64×64 | 도형 |
| 투사체·VFX | `vfx.projectile_{sap,pinecone}`, `vfx.telegraph_line`, `vfx.sling_shot`, `vfx.thorn_trap`, `vfx.forest_volley` | 32~256 | 도형 |
| 폰트 | `font.ui.main` | Noto Sans KR Regular (OFL) | 외부, **final** |
| 예정(파일 없음) | 나머지 4직업 스프라이트·아이콘·초상, `bgm.*`, `amb.*` | | planned |

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
