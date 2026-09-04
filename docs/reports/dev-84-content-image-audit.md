# DEV-78 콘텐츠 이미지 연결 감사

기준: `data/generated/items.json`, `data/generated/monsters.json`, `assets/asset-manifest.json`, `assets/promoted-assets-manifest.json`, `assets/style/art-style-tokens.json`.

## 요약

- 런타임 대상 행: 60개
- 아이템·다구: 39개
- 몬스터·요괴: 21개
- 파일 경로 무결성 누락/깨짐: 0개
- 전용 에셋 미해결: 11개
- 사람 아트 검수 필요: 45개
- 런타임 승인 매핑: 48개

`missing_or_broken`/`path_integrity_missing_or_broken`은 현재 연결된 manifest asset ID와 PNG 파일 경로의 무결성 지표다. 전용 에셋 완료 지표가 아니며, 미검수 아이템 매핑은 `runtime_approved=false`로 런타임 조회에서 제외한다.

## Notion 확인 한계

`query_data_sources` 사용량 제한으로 🎨 아트 에셋 DB의 relation/파일 필드는 행 단위로 재조회하지 못했다. 이 리포트는 현재 저장소에 export된 정적 데이터와 manifest 기준 감사 결과이며, Notion DB relation 반영은 쿼리 제한 해제 후 재검증이 필요하다.

## 아이템·다구

