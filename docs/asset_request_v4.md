# 에셋 요청서 v4 — 남은 임시·파생 에셋과 v3 보정 요청

v3(A~E)까지 받은 뒤 남은 항목이다. 규격·앵커·파일 구조는 v3 요청서(`docs/asset_request_v3.md`)와 같다(format_version 2, 128/256/512, 발 앵커, `direction: all` 은 `default_all`). 매니페스트 현황: 최종 205 · 파생 89 · 임시 93 · 예정 5 (총 392).

## 0. v3 연결 결과와 보정 요청 (작화 쪽)

| 항목 | 연결 결과 | 보정 요청 |
|---|---|---|
| `tile_willow_wall` 9장 | 방 경계 바깥 2줄 링으로 연결(경계 4 + 안쪽 모서리 4 + 전체 1). 타일의 투명 여백 아래에 코드가 어두운 수풀 바탕을 깐다 | 여백 없이 불투명 수풀로 채운 판 또는 바탕색 지정. 강둑 **바깥쪽(볼록) 모서리** 4장 추가 |
| `tile_willow_ground` 4변형 | 4×4 시드 모자이크 256px 한 장으로 합쳐 반복 사용 | 흙 패치 대비가 강해 반복이 보인다. 변형 8장(흙 패치 없는 것 4 + 옅은 것 4) |
| `tile_willow_shore` 4장 | 물 사각형의 네 변에 연결 (물 폭·높이 128px 이상일 때) | 물가 코너 4장(볼록·오목) |
| `tile_willow_water` 2프레임 | 0.5초 간격 교대 | 없음 |
| `tile_willow_bridge`, `tile_hub_ground[1]` 나무판 | 등록만(다리·판자 배치 규칙이 아직 없음) | 없음 |
| `prop_gnaw_tree/device/lever/sluice_gate/log_cover/hold_point` | 서버 진행률·상태로 프레임 선택. 쓰러진 나무(2)는 갉기 완료 이벤트에 2.5초 표시 | 없음 |
| `prop_memory_tree/workshop/expedition_board/stall` | 마을에 배치(기억나무·작업실은 복구 단계 프레임). 좌판·모닥불은 상점/휴식 패널 아이콘으로도 사용 | 훈련장·약초방·기록관 소품 3종(각 0/1/2단계) |
| `vfx_thorn_trap` | 설치[0] → 대기[1,2] 반복 → 서버 발동 이벤트에 [3] 0.4초 | 없음 |
| `vfx_great_tree` | 성장 5프레임 후 활성 프레임을 보호 지속시간 동안 유지 | 활성 상태 흔들림 2프레임(선택) |
| `vfx_projectile_*` 2프레임 | 회전 루프 | 없음 |
| `vfx_whirlpool` | IC-05 끌려가는 발판 아래 루프 | 없음 |
| `enemy_thorn_boar.charge` | 서버에 '지속 돌진' 상태가 없어 **미연결** (v2 tusk_charge 예고·접촉을 사용) | 없음 (서버 작업) |
| `icon_status_mark/stagger/wet` | 해당 상태가 플레이어 스냅샷에 없어 **미연결** | 없음 (서버 작업) |
| `ui_bar_hp/boss` | 틀+채움 레이어, fill_rect 로 클리핑 | 없음 |
| `ui_card_reward/route`, `ui_button` 3상태, `ui_panel`, `ui_title_logo`, `ui_frame_portrait`, `ui_app_icon` | 전부 연결 | 카드 안쪽 여백이 좁아 긴 설명이 잘린다 → 카드 안쪽 투명 영역을 상하 16px 넓힌 변형 |

## 1. 우선순위 F — 후속 콘텐츠 (임시 93 · 파생 89)

### F-1. 직업 3종 동작 (파생본 → 최종본). 시트 규격은 사수(A-1)와 같다

- 톱니전사 `player_berserker`: `attack`, `cast`, `cast_e`, `cast_q`, `cast_r`, `down`, `hit`, `walk` (v1 대기만 있음). 시전 접점: attack/Q/R 2, E 3
- 수액주술사 `player_shaman`: `attack`, `cast`, `cast_e`, `cast_q`, `cast_r`, `down`, `hit`, `walk` (v1 대기만 있음). 시전 접점: attack/Q/R 2, E 3
- 물길공학자 `player_engineer`: `attack`, `cast`, `cast_e`, `cast_q`, `cast_r`, `down`, `hit`, `walk` (v1 대기만 있음). 시전 접점: attack/Q/R 2, E 3

### F-2. 일반 적 9종 이동·피격·사망 (파생본 → 최종본, 각 walk 4 / hit 2 / death 4)

- `gear_crab`, `lantern_moth`, `reed_frog`, `river_leech`, `root_puppet`, `sap_totem`, `shell_soldier`, `spore_mushroom`, `woodjaw_beetle`

### F-3. 보스 2종 (파생본 → 최종본, 512 프레임): walk 4 / hit 2 / death 6 / molt 4 (뿌리왕은 molt 대신 root_regrow 4)

- `boss_lantern_toad`, `boss_root_king`

### F-4. 새 직업 VFX (임시 → 최종, `direction: all`)

