# 투두닉(Todoniq): Windows에서 iPhone TestFlight 빌드 준비하기

## 현재 — 1301 내부 TestFlight 제공·업데이트 심사 접수 (2026-10-25)

**1.0.2 (1301)**은 Apple 처리 **VALID**, 수출 규정 **usesNonExemptEncryption=false**, 기존 **Todoniq Owner** 연결 **IN_BETA_TESTING**을 확인했다. 본인 iPhone의 **TestFlight → 투두닉 → 업데이트**에서 받는다. 목록을 새로고침하고 버전 **1.0.2 (1301)**을 확인한다. 실제 iPhone 설치와 StoreKit 구매/환불은 별도 미확인이다.

**2026-10-25 18:11 KST** 공개 업데이트 심사에 iOS 1.0.2 (1301) 한 항목을 제출했다. 제출 `c31ce4ac-0366-498f-b308-e54b4c32aa6f`는 **WAITING_FOR_REVIEW / AFTER_APPROVAL**이며, 공개 버전은 **1.0.1 (1203), READY_FOR_SALE**을 유지한다. 한영 메타데이터·42장 이미지 COMPLETE를 확인했고 검증한 원본 IPA를 다시 빌드·서명·업로드하지 않았다. [검증 기록](store/review/update-qa-2026-10-22.json)을 따른다. Google 등록은 보류한다.

이하의 1203·1101 및 이전 상태 설명은 당시의 이력이다.

## 현재 — 1203 공개 재심사 접수 완료 (2026-10-18 10:33 KST)

사용자 승인으로 **1101 제출을 철회**하고 기존 공개 버전 레코드의 번호를 **1.0.1**로 바꾼 뒤, 본인 TestFlight에 제공한 동일한 **1203**을 연결했다. 한국어 설명 **2,017자**·영어 설명 **3,725자**와 1203 영어 심사 메모를 저장하고 실제 Apple 값과 대조했다. **2026-10-18 10:33 KST**, 새 제출 `3fa9f819-92c4-4b4f-85e3-afa568bd28d7`의 **앱 1.0.1 (1203)·연간 상품·구독 그룹 모두 심사 대기 중**을 실제 화면에서 확인했다. API는 **WAITING_FOR_REVIEW / AFTER_APPROVAL**이며 승인 후 자동 출시 설정을 유지했다. 승인이나 공개 출시 완료로 표시하지 않는다.

최신 UI의 Apple 소개 이미지 42장과 한영 ZIP 2개를 준비·검증했다. 한영 캡처 테스트 **4개**, 가격·타 플랫폼 홍보 차단 정책 테스트 **5개**, 소개 PNG **56장·자산 4개** 규격, Apple 42장 출처 및 ZIP 각각 22파일의 SHA 대조를 통과했다. 최신 정적 분석도 문제 없다. 실제 Apple 중형 iPhone·iPad의 한영 **28장 전체 교체**를 마쳤고, 모든 이미지의 **COMPLETE·파일명·순서·크기·MD5 및 로컬 SHA 출처**를 대조했다. 제출 후 API에서 한영 문안·앱명·부제·개인정보 URL·선택 빌드·출시 설정도 재확인했다.

연간 구독 상품 심사 메모의 구형 1001 안내를 **최초 공개 출시 1.0.1 (1203)**로 수정했다. 상품의 나머지 내용·가격·기간·판매 지역과 기존 비공개 Pro 구매 화면 첨부는 유지했다. 해당 첨부는 fixture를 사용한 프로덕션 화면 렌더이며 실제 구매 증빙으로 표시하지 않는다. 별도 심사 메시지는 보내지 않았다. [1203 재심사 접수 기록](store/review/resubmission-2026-10-18-1203.json)에 최종 결과를 남겼다.

