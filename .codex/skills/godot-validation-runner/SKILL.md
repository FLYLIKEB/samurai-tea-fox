---
name: godot-validation-runner
description: 이 Godot 4.x 프로젝트에서 변경 후 관련 테스트, headless Godot 검증, 빌드·import smoke check 결과를 확인하고 보고할 때 사용한다.
metadata:
  short-description: Godot 테스트와 검증 실행
---

# Godot 검증 실행

이 프로젝트에서 변경사항을 완료 처리하기 전에 검증할 때 사용한다. 목표는 변경 범위에 맞는 가장 작은 테스트부터 실행하고, 필요하면 전체 Godot headless 테스트와 빌드/import 확인까지 확장하는 것이다.

## 표준 명령

Godot가 설치된 환경에서는 다음 명령을 우선 사용한다.

```sh
godot --headless --path . --script res://tests/test_runner.gd
```

## 테스트 선택

- 데이터 로딩 변경: `test_data_catalog.gd`
- 월드 생성 변경: `test_world_generation.gd`
- 입력/명령 계층 변경: `test_command_layer.gd`
- 플레이어 자원 변경: `test_player_resources.gd`
- 저장 변경: `test_save_codec.gd`
- 공통 경계나 여러 모듈을 건드렸다면 전체 `tests/test_runner.gd`

## 보고 규칙

- 실행한 명령과 결과를 완료 보고에 적는다.
- Godot 실행 파일이 없으면 설치 여부를 추측하지 말고, 실행 불가 사유와 대체 검증을 분리해서 보고한다.
- 실패한 테스트가 있으면 로그의 핵심 원인과 수정 여부를 함께 보고한다.
- 빌드나 import 확인이 필요한 변경인데 실행하지 못했다면 완료가 아니라 검증 gap으로 명시한다.

## 완료 기준

- 변경 범위와 직접 관련된 테스트가 통과한다.
- 프로젝트 전체 계약을 건드린 경우 전체 headless 테스트가 통과한다.
- 실패를 무시하고 완료라고 주장하지 않는다.
