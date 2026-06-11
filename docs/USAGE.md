# Usage

This guide covers local installation, everyday use, status behavior, icon customization, cleanup, and development commands.

## Quick Install

Run this from the project root:

```bash
scripts/install-local.sh
```

Installed files:

```text
~/.local/bin/catdex
~/Applications/CatdexMenu.app
```

The installer adds `~/.local/bin` to `~/.zshrc` when it is missing. For an already-open terminal, reload your zsh config once:

```bash
source ~/.zshrc
```

## Start The Menu Bar App

Run:

```bash
open ~/Applications/CatdexMenu.app
```

The menu bar normally shows `🐱`. When active sessions exist, it shows the highest-priority state:

- `🐱❓`: review needed
- `🙀`: failed
- `😿`: stale
- `✍️`: responding or running tools
- `😼`: starting or running
- `👀`: waiting for the next prompt

If multiple sessions are active, Catdex appends the active count, such as `✍️ 2`.

Priority:

```text
review > failed > stale > responding > starting/running > waiting
```

Click the menu bar item to see the session list:

```text
🐱 Codex Cats
😼 RUNNING  investigate duplicate reminders  ·  backend-app @fix/reminder
🙀 FAILED   fix the UI build                 ·  admin-web
```

`done` sessions are hidden from the active list. They may still exist as session files, but they are not shown in the menu.

Each row means:

```text
state-icon STATE  task  ·  project-folder @branch
```

Session submenu actions:

- `Open Workspace`: open the working directory
- `Open Log`: open the internal Catdex log
- `Open Codex Session`: open the Codex JSONL session file from the menu submenu
- `Reveal Session JSON`: select the Catdex session JSON in Finder
- `Dismiss`: remove a finished session from the list

Menu actions:

- `Token Usage`: review token totals for the selected date range
- `Hide Floating Panel` / `Show Floating Panel`
- `Settings...`
- `Open Status Folder`
- `Dismiss Finished`
- `Refresh`
- `Quit`

`Dismiss Finished` removes `done`, `failed`, and `stale` sessions. It does not remove active sessions.

## Floating Panel

Catdex also shows a compact floating panel. It follows you across macOS Spaces and stays above normal windows.

Each session gets one cell:

```text
icon
task
```

The task name is clipped inside the cell so the panel stays small. Drag the panel by its background or cells to move it.

Click a session cell to open a context popover. The popover shows:

- `CURRENT`: state, last status message, and update time
- `LAST USER QUESTION`: the latest user prompt seen in the Codex session file
- `LAST ASSISTANT ANSWER`: the latest assistant `final_answer`; if it contains a divider, Catdex shows only the final result after the last divider
- `PATHS`: workspace, log, and Codex session paths

Popover actions:

- `Workspace`: open the working directory
- `Log`: open the Catdex wrapper log
- `Copy Context`: copy the displayed context to the clipboard
- `Reveal JSON`: select the Catdex session JSON in Finder

Use the upper-right close button, press `Esc`, or click outside the popover to dismiss it.

## Token Usage

Open the menu bar item and choose `Token Usage`.

Catdex reads `token_count` events from Codex JSONL session files under `~/.codex/sessions`, or from the custom sessions folder selected in the Token Usage menu. It also includes Codex session files recorded in Catdex session state. It totals the `last_token_usage` values in the selected date range and skips repeated events when the cumulative `total_token_usage.total_tokens` value has not changed.

The default date range is the last 30 days, including today.

Usage is calculated in the background when `CatdexMenu.app` starts, when the range changes, when a Catdex-launched session changes from active to finished, when you choose `Refresh Usage`, and once per hour while `Hourly Refresh` is enabled. Hourly refresh is on by default so Codex sessions started outside Catdex are picked up while the app is open. The normal `Refresh` menu item only refreshes session state unless it detects a session finishing.

The submenu shows:

- `Range`: selected start and end dates
- `Path`: Codex sessions folder currently being scanned
- `Sessions`: number of tracked sessions with usage in the range
- `Events`: number of counted `token_count` events
- `Total`, `Input`, `Cached`, `Output`, `Reasoning`
- `Context window`: latest model context window reported by Codex

