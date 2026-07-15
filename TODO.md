# TODO — 20 mottos 대비 gap 및 로드맵

기준: 20개 harness 원칙(s01–s20). Claude Code 플랫폼이 이미 구현하는 것과
이 repo(배포형 harness)가 채워야 할 것을 구분한다.

**진행 원칙**
- Phase 1 = s01–s11, Phase 2 = s12–s20.
- 스코프: harness = **엔진 + 확장 계약** (배포, 기억 루프, 계측, 기본 가드레일,
  범용 워크플로우, 팀 장치). 스택 스캐폴딩·팀 고유 규약 기본값·커스텀 호스팅은
  userland (개인 ~/.claude, 프로젝트 .claude/, 팀은 fork). **harness는 자기가
  만든 항목만 건드린다** — 상세는 README Scope 섹션.
- different project에서 범용으로 쓰이는 것만 harness에 넣는다.
- Rules(구 learnings)는 프로젝트 repo에 커밋되어 쌓인다 (`.claude/rules.md`, clone = 상속).
- 메트릭은 로컬 전용, 커밋 금지 (jsonl 커밋 노이즈/충돌 방지). 새 스킬·학습 루프의
  실사용 측정은 유지한다.

## s01–s20 매핑

| 원칙 | 커버 주체 | 상태 |
|---|---|---|
| s01 one loop & Bash | Claude Code | ✅ 플랫폼 |
| s02 tool = one handler | Claude Code (tools/MCP) | ✅ 플랫폼 |
| s03 boundaries first | harness deny 규칙 5개 | 🟡 좁음 — allowlist/경계 확대 필요 |
| s04 hook around the loop | harness hooks 6종 | 🟡 작동하나 마찰(check-types)·범용성(check-type-dup) 문제 |
| s05 plan before starting | implement 스킬 (plan-first todos) | 🟡 앞단만 — review→ship 뒷단 없음 |
| s06 subagents, clean context | — | 🔴 **agents/ 정의 0개** (README만) |
| s07 knowledge on demand | skills + 2-tier learn-recall | ✅ |
| s08 make room (compaction) | Claude Code auto-compact | ✅ 플랫폼 (recall 인덱스가 보조) |
| s09 remember/forget | 학습 루프 (extraction/selection) | 🟡 consolidation이 프롬프트 재량뿐 |
| s10 runtime prompt assembly | skills/hooks 주입 구조 | ✅ |
| s11 errors → retry | hook exit-2 피드백 | 🟡 auto-update는 실패를 삼킴 (신호 0) |
| s12 file-backed task graph | implement의 plan/ fallback | 🟡 규약 미표준화 → Phase 2 |
| s13 background ops | Claude Code | ✅ 플랫폼 |
| s14 fire on schedule | — | 🔴 없음 → Phase 2 |
| s15 teammates + mailboxes | Claude Code (Agent/SendMessage) | 🔴 harness 규약 없음 → Phase 2 |
| s16 shared comm rules | — | 🔴 없음 → Phase 2 |
| s17 self-organizing board | — | 🔴 없음 → Phase 2 |
| s18 worktree isolation | Claude Code | 🔴 harness 규약 없음 → Phase 2 |
| s19 plug in via MCP | 스킬이 Linear MCP 사용 (graceful degrade) | ✅ |
| s20 one complete harness | 이 repo (배포: clone+symlink+auto-pull) | 🟡 harness-init 부재, staleness 무신호 |

## Phase 1 — s01~s11

### 진행 중 (이번 배치)

- [x] **학습 루프 repo 재타게팅** (s09) — learn-on-stop/learn-recall이
      `<repo>/.claude/rules.md`(커밋됨)에 쓰고 읽음. repo 밖은 legacy 로컬 경로
      fallback + 마이그레이션 유도. 메트릭에 source(repo/legacy) 기록.
- [x] **auto-update 침묵 실패 제거** (s11) — stamp를 fetch 후로, behind인데 ff 불가면
      1줄 경고. upstream 없음/detached HEAD 가드. 업데이트 성공 시 setup 재실행
      (새 스킬/훅 자동 링크).
