# 투두닉(Todoniq): Windows에서 iPhone TestFlight 빌드 준비하기

> 2026-10-11 최신 결정: 사용자는 본인 명의 개인사업자 등록을 신청하고 발급을 기다립니다. 기존 Apple 계정·앱·서명을 유지하며 타인 사업자·세금·은행 정보를 혼합하지 않습니다. TestFlight 외부 601 베타 심사는 신청 완료, 공개 App Store의 앱 601·Pro 상품·구독 그룹 심사 초안은 준비 완료이며 정식 심사는 미제출입니다.

2026-10-11 현재, 최종 소스 `fc88e97b140db0c32a2ba88b97a621f04187b9e5`의 **1.0.0 (601)**이 [Android·iOS 네이티브 QA 실행 38114962066](https://github.com/dabok407/to-do-list/actions/runs/38114962066), [실제 macOS 서명 실행 38115046318](https://github.com/dabok407/to-do-list/actions/runs/38115046318), [원본 IPA 업로드 실행 38118780821](https://github.com/dabok407/to-do-list/actions/runs/38118780821)에 성공했습니다. Apple API에서 빌드 ID `ef4ef617-58c7-4177-9688-5a3cb99a1546`의 **processingState=VALID, expired=false, usesNonExemptEncryption=false, internalBuildState=IN_BETA_TESTING**을 확인했습니다. Apple 업로드 시각은 **2026-10-11 15:45:14 KST**입니다. 기존 **Todoniq Owner** 내부 그룹에 601·501·101이 연결되어 본인 내부 테스트가 가능합니다.

사용자의 실제 iPhone에서 **101 설치와 501 업데이트 설치 후 피드백을 확인했습니다**. 사용자는 **601 화면을 수용하고 이 UI로 출시하는 것을 승인했으며**, 601의 실제 iPhone 알림·위젯·입력 흐름과 결제 검증은 아직 남아 있습니다. 외부 그룹의 이전 101 베타 심사를 철회하고 **601을 Todoniq Preview에 연결해 베타 심사를 신청**했습니다. 마지막 확인은 **심사 대기 중**, 승인 후 **자동으로 테스터에게 공지** 설정 완료입니다. 실제 초대 메일 전달은 아직 확인되지 않았습니다.

공개 App Store 버전 1.0.0은 **빌드 601·승인 후 자동 출시·데이터 수집 없음 게시**를 저장했습니다. Pro 심사용 화면을 업로드하고 상품·구독 그룹까지 같은 초안에 추가했습니다. **앱 601·Pro 연간 상품·구독 그룹 총 3개**와 활성화된 **심사를 위해 제출** 버튼을 확인했으며 정식 심사·공개 출시는 미완료입니다. 심사용 화면은 실제 앱 컴포넌트에 등록 가격의 모의 응답을 적용한 자료이며 실제 StoreKit 결제 검증과 구분합니다. 앱과 연간 Pro의 배포·판매 국가는 각각 **EU 27개국을 제외한 148개 국가 또는 지역**, 향후 국가 자동 추가 끔입니다. 사용자는 이후 EU 확대를 요청했고 현재 DSA 연락처 인증 후 이름 확인 문서 제출을 기다립니다.

개인 Mac을 구매할 필요는 없습니다. Windows에서 준비하고 GitHub Actions의 **macOS 15 / Xcode 26.3 / Flutter 3.47.6** 실행기로 빌드합니다. iOS 서명·빌드는 실제 macOS 환경에서 실행됩니다. [Flutter iOS 배포 안내](https://docs.flutter.dev/deployment/ios)

## 601에서 달라진 화면과 입력

1. 전체 화면에서 입력 필드 밖을 누르거나 스크롤하면 키보드를 닫습니다. 작성 중인 초안을 유지하며 필드 이동과 버튼 동작도 그대로 실행합니다.
2. 월 보기에서 날짜를 누르면 선택한 날짜의 주 보기로 전환하는 동작을 복원했습니다.
3. 날짜와 시간을 하나의 테두리·라벨이 있는 같은 행에 배치했습니다. 왼쪽은 날짜, 오른쪽은 시간이며 모든 테두리 입력의 떠 있는 라벨 표시를 통일했습니다.
4. 편집 순서는 날짜/시간 → 분류 → 우선순위 → 할 일 → 메모 → 미완료 재알림 → 반복 → 선택형 ‘작게 시작하기’입니다.
5. 반복 간격의 기본값 1은 접힌 상태로 표시합니다. 설명은 N주·N개월 반복 주기를 안내합니다.
6. 반복 종료일은 새 회차를 만드는 마지막 날이며, 오래된 미완료 회차의 재알림과 별개임을 안내합니다.
7. 주간·월간 반복 패턴을 오가도 선택한 요일을 유지하고, 잘못된 반복 간격은 오류 안내와 포커스로 알려줍니다.
8. 도움말은 ‘작게 시작하기’에 적은 첫 행동이 같은 회차를 오늘 3번 이상 미룬 뒤 상세 화면의 ‘5분 시작’ 안내에 표시된다고 설명합니다.

로컬 `flutter analyze`는 **문제 없음**, 단위·위젯 테스트는 **208개 통과 / 선택형 스토어 이미지 생성 테스트 1개 건너뜀**입니다. [모바일 자동 QA 실행 38114962066](https://github.com/dabok407/to-do-list/actions/runs/38114962066)의 Android·iOS 네이티브 검증도 성공했습니다. 양쪽 실행 로그의 `NATIVE_KEYBOARD_DISMISSAL_OK`, iOS의 `IOS_TERMINATED_NOTIFICATION_OK`, Android의 `BACKGROUND_NOTIFICATION_OK`·`REBOOT_NOTIFICATION_OK`와 위젯 콜드 딥 링크 검증을 확인했습니다. 자동 검증과 실제 iPhone 설치 후 검증은 구분하며, 601의 실제 iPhone 알림·위젯·입력 흐름과 실제 스토어 구매는 아직 검증하지 않았습니다.

## 이전 501 배포 이력

소스 `2951bdb7c9ae5feb70d1ff40ad49d4b8bf1cf8db`의 **1.0.0 (501)**은 [macOS 서명 실행 38103987813](https://github.com/dabok407/to-do-list/actions/runs/38103987813)과 [원본 IPA 업로드 실행 38105521301](https://github.com/dabok407/to-do-list/actions/runs/38105521301)에 성공했습니다. Apple API에서 빌드 ID `6e4f66d2-a918-4ff2-8345-3633ed4b76b2`의 **processingState=VALID, expired=false, usesNonExemptEncryption=false, internalBuildState=IN_BETA_TESTING**을 확인했습니다. Apple 업로드 시각은 **2026-10-11 11:39:13 KST**, 원본 IPA SHA-256은 `6551ceabb0f6a0d47864e1c9efe9a1aee948154484fce1e73983816f9186fef7`입니다. 이 해시는 501의 기록이며 601의 해시가 아닙니다. 이후 사용자가 실제 iPhone에 501 업데이트를 설치하고 피드백을 제공했습니다.

501 당시 화면과 입력 변경은 다음과 같습니다. 월 보기 유지 동작과 편집 순서는 이후 601에서 위 내용으로 변경됐습니다.

1. 월 보기에서 날짜를 눌러도 월 보기를 유지하고, 주 보기로 강제 축소하지 않습니다.
2. 빠른 추가 입력을 자체 Material 위에 그려 테두리 겹침과 스크롤 전 화면 갱신 문제를 해결했습니다. 체험 안내와의 간격은 16픽셀입니다.
3. 미완료 재알림 스위치에 회색·검정·흰색을 적용하고, iOS에서 표시되는 스위치에도 같은 색 규칙을 적용했습니다.
4. 추가 화살표와 키보드 제출을 지원합니다. 빈 입력은 포커스와 오류 안내로 처리하며, 앞뒤 공백·대소문자·연속 공백을 정리해 중복을 확인합니다. 중복 확인을 취소하면 입력을 유지하고, 추가를 승인하면 별도 고유 ID를 만듭니다.
5. 제목 아래에 시간 필드를 배치했습니다. 오늘은 현재 시각에서 60분 뒤를 기본값으로 쓰되 23:59를 넘지 않고, 다른 날짜는 09:00을 사용합니다. 사용자가 선택한 시간은 날짜를 바꿔도 유지합니다.
6. 공통 시간 선택기가 다이얼·직접 입력 모드를 기기에 저장하고, 취소했을 때도 모드 선택을 기억합니다. 최초 기본 모드는 다이얼입니다.
7. 편집 순서는 분류 → 날짜 → 시간 → 할 일 → 메모 → 우선순위 → 미완료 재알림 → 반복 → 실행 보조입니다.

[모바일 자동 QA 실행 38103738656](https://github.com/dabok407/to-do-list/actions/runs/38103738656)의 Android·iOS 검증이 성공했습니다. 단위·위젯 테스트는 **196개 통과·1개 건너뜀**, 서명 실행의 큰 글씨 검증은 **35개**, Swift 검증은 **14개**, Android 큰 글씨 검증은 **16개**가 통과했습니다. 동일 시각의 실제 OS 알림 2개는 **앱이 전경에 있는 상태**에서 확인했고, **앱 종료 상태의 OS 알림은 별도 1개**를 확인했습니다. 알림 권한 거절 상태의 할 일 저장·완료·완료 해제·삭제를 검증했으며 권한 재허용은 미검증입니다. 오프라인 유료 기능 검증은 모의 구독 상태를 사용했으며 실제 스토어 구매 검증은 남아 있습니다.

## 1. 이미 등록한 Apple 항목 확인

[Apple Developer 계정](https://developer.apple.com/account/) → **Certificates, Identifiers & Profiles**에서 다음 항목을 확인합니다.

| 항목 | 값 |
| --- | --- |
| Team ID | `B2MTNFVL58` |
| 앱 Bundle ID | `com.dabok407.hangeoreum` |
| 위젯 Bundle ID | `com.dabok407.hangeoreum.TasksWidget` |
| 두 타깃의 App Group | `group.com.dabok407.hangeoreum` |
| App Store Connect 앱 ID | `6821236391` |
| 새 공개 앱 이름 | 투두닉 - 할 일과 캘린더 / Todoniq - Tasks & Calendar |

앱과 위젯의 Identifiers에서 **App Groups**가 켜져 있고 같은 그룹이 연결되어 있어야 합니다. 기존 내부 식별자는 앱 표시 이름과 별개이므로 바꾸지 않습니다.

## 2. 배포 인증서와 두 프로파일 준비

이 작업은 인증서와 개인키를 생성합니다. 이번 배포용 자격 증명은 사용자의 명시적 승인 후 생성·등록을 완료했습니다. 아래 절차는 향후 재생성할 때 참고합니다. 개인키, `.p12`, 비밀번호, API `.p8` 파일을 대화창이나 공개 소스 저장소에 올리지 마세요.

Apple의 일반 CSR 안내는 Mac 키체인을 기준으로 설명합니다. Windows에서는 설치된 Git Bash의 OpenSSL로 같은 CSR 형식을 만들 수 있습니다. 다음 명령은 **미리 준비하는 절차 예시**이며 지금 실행된 것이 아닙니다. 파일은 Git에 추가하지 않는 개인 보관 폴더에서 만들고, 비밀번호는 명령행 인자로 넣지 않고 프롬프트에 입력합니다. [Apple CSR 안내](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request), [OpenSSL req 문서](https://docs.openssl.org/master/man1/openssl-req/)

```bash
openssl genrsa -aes256 -out firstkan-distribution.key 2048
openssl req -new -key firstkan-distribution.key -out firstkan-distribution.csr
```

1. Developer 계정 → **Certificates** → **+** → **Apple Distribution** → **Continue**.
2. CSR 파일을 선택해 등록하고 배포 인증서 `.cer`를 내려받습니다. CSR을 만든 개인키를 반드시 함께 보관합니다.
3. Git Bash에서 인증서와 개인키를 합친 암호화 `.p12`를 만듭니다. 아래 `distribution.cer`는 내려받은 실제 파일명으로 맞춥니다.

```bash
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey firstkan-distribution.key -in distribution.pem -out firstkan-distribution.p12
```

4. Developer 계정 → **Profiles** → **+** → **Distribution / App Store Connect** → **Continue**.
5. 앱 ID를 선택하고 위에서 만든 **Apple Distribution** 인증서를 선택합니다. 프로파일 이름을 입력해 **Generate → Download**합니다.
6. 위젯 ID로 4~5번을 반복합니다. 두 프로파일은 같은 배포 인증서를 선택하고 App Group을 포함해야 합니다. [Apple 배포 프로파일 안내](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)

서명 helper는 만료, Team ID, 앱·위젯 ID, App Group, 배포용 여부와 인증서 일치를 확인합니다. 개발용·Ad Hoc 프로파일로는 이 workflow를 실행할 수 없습니다.

## 3. 업로드 API 키 준비

서명된 파일을 만들기만 할 때는 API 키가 필요하지 않습니다. TestFlight 업로드를 켤 때 다음 세 항목이 필요합니다.

[App Store Connect](https://appstoreconnect.apple.com/) → **Users and Access → Integrations → App Store Connect API → Team Keys**에서 API 접근이 활성화되어 있는지 확인합니다. 권한을 가진 계정으로 **+**를 눌러 키를 만들고, 빌드 업로드에 필요한 **Developer** 역할을 우선 검토합니다. 실제 계정 화면에서 허용되는 최소 권한을 확인합니다. **Issuer ID**, **Key ID**를 기록하고 `.p8` 개인키를 내려받습니다. 개인키는 한 번만 내려받을 수 있으므로 안전하게 보관합니다. [Apple API 안내](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api), [빌드 업로드 권한 안내](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)

## 4. GitHub Secrets 등록

저장소 **Settings → Environments → New environment**에서 `ios-testflight`를 만듭니다. 환경을 열어 **Environment secrets → Add secret**에 아래 이름 그대로 등록합니다. 필요한 경우 승인자를 설정하여 업로드 전에 사람이 확인하도록 합니다. Secret 값은 로그·채팅·커밋에 남기지 않습니다. 등록 및 외부 전송은 사용자가 승인한 뒤 수행합니다.

| Secret 이름 | 넣을 값 | 필요한 경우 |
| --- | --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | `.p12` 파일의 Base64 | 서명 빌드 |
| `IOS_DISTRIBUTION_P12_PASSWORD` | `.p12` 내보내기 비밀번호 | 서명 빌드 |
| `IOS_APP_PROFILE_BASE64` | 앱 `.mobileprovision`의 Base64 | 서명 빌드 |
| `IOS_WIDGET_PROFILE_BASE64` | 위젯 `.mobileprovision`의 Base64 | 서명 빌드 |
| `ASC_ISSUER_ID` | Team API Issuer ID | 업로드 |
| `ASC_API_KEY_ID` | API Key ID | 업로드 |
| `ASC_API_PRIVATE_KEY` | `.p8` 내용 전체, BEGIN/END와 줄바꿈 포함 | 업로드 |

파일 Base64는 PowerShell에서 아래처럼 클립보드에 복사할 수 있습니다. 실제 파일 경로로 바꾸고 `.p12`, 앱 프로파일, 위젯 프로파일 각각 수행합니다. 출력으로 개인키를 표시하지 않습니다. Base64는 암호화가 아니므로 원본과 같은 수준으로 보호합니다.

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\개인보관폴더\firstkan-distribution.p12')) | Set-Clipboard
```

환경을 만들지 않고 저장소 **Settings → Secrets and variables → Actions**에 Repository secrets를 넣는 방식도 지원됩니다. workflow는 `ios-testflight` 환경을 사용하므로 같은 이름이 환경과 저장소 양쪽에 있으면 환경의 값을 우선 사용합니다. 실행기는 임시 키체인을 만들고 종료 시 개인키·프로파일 임시 파일과 키체인을 정리합니다. [GitHub Xcode 서명 안내](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)

## 5. 먼저 서명 빌드만 실행

`.github/workflows/ios-testflight.yml`이 GitHub 기본 브랜치에 반영된 뒤 저장소 **Actions → iOS signed build and TestFlight → Run workflow**를 사용합니다. 이 문서 작성만으로 workflow가 업로드되거나 실행되지는 않습니다.

1. 출시할 소스 브랜치를 선택합니다.
2. `version`: `1.0.0`처럼 세 자리 숫자 버전을 입력합니다.
3. `build_number`: 처음에는 비워둡니다. 실행 번호와 재실행 횟수로 새 번호를 만듭니다.
4. `upload_to_testflight`: **false**로 둡니다.
5. 테스트, 네이티브 위젯 검증, 서명 빌드가 통과하면 실행 결과의 **Artifacts**에서 `firstkan-ios-버전-번호`를 받습니다.

결과에는 `firstkan.ipa`, 심볼 ZIP, 버전·SHA256 기록이 포함됩니다. 이 단계의 성공은 서명 파일 준비 완료를 뜻하며 iPhone에 배포되었다는 뜻은 아닙니다. IPA에는 앱과 위젯, 한국어·영어가 함께 들어갑니다.

## 6. TestFlight 업로드

이번 작업은 사용자가 배포 자격 증명 준비와 GitHub Secrets 저장·업로드 사용을 승인했습니다. 먼저 생성한 서명 IPA를 업로드할 때는 **Upload existing signed iOS build to TestFlight** (`ios-testflight-upload.yml`)를 실행합니다. 최신 601의 입력 예시는 원본 성공 실행 **38115046318**, 버전 **1.0.0**, 빌드 **601**입니다. 원본 실행의 저장소·브랜치·워크플로·성공 상태, GitHub 아티팩트 digest, manifest/IPA SHA-256와 macOS 실제 서명·프로파일·App Group을 검사한 뒤 원본 IPA를 그대로 업로드합니다. 이번 [업로드 실행 38118780821](https://github.com/dabok407/to-do-list/actions/runs/38118780821)은 검증·업로드에 성공했으며, 실행 로그에서 확인한 601의 원본 IPA SHA-256은 `577f15e39ec6fef7a29f5f28595764ffccea80018fb3daf0869b98a0a93fa11b`입니다. 재빌드하거나 앱 코드와 빌드 번호를 변경하지 않습니다.

새 앱 코드로 빌드를 만들 때는 `ios-testflight.yml`의 `upload_to_testflight`를 **true**로 실행할 수도 있습니다. Apple은 이미 업로드한 버전의 같은 빌드 번호를 다시 받지 않으므로 새 빌드에는 새 번호를 사용합니다. 두 workflow 모두 App Store Connect에 빌드만 업로드하며 공개 App Review에 제출하지 않습니다.

업로드가 성공해도 Apple의 처리 시간이 남습니다. [앱 TestFlight 페이지](https://appstoreconnect.apple.com/apps/6821236391/testflight)에서 빌드가 나타나는지 확인하고, **Missing Compliance**가 있으면 실제 암호화 사용 내용에 맞춰 수출 규정 질문에 답합니다. 업로드 성공과 처리 완료를 구분합니다. [Apple 빌드 업로드 안내](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)

### 수출 규정 확인과 이전 101 준비 이력

실제 IPA의 Flutter.framework에는 BoringSSL의 표준 TLS 암호화 구현이 포함되어 있습니다. 앱에서 별도의 암호화 API를 호출하지 않아도 Apple의 확인 범위에는 포함된 외부 라이브러리가 들어갑니다. 이전 101 준비 당시인 2026-10-10에는 사용자 승인에 따라 프랑스 제외를 결정했습니다. 콘솔에서 **Apple OS 암호화를 대체하거나 병행하는 표준 알고리즘**과 **프랑스 배포: 아니요**를 저장했고, 빌드 101의 **수출 규정 관련 문서 누락**이 해소되어 **제출 준비 완료**로 변경된 것을 확인했습니다.

501과 최신 601 모두 Apple API의 `usesNonExemptEncryption=false`와 내부 테스트 가능 상태를 확인했습니다.

Apple 안내는 OS 외 표준 암호화를 사용하는 앱의 프랑스 App Store 배포에 프랑스 암호화 신고서를 요구합니다. 프랑스를 추가할 때는 해당 신고서 요건과 수출 답변을 다시 확인합니다. 이전 101 준비 당시 실제 App Availability에서도 프랑스만 제외한 **174개 국가 또는 지역** 선택과 향후 국가 자동 추가 끔을 재확인했습니다. 현재 2026-10-11의 앱·연간 Pro 설정은 각각 **EU 27개국 제외 148개 국가 또는 지역**이며 향후 국가 자동 추가 끔을 유지합니다. `ITSAppUsesNonExemptEncryption=NO`는 자동으로 추가하지 않았습니다. [Apple 수출 규정 문서 기준](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)

## 7. 내 iPhone에 설치

1. App Store에서 Apple의 **TestFlight** 앱을 설치합니다.
2. App Store Connect → **앱 → 투두닉 - 할 일과 캘린더 → TestFlight**를 엽니다.
3. **Internal Testing → Todoniq Owner**에서 기존 내부 테스트 그룹을 엽니다.
4. 그룹에 **1.0.0 (601)**이 연결되어 내부 테스트가 가능한지 확인합니다. 새 내부 테스터를 추가할 때는 **Invite Testers**에서 테스트할 App Store Connect 사용자를 선택합니다.
5. 기존에 501을 설치한 iPhone의 TestFlight에서 601로 **Update**합니다. 처음 설치하는 경우 실제 Apple 계정에 온 초대를 받아 **Install**을 누릅니다.

현재 **Todoniq Owner** 내부 그룹은 자동 배포를 끄고 빌드를 수동으로 추가하도록 설정했습니다. **1.0.0 (601)·1.0.0 (501)·1.0.0 (101)**의 연결을 확인했고, 601은 **IN_BETA_TESTING**으로 내부 테스트가 가능합니다. 사용자의 실제 iPhone에 101 설치와 501 업데이트 설치가 확인됐고 피드백을 받았습니다. 601 UI의 출시 승인은 받았으며, 실제 iPhone 업데이트·알림·위젯·입력 흐름과 결제 검증은 남아 있습니다. 사용자가 요청한 추가 테스터 한 명은 **Todoniq Preview** 외부 그룹에 등록했습니다. 이전 101의 베타 심사를 철회하고 최신 601을 외부 그룹에 추가해 베타 심사를 신청했습니다. 마지막 확인은 **601 심사 대기 중**이며 **자동으로 테스터에게 공지**를 켰습니다. 외부 테스터의 설치 초대는 승인된 빌드가 제공된 후 가능합니다. 공개 초대 링크는 만들지 않았습니다. 테스터의 개인 이메일은 공개 문서에 기록하지 않습니다.

내부 테스트 설치와 공개 App Store 출시는 다른 단계입니다. 외부 테스터 배포에는 Beta App Review가 필요할 수 있습니다. 실제 구독 결제 테스트에는 구독 상품·계약·Sandbox 설정도 별도로 완료해야 합니다. [Apple 내부 테스터 안내](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)

## 문제가 나면 확인할 항목

- `필수 GitHub Secret 없음`: 이름과 `ios-testflight` 환경의 값 확인.
- 프로파일 만료·App Group 불일치: 올바른 ID와 인증서로 앱·위젯 프로파일을 다시 생성.
- 배포 인증서 불일치: CSR 개인키와 해당 인증서가 들어 있는 `.p12`인지 확인.
- 빌드 번호 중복: 새 번호로 실행.
- 업로드 성공 후 빌드 미표시: Apple 처리 상태와 업로드 단계 결과를 확인.

현재 남은 실제 검증은 **601의 iPhone 업데이트·알림·위젯·입력 흐름 검증과 실제 구독 구매 확인**입니다. 권한 재허용도 미검증입니다. 601의 Android·iOS 네이티브 QA·macOS 서명 빌드·원본 IPA 업로드·Apple 처리·암호화 답변 확인과 소유자 내부 그룹 연결은 완료했습니다. 외부 그룹의 최신 601 베타 심사는 신청 완료·승인 대기 중이며 승인 후 자동 공지를 설정했습니다. Apple 구독 그룹 `22461798`과 연간 상품 `6821330921`(`hangeoreum_pro_yearly`)을 생성하고 1년 기간·한국어·영어 이름과 설명을 저장했습니다. 그룹 표시 이름도 한국어 투두닉 Pro / 영어 Todoniq Pro로 저장했으며 앱 이름 사용 기본 옵션을 유지했습니다. 연간 상품의 판매 국가는 **EU 27개국 제외 148개 국가 또는 지역·향후 국가 자동 추가 끔**으로 저장했습니다. **연간 상품의 심사용 추가 정보(선택사항) 메모는 저장 완료**입니다. 상품 ID·601과 함께 심사·설정 → Pro 구매/복원/관리·7일 체험 비자동결제·무료/Pro 범위·로컬 데이터/StoreKit 안내를 포함합니다. **Pro 신규 구독자 연간 가격은 미국 USD $0.69·대한민국 KRW ₩900.00으로 저장 완료**입니다. Pro 심사용 화면은 실제 앱 컴포넌트와 등록 가격의 모의 응답으로 제작·업로드하고 출처를 공개했습니다. 실제 StoreKit 구매/복원·갱신 등의 검증은 미완료입니다. TestFlight 베타 심사 제출을 공개 App Store 심사 제출이나 출시 완료로 표시하지 않습니다.

공개 App Store 버전 1.0.0의 첨부 빌드는 101에서 **601로 교체·저장**했으며, 출시 방식은 **심사 승인 후 자동 출시**로 저장했습니다. 무료 설치 가격 $0.00, **EU 27개국 제외 148개 국가 또는 지역·향후 국가 자동 추가 끔**, 첫 모바일 출시의 Mac·Vision Pro 배포 끔을 저장했습니다. 콘텐츠 권리는 타사 콘텐츠 없음, 연령 설문은 의료 정보 없음·웰빙 주제 포함으로 저장했으며 대한민국 전체·일반 글로벌 9+가 적용됩니다.

이전 ‘심사에 추가’의 실제 사전검증은 **개인정보 답변 게시 미완료로 차단**됐고, App Store Connect는 관리자에게 **‘앱이 수집하는 개인정보’ 섹션에 개인정보 처리지침 정보를 제공**하라는 오류를 표시했습니다. 이후 사용자 승인에 따라 Apple 앱 개인정보의 **데이터 수집 없음 답변을 게시 완료**했으며 실제 화면에서 확인했습니다. 개인정보 처리방침 URL도 저장돼 있습니다. 현재는 **개인정보 차단 해소·601 심사 초안 준비됨**이며, 정식 심사 제출과 공개 출시는 아직 완료하지 않았습니다.

Pro 심사용 화면을 업로드해 스크린샷 누락 오류를 해소하고 상품·구독 그룹을 같은 초안에 추가했습니다. 2026-10-11 23:14 KST **제출 준비된 항목 3개(앱 601·Pro 연간 상품·구독 그룹)** 및 활성화된 **심사를 위해 제출** 버튼을 확인했습니다. 정식 심사는 미제출이며 계약 활성화·실제 결제 검증은 별도로 남아 있습니다.

2026-10-11 연간 상품 `6821330921`의 신규 구독자 가격표에서 **미국 USD $0.69·대한민국 KRW ₩900.00 저장**을 확인했습니다. 다른 판매 국가의 가격은 자동 환산을 사용합니다. **2026-10-11 실제 비즈니스 화면**의 무료 앱 계약은 **활성화됨**, 유료 앱 계약은 **사용자 정보 대기 중(Pending User Info)**입니다. **대한민국 전자상거래법 항목의 활성화 상태**를 확인했습니다. **은행 정보는 제출 후 처리 중이며 24시간 후 변경 사항 표시 안내가 있고, 활성화는 미확인**입니다. 미국 외국인 지위 인증서(`U.S. Certificate of Foreign Status of Beneficial Owner`)와 **W-8BEN은 모두 활성화됨**이며, **대한민국 세금 양식은 미제출(세금 정보 없음)**입니다. 이후 사용자가 EU 확대 및 공개 연락처 사용을 승인하여 DSA 거래자 이메일·전화 인증을 완료했습니다. 현재 **이름 확인 문서 업로드 대기**입니다. 국가 설정은 아직 148개이며 EU 확대 완료로 기록하지 않습니다. 유료 계약 활성화·대한민국 세금 등록·은행 처리 완료는 남아 있습니다. 정식 공개 심사는 아직 제출하지 않았습니다. Google도 미국 US$0.69/년·대한민국 ₩900/년을 목표로 준비하지만 실제 Play 상품·가격 등록은 아직 없습니다.

대한민국 세금 양식은 **사업자등록번호(BRN)와 최근 90일 이내 증명서**, 또는 **국세청 고유번호와 최근 90일 이내 고유번호증** 및 영어 번역본을 요구합니다. 이 입력란에 주민등록번호를 대체 입력하지 않습니다. [Apple 대한민국 세금 정보 요건](https://developer.apple.com/kr/help/app-store-connect/manage-tax-information/provide-tax-information)