프로덕션 소스 `daf25c5987fd292060b7805e290e068bfd525597`와 Apple 빌드 `d49a0d17-346d-4d59-a5ce-2fdcec9bad0a`를 그대로 사용한다. 기존 원본 IPA의 SHA-256 `4304207c4accf4be3bb73a9ecbf7927cebf5f821e2596e4a6532ec0af7e2e89b`를 유지하며 새 빌드 생성·재업로드는 필요하지 않았다. 본인 TestFlight 연결은 유지하고 실제 iPhone 설치·StoreKit 구매 성공을 이번 자료 검증의 결과로 주장하지 않는다. 아래의 1101 심사 유지 기록은 1203 공개 교체를 승인하기 전의 이력이다. Google 개발자 계정 작업은 보류한다.

## 현재 — 1203 내부 TestFlight 업데이트 가능 (2026-10-18)

**1.0.1 (1203)**에 분류 버튼 5개 한 줄 균등 배치와 새 일정 기본 우선순위 **보통**을 반영했다. 기본 분류는 생활이며 기존 일정의 분류·우선순위는 유지한다. iPhone에서 **TestFlight → 투두닉 → 업데이트**로 설치한다. 목록에 업데이트가 바로 보이지 않으면 아래로 당겨 새로고침하고, 앱 상세 화면에서 **1.0.1 (1203)**인지 확인한다.

