# 에셋 브라우저

`assets/` 아래 이미지를 로컬 Tkinter 앱에서 확인하고, 선택한 경로나
Codex에 바로 붙여넣을 프롬프트를 복사하는 도구입니다.

프로젝트 루트에서 실행합니다:

```sh
python3 tools/asset_browser/asset_browser.py
```

옵션:

```sh
python3 tools/asset_browser/asset_browser.py --root assets/sprites
python3 tools/asset_browser/asset_browser.py --scale 6
python3 tools/asset_browser/asset_browser.py --list-images
```

기능:

- 선택한 폴더 아래의 일반 이미지 포맷을 재귀적으로 스캔합니다.
- 작은 픽셀아트 이미지를 정수 배율과 nearest-neighbor 방식으로 보여줍니다.
- 단색 중심의 미니멀 격자 UI에서 여러 이미지를 선택할 수 있습니다.
- 선택한 이미지의 상대경로, 절대경로, Codex용 배치 프롬프트를 복사합니다.
- 하단 편집창에서 복사될 Codex 프롬프트를 확인하고 직접 수정할 수 있습니다.
- 기본 프롬프트는 `default_prompt_template.txt`에서 관리하며 앱 안에서 수정/저장할 수 있습니다.
- `assets/style/art-style-tokens.json`의 팔레트, 컨셉, 이미지 생성 토큰을 앱 안에서 요약 확인하고 원본 JSON을 복사할 수 있습니다.
- 전역 팔레트와 바이옴 포인트 색을 실제 색상 스와치로 볼 수 있습니다.
- 팔레트 색상칩을 클릭해 시스템 색상 선택기로 색을 수정하고 JSON에 바로 저장할 수 있습니다.
- `팔레트 테스트 보기`를 켜면 원본 파일을 수정하지 않고 현재 팔레트로 이미지가 어떻게 바뀌는지 썸네일에서 미리볼 수 있습니다.
- `표시 이미지 실제 변환`을 누르면 현재 화면에 표시된 이미지 전체를 팔레트 색으로 실제 변환합니다.
- 실제 변환 전 확인 팝업을 띄우고, 원본은 `tools/asset_browser/palette_backups/` 아래에 자동 백업합니다.
- 스캔 폴더, 기본 프롬프트 템플릿, 아트 스타일 토큰 파일을 Finder에서 바로 볼 수 있습니다.
- 선택한 상대경로 목록을 `.txt` 파일로 저장합니다.

기본 프롬프트 템플릿에서 쓸 수 있는 치환값:

- `{asset_list}`: 선택한 이미지 상대경로 목록
- `{asset_count}`: 선택한 이미지 개수
- `{project_root}`: 프로젝트 루트 절대경로

Pillow는 선택 사항입니다. 설치되어 있으면 JPG, BMP, WEBP, TGA, TIFF 같은
포맷도 미리볼 수 있습니다. Pillow가 없어도 Tkinter 기본 지원 포맷인 PNG,
GIF 등은 미리볼 수 있습니다.
