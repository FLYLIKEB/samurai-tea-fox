# Main의 기능별 구성

`src/main/main.gd`는 장면 노드 참조, 런타임 조립, Godot 입력 callback, 기존 공개 진입점만 제공한다. 실제 기능 흐름과 상태 전환은 아래 기능별 조정자와 협력 객체가 담당한다. 기존 도메인 서비스를 재사용하며 새 autoload나 공통 상속 계층을 두지 않는다.

## 책임과 의존성

| 파일 | 책임 | 의존성 전달 방식 |
| --- | --- | --- |
| `src/main/run_bootstrap_coordinator.gd` | 부팅, 런 서비스 구성, 월드 생성, 저장, 전투·사망 수명주기 | 현재 런타임 값을 읽고 쓰는 명시적 `Ports`와 장면 수명주기 호출 시점의 Main |
| `src/main/main_input_coordinator.gd` | 프레임 입력, 포인터·터치 입력, 메뉴별 명령 순서 | 입력 callback마다 현재 Main 진입점 사용 |
| `src/main/main_command_coordinator.gd` | 명령 종류별 서비스 분배와 결과 효과 실행 | 명시적 `Ports`, `CommandDispatcher`, `ActionCommandResultEffects` |
| `src/main/action_command_result_effects.gd` | 성공한 명령의 상태 동기화, 시간 진행, 피드백, 적 턴 예약 순서 | 좁은 callback 집합 |
| `src/main/world_interaction_coordinator.gd` | 포인터 이동, 월드 대상 판정, 채집·드롭·던전 상호작용 | 호출 시점의 현재 Main과 기존 탐색·획득 서비스 |
| `src/main/dungeon_scene_coordinator.gd` | 던전 진입·복귀, 장면 복원, 적 생성·제거, 보스 대화와 저장 동기화 | 호출 시점의 현재 Main과 던전 도메인 서비스 |
| `src/main/dungeon_command_coordinator.gd` | 던전 입장·완료 명령의 검증 및 부작용 순서 | 던전 기능만 노출하는 callback 집합 |
| `src/main/dungeon_combatant_session.gd` | 던전 적 노드와 던전 진입 전 월드·전투 대상 스냅샷 | Main의 호환 프로퍼티가 단일 상태를 위임 |
| `src/main/facility_biome_coordinator.gd` | 시설 제작·배치와 바이옴 진행·텔레포트 전환 | 명시적 `Ports`와 `FacilityPlacementSession` |
| `src/main/facility_preview_presenter.gd` | 시설 배치 미리보기 노드와 에셋 카탈로그 수명 | 현재 장면·카탈로그·설치 정보 |
| `src/main/player_runtime_coordinator.gd` | 차, 소모품, 수면, 양조, 인벤토리, 지도 발견, 기억의 차 | 명시적 `Ports`와 기존 플레이어 기능 서비스 |
| `src/main/hud_presentation_coordinator.gd` | 월드 렌더, 카메라, HUD, 서사 표시, 효과음 | 현재 런타임 값을 읽고 쓰는 명시적 `Ports` |
| `src/main/game_progression_coordinator.gd` | 센리큐 단계, 엔딩, 최종 방, 보상과 능력 대상 | 호출 시점의 현재 Main과 진행 도메인 서비스 |
| `src/main/run_state_snapshot_coordinator.gd` | RunState 로드·생성·복원·스냅샷과 바이옴별 별칭 | RunState, 저장소, `RunRuntimeStateBinder` |
| `src/main/run_service_factory.gd` | 카탈로그 검증 및 기본 런 서비스 생성 | 현재 카탈로그를 받아 생성 결과 반환 |
| `src/main/cheat_start_configurator.gd` | 치트 인벤토리와 바이옴 진행 초기화 | 현재 카탈로그·인벤토리·장비·RunState, 동기화 callback |
| `src/main/acquisition_definition_builder.gd` | 채집·나무·광물·드롭 정의와 채집 대상 등록 | 현재 카탈로그·인벤토리·WorldData·바이옴 |
| `src/main/dungeon_layout_builder.gd` | 던전 지형·자원 배치·적 점유 셀 생성 | 던전 정의, 자원 상호작용 종류 조회 callback |
| `src/main/dungeon_definition_resolver.gd` | 바이옴 던전·보스·대화 정의 해석 | 현재 카탈로그·RunState·NarrativeRuntime |
| `src/main/pointer_route_controller.gd` | 포인터 경로 및 도착 대기 상태 | 현재 월드와 좌표 변환·도착 callback |
| `src/main/spatial_interaction_resolver.gd` | 대상 후보·방향 우선순위·거리·시설 점유 영역 탐색 | 현재 월드·대상 서비스·플레이어 방향/좌표 |
| `src/main/facility_placement_session.gd` | 시설 배치 대기 상태, 선택·회전·검증·제작 거래, 시설 복원 | 현재 제작/배치 서비스·인벤토리·월드·RunState |
| `src/presentation/facility_placement_preview.gd` | 설치 예정 시설의 유령 이미지와 영역 표시 | 위치·크기·유효성·텍스처 |
| `src/main/narrative_session.gd` | 활성 대화 ID, 선택지 결과, 기억의 차 상태 반영 | 현재 내러티브 서비스·RunState·메타 상태 |
| `src/main/player_item_actions.gd` | 차 마시기 진행, 소모품 시작·중단·완료 순서 | 매 호출의 서비스·자원 및 저장/화면/턴 callback |
| `src/main/world_presentation.gd` | 스프라이트 출처, 카메라 경계, 상호작용 표시 | 월드 스냅샷·표시 노드·좌표 |
| `src/main/main_scene_overlays.gd` | 로딩 및 종료 화면 노드 구성 | 장면 부모 노드 |

