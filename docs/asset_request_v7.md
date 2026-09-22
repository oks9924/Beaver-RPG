# 에셋 요청 v7 — 방 지형 프리팹 조각용 소품·바닥 장식 (2026-09-22)

방 안 지형을 매 판 다르게 만드는 2차(프리팹 조각, GEN-03)가 들어갔습니다. 방을 350×300 칸 격자(1400×900 방은 4×3)로 나누고 칸마다 "통나무 벽", "바위 둘", "웅덩이", "그루터기 고리" 같은 조각을 고릅니다. 지금은 기존 소품(바위·통나무·그루터기·버섯·톱니·목재)만으로 조각을 그리고 있어서 모양이 단조롭습니다. 아래 소품이 들어오면 코드 수정 없이 `data/chunks.json` 의 역할(role) 매핑이 새 ID 를 우선 씁니다. ID 가 없거나 final 이 아니면 자동으로 기존 소품으로 대체되므로, 일부만 먼저 주셔도 됩니다.

규격은 v3bce 소품과 같습니다: PNG 투명 배경, 위에서 비스듬히 본 시점(기존 바위·통나무와 같은 각도), 앵커는 아래쪽 (0.5, 0.75). 시트는 가로 나열, `docs/asset_plan.md` 소품 절의 규칙을 따릅니다. 충돌은 코드가 원으로 처리하므로 그림에 충돌 정보는 필요 없습니다.

## A. 지역별 조각 소품 (3지역 × 5종 = 15)

| 역할 | ID (지역별 3개) | 내용 | 프레임 크기 | 비고 |
|---|---|---|---|---|
| boulder_cluster | prop.willow.boulder_cluster · prop.swamp.boulder_cluster · prop.dam.boulder_cluster | 바위 2~3개가 붙은 덩어리 | 192×144, 2프레임(변형) | 충돌 원 반지름 약 48px 하나 |
| trunk | prop.willow.trunk · prop.swamp.trunk · prop.dam.trunk | 짧은 통나무 토막 (개별 충돌용) | 128×96, 2프레임 | 늪은 이끼 낀 통나무, 댐은 잘린 목재 |
| trunk_long_h | prop.willow.trunk_long_h · prop.swamp.trunk_long_h · prop.dam.trunk_long_h | 가로로 누운 긴 통나무 (칸 폭의 약 70%) | 384×128, 1프레임 | 코드가 충돌 원 3개를 아래에 깔고 이 그림 하나를 위에 그린다 |
| trunk_long_v | prop.willow.trunk_long_v · prop.swamp.trunk_long_v · prop.dam.trunk_long_v | 세로로 누운 긴 통나무 | 128×384, 1프레임 | 위와 같음 (세로) |
| stump_cluster | prop.willow.stump_cluster · prop.swamp.stump_cluster · prop.dam.stump_cluster | 그루터기 2~3개 | 160×120, 2프레임 | 댐은 뿌리 덩어리 |
| bush | prop.willow.bush · prop.swamp.bush · prop.dam.bush | 갈대·덤불·이끼 더미 (작은 충돌) | 96×80, 3프레임 | 늪은 갈대, 댐은 뿌리 이끼 |

## B. 바닥 장식 (3지역 × 3종 = 9, 충돌 없음)

| ID | 내용 | 프레임 크기 |
|---|---|---|
| decal.willow.dirt · decal.swamp.dirt · decal.dam.dirt | 흙 자국·발자국 | 256×192, 3프레임 |
| decal.willow.leaves · decal.swamp.leaves · decal.dam.leaves | 낙엽·이끼 조각 | 256×192, 3프레임 |
| decal.willow.puddle · decal.swamp.puddle · decal.dam.puddle | 작은 웅덩이 (물 타일과 어울리는 색) | 256×192, 3프레임 |

바닥 장식은 바닥 타일 위, 캐릭터 아래에 그리며 반투명이어도 됩니다. 한 방에 2~5개가 무작위로 깔립니다.

## C. (선택) 웅덩이 가장자리

| ID | 내용 | 규격 |
|---|---|---|
| tile.willow.pond_edge · tile.swamp.pond_edge · tile.dam.pond_edge | 조각 안의 사각 물 웅덩이 가장자리 (9분할 프레임: 모서리 4 · 변 4 · 가운데 1) | 64×64 × 9프레임 |

없으면 지금처럼 물 타일을 사각으로 깝니다.

## 제작 지침
- 같은 지역 소품끼리 색·외곽선·명암 방향이 기존 v3bce 소품(바위·통나무)과 맞아야 합니다. 나란히 놓였을 때 한 세트로 보여야 합니다.
- 긴 통나무(trunk_long_h/v)는 가운데가 비지 않게, 양 끝이 살짝 굵게. 캐릭터(112px)가 옆에 서면 통나무 지름이 캐릭터 허리 정도.
- 덤불(bush)은 3프레임이 서로 다른 모양이면 좋습니다(같은 조각에 여러 개 놓입니다).
- 파일 이름은 ID 그대로 점을 유지 (`prop.willow.boulder_cluster.png`). v6 처럼 `project_files/assets/final/` 에 완성본을 넣어 주시면 임포터 v7 단계에서 그대로 복사합니다.

## 납품 후 절차
1. `tools/import_asset_pack.gd --packs=` 재실행(v7 단계 추가 예정) 또는 `asset_overrides/` 에 PNG 복사.
2. `--tool=check_assets` 0 문제 확인, `--tool=check_rooms` 로 조각 사용 분포 확인.
3. `docs/screenshots/room_gen.png` 다시 촬영해 비교.

## 개발 담당자에게 붙여넣을 요청
> 첨부한 beaver_assets_v7.zip 을 적용해줘. 방 지형 프리팹 조각용 소품 15종·바닥 장식 9종(·선택 웅덩이 가장자리 3종)이고 ID 는 docs/asset_request_v7.md 표 그대로야. data/chunks.json 의 roles/decals 가 이 ID 를 먼저 쓰도록 되어 있으니 매니페스트에 final 로 등록하고 check_assets·check_rooms 를 돌린 뒤 방 캡처를 다시 찍어줘.
