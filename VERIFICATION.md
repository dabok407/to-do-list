# 개발 검증 기록

검증 대상은 `mobile/`의 실제 Flutter iOS·Android 앱이다. 웹 프로토타입의 성공을 네이티브 앱 검증으로 대체하지 않는다. 스토어 계정·로그인·상품 설명 작성·심사 제출은 이 개발 검증에 포함하지 않는다.

## 구현 범위

- SQLite 로컬 저장, 서버·회원가입·클라우드 동기화 없는 실행
- 월·주 캘린더, 날짜별 할 일, 오늘·주·월 요약과 상태별 목록
- 등록·수정·삭제, 시작·진행·보류·완료·완료 해제·건너뛰기 복원
- N일, N주 지정 요일, 주 N회 목표, N개월 날짜, 월 특정/마지막 요일과 종료일
- 반복 회차 이번만·앞으로 수정, 이번만·앞으로·전체 삭제와 과거 기록 보존
- OS 로컬 알림, 미루기·재알림·5분 시작·시간대 변경·Android 재부팅 복구
- Android AppWidget 및 iOS WidgetKit, 가까운 일정·우선순위·시작·미루기와 상세 이동
- 최근 30일 통계와 완료 해제에 따른 통계 복원
- 앱과 백그라운드 작업의 SQLite 잠금·예약 동기화, 6시간 주기 예약 충전 요청

2026-10-09 추가 요청으로 분류·빠른 입력·일정 제목 표시와 Pro 연간 자동 갱신 구독·90일 완료 기록·분류별 분석을 구현했다. AI·광고·클라우드는 포함하지 않는다. 구독의 실제 상품 등록·Sandbox/라이선스 테스트는 아직 수행하지 못했으며 [BILLING.md](mobile/BILLING.md)에 계정 연결 절차와 검증 경계를 기록했다.

## 자동 검증

2026-10-09 로컬 실행: `flutter analyze` 오류 없음, `flutter test` 46개 통과. iOS GMT 시간대 회귀 검증, 320px·글꼴 1.5배 화면 조작과 실제 파일 DB 2→4 마이그레이션도 포함한다. 구독 테스트 4개는 플랫폼 채널의 모의 응답을 사용하며 실제 스토어 청구·갱신 테스트를 대체하지 않는다.

구독·디자인 추가 소스 `97dbf51`의 [GitHub Actions 실행](https://github.com/dabok407/to-do-list/actions/runs/37884534266)은 검증 중이다. iOS 시뮬레이터 앱 빌드와 Android debug APK·release bundle 빌드 단계를 통과했으며 네이티브 실행 단계는 결과 확인 전이다. [앞선 `f5aa59d` 실행](https://github.com/dabok407/to-do-list/actions/runs/37877943803)은 양쪽 모두 성공했다. 이후 `0e8e8a5` 실행은 iOS 접근성 트리 검사와 Android 테스트 VM 연결에서 실패했으며, 현재 실행에는 실제 iOS 화면 OCR 검증과 Android 고정 VM 포트 연결을 반영했다. 작은 Android 위젯의 시간 문구 잘림 수정도 현재 실행에서 재검증한다.

브라우저에서는 실제 Flutter 화면에 샘플 데이터를 연결한 `design-review.html`을 실행했다. 월→주 보기, 안방 대청소의 완료→완료 해제, 구독 안내→샘플 Pro 전환→90일 기록·분류별 분석 표시를 직접 확인했다. 이 환경에는 실제 결제·OS 알림이 없으며 네이티브 검증과 구분한다.

| 검증 | 현재 증거 |
| --- | --- |
| 반복·회차 예외·삭제·주간 목표·이벤트·통계·예약 계획 | 로컬 회귀 테스트 통과 |
| 알림 권한 거부·직렬 액션·완료 해제 | 로컬 및 양쪽 네이티브 통합 테스트 통과 |
| Android Kotlin 컴파일 | 로컬 컴파일 통과 |
| Android debug APK·release AAB | 이전 CI 빌드 통과, 로컬 서명 release AAB 최종 빌드·서명 검증 통과 |
| Android 실제 에뮬레이터 알림·프로세스 종료·재부팅·위젯 | 종료·재부팅 알림, 3개 위젯 크기, 미루기 버튼·콜드 링크·headless 예약 보충 통과. 마지막 compact 표시 수정 재검증 중 |
| iOS 앱 및 WidgetKit 시뮬레이터 빌드 | CI 빌드 통과 |
| iPhone 시뮬레이터 UI·알림·권한 거부·콜드 링크 | CI 모두 통과, 콜드 링크 후 진행 중 DB 상태·화면 확인 |
| WidgetKit 데이터·소형/중형 화면 렌더링 | CI XCTest 통과, 소형·중형 렌더링 이미지 확인 |
| iOS release 빌드, 서명 제외 | CI 통과 (배포 서명·실기기 설치 증거와는 구분) |

Android 서명 결과(구독·디자인 및 구독 전 안내 문구 수정 포함, 2026-10-09): `mobile/build/app/outputs/bundle/release/app-release.aab`, 약 56.1 MB. SHA-256: `241978CE453DBAEA05D695A355135A1538BFE5400645054D5BB79FDD96D412E0`. JDK jarsigner 결과 `jar verified`. 자체 서명 인증서·타임스탬프 부재와 ZIP 스트림에서의 manifest 순서 경고가 출력됐으며 Play 설치·승인을 증명하는 결과는 아니다. Android 업로드 키는 아직 스토어 계정에 연결하지 않았다. Play 상품 공개 검증 키가 없는 빌드이므로 실제 구매는 비활성화되며 계정 연결 후 재빌드해야 한다.

## 재현

```sh
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build appbundle --release
```

Android 배포 서명은 `mobile/tool/prepare_android_signing.ps1`로 로컬에 준비한다. `mobile/android/upload-key.jks`와 `key.properties`는 Git에 포함하지 않는다. 둘을 안전한 별도 저장소에 함께 백업해야 같은 앱의 업데이트 서명을 유지할 수 있다.

macOS에서는 `flutter build ios --simulator --debug`, `flutter build ios --release --no-codesign`으로 계정 없이 컴파일을 확인한다. CI는 네이티브 실행 스크립트와 Flutter 드라이버, XCTest 결과 및 화면 캡처를 artifact로 남긴다.

## 플랫폼 검증 경계

일반 매일·매주·월간 반복은 조건에 맞으면 OS 반복 알림으로 예약한다. 복잡한 반복·종료일·변경 예외는 가까운 개별 예약과 백그라운드 충전을 사용한다. iOS 예약 개수와 백그라운드 실행 시각, 집중 모드·사용자 알림 권한·기기 절전 정책은 OS가 결정한다. 앱은 권한 상태를 표시하고 권한 거부 상태에서도 할 일 저장과 변경을 지원한다.

iOS 배포 서명·AppGroup 등록·실제 iPhone 설치는 Apple 개발자 계정 연결 후 진행한다. 이 Windows 환경에서 실제 iPhone 및 제조사별 Android 실기기 테스트를 수행했다는 의미는 아니다. 시뮬레이터 결과와 실기기 결과를 구분한다.
