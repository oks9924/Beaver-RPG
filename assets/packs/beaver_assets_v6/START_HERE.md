# Beaver RPG 에셋 v6 — 걷기·공격 교체 팩

2026-09-21 · 5직업 · 10개 시트 · 개별 프레임 160개

## 무엇을 전달하면 되나

개발 담당자에게 **`beaver_assets_v6.zip`과 이 문서**를 함께 전달하세요. v1~v5 전체를 대체하는 팩이 아니라, 기존 5직업의 `walk`와 `attack`만 교체하는 증분 팩입니다. 기존 게임의 코드·전투 수치·서버 동작은 바꾸지 않습니다.

각 방향의 몸통·머리·옷·꼬리를 하나의 고정 부품으로 만들고, 같은 부품을 모든 프레임에 반복 사용했습니다. 걷기는 팔·다리의 변형으로, 공격은 무기 팔의 회전으로 제작했습니다. 프레임마다 캐릭터를 다시 그리지 않았습니다. 기존 직업의 의상·색·무기를 참고한 새 컷아웃 원화이므로 기존 idle 등과 픽셀 단위로 같은 그림은 아닙니다.

**에셋 파일 검수는 통과했습니다. 실제 게임의 `check_assets`와 4인 플레이 스크린샷 검증은 개발 프로젝트에서 진행해야 합니다.**

## 변경 대상

| 직업 | 런타임 ID 두 개 | 원본 프레임 폴더 |
|---|---|---|
| 수호목수 | `char.guardian.walk`, `char.guardian.attack` | `assets/player_guardian/` |
| 톱니전사 | `char.sawtooth.walk`, `char.sawtooth.attack` | `assets/player_berserker/` |
| 솔방울사수 | `char.pinecone.walk`, `char.pinecone.attack` | `assets/player_ranger/` |
| 수액주술사 | `char.sapshaman.walk`, `char.sapshaman.attack` | `assets/player_shaman/` |
| 수압공학자 | `char.hydro.walk`, `char.hydro.attack` | `assets/player_engineer/` |

- 각 시트: 512×512 RGBA 투명 PNG, 4열×4행.
- 각 프레임: 128×128. 열 순서: 0 → 1 → 2 → 3.
- **시트 행 순서: 아래 `down` → 위 `up` → 왼쪽 `left` → 오른쪽 `right`.** 기존 런타임 매니페스트 기준입니다. 원본 팩의 방향 나열 순서로 행을 추측하지 마세요.
- 정규화 앵커: `[0.5, 0.82]`. 픽셀로는 `[64, 104.96]`, 원본 프레임 메타데이터에는 반올림한 `[64, 105]`를 기록했습니다.
- 걷기: 8fps, 4프레임, 0.5초 순환. 접지 A → 통과 A → 접지 B → 통과 B.
- 공격: 8fps 기본값, 준비 → 휘두름/발사 동작 → 동작 끝 → 복귀. 게임에서는 비반복 재생. 기존 `hit: 2` 이벤트 유지.
- 오른쪽은 왼쪽을 정확히 반전한 이미지입니다. 별도로 다시 반전하지 마세요.

## 현재 임포터에 관한 확인 사항

확인한 프로젝트의 `tools/import_asset_pack.gd`는 v1~v5의 팩 이름과 직업별 가져오기 대상을 직접 지정합니다. **v6 폴더만 추가하고 `--packs=`를 실행하는 것으로는 이번 10개 시트가 모두 교체되지 않습니다.** 같은 ID라는 사실만으로 신규 팩이 자동 인식되지는 않습니다.

따라서 이번에는 **이미 조립된 시트 10장을 기존 `final_path`로 복사하는 방법**을 권장합니다. 동봉 도구가 파일을 백업하고 해당 10개 매니페스트 항목만 갱신합니다. 게임 스크립트를 수정할 필요가 없습니다. 기존 임포터를 나중에 다시 실행하면 구버전 시트로 덮어쓸 수 있으므로, 재임포트 후에는 v6 적용을 마지막에 다시 실행하세요.

