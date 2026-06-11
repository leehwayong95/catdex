# Catdex Status

![macOS](https://img.shields.io/badge/platform-macOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

A tiny macOS menu bar app and floating panel for tracking Codex sessions.

Catdex wraps the `codex` CLI, records lightweight session state, and shows every running task as a small status icon. It stays quiet when nothing needs you, then sends a macOS notification when Codex enters `review`.

```text
menu bar:       🐱❓ 2
floating panel: ┌──────────────┐
                │ ✍️   🐱❓   👀 │
                │ api  batch ui │
                └──────────────┘
```

[한국어 README 보기](#korean)

## Why Catdex?

Running multiple Codex sessions is easy. Remembering which one needs attention is not.

Catdex gives you a small ambient dashboard for local Codex work:

- menu bar status at a glance
- always-on-top floating panel across macOS Spaces
- one compact cell per Codex session
- `review` notifications when approval or input is needed
- custom status icons with emoji or image files
- automatic stale detection when heartbeat updates stop

## Features

| Feature | Details |
| --- | --- |
| Menu bar status | Shows the highest-priority active session state |
| Floating panel | Small always-on-top grid with one cell per session |
| Review alerts | Sends a macOS notification when Codex needs confirmation |
| Custom icons | Use emoji, PNG, SVG, PDF, ICNS, JPG, GIF, TIFF, BMP |
| Stale detection | Marks active sessions stale when heartbeat updates stop |
| Session context | Click a floating-panel cell to inspect the latest prompt, final answer, paths, and actions |
| Session actions | Open workspace, log, copy context, or reveal session JSON |
| Token usage | Review token totals for a configurable date range, defaulting to the last 30 days |
| Cleanup tools | `catdex cleanup` and `catdex doctor` included |

## Requirements

- macOS 13 or later
- Swift Package Manager / Xcode command line tools
- Codex CLI available as `codex`

Catdex is currently macOS-focused. The `CatdexMenu` app uses AppKit, `NSStatusBar`, and `NSPanel`.

## Install

Clone the repo and install locally:

```bash
git clone git@github.com:jhyeona/catdex.git
cd catdex
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

Start the menu bar app:

```bash
open ~/Applications/CatdexMenu.app
```

## Quick Start

Use `catdex` where you would normally use `codex`:

```bash
catdex
catdex "review the API changes"
catdex --model gpt-5.4 "debug the reminder job"
```

Catdex uses the current project folder as the initial display name. To rename it, click the pencil button in the floating-panel context popover and enter a new name.

Use a custom Codex executable:

```bash
catdex --codex-bin /path/to/codex "check this branch"
```

Use OpenCode / oh-my-openagent instead of Codex:

```bash
catdex --backend opencode -- run "check this branch"
catdex --opencode-bin /path/to/opencode -- run --agent sisyphus "review this"
```

You can also choose the default backend in `CatdexMenu.app` Settings. `CATDEX_BACKEND` still wins for one shell or script run. The OpenCode backend defaults to `opencode`, or `CATDEX_OPENCODE_BIN` when set. Catdex reads OpenCode activity from `CATDEX_OPENCODE_DB`, `OPENCODE_DATA_DIR/opencode.db`, or `~/.local/share/opencode/opencode.db` when available. This is status tracking only; token usage totals still come from Codex JSONL session files.

## Statuses

| State | Meaning |
| --- | --- |
| `starting` | Catdex created a session and is starting Codex or finding its session file |
| `responding` | Codex is thinking, answering, running tools, or processing tool results |
| `waiting` | Codex finished an answer and is waiting for the next prompt |
| `review` | Codex needs confirmation, approval, or user input |
| `done` | Codex exited successfully |
| `failed` | Codex exited with an error, signal, or aborted turn |
| `stale` | Heartbeat was lost or the process disappeared |
| `running` | Compatibility state for older sessions |

Menu bar priority:

```text
review > failed > stale > responding > starting/running > waiting
```

`done` sessions are hidden from the active list so the UI stays focused on work that may still matter.

## Floating Panel

Catdex shows a compact floating panel that follows you across Spaces. Each session gets its own small cell:

```text
icon
task
```

Task names are clipped inside each cell, keeping the whole panel small. Drag the panel by its background or cells to move it.

Click a session cell to open a context popover. It shows the current state, last user question, last assistant final answer, workspace/log paths, and action buttons:

- `Workspace`: open the working directory
- `Log`: open the Catdex wrapper log
- `Copy Context`: copy the displayed context to the clipboard
- `Reveal JSON`: select the Catdex session JSON in Finder

From the menu bar, use:

- `Hide Floating Panel`
- `Show Floating Panel`

## Token Usage

Open the menu bar item and choose `Token Usage`.

Catdex totals `token_count` events from Codex session files under `~/.codex/sessions`. The default range is the last 30 days, including today. The submenu shows total, input, cached input, output, reasoning tokens, session count, and event count.

Usage is calculated in the background when the menu app starts, when the date range changes, when a Catdex-launched session finishes, when you choose `Refresh Usage`, and once per hour while `Hourly Refresh` is enabled. Hourly refresh is on by default so sessions started outside Catdex are still picked up while the app is open. Catdex also includes Codex session files recorded in Catdex session state, so non-standard Codex homes can still be counted for Catdex-launched sessions.

Use:

- `Hourly Refresh`: turn the 1-hour automatic rescan on or off
- `Refresh Usage`: rescan Codex session files for the selected range
- `Set Usage Range...`: choose custom start and end dates
- `Reset Usage Range (30 Days)`: return to the default 30-day range
- `Set Sessions Folder...`: choose a custom Codex sessions folder
- `Reset Sessions Folder`: use `$CODEX_HOME/sessions` when available, otherwise `~/.codex/sessions`

To find the Codex sessions folder from a terminal:

```bash
echo "${CODEX_HOME:-$HOME/.codex}/sessions"
open "${CODEX_HOME:-$HOME/.codex}/sessions"
find "${CODEX_HOME:-$HOME/.codex}/sessions" -name "*.jsonl" | head
```

The Token Usage submenu also shows `Path`, which is the folder Catdex is currently scanning.

## Custom Icons

Open the menu bar item and choose `Settings...`.

For every state you can set:

- `Choose...`: select an image file
- `Emoji...`: type an emoji or short text
- `Reset`: go back to the default emoji

Supported image types:

```text
png, jpg, gif, tiff, bmp, icns, pdf, svg
```

Settings are stored here:

```text
~/.codex/cat-status/settings.json
```

Emoji settings take priority over image settings. If an image cannot be loaded, Catdex falls back to the default emoji.

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

## How It Works

```text
catdex command
   │
   ├─ creates ~/.codex/cat-status/sessions/<id>.json
   ├─ starts the real codex process
   ├─ watches ~/.codex/sessions/**/*.jsonl
   ├─ infers responding / waiting / review
   ├─ writes heartbeat updates
   └─ records done or failed when Codex exits

CatdexMenu.app
   │
   ├─ reads session JSON files
   ├─ reads Codex JSONL for panel context
   ├─ prunes old finished sessions
   ├─ marks lost-heartbeat sessions as stale
   └─ renders the menu bar item and floating panel
```

Status files and logs live under:

```text
~/.codex/cat-status/
├── sessions/
├── logs/
└── settings.json
```

Catdex tracks sessions that were started through `catdex`. Existing `codex` sessions started directly are not imported.

## Maintenance

Clean up finished sessions:

```bash
catdex cleanup
```

Check your setup:

```bash
catdex doctor
```

Override the status directory:

```bash
CATDEX_STATUS_DIR=/private/tmp/catdex-status catdex "test"
```

## Development

Run tests:

```bash
swift test
```

Build the menu bar app:

```bash
swift build --product CatdexMenu
```

Create the `.app` bundle:

```bash
scripts/build-app.sh
```

Create a local install:

```bash
scripts/install-local.sh
```

## FAQ

**Does Catdex work on Windows or Linux?**

Not currently. The menu bar app and floating panel are macOS AppKit code. The session format and parts of the CLI wrapper could be ported later.

**Does Catdex upload anything?**

No. Catdex writes local JSON and log files under `~/.codex/cat-status/`.

**Can I use Catdex with existing Codex sessions?**

Only sessions started through `catdex` are tracked. Catdex does not import already-running direct `codex` sessions.

**Why did a session become `stale`?**

It was active, but heartbeat updates stopped for long enough that Catdex could no longer trust it was alive.

**Why do I only get notifications for `review`?**

Completion notifications are noisy. Catdex only notifies when Codex likely needs a human decision.

## Roadmap Ideas

- optional screenshot/GIF in README
- persistent floating panel position
- packaged app release
- import or inspect existing Codex sessions
- non-macOS CLI-only mode

## License

MIT. See [LICENSE](LICENSE).

## Korean

<details>
<summary>한국어 README 보기</summary>

# Catdex Status

Codex 작업 여러 개를 돌릴 때 “지금 뭐가 답변 중이고, 뭐가 내 확인을 기다리는지” 놓치지 않도록 만든 작은 macOS 도구입니다.

`catdex`는 `codex` CLI를 감싸서 실행하고, 작업 상태를 `~/.codex/cat-status/` 아래에 기록합니다. `CatdexMenu` 앱은 그 상태 파일을 읽어 메뉴바와 플로팅 패널에 보여줍니다.

```text
메뉴바:        🐱❓ 2
플로팅 패널:  ┌──────────────┐
              │ ✍️   🐱❓   👀 │
              │ api  batch ui │
              └──────────────┘
```

## 왜 만들었나요?

Codex 세션을 여러 개 켜두면 작업 자체보다 “어느 세션이 내 확인을 기다리는지”를 놓치기 쉽습니다.

Catdex는 로컬 Codex 작업을 위한 작은 상태판입니다.

- 메뉴바에서 상태를 빠르게 확인
- 모든 Space 위에 떠 있는 작은 플로팅 패널
- 세션별 상태 아이콘과 작업명 표시
- 플로팅 패널에서 마지막 질문/최종 답변 컨텍스트 확인
- 기본 30일 또는 직접 설정한 기간의 토큰 사용량 확인
- `review` 상태에서 macOS 알림
- 상태별 이모지/이미지 아이콘 커스터마이징
- heartbeat가 끊기면 `stale`로 표시

## 설치

```bash
git clone git@github.com:jhyeona/catdex.git
cd catdex
scripts/install-local.sh
```

설치 위치:

```text
~/.local/bin/catdex
~/Applications/CatdexMenu.app
```

설치 스크립트는 `~/.local/bin`이 `PATH`에 없으면 `~/.zshrc`에 자동으로 추가합니다. 이미 열려 있는 터미널에서는 한 번만 설정을 다시 읽으면 됩니다.

```bash
source ~/.zshrc
```

메뉴바 앱 실행:

```bash
open ~/Applications/CatdexMenu.app
```

## 사용

기존 `codex` 대신 `catdex`를 사용합니다.

```bash
catdex
catdex "API 변경사항 리뷰"
catdex --model gpt-5.4 "리마인더 배치 디버깅"
```

Catdex는 현재 프로젝트 폴더명을 초기 표시명으로 사용합니다. 이름을 바꾸려면 플로팅 패널 컨텍스트 팝오버의 연필 버튼을 클릭하고 새 이름을 입력합니다.

## 상태

| 상태 | 의미 |
| --- | --- |
| `starting` | Catdex 세션 생성, Codex 시작 또는 세션 파일 탐색 중 |
| `responding` | Codex가 답변 생성, 추론, 도구 실행/결과 처리 중 |
| `waiting` | 답변 완료 후 다음 프롬프트 대기 |
| `review` | 권한 승인, 명령 확인, 사용자 입력 등 컨펌 필요 |
| `done` | Codex 정상 종료 |
| `failed` | 비정상 종료, 시그널, turn abort |
| `stale` | heartbeat가 끊겼거나 프로세스가 사라짐 |
| `running` | 이전 버전 세션 호환용 상태 |

우선순위:

```text
review > failed > stale > responding > starting/running > waiting
```

`done` 세션은 활성 목록에서 숨겨서, 아직 신경 써야 하는 작업만 보이게 합니다.

## 플로팅 패널

플로팅 패널은 각 세션을 작은 칸 하나로 보여줍니다.

```text
아이콘
작업명
```

작업명은 칸 너비 안에서 잘립니다. 패널 배경이나 셀을 잡고 드래그할 수 있습니다.

세션 셀을 클릭하면 컨텍스트 팝오버가 열립니다. 현재 상태, 마지막 사용자 질문, 마지막 assistant 최종 답변, workspace/log 경로와 액션 버튼을 확인할 수 있습니다.

- `Workspace`: 작업 폴더 열기
- `Log`: Catdex wrapper 로그 열기
- `Copy Context`: 현재 팝오버 내용을 클립보드에 복사
- `Reveal JSON`: Catdex 세션 JSON을 Finder에서 선택

## 토큰 사용량

메뉴바 고양이 아이콘을 클릭한 뒤 `Token Usage`를 엽니다.

`~/.codex/sessions` 아래 Codex 세션 파일의 `token_count` 이벤트를 합산합니다. 기본 기간은 오늘을 포함한 최근 30일입니다. 하위 메뉴에서 total, input, cached input, output, reasoning 토큰과 세션 수, 이벤트 수를 확인할 수 있습니다.

사용량은 메뉴 앱 시작 시, 기간 변경 시, catdex로 실행한 세션이 끝났을 때, `Refresh Usage`를 선택했을 때, 그리고 `Hourly Refresh`가 켜져 있으면 1시간마다 백그라운드에서 다시 계산합니다. 앱을 열어둔 동안 catdex 밖에서 실행한 Codex 세션도 잡기 위해 기본값은 켜짐입니다. Catdex 세션 상태에 기록된 Codex 세션 파일도 함께 합산하므로, 표준 경로가 아닌 Codex home을 쓰더라도 catdex로 실행한 세션은 집계될 수 있습니다.

- `Hourly Refresh`: 1시간 자동 재스캔 켜기/끄기
- `Refresh Usage`: 선택한 기간의 Codex 세션 파일 다시 스캔
- `Set Usage Range...`: 시작일과 종료일 직접 설정
- `Reset Usage Range (30 Days)`: 기본 30일 범위로 복구
- `Set Sessions Folder...`: Codex sessions 폴더 직접 선택
- `Reset Sessions Folder`: `$CODEX_HOME/sessions`가 있으면 사용하고, 없으면 `~/.codex/sessions` 사용

터미널에서 Codex sessions 폴더를 찾으려면:

```bash
echo "${CODEX_HOME:-$HOME/.codex}/sessions"
open "${CODEX_HOME:-$HOME/.codex}/sessions"
find "${CODEX_HOME:-$HOME/.codex}/sessions" -name "*.jsonl" | head
```

Token Usage 하위 메뉴의 `Path`는 Catdex가 현재 스캔 중인 폴더입니다.

## 아이콘 설정

메뉴바 고양이 아이콘을 클릭한 뒤 `Settings...`를 엽니다.

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

이모지 설정이 이미지 설정보다 우선합니다.

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

## 정리와 점검

완료/실패/stale 세션 정리:

```bash
catdex cleanup
```

설치와 상태 저장소 점검:

```bash
catdex doctor
```

## 개발

```bash
swift test
swift build --product CatdexMenu
scripts/build-app.sh
scripts/install-local.sh
```

자세한 사용법은 [docs/USAGE.md](docs/USAGE.md)를 참고하세요.

</details>
