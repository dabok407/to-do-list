# 제품 및 화면 설계

## v0.2 반영 (2026-10-06)

메인 화면은 전체 월간 캘린더 + 선택 날짜의 시간순 목록으로 변경했습니다. 큰 홍보 문구와 색 카드 대신 여백, 얇은 경계선, 선형 아이콘, 작은 테라코타 포인트를 사용합니다. 모바일에서는 날짜별 표시점, 데스크톱에서는 짧은 일정 제목을 사용합니다. 요약은 오늘/이번 주/이번 달 전환과 남음·완료 수만 제공해 캘린더를 가리지 않습니다. 주간 보기는 한 주에 집중하는 대안입니다.

N일 / N주+여러 요일 / N개월+날짜 / N개월+특정 번째 요일과 종료 날짜를 구현했습니다. 월말 없는 날짜는 말일 보정 후 원래 일자를 유지합니다. 종료 날짜는 그날까지 포함합니다. 주간 간격은 월요일 시작 주를 기준으로 합니다. ‘주 2회’는 두 요일 선택이며 임의의 날에 두 번 수행하는 목표는 아직 없습니다.

위젯 미리보기: 홈 작은 위젯 한 항목, 목록 세 항목, 잠금 화면 한 줄. 실제 데이터로 후보를 계산하되 OS 위젯 설치 기능은 아닙니다. 진행 중을 우선, 지난 알림을 중요도순, 미래는 시간순·동시각 중요도순으로 정렬합니다. 실제 iOS에서는 WidgetKit 타임라인과 공유 로컬 저장소, 사용자 액션 후 갱신이 필요합니다. 위젯은 초단위 타이머가 아니라 다음 행동을 보여주는 용도로 설계합니다. [Apple 위젯 가이드](https://developer.apple.com/design/human-interface-guidelines/widgets)는 지속 실시간 갱신이 아니라 시스템이 조정하는 주기적 갱신을 설명합니다.

아래 실제 앱 DB·네이티브 알림·배포 설계는 여전히 후속 구현 계획입니다. v0.2 웹 구현 현황은 README.md를 기준으로 합니다.

## 포지셔닝

미루는 사람을 위한 실행형 To Do. 의료·진단 표현 없이 ‘작은 시작’을 돕습니다. 시작과 완료는 서로 다른 상태이며 알림을 닫았다고 완료로 바꾸지 않습니다. 목표 축소는 미리 적은 작은 첫걸음으로 제안하고 원래 목표를 덮어쓰지 않습니다.

## 화면 흐름

오늘: 이번 주 날짜 / 지금 할 일 / 시간별 약속 / 진행 상태.
예정: 미래 일정, 다음 반복 일정.
완료: 완료 기록.
등록·수정: 제목 / 메모 / 날짜·시간 / 우선순위 / 반복 요일 / 작은 첫걸음.
상태 확인: 지금 시작 / 완료 / 시간별 보류 / 오늘 못함.
세 번 미루기: 작은 목표 제안 → 5분 시작 → 진행 상태 확인 → 완료 또는 보류.
나의 흐름: 최근 30일 숫자와 완료 시간대.
설정: 진행 상태 확인 간격, 로컬 데이터 안내, 테스트 초기화.

안방 대청소를 토요일 10시에 등록 → 시간 도착 → 시작 또는 보류 → 보류 시 다음 알림 시간 명시 → 반복 보류 시 물건 5개 치우기 → 5분 후 상태 확인. ‘오늘 못함’은 이번 회차 건너뛰기이며 반복 자체를 해제하지 않습니다.

현재 미리보기에는 조용한 세이지 그린, 흰색 카드, 황색 보류 상태를 사용합니다. 알림은 비난하지 않는 짧은 문장으로 구성하고 완료 버튼은 명시적으로 분리합니다.

## 벤치마킹

- [Apple Reminders](https://support.apple.com/en-us/102484): 제목·메모·날짜·시간 중심의 간단한 입력 및 완료 동작 참고.
- [Todoist reminders](https://www.todoist.com/help/todoist/features/introduction-to-reminders-9PezfU): 일정과 재알림의 구분을 참고.
- 차별점으로 진행 중, 보류, 작은 목표 시작을 분리. 경쟁 서비스 효과나 임상 효과를 검증했다고 주장하지 않습니다.

## 실제 앱 기술 결정 제안

출시 목표는 iOS와 Android 동시 개발 및 App Store·Google Play 동시 제출입니다. Flutter + 로컬 SQLite를 공통 구현 방향으로 삼고 화면과 상태 로직은 공유하며 알림·위젯 어댑터는 플랫폼별로 둡니다. 이번 웹 시안은 기능/UX 명세로 사용하며 Flutter 코드가 아닙니다.

[Flutter 공식 플랫폼 문서](https://docs.flutter.dev/platform-integration)는 iOS와 Android 공유 개발을 지원하며 iOS 빌드 환경은 macOS가 필요하다고 명시합니다. [Apple Simulator](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)는 Xcode에서 실행합니다. 현재 Windows에서 공식 iOS Simulator를 실행하거나 IPA를 빌드한 상태가 아닙니다.

예상 패키지:

```
lib/
  app/                  라우팅, 테마, 의존성 조립
  domain/               Task, Occurrence, Event, RecurrenceCalculator
  data/local/           SQLite schema 및 migration
  data/repositories/    TaskRepository, StatsRepository
  services/             ReminderScheduler 인터페이스
  features/tasks/       등록, 목록, 상세 및 상태 ViewModel
  features/focus/       작은 목표와 진행 상태
  features/stats/       이벤트 기반 통계
  features/settings/    권한, 로컬 정책, 알림 설정
ios/                    UNUserNotificationCenter 어댑터
android/                AlarmManager 및 알림 액션 어댑터
```

Repository는 데이터 저장, ViewModel은 UI 상태와 사용자 액션, RecurrenceCalculator는 원래 일정/시간대 기준 다음 발생 계산, ReminderScheduler는 OS 알림 예약·취소를 담당합니다. 유료 기능은 Entitlement 인터페이스로 추후 추가하되 현재 동작을 막지 않습니다.

## 실제 DB 계획 (아직 구현 전)

| 테이블 | 주요 필드 |
| --- | --- |
| tasks | id, title, note, priority, small_step, created_at, archived_at |
| recurrence_rules | task_id, frequency, weekdays, local_time, timezone, anchor_date |
| occurrences | id, task_id, original_due_at, reminder_at, state, started_at, completed_at, skipped_at |
| task_events | id, occurrence_id, type, occurred_at, delay_minutes, local_date |
| reminder_jobs | id, occurrence_id, platform_id, scheduled_at, kind |
| settings | key, value |

최초 등록 수는 tasks 기준, 완료율은 해당 기간의 발생 회차 기준으로 분리합니다. 미루기 수와 평균 미룬 시간은 task_events 기준, 자주 완료하는 시간대는 completed_at 기준. soft-delete로 통계를 유지하고 migrations를 버전 관리합니다.

## 알림 구조 (아직 구현 전)

DB 저장 → 이전 예약 취소 → 다음 due 또는 reminder 시간 예약 → OS가 앱 미실행 상태에서 표시 → 액션으로 이벤트/상태 저장 → 다음 알림 재예약. 완료/건너뛰기 시 해당 회차 알림 제거, 반복 규칙은 유지. 시작은 진행 중으로 변경하고 확인 알림 예약. 보류는 original_due를 보존하고 reminder_at만 변경.

iOS는 [UNUserNotificationCenter 로컬 예약](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app), UNNotificationAction을 사용합니다. 무한한 백그라운드 실행을 전제하지 않고 한정된 재알림을 미리 예약한 뒤 앱 재진입/액션에서 갱신합니다. 시스템 예약 제한, 집중 모드, 권한 거부를 실기기에서 검증해야 합니다.

Android는 지정 시각에 AlarmManager로 일회성 예약 후 NotificationManager로 표시합니다. 정확한 알림은 [정확한 알람 권한 및 canScheduleExactAlarms](https://developer.android.com/develop/background-work/services/alarms)를 확인하고 허용되지 않으면 지연 가능한 예약을 사용하며 UI에 알려줍니다. WorkManager는 정밀 시각 알림이 아닌 예약 복구·정리 용도입니다. Android 알림 권한, 부팅 후 재예약, 시간대 변경, 절전 모드, 제조사 정책을 확인합니다.

재알림은 하루 상한 및 방해 금지 시간을 실제 앱에서 추가해 사용자가 통제할 수 있게 합니다. ‘계속 진행 중’ 선택 시 다음 상태 확인을 예약합니다. 현재 시안에는 해당 선택과 반복 확인 상한이 없습니다.

## 출시 순서

UX 확인 → 공유 앱/로컬 DB → iOS·Android 알림/액션 병행 구현 및 실기기 검증 → TestFlight·Play 내부 테스트 → 스토어용 개인정보 안내 및 데이터 보존 정책 → 두 스토어 동시 제출. 심사 결과에 따라 공개일이 달라질 수 있으므로 양쪽 승인 후 공개 일정을 맞춥니다. 서버·가입·클라우드 DB 없이 진행하며 백업 제외 설정으로 앱 삭제/기기 변경 시 유실 가능성을 명확히 안내합니다.