Use:

- `Hourly Refresh`: turn the 1-hour automatic rescan on or off
- `Refresh Usage`: rescan Codex session files for the selected range
- `Set Usage Range...`: open a date-range window and choose start/end dates
- `Reset Usage Range (30 Days)`: clear the custom range and use the default 30-day range
- `Set Sessions Folder...`: choose a custom Codex sessions folder
- `Reset Sessions Folder`: use `$CODEX_HOME/sessions` when available, otherwise `~/.codex/sessions`

To find the sessions folder:

```bash
echo "${CODEX_HOME:-$HOME/.codex}/sessions"
open "${CODEX_HOME:-$HOME/.codex}/sessions"
find "${CODEX_HOME:-$HOME/.codex}/sessions" -name "*.jsonl" | head
```

Use `Set Sessions Folder...` when the folder shown by `Path` does not match where Codex writes JSONL session files.

The selected date range is saved in:

```text
~/.codex/cat-status/settings.json
```

## Custom Status Icons

Open the menu bar item and choose `Settings...`.

For each state:

- `Choose...`: select an image file
- `Emoji...`: enter an emoji or short text
- `Reset`: use the default emoji again

Supported image types:

```text
png, jpg, gif, tiff, bmp, icns, pdf, svg
```

Settings are saved here:

```text
~/.codex/cat-status/settings.json
```

Emoji settings take priority over image settings. If an image cannot be loaded, Catdex falls back to the default emoji.

## Start Codex Work

Use `catdex` instead of `codex`:

```bash
catdex
catdex "investigate duplicate reminders"
```

Catdex uses the current project folder as the initial task name. Prompts are forwarded to Codex, but they do not change the displayed task name.

To rename the displayed task, click a floating-panel cell, then click the pencil button in the context popover and enter a new name. The edited name is stored in Catdex session state and is used by the menu, floating panel, and popover.

The wrapper does this:

1. Creates a new session ID
2. Writes `~/.codex/cat-status/sessions/*.json`
3. Starts the real `codex` process
4. Finds the Codex JSONL session file
5. Infers state from Codex events
6. Updates heartbeat while running
7. Records `done` or `failed` from the Codex exit code

Catdex forwards `SIGTERM`, `SIGINT`, and `SIGHUP` to the Codex process group and records the session as `failed`, so interrupted terminal sessions do not stay stuck as active forever.

Pass Codex options as usual:

```bash
catdex --model gpt-5.4 "review the API"
```

Use a custom Codex executable:

```bash
catdex --codex-bin /path/to/codex "review the API"
```

`--task` is accepted for compatibility, but display names are edited from CatdexMenu.

## States

| State | Meaning |
| --- | --- |
| `starting` | Catdex created a session and is starting Codex or finding its session file |
| `responding` | Codex is answering, reasoning, running tools, or processing tool results |
| `waiting` | Codex finished an answer and is waiting for the next prompt |
| `review` | Permission approval, command confirmation, or user input is needed |
| `done` | Codex exited successfully |
| `failed` | Codex exited with an error, signal, or aborted turn |
| `stale` | The process disappeared or heartbeat updates stopped |
| `running` | Compatibility state for older sessions |

Catdex reads events from Codex JSONL files under:

```text
~/.codex/sessions/**/*.jsonl
```

It infers `responding`, `waiting`, and `review` from those events. `review` is detected from user input requests or tool calls that require elevated permissions.

Manual `review` representation in a session JSON:

```json
{
  "state": "review",
  "lastMessage": "Permission approval required",
  "reviewOptions": [
    "Yes, proceed",
    "No, stop",
    "Change command"
  ]
}
```

The menu shows `🐱❓ REVIEW`, and review options appear in the row tooltip.

## Notifications

Catdex sends a macOS notification when a session enters `review`:

```text
🐱❓ Codex needs review
<task name>
```

Disable notifications for one run:

```bash
CATDEX_NOTIFY=0 catdex "quiet task"
```

