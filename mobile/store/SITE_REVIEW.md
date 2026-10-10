# 첫칸 안내 사이트 배포 전 검토

이 문서는 **로컬 작업·운영 검토용이며 GitHub Pages 배포물에 포함하지 않는다.** 공개 HTML에서는 미공개·초안 배너와 고정 가격을 제거했다. 파일 작성은 실제 게시나 법적 검토 완료를 의미하지 않는다.

## 준비된 구성

- `site/index.html`, `site/support.html`, `site/privacy.html`, `site/terms.html`: 한국어.
- `site/index-en.html`, `site/support-en.html`, `site/privacy-en.html`, `site/terms-en.html`: 동일 범위 English.
- 페이지별 언어 전환, 언어에 맞는 메뉴, 본문 건너뛰기, 키보드 포커스, 모바일 레이아웃.
- 확정 공개 이메일 `dabok407@gmail.com`. 문의 자동 발송·자동 데이터 첨부·수집 폼 없음.
- 앱 로컬 기록, Apple/Google 결제 확인, 사용자가 직접 보내는 이메일, GitHub Pages IP 로그를 구분.
- 최초 실행 7일 전체 기능 체험은 자동 결제 없음. 선택적 Pro 연간 자동 갱신이며 가격은 스토어 확인 화면 기준.
- 무료 위젯 일정 보기와 Pro의 시작·미루기 동작을 구분.
- 외부 스크립트·광고·분석·외부 폰트 없음. 공개 페이지에 운영자의 주소·전화번호·추정 법적 명칭을 넣지 않음.

## 게시 전에 확인할 항목

- [ ] 운영주체의 법적 명칭, 개인정보 문의 처리 책임자, 판매 국가에서 요구하는 공개 정보. 현재 브랜드와 확정 지원 이메일만 공개한다. 개인 주소·전화번호를 추정하거나 이전 대화의 비공개 정보를 옮기지 않는다.
- [ ] 이메일 문의 처리 문안에 대한 운영자 확인. 현재 문안은 문의 확인·답변·필요한 후속 대응 중 보관하고, 더 이상 필요하지 않은 정보는 삭제하며 법정 보관이 필요한 범위는 별도로 따른다고 안내한다. 구체적인 최대 보관 기간·삭제 주기·Gmail 휴지통 처리 및 접근·정정·삭제 요청 대응 방식을 운영 기준으로 정한다. 확정되지 않은 숫자나 대응 기한을 임의로 공개하지 않았다.
- [ ] 개인정보 안내 및 구독 이용 안내가 적용 법령과 스토어 설문에 맞는지 확인. 이 문서 작성은 법률 적합성 인증이 아니다.
- [ ] 실제 게시일에 맞춰 최종 수정 날짜 및 필요한 시행일을 확정한다. HTML의 `2026-10-10`은 문안 수정 날짜이며 게시 완료 날짜가 아니다.
- [ ] 실제 배포 앱에서 SDK·기능·무료/Pro 범위가 문안과 일치하는지 확인한다. 알림은 로컬 예약이며 운영체제·권한·예약 범위에 영향을 받는다는 안내를 유지한다.
- [ ] 실제 스토어의 연간 가격·통화·국가·갱신 조건을 확인한다. USD 0.70은 미확정 목표이며 공개 페이지에 넣지 않았다.
- [ ] GitHub Pages를 활성화하고 HTTPS URL을 읽기 전용으로 확인한다. 저장소 프로젝트 사이트의 예정 경로는 `https://dabok407.github.io/to-do-list/`이나 게시 전에는 유효한 지원 URL로 기록하지 않는다.
- [ ] GitHub Pages 배포물에는 `site/`의 HTML·CSS만 넣고 README·이 검토 문서·앱 소스·빌드 파일·인증서·키를 포함하지 않는다.
- [ ] 공개 후 8개 페이지와 CSS를 로그인 없이 열고 언어·메뉴·본문 앵커·메일 링크를 확인한다. 사용자 메일을 자동 발송하는 테스트는 하지 않는다.
- [ ] App Store Connect 및 Play Console의 지원·개인정보 URL과 앱 설정/Pro의 URL을 실제 공개 주소에 연결한다.

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
