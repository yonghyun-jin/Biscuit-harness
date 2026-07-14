# Biscuit Harness — 설계 문서

> 2026-07-14 대화 정리. 이 폴더에서 새 세션으로 harness repo를 구축할 것.

## 목표

개인/팀용 Claude Code harness 시스템을 **중앙 repo 하나**로 만들고, 여러 프로젝트/팀원에게 배포한다.
- 중앙 repo에 업데이트 → push → 팀원들은 **자동으로** 최신 버전 수신
- 새 프로젝트 시작 시 최소한의 셋업만
- gstack (https://github.com/garrytan/gstack) 의 배포 메커니즘을 그대로 차용

## 배포 메커니즘 (핵심 결정: npm ❌, git-in-place ✅)

npm + sync 스크립트 방식은 폐기. 이유: Claude Code는 node_modules를 안 보므로 sync 복사가 필요해서 복잡함.

**gstack 방식 채택:** Claude Code가 스캔하는 폴더에 git repo를 통째로 clone.

```
git clone → ~/.claude/skills/biscuit-harness   ← 설치 위치 = 스캔 위치 (sync 불필요)
./setup   → agents는 symlink, hooks는 settings.json에 경로 등록 (연결만)
git pull  → 전부 자동 최신화 (복사본이 없으므로 drift 없음)
```

### Claude Code가 각 요소를 찾는 위치

| 요소 | 위치 | 처리 방법 |
|---|---|---|
| Skills | `~/.claude/skills/` | clone하면 바로 인식 ✅ |
| Agents | `~/.claude/agents/` | setup이 **symlink** 생성 |
| Hooks | `~/.claude/settings.json`에 등록 필요 | setup이 repo 안 스크립트 **경로**를 등록 |

symlink + 경로 등록이므로 git pull 하면 모든 게 자동 최신. `.claude/` 안의 harness 파일 직접 수정 금지 (중앙 repo에서만 수정).

## 자동 업데이트 메커니즘 (2겹 부트스트랩)

### 1겹: setup이 auto-update 훅을 심음
```json
// 팀원의 ~/.claude/settings.json — ./setup이 등록
"SessionStart": [{ "command": "~/.claude/skills/biscuit-harness/hooks/auto-update.sh" }]
```
- 매 세션 시작 시 git pull (1시간에 1번 throttle, 네트워크 실패 시 조용히 스킵)
- 훅 스크립트 본체는 repo 안에 있으므로 훅 로직 개선도 git pull로 전파됨

### 2겹: setup 안 한 팀원은 프로젝트 repo가 잡음
```json
// 프로젝트 repo의 .claude/settings.json — git에 커밋됨 (team-init이 생성)
"SessionStart": [{ "command": "sh -c '[ -d ~/.claude/skills/biscuit-harness ] || echo \"⚠️ harness 미설치: git clone ... && ./setup\"'" }]
```
- 프로젝트 clone에 딸려오므로 로컬 셋업 0으로 작동 → 부트스트랩 문제 해결
- `required` = 차단 / `optional` = 권유

## Repo 구조 (만들 것)

```
biscuit-harness/  (GitHub: seanjin/biscuit-harness)
├── README.md            ← 설치 안내 (아래 "설치 프롬프트" 포함)
├── setup                ← 설치 스크립트:
│                           1. agents/* → ~/.claude/agents/ symlink
│                           2. ~/.claude/settings.json에 hooks 등록
│                           3. auto-update SessionStart 훅 등록
│                           4. CLAUDE.md에 harness 섹션 추가 안내
├── skills/              ← 커스텀 스킬 (SKILL.md 형식)
├── agents/              ← 에이전트 정의 .md
├── hooks/
│   ├── auto-update.sh   ← git pull (1h throttle, silent fail)
│   ├── check-types.sh   ← PostToolUse: Edit/Write 후 변경 파일 패키지만 tsc
│   └── check-type-dup.sh ← PostToolUse: apps/에 새 도메인 interface/type 선언 감지
│                            → exit 2 + stderr로 Claude에 피드백 (packages/shared 재사용 유도)
└── bin/
    └── team-init        ← 프로젝트 repo에 마커(.claude/settings.json 체크 훅) 커밋
                            required|optional 모드
```

## 설치 플로우 (gstack README 스타일)

### Step 1: 개인 설치 — Claude Code에 붙여넣는 프롬프트
```
Install biscuit-harness: run git clone --single-branch --depth 1
https://github.com/seanjin/biscuit-harness.git ~/.claude/skills/biscuit-harness
&& cd ~/.claude/skills/biscuit-harness && ./setup
then add a "biscuit-harness" section to CLAUDE.md listing the available skills.
```

### Step 2: 팀 모드 — 프로젝트 repo에서
```
(cd ~/.claude/skills/biscuit-harness && ./setup --team) \
&& ~/.claude/skills/biscuit-harness/bin/team-init required \
&& git add .claude/ CLAUDE.md \
&& git commit -m "require biscuit-harness for AI-assisted work"
```

## 배포 흐름 요약

| 역할 | 하는 일 |
|---|---|
| maintainer (Sean) | harness repo에 커밋 & push — 그게 배포의 전부 |
| 팀원 | 최초 clone + ./setup 1회 → 이후 전자동 (세션 시작 시 auto-pull) |
| 프로젝트 repo | 마커만 커밋 (harness 코드 없음, "no vendored files") |

## 배경: 기존 harness 감사 결과 (20 principles 스코어카드)

우선순위별 부족한 부분 — harness에 넣을 기능의 근거:
1. 🔴 **Hooks 없음 (s04)** — Edit/Write 후 자동 tsc/lint 검사 훅 필요
2. 🔴 **권한 경계 없음 (s03)** — `skipDangerousModePermissionPrompt: true` + deny 규칙 0개. `rm -rf`, force-push 등 deny 규칙 필요
3. 🟡 **티켓 흐름 비일관 (s05)** — "작업 → Linear, 참고문서 → docs/, ad-hoc ticket .md 금지" 규칙을 글로벌 CLAUDE.md에
4. 🟡 **메모리 파편화 (s09)** — repo 경로 이동 시 메모리 고아 발생. (main-itin-ai-app은 2026-07-14 수동 마이그레이션 완료)
5. 🟢 스케줄/자율 팀 (s14, s17) — 나중에

### 사용자 선호 (harness 규칙에 반영할 것)
- 인라인 interface/type 선언 금지 → packages/shared 등 기존 타입 재사용 우선 (hook으로 강제)
- /ship 시 CHANGELOG/VERSION 스킵
- CI/CD 워크플로우 수정 전 git log 확인 필수

## CLAUDE.md / agents 계층 (참고)

```
~/.claude/CLAUDE.md          ← 글로벌 (개인 규칙, 모든 프로젝트) — 자동 로드
<repo>/CLAUDE.md             ← 프로젝트 (팀 공유) — 자동 로드, 충돌 시 우선
~/.claude/agents/            ← 개인 에이전트 — 자동 발견
<repo>/.claude/agents/       ← 프로젝트 에이전트 — 자동 발견, 이름 겹치면 우선
~/.claude/settings.json      ← 글로벌 hooks/권한
<repo>/.claude/settings.json ← 프로젝트 hooks/권한 (글로벌 위에 덮어씀)
```

판단 기준: "다른 프로젝트에서도 유효한가?" Yes → 글로벌/harness, No → 프로젝트.

## 다음 단계 (새 세션에서 할 일)

1. gstack repo를 실제로 clone/분석해서 setup 스크립트 패턴 참고
2. 위 repo 구조대로 biscuit-harness 뼈대 생성
3. setup 스크립트 작성 (symlink + hook 등록 + auto-update)
4. hooks 3종 작성 (auto-update, check-types, check-type-dup)
5. bin/team-init 작성 (required/optional)
6. README 작성 (gstack 스타일 설치 프롬프트 포함)
7. GitHub에 push → 본인 머신에서 실제 설치 테스트