- [ ] **check-type-dup opt-in화** (s04) — `.claude/harness.json`의
      `"check-type-dup": true`일 때만 활성. TS 모노레포 전용 규약을 기본에서 제거.
- [ ] **metrics 동적화 + 학습 루프 측정** (s09) — HARNESS_SKILLS 하드코딩을
      skills/ 스캔으로.
- [x] ~~bin/harness-init + /harness-init 스킬~~ — **드랍.** harness는 머신 전역
      설치라 프로젝트별 설치가 없고, rules.md는 훅이 자가 생성, CLAUDE.md는
      내장 /init, 팀 마커는 team-init, 스택 스캐폴딩은 프로젝트 특수 영역(범용성
      원칙 위배). README "New project" 섹션으로 대체 (git init + 선택적 team-init
      + 선택적 harness.json opt-in).

### 다음 배치

- [x] **agents/ 실제 정의** (s06) — researcher / spec / builder / verifier /
      reviewer(3-lens 패널용, 6항목 체크리스트 내장) + `/orchestrate` 스킬이
      research→spec→**human approval**→build→verify→review→보고 파이프라인을 지휘.
      orchestrator는 agent가 아닌 skill (서브에이전트는 서브에이전트를 못 띄움).
      learn-on-stop에 결정 기록 지침(왜/제약/주의점 — wiki로 재사용) 추가.
- [ ] **skills/ship** (s05 뒷단) — PR 생성·CHANGELOG/VERSION 스킵 등. implement가
      merge 앞에서 dead-end인 문제 해결. dev loop 완결: scope→ticket→implement→ship→learn.
- [ ] **check-types 마찰 완화** (s04, s11) — `--incremental`, 편집 파일 에러만 exit 2
      (패키지 전체 에러는 정보성). 현재 harness 최대 지연·자기 friction 오염원.
- [ ] **권한 경계 확대** (s03) — 자주 쓰는 read-only 명령 allowlist + deny 확장.
      "경계 먼저, 그 안에서 자유" — 프롬프트 피로도 함께 감소.
- [ ] **학습 consolidation 기계화** (s09) — Rules 20개/150줄 초과 시 recall이
      통합 세션을 요구하는 경고 주입; `# Rules` 헤딩 파싱 관대화.
- [ ] **check-type-dup 심각도 하향** (s04) — 규약 위반은 non-blocking 피드백
      (블록은 진짜 정합성 오류만).
- [ ] **비-TS 스택 가드레일** (s04 확장) — harness-init의 스택 선택과 연동
      (Python: ruff/mypy 등).

### 배포 인프라 (상시 — s20 하이진, Phase 무관 소형 수정)

- [x] **setup 훅 dedupe 수정** — basename 기준으로 변경: clone 이동/재설치 시
      기존 항목을 새 경로로 repoint (이중 등록 없음). 동시에 deny 규칙을
      최초 설치 1회만 추가하도록 수정 — auto-update의 setup 재실행이 사용자가
      지운 deny 규칙을 부활시키던 회귀 해결 ("자기가 만든 항목만 건드린다" 계약).
- [ ] **team-init 버전 핀** — 마커에 최소 커밋 기록, 설치본 HEAD와 비교 경고.

## Phase 2 — s12~s20

- [ ] **plan/ 작업 그래프 규약 표준화** (s12) — implement의 plan/ fallback을
      "파일 기반 태스크, 순서, 상태" 규약으로 명문화 (멀티에이전트 협업의 기반).
- [ ] **스케줄 실행 규약** (s14) — 반복 작업(예: 주간 rules 파일 정리)을
      schedule/cron으로 돌리는 표준 워크플로우.
- [ ] **멀티에이전트 팀 규약** (s15–s18) — mailbox 메시지 포맷(s16),
      태스크 보드 self-claim(s17), worktree 격리 규약(s18)을 스킬/문서로.
- [ ] **harness-stats --export** (s20) — opt-in 요약 집계. 메트릭 원본은 계속 로컬,
      커밋 금지 유지.
