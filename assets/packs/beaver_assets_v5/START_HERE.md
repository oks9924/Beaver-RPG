# 비버 RPG 에셋 v5 — 장비·제작·강화

이 팩은 `asset_request_v5.md`의 A~D 전체를 포함한다. 기존 게임에 추가하는 에셋 팩이며, v1~v4를 대체하는 통합본은 아니다.

## 전달 방법

개발 중인 도구에 ZIP을 첨부하거나 압축을 풀어 프로젝트에서 접근 가능한 위치에 놓고, 아래 작업 지시를 함께 전달하면 된다. ZIP을 읽을 수 없는 도구에는 압축 해제 경로를 알려준다.

```text
첨부한 beaver_assets_v5를 현재 개발 프로젝트에 추가해 줘.
먼저 이 팩의 START_HERE.md, manifest.json, audio_manifest.json과 프로젝트의 docs/asset_plan.md, tools/import_asset_pack.gd, assets/asset_manifest.json, client/ui/hub_screen.gd를 읽어.

1. 기존 importer의 --packs 인자 형식과 manifest 스키마를 실제 코드에서 확인하고, 필요한 최소 어댑터만 구현해. 이 팩의 manifest.json을 프로젝트 assets/asset_manifest.json에 통째로 덮어쓰지 마.
2. 요청서의 점(.)이 포함된 ID를 정확히 유지해서 그래픽 29개 ID와 효과음 3개 ID를 추가해. 기존 v1~v4 항목은 유지해.
3. assets/의 개별 프레임 또는 sheets/의 가로 시트를 사용해. sources/와 preview/는 런타임 로딩 대상이 아니야.
4. _item_button은 icon.gear.<base>의 등록·로드 성공과 status=final을 확인한 뒤 표시해. 실제 임포트가 실패하면 기존 텍스트 fallback을 유지해.
5. ui.frame.rarity는 애니메이션이 아니라 등급 지수 0~4로 선택하는 5프레임이야. ui.slot.gear도 0~3으로 선택하는 4프레임이야. 강화 배지의 +N은 코드로 그려.
6. 강화 VFX/SFX는 서버가 확정한 성공·실패·파괴 결과에만 연결하고, 결과 ID로 중복 재생을 막아. 클라이언트 버튼 클릭만으로 결과를 미리 확정하지 마.
7. 선택 인덱스, 투명 영역, 배지 숫자, 잠긴 도안, 제작품 표시, 전설 기본 아이콘 재사용, 강화 결과 3종을 실제 클라이언트에서 확인해. 완료 보고에는 수정 파일, 임포트 결과, 실제로 확인한 항목과 미확인 항목을 구분해.
현재 진행 중인 개발 단계에 이어서 적용하고, 게임을 처음부터 다시 만들지 마.
```

## 포함 내용

| 구분 | 에셋 ID 수 | 개별 PNG 프레임 |
|---|---:|---:|
| A 장비 | 17 | 17 |
| B 등급·상태 UI | 5 | 12 |
| C 재료·도안 | 4 | 4 |
| D 강화 VFX | 3 | 18 |
| 합계 | 29 | 51 |

가로 PNG 시트 29장, 1초 미만 OGG 효과음 3종, 생성 원본, 등급 테두리 SVG, WAV 원본, 매니페스트, 미리보기를 함께 제공한다. 전설 고유 9종은 별도 아이콘 없이 기본 장비 아이콘과 전설 테두리를 조합한다.

## 파일 구조

- `manifest.json`: v4 팩과 같은 format_version=2 / actors / animations 구조를 바탕으로 한 팩 메타데이터. 프레임 경로는 팩 루트 기준 상대 경로.
- `audio_manifest.json`: 효과음 ID와 OGG 경로·길이·트리거 정보.
- `assets/<정확한 ID>/default/all_00.png`: 실제 규격의 RGBA 프레임. 다중 프레임은 all_01.png부터 이어진다.
- `sheets/<정확한 ID>.png`: 여백·간격 없이 왼쪽에서 오른쪽으로 나열한 1행 시트.
- `docs/asset_index.md`: 모든 ID와 크기·프레임 수의 대응표.
- `docs/integration.md`: 프레임 인덱스, 재생 규칙, UI 연결 방법.
- `preview/index.html`: 로컬에서 열어 보는 에셋·연출·효과음 카탈로그. 게임 클라이언트나 웹 게임이 아니다.
- `sources/`: 수정용 고해상도 원본 및 SVG/WAV. 이 폴더를 그대로 게임에 등록하지 않는다.
- `qa_report.json`: 파일 수준 검수 결과.

## 검증 범위

개별 파일의 규격·투명도·프레임 수·시트 정렬·색상·오디오 길이를 검사했다. 에셋 제작 상태는 `final`, 팩 연결 상태는 `integration_draft`이며 `integration_tested=false`다. 이는 완성된 그림 파일과 실제 프로젝트 연결 검증을 구분하기 위한 값이다.

현재 프로젝트의 importer, 레지스트리 스키마, `docs/asset_plan.md` 원문이 제공되지 않아 Godot 프로젝트에서 실행·임포트한 결과를 주장하지 않는다. 실제 코드를 확인하고 등록 항목을 병합해야 한다.