## Cleanup

`catdex` updates heartbeat every 15 seconds while running. The menu bar app marks active sessions as `stale` after 120 seconds without heartbeat updates, and persists that state to the session file.

`done`, `failed`, and `stale` sessions older than 24 hours are automatically pruned during menu refresh.

Clean up now:

```bash
catdex cleanup
```

This marks old active sessions as `stale`, then removes finished sessions and their logs.

## Doctor

Check the installation and runtime state:

```bash
catdex doctor
```

`catdex doctor` checks:

- status directory writability
- Codex executable discovery
- `catdex` on `PATH`
- `CatdexMenu.app` installation
- current session counts
- active sessions pointing at dead PIDs

Run Codex's own `doctor` command by passing it after `--`:

```bash
catdex -- doctor
```

`cleanup` and `doctor` are reserved Catdex top-level commands. To pass those words to Codex as prompts or subcommands, put them after `--`.

## Environment Variables

Change the status directory:

```bash
CATDEX_STATUS_DIR=/private/tmp/catdex-status catdex "test"
```

Change the default Codex executable:

```bash
CATDEX_CODEX_BIN=/path/to/codex catdex "test"
```

Disable notifications:

```bash
CATDEX_NOTIFY=0 catdex "test"
```

## Development

Run tests:

```bash
swift test
```

Build the menu bar executable:

```bash
swift build --product CatdexMenu
```

Create the app bundle:

```bash
scripts/build-app.sh
```

Bundle output:

```text
build/CatdexMenu.app
```

## Smoke Tests

Create a session without starting Codex:

```bash
catdex --dry-run "CLI smoke test"
```

Record a successful run:

```bash
CATDEX_NOTIFY=0 catdex --task "true command smoke" --codex-bin /usr/bin/true
```

Record a failed run:

```bash
CATDEX_NOTIFY=0 catdex --task "false command smoke" --codex-bin /usr/bin/false
```

Test cleanup in a temporary directory:

```bash
CATDEX_STATUS_DIR=/private/tmp/catdex-status-test catdex cleanup
```

Run the environment check:

```bash
catdex doctor
```

## Korean

<details>
<summary>한국어 사용법 보기</summary>

# 사용 방법

## 빠른 설치

프로젝트 루트에서 실행합니다.

```bash
scripts/install-local.sh
```

설치 결과:

```text
~/.local/bin/catdex
~/Applications/CatdexMenu.app
```

설치 스크립트는 `~/.local/bin`이 `PATH`에 없으면 `~/.zshrc`에 자동으로 추가합니다. 이미 열려 있는 터미널에서는 한 번만 설정을 다시 읽으면 됩니다.

```bash
source ~/.zshrc
```

## 메뉴바 앱 실행

```bash
open ~/Applications/CatdexMenu.app
```

메뉴바에는 평소 `🐱`가 보입니다. 표시할 세션이 있으면 가장 중요한 상태를 메뉴바 아이콘에 반영합니다.

- `🐱❓`: 컨펌 필요
- `🙀`: 실패
- `😿`: stale
- `✍️`: 답변/도구 실행 중
- `😼`: 시작 또는 실행 중
- `👀`: 다음 프롬프트 대기

세션이 여러 개면 `✍️ 2`처럼 active 세션 수가 붙습니다.

우선순위:

```text
review > failed > stale > responding > starting/running > waiting
```

클릭하면 세션 목록이 보입니다.

```text
🐱 Codex Cats
😼 RUNNING  배치 중복 발송 조사  ·  backend-app @fix/reminder
🙀 FAILED   UI 빌드 수정         ·  admin-web
```

`done` 세션은 활성 목록에 표시하지 않습니다.

세션 메뉴:

- `Open Workspace`: 작업 폴더 열기
- `Open Log`: Catdex 내부 로그 열기
- `Open Codex Session`: 메뉴 하위 항목에서 Codex JSONL 세션 파일 열기
- `Reveal Session JSON`: 세션 상태 파일을 Finder에서 선택
- `Dismiss`: 완료된 세션 제거

