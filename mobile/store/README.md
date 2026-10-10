# 투두닉(Todoniq) 스토어 소개 이미지

로컬 검토 페이지: `http://127.0.0.1:5174/store-images.html`. **이미지 언어**에서 한국어 또는 English를 선택하고 **iPhone 중형·iPhone 대형·iPad·Android** 탭에서 큰 보기와 개별 다운로드를 확인한다. 영어 대형 iPhone은 `http://127.0.0.1:5174/store-images.html?lang=en&device=iphone-large`로 바로 열 수 있다.

한국어·영어 각각 실제 앱 화면 8종을 세 기기 크기로 캡처했다. 스토어 소개에는 각 화면 규격당 7장을 사용한다. 투두닉(Todoniq)으로 이름을 변경하면서 원본 48장과 소개 이미지 **언어별 28장, 총 56장**을 모두 다시 제작했다. 2026-10-10에 소개 PNG 56장·등록 자산 4개의 규격·언어·브랜드 검증과 ZIP 4개의 파일 수·SHA-256 대조를 통과했다. 이전 이미지의 SHA-256 보존 검사는 이번 브랜드 변경에 적용하지 않는다. 사용자 검토와 스토어 업로드는 별도 단계다.

| 한국어 위치 | 영어 위치 | 용도·수량 | 해상도 |
| --- | --- | --- | --- |
| `captures/iphone/` | `captures/en/iphone/` | 실제 iPhone 크기 Flutter 원본 8장씩 | 1179×2556 |
| `captures/ipad/` | `captures/en/ipad/` | 실제 iPad 크기 Flutter 원본 8장씩 | 2064×2752 |
| `captures/android/` | `captures/en/android/` | 실제 Android 크기 Flutter 원본 8장씩 | 1080×1920 |
| `screenshots/iphone/` | `screenshots/en/iphone/` | App Store 중형 iPhone 소개 이미지 7장씩 | 1179×2556 |
| `screenshots/iphone-large/` | `screenshots/en/iphone-large/` | App Store 대형 iPhone 소개 이미지 7장씩 | 1320×2868 |
| `screenshots/ipad/` | `screenshots/en/ipad/` | App Store iPad 소개 이미지 7장씩 | 2064×2752 |
| `screenshots/android/` | `screenshots/en/android/` | Google Play 소개 이미지 7장씩 | 1080×1920 |
| `assets/play-feature-1024x500.png` | `assets/play-feature-1024x500-en.png` | 언어별 Play 대표 그래픽 | 1024×500 |

양쪽 언어가 함께 사용하는 Apple 1024×1024 아이콘과 Play 512×512 아이콘은 [등록 자산 안내](assets/README.md)에 정리했다. 검증 대상 등록 자산은 언어별 대표 그래픽 2개와 아이콘 2개, 총 4개다.

## 업로드 순서

| 순서·파일 이름 | 한국어 소개 문구 | English copy |
| --- | --- | --- |
| `01-calendar.png` | 나만의 할 일, 투두닉 | Your tasks. Your way. |
| `02-overdue.png` | 끝내지 못한 일도 잊지 않게 | Keep unfinished tasks in sight |
| `03-start.png` | 어렵다면, 5분만 시작해요 | Start small. Try five minutes. |
| `04-repeat.png` | 반복 일정은 내 생활에 맞게 | Routines that fit your life |
| `05-stats-detail.png` | 나의 실행 패턴을 알아봐요 | Find your execution patterns |
| `06-stats.png` | 내가 해낸 일을 돌아보기 | See what you have accomplished |
| `07-privacy.png` | 내 일정은 내 기기에 | Your plans stay on your device |

이 순서는 두 언어와 네 가지 화면 규격 모두 같다. 첫 장부터 회원가입 없이 일정이 기기에 저장된다는 점을 소개하며, 7번째 이미지에서 할 일·메모를 개발자 서버로 전송하지 않는다는 점을 설명한다. 다섯 번째 소개 이미지는 **30일 통계 상세 화면**이다. 원본 `08-pro.png`는 구매 화면 검토용이며 위 7장 묶음에는 포함하지 않는다.

