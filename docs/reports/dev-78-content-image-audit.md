# DEV-78 콘텐츠 이미지 연결 감사

기준: `data/generated/items.json`, `data/generated/monsters.json`, `assets/asset-manifest.json`, `assets/promoted-assets-manifest.json`, `assets/style/art-style-tokens.json`.

## 요약

- 런타임 대상 행: 55개
- 아이템·다구: 40개
- 몬스터·요괴: 15개
- 파일 경로 무결성 누락/깨짐: 0개
- 전용 에셋 미해결: 9개
- 사람 아트 검수 필요: 40개
- 런타임 승인 매핑: 15개

`missing_or_broken`/`path_integrity_missing_or_broken`은 현재 연결된 manifest asset ID와 PNG 파일 경로의 무결성 지표다. 전용 에셋 완료 지표가 아니며, 미검수 아이템 매핑은 `runtime_approved=false`로 런타임 조회에서 제외한다.

## Notion 확인 한계

`query_data_sources` 사용량 제한으로 🎨 아트 에셋 DB의 relation/파일 필드는 행 단위로 재조회하지 못했다. 이 리포트는 현재 저장소에 export된 정적 데이터와 manifest 기준 감사 결과이며, Notion DB relation 반영은 쿼리 제한 해제 후 재검증이 필요하다.

## 아이템·다구

| content_id | 이름 | 종류 | resolution | runtime_approved | dedicated_asset_missing | asset_id | path | 예외 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ash_stained_iron_kettle` | 재 묻은 철솥 | 다구 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_crafting_round_iron_kettle_stove_32x32_png` | `res://assets/sprites/objects/crafting/round_iron_kettle_stove_32x32.png` |  |
| `bandage` | 붕대 | 소모품 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_gourd_png` | `res://assets/ui/icons/atlas/gourd.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `black_bamboo_tea_scoop` | 검은 대나무 찻숟가락 | 다구 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_whisk_png` | `res://assets/ui/icons/atlas/whisk.png` |  |
| `clay` | 점토 | 재료 | semantic_existing_asset | False | False | `asset_assets_tiles_terrain_desert_cracked_clay_32x32_png` | `res://assets/tiles/terrain/desert/cracked_clay_32x32.png` |  |
| `cloth` | 천 | 재료 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `humble_clay_bowl` | 소박한 흙사발 | 다구 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_bowl_png` | `res://assets/ui/icons/atlas/bowl.png` |  |
| `item_28` | 철 조각 | 재료 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_mining_iron_ore_32x32_png` | `res://assets/sprites/objects/mining/iron_ore_32x32.png` |  |
| `item_29` | 부활 차씨 | 소모품 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_leaf_resource_png` | `res://assets/ui/icons/atlas/leaf_resource.png` |  |
| `item_32` | 천 조각 |  | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` |  |
| `item_33` | 동전 |  | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_coin_disc_png` | `res://assets/ui/icons/atlas/coin_disc.png` |  |
| `item_5` | 침향 | 향 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png` | `res://assets/sprites/objects/shrine-props/incense_burner_32x32.png` |  |
| `mountain_wind_layered_clothes` | 산바람 겹옷 | 방어구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `old_incense_box` | 오래된 향합 | 다구 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png` | `res://assets/sprites/objects/shrine-props/incense_burner_32x32.png` |  |
| `oribe_green_glazed_bowl` | 오리베 녹유 찻사발 | 다구 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_bowl_png` | `res://assets/ui/icons/atlas/bowl.png` |  |
| `short_travel_sword` | 짧은 여행검 | 무기 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_sword_png` | `res://assets/ui/icons/atlas/sword.png` |  |
| `snow_bamboo_overcoat` | 설죽 덧옷 | 방어구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `stone` | 돌 | 재료 | semantic_existing_asset | False | False | `small_rock_resource` | `res://assets/sprites/objects/natural-props/small_rock_32x32.png` |  |
| `stone_axe` | 돌도끼 | 도구 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_sword_png` | `res://assets/ui/icons/atlas/sword.png` |  |
| `traveler_quilted_clothes` | 여행자의 누비옷 | 방어구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `unbroken_failure` | 깨지지 않은 실패작 | 다구 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_bowl_png` | `res://assets/ui/icons/atlas/bowl.png` |  |
| `war_tea_caddy` | 전란의 차입 | 다구 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_tea_tin_png` | `res://assets/ui/icons/atlas/tea_tin.png` |  |
| `wood` | 목재 | 재료 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_village_props_firewood_pile_1x2_64x32_png` | `res://assets/sprites/objects/village-props/firewood_pile_1x2_64x32.png` |  |
| `iron_ore` | 철광석 | 재료 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_mining_iron_ore_32x32_png` | `res://assets/sprites/objects/mining/iron_ore_32x32.png` |  |
| `copper_ore` | 구리광석 | 재료 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_mining_copper_ore_32x32_png` | `res://assets/sprites/objects/mining/copper_ore_32x32.png` |  |
| `snowfield_mineral` | 설원 광물 | 재료 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_mining_silver_ore_32x32_png` | `res://assets/sprites/objects/mining/silver_ore_32x32.png` |  |
| `conifer_wood` | 침엽수 목재 | 재료 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `rare_wood` | 희귀 목재 | 재료 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_village_props_firewood_pile_1x2_64x32_png` | `res://assets/sprites/objects/village-props/firewood_pile_1x2_64x32.png` |  |
| `old_wood` | 오래된 목재 | 재료 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_nature_short_log_pile_32x32_png` | `res://assets/sprites/objects/nature/short_log_pile_32x32.png` |  |
| `charcoal` | 숯 | 재료 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_crate_png` | `res://assets/ui/icons/atlas/crate.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `incense_sticks` | 선향 | 향 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png` | `res://assets/sprites/objects/shrine-props/incense_burner_32x32.png` |  |
| `insulated_tea_bottle` | 보온 차병 | 다구 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_gourd_png` | `res://assets/ui/icons/atlas/gourd.png` |  |
| `iron_kettle` | 철 차솥 | 다구 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_crafting_round_iron_kettle_stove_32x32_png` | `res://assets/sprites/objects/crafting/round_iron_kettle_stove_32x32.png` |  |
| `mountain_iron_dagger` | 산철 단도 | 무기 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_sword_png` | `res://assets/ui/icons/atlas/sword.png` |  |
| `mountain_kiln` | 산중 가마 | 도구 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_crafting_kiln_32x32_png` | `res://assets/sprites/objects/crafting/kiln_32x32.png` |  |
| `portable_brazier` | 휴대 화로 | 도구 | semantic_existing_asset | False | False | `asset_assets_ui_icons_atlas_fire_png` | `res://assets/ui/icons/atlas/fire.png` |  |
| `repair_hammer` | 수선 망치 | 도구 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_crafting_workbench_32x32_png` | `res://assets/sprites/objects/crafting/workbench_32x32.png` |  |
| `wood_incense_burner` | 목향 향로 | 다구 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_shrine_props_incense_burner_32x32_png` | `res://assets/sprites/objects/shrine-props/incense_burner_32x32.png` |  |
| `metal_workbench` | 금속 가공대 | 도구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_low_table_png` | `res://assets/ui/icons/atlas/low_table.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `blacksmith_forge` | 대장간 | 도구 | kind_fallback_exception | False | True | `asset_assets_ui_icons_atlas_low_table_png` | `res://assets/ui/icons/atlas/low_table.png` | No item-specific exported image field exists; use the type fallback until art review creates a dedicated row. |
| `wooden_workbench` | 목재 작업대 | 도구 | semantic_existing_asset | False | False | `asset_assets_sprites_objects_crafting_workbench_32x32_png` | `res://assets/sprites/objects/crafting/workbench_32x32.png` |  |