| ID | 크기 | 프레임 | 내용 |
|---|---|---|---|
| `vfx_gnaw_dash` | 128 | 4 | 톱니전사 Q 돌진 궤적·톱밥 |
| `vfx_great_dam` | 512 | 4 | 공학자 R 댐 붕괴 물결 |
| `vfx_log_whirl` | 256 | 4 (루프) | 톱니전사 R 회전 베기 통나무 잔상 |
| `vfx_projectile_water` | 32 | 2 | 물방울 투사체 |
| `vfx_root_bind` | 128 | 4 | 주술사 뿌리 구속 |
| `vfx_sap_bloom` | 256 | 4 | 주술사 회복 구역 수액 꽃 |
| `vfx_spring_flood` | 512 | 4 | 주술사 R 샘물 범람 |
| `vfx_telegraph_circle` | 256 | 1 | 원형 예고 (반투명 링, 현재 임시) |
| `vfx_telegraph_line` | 256 | 1 | 직선 예고 |
| `vfx_torrent_valve` | 256 | 4 | 공학자 급류 분사 |
| `vfx_water_turret` | 128 | 4 | 공학자 포탑 물줄기 |
| `vfx_wood_split` | 128 | 4 | 톱니전사 E 강타 나무 쪼개짐 |

### F-5. 지역 2·3 타일과 소품 (임시 → 최종)

- 타일: `tile_rootdam_ground`, `tile_rootdam_wall`, `tile_rootdam_water`, `tile_swamp_ground`, `tile_swamp_wall`, `tile_swamp_water` (각각 버들강과 같은 구성: 바닥 4변형, 강둑/벽 9, 물 2, 물가 4)
- 소품: `prop_boss_anchor`, `prop_boss_claw_link`, `prop_boss_corridor`, `prop_boss_debris`, `prop_boss_gate`, `prop_boss_pillar`, `prop_boss_platform`, `prop_boss_rope`, `prop_dam`, `prop_dam_gear`, `prop_dam_timber`, `prop_raft`, `prop_secret`, `prop_swamp_mushroom`, `prop_swamp_stump`, `prop_turret`
  - 보스 기믹 소품(`prop_boss_*`)은 IC 장치 그림(v2)이 있는 기믹은 그것을 쓰고, 없는 것만 필요: 지지목·수문·통로·닻줄·잔해·닻·발판·집게 고리는 v2 장치 시트로 대체 중 → 상태 2~3장씩

### F-6. 아이콘·초상 (임시·파생 → 최종)

- 스킬 아이콘 9: `icon_skill_hydro_e`, `icon_skill_hydro_q`, `icon_skill_hydro_r`, `icon_skill_sapshaman_e`, `icon_skill_sapshaman_q`, `icon_skill_sapshaman_r`, `icon_skill_sawtooth_e`, `icon_skill_sawtooth_q`, `icon_skill_sawtooth_r`
- 유물 아이콘 26: `acorn_cache`, `amber_tooth`, `ancient_incisor`, `beaver_grease`, `bitter_sap`, `dam_bell`, `dam_keeper_badge`, `firefly_jar`, `gnawed_charm`, `hollow_log`, `hunters_eye`, `kin_totem`, `lucky_acorn`, `memory_bloom`, `moss_blanket`, `otter_whistle`, `quick_gnaw`, `river_heart`, `river_pebbles`, `sap_lantern`, `stone_shell`, `storm_tail`, `tail_drum`, `thorn_bolt`, `thorn_crown`, `willow_bark`
- 직업 아이콘·초상 (현재 기본 자세 크롭 파생): `icon_class_guardian`, `icon_class_hydro`, `icon_class_pinecone`, `icon_class_sapshaman`, `icon_class_sawtooth`, `portrait_guardian`, `portrait_hydro`, `portrait_ironclaw`, `portrait_lantern_toad`, `portrait_pinecone`, `portrait_root_king`, `portrait_sapshaman`, `portrait_sawtooth`
- 적 아이콘 12 (도감용, 현재 크롭 파생): `icon_enemy_*`
- NPC 6명 스프라이트(128, idle 2프레임 4방향은 아님 — 정면 1장이면 됨)와 초상 6: `npc_archivist_willow`, `npc_elder_zelkova`, `npc_engineer_ripple`, `npc_herbalist_moss`, `npc_merchant_doto`, `npc_smith_resin`

## 2. 우선순위 G — 오디오 (임시 12 · 예정 5)

- 효과음: `sfx_dodge`, `sfx_down`, `sfx_great_tree`, `sfx_hammer_hit`, `sfx_player_hit`, `sfx_rescue`, `sfx_sling`, `sfx_snail_death`, `sfx_snail_hit`, `sfx_tail_slam`, `sfx_ui_click`, `sfx_wood_block` (wav 44.1kHz mono, 0.1~1.5초)
- 음악·환경음: `bgm_hub`, `bgm_combat_normal`, `bgm_boss`, `amb_water`, `amb_wind` (ogg 루프 60~120초)

## 3. 검수 기준

v3 와 같다. 추가로: 강둑 볼록 모서리는 안쪽 모서리와 같은 방식으로 인덱스를 문서화하고, 카드 변형은 기존 256×352 / 256×160 과 같은 캔버스에서 안쪽 투명 영역만 바꾼다.
