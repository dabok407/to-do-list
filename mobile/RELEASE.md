# 한걸음 모바일 출시

목표: iOS·Android 공통 MVP를 개발·검증하고 두 스토어에 동시에 제출한다. 사용자 계정·운영 서버·클라우드 DB는 사용하지 않는다. GitHub Actions는 개발·빌드 도구이며 앱 실행 중 필요한 서버가 아니다.

## 현재 검증

첫 모바일 구현 커밋 6d83f5e는 GitHub Actions에서 분석·단위 테스트·Android debug APK·iOS simulator debug·iOS release no-codesign 빌드를 통과했다. 후속 변경은 해당 커밋의 성공으로 검증됐다고 간주하지 않으며 각 Actions 결과를 확인한다.

## 계정 준비

- Apple Developer Program 가입 여부 확인 및 App Store Connect 앱 생성. Bundle ID: com.dabok407.hangeoreum. 표시 이름: 한걸음.
- 기존 Google Play Console 계정 복구 및 접근 확인. 신규 계정이면 콘솔에서 요구하는 신원·기기·테스트 요건을 확인한다.
- 스토어 지원 이메일, 개인정보 안내 URL, 배포 국가, 연령 등급 설문을 확정한다. 저장소·APK·시뮬레이터 빌드는 스토어 게시와 다르다.
- Mac을 소유할 필요는 없다. GitHub macOS runner에서 컴파일할 수 있다. 서명된 iOS 설치·업로드에는 Apple 배포 인증서와 프로비저닝 프로파일 또는 클라우드 서명 서비스가 필요하다. iPhone에서 TestFlight 알림 검증을 수행한다.

## Android 서명 및 빌드

android/key.properties 파일은 저장소에서 제외한다. 업로드용 keystore를 안전하게 보관한다. 예전 앱을 업데이트하는 경우 기존 앱 ID와 업로드 키를 먼저 확인한다.

```properties
storeFile=../upload-key.jks
storePassword=YOUR_PASSWORD
keyAlias=upload
keyPassword=YOUR_PASSWORD
```

```sh
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

key.properties가 있을 때만 release 키로 서명한다. debug 키를 스토어용 서명으로 대체하지 않는다. 서명된 build/app/outputs/bundle/release/app-release.aab를 Play 내부 테스트에 올리고 검증 후 프로덕션 심사를 요청한다.

## iOS 서명 및 빌드

GitHub Actions Mobile verification은 시뮬레이터와 서명 전 릴리스만 검증한다. 서명 전 빌드를 iPhone에 설치하거나 App Store에 업로드할 수 없다.

Apple 계정의 Team ID, 배포 인증서, 프로비저닝 프로파일을 준비한 macOS 빌드 환경에서 Runner의 Signing 설정을 com.dabok407.hangeoreum에 맞춘다. 해당 키·인증서·API 키를 저장소나 대화에 붙여넣지 않고 CI secrets에 보관한다.

```sh
flutter pub get
flutter build ipa --release
```

서명된 build/ios/ipa 결과를 App Store Connect에 업로드하고 TestFlight를 통해 실제 iPhone에서 검증한다. 스토어 메타데이터와 개인정보 설문을 완료한 뒤 심사에 제출한다. 양쪽 승인 후 수동 공개일을 맞춘다.

## 실제 기기 검증

- 앱을 닫은 상태에서 지정 시각 알림, 알림 액션, 보류 및 재알림.
- 완료·완료 해제 후 예약 알림과 통계 일치.
- 기기 재부팅, 시간대 변경, 집중 모드·알림 거부·정확한 알람 권한 거부.
- 반복 일정의 종료일·월말·요일·이번만/앞으로 수정.
- 앱 재시작 후 SQLite 데이터 보존, 앱 삭제 시 데이터 제거.
- 한국어 확대 글꼴·작은 화면·키보드 표시·빈 제목·입력 오류.

## 제한

가까운 예약 최대 60개를 OS에 등록하고 앱 진입·사용자 액션에서 재충전한다. iOS 예약 제한을 고려한 구조이며, 장기간 앱을 전혀 열지 않을 경우 예약 범위 밖의 알림은 보장하지 않는다. 보류 재알림은 같은 날 30·60분 후 두 번 추가 예약한다. Android 정확한 알람 권한이 없으면 지연 가능한 알림으로 예약한다.

실제 OS 위젯, 임의 요일 주 N회 목표, Pro, 동기화, 광고는 미구현이다. 위젯은 후속 기능이며 웹의 위젯 탭은 미리보기다. 앱은 의료·진단 도구가 아니다.
