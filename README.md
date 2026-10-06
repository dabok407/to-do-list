# 한걸음

미루는 사람을 위한 실행형 To Do / Reminder. iOS·Android 동시 개발·동시 스토어 제출을 목표로 한다. 가입·운영 서버·클라우드 DB·광고·구독 없이 기기 안에서 동작한다.

## 실제 모바일 앱

`mobile/`에 Flutter iOS·Android 프로젝트가 있다. 웹을 앱 안에 띄우는 방식이 아니라 Flutter 화면과 기기 SQLite·OS 알림을 사용한다. 앱 데이터는 기기에 저장되며 앱 삭제·기기 변경 시 유실될 수 있다.

- 월간·주간 캘린더, 날짜별 목록, 오늘·이번 주·이번 달 요약
- 제목·메모·날짜·시간·우선순위·작은 첫걸음 등록 및 CRUD
- 시작·진행 중·보류·완료·완료 해제·이번 회차 건너뛰기
- N일·N주 여러 요일·N개월 같은 날짜·매월 특정 번째 요일, 종료일
- 반복 일정 이번만/이번부터 앞으로 수정, 과거 완료 기록 보존
- 10분·30분·1시간·오늘 나중에 미루기, 하루 세 번째 미루기 후 5분 시작
- iOS·Android 로컬 알림 예약 및 시작·10분 미루기·완료 액션
- 보류 후 같은 날 두 번 추가 재알림, 진행 상태 확인 알림
- 최근 30일 등록 수·완료 수·완료율·미루기 수·평균 지연·완료 시간대
- 오프라인 Pretendard 글꼴, 다크 레드 높은 우선순위

실제 OS 위젯·Pro·동기화·광고는 포함하지 않는다. 스토어에 게시된 상태는 아니다. 알림 액션은 OS에서 앱을 열어 처리하며 백그라운드에서 무한히 실행하지 않는다.

## 프로젝트 구조

| 경로 | 역할 |
| --- | --- |
| mobile/lib/main.dart | 앱 초기화, 한국어·테마, 알림 액션 연결 |
| mobile/lib/domain | Task·Occurrence·반복 계산 |
| mobile/lib/data/task_repository.dart | SQLite schema v2·migration·CRUD·회차·이벤트·통계 |
| mobile/lib/app/task_controller.dart | 화면 상태·우선순위 큐·저장 후 알림 동기화 |
| mobile/lib/features | 캘린더·목록·상세·등록·반복 수정·통계·설정 |
| mobile/lib/services/reminder_scheduler.dart | 기기 시간대·권한·OS 예약·취소·알림 액션 |
| mobile/android, mobile/ios | 실제 플랫폼 프로젝트·권한·서명 구성 |
| mobile/test, mobile/integration_test | 반복·DB·입력 검증·실제 기기 통합 테스트 |
| .github/workflows/mobile.yml | Android·iOS 빌드 및 Android 에뮬레이터 검증 |

DB는 tasks(원본·반복 규칙·시리즈), occurrences(실제 회차·상태·원래 시간·재알림 시간), events(미루기·시작·완료), recurrence_exceptions(이번 회차 수정 예외)로 구성한다. 완료 해제는 이전 상태와 완료 통계를 복원한다.

알림 흐름: DB에 저장 → 변경된 상태로 예약 재계산 → OS 알림 → 사용자 액션으로 DB 갱신 → 완료 알림 취소 또는 다음 확인 예약. Android는 정확한 알람 권한을 확인하고 거부 시 지연 가능한 예약을 사용한다. 재부팅 예약 복구 receiver를 포함한다. iOS는 로컬 예약·알림 category action을 사용한다.

## 모바일 빌드·실행

Flutter 3.47.6 기준. Android SDK·JDK 17을 사용한다. iOS 빌드는 macOS·Xcode가 필요하며 GitHub의 macOS runner를 사용할 수 있어 Mac 소유는 필수가 아니다.

```sh
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

에뮬레이터 또는 연결된 기기를 `flutter devices`로 확인하고 `flutter run -d DEVICE_ID`로 실행한다. Windows 에뮬레이터는 지원되는 가상화 드라이버가 필요하다. 로컬 SDK 설치 폴더 `.tools`는 소스 관리에서 제외한다.

스토어 서명·업로드·실기기 검증은 [출시 문서](mobile/RELEASE.md)를 참고한다. debug APK 및 서명 전 iOS 빌드는 스토어용 배포 빌드가 아니다. 빌드 결과는 저장소 Actions에서 각 커밋별로 확인한다.

## 알림 범위

가까운 최대 60개 예약을 OS에 등록하고 앱 진입·액션 때 다시 채운다. 장기간 앱을 전혀 열지 않으면 예약 범위 밖 알림이 전달되지 않을 수 있다. 앱 설정에서 알림·정확한 알람 권한과 테스트 알림을 확인한다. 집중 모드·절전 정책·기기 재부팅은 양쪽 실기기에서 검증해야 한다.

## 웹 프로토타입

기존 화면 비교·UX 검증용 웹 소스는 루트에 유지한다. 실제 기기 알림은 아니다.

```sh
npm run build
npm start
```

http://127.0.0.1:5173. 상세한 웹 구현은 [프로토타입 문서](PROTOTYPE.md) 참고.

## 다음 출시 작업

최신 빌드·에뮬레이터 테스트 통과 → 실제 iPhone 및 Android에서 앱 종료·알림 액션·권한 거부·재부팅 검증 → 개발자 계정·서명 연결 → TestFlight·Play 내부 테스트 → 스토어 메타데이터·개인정보 안내 확정 → 동시 심사 제출 → 양쪽 승인 후 공개일 조정.
