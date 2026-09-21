# 에셋 요청 v5 — 장비·제작·강화 UI (2026-09-21)

영구 장비(드랍·장착·강화·재감정·분해·제작)가 들어가서 아이콘과 UI 조각이 필요합니다. 코드는 에셋 ID 로만 참조하고, 없으면 등급 색 글자로 표시합니다(현재 상태). 규격은 v4 아이콘과 같습니다: 64×64 PNG, 투명 배경, 4방향 아님(정면 1장). 시트는 가로 나열, `docs/asset_plan.md` 의 아이콘 절 규칙을 따릅니다.

## A. 장비 아이콘 (17)
| ID | 내용 | 비고 |
|---|---|---|
| icon.gear.guardian_hammer | 나무망치 | 수호목수 기본 무기 |
| icon.gear.guardian_log | 통나무 | 수호목수 2번 무기 (넓고 느린 밀치기) |
| icon.gear.sawtooth_axe | 쌍톱 손도끼 | 톱니전사 기본 |
| icon.gear.sawtooth_greatsaw | 대톱 | 톱니전사 2번 (무겁고 경직) |
| icon.gear.pinecone_sling | 솔방울 새총 | 솔방울사수 기본 |
| icon.gear.pinecone_launcher | 솔방울 투척기 | 솔방울사수 2번 (산탄 3발) |
| icon.gear.sap_staff | 수액 지팡이 | 수액주술사 기본 |
| icon.gear.sap_dripper | 수액 방울총 | 수액주술사 2번 (출혈) |
| icon.gear.hydro_pump | 물총 펌프 | 물길공학자 기본 |
| icon.gear.hydro_wrench | 수문 렌치 | 물길공학자 2번 (근접·설치물 강화) |
| icon.gear.bark_vest | 나무껍질 조끼 | 갑옷 |
| icon.gear.shell_plate | 껍질 판갑 | 갑옷 |
| icon.gear.moss_cloak | 이끼 망토 | 갑옷 |
| icon.gear.river_pebble | 강돌 부적 | 장신구 |
| icon.gear.acorn_charm | 도토리 부적 | 장신구 |
| icon.gear.firefly_bead | 반딧불 구슬 | 장신구 |
| icon.gear.resin_ring | 송진 반지 | 장신구 |

전설 고유 9종은 기본 아이템 아이콘에 전설 테두리를 씌우므로 별도 아이콘이 필요 없습니다.

## B. 등급·상태 UI (5)
| ID | 내용 | 규격 |
|---|---|---|
| ui.frame.rarity | 등급 테두리 5프레임: 일반 흰 · 고급 초록(#7be07b) · 희귀 파랑(#6fb6ff) · 영웅 보라(#c58cff) · 전설 주황(#ffb347) | 64×64 시트 5칸, 안쪽 48×48 투명 |
| ui.badge.enhance | 강화 단계 배지 "+N" 바탕 (숫자는 코드가 씀) | 24×24 |
| ui.slot.gear | 장착 슬롯 빈 칸 4종(무기·갑옷·장신구·잠김) | 64×64 시트 4칸 |
| ui.icon.locked | 자물쇠 (잠긴 도안) | 32×32 |
| ui.icon.crafted | 제작품 표시 (작은 망치) | 24×24 |

## C. 재료·제작 (4)
| ID | 내용 | 규격 |
|---|---|---|
| icon.material.sap_crystal | 수액 결정 (호박색 결정) | 64×64 |
| icon.blueprint.weapon | 무기 도안 (두루마리 + 망치 실루엣) | 64×64 |
| icon.blueprint.armor | 갑옷 도안 | 64×64 |
| icon.blueprint.trinket | 장신구 도안 | 64×64 |

## D. 강화 결과 연출 (3, 선택)
| ID | 내용 | 규격 |
|---|---|---|
| vfx.enhance.success | 반짝임 6프레임 | 96×96 시트, 0.5초 |
| vfx.enhance.fail | 연기 4프레임 | 96×96 시트 |
| vfx.enhance.destroy | 산산조각 8프레임 | 128×128 시트, 0.8초 |
| sfx.enhance.success / sfx.enhance.fail / sfx.enhance.destroy | 효과음 3종 | ogg, 1초 이내 |

## 연결 방법
`assets/asset_manifest.json` 에 위 ID 로 항목을 넣고 `tools/import_asset_pack.gd --packs=` 로 들이면 됩니다. 장비 탭(`client/ui/hub_screen.gd` 의 `_item_button`)은 `icon.gear.<base>` 가 `final` 이면 아이콘을 앞에 붙이고, 등급 테두리는 `ui.frame.rarity` 프레임을 등급 지수로 고릅니다. 아이콘이 없어도 동작에는 영향이 없습니다.