## 권장 적용 방법 — 개발 프로젝트에 반영

1. 압축을 풉니다. `beaver_assets_v6/` 폴더를 확인합니다.
2. 기존 코드 작업을 보존한 상태에서, 아래 경로를 실제 폴더로 바꿔 먼저 미리 검사합니다. Python 3.9 이상이며 설치 도구에는 추가 패키지가 필요 없습니다.

```bash
python "/path/to/beaver_assets_v6/tools/apply_v6.py" --project "/path/to/Beaver-RPG" --dry-run
```

3. 10개 ID와 대상 경로가 정상 확인되면 적용합니다.

```bash
python "/path/to/beaver_assets_v6/tools/apply_v6.py" --project "/path/to/Beaver-RPG"
```

도구는 기존 시트와 `assets/asset_manifest.json`을 `asset_backups/v6_<실행시각>/`에 먼저 복사합니다. 10개 ID의 `final_path`에 시트를 복사하고 앵커를 `[0.5, 0.82]`로 맞춥니다. 프레임 수·방향 규격이 다르면 덮어쓰기 전에 중단합니다. FPS, 타격 이벤트, 렌더 크기, 히트박스 및 다른 에셋 항목은 보존합니다. 검증 상태는 `not_run`으로 둡니다.

4. 실행 파일 옆 `asset_overrides/`에 이 10개 ID의 이전 PNG가 있으면 **별도 백업 폴더로 옮겨둡니다.** 외부 오버라이드가 프로젝트 시트보다 우선합니다.
5. Godot 리소스를 갱신하고 검사합니다. 환경에 따라 `godot` 대신 실제 Godot 실행 파일 경로를 사용하세요.

```bash
godot --headless --path "/path/to/Beaver-RPG" --import
godot --headless --path "/path/to/Beaver-RPG" -- --tool=check_assets
```

6. 실제 게임에서 5직업 × 4방향의 걷기/공격, idle 전환, 회피 전환, 4인 밀집 상태를 확인합니다. `check_assets` 0 문제를 확인한 뒤 `docs/screenshots/room_density_4p.png`를 다시 촬영하고 이전 버전과 비교합니다. 동봉 미리보기는 실제 게임 캡처가 아닙니다.

되돌릴 때는 실행 중인 게임을 종료하고 해당 백업 폴더의 파일을 원래 상대 경로로 복사하세요. `backup_index.json`에서 원래 없었던 파일도 확인할 수 있습니다. 백업 매니페스트를 복원하면 **그 이후에 추가한 다른 에셋 변경도 사라질 수 있으므로**, 후속 개발이 진행된 경우 버전 관리에서 해당 10개 항목만 되돌리세요.

## 빠른 외형 확인 — 실행 파일 옆 오버라이드

압축 안의 `asset_overrides/`에 들어 있는 PNG 10장을 실행 파일 옆의 같은 이름 폴더에 복사하면 됩니다. 기존 파일은 먼저 백업하세요. 파일 이름은 `char.guardian.walk.png`처럼 **점을 유지**해야 합니다.

이 경로는 PNG만 바꿉니다. 실행 파일에 들어 있는 이전 앵커 `[0.5, 0.828]`은 바뀌지 않아 약 1px의 차이가 생길 수 있습니다. 정확한 v6 앵커 반영과 배포에는 위의 프로젝트 적용 방법을 사용하세요.

## 폴더 설명

