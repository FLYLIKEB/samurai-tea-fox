# 에셋 브라우저 설정

에셋 브라우저 앱 본체는 별도 레포에서 관리합니다.

- 로컬 기본 위치: `/Users/jwp/Developer/samurai-tea-fox-asset-browser`
- GitHub: `https://github.com/FLYLIKEB/samurai-tea-fox-asset-browser`
- 프로젝트별 기본 프롬프트: `tools/asset_browser/default_prompt_template.txt`

실행:

```sh
tools/asset_browser/run.sh
```

옵션 예시:

```sh
tools/asset_browser/run.sh --root assets/sprites
tools/asset_browser/run.sh --scale 6
tools/asset_browser/run.sh --list-images
```

다른 위치에 클론한 앱을 쓰려면 `ASSET_BROWSER_REPO`를 지정합니다.

```sh
ASSET_BROWSER_REPO=/path/to/samurai-tea-fox-asset-browser tools/asset_browser/run.sh
```
