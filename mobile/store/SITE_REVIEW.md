# 투두닉 / Todoniq 안내 사이트 배포 및 운영 검토

이 문서는 **로컬 작업·운영 검토용이며 GitHub Pages 배포물에 포함하지 않는다.** 확정된 새 브랜드는 **투두닉 / Todoniq**이며 슬로건은 **나만의 할 일, 투두닉 / Your tasks. Your way.**다. 새 사이트 게시와 한국어·영어 실제 브라우저 확인을 완료했다. 운영 정책 확인, 실제 구독 상품·서명 IPA·TestFlight·스토어 심사 제출은 아직 완료하지 않았다.

## 배포·연결 확인

- 2026-10-10 [GitHub Pages 배포 실행 38030189739](https://github.com/dabok407/to-do-list/actions/runs/38030189739) 성공. 배포 소스 커밋 `b2ff571`, 이전 첫칸 브랜드 기준 이력이다.
- 새 브랜드 [GitHub Pages 배포 38040488335](https://github.com/dabok407/to-do-list/actions/runs/38040488335), 소스 `2567bb4` 성공. 공개 주소 https://dabok407.github.io/to-do-list/ 의 한국어·영어 index/support/privacy/terms 8개 HTML이 HTTP 200이고 각 언어의 새 브랜드를 포함한다. CUA에서 실제 한영 지원 페이지의 브랜드·슬로건·로컬 저장과 별도 통신 안내를 확인했다.
- 기존 앱 설정·Pro의 `StorePolicyLinks`를 공개 URL에 연결했으며 관련 테스트 5개가 통과했다. URL은 브랜드 변경 후에도 유지한다. iOS 이용약관 링크는 Apple 표준 EULA다.
- App Store Connect에는 이전 첫칸 이름·한국어/영어 문안·지원/개인정보 URL과 이미지 28장이 저장되어 있다. 로그인 세션 만료로 새 투두닉 / Todoniq 이름·문안·이미지는 콘솔에 반영하지 못했다. 같은 Apple ID `6821236391`을 사용한다. Play Console 입력은 계정 준비 후 진행한다.
- 새 투두닉 / Todoniq 소스 `b5f8935`의 [모바일 검증 실행 38039981394](https://github.com/dabok407/to-do-list/actions/runs/38039981394)는 Android·iOS 모두 전체 성공했다. iOS release는 no-codesign이며 배포 서명·실기기 설치·스토어 구매 검증과 구분한다. 이전 실행 `38036673085` / 소스 `36f3464`는 첫칸 브랜드 이력이다. 새 사이트의 게시·공개 응답·한영 지원 첫 화면 확인은 위 배포 기록과 같이 완료했다.

## 준비된 구성

- `site/index.html`, `site/support.html`, `site/privacy.html`, `site/terms.html`: 한국어.
- `site/index-en.html`, `site/support-en.html`, `site/privacy-en.html`, `site/terms-en.html`: 동일 범위 English.
- 페이지별 언어 전환, 언어에 맞는 메뉴, 본문 건너뛰기, 키보드 포커스, 모바일 레이아웃.
- 한국어 투두닉 / 영어 Todoniq, 확정 슬로건, 지원 첫 화면의 기기 내 저장·개발자 서버 미전송·회원가입/광고 추적 없음 안내.
- 확정 공개 이메일 `dabok407@gmail.com`. 문의 자동 발송·자동 데이터 첨부·수집 폼 없음.
- 앱 로컬 기록, Apple/Google 결제 확인, 사용자가 직접 보내는 이메일, GitHub Pages IP 로그를 구분.
- 최초 실행 7일 전체 기능 체험은 자동 결제 없음. 선택적 Pro 연간 자동 갱신이며 가격은 스토어 확인 화면 기준.
- 무료 위젯 일정 보기와 Pro의 시작·미루기 동작을 구분.
- 외부 스크립트·광고·분석·외부 폰트 없음. 공개 페이지에 운영자의 주소·전화번호·추정 법적 명칭을 넣지 않음.

## 새 브랜드 로컬 확인

- 2026-10-10 HTML 8개의 문서 언어·브랜드·슬로건, 로컬 링크 대상과 본문 앵커, ID 중복을 확인했다. 외부 스크립트·문의 폼·iframe을 추가하지 않았다.
- 스토어 제목은 한국어 14자·영어 26자, 프로모션은 한국어 107자·영어 156자, Play 짧은 설명은 한국어 49자·영어 77자로 각 제한 이내다. 키워드는 한국어 67바이트·영어 75바이트다.
- 연결된 브라우저 목록이 없어 이 작업에서 실제 320px·390px·768px 렌더링과 200% 글자 크기 동작은 확인하지 못했다. 게시·화면 검토 결과로 대체하지 않는다.

## 남은 운영·제출 확인

- [ ] 운영주체의 법적 명칭, 개인정보 문의 처리 책임자, 판매 국가에서 요구하는 공개 정보. 현재 브랜드와 확정 지원 이메일만 공개한다. 개인 주소·전화번호를 추정하거나 이전 대화의 비공개 정보를 옮기지 않는다.
- [ ] 이메일 문의 처리 문안에 대한 운영자 확인. 현재 문안은 문의 확인·답변·필요한 후속 대응 중 보관하고, 더 이상 필요하지 않은 정보는 삭제하며 법정 보관이 필요한 범위는 별도로 따른다고 안내한다. 구체적인 최대 보관 기간·삭제 주기·Gmail 휴지통 처리 및 접근·정정·삭제 요청 대응 방식을 운영 기준으로 정한다. 확정되지 않은 숫자나 대응 기한을 임의로 공개하지 않았다.
- [ ] 개인정보 안내 및 구독 이용 안내가 적용 법령과 스토어 설문에 맞는지 확인. 이 문서 작성은 법률 적합성 인증이 아니다.
- [ ] 정책 시행일이 별도로 필요한지 확정한다. HTML의 최종 수정 날짜는 `2026-10-10`이며 실제 최초 게시도 같은 날 완료했다.
- [ ] 실제 배포 앱에서 SDK·기능·무료/Pro 범위가 문안과 일치하는지 확인한다. 알림은 로컬 예약이며 운영체제·권한·예약 범위에 영향을 받는다는 안내를 유지한다.
- [ ] 실제 스토어의 연간 가격·통화·국가·갱신 조건을 확인한다. USD 0.70은 미확정 목표이며 공개 페이지에 넣지 않았다.
- [x] 이전 첫칸 GitHub Pages 활성화·배포 및 8개 HTML·CSS의 공개 HTTPS 응답 확인.
- [x] 새 투두닉 / Todoniq 사이트 배포, 8개 HTML HTTP 200 및 한영 지원 첫 화면 브랜드·슬로건 확인.
- [x] 배포 workflow는 `site/`의 HTML·CSS만 게시한다. README·이 검토 문서·앱 소스·빌드 파일·인증서·키는 배포 폴더 밖에 둔다.
- [x] 기존 앱 설정·Pro 및 App Store Connect 한국어·영어 지원 URL·전용 개인정보 URL·소개 내 링크 연결.
- [ ] Apple 재로그인 후 기존 앱의 새 브랜드 이름·문안·이미지 반영. Bundle ID·SKU·상품 ID·공개 URL은 유지.
- [ ] 공개 페이지의 모든 언어·메뉴·본문 앵커·메일 링크를 최종 점검한다. 사용자 메일을 자동 발송하는 테스트는 하지 않는다.
- [ ] Play Console 안내 URL 입력.

## 로컬 확인

저장소의 로컬 개발 서버가 정적 파일을 제공하면 `/mobile/store/site/` 경로에서 확인할 수 있다. 환경별 서버의 경로 제한이 있을 수 있으므로 실제 HTTP 200과 CSS 응답을 확인한다. 별도 테스트 서버를 쓰면 `site/` 폴더만 루트로 제공한다. 이것은 로컬 페이지 확인용이며 앱 운영 서버를 추가하는 일이 아니다.

레이아웃은 한국어/English 각각 320px·390px·768px, 200% 글자 크기, 키보드 포커스, 페이지 언어 전환을 확인한다. 공개 사이트의 접근성 및 정책 적합성 전체 인증으로 표현하지 않는다.

## 확인한 공식 자료

- [GitHub Pages와 사이트 접속 IP 기록](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages#data-collection)
- [GitHub 개인정보 보호정책](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
- [Apple 구독 취소](https://support.apple.com/ko-kr/118428)
- [Apple 환불 요청](https://support.apple.com/ko-kr/118223)
- [Google Play 정기 결제 관리](https://support.google.com/googleplay/answer/7018481?hl=ko)
- [Apple 표준 EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)