| content_id | 이름 | 종류 | resolution | runtime_approved | dedicated_asset_missing | asset_id | path | 예외 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ash_stained_iron_kettle` | 재 묻은 철솥 | 다구 | dedicated_item_icon | True | False | `item_ash_stained_iron_kettle_icon` | `res://assets/sprites/items/ash_stained_iron_kettle_32x32.png` |  |
| `bandage` | 천 붕대 | 소모품 | dedicated_item_icon | True | False | `item_cloth_bandage_icon` | `res://assets/sprites/items/cloth_bandage_32x32.png` |  |
| `black_bamboo_tea_scoop` | 검은 대나무 찻숟가락 | 다구 | dedicated_item_icon | True | False | `item_black_bamboo_tea_scoop_icon` | `res://assets/sprites/items/black_bamboo_tea_scoop_32x32.png` |  |
| `blacksmith_forge` | 대장간 | 도구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_low_table_png` | `res://assets/ui/icons/atlas/low_table.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `charcoal` | 숯 | 재료 | dedicated_item_icon | True | False | `item_charcoal_icon` | `res://assets/sprites/items/charcoal_32x32.png` |  |
| `clay` | 점토 | 재료 | dedicated_item_icon | True | False | `item_clay_icon` | `res://assets/sprites/items/clay_32x32.png` |  |
| `cloth` | 천 조각 | 재료 | dedicated_item_icon | True | False | `item_cloth_scraps_icon` | `res://assets/sprites/items/cloth_scraps_32x32.png` |  |
| `conifer_wood` | 침엽수 목재 | 재료 | dedicated_item_icon | True | False | `item_conifer_wood_icon` | `res://assets/sprites/items/conifer_wood_32x32.png` |  |
| `copper_ore` | 구리광석 | 재료 | dedicated_item_icon | True | False | `item_copper_ore_icon` | `res://assets/sprites/items/copper_ore_32x32.png` |  |
| `humble_clay_bowl` | 소박한 흙사발 | 다구 | dedicated_item_icon | True | False | `item_humble_clay_bowl_icon` | `res://assets/sprites/items/humble_clay_bowl_32x32.png` |  |
| `incense_sticks` | 선향 | 향 | dedicated_item_icon | True | False | `item_incense_sticks_icon` | `res://assets/sprites/items/incense_sticks_32x32.png` |  |
| `insulated_tea_bottle` | 보온 차병 | 다구 | dedicated_item_icon | True | False | `item_insulated_tea_bottle_icon` | `res://assets/sprites/items/insulated_tea_bottle_32x32.png` |  |
| `iron_kettle` | 철 차솥 | 다구 | dedicated_item_icon | True | False | `item_iron_kettle_icon` | `res://assets/sprites/items/iron_kettle_32x32.png` |  |
| `iron_ore` | 철광석 | 재료 | dedicated_item_icon | True | False | `item_iron_ore_icon` | `res://assets/sprites/items/iron_ore_32x32.png` |  |
| `item_28` | 철 조각 | 재료 | dedicated_item_icon | True | False | `item_iron_scrap_icon` | `res://assets/sprites/items/iron_scrap_32x32.png` |  |
| `item_29` | 되돌림 매듭 | 부활 아이템 | dedicated_item_icon | True | False | `item_reversal_knot_icon` | `res://assets/sprites/items/reversal_knot_32x32.png` |  |
| `item_33` | 동전 | 재료 | dedicated_item_icon | True | False | `item_coin_icon` | `res://assets/sprites/items/coin_32x32.png` |  |
| `item_5` | 침향 | 향 | dedicated_item_icon | True | False | `item_agarwood_icon` | `res://assets/sprites/items/agarwood_32x32.png` |  |
| `metal_workbench` | 금속 가공대 | 도구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_low_table_png` | `res://assets/ui/icons/atlas/low_table.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `mountain_iron_dagger` | 산철 단도 | 무기 | dedicated_item_icon | True | False | `item_mountain_iron_dagger_icon` | `res://assets/sprites/items/mountain_iron_dagger_32x32.png` |  |
| `mountain_kiln` | 산중 가마 | 도구 | dedicated_item_icon | True | False | `item_mountain_kiln_object_64` | `res://assets/sprites/objects/crafting/mountain_kiln_64x64.png` |  |
| `mountain_wind_layered_clothes` | 산바람 겹옷 | 방어구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `old_incense_box` | 오래된 향합 | 다구 | dedicated_item_icon | True | False | `item_old_incense_box_icon` | `res://assets/sprites/items/old_incense_box_32x32.png` |  |
| `old_wood` | 오래된 목재 | 재료 | dedicated_item_icon | True | False | `item_old_wood_icon` | `res://assets/sprites/items/old_wood_32x32.png` |  |
| `oribe_green_glazed_bowl` | 오리베 녹유 찻사발 | 다구 | dedicated_item_icon | True | False | `item_oribe_green_glazed_bowl_icon` | `res://assets/sprites/items/oribe_green_glazed_bowl_32x32.png` |  |
| `portable_brazier` | 휴대 화로 | 도구 | dedicated_item_icon | True | False | `item_portable_brazier_icon` | `res://assets/sprites/items/portable_brazier_32x32.png` |  |
| `rare_wood` | 희귀 목재 | 재료 | dedicated_item_icon | True | False | `item_rare_wood_icon` | `res://assets/sprites/items/rare_wood_32x32.png` |  |
| `repair_hammer` | 수선 망치 | 도구 | dedicated_item_icon | True | False | `item_repair_hammer_icon` | `res://assets/sprites/items/repair_hammer_32x32.png` |  |
| `short_travel_sword` | 짧은 여행검 | 무기 | dedicated_item_icon | True | False | `item_short_travel_sword_icon` | `res://assets/sprites/items/short_travel_sword_32x32.png` |  |
| `snow_bamboo_overcoat` | 설죽 덧옷 | 방어구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `snowfield_mineral` | 설원 광물 | 재료 | dedicated_item_icon | True | False | `item_snowfield_mineral_icon` | `res://assets/sprites/items/snowfield_mineral_32x32.png` |  |
| `stone` | 돌 | 재료 | dedicated_item_icon | True | False | `item_stone_icon` | `res://assets/sprites/items/stone_32x32.png` |  |
| `stone_axe` | 돌도끼 | 도구 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_sword_png` | `res://assets/ui/icons/atlas/sword.png` |  |
| `traveler_quilted_clothes` | 여행자의 누비옷 | 방어구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `unbroken_failure` | 깨지지 않은 실패작 | 다구 | dedicated_item_icon | True | False | `item_unbroken_failure_icon` | `res://assets/sprites/items/unbroken_failure_32x32.png` |  |
| `war_tea_caddy` | 전란의 차입 | 다구 | dedicated_item_icon | True | False | `item_war_tea_caddy_icon` | `res://assets/sprites/items/war_tea_caddy_32x32.png` |  |
| `wood` | 목재 | 재료 | dedicated_item_icon | True | False | `item_wood_icon` | `res://assets/sprites/items/wood_32x32.png` |  |
| `wood_incense_burner` | 목향 향로 | 다구 | dedicated_item_icon | True | False | `item_wood_incense_burner_icon` | `res://assets/sprites/items/wood_incense_burner_32x32.png` |  |
| `wooden_workbench` | 목재 작업대 | 도구 | dedicated_item_icon | True | False | `item_wooden_workbench_object_64` | `res://assets/sprites/objects/crafting/wooden_workbench_64x64.png` |  |

## 몬스터·요괴