## 상태 소유와 호출 계약

- 포인터, 시설 배치, 활성 대화, 차 마시기 상태는 각각 해당 기능 객체가 단독 소유한다.
- 기존 테스트·호출자가 사용하는 Main 진입점은 유지한다. 대기 상태를 노출하는 기존 프로퍼티는 기능 객체의 상태에 직접 연결하며 별도 복사본을 저장하지 않는다.
- 월드·런 교체가 가능한 서비스는 매 호출 현재 값을 전달한다. 장기간 유지하는 기능 객체에 이전 `world_data`, 인벤토리, RunState를 저장하지 않는다.
- 명령·시설·HUD·플레이어·부팅 조정자는 `Ports`에 필요한 읽기·쓰기와 명령만 선언한다. 장면 노드 수명과 물리 callback에 직접 묶인 조정자는 Main을 호출 시점에만 받고 보관하지 않는다.
- `PlayerItemActions`의 callback은 저장 동기화·저장·HUD 갱신·턴 진행·적 턴 예약이라는 완료 효과에만 한정한다. Main 전체 또는 임의 필드 조회 인터페이스를 전달하지 않는다.
- 인벤토리·차·소모품 동기화는 같은 `RunRuntimeStateBinder`와 같은 엔트리를 사용하므로 Main의 `_sync_run_runtime_state()`로 합친다.

## 기능 조정자가 보존하는 순서

- 프레임 입력의 이동 → 행동 순서와 같은 프레임의 메뉴/슬롯 조회 시점.
- 던전 진입/복귀의 바깥 월드 보관, 서비스 교체, 렌더링, 플레이어 배치, 전투 노드 수명, 저장 순서.
- 시설 설치의 재검증·재료 소비 성공 후 기록 → 렌더링 → 대기 상태 정리 → 저장/화면/턴 처리 순서.
- 대화 선택지 완료 후 보스 전 대화 완료 처리가 성공한 경우에만 활성 대화 상태 해제.
- 사망 종료 화면의 타이머와 장면 전환 수명.

기능 분리 자체를 목적으로 부작용의 실행 순서를 바꾸지 않는다. 장면 전체가 필요한 흐름도 coordinator가 Main을 장기간 보관하지 않고 호출 동안에만 사용한다. 다음 단계에서는 이 호출면을 기능별 포트로 더 좁힐 수 있지만, 이번 분리는 기존 공개 API와 테스트 seam을 유지한다.

## 동작 보존과 정본

기획·밸런스·대사·stable ID·정적 데이터·저장 형식을 바꾸지 않는다. 런타임 Notion 호출도 추가하지 않는다. 기존 optional 콘텐츠 누락 처리, legacy 시설/채집 상태 복원, 스프라이트 대체와 생성 실패 결과는 유지한다. 이러한 기존 호환 경로의 정책 개선은 이번 파일 분리와 별도 범위다.

## 회귀 검증

- `tests/test_runner.gd`: 기존 도메인/Main 테스트와 명령 효과, RunState 스냅샷, 던전 전투 세션, 던전 명령, 시설·바이옴 조정자 단위 테스트.
- `tests/integration/test_main_frame_input_boundary_runner.gd`: 프레임 입력과 메뉴 처리 순서.
- `tests/integration/test_main_runtime_rendering_runner.gd`: 실제 Main 시작, 월드 표시 및 저장 상태 복원.
- `tests/integration/test_dev116_main_death_transition_runner.gd`: 사망 저장 전환 및 시작 화면 복귀.
- `tests/integration/test_dev77_portrait_dialogue_runner.gd`: 대화 HUD 연결.

신규 회귀는 다른 월드로 교체한 뒤의 대상 조회, 인스턴스별 상태 격리, 실패한 시설 확정의 재료 보존, 포인터 경로 순서, 바라보는 방향 우선순위, 대화 ID 전달 및 보스 완료 실패 후 ID 보존을 고정한다.
