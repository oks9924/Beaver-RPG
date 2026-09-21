# 로그라이크 표준 설계 조사와 적용 (v0.3.0)

2026-09-21. 인터넷에서 널리 쓰이는 액션·협동 로그라이크의 진행·난이도·보상 규칙을 조사해 우리 구조(서버 판정, 데이터 파일, 1~4인 프로필)에 맞게 옮겼다. 수치는 전부 `data/*.json` 이며 실기 플레이 뒤 조정한다.

## 1. 조사 요약 (출처)

| 게임 | 가져온 규칙 | 출처 |
|---|---|---|
| Risk of Rain 2 | **디렉터 크레딧**: 시간에 따라 쌓이는 크레딧으로 적 무리를 사서 스폰. **시간 위험도**: 경과 시간에 따라 적 레벨이 오르고 난이도가 속도를 정한다(Drizzle 50%, Monsoon 150%). **정예 접두**: Blazing(불 자국), Glacial(둔화·사망 폭발), Overloading(재생 보호막), Malachite(회복 차단). **제단**: 운의 제단(도토리로 도박), 피의 제단(체력→돈), 전투의 제단(적 소환→보상) | [Difficulty](https://riskofrain2.wiki.gg/wiki/Difficulty), [Monsters](https://riskofrain2.wiki.gg/wiki/Monsters), [Shrines](https://riskofrain.fandom.com/wiki/Shrines_(Risk_of_Rain_2)), [정예 설계 분석](https://parryeverything.com/2021/08/13/the-elites-of-risk-of-rain-2-efficient-design-and-the-fundamentals-of-real-time-combat/) |
| Hades | **형벌의 서약(열기)**: 모듈형 난이도를 단계별로 쌓고 열기 합계에 따라 보상. **보온 희귀도**: 일반/희귀/영웅/전설, 깊이·조건에 따라 희귀가 잦아짐 | [Pact of Punishment](https://hades.fandom.com/wiki/Pact_of_Punishment), [Boons](https://hades.fandom.com/wiki/Boons) |
| Slay the Spire | **휴식처 선택**: 휴식(회복 30%) 또는 대장간(카드 강화). **정예 = 유물 보상**. 지도에서 보상 종류를 미리 보고 경로를 고른다 | [Map Locations](https://slaythespire.wiki.gg/wiki/Map_Locations) |
| Dead Cells | **저주 상자**: 강한 보상 + 저주. **시간 문**: 정해진 시간 안에 오면 추가 보상 | [Objects](https://deadcells.wiki.gg/wiki/Objects) |
| Deep Rock Galactic | 위험도 × 인원수로 적 수·체력·피해가 함께 오른다 (1~4인 피해 약 25% 차이) | [Difficulty Scaling](https://deeprockgalactic.wiki.gg/wiki/Difficulty_Scaling) |

## 2. 우리 환경에 맞춘 재구성

| 표준 | 우리 구현 | 데이터 | 코드 |
|---|---|---|---|
| 디렉터 크레딧 | 웨이브(3회)가 다 나온 뒤 방 예산의 50%를 초당 8%씩 크레딧으로 풀어 적이 3마리 이하일 때 1~3마리씩 증원. 예산이 다하면 증원이 끝나 방은 반드시 끝난다 | `rules.director` | `CombatRoom._step_director` |
| 시간 위험도 | 위험도 = 1 + 전투 누적 분 × 0.06 × 난이도 속도(느긋 0.5 / 기준 1 / 검은 물 1.5) + 층 × 0.03, 상한 2.2. 적 체력(80% 반영)·피해(50%)·웨이브 예산(30%)·정예 확률에 곱한다. 메뉴·투표 시간은 세지 않는다 | `rules.danger`, `difficulties.danger_pace` | `ExpeditionInstance.danger()`, `effective_profile()` |
| 형벌의 서약 | 서약 8종(단단한 갑각·사나운 강·정예의 계절·마른 수액·짧은 숨·차오르는 물·비싼 노점·오래된 갑각), 단계별 열기. 열기 1당 기억 조각 +15%, 도토리 +10%. 계정에 최고 완주 열기 기록 | `data/pacts.json` | `ContentDB.normalize_pacts`, `ExpeditionInstance.set_pacts/pact_sum`, `ServerMain._on_run_finished` |
| 정예 접두 | 젖은(둔화·웅덩이), 검은 수액(회복 절반), 가시 껍질(근접 반사 출혈), 재생 껍질, 분열(작은 2마리). 일반 스폰이 `elite_chance`(기본 6% × 난이도 × 서약 × 위험도)로 정예가 되며 웨이브당 1마리. 정예방 고정 정예도 접두 1개. 색 링과 이름으로 구분 | `data/elites.json` | `_spawn_enemy`, `_apply_affix_on_hit`, `_affix_on_death`, `EntityView.affix_color` |
| 보온 희귀도 | 유물 일반/희귀/전설 가중치 1 / 0.25 / 0.06, 층마다 희귀 가중치 +12%, 유물 `rare_chance_add` 반영. 강화는 진화=전설, 중첩형=희귀. 카드에 희귀도 표기 | `rules.rarity_weights`, `rarity_layer_bonus` | `_weighted_relic`, `_make_reward_options` |
| 리롤 | 런당 1회 다시 뽑기 (같은 시드 흐름) | `rules.reward_rerolls_per_run` | `reroll_reward`, `REWARD_PICK {reroll}` |
| 제단 | 운의 제단(도토리 15/40 → 45%/85% 유물, 큰 판은 희귀 보장), 피의 제단(체력 35% → 도토리 25), 저주받은 상자(희귀 유물 + 2방 받는 피해 +30%), 전투의 제단(다음 방 정예 + 예산 +4, 완주 시 기억 조각 +2) | `data/events.json` | `_resolve_event` 효과 유형 5개 추가 |
| 휴식처 | 각자 휴식(회복 40% + 회복 도구) 또는 숫돌(무작위 강화 1, 회복 없음). 안 고르면 휴식 | — | `_apply_rest_choice`, `NODE_ACTION rest_choice` |
| 시간 문 | 방을 70 + 10×인원 초 안에 깨면 도토리 +10, 경험치 +25% | `rules.room_par` | `_on_room_finished` |
| 페이싱 대응안 | 섬멸 웨이브 2→3, 예산 6→9, 다음 웨이브 조건 3마리 이하. 보스 체력 520→900(두꺼비 1050·뿌리왕 1425), 기믹 간격 12→9초, 갑각 온전 시 받는 피해 60%, 기믹 실패 시 보스 5% 회복 + 추가 적 2 (1~2인도) | `rooms.json`, `bosses.json`, `party_scaling.json` | `damage_taken_mult`, `_finish_mechanic` |

## 3. 인원 스케일과의 관계
인원 프로필(1~4인)이 먼저 곱해지고 그 위에 난이도 → 서약 → 위험도 순으로 곱한다. DRG 처럼 4인은 1인보다 적 수(예산 ×2.0)와 체력(×1.2)이 함께 오르며, 위험도는 파티 공통이다.

## 4. 조정 손잡이 (실기 뒤 만질 것)
- 방이 길다/짧다 → `rules.director.reserve_frac`(증원 양), `credit_per_sec_frac`(증원 속도), `rooms.*.waves.base_budget`.
- 뒤로 갈수록 너무 어렵다 → `rules.danger.per_combat_min`, `max`, `hp_weight`.
- 정예가 잦다/드물다 → `elites.spawn.base_chance`, `max_affix_elites_per_wave`.
- 서약이 싱겁다 → `pacts.json` 의 `*_per_rank`, `_rewards.shards_mult_per_heat`.
- 희귀가 안 나온다 → `rules.rarity_weights`, `rarity_layer_bonus`.
