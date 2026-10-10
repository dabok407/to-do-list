# 첫칸 지원 사이트

한국어와 English로 읽을 수 있는 정적 안내 페이지다. 앱의 일정·메모는 기기에 저장하며, 이 사이트는 앱 데이터 저장이나 알림 처리를 위한 서버가 아니다.

공개 사이트는 [https://dabok407.github.io/to-do-list/](https://dabok407.github.io/to-do-list/)이며 고객 문의 이메일은 `dabok407@gmail.com`이다. 메일은 사용자가 메일 앱에서 직접 보내며, 페이지에는 문의 수집 폼·외부 JavaScript·분석 도구·외부 폰트가 없다.

| 한국어 | English | 내용 |
| --- | --- | --- |
| `index.html` / `support.html` | `index-en.html` / `support-en.html` | 문의·기능·알림·구매 복원·해지 도움말 |
| `privacy.html` | `privacy-en.html` | 로컬 저장·스토어 결제·이메일 문의·웹사이트 접속 정보 |
| `terms.html` | `terms-en.html` | 7일 앱 내부 체험·무료/Pro·연간 자동 갱신·스토어 약관 |

각 페이지 상단의 한국어/English 링크는 같은 안내의 다른 언어로 이동한다. 별도 계정·쿠키·언어 저장 코드 없이 동작하며, 선택한 언어로 사이트 메뉴를 계속 이용할 수 있다. `style.css`는 공통 스타일이다.

GitHub Pages는 정적 호스팅만 담당한다. 앱 데이터와 별도로, 사이트 방문 IP 주소가 GitHub의 보안 정책에 따라 기록될 수 있으며 개인정보 페이지에 이 내용을 안내한다.

2026-10-10 GitHub Pages 배포 후 8개 HTML과 CSS의 HTTP 200 응답을 확인했다. 앱 설정·Pro의 공개 링크 연결과 링크 컴포넌트 테스트 5개도 통과했다. 언어에 따라 해당 지원·개인정보 안내를 열고 iOS의 이용약관은 Apple 표준 EULA를 연다. 배포 기록, 콘솔 연결 현황과 남은 운영 검토는 사이트 폴더 밖의 [`SITE_REVIEW.md`](SITE_REVIEW.md)에서 관리한다. 실제 구독 상품·서명 IPA·TestFlight·스토어 심사 제출은 아직 완료하지 않았다.

배포 아티팩트에는 HTML과 CSS만 포함하고, 이 README와 사이트 폴더 밖의 검토 문서는 포함하지 않는다.
