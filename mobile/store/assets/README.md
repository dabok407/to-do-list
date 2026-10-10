# 투두닉(Todoniq) 스토어 등록 자산

앱 아이콘의 기존 도형·색상을 유지해 스토어 등록 규격으로 내보냈다. 브랜드 이름은 한국어 투두닉, 영어 Todoniq으로 표시한다.

| 파일 | 용도·규격 |
| --- | --- |
| `play-icon-512.png` | 한국어·영어 공통 Play 아이콘. 512×512, 32비트 RGBA PNG, 1,024KB 이내 |
| `app-store-icon-1024.png` | 한국어·영어 공통 Apple 아이콘. 1024×1024, 24비트 RGB PNG, 알파 채널 없음 |
| `play-feature-1024x500.png` | 한국어 Play 대표 그래픽. 실제 앱 화면 기반 1024×500 RGB PNG |
| `play-feature-1024x500-en.png` | 영어 Play 대표 그래픽. 실제 영어 앱 화면 기반 1024×500 RGB PNG |

다시 생성하려면 저장소 루트에서 PowerShell로 `./mobile/tool/generate_icons.ps1 -StoreOnly`를 실행한다. 이 옵션은 스토어 파일만 만들고 기존 앱 리소스를 변경하지 않는다.

Apple 아이콘은 일반 소개 스크린샷과 다르다. 실제 스토어 아이콘은 배포 앱의 Asset Catalog에도 올바르게 포함되어야 한다. 소개 이미지의 언어별 위치·출처·재현 명령은 [이미지 안내](../README.md)에 기록했다.

`store-contact-sheet.png`와 `store-contact-sheet-en.png`는 각각 한국어·영어 전체 검토용으로, 스토어에 올리는 개별 스크린샷이 아니다. 브랜드 변경 후 마케팅 PNG 56장과 언어별 대표 그래픽 2개를 다시 만들었다. 위 등록 자산 4개와 함께 2026-10-10 규격·채널·투명도·아이콘 크기·원본 언어·브랜드 검증을 통과했다. 결과와 파일 SHA-256은 `image-verification.json`에 기록했다.

| PNG 묶음 | 대상·검증한 파일 수 |
| --- | --- |
| `app-store-images.zip` | 한국어 중형 iPhone·대형 iPhone·iPad 21장 + 아이콘, 총 22개 |
| `play-store-images.zip` | 한국어 Android 7장 + 아이콘 + 대표 그래픽, 총 9개 |
| `app-store-images-en.zip` | 영어 중형 iPhone·대형 iPhone·iPad 21장 + 아이콘, 총 22개 |
| `play-store-images-en.zip` | 영어 Android 7장 + 아이콘 + 대표 그래픽, 총 9개 |

4개 ZIP의 파일 수와 각 내부 파일의 원본 SHA-256 대조를 통과했으며 `package-verification.json`에 결과를 기록했다. 이미지를 바꾸면 규격 검증 후 ZIP을 다시 생성·대조한다. 모든 기기의 다섯 번째 이미지에는 `05-stats-detail.png`를 사용한다. 이전 브랜드의 위젯 PNG는 현재 파일 목록에서 제거했다. 최신 네이티브 빌드로 다시 캡처·검증하기 전까지 위젯 소개 장면은 갤러리와 ZIP에서 제외한다. 위젯 기능 자체는 앱에 계속 제공된다. 스토어 최종 제출은 완료하지 않았다.