메뉴 하단:

- `Token Usage`: 선택한 기간의 토큰 사용량 확인
- `Hide Floating Panel` / `Show Floating Panel`
- `Settings...`
- `Open Status Folder`
- `Dismiss Finished`
- `Refresh`
- `Quit`

## 플로팅 패널

플로팅 패널은 macOS Spaces를 따라다니고 일반 창 위에 표시됩니다.

각 세션은 작은 칸 하나로 보입니다.

```text
아이콘
작업명
```

세션 셀을 클릭하면 컨텍스트 팝오버가 열립니다.

- `CURRENT`: 상태, 마지막 상태 메시지, 갱신 시각
- `LAST USER QUESTION`: Codex 세션 파일에서 읽은 마지막 사용자 질문
- `LAST ASSISTANT ANSWER`: 마지막 assistant `final_answer`; 구분선이 있으면 마지막 구분선 뒤의 최종 결과만 표시
- `PATHS`: workspace, log, Codex session 경로

팝오버 버튼:

- `Workspace`: 작업 폴더 열기
- `Log`: Catdex wrapper 로그 열기
- `Copy Context`: 표시 중인 컨텍스트를 클립보드에 복사
- `Reveal JSON`: Catdex 세션 JSON을 Finder에서 선택

우측 상단 닫기 버튼, `Esc`, 또는 바깥 클릭으로 닫을 수 있습니다.

작업명은 칸 안에서 잘립니다. 패널 배경이나 셀을 잡고 드래그할 수 있습니다.

## 토큰 사용량

메뉴바에서 `Token Usage`를 엽니다.

`~/.codex/sessions` 또는 Token Usage 메뉴에서 직접 선택한 sessions 폴더 아래 Codex JSONL 세션 파일의 `token_count` 이벤트를 읽습니다. Catdex 세션 상태에 기록된 Codex 세션 파일도 함께 포함합니다. 선택한 기간 안의 `last_token_usage` 값을 합산하고, 누적 `total_token_usage.total_tokens` 값이 직전 이벤트와 같으면 중복 이벤트로 보고 건너뜁니다.

기본 기간은 오늘을 포함한 최근 30일입니다.

사용량은 `CatdexMenu.app` 시작 시, 기간 변경 시, catdex로 실행한 세션이 active에서 finished로 바뀌었을 때, `Refresh Usage`를 선택했을 때, 그리고 `Hourly Refresh`가 켜져 있으면 1시간마다 백그라운드에서 계산합니다. 앱을 열어둔 동안 catdex 밖에서 실행한 Codex 세션도 잡기 위해 기본값은 켜짐입니다. 일반 `Refresh` 메뉴는 세션 상태만 새로고침하지만 세션 종료 전이가 감지되면 사용량도 갱신합니다.

하위 메뉴에서 다음을 확인할 수 있습니다.

- `Range`: 선택된 시작일과 종료일
- `Path`: 현재 스캔 중인 Codex sessions 폴더
- `Sessions`: 해당 기간에 사용량이 있는 세션 수
- `Events`: 집계된 `token_count` 이벤트 수
- `Total`, `Input`, `Cached`, `Output`, `Reasoning`
- `Context window`: Codex가 마지막으로 보고한 model context window

사용 가능한 동작:

- `Hourly Refresh`: 1시간 자동 재스캔 켜기/끄기
- `Refresh Usage`: 선택한 기간의 Codex 세션 파일 다시 스캔
- `Set Usage Range...`: 시작일/종료일을 직접 선택
- `Reset Usage Range (30 Days)`: 직접 설정한 기간을 지우고 기본 30일로 복구
- `Set Sessions Folder...`: Codex sessions 폴더 직접 선택
- `Reset Sessions Folder`: `$CODEX_HOME/sessions`가 있으면 사용하고, 없으면 `~/.codex/sessions` 사용

sessions 폴더를 찾으려면:

```bash
echo "${CODEX_HOME:-$HOME/.codex}/sessions"
open "${CODEX_HOME:-$HOME/.codex}/sessions"
find "${CODEX_HOME:-$HOME/.codex}/sessions" -name "*.jsonl" | head
```

