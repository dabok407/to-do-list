# 투두닉(Todoniq): Windows에서 iPhone TestFlight 빌드 준비하기

2026-10-10 현재, 사용자가 승인한 Apple 배포 인증서·앱/위젯 프로파일과 업로드 API 키를 준비하고 지정한 GitHub `ios-testflight` 환경의 Secrets 7개에 등록했습니다. [실제 macOS 서명 실행 38044570593](https://github.com/dabok407/to-do-list/actions/runs/38044570593)이 테스트·프로파일 검증·IPA 내보내기에 성공했습니다. 버전은 **1.0.0 (101)**입니다. [원본 IPA 업로드 실행 38047340077](https://github.com/dabok407/to-do-list/actions/runs/38047340077)도 macOS 실제 서명 재검증과 Apple 업로드 단계를 통과했습니다. Apple API에서 해당 앱·빌드의 **processingState=VALID, expired=false**를 확인했습니다. 업로드 시각은 **2026-10-10 20:09:49 KST**입니다. 수출 규정 질문을 완료하고 소유자 내부 테스트에 빌드를 연결했습니다. 콘솔에서 소유자의 **초대됨** 상태를 확인했습니다. 추가 외부 테스터를 등록하고 TestFlight 베타 심사도 제출했으며 **심사 대기 중**입니다. 실제 iPhone 설치·실행 확인은 별도로 남아 있습니다.

개인 Mac을 구매할 필요는 없습니다. Windows에서 준비하고 GitHub Actions의 **macOS 15 / Xcode 26.3 / Flutter 3.47.6** 실행기로 빌드합니다. iOS 서명·빌드는 실제 macOS 환경에서 실행됩니다. [Flutter iOS 배포 안내](https://docs.flutter.dev/deployment/ios)

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

이번 작업은 사용자가 배포 자격 증명 준비와 GitHub Secrets 저장·업로드 사용을 승인했습니다. 먼저 생성한 서명 IPA를 업로드할 때는 **Upload existing signed iOS build to TestFlight** (`ios-testflight-upload.yml`)를 실행합니다. 원본 성공 실행 **38044570593**, 버전 **1.0.0**, 빌드 **101**을 지정합니다. 원본 실행의 저장소·브랜치·워크플로·성공 상태, GitHub 아티팩트 digest, manifest/IPA SHA-256와 macOS 실제 서명·프로파일·App Group을 검사한 뒤 원본 IPA를 그대로 업로드합니다. 재빌드하거나 앱 코드와 빌드 번호를 변경하지 않습니다.

새 앱 코드로 빌드를 만들 때는 `ios-testflight.yml`의 `upload_to_testflight`를 **true**로 실행할 수도 있습니다. Apple은 이미 업로드한 버전의 같은 빌드 번호를 다시 받지 않으므로 새 빌드에는 새 번호를 사용합니다. 두 workflow 모두 App Store Connect에 빌드만 업로드하며 공개 App Review에 제출하지 않습니다.

업로드가 성공해도 Apple의 처리 시간이 남습니다. [앱 TestFlight 페이지](https://appstoreconnect.apple.com/apps/6821236391/testflight)에서 빌드가 나타나는지 확인하고, **Missing Compliance**가 있으면 실제 암호화 사용 내용에 맞춰 수출 규정 질문에 답합니다. 업로드 성공과 처리 완료를 구분합니다. [Apple 빌드 업로드 안내](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)

### 현재 수출 규정 확인 항목

실제 IPA의 Flutter.framework에는 BoringSSL의 표준 TLS 암호화 구현이 포함되어 있습니다. 앱에서 별도의 암호화 API를 호출하지 않아도 Apple의 확인 범위에는 포함된 외부 라이브러리가 들어갑니다. 2026-10-10 사용자 승인에 따라 첫 App Store 출시는 프랑스를 제외합니다. 콘솔에서 **Apple OS 암호화를 대체하거나 병행하는 표준 알고리즘**과 **프랑스 배포: 아니요**를 저장했고, 빌드 101의 **수출 규정 관련 문서 누락**이 해소되어 **제출 준비 완료**로 변경된 것을 확인했습니다.

Apple 안내는 OS 외 표준 암호화를 사용하는 앱의 프랑스 App Store 배포에 프랑스 암호화 신고서를 요구합니다. 프랑스를 추가할 때는 해당 신고서 요건과 수출 답변을 다시 확인합니다. 수출 답변과 별도로 실제 App Availability에서도 프랑스를 제외해 **사용 불가**, 나머지 174개 국가 또는 지역이 선택된 것을 재확인했습니다. 향후 국가 자동 추가는 껐습니다. `ITSAppUsesNonExemptEncryption=NO`는 자동으로 추가하지 않았습니다. [Apple 수출 규정 문서 기준](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)

## 7. 내 iPhone에 설치

1. App Store에서 Apple의 **TestFlight** 앱을 설치합니다.
2. App Store Connect → **앱 → 투두닉 - 할 일과 캘린더 → TestFlight**를 엽니다.
3. **Internal Testing → +**로 내부 테스트 그룹을 만듭니다.
4. **Invite Testers**에서 테스트할 App Store Connect 사용자를 추가하고 **Add Builds**에서 처리된 빌드를 연결합니다.
5. iPhone에서 초대를 받아 TestFlight의 **Install**을 누릅니다. 실제 Apple 계정에 온 초대를 사용합니다.

현재 **Todoniq Owner** 내부 그룹은 자동 배포를 끄고 빌드를 수동으로 추가하도록 설정했습니다. 빌드 1.0.0 (101)을 연결하고 기존 소유자 한 명의 **초대됨** 상태를 확인했습니다. 사용자가 요청한 추가 테스터 한 명은 **Todoniq Preview** 외부 그룹에 등록했습니다. 외부 그룹에도 빌드 101을 연결하고 베타 설명·테스트 항목·승인된 심사 연락처를 입력해 **TestFlight 베타 심사 대기 중** 상태를 확인했습니다. 외부 테스터의 설치 초대는 승인된 빌드가 제공된 후 가능합니다. 공개 초대 링크는 만들지 않았습니다. 테스터의 개인 이메일은 공개 문서에 기록하지 않습니다.

내부 테스트 설치와 공개 App Store 출시는 다른 단계입니다. 외부 테스터 배포에는 Beta App Review가 필요할 수 있습니다. 실제 구독 결제 테스트에는 구독 상품·계약·Sandbox 설정도 별도로 완료해야 합니다. [Apple 내부 테스터 안내](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)

## 문제가 나면 확인할 항목

- `필수 GitHub Secret 없음`: 이름과 `ios-testflight` 환경의 값 확인.
- 프로파일 만료·App Group 불일치: 올바른 ID와 인증서로 앱·위젯 프로파일을 다시 생성.
- 배포 인증서 불일치: CSR 개인키와 해당 인증서가 들어 있는 `.p12`인지 확인.
- 빌드 번호 중복: 새 번호로 실행.
- 업로드 성공 후 빌드 미표시: Apple 처리 상태와 업로드 단계 결과를 확인.

현재 남은 실제 검증은 **iPhone 알림·위젯·구독 확인**이며 외부 테스트는 Apple의 베타 심사 승인을 기다립니다. 자격 증명 등록, 실제 macOS 서명 빌드·업로드·Apple 처리, 수출 질문과 소유자 내부 초대는 완료했습니다. Apple 구독 그룹 `22461798`과 연간 상품 `6821330921`(`hangeoreum_pro_yearly`)을 생성하고 1년 기간·한국어·영어 이름과 설명을 저장했습니다. 그룹 표시 이름도 한국어 투두닉 Pro / 영어 Todoniq Pro로 저장했으며 앱 이름 사용 기본 옵션을 유지했습니다. 연간 완납 상품의 판매 국가를 프랑스 제외 174개 국가 또는 지역·향후 국가 자동 추가 끔으로 저장했습니다. 가격·상품 심사 자료·계약·세금/계좌와 실제 스토어 구매 검증은 남아 있습니다. TestFlight 베타 심사 제출을 공개 App Store 심사 제출이나 출시 완료로 표시하지 않습니다.

공개 App Store 버전 1.0.0에는 빌드 101을 연결·저장했습니다. 무료 설치 가격 $0.00, 프랑스 제외 174개 국가 또는 지역·향후 국가 자동 추가 끔, 첫 모바일 출시의 Mac·Vision Pro 배포 끔을 저장했습니다. 콘텐츠 권리는 타사 콘텐츠 없음, 연령 설문은 의료 정보 없음·웰빙 주제 포함으로 저장했으며 대한민국 전체·일반 글로벌 9+가 적용됩니다. 개인정보 답변은 데이터 미수집으로 초안을 저장했고 게시 동의는 대기 중입니다.

Apple의 실제 추가 가격 목록에는 목표 US$0.70/년이 없고 US$0.69/년을 선택할 수 있습니다. 대한민국 자동 환산 제안은 ₩1,100이며 대한민국 가격 ₩1,100 또는 ₩900 선택은 사용자 답변 대기 상태로 아직 저장하지 않았습니다. 2026-10-10 실제 비즈니스 화면의 무료 앱 계약은 **활성화됨**, 유료 앱 계약은 **신규**입니다. 소유자의 개인 정보 확인·계약·세금·은행 등록, EU DSA·대한민국 계정 정보와 실제 구독 구매 검증이 남습니다. 정식 공개 심사는 아직 제출하지 않았습니다.
