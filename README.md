# 한걸음

미루는 사람을 위한 실행형 To Do / Reminder. iOS·Android 동시 개발·동시 스토어 제출을 목표로 한다. 가입·운영 서버·클라우드 DB·광고·구독 없이 기기 안에서 동작한다.

## 실제 모바일 앱

`mobile/`에 Flutter iOS·Android 프로젝트가 있다. 웹을 앱 안에 띄우는 방식이 아니라 Flutter 화면과 기기 SQLite·OS 알림을 사용한다. 앱 데이터는 기기에 저장되며 앱 삭제·기기 변경 시 유실될 수 있다.

- 월간·주간 캘린더, 날짜별 목록, 오늘·이번 주·이번 달 요약
- 제목·메모·날짜·시간·우선순위·작은 첫걸음 등록 및 CRUD
- 시작·진행 중·보류·완료·완료 해제·이번 회차 건너뛰기
- N일·N주 여러 요일·N개월 같은 날짜·매월 특정 번째 요일, 종료일
- 요일을 고정하지 않는 주 N회 목표와 주간 달성 횟수
- 반복 일정 이번만/이번부터 앞으로 수정, 과거 완료 기록 보존
- 이번 회차·이번부터 앞으로·전체 시리즈 삭제
- 10분·30분·1시간·오늘 나중에 미루기, 하루 세 번째 미루기 후 5분 시작
- iOS·Android 로컬 알림 예약 및 시작·10분 미루기·완료 액션
- 보류 후 같은 날 두 번 추가 재알림, 진행 상태 확인 알림
- Android 홈 화면 위젯·iOS WidgetKit 위젯, 할 일 열기·시작·10분 미루기
- OS 반복 알림과 백그라운드 예약 보충·위젯 갱신
- 최근 30일 등록 수·완료 수·완료율·미루기 수·평균 지연·완료 시간대
- 오프라인 Pretendard 글꼴, 다크 레드 높은 우선순위

위젯은 실제 OS 홈 화면에 추가하는 네이티브 위젯이다. 위젯·알림 액션은 앱을 열어 로컬 DB에 반영한다. Pro·동기화·광고·구독은 포함하지 않으며 스토어에 게시된 상태는 아니다.

로컬 `flutter analyze`와 `flutter test` 42개는 통과했으며, 최신 소스 커밋·CI·네이티브 실행 검증·서명 빌드·실기기 결과는 [검증 보고서](VERIFICATION.md)에 구분해 기록한다. 기능 구현 완료를 스토어 배포 검증 완료로 간주하지 않는다.

## 프로젝트 구조

| 경로 | 역할 |
| --- | --- |
| mobile/lib/main.dart | 앱 초기화, 한국어·테마, 알림 액션 연결 |
| mobile/lib/domain | Task·Occurrence·반복 계산 |
| mobile/lib/data/task_repository.dart | SQLite schema v3·migration·회차·주간 목표·삭제 범위·통계·예약 동시 실행 제어 |
| mobile/lib/app/task_controller.dart | 화면 상태·우선순위 큐·알림/위젯 동기화·액션 연결 |
| mobile/lib/features | 캘린더·목록·상세·등록·반복 수정·통계·설정 |
| mobile/lib/services/reminder_scheduler.dart | 기기 시간대·권한·OS 예약·취소·알림 액션 |
| mobile/lib/services/notification_plan.dart | OS 반복 알림·개별 예약·예약 상한과 보충 범위 계산 |
| mobile/lib/services/background_refresh.dart | 6시간 주기 요청으로 예약 보충·위젯 갱신 |
| mobile/lib/services/widget_service.dart | DB에서 네이티브 위젯 스냅샷 생성·위젯 링크 처리 |
| mobile/android | Android 앱·AppWidget·권한·서명 구성 |
| mobile/ios | iOS 앱·WidgetKit 확장·App Group·권한·서명 구성 |
| mobile/test, mobile/integration_test, mobile/tool | 단위/위젯·플랫폼 통합·권한 거부·네이티브 생명주기 검증 |
| .github/workflows/mobile.yml | Android 빌드/에뮬레이터·iOS 빌드/시뮬레이터·네이티브 위젯 검증 |
| VERIFICATION.md | 커밋별 검증 결과와 남은 실기기·서명 검증 |

DB는 tasks(원본·반복 규칙·시리즈·주간 목표), occurrences(실제 회차·상태·원래 시간·재알림 시간), events(미루기·시작·완료), recurrence_exceptions(회차 예외), settings(백그라운드 갱신 기록·예약 동시 실행 제어)로 구성한다. schema v3으로 기존 DB를 마이그레이션한다. 완료 해제는 이전 상태와 완료 통계를 복원한다. iOS 위젯에는 `group.com.dabok407.hangeoreum` App Group의 읽기용 스냅샷을 제공한다.

알림 흐름: DB에 저장 → 알림/위젯 갱신 → OS 알림 → 사용자 액션으로 DB 갱신 → 완료 알림 취소 또는 다음 확인 예약. Android는 정확한 알람 권한을 확인하고 거부 시 지연 가능한 예약을 사용하며 재부팅 예약 복구 receiver를 포함한다. iOS는 로컬 예약·알림 category action을 사용한다. 앱 진입·액션과 OS가 허용한 백그라운드 실행에서 예약을 보충한다.

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

스토어 서명·업로드·실기기 검증은 [출시 문서](mobile/RELEASE.md)를 참고한다. Android 업로드 키와 `key.properties`는 로컬에 생성했으며 Git에서 제외한다. 서명된 AAB 빌드 결과는 [검증 보고서](VERIFICATION.md)에서 확인한다. debug APK 및 서명 전 iOS 빌드는 스토어용 배포 빌드가 아니다. iOS 배포 서명은 Apple 계정 연결 후 진행한다.

## 알림 범위

가까운 예약을 iOS 최대 60개·Android 최대 400개까지 등록한다. 종료일이 없고 간격이 1인 일/주 반복과 매월 28일 이내 날짜 반복은 미래 회차 상태·예외·시작일 조건이 맞을 때 OS 반복 알림으로 압축한다. 나머지는 개별 예약을 사용한다.

앱 진입·액션 외에도 Workmanager로 최초 6시간 지연과 6시간 주기 백그라운드 보충을 요청한다. 실제 실행 시각과 빈도는 OS가 결정하며, 강제 종료·집중 모드·절전·권한 설정에 따라 보충이나 알림이 지연될 수 있다. 장기간 실행되지 않거나 개별 예약 범위를 넘어가면 알림을 보장하지 않는다. 앱 설정에서 알림·정확한 알람 권한과 테스트 알림을 확인할 수 있다. 예약 보충과 양쪽 실기기 검증 결과는 [검증 보고서](VERIFICATION.md)를 참고한다.

## 웹 프로토타입

기존 화면 비교·UX 검증용 웹 소스는 루트에 유지한다. 실제 기기 알림은 아니다.

```sh
npm run build
npm start
```

http://127.0.0.1:5173. 상세한 웹 구현은 [프로토타입 문서](PROTOTYPE.md) 참고.

## 다음 출시 작업

최신 CI 및 Android 서명 AAB 결과 확인 → 실제 Android 검증 → 개발자 계정 연결·iOS 앱/위젯/App Group 서명 → TestFlight·Play 내부 테스트 및 양쪽 실기기 검증 → 스토어 메타데이터·개인정보 안내 확정 → 동시 심사 제출 → 양쪽 승인 후 공개일 조정.
