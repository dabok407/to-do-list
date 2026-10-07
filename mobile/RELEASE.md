# 한걸음 모바일 출시

목표: iOS·Android 공통 앱을 개발·검증하고 두 스토어에 동시에 제출한다. 사용자 계정·운영 서버·클라우드 DB는 사용하지 않는다. GitHub Actions는 개발·빌드 도구이며 앱 실행 중 필요한 서버가 아니다.

## 구현 및 검증 상태

최신 기능 구현 커밋은 `38eaf33`이다. 할 일·캘린더·반복 회차·주 N회 목표·범위별 삭제·통계, Android AppWidget·iOS WidgetKit, OS 반복 알림·백그라운드 예약 보충을 구현했다. DB는 schema v3이며 iOS 앱과 위젯은 App Group의 읽기용 스냅샷을 공유한다.

로컬 `flutter analyze`와 `flutter test` 34개는 통과했다. 최신 CI run `37481741623`, 네이티브 실행 검증, 서명된 AAB, 실기기 테스트 결과는 [검증 보고서](../VERIFICATION.md)에서 확인한다. 진행 중인 검증을 성공으로 기록하거나 과거 커밋의 성공으로 최신 변경을 검증했다고 간주하지 않는다.

현재 CI는 Android debug APK·서명 전 release AAB·에뮬레이터 통합/권한 거부/네이티브 생명주기, iOS simulator 빌드·통합/권한 거부·WidgetKit XCTest/렌더링/링크·release no-codesign을 검증하도록 구성했다. CI 성공과 물리 기기·스토어 배포 서명 검증은 구분한다.

## 계정 준비

- Apple Developer Program 가입 여부 확인 및 App Store Connect 앱 생성. 앱 Bundle ID: `com.dabok407.hangeoreum`. 표시 이름: 한걸음.
- 기존 Google Play Console 계정 복구 및 접근 확인. 기존 앱 업데이트라면 앱 ID·업로드 키를 먼저 대조한다. 신규 계정의 신원·기기·테스트 요건은 계정 연결 후 콘솔에서 확인한다.
- 지원 이메일, 지원 URL, 공개 개인정보 안내 URL, 배포 국가·가격·연령 등급을 확정한다. [스토어 문안](STORE_METADATA.md)은 초안이다.
- Mac 소유는 필수가 아니다. GitHub macOS runner에서 컴파일할 수 있지만 iPhone 설치·업로드에는 Apple 배포 인증서·프로비저닝 프로파일 또는 클라우드 서명이 필요하다.

## Android 서명 및 빌드

`mobile/android/upload-key.jks`와 `mobile/android/key.properties`는 로컬에 생성했다. 두 파일은 Git에서 제외하며 비공개로 보관한다. keystore를 암호화한 별도 저장소에 백업하고 alias·암호는 안전한 비밀번호 관리 도구에 보관한다. 키 파일·암호를 저장소나 대화에 붙여넣지 않는다. 기존 Play 앱을 업데이트할 때는 새 로컬 키가 해당 앱의 업로드 키와 맞는지 먼저 확인한다.

Gradle은 `key.properties`가 있을 때 release 키를 사용한다. debug 키를 스토어 서명으로 대체하지 않는다. CI에는 로컬 키가 제공되지 않으므로 CI의 release AAB는 스토어 업로드용 서명 완료 증거가 아니다.

