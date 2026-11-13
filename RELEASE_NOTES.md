# v2.0.22

### 한국어
- 데이터 공유 현황 창을 추가했습니다. `/공유` 또는 `/ezshare`로 열면 받은 기록, 보낸 사람, 보낸 기록, 종류별 현황과 새로 받은 기록만 따로 볼 수 있습니다.
- 공유 데이터를 채널로도 보내 더 빨리 퍼지게 했습니다.
- 데이터 채널의 사용자 명단이 새로 갱신되지 않아 일부 사용자와 귓속말로 공유 기록을 주고받지 못하던 문제를 고쳤습니다.
- 퀘스트 보상, 트레이너가 가르치는 주문, 오브젝트 이름도 다른 사용자와 공유합니다.
- 전투 중에는 세계 지도를 열거나 옮기지 않고, 전투가 끝나면 옮깁니다. "애드온 동작 차단" 오류의 원인이었습니다.
- 전투 중 채팅 안내는 모아 두었다가 전투가 끝나면 보여 줍니다. EzWoW-Quest 없이 쓸 때 퀘스트 안내가 "EzWoW - Quest"로 나오던 것도 고쳤습니다.
- 다른 지점을 고르거나 핀을 지운 뒤 지도를 닫으면 예전 추적 지점이 되살아나던 문제를 고쳤습니다.
- 전투 중 희귀 몬스터 알림을 닫으면 보이지 않는 대상 지정 버튼이 남던 문제를 고쳤습니다. 알림은 전투가 끝날 때 닫힙니다.
- 게임패드: 전투가 끝나면 EzWoW 창이 패드 조작을 가져가던 문제를 고쳤습니다. 전투 전에 EzWoW 창을 조작하던 경우에만 되돌립니다.
- 추적 화살표의 목적지 이름이 다시 불러오기나 재접속 뒤에도 남습니다.
- 공유 기록을 설치된 EzWoW 애드온 중 최대 2개에만 저장해 접속·다시 불러오기가 빨라지고 저장 파일이 작아집니다. 업데이트 후 게임을 한 번 완전히 다시 시작하면 적용됩니다.

### English
- Added a data sharing window. Open it with `/ezshare` to see received records, players, sent records, totals by kind, and only the newly received records.
- Shared data is now also sent through the channel, so it spreads faster.
- Fixed shared records not being exchanged by whisper with some players because the data channel's player list was not refreshed.
- Quest rewards, trainer spells and object names are now shared with other players too.
- The World Map is no longer opened or moved in combat; it moves when combat ends. This caused "action blocked" errors.
- Chat messages are held during combat and shown afterwards. Quest guide lines without EzWoW-Quest no longer say "EzWoW - Quest".
- Fixed an old waypoint coming back after picking another spot or clearing pins and then closing the map.
- Closing the rare alert in combat no longer leaves invisible target buttons; the alert closes when combat ends.
- Gamepad: EzWoW windows no longer take over the pad after combat; it returns only if you were using an EzWoW window before the fight.
- The waypoint arrow keeps its destination name after a reload or relog.
- Shared records are now saved by at most 2 of your installed EzWoW addons, so logins and reloads are faster and save files smaller. Takes effect after one full game restart following the update.
