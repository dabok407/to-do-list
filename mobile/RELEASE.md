# 한걸음 모바일 출시

목표: iOS·Android 공통 앱을 개발·검증하고 두 스토어에 동시에 제출한다. 사용자 계정·운영 서버·클라우드 DB는 사용하지 않는다. GitHub Actions는 개발·빌드 도구이며 앱 실행 중 필요한 서버가 아니다.

## 구현 및 검증 상태

할 일·캘린더·반복 회차·주 N회 목표·범위별 삭제·통계, Android AppWidget·iOS WidgetKit, OS 반복 알림·백그라운드 예약 보충을 구현했다. DB는 분류를 추가한 schema v5이며 iOS 앱과 위젯은 App Group의 읽기용 스냅샷을 공유한다. 연간 자동 갱신 Pro와 90일·분류별 분석을 추가했다.

첫 실행 7일 체험과 기능별 유료 접근 제어를 추가했다. 로컬 전체 테스트는 84개 통과했으며 최신 정적 분석·빌드·네이티브 결과는 검증 보고서에 구분해 기록한다. 최신 CI 소스·실행 번호, 네이티브 실행 검증, 서명된 AAB, 실기기 테스트 결과는 [검증 보고서](../VERIFICATION.md)에서 확인한다. 진행 중인 검증을 성공으로 기록하거나 과거 커밋의 성공으로 최신 변경을 검증했다고 간주하지 않는다.

현재 CI는 Android debug APK·서명 전 release AAB·에뮬레이터 통합/권한 거부/네이티브 생명주기, iOS simulator 빌드·통합/권한 거부·WidgetKit XCTest/렌더링/링크·release no-codesign을 검증하도록 구성했다. CI 성공과 물리 기기·스토어 배포 서명 검증은 구분한다.

## 계정 준비

- Apple Developer Program 가입 여부 확인 및 App Store Connect 앱 생성. 앱 Bundle ID: `com.dabok407.hangeoreum`. 표시 이름: 한걸음.
- 기존 Google Play Console 계정 복구 및 접근 확인. 기존 앱 업데이트라면 앱 ID·업로드 키를 먼저 대조한다. 신규 계정의 신원·기기·테스트 요건은 계정 연결 후 콘솔에서 확인한다.
- 지원 이메일, 지원 URL, 공개 개인정보 안내 URL, 배포 국가·가격·연령 등급을 확정한다. [스토어 문안](STORE_METADATA.md)은 초안이다.
- Mac 소유는 필수가 아니다. GitHub macOS runner에서 컴파일할 수 있지만 iPhone 설치·업로드에는 Apple 배포 인증서·프로비저닝 프로파일 또는 클라우드 서명이 필요하다.

## 처음 가입하는 사용자용 진행 순서

### Apple: 아이폰에서 개발자 등록