```sh
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

로컬에서 서명된 AAB 빌드를 진행했으며 완료·서명 확인 결과는 [검증 보고서](../VERIFICATION.md)에 기록한다. 결과 경로는 `build/app/outputs/bundle/release/app-release.aab`다. 빌드 성공과 서명 확인 후 Play 내부 테스트에 업로드하고 설치·알림·위젯을 검증한 뒤 프로덕션 심사를 요청한다.

## iOS 앱·위젯 서명 및 빌드

CI의 `--release --no-codesign` 빌드는 서명 전 컴파일 검증이며 iPhone 설치나 App Store 업로드에 사용할 수 없다. 배포 서명은 Apple 계정 연결 후 진행한다.

Apple 계정의 Team ID·배포 인증서·프로비저닝 프로파일을 준비하고 Runner 앱과 HangeoreumWidget 확장을 같은 Team으로 서명한다. 앱 Bundle ID와 위젯 확장 ID를 등록하고 양쪽에 App Group `group.com.dabok407.hangeoreum`을 연결한다. 앱/확장의 entitlements와 배포 프로파일에 같은 App Group이 포함되어야 한다. 인증서·개인키·API 키는 저장소나 대화 대신 CI secrets에 보관한다.

```sh
flutter pub get
flutter build ipa --release
```

서명된 `build/ios/ipa` 결과를 App Store Connect에 업로드하고 TestFlight로 실제 iPhone에서 설치·알림·위젯·App Group 공유를 검증한다. 스토어 메타데이터와 개인정보 설문을 완료한 뒤 심사에 제출한다. 양쪽 승인 후 수동 공개일을 맞춘다.

## 실제 기기 검증

아래 항목의 기기·OS·빌드·실행 결과를 [검증 보고서](../VERIFICATION.md)에 남긴다. 에뮬레이터/시뮬레이터에서 통과한 항목도 실제 배포 빌드의 물리 기기 결과로 대체하지 않는다.

- 앱을 닫은 상태의 지정 시각 알림, 알림 본문 열기·시작·10분 미루기·완료 액션, 보류 재알림과 진행 상태 확인.
- 완료·완료 해제·이번 회차/앞으로/전체 삭제 후 알림·위젯·통계 일치.
- Android 재부팅, 시간대 변경, 집중 모드·절전·알림 거부·정확한 알람 권한 거부.
- 일/주/월 OS 반복 알림, 종료일·월말·요일·이번만/앞으로 수정, 주 N회 목표 달성·주간 전환.
- Android 홈 화면 위젯 설치·크기 변경, iOS 작은/중간 WidgetKit 위젯 설치, 데이터 갱신·빈 상태·우선순위·진행 중 표시.
- 앱이 열려 있을 때와 종료된 상태의 위젯 할 일 열기·시작·미루기, iOS App Group 스냅샷 공유.
- OS가 허용한 백그라운드 실행에서 예약 보충·위젯 갱신, 장시간 앱 미사용 시 예약 범위와 갱신 기록.
- 앱 재시작 후 SQLite 보존, schema v3 마이그레이션, 앱 삭제 후 데이터 제거.
- 한국어 확대 글꼴·작은 화면·키보드·빈 제목·입력 오류.

## 알림 및 위젯 동작 범위

iOS 최대 60개·Android 최대 400개 예약을 등록한다. 종료일이 없고 간격이 1인 일/주 반복과 매월 28일 이내 날짜 반복은 미래 회차 상태·예외·시작일 조건이 맞을 때 OS 반복 알림으로 압축한다. 종료일·간격·예외가 있는 반복, 월말/특정 번째 요일, 주 N회 목표 등은 개별 예약을 사용한다.

앱 진입·사용자 액션과 백그라운드 실행에서 예약을 보충한다. Workmanager의 최초 지연과 요청 주기는 각각 6시간이며 네트워크를 요구하지 않는다. 실제 실행 시각·빈도는 OS가 결정한다. 강제 종료·절전 등으로 보충이 지연되고 개별 예약 범위를 넘어가면 알림을 보장하지 않는다. 설정 화면에서 알림·정확한 알람 권한과 테스트 알림을 확인할 수 있다. 최근 백그라운드 갱신 시각은 로컬 settings에 저장한다.

보류 재알림은 선택한 시간과 같은 날 30·60분 후 두 번 추가 예약한다. Android 정확한 알람 권한이 없으면 지연 가능한 알림을 사용한다. 위젯은 읽기용 스냅샷을 표시하며 시작·미루기 액션은 앱을 열어 DB를 갱신한다. WidgetKit 갱신 빈도도 OS 정책의 영향을 받는다.

Pro·동기화·광고·구독은 현재 범위에 포함하지 않는다. 앱은 의료·진단 도구가 아니다. 스토어 게시·계정 로그인·업로드·심사 제출은 아직 완료했다고 간주하지 않는다.