| content_id | 이름 | 종류 | resolution | runtime_approved | dedicated_asset_missing | asset_id | path | 예외 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `abandoned_mine_samurai` | 폐광 무사 | 도적·무사 | monster_id_convention | True | False | `monster_abandoned_mine_samurai_front_idle` | `res://assets/sprites/characters/monsters/abandoned_mine_samurai/abandoned_mine_samurai_front_idle_32x32.png` |  |
| `agarwood_thief` | 향목 도둑 | 도적·무사 | monster_id_convention | True | False | `monster_agarwood_thief_front_idle` | `res://assets/sprites/characters/monsters/agarwood_thief/agarwood_thief_front_idle_32x32.png` |  |
| `ash_crow_flock` | 잿빛 까마귀떼 | 야생동물 | monster_id_convention | True | False | `monster_ash_crow_flock_front_idle` | `res://assets/sprites/characters/monsters/ash_crow_flock/ash_crow_flock_front_idle_32x32.png` |  |
| `empty_armor_yokai` | 빈 갑주 요괴 | 요괴 | monster_id_convention | True | False | `monster_empty_armor_yokai_front_idle` | `res://assets/sprites/characters/monsters/empty_armor_yokai/empty_armor_yokai_front_idle_32x32.png` |  |
| `foxfire` | 여우불 | 요괴 | monster_id_convention | True | False | `monster_foxfire_front_idle` | `res://assets/sprites/characters/monsters/foxfire/foxfire_front_idle_32x32.png` |  |
| `frost_lantern_yokai` | 서리등불 요괴 | 요괴 | monster_id_convention | True | False | `monster_frost_lantern_yokai_front_idle` | `res://assets/sprites/characters/monsters/frost_lantern_yokai/frost_lantern_yokai_front_idle_32x32.png` |  |
| `monster_16` | 논두렁 멧돼지 | 야생동물 | monster_variant_fallback_exception | False | True | `monster_mountain_boar_front_idle` | `res://assets/sprites/characters/monsters/mountain_boar/mountain_boar_front_idle_32x32.png` | No dedicated monster asset exists; keep the closest existing variant for review only. |
| `monster_17` | 절벽 독수리 | 야생동물 | monster_variant_fallback_exception | False | True | `monster_ash_crow_flock_front_idle` | `res://assets/sprites/characters/monsters/ash_crow_flock/ash_crow_flock_front_idle_32x32.png` | No dedicated monster asset exists; keep the closest existing variant for review only. |
| `monster_18` | 모래갑옷 무사 | 도적·무사 | monster_variant_fallback_exception | False | True | `monster_abandoned_mine_samurai_front_idle` | `res://assets/sprites/characters/monsters/abandoned_mine_samurai/abandoned_mine_samurai_front_idle_32x32.png` | No dedicated monster asset exists; keep the closest existing variant for review only. |
| `monster_19` | 바람굶주린 도적 | 도적·무사 | monster_variant_fallback_exception | False | True | `monster_road_bandit_front_idle` | `res://assets/sprites/characters/monsters/road_bandit/road_bandit_front_idle_32x32.png` | No dedicated monster asset exists; keep the closest existing variant for review only. |
| `monster_20` | 눈굴 토끼요괴 | 요괴 | monster_variant_fallback_exception | False | True | `monster_frost_lantern_yokai_front_idle` | `res://assets/sprites/characters/monsters/frost_lantern_yokai/frost_lantern_yokai_front_idle_32x32.png` | No dedicated monster asset exists; keep the closest existing variant for review only. |
| `monster_21` | 향먹는 나방 | 요괴 | monster_variant_fallback_exception | False | True | `monster_agarwood_thief_front_idle` | `res://assets/sprites/characters/monsters/agarwood_thief/agarwood_thief_front_idle_32x32.png` | No dedicated monster asset exists; keep the closest existing variant for review only. |
| `moss_tree_yokai` | 이끼쓴 나무요괴 | 요괴 | monster_id_convention | True | False | `monster_moss_tree_yokai_front_idle` | `res://assets/sprites/characters/monsters/moss_tree_yokai/moss_tree_yokai_front_idle_32x32.png` |  |
| `mountain_boar` | 산멧돼지 | 야생동물 | monster_id_convention | True | False | `monster_mountain_boar_front_idle` | `res://assets/sprites/characters/monsters/mountain_boar/mountain_boar_front_idle_32x32.png` |  |
| `road_bandit` | 노상 도적 | 도적·무사 | monster_id_convention | True | False | `monster_road_bandit_front_idle` | `res://assets/sprites/characters/monsters/road_bandit/road_bandit_front_idle_32x32.png` |  |
| `snow_path_assassin` | 눈길 자객 | 도적·무사 | monster_id_convention | True | False | `monster_snow_path_assassin_front_idle` | `res://assets/sprites/characters/monsters/snow_path_assassin/snow_path_assassin_front_idle_32x32.png` |  |
| `snow_wolf` | 설원 늑대 | 야생동물 | monster_id_convention | True | False | `monster_snow_wolf_front_idle` | `res://assets/sprites/characters/monsters/snow_wolf/snow_wolf_front_idle_32x32.png` |  |
| `stonebound_yokai` | 돌붙이 요괴 | 요괴 | monster_id_convention | True | False | `monster_stonebound_yokai_front_idle` | `res://assets/sprites/characters/monsters/stonebound_yokai/stonebound_yokai_front_idle_32x32.png` |  |
| `swamp_snake` | 습지 뱀 | 야생동물 | monster_id_convention | True | False | `monster_swamp_snake_front_idle` | `res://assets/sprites/characters/monsters/swamp_snake/swamp_snake_front_idle_32x32.png` |  |
| `wandering_ronin` | 떠돌이 낭인 | 도적·무사 | monster_id_convention | True | False | `monster_wandering_ronin_front_idle` | `res://assets/sprites/characters/monsters/wandering_ronin/wandering_ronin_front_idle_32x32.png` |  |
| `wild_dog` | 들개 | 야생동물 | monster_id_convention | True | False | `monster_wild_dog_front_idle` | `res://assets/sprites/characters/monsters/wild_dog/wild_dog_front_idle_32x32.png` |  |

## 검증 이슈

- 누락, 깨진 경로, PNG 규격 이슈 없음.
