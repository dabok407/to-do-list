# 연간 자동 갱신 구독

2026-10-09 기준. 사용자가 요청한 상품은 Pro **1년 자동 갱신**, 목표 미국 가격은 **US$0.70/년**이다. 이 금액은 확정된 스토어 상품 가격이 아니다. 스토어에서 허용하는 가격 항목과 국가별 범위를 확인한 뒤 실제 가격을 정한다. 한국의 원화 가격도 두 콘솔에서 따로 맞춘다. 앱은 가격을 하드코딩하지 않고 StoreKit `displayPrice` / Play `formattedPrice`를 표시한다.

## 구현

- Flutter: `SubscriptionService` → `com.dabok407.hangeoreum/billing` 채널.
- iOS: StoreKit 2 `Product.products`, `purchase`, 검증된 `Transaction.currentEntitlements` 및 `Transaction.updates`, `AppStore.sync`, 구독 관리 시트.
- Android: Play Billing 8.3, `annual` 기본 요금제의 P1Y 무한 갱신 가격만 선택. 스토어의 현재 구독 조회, RSA 서명 검증, 구매 승인(acknowledge), 복원과 구독 관리 링크.
- 승인 대기는 Pro 권한을 부여하지 않는다. 자동 갱신 해지는 남은 유료 기간을 즉시 없애지 않는다. 만료·환불은 다음 스토어 조회에 반영된다.
- Pro: 90일 완료 히트맵과 분류별 완료 수/비중. 기본 CRUD·반복·알림·미루기·30일 통계는 무료로 유지한다.
- 별도 운영 서버, 자체 계정, RevenueCat 등 외부 결제 서버는 추가하지 않는다. 구매는 플랫폼 계정에 귀속하며 iOS↔Android 간 공유하지 않는다.
- iOS는 기기에 남은 검증된 StoreKit 권한을 조회한다. Android의 조회 실패 시 Pro는 보수적으로 닫고 기본 기능은 유지한다. 앱이 실행되지 않은 동안 환불 등을 실시간 감지하는 자체 서버는 없다. 스토어의 로컬 캐시 지연과 기기 변조에 대한 한계가 있다. 스토어 서버 API 비밀 키를 앱에 넣지 않는다.

## 계정 생성 후 상품 등록

### Apple

1. App Store Connect → 앱 → 한걸음 → 수익화 → 구독.
2. 구독 그룹 `한걸음 Pro` 생성. 상품 ID `hangeoreum_pro_yearly`, 기간 **1년**, 자동 갱신 구독으로 등록.
3. 한국어 표시 이름·설명·심사 스크린샷 추가. 유료 앱 계약·세금·은행 정보를 완료.
4. 미국 가격 항목을 조회하고 목표 가격에 가장 가까운 허용 가격을 선택. 한국 가격도 별도 확인. 임의로 $0.70을 지원한다고 가정하지 않는다.
5. 앱과 위젯 서명 후 TestFlight 업로드. Sandbox/TestFlight에서 구매, 취소, 복원, 갱신, 해지 후 만료, 환불, 결제 유예를 검증.
6. 개인정보처리방침·지원 URL과 이용약관 링크를 실제 공개 페이지로 확정하고 앱 정보/상품 심사에 연결한다. 앱 내 안내 문구만으로 제출 준비 완료라고 판단하지 않는다.

### Google

1. Play Console → 앱 → 수익 창출 → 상품 → 구독 → 만들기.
2. 상품 ID `hangeoreum_pro_yearly` 생성.
3. 기본 요금제 ID `annual`, 유형 **자동 갱신**, 결제 기간 **매년**으로 설정. 이번 버전은 체험/할인 offer를 선택하지 않는다.
4. 국가별 가격과 판매 여부를 설정하고 상품·기본 요금제를 활성화한다. 미국 목표 가격 $0.70, 한국 원화 가격은 허용 범위와 세금을 확인해 확정한다.
5. Console의 앱 라이선스 RSA 공개 키를 빌드 환경 변수 `PLAY_BILLING_PUBLIC_KEY`에 설정한다. 이는 공개 검증 키다. 서비스 계정 비밀 키와 혼동하지 않는다. 키가 없으면 앱은 구매를 열지 않는다.
6. `flutter build appbundle --release`로 새 AAB를 생성한다. GitHub Actions로 빌드할 경우 해당 환경 변수를 별도로 전달해야 한다.
7. 내부 테스트에 업로드하고 라이선스 테스터를 등록. Play에서 설치한 앱으로 결제 성공/취소/보류·승인, 복원, 자동 갱신, 계정 변경, 해지·만료·환불·유예를 확인한다.

## 검증 범위

단위 테스트는 가격 표시, 중복 구매 방지, 승인 대기, 복원, 갱신 해지와 만료의 구분, 스토어 오류 시 권한 차단을 검증한다. 이 테스트는 실제 스토어 청구를 증명하지 않는다. 상품·개발자 계정 등록과 Sandbox/라이선스 테스트가 완료되어야 결제의 출시 검증이 끝난다. 현금 결제나 유료 계정 가입은 자동 수행하지 않는다.

브라우저 미리보기(`lib/preview.dart`)는 별도 진입점이며 샘플 구독과 샘플 데이터만 사용한다. 스토어 앱은 `lib/main.dart`로 빌드하고, 미리보기 코드로 스토어 빌드를 만들면 안 된다.

## 공식 참고

- https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions
- https://developer.apple.com/documentation/appstoreconnectapi/managing-auto-renewable-subscriptions
- https://developer.apple.com/documentation/storekit/transaction/currententitlements
- https://developer.android.com/google/play/billing/integrate
- https://support.google.com/googleplay/android-developer/answer/140504
