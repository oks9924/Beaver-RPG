# v3 B~E 에셋 목록

인덱스는 0부터 시작합니다. 모든 경로는 `assets/<ID>/default/all_NN.png`, 상태 키는 `default_all`입니다. 상태 선택·레이어·변형 배열은 자동 애니메이션이 아닙니다.

| 그룹 | ID | 크기 | PNG 수 | 사용 방식 | 인덱스 의미 |
|---|---|---|---:|---|---|
| B | `vfx_hammer_swing` | 128×128 | 4 | one_shot | 0: short pale wood arc; 1: broad curved sweep; 2: wood dust at contact; 3: few fading splinters |
| B | `vfx_log_shield` | 128×128 | 4 | loop | 0: grain glow low; 1: grain glow rising; 2: grain glow high; 3: grain glow falling |
| B | `vfx_tail_shockwave` | 256×256 | 5 | one_shot | 0: tiny ground dust puff; 1: small dust circle; 2: wide ground dust ring; 3: broken drifting ring; 4: few dissipating dust wisps |
| B | `vfx_great_tree` | 512×512 | 6 | state_sequence | 0: short root shoots; 1: roots spread; 2: trunk grows; 3: leaf canopy opens; 4: sheltering canopy settles; 5: stable active leafy canopy |
| B | `vfx_sling_shot` | 128×128 | 3 | one_shot | 0: compact leaf burst; 1: leaf fragments spread right; 2: few fading leaf fragments |
| B | `vfx_acorn_scatter` | 256×256 | 4 | one_shot | 0: three close acorns; 1: five acorns fan outward; 2: wide fan of acorns and leaves; 3: few fading leaf fragments |
| B | `vfx_thorn_trap` | 128×128 | 4 | state_sequence | 0: coiled roots just placed; 1: compact thorn coil waiting; 2: same coil gently pulsing; 3: thorn spikes snap upward |
| B | `vfx_forest_volley` | 256×256 | 6 | one_shot | 0: two descending pinecones; 1: more descending pinecones; 2: first pinecones land; 3: many land with pale dust; 4: impact leaf scatter; 5: faint last dust and leaves |
| B | `vfx_projectile_pinecone` | 32×32 | 2 | loop | 0: pinecone angled clockwise; 1: pinecone tumbled slightly farther |
| B | `vfx_projectile_sap` | 32×32 | 2 | loop | 0: plump purple droplet; 1: elongated purple droplet |
| B | `vfx_hit_spark` | 64×64 | 3 | one_shot | 0: small tight splinter burst; 1: wide pale woodchip starburst; 2: few separated fading chips |
| B | `vfx_rescue_ring` | 128×128 | 4 | loop | 0: green leaf ring gentle phase one; 1: green leaf ring phase two; 2: green leaf ring phase three; 3: green leaf ring phase four |
| B | `vfx_heal_burst` | 128×128 | 4 | one_shot | 0: small green sap bubbles; 1: bubbles and leaves rise; 2: full gentle green healing bloom; 3: few drifting leaves |
| B | `vfx_boss_rock_impact` | 256×256 | 4 | one_shot | 0: rock contacts ground; 1: gray fragments erupt; 2: fragments spread with pale dust; 3: few settled chips |
| B | `vfx_boss_ground_slam` | 512×512 | 5 | one_shot | 0: small central ground crack; 1: cracks branch outward; 2: water splash peaks; 3: falling droplets and broken soil; 4: quiet cracks with small mist |
| B | `vfx_whirlpool` | 512×512 | 4 | loop | 0: water spiral phase one; 1: water spiral phase two; 2: water spiral phase three; 3: water spiral phase four |
| C | `tile_willow_ground` | 64×64 | 4 | select_frame | 0: small bright grass flecks; 1: sparse dirt patch; 2: tiny scattered pebbles; 3: subtle clover flecks |
| C | `tile_willow_wall` | 64×64 | 9 | select_frame | 0: solid dense bank foliage; 1: north bank edge; 2: east bank edge; 3: south bank edge; 4: west bank edge; 5: concave inner northwest corner; 6: concave inner northeast corner; 7: concave inner southeast corner; 8: concave inner southwest corner |
| C | `tile_willow_water` | 64×64 | 2 | loop | 0: quiet shallow ripples phase one; 1: same shallow water ripples phase two |
| C | `tile_willow_shore` | 64×64 | 4 | select_frame | 0: grass north water south; 1: water west grass east; 2: water north grass south; 3: grass west water east |
| C | `tile_willow_bridge` | 64×64 | 2 | select_frame | 0: horizontal east-west bridge; 1: vertical north-south bridge |
| C | `tile_hub_ground` | 64×64 | 2 | select_frame | 0: packed village dirt; 1: weathered wooden planks |
| C | `prop_gnaw_tree` | 256×256 | 3 | select_frame | 0: intact slim willow trunk; 1: trunk half gnawed near base; 2: fallen trunk and stump with dropped wood |
| C | `prop_device` | 256×256 | 4 | select_frame | 0: bare frame no gears zero percent; 1: one fitted gear one third complete; 2: gears and pulley two thirds complete; 3: completed wooden mechanism with gentle green indicator |
| C | `prop_lever` | 256×256 | 2 | select_frame | 0: lever lowered; 1: lever raised |
| C | `prop_sluice_gate` | 256×256 | 3 | select_frame | 0: closed vertical wooden gate; 1: gate halfway lifted small flow; 2: gate open clear water pouring underneath |
| C | `prop_log_cover` | 256×256 | 2 | select_frame | 0: intact log barricade; 1: broken log barricade |
| C | `prop_willow_log` | 256×256 | 2 | select_frame | 0: broad fallen willow log; 1: narrow forked fallen log |
| C | `prop_willow_rock` | 256×256 | 2 | select_frame | 0: round gray-green river boulder; 1: flat cluster of smooth river stones |
| C | `prop_hold_point` | 256×256 | 2 | select_frame | 0: drooping desaturated leaf flag inactive; 1: upright bright green leaf flag active |
| C | `prop_campfire` | 256×256 | 2 | loop | 0: flame leans slightly left; 1: flame leans slightly right |
| C | `prop_stall` | 256×256 | 1 | select_frame | 0: merchant riverside stall |
| C | `prop_memory_tree` | 512×512 | 3 | select_frame | 0: withered bare memory tree; 1: same tree with fresh small green buds; 2: same tree with glowing full leaves |
| C | `prop_workshop` | 256×256 | 3 | select_frame | 0: collapsed wooden workshop; 1: same workshop repaired roof; 2: same restored workshop with chimney smoke |
| C | `prop_expedition_board` | 256×256 | 1 | select_frame | 0: blank expedition noticeboard |
| D | `icon_skill_guardian_q` | 64×64 | 1 | select_frame | 0: 통나무 방패 |
| D | `icon_skill_guardian_e` | 64×64 | 1 | select_frame | 0: 꼬리 내려치기 |
| D | `icon_skill_guardian_r` | 64×64 | 1 | select_frame | 0: 거목의 품 |
| D | `icon_skill_ranger_q` | 64×64 | 1 | select_frame | 0: 도토리 산탄 |
| D | `icon_skill_ranger_e` | 64×64 | 1 | select_frame | 0: 가시 덫 |
| D | `icon_skill_ranger_r` | 64×64 | 1 | select_frame | 0: 숲의 일제사격 |
| D | `icon_heal` | 64×64 | 1 | select_frame | 0: 회복 |
| D | `icon_dodge` | 64×64 | 1 | select_frame | 0: 회피 |
| D | `icon_relic_oak_heart` | 64×64 | 1 | select_frame | 0: 참나무 심장 |
| D | `icon_relic_sharp_incisors` | 64×64 | 1 | select_frame | 0: 날카로운 앞니 |
| D | `icon_relic_river_stone` | 64×64 | 1 | select_frame | 0: 강돌 |
| D | `icon_relic_quick_paws` | 64×64 | 1 | select_frame | 0: 빠른 발 |
| D | `icon_relic_sap_amber` | 64×64 | 1 | select_frame | 0: 수액 호박 |
| D | `icon_relic_hunters_tooth` | 64×64 | 1 | select_frame | 0: 사냥꾼 이빨 |
| D | `icon_relic_kin_bond` | 64×64 | 1 | select_frame | 0: 혈족의 끈 |
| D | `icon_relic_thorn_tail` | 64×64 | 1 | select_frame | 0: 가시 꼬리 |
| D | `icon_relic_heavy_paddle` | 64×64 | 1 | select_frame | 0: 무거운 노 |
| D | `icon_relic_acorn_pouch` | 64×64 | 1 | select_frame | 0: 도토리 주머니 |
| D | `icon_status_slow` | 64×64 | 1 | select_frame | 0: 둔화 |
| D | `icon_status_bleed` | 64×64 | 1 | select_frame | 0: 출혈 |
| D | `icon_status_shield` | 64×64 | 1 | select_frame | 0: 보호막 |
| D | `icon_status_mark` | 64×64 | 1 | select_frame | 0: 표식 |
| D | `icon_status_stagger` | 64×64 | 1 | select_frame | 0: 경직 |
| D | `icon_status_wet` | 64×64 | 1 | select_frame | 0: 젖음 |
| E | `ui_panel` | 96×96 | 1 | select_frame | 0: panel |
| E | `ui_button` | 96×48 | 3 | select_frame | 0: normal; 1: hover; 2: pressed |
| E | `ui_card_reward` | 256×352 | 2 | select_frame | 0: relic; 1: upgrade |
| E | `ui_card_route` | 256×160 | 5 | select_frame | 0: combat; 1: event; 2: shop; 3: rest; 4: boss |
| E | `ui_bar_hp` | 256×24 | 2 | select_frame | 0: frame; 1: fill |
| E | `ui_bar_boss` | 512×32 | 1 | select_frame | 0: frame |
| E | `ui_title_logo` | 1024×512 | 1 | select_frame | 0: blank_logo |
| E | `ui_app_icon` | 256×256 | 1 | select_frame | 0: app_icon |
| E | `ui_frame_portrait` | 288×288 | 1 | select_frame | 0: frame |