1. 아이폰 설정 맨 위의 Apple 계정을 확인하고 이중 인증을 활성화한다. 앱 구매용 계정과 개발자 등록 계정을 혼동하지 않도록 기록한다.
2. App Store에서 Apple의 **Apple Developer** 앱을 설치한다. 앱의 **Account(계정)** 탭에서 Apple 계정으로 로그인한다.
3. **Enroll Now(지금 등록)**를 선택하고 본인 확인·법적 이름·주소·연락처를 입력한다. 혼자 배포한다면 Individual(개인)을 검토한다. 개인 등록 시 판매자 이름에 법적 이름이 표시된다.
4. 계약과 연회비를 확인하고 가입한다. Apple Developer Program은 연 US$99 또는 현지 통화로 청구하며 실제 결제 화면의 금액을 확인한다.
5. 승인 후 [App Store Connect](https://appstoreconnect.apple.com)에 같은 계정으로 로그인한다. 개발자 프로그램 가입과 앱 등록은 별도 단계다.

근거: [Apple 앱에서 등록하기](https://developer.apple.com/help/account/membership/enrolling-in-the-app), [프로그램 등록](https://developer.apple.com/help/account/membership/program-enrollment/).

### Google: 기존 Gmail로 먼저 확인

1. PC 브라우저에서 [Google Play Console](https://play.google.com/console)에 과거 배포 때 사용한 Google 계정으로 로그인한다. Gmail 계정을 사용할 수 있지만 Gmail 가입만으로 개발자 등록이 완료되는 것은 아니다.
2. 기존 개발자 계정이나 앱 목록이 보이면 그 계정을 사용한다. 등록 화면이 나온다면 과거의 다른 Google 계정으로도 확인한 뒤 신규 등록을 판단한다.
3. 신규 등록은 개인/조직 유형 선택 → 연락처·개발자 정보 → 계약 → US$25 일회성 등록비 → 신원 확인 순서로 진행한다. 콘솔에 추가 확인이 표시되면 완료한다.
4. 신규 개인 계정은 Android 기기의 Play Console 앱을 통한 기기 확인이 요구될 수 있다. 아이폰만 있다면 이 단계에서 실제 Android 기기 접근이 필요하다.
5. 2023년 11월 13일 이후 생성한 신규 개인 계정은 프로덕션 접근 신청 전에 최소 12명의 테스터가 연속 14일 참여하는 비공개 테스트가 필요하다. 기존 계정에 같은 조건이 적용되는지는 콘솔에서 확인한다.

근거: [Play Console 시작하기](https://support.google.com/googleplay/android-developer/answer/6112435?hl=ko), [신규 개인 계정 테스트 요건](https://support.google.com/googleplay/android-developer/answer/14151465?hl=ko).

### 계정 승인 후 업로드와 심사

| 단계 | iOS | Android |
| --- | --- | --- |
| 앱 등록 | App Store Connect → Apps → + → New App. iOS·한걸음·한국어·Bundle ID·고유 SKU 입력 | Play Console 홈 → 앱 만들기. 한걸음·한국어·앱·무료 설치 선택 |
| 파일 준비 | macOS 빌드 환경에서 앱과 위젯을 같은 Team/App Group으로 서명한 IPA | 로컬 업로드 키로 서명한 AAB |
| 테스트 업로드 | 서명 빌드 업로드 후 해당 앱의 TestFlight에서 내부 테스트 설정, 아이폰 TestFlight 앱으로 설치 | 해당 앱 → 테스트 및 출시 → 테스트 → 내부 테스트에서 새 버전 생성·AAB 업로드·테스터 등록 |
| 추가 테스트 | 실제 아이폰에서 알림·위젯·재시작 확인 | 계정에 요구되는 비공개 테스트와 프로덕션 접근 신청 |
| 제출 자료 | 앱 정보·개인정보·가격/배포·버전 설명·스크린샷·지원 URL·심사 연락처·빌드 선택 | 대시보드의 필수 설정, 스토어 등록정보·앱 콘텐츠·데이터 보안·연령 등급·개인정보 URL |
| 심사 제출 | 버전 화면 Add for Review → 제출 화면 Submit for Review | 프로덕션 버전 생성 → 오류/필수 항목 해결 → 변경사항 심사 전송 |
| 동시 공개 | 수동 출시 선택 후 양쪽 승인까지 대기 | 관리형 게시를 사용해 양쪽 승인 후 공개 시점 조정 |

메뉴는 콘솔 언어·계정 상태에 따라 이름이 달라질 수 있다. 앱 생성이나 테스트 업로드만으로 스토어에 공개되지 않는다. 각 심사 결과와 재심사 여부에 따라 공개일이 달라진다.

근거: [Apple 앱 생성](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app), [Apple 빌드 업로드](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [Apple 심사 제출](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app), [Google 앱 만들기](https://support.google.com/googleplay/android-developer/answer/9859152?hl=ko).

Mac PC를 직접 소유할 필요는 없지만 iOS 빌드·서명에는 macOS 환경이 필요하다. 이 저장소의 GitHub macOS 검증과 배포용 서명 설정은 구분한다. 개발자 계정 연결 후 클라우드 macOS 빌드에서 서명하고 TestFlight로 사용자의 아이폰에 설치할 수 있다.

### 연간 자동 갱신 Pro

사용자 요청에 따라 Pro 1년 자동 갱신 상품을 구현했다. 목표 미국 가격은 US$0.70/년이며 실제 허용 가격은 양쪽 콘솔에서 확인해야 한다. 한국 가격은 원화로 별도 설정한다. 앱은 StoreKit/Play가 반환한 가격을 표시한다. 무료 앱 설치 가격과 Pro 구독 가격은 별도로 등록한다. 첫 실행부터 7일은 앱 내부 체험이며 자동 청구되지 않는다. 체험 종료 후 사용자가 구독을 구매하면 연간 자동 갱신한다. 중복 체험이 생기지 않도록 별도 스토어 무료 체험 상품은 추가하지 않았으며 광고도 없다.

유료 계약·세금·수익 지급 계좌·상품 ID/가격 등록을 완료한 후 구매 성공·취소·실패·복원·오프라인 이용을 테스트한다. 서버 없이 기기에서 스토어 SDK로 구매 상태를 조회할 수 있으며, 다른 플랫폼에서 산 권한까지 공통 계정으로 공유하는 기능은 포함하지 않는다. 앱 데이터 복원과 같은 스토어 계정의 구매 복원은 별개다. 상품이 등록되기 전에는 실제 결제 테스트가 끝났다고 간주하지 않는다.

상품 ID는 양쪽 모두 `hangeoreum_pro_yearly`, Play 기본 요금제 ID는 `annual`이다. [결제 연결 문서](BILLING.md)의 순서로 상품·Android 공개 검증 키를 등록한다. 기간·갱신 금액·해지 방법은 구매 화면에 표시한다. 만료·갱신·취소·복원·유예 상태의 실제 스토어 테스트는 상품 등록 후 필요하다. Apple 구독에는 지속적인 사용자 가치가 필요하다. [Apple 구독 안내](https://developer.apple.com/app-store/subscriptions/).

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

미완료 재알림은 기본 다음 날부터 매일 예정 시각에 예약한다. 할 일별로 끄기·1/2/3/7일 간격·별도 시각을 선택한다. 미루기는 사용자가 선택한 시간까지 기다린다. 미래 시작 재알림은 최대 32회 미리 예약하고, OS 예약 용량 내에서 가까운 시각부터 사용한다. 앱 재실행과 OS가 허용한 백그라운드 작업에서 충전하며, 이미 기한이 지난 단발성 일일·주간 재알림은 안전한 경우 OS 반복으로 전환한다. 앱을 장기간 한 번도 열지 않고 백그라운드 갱신도 허용되지 않는 경우 미래 시작·복잡한 반복의 무기한 전달은 보장하지 않는다. Android 정확한 알람 권한이 없으면 지연 가능한 알림을 사용한다. 위젯은 읽기용 스냅샷을 표시하며 시작·미루기 액션은 앱을 열어 DB를 갱신한다. WidgetKit 갱신 빈도도 OS 정책의 영향을 받는다.

Pro·동기화·광고·구독은 현재 범위에 포함하지 않는다. 앱은 의료·진단 도구가 아니다. 스토어 게시·계정 로그인·업로드·심사 제출은 아직 완료했다고 간주하지 않는다.
