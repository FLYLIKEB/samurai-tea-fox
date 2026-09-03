# 바이옴 맵 캡처

현재 월드 생성기와 씬 렌더러의 결과를 PNG로 저장하는 전용 도구다. 게임 로직을 복제하지 않고 `WorldGenerator` → `WorldRendererProjection` → `WorldSceneRenderer` 흐름을 그대로 사용한다.

## 전체 바이옴 캡처

프로젝트 루트에서 실행한다.

```sh
bash tools/capture_biome_maps.sh
```

기본 출력 폴더는 `artifacts/biome-previews/`다. 바이옴별 PNG와 `biome_map_examples_contact_sheet.png` 합본이 생성된다.

## 옵션

```sh
# 지원 바이옴과 기본 시드 확인
bash tools/capture_biome_maps.sh --list

# 특정 바이옴을 다른 시드로 캡처
bash tools/capture_biome_maps.sh --biome=mountain_region --seed=22034

# 출력 폴더 변경
bash tools/capture_biome_maps.sh --output-dir=/tmp/muchau-map-previews

# 합본 없이 개별 PNG만 생성
bash tools/capture_biome_maps.sh --no-contact-sheet

# 픽셀 배율 변경
bash tools/capture_biome_maps.sh --scale=0.75
```

지원 바이옴 ID는 `common_region`, `wasteland`, `snowfield`, `mountain_region`, `rainforest`다. 캡처 시 해당 시드의 지형, 강·길, 시설, 자원, 필수 랜드마크를 함께 렌더링한다.

macOS 기본 렌더링 드라이버를 사용한다. 다른 환경에서는 필요에 따라 `GODOT_BIN`, `GODOT_DISPLAY_DRIVER`, `GODOT_RENDERING_METHOD` 환경 변수로 실행 설정을 바꿀 수 있다.
