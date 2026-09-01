---
name: godot-scene-resource-authoring
description: Godot 4.x의 장면 파일, 리소스 파일, 장면 트리, 자동 로드 관련 파일을 만들거나 수정할 때 텍스트 형식과 책임 경계를 지키기 위해 사용한다.
metadata:
  short-description: Godot 장면·리소스 작성 규칙
---

# Godot Scene과 Resource 작성

Godot scene, resource, autoload, import 설정을 만들거나 수정할 때 사용한다. 이 프로젝트는 scene과 UI가 presentation을 맡고, 순수 게임 규칙은 가능한 한 GDScript 도메인 모듈에 둔다.

## 기본 경계

- `.tscn`은 노드 구성과 연결을 표현한다. 게임 규칙의 정본으로 만들지 않는다.
- `.tres`와 Resource는 재사용 가능한 설정이나 정의 데이터 표현에 사용하되, Notion export 데이터와 중복되는 콘텐츠 값은 넣지 않는다.
- 도메인 규칙은 `src/` 아래 모듈 script에 두고 테스트 가능하게 유지한다.
- scene은 input adapter, renderer, presenter 역할을 맡고 domain state를 직접 소유하지 않는다.
- autoload는 명확한 전역 생명주기 책임이 있을 때만 추가한다.

## 수정 규칙

- 기존 `.tscn` 또는 `.tres`를 수정하기 전에 인스턴스 ID, ext_resource, sub_resource 참조를 확인한다.
- Godot가 생성한 section 순서와 resource 참조 형식을 불필요하게 재정렬하지 않는다.
- 씬 파일을 손으로 크게 재작성하지 말고, 필요한 최소 section만 바꾼다.
- node path 문자열을 바꿀 때는 관련 script의 `$NodePath`, `get_node`, signal 연결을 같이 확인한다.
- 새 scene을 만들면 해당 script와 테스트 가능 도메인 로직의 책임을 분리한다.

## 완료 전 확인

- scene/resource 참조가 깨지지 않았는지 확인한다.
- 가능하면 Godot headless import 또는 전체 테스트를 실행한다.
- Godot 실행 파일이 없으면 변경 파일의 참조 구조를 텍스트로 점검하고 검증 gap을 보고한다.