| 경로 | 용도 |
|---|---|
| `sheets/` | ID별 완성 시트 10장 |
| `project_files/assets/final/` | 기존 프로젝트 파일명으로 준비한 같은 시트 10장 |
| `asset_overrides/` | 실행 파일 옆 외부 오버라이드용 같은 시트 10장 |
| `assets/<actor>/<state>/<direction>_00.png` | v3a와 같은 경로 규칙의 개별 프레임 160장 |
| `manifest.json` | v3a의 `actors` 구조를 유지한 원본 프레임 목록 + 런타임 시트 매핑 |
| `sources/` | 직업별 원화 부품 아틀라스, 잘라낸 부품, 고정 몸체 레이어, 제작 프롬프트 |
| `tools/rebuild_sheets.py` | 같은 부품으로 시트를 다시 조립하는 재현용 도구 |
| `tools/apply_v6.py` | 백업 후 기존 프로젝트의 10개 ID에 적용 |
| `tools/validate_assets.py` | 프레임·시트 규격 및 움직임 차이 검사 |
| `preview/walk_8fps.gif`, `preview/attack_8fps.gif` | 5직업 × 4방향 동작 미리보기 |
| `docs/qa_report.json`, `docs/png_sha256.json` | 실제 검사 결과 및 PNG 해시 |

v3a의 `actors`는 **매니페스트의 키 이름**입니다. 이미지의 실제 경로는 `assets/player_.../walk/down_00.png` 형식입니다. `actors/`라는 이미지 폴더로 경로를 임의 변경하지 마세요.

`preview`의 열은 수호목수 → 톱니전사 → 솔방울사수 → 수액주술사 → 수압공학자, 행은 아래 → 위 → 왼쪽 → 오른쪽입니다. 공격 GIF는 비교 편의를 위해 반복되지만 실제 공격 애니메이션의 `loop` 값은 `false`입니다.

## 개발 담당자에게 붙여넣을 요청

> 첨부한 beaver_assets_v6.zip을 현재 Beaver RPG 프로젝트에 적용해줘. 이번 변경은 5직업의 walk/attack, 총 10개 런타임 ID만 대상으로 해. START_HERE.md를 먼저 읽고 기존 매니페스트·임포터·외부 asset_overrides 우선순위를 확인해줘. 현재 임포터가 v6를 인식하지 못하면 팩 폴더만 추가한 것으로 완료 처리하지 말고, 동봉 apply_v6.py의 --dry-run 후 실제 적용으로 시트를 교체해줘. 기존 파일을 백업하고 앵커 [0.5, 0.82], 512×512 시트, 128×128 프레임, down/up/left/right 행 순서, 4프레임을 확인해줘. 기존 FPS·타격 이벤트·히트박스·전투 수치와 다른 에셋은 보존해줘. 리소스 재임포트 후 check_assets가 0 문제인지 확인하고 5직업의 4방향 걷기/공격을 실제 재생해줘. 특히 3→0 걷기 연결과 idle 전환을 확인하고, 4인 밀집 장면을 docs/screenshots/room_density_4p.png로 다시 캡처해줘. 파일 검사 통과와 게임 실기 검증 완료를 구분해서 보고해줘. 기존 전체 팩을 재임포트한다면 v6 교체를 마지막에 다시 적용해줘.

## 후속 제작과 검증 범위

새로운 idle/hit/dodge/cast/death 애니메이션은 이번 교체 범위에 없습니다. 해당 상태로 전환할 때 원화 스타일이나 앵커 차이가 드러나는지는 게임에서 확인해야 합니다. 추가 상태를 제작할 때는 `sources/rig/`의 같은 몸체와 부품을 재사용하세요.

재조립에는 Python, Pillow, NumPy, ImageMagick의 `convert` 명령이 필요합니다. PNG만 게임에 적용할 때는 이 의존성이 필요 없습니다. 원본 팩의 사본에서 다음을 실행하면 됩니다.

```bash
python tools/rebuild_sheets.py
python tools/validate_assets.py
```

몸체 레이어는 고정되어도 공격하는 팔이 몸체 앞을 가리는 픽셀은 달라집니다. 이것을 몸 크기 변경으로 판단하지 마세요. 전체 실루엣의 폭은 공격 방향에 따라 변하는 것이 정상입니다. 원거리 직업은 큰 근접 무기 휘두르기 대신 조준·발사·반동을 표현했습니다.
