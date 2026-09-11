# Usage for Windows

> **On hold (2026-08-27):** Windows packaging, distribution, and Explorer
> release validation are deferred until the maintainers resume Windows work.
> The sources and tests are preserved and continue to build and pass tests.

Windows 작업표시줄에서 Claude, Codex, Grok의 대표 구독 사용량만 확인하는 경량 앱입니다.

```text
[Claude logo] 82  [OpenAI logo] 63  [X logo] 91
```

숫자는 각 공급자의 대표 사용 창에 남아 있는 비율입니다. 공급자 이름, 그래프, 네트워크·CPU 상태는 작업표시줄에 표시하지 않습니다.

## 동작

- 기본 위치: 기본 모니터 작업표시줄의 알림 영역 바로 왼쪽
- 표시: Claude·Codex·Grok 실제 로고와 남은 비율 3칸
- 갱신: 시작 직후, 5분마다, 또는 좌클릭/`Refresh now`
- 메뉴: 우클릭 시 `Refresh now`, `Quit Usage`만 제공
- 장애 격리: 한 공급자가 실패해도 다른 공급자와 이전 정상값은 유지
- 안전 폴백: Explorer 작업표시줄에 부착할 수 없으면 같은 스트립을 작업표시줄 바로 위에 표시
- Explorer 상태 확인: 10초마다 부착 상태만 확인하며 고빈도 애니메이션은 사용하지 않음

`TrafficMonitor`는 작업표시줄에 정보를 놓는 방식만 참고했습니다. 네트워크 속도, CPU·메모리, 그래프, 스킨, 플러그인, 상세 통계 기능은 Usage의 범위가 아닙니다.

## 디자인 계약

- Windows 시스템 폰트인 `Segoe UI Semibold 9pt`를 사용합니다. 이는 Usage macOS의 11pt macOS 상태 텍스트와 같은 시각 밀도를 목표로 한 플랫폼 대응값입니다.
- Claude `#D97757`, OpenAI/GPT `#19C37D`, X는 밝은 테마에서 검정·어두운 테마에서 흰색입니다.
- 기본 논리 크기는 162×30px이며 디스플레이 DPI에 맞춰 확대됩니다.
- 앱 자체 트레이 아이콘은 공급자 상표를 사용하지 않고 세 개의 색상 막대로 구성합니다.

## 데이터와 개인정보

Usage는 별도 로그인이나 API 키 입력 화면을 만들지 않습니다. 설치된 CLI의 기존 로그인을 사용합니다.

- Claude: `%USERPROFILE%\.claude\.credentials.json`의 OAuth access token을 요청 시 메모리에서만 읽어 Anthropic 사용량 엔드포인트를 조회합니다. 파일을 수정하거나 토큰을 기록하지 않습니다. `CLAUDE_CONFIG_DIR`도 지원합니다.
- Codex: `codex -s read-only -a untrusted app-server`를 실행하고 `account/rateLimits/read`만 호출합니다.
- Grok: `grok agent stdio`를 실행하고 읽기 전용 `x.ai/billing` RPC만 호출합니다.
- 브라우저 쿠키, Windows Credential Manager, 별도 Keychain, 원시 계정 응답 저장은 사용하지 않습니다.

## 사전 조건

- Windows 10 또는 Windows 11
- .NET Framework 4.8
- 로그인된 `claude`, `codex`, `grok` CLI가 `PATH`에 존재
- 빌드 시 Visual Studio Build Tools의 .NET Framework 4.8 개발자 팩과 MSBuild

## 빌드와 테스트

Visual Studio Developer PowerShell에서 실행합니다.

```powershell
cd Windows
.\build.ps1 -Configuration Release
```

빌드 스크립트는 전체 솔루션을 다시 빌드하고 7개 코어 파서 테스트를 실행합니다. 앱 출력은 다음 위치입니다.

```text
Windows\Usage.Windows\bin\Release\Usage.Windows.exe
```

배포 ZIP은 다음 명령으로 만듭니다.

```powershell
.\package.ps1 -Configuration Release -Version 0.1.0
```

```text
Windows\artifacts\Usage-Windows-0.1.0.zip
```

## Windows 실기 검증 게이트

macOS의 교차 컴파일과 코어 테스트만으로 Explorer 통합을 증명할 수는 없습니다. 배포 전 실제 Windows 10/11에서 다음을 한 번씩 확인합니다.

- 100%, 150%, 200% DPI에서 세 칸이 잘리지 않는지
- 밝은/어두운 시스템 테마에서 X 로고와 숫자가 보이는지
- 일반·자동 숨김 작업표시줄에서 알림 영역과 겹치지 않는지
- 각 CLI가 로그인/로그아웃된 경우 해당 칸만 값/`—`로 바뀌는지
- 좌클릭 새로고침과 우클릭 종료가 정확한 Usage 프로세스에만 작동하는지
- 작업표시줄 부착 실패 시 우측 하단 폴백 스트립이 보이는지

## 의도적으로 제외한 기능

- CPU·메모리·네트워크 속도
- 사용량 그래프와 장기 기록
- 스킨·위젯 편집·플러그인
- 임계치 알림과 자동 실행
- 다중 계정과 공급자 추가
- 별도 설정·대시보드 창

이 항목들은 현재 MVP에 포함하지 않습니다. 핵심은 세 에이전트의 사용량을 계속 보이게 하는 것입니다.