Apple 공식 표에서 1179×2556은 Dynamic Island 중형, 1320×2868은 Dynamic Island 대형, 2064×2752는 13인치 iPad 허용 규격이다. 중형 iPhone 필수 안내와 대형 이미지가 없을 때의 조건을 함께 충족하도록 두 iPhone 크기를 준비했다. PNG 파일 검사와 실제 App Store Connect 슬롯·업로드 확인은 구분한다. [Apple 스크린샷 규격](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

알림·미루기·실행 보조·통계에는 Pro 구독 필요를 표시한다. 첫 7일은 앱 내부 전체 기능 체험으로, 체험만으로 결제나 구독이 시작되지 않는다. 확정되지 않은 가격·다운로드 순위·의료 효과는 넣지 않는다. 앱의 위젯 보기는 무료이고 시작·미루기 동작은 Pro 기능이며, 소개 이미지의 위젯 장면 제외는 앱 기능 삭제를 뜻하지 않는다.

## 화면 출처

화면은 투두닉의 프로덕션 `HangeoreumApp`을 실제 Flutter 위젯 테스트에서 Pretendard 폰트와 생활 일정 샘플로 렌더했다. 내부 클래스와 패키지 이름은 변경하지 않았다. 같은 컴포넌트의 한국어·영어 표시를 캡처했으며 디자인 모형으로 UI를 새로 그리지 않았다. 영어 캡처의 일정은 영어 생활 일정 샘플이며 사용자가 저장한 기록을 번역한 것이 아니다. 기기별 크기·플랫폼을 적용했지만 네이티브 OS 상태바가 있는 기기 캡처로 표시하지 않는다. 대형 iPhone 소개는 중형 iPhone 원본을 비율 유지로 배치한 별도 1320×2868 캔버스이며 별도 네이티브 기기 캡처가 아니다. 일정과 통계는 가상 샘플이며 개인정보는 포함하지 않는다. `captures/{device}/source.json`과 `captures/en/{device}/source.json`에 언어·브랜드·원본·샘플 통계를 기록했다.

이전 브랜드의 네이티브 위젯 캡처 6개는 혼동을 막기 위해 현재 파일 목록에서 제거했다. 현재 기본 내보내기는 iPhone·iPad·Android 모두 실제 통계 상세 화면을 대신 사용한다. 위젯 기능은 앱에서 계속 구현되어 있으며 기능 검증과 소개용 캡처는 별도다. 과거 WidgetKit 실행 `37928717116`과 Android 네이티브 결과는 기존 QA 기록으로만 남긴다. 이 PC에서는 HAXM 지원 오류로 Android 에뮬레이터를 시작하지 못했으므로 다른 플랫폼 위젯을 Android 캡처로 대체하지 않는다.

화면 픽셀은 비율을 유지해 배치하고 앱 밖에 해당 언어의 소개 문구를 넣는다. 최종 소개 이미지는 알파 채널 없는 RGB PNG로 내보내고 검증한다. 이미지 제작·검증은 서명 IPA, 실제 결제 테스트나 스토어 업로드 완료와 별개다.

## 재현

`mobile/` 폴더에서 한국어·영어 실제 앱 컴포넌트 원본 캡처:

```powershell
../.tools/flutter/bin/flutter.bat test test/store_capture_test.dart --dart-define=STORE_CAPTURE=true --dart-define=STORE_CAPTURE_LANGUAGE=ko --update-goldens
../.tools/flutter/bin/flutter.bat test test/store_capture_test.dart --dart-define=STORE_CAPTURE=true --dart-define=STORE_CAPTURE_LANGUAGE=en --update-goldens
```

저장소 루트에서 Sharp가 설치된 Node 환경으로 최종 이미지 내보내기:

```powershell
node mobile/tool/compose_store_images.cjs --language=ko
node mobile/tool/compose_store_images.cjs --language=en
node mobile/tool/verify_store_images.cjs
./mobile/tool/package_store_images.ps1
```

기존 이미지를 보존하고 대형 iPhone만 추가 생성하려면 합성 명령에 `--device=iphone-large`를 넣어 한국어·영어 각각 실행한다. 원본은 해당 언어의 `captures/iphone/`에서 읽고 새 파일은 `screenshots/iphone-large/`에 저장한다.

Sharp가 기본 모듈 경로에 없다면 `HANGEOREUM_SHARP_MODULE`에 설치된 Sharp 모듈의 절대 경로를 지정한다. `--partial`은 제작 중 존재하는 원본만 내보내는 미리보기 옵션으로, 최종 제작·검증에는 사용하지 않는다. 검증 명령은 두 언어의 소개 이미지 56장과 등록 자산 4개의 규격·채널·투명도·아이콘 크기를 검사하고 `assets/image-verification.json`을 기록한다. 패키징 명령은 이 기록과 일치하는 소개 이미지·등록 자산만 묶고 ZIP 내부 파일을 SHA-256으로 대조해 `assets/package-verification.json`을 기록한다. 이미지를 다시 만들거나 수정하면 두 검증을 다시 실행한다.

`--native-widgets`는 향후 현재 투두닉 빌드와 대상 언어로 네이티브 위젯을 다시 캡처하고, 이미지 검증·패키징 목록을 위젯 파일에 맞춰 변경한 경우에만 사용하는 선택 옵션이다. 현재 최종 검증과 ZIP은 통계 상세 화면을 기준으로 한다. 이 옵션 없이 실행하면 모든 기기의 5번 파일은 `05-stats-detail.png`다. 과거 위젯 파일이 존재한다는 이유만으로 옵션을 켜지 않는다.

## ZIP과 최종 제출

한국어 묶음은 `assets/app-store-images.zip`, `assets/play-store-images.zip`, 영어 묶음은 `assets/app-store-images-en.zip`, `assets/play-store-images-en.zip`으로 구분한다. 언어별 Apple ZIP은 중형 iPhone·대형 iPhone·iPad 각 7장과 아이콘, 총 22개 파일을 포함한다. 언어별 Play ZIP은 Android 7장·아이콘·해당 언어 대표 그래픽, 총 9개 파일을 포함한다. 현재 4개 묶음의 수량과 원본 SHA-256 대조를 통과했다. 과거 `05-widget.png`는 최신 묶음에 포함하지 않는다.

ZIP을 풀고 해당 언어와 기기의 파일을 번호순으로 올린다. App Store Connect의 한국어·English (U.S.) 현지화와 Play의 언어별 등록정보에 맞춰 선택하며, 실제 콘솔 슬롯과 사용자 검토를 거쳐 제출한다. 현재 자료는 로컬 검토용이며 스토어에 제출하지 않았다.
