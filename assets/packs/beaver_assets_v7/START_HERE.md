# Beaver RPG v7 — 방 지형 소품·바닥 장식

2026-09-22. 버들강(willow), 검은 수액 늪(swamp), 고대 뿌리 댐(dam)의 필수 에셋 27종, 총 60개 변형입니다. 요청서 A 표는 실제 18종이며 B는 9종입니다. 선택 사항 C의 pond_edge 9분할 타일은 포함하지 않았습니다.

## 개발 담당자에게 전달할 내용

> 이 ZIP을 v7 신규 에셋으로 적용해 주세요. START_HERE.md와 asset_manifest.v7.patch.json을 먼저 읽고, 기존 개발 작업을 유지하면서 신규 ID 27개를 등록해 주세요. PNG 복사만으로 등록이 끝났다고 판단하지 마세요. 현재 프로젝트에 v7 임포터가 구현되어 있다면 그 규칙과 이 패키지의 실제 구조를 대조한 뒤 사용하세요. 없다면 tools/apply_v7.py의 미리보기를 실행하고 적용하거나 동일한 병합 작업을 구현하세요. 변형 프레임은 애니메이션 재생용이 아니라 select_frame 용입니다. chunks.json의 역할 연결, 데칼 렌더 순서, 긴 통나무의 충돌체와 그림 정렬을 확인하고 기존 check_assets/check_rooms 절차 및 room_gen 미리보기로 검증해 주세요. 실행하지 않은 검사는 통과했다고 보고하지 마세요.

## 구성과 규격

- `project_files/assets/final/`: 실제 규격의 투명 RGBA PNG 27개. 파일명은 ID의 점을 유지합니다.
- `asset_overrides/`: 같은 PNG 사본. 신규 ID 등록 후 오버라이드에 사용할 수 있습니다.
- `frames/`: 개별 변형 60개. 각 시트는 왼쪽부터 0 기반 인덱스입니다.
- `asset_manifest.v7.patch.json`: 기존 매니페스트에 병합할 신규 항목입니다. 전체 매니페스트 대체용이 아닙니다.
- `sources/`: 고해상도 생성 원화 27개와 재제작용 프롬프트입니다.
- `PREVIEW.png`: 지역별·종류별 비교표입니다. 실제 게임 실행 화면은 아닙니다.
- `QA.json`: 크기, 프레임 수, 투명도, 테두리 여백, 파일 해시와 실제 그림 영역입니다.

| 역할 (각 지역 공통) | 프레임 크기 | 변형 수 |
| --- | --- | --- |
| prop.REGION.boulder_cluster | 192×144 | 2 |
| prop.REGION.trunk | 128×96 | 2 |
| prop.REGION.trunk_long_h | 384×128 | 1 |
| prop.REGION.trunk_long_v | 128×384 | 1 |
| prop.REGION.stump_cluster | 160×120 | 2 |
| prop.REGION.bush | 96×80 | 3 |
| decal.REGION.dirt | 256×192 | 3 |
| decal.REGION.leaves | 256×192 | 3 |
| decal.REGION.puddle | 256×192 | 3 |

REGION은 willow/swamp/dam입니다. 시트 크기는 (프레임 너비 × 변형 수) × 프레임 높이입니다. 앵커는 요청에 맞춰 `[0.5, 0.75]`로 등록합니다. 원본 종횡비를 유지하며 프레임에 맞췄으며 빛 방향은 좌측 위입니다.

## 적용

확인한 저장소 스냅샷에는 v7 임포터 단계가 없었습니다. 이후 개발 변경분을 먼저 확인하세요. 아래 스크립트는 Python 표준 라이브러리만 사용합니다.

```sh
python tools/apply_v7.py /path/to/Beaver-RPG
python tools/apply_v7.py /path/to/Beaver-RPG --apply
```

첫 명령은 변경 없이 대상과 항목 수를 보여줍니다. 두 번째는 파일 복사와 매니페스트 병합을 수행하며 변경 전 매니페스트와 기존 동명 PNG를 `asset_import_backups/`에 백업합니다. 프로젝트 루트에 `assets/asset_manifest.json`이 있어야 합니다. 기존 다른 ID와 코드 파일은 유지됩니다.

## 렌더링·검증 유의점

1. `animation.mode=select_frame`, 1행, columns=변형 수입니다. 방 시드로 변형을 골라 프레임을 고정하세요.
2. 데칼은 충돌이 없으며 바닥 위·캐릭터 아래에 그립니다. 방당 2~5개 배치하고 시인성이 중요한 위험 예고 영역은 피하세요.
3. 충돌 원은 코드에서 유지합니다. 그림에 충돌선을 넣지 않았습니다. 신규 prop 항목의 hitbox_ref가 검사기에 필요하면 프로젝트의 실제 등록 키에 연결하세요.
4. render_size는 우선 요청 프레임 크기입니다. 셀 350×300에 맞춰 실제 배치 크기를 조정하세요. 특히 긴 통나무는 가로/세로 전용 이미지이며 코드의 연속 원형 충돌체를 자연스럽게 덮는지 확인하세요.
5. 앵커는 파일별 메타데이터이며 코드가 실제로 적용해야 합니다. 세로 통나무와 바닥 데칼은 길이·평면 방향 때문에 배치 중심과 앵커가 다를 수 있으므로 방 미리보기에서 오프셋을 확인하세요. 그림 영역은 QA.json에 있습니다.
6. check_assets, check_rooms 및 게임 내 room_gen 검증은 납품 환경에서 실행하지 않았습니다. 서버/클라이언트 실행 및 충돌 정렬도 개발 프로젝트에서 검증해야 합니다.

생성형 원화를 기존 지역별 에셋을 참조해 제작했습니다. 이후 수정에는 sources의 원화와 프롬프트를 사용하고, 게임에는 project_files의 규격화된 시트를 사용하세요.