## 몬스터·요괴

| content_id | 이름 | 종류 | resolution | runtime_approved | dedicated_asset_missing | asset_id | path | 예외 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `abandoned_mine_samurai` | 폐광 무사 | 도적·무사 | monster_id_convention | True | False | `monster_abandoned_mine_samurai_front_idle` | `res://assets/sprites/characters/monsters/abandoned_mine_samurai/abandoned_mine_samurai_front_idle_32x32.png` |  |
| `agarwood_thief` | 향목 도둑 | 도적·무사 | monster_id_convention | True | False | `monster_agarwood_thief_front_idle` | `res://assets/sprites/characters/monsters/agarwood_thief/agarwood_thief_front_idle_32x32.png` |  |
| `ash_crow_flock` | 잿빛 까마귀떼 | 야생동물 | monster_id_convention | True | False | `monster_ash_crow_flock_front_idle` | `res://assets/sprites/characters/monsters/ash_crow_flock/ash_crow_flock_front_idle_32x32.png` |  |
| `empty_armor_yokai` | 빈 갑주 요괴 | 요괴 | monster_id_convention | True | False | `monster_empty_armor_yokai_front_idle` | `res://assets/sprites/characters/monsters/empty_armor_yokai/empty_armor_yokai_front_idle_32x32.png` |  |
| `foxfire` | 여우불 | 요괴 | monster_id_convention | True | False | `monster_foxfire_front_idle` | `res://assets/sprites/characters/monsters/foxfire/foxfire_front_idle_32x32.png` |  |
| `frost_lantern_yokai` | 서리등불 요괴 | 요괴 | monster_id_convention | True | False | `monster_frost_lantern_yokai_front_idle` | `res://assets/sprites/characters/monsters/frost_lantern_yokai/frost_lantern_yokai_front_idle_32x32.png` |  |
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