`Path`에 표시된 폴더와 Codex가 JSONL 세션 파일을 쓰는 위치가 다르면 `Set Sessions Folder...`로 직접 선택합니다.

선택한 기간은 여기에 저장됩니다.

```text
~/.codex/cat-status/settings.json
```

## 상태 아이콘 설정

메뉴바에서 `Settings...`를 엽니다.

상태별로 다음을 설정할 수 있습니다.

- `Choose...`: 이미지 파일 선택
- `Emoji...`: 이모지나 짧은 텍스트 입력
- `Reset`: 기본 이모지로 복구

지원 이미지:

```text
png, jpg, gif, tiff, bmp, icns, pdf, svg
```

설정 파일:

```text
~/.codex/cat-status/settings.json
```

이모지 설정이 이미지 설정보다 우선합니다. 이미지 로드에 실패하면 기본 이모지로 돌아갑니다.

## Codex 작업 시작

기존 `codex` 대신 `catdex`를 사용합니다.

```bash
catdex
catdex "배치 중복 발송 조사"
```

Catdex는 현재 프로젝트 폴더명을 초기 작업명으로 사용합니다. 프롬프트는 Codex에 그대로 전달하지만 메뉴에 보이는 작업명은 바꾸지 않습니다.

표시 작업명을 바꾸려면 플로팅 패널 셀을 클릭한 뒤 컨텍스트 팝오버의 연필 버튼을 클릭하고 새 이름을 입력합니다. 수정한 이름은 Catdex 세션 상태에 저장되고 메뉴, 플로팅 패널, 팝오버에 함께 적용됩니다.

Codex 옵션은 그대로 넘길 수 있습니다.

```bash
catdex --model gpt-5.4 "API 리뷰"
```

Codex 실행 파일 경로를 직접 지정:

```bash
catdex --codex-bin /path/to/codex "API 리뷰"
```

`--task`는 호환성을 위해 허용하지만 표시명은 CatdexMenu에서 수정합니다.

## 상태

| 상태 | 의미 |
| --- | --- |
| `starting` | Catdex 세션 생성, Codex 시작 또는 세션 파일 탐색 중 |
| `responding` | Codex가 답변 생성, 추론, 도구 실행/결과 처리 중 |
| `waiting` | 답변 완료 후 다음 프롬프트 대기 |
| `review` | 권한 승인, 명령 확인, 사용자 입력 등 컨펌 필요 |
| `done` | Codex 정상 종료 |
| `failed` | 비정상 종료, 시그널, turn abort |
| `stale` | 프로세스가 사라졌거나 heartbeat가 끊김 |
| `running` | 이전 버전 세션 호환용 |

`catdex`는 Codex가 남기는 JSONL 이벤트를 읽어서 `responding`, `waiting`, `review`를 추론합니다.

## 알림

세션이 `review` 상태로 바뀌면 macOS 알림을 보냅니다.

```text
🐱❓ Codex needs review
<작업명>
```

알림 끄기:

```bash
CATDEX_NOTIFY=0 catdex "조용한 작업"
```

## 정리

`catdex`는 실행 중 15초마다 heartbeat를 갱신합니다. 메뉴바 앱은 120초 이상 갱신이 끊긴 active 세션을 `stale`로 바꿉니다.

완료/실패/stale 세션 정리:

```bash
catdex cleanup
```

설치와 상태 저장소 점검:

```bash
catdex doctor
```

## 환경 변수

상태 저장 위치 변경:

```bash
CATDEX_STATUS_DIR=/private/tmp/catdex-status catdex "테스트"
```

Codex 실행 파일 기본값 변경:

```bash
CATDEX_CODEX_BIN=/path/to/codex catdex "테스트"
```

알림 끄기:

```bash
CATDEX_NOTIFY=0 catdex "테스트"
```

## 개발 명령

```bash
swift test
swift build --product CatdexMenu
scripts/build-app.sh
```

</details>