검증 소스 `daf25c5987fd292060b7805e290e068bfd525597`의 [서명·업로드 39026570583](https://github.com/dabok407/to-do-list/actions/runs/39026570583)와 [Android·iOS QA 39026551490](https://github.com/dabok407/to-do-list/actions/runs/39026551490)가 모두 **SUCCESS**다. 로컬 테스트 **430개 통과 / 선택형 캡처 3개 건너뜀**, 정적 분석 문제 없음이다. 원본 IPA SHA-256은 `4304207c4accf4be3bb73a9ecbf7927cebf5f821e2596e4a6532ec0af7e2e89b`이며 로컬·별도 백업·manifest·GitHub 아티팩트 digest를 대조했다.

Apple 빌드 `d49a0d17-346d-4d59-a5ce-2fdcec9bad0a`의 **VALID / expired=false / usesNonExemptEncryption=false / IN_BETA_TESTING**, 기존 Todoniq Owner 그룹의 **테스트 중** 표시를 **2026-10-18 09:45 KST**에 확인했다. 업로드 시각은 **2026-10-17 20:11:47 KST**다. 기존 1101·1202 그룹 연결과 공개 **1.0.0 (1101)**의 심사 대기·선택 빌드·승인 후 자동 출시 설정을 유지했다. 새 공개 버전·업데이트 심사·외부 그룹은 변경하지 않았다. 실제 iPhone의 1203 설치와 실제 StoreKit 결제는 아직 확인하지 않았다. [1203 검증·업로드 기록](store/review/update-1.0.1-1203.json)에 근거를 남겼다.

## 이전 — 1202 내부 TestFlight 업데이트 제공 (2026-10-17)

**1.0.1 (1202)**을 [원본 IPA 업로드 39015097225](https://github.com/dabok407/to-do-list/actions/runs/39015097225)로 전달하고 Apple의 **VALID / expired=false / usesNonExemptEncryption=false**를 확인했다. 기존 **Todoniq Owner** 내부 그룹에 추가했으며 공식 API의 **IN_BETA_TESTING**과 브라우저의 **테스트 중** 표시를 확인했다. 본인 iPhone에서 **TestFlight → 투두닉 → 업데이트**로 **1.0.1 (1202)**을 받을 수 있다. 업데이트가 바로 보이지 않으면 앱 목록을 아래로 당겨 새로고침한다.

업로드 시각은 **2026-10-17 16:51:25 KST**, Apple 빌드 ID는 `957b1e9f-984b-4000-b18d-55f3540a4390`다. 서명된 1202 원본을 재빌드·재서명하지 않았으며 SHA-256은 `7ce6d405fccb1ad75c8678243871eb895a0b25ca7a3c5b691aafb53442ba76cf`다. 기존 그룹 빌드와 외부 테스트 그룹을 유지했다.

공개 **1.0.0 (1101)**은 같은 빌드 연결과 승인 후 자동 출시 설정을 유지하며 최종 조회에서 **심사 대기 중**이다. 1202의 공개 버전 생성·업데이트 심사 제출은 하지 않았다. 실제 iPhone의 1202 설치·StoreKit 결제/복원은 아직 별도 확인 사항이다. [1202 준비·업로드 기록](store/review/update-1.0.1-1202.json)에 이력과 대조 결과를 남겼다.

## 이전 준비 — 1.0.1 (1202), 사용자 후속 6건 (2026-10-17)

시간 수정 중복을 고친 1201에 이어 스와이프 완료/해제·되돌리기, 빠른 추가 한 시간 뒤 기본값, 기타 분류, 분류·우선순위 직접 선택, 신규 낮음 기본값과 유료 체험 카드 숨김을 추가했다. 기존 일정의 우선순위와 기록은 유지한다. 검증된 구매·복원만 유료 UI를 적용하며 대기·취소·실패는 체험/무료 상태를 유지한다. Pro 화면 진입 중 구독 조회로 생기던 프레임 갱신 오류도 수정했다.

로컬 전체 테스트 **393개 통과 / 선택형 캡처 3개 건너뜀**, 별도 한·영 등록 화면 캡처 테스트 **14개 통과**, 정적 분석 문제 없음을 확인했다. [Android QA 39002975587](https://github.com/dabok407/to-do-list/actions/runs/39002975587)의 Android 작업과 [iPhone 최종 QA 39005355402](https://github.com/dabok407/to-do-list/actions/runs/39005355402)의 iOS 작업이 모두 **SUCCESS**다. 스와이프·기본 시간·직접 선택·알림 취소/복구를 실제 OS에서 검증했고 iOS의 종료 후 알림 제목/본문·OCR·권한 거부·위젯·릴리스 빌드도 통과했다. 첫 실패와 테스트 흐름 수정·취소 이력은 [1202 준비 기록](store/review/update-1.0.1-1202.json)에 남겼다. 최종 테스트 수정은 앱 코드·네이티브·자산·의존성을 바꾸지 않았다.

[서명 빌드 39001832328](https://github.com/dabok407/to-do-list/actions/runs/39001832328)가 **SUCCESS**이며 **1.0.1 (1202)** 원본 IPA를 `mobile/build/testflight/1.0.1-1202/Todoniq-1.0.1-1202.ipa`에 준비했다. 원본 SHA-256은 `7ce6d405fccb1ad75c8678243871eb895a0b25ca7a3c5b691aafb53442ba76cf`이고 manifest·아티팩트 digest·메타데이터를 대조했다. `.tools/releases/ios/1.0.1-1202/`에도 같은 원본·manifest·심볼을 보관했다. 이후 upload-only 입력은 `source_run_id=39001832328`, `version=1.0.1`, `build_number=1202`이며 아직 실행하지 않았다. GitHub 아티팩트 보관 14일이 지난 뒤에는 로컬 원본을 재검증하는 별도 업로드 경로가 필요하다.

실제 앱 기반 [로컬 미리보기](http://127.0.0.1:5175/review.html?lang=ko)는 예제 데이터와 모의 구독을 사용한다. **현재 제출한 1101은 그대로이며 1202의 Apple 업로드·TestFlight 연결·새 버전 등록·업데이트 심사는 아직 수행하지 않았다.** 실제 iPhone 설치와 StoreKit 결제 검증은 별도다.

## 이전 준비 — 1.0.1 (1201) 일정 시간 변경 수정 (2026-10-17)

기존 단발 일정의 날짜/시간을 수정하면 미룸·진행·완료 기록과 별도로 새 회차가 생기는 오류를 수정했다. 기존 회차 ID·상태·이벤트를 유지하고 예정·미룸 알림을 바뀐 시각으로 갱신한다. 반복 ‘이번만’으로 분리한 단발 일정에도 적용한다. 독립 일정과 이력이 있는 기존 중복을 임의 병합하지 않는다.

첫 수정 회귀 70개 통과 후 백그라운드 경합·삭제된 회차 방어를 추가했다. 최종 로컬 정적 분석 문제 없음·전체 테스트 **344개 통과 / 선택형 이미지 생성 1개 건너뜀**이며 신규 DB·플랫폼 예약 회귀는 26개다. 소스 `6982e24`의 [서명 빌드 38996342887](https://github.com/dabok407/to-do-list/actions/runs/38996342887)가 성공했고 **1.0.1 (1201)** IPA의 원본 체크섬·manifest·메타데이터 검증과 로컬 보관을 마쳤다. [첫 네이티브 QA 38996307891](https://github.com/dabok407/to-do-list/actions/runs/38996307891)는 Android 전체 성공, iOS는 알림 센터의 **1 Notification** 축소 표시를 펼치지 못해 마지막 화면 검증에 실패했다. 정확한 제목·본문·픽셀 검증을 유지하고 공개 Count 컨트롤을 펼치는 테스트 동작만 보완한 [iPhone 재검증 38998601067](https://github.com/dabok407/to-do-list/actions/runs/38998601067)은 **SUCCESS**다. 앱 실행·WidgetKit·종료 후 링크·앱 종료 후 알림·권한 거부·릴리스 빌드가 통과했다. 재검증 소스 `5e3eebd`는 테스트와 기록만 달라 서명한 앱 코드·자산·의존성 및 IPA 원본을 유지했다.

검증한 파일은 `mobile/build/testflight/1.0.1-1201/Todoniq-1.0.1-1201.ipa`에 있고, Flutter 빌드 정리로 지워지지 않도록 `.tools/releases/ios/1.0.1-1201/`에도 같은 해시의 원본·manifest·심볼을 보관했다. GitHub 아티팩트 보관은 14일이다. 이후 업로드에는 원본 실행 `38996342887`·버전 `1.0.1`·빌드 `1201`을 사용하며, 아티팩트 만료 뒤에는 로컬 원본의 해시·manifest·서명을 재검증하는 별도 업로드 경로가 필요하다.

현재 제출한 **1.0.0 (1101)**은 유지한다. 다음 빌드의 Apple 업로드·TestFlight 연결·업데이트 심사 제출은 아직 수행하지 않았다. 물리 iPhone 검증은 별도이며 결과는 [검증 기록](../VERIFICATION.md)과 [다음 버전 준비 기록](store/review/update-1.0.1.json)을 따른다.

## 현재 — 1101 내부 테스트 연결·재심사 접수 (2026-10-17)

1101 수출 규정 답변을 로그인된 App Store Connect 브라우저에서 저장하고 기존 **Todoniq Owner** 내부 그룹에 연결했다. 공식 API 읽기 확인은 **VALID / expired=false / usesNonExemptEncryption=false / IN_BETA_TESTING**이며 1101 빌드 ID `969eb0ab-714b-4da5-9da5-959f889688b7`가 해당 그룹에 포함된다. 본인 iPhone에서 **TestFlight → Todoniq → 업데이트**로 **1.0.0 (1101)**을 받을 수 있다. 실제 설치 완료나 실제 StoreKit 구매 검증을 확인한 것은 아니다. 외부 그룹과 기존 빌드는 유지했다.

한·영 설명·소개 이미지 28장과 공개 버전의 첨부 빌드 1101을 저장했다. 심사 메모에 수정 내역을 추가하고 새 Pro 구매 UI 자료를 앱 심사 첨부 파일로 전달했다. 상품 자체 심사용 정보는 기존 제출에서 읽기 전용이므로 유지했고 상품·그룹은 삭제하지 않았다. **2026-10-17 11:15 KST**, 기존 제출 `88f8d59f-d908-4bb0-bd89-6a9cc8fe0658`의 **1101·Pro 연간 상품·구독 그룹 3개를 재심사에 제출**하고 모두 **심사 대기 중**임을 Apple 화면에서 확인했다. 승인 후 자동 출시 설정은 유지한다. 별도 심사 대화 회신은 보내지 않았고 수정 설명은 앱 심사 메모에 포함했다.

배포·검증 소스와 원본 IPA는 아래 10월 16일 이력과 같으며 앱을 다시 빌드하거나 새 서명 키를 만들지 않았다. [재심사 확인 기록](store/review/resubmission-2026-10-17.json)을 따른다. Google 계정 작업은 사용자 재개 요청까지 보류한다.

## 이전 — Apple 반려 대응 문구 교정 (2026-10-16)

공개 심사에 제출한 1.0.0 (1001)은 소개글의 타 플랫폼 언급과 스크린샷 가격·무료 표현으로 반려됐다. 한·영 소개 자료뿐 아니라 실제 Pro·개인정보 화면도 기기의 스토어 안내로 수정했으며 기능 로직·가격·알림 예약은 바꾸지 않았다. 관련 회귀·기존 구독 테스트 12개와 정적 분석을 통과했다.

수정 소스 `a9828e4c990ebdd1878b37325b0a387cd7c01386`의 **1.0.0 (1101)**은 [Android·iOS QA 38873447757](https://github.com/dabok407/to-do-list/actions/runs/38873447757), [macOS 서명 38873490175](https://github.com/dabok407/to-do-list/actions/runs/38873490175), [원본 IPA 업로드 38877188286](https://github.com/dabok407/to-do-list/actions/runs/38877188286)가 모두 **SUCCESS**다. 원본 IPA SHA-256은 `2693f05e325fe2abf536d1741359d8a9cb001dbf05c13ba2b74a922e9ec9b3a8`이며 Apple 빌드 ID `969eb0ab-714b-4da5-9da5-959f889688b7`은 **VALID / expired=false**다. Apple의 업로드 기록은 **2026-10-16 18:05:02 KST**다.

1101의 수출 규정 답변은 아직 `null`이고 내부·외부 상태는 **MISSING_EXPORT_COMPLIANCE**다. 이전 1001과 관련 코드·의존성·서명 구성이 동일함을 확인하고 기존 답변을 재사용하려 했으나 PATCH가 **HTTP 403**으로 실패했다. 내부 그룹 연결 POST는 실행하지 않았으며 읽기 재확인에서도 Todoniq Owner에 1101은 없다. **아직 TestFlight에서 1101 업데이트를 제공하는 상태가 아니다.** 브라우저 연결 뒤 수출 규정 답변과 기존 내부 그룹 연결을 완료해야 한다. 기존 1001과 다른 빌드는 유지했다.

기존 Apple API로 업로드·읽기 확인은 가능했지만 소개글 PATCH도 HTTP 403으로 중단했다. 사용자 브라우저 연결이 가능해진 뒤 수정 이미지·문안·최종 빌드를 공개 심사 버전에 등록하고 회신·재심사해야 한다. Google 계정 작업은 사용자 요청으로 보류한다. [감사 기록](APP_STORE_REVIEW_AUDIT.md)에 점검 범위와 별도 미확인인 실제 StoreKit 구매 검증을 남긴다. 서명 아티팩트 ID는 `12034858289`, ZIP digest는 `f147c13c07711f1af8d36109f43f420338c7a66e4eb84ff3b8a67bab54ea365f`이며 IPA 해시와 구분한다.

## 이전 1001 — 기기 지역 달력 검증·업로드 (2026-10-12)

앱 소스 `d28135ec2b9b5786958e5966e49484ce0a229cad`의 **1.0.0 (1001)**은 [Android·iOS 네이티브 QA 38237880349](https://github.com/dabok407/to-do-list/actions/runs/38237880349), [macOS 서명 38238307313](https://github.com/dabok407/to-do-list/actions/runs/38238307313), [검증한 원본 IPA 업로드 38241551647](https://github.com/dabok407/to-do-list/actions/runs/38241551647)가 모두 **SUCCESS**다. 기기 지역·첫요일 설정, 앱 언어 전환, iOS WidgetKit·콜드 링크·앱 종료 후 실제 알림 화면 및 제목/본문 OCR·권한 거부, Android 종료·재부팅 알림·위젯·권한 거부를 최종 실행에서 통과했다.

한국 기기에서 영어 UI를 선택해도 일요일, 영국 기기에서 한국어 UI를 선택해도 월요일 시작이다. OS 첫요일 사용자 설정을 우선하며 홈 캘린더와 날짜 선택기에 함께 적용한다. 위치 권한·서버 조회 없이 읽고 지역 변경·앱 복귀·재실행 때 갱신한다. 이전 빠른 추가의 시간 선택 확인과 날짜 선택 후 주 보기 전환도 유지한다.

원본 IPA SHA-256은 `aa55b81759eb8c59b05d2e29517ac57d51e7942e2282d76d950a3429d3442ecb`다. 서명 아티팩트 ID는 `11742151358`, ZIP digest는 `a2d369ce0af68f172272a1329f0f006d7c83f5fdc9126aff50a145c53ec1bc1f`이며 ZIP digest를 IPA 해시로 사용하지 않는다. Apple 화면에서 빌드 ID `a23b9b0c-c7f4-48f9-9c43-de3b15125195`의 처리가 완료됐고 OS 암호화만 사용한다는 수출 규정 정보를 저장했다. **1001을 기존 Todoniq Owner 내부 그룹에 연결 완료**했으며 그룹 화면에 **테스트 중 / 90일 후 만료**가 표시된다. 본인 iPhone의 **TestFlight → Todoniq → 업데이트**에서 **1.0.0 (1001)**을 확인할 수 있다. 실제 기기의 1001 설치는 아직 확인하지 않았다. 공개 버전 1.0.0의 빌드는 **601에서 1001로 교체·저장**했고, **앱 1.0.0 (1001)·Pro 연간 상품·구독 그룹 총 3개를 최종 제출**했다. Apple의 **3개의 항목 제출됨** 확인과 각 항목의 **심사 대기 중** 상태를 확인했으며, 제출 화면의 시각은 **2026-10-12 21:23 KST**다. 승인 후 자동 출시 설정을 유지한다. 외부 베타는 기존 601을 유지하며 이전 **901은 Apple에 업로드하지 않았다**.

한국 세금 정보는 본인 사업자 증명서로 2026-10-12 제출했고 Apple 처리 대기 중이다. 유료 계약·수익 지급 계좌·미국 세금 양식 2개는 활성 상태를 확인했다. EU DSA는 인증 흐름 재시작과 동일 문서 재첨부 후 최종 제출에 성공했으며 Business 화면의 **2026-10-12 / 심사 중**을 확인했다. 앞선 오류의 단일 원인은 확정하지 않았다. 거래자 검증 결과 확인과 실제 StoreKit 결제 검증은 별도 남은 작업이다. 앱 배포 국가와 Pro 판매 국가는 각각 **전체 175개 국가 또는 지역**으로 저장했고, Pro 확인 화면에서 대한민국 연간 **₩900**을 확인했다. Pro 심사 메모의 빌드 번호는 **601에서 1001로 수정·저장**했다. 사업자번호·서류·비공개 연락처는 공개 소스에 저장하지 않는다.

한국어·영어의 중형 iPhone·13인치 iPad에 **각 7장, 총 28개 PNG 재등록과 순서 확인을 완료**했다. 첫 캘린더 이미지 4장은 최신 일요일 시작 화면이며 나머지 24장은 기존 파일과 같다. 승인된 구도·문안·장수를 유지했다.

## 이전 901 후보의 기기 지역 달력 수정 — 2026-10-12

801에서는 첫 요일이 앱 표시 언어의 locale에 연결되어 있었다. 이를 기기 지역·달력 설정과 분리했다. 한국 지역에서 영어 UI를 선택해도 일요일, 영국 지역에서 한국어 UI를 선택해도 월요일 시작이며 OS의 첫요일 사용자 설정을 우선한다. 홈 캘린더와 날짜 선택기는 같은 첫요일을 사용한다. 별도 위치 권한이나 서버 조회 없이 읽고 앱 복귀·지역 변경·재실행 때 갱신한다. 기존 일정과 반복 회차·주간 목표 계산은 변경하지 않았다. 아래 801 업로드 기록에 이 변경이 포함된 것은 아니다.

앱 소스 `7caff72ba7709d5ab756f44cf79c6191c6a68a75`의 전체 로컬 테스트 **310개 / 선택형 이미지 생성 1개 건너뜀**, 신규 지역 테스트 35개와 글자 크기 200% 화면 검증을 통과했다. [901 서명 실행 38231230058](https://github.com/dabok407/to-do-list/actions/runs/38231230058)에서 **1.0.0 (901)** 파일을 생성했지만 Apple에 업로드하지 않았다. [네이티브 QA 38225036636](https://github.com/dabok407/to-do-list/actions/runs/38225036636)은 Android 전체와 양쪽 실제 지역 응답·앱 통합을 통과했으나 iOS 알림센터 화면 검증이 완료되지 않아 전체 실패 상태다. 첫 시도는 시뮬레이터 명령 지연 후 시간 초과, 재시도는 알림센터가 열리지 않은 홈 화면에서 제목 탐색 실패다. OS의 실제 배너 표시 로그는 확인했으나 화면 OCR 조건을 대신하지 않는다. 같은 예약 알림에 대한 알림센터 제스처 재시도·진단 기록을 보완하여 다시 검증한다.

사업자 발급 완료는 사용자가 확인했다. Apple 세금·계약 입력 및 EU 증명서 확인은 로그인 세션 복구 후 이어간다. 사업자번호·증명서·비공개 연락처는 공개 소스에 저장하지 않는다.

## 이전 801 업데이트 — 2026-10-12

빠른 추가에서 **시간 먼저 → 분류 → 할 일 입력·등록** 순서로 배치하고, 시간 선택을 확인하기 전에는 화살표·키보드 완료로 등록하지 않게 했다. 캘린더는 한국어와 기본 영어(미국)에서 **일요일부터 토요일** 순서로 표시하며 날짜 선택 후 주 보기 전환을 유지한다. 시간 선택 취소·중복 확인·초안 보존·다음 등록의 시간 확인 초기화와 월/주 경계·큰 글씨를 검증했다.

앱 소스 `ecd75f46a59734fbf40249af8a2a1048839ff8db`의 **1.0.0 (801)**이 [Android·iOS 네이티브 QA 실행 38210974017](https://github.com/dabok407/to-do-list/actions/runs/38210974017), [macOS 서명 실행 38211045565](https://github.com/dabok407/to-do-list/actions/runs/38211045565), [원본 IPA 업로드 실행 38214436529](https://github.com/dabok407/to-do-list/actions/runs/38214436529)에 성공했다. 정적 분석 문제 없음, 전체 **275개 통과 / 선택형 이미지 생성 1개 건너뜀**이며 실제 앱 종료 후 알림과 위젯·권한 거부 검증도 통과했다. 검증 과정에서 발견한 테스트 알림 취소 경합은 원래 예약 시각 보존·직렬화·SQLite lease로 수정했다. 첫 후보 701은 업로드하지 않았다.

원본 IPA SHA-256은 `41ebf554f054a3681853b2a3aa08c6c4a7fbeb51b87dc734108b5f6ce6e47a52`, Apple 빌드 ID는 `93d71a68-32d9-48f8-884b-860d890dc699`다. Apple 업로드 시각은 **2026-10-12 15:50:50 KST**, 처리 상태는 **VALID / expired=false**다. 마지막 확인 시 수출 규정 정보와 내부 **Todoniq Owner** 그룹 연결은 아직 대기 중이다. API 변경 HTTP 403 후 브라우저 로그인 만료를 확인하여 사용자 재로그인을 요청했다. 업로드 성공을 iPhone 설치 가능으로 표시하지 않는다.

공개 심사 초안과 외부 베타는 기존 **601** 상태를 유지한다. 이번 801 업데이트에서 계약·세금·EU 연락처·외부 초대·정식 심사 제출은 변경하지 않았다. 아래 601 기록은 이전 배포 이력이다.

로컬 한영 캘린더 소개 이미지 8장과 ZIP 4개도 일요일 시작으로 갱신·검증했다. 승인된 iPad 구도·문안과 다른 소개 PNG 48장·아이콘 2개는 유지했다. App Store Connect의 기존 이미지 교체는 아직 수행하지 않았다.

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
