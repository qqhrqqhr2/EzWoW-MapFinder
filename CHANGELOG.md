# Changelog - EzWoW - Map Finder

## v2.0.0

### English

- Fixed icon and window dragging offsets at different UI scales.
- Added World Map markers for boats, zeppelins, trams and portals; click a marker to view the destination.
- Expanded mouse-wheel map zoom up to 3.2x.
- Added required gathering skill levels and improved searches using joined zone abbreviations.
- Improved search responsiveness and integration with Best Gear Finder, Profession Recipes and Dungeon Route Guide.

### 한국어

- UI 배율에 따라 아이콘·창을 끌 때 위치가 어긋나는 문제를 수정했습니다.
- 배·비행선·지하철·차원문 지도 표식과 클릭 시 목적지 이동을 추가했습니다.
- 마우스 휠 지도 확대를 최대 3.2배로 확장했습니다.
- 채집 필요 숙련도 표시와 지역 약칭을 붙여 쓴 검색어 처리를 개선했습니다.
- 검색 성능과 장비·제조법·던전 길잡이 연동을 개선했습니다.

## v0.3.0
- 드래그 시 마우스 포인터와 아이콘/프레임 좌표가 어긋나거나 벌어지는 스케일 오차(`EffectiveScale`) 및 초기 점프 현상 수정
- **모듈 구조 재설계 (`Core/`, `Data/`, `Database/`, `Modules/`, `UI/`) 및 검색 엔진 최적화**:
  - `Core/Init.lua`, `Core/Locales.lua`, `Core/UIKit.lua`, `Core/WorldMapDock.lua`
  - `Data/ZoneAndGatherData.lua`(지역 경계·약칭·약초/채광 숙련도·대륙 이동 수단 데이터)
  - `Modules/SearchEngine.lua`(비동기 코루틴/틱 분할 검색 엔진), `Modules/MapEnhancements.lua`(월드맵 편의 기능)
  - `UI/SearchPanel.lua`, `UI/OptionsWindow.lua`
- **신규 월드맵 편의 기능 및 연동 추가**:
  - 배·비행선·깊은굴 지하철·차원문(`showTransit`) 월드맵 핀 표시 및 클릭 시 목적지 지도 즉시 이동 추가 (제프라스 섬·강물숲·달라란 포함)
  - 월드맵 마우스 휠 확대 단계 최대 3.2배 확장(`enableMapZoom`) 추가
  - 약초 채집·채광 오브젝트 필요 숙련도 표시 및 지역 약칭 붙여쓰기(`오그경매`, `아포은행` 등) 자동 분리 검색 추가
  - `EzWoW-BestGearFinder`, `EzWoW-ProfessionRecipes`, `EzWoW-DungeonRouteGuide` 외부 검색 호출 연동
  - 슬래시 명령어 `/ezmf`, `/맵파인더` 및 `EzWoW_MapFinderDB` 정비
