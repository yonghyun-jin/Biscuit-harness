# Rules

- 범용성 필터: harness 기본에는 어떤 프로젝트에서도 유효한 것만 넣는다. 특정 팀/스택
  규약(예: apps/+packages/shared)은 프로젝트의 `.claude/harness.json` opt-in 뒤로
  보낸다 — check-type-dup가 선례.
- 지식 공유 채널은 git이다: rules는 프로젝트 repo의 `.claude/rules.md`에
  커밋되어 쌓이고(clone = 상속), 승격/집계 파이프라인은 만들지 않는다. 메트릭은
  반대로 머신 로컬 전용, 절대 커밋 금지(세션당 1줄 jsonl은 커밋 노이즈+머지 충돌).
- 역할 분담 불변식: CLAUDE.md = 사람 큐레이션 정적 가이드, .claude/rules.md = 모델
  축적 동적 지식(hook이 주입 — CLAUDE.md에서 @import 금지, 이중 주입됨), AGENTS.md =
  타 도구용 표준일 뿐 에이전트 정의가 아님(Claude Code 전용 팀이면 불필요).
- 프로젝트별 "설치"는 존재하지 않는다: harness는 머신 전역이라 새 프로젝트에 필요한
  건 git init + (팀 repo면) team-init + (원하면) harness.json opt-in뿐. 이 이유로
  harness-init 스킬/스크립트를 만들었다가 당일 드랍함 — 부활시키지 말 것.
- orchestrator는 agent가 아니라 skill이어야 한다: Claude Code 서브에이전트는
  서브에이전트를 못 띄우므로 파이프라인 지휘는 메인 세션 몫.
- 진행 프레임: Phase 1 = s01–s11, Phase 2 = s12–s20 (20 mottos, TODO.md 참조).
- hook 스크립트에서 python heredoc을 쓸 때 hook payload는 BH_HOOK_INPUT env로
  넘긴다 — heredoc이 stdin을 점유하기 때문.
- 블로킹(exit 2)은 진짜 정합성 오류에만, 규약 위반은 non-blocking 피드백 지향.
- rules 격리는 repo 단위가 불변식: learn-recall은 cwd의 git toplevel 파일만
  읽으므로 이 파일은 harness 개발 세션에만 주입된다(다른 프로젝트 무주입, 검증
  완료). 사용자가 명시적으로 확인한 요구사항 — cross-project 주입을 추가하지 말 것.

- 지식 라우팅 기준(2축): ① 동작(강제 필요)이면 harness의 hook/deny로, 말(지식)이면
  ②로. ② 문장에서 프로젝트 고유명사를 지워도 참이면 글로벌(개인 취향 →
  ~/.claude/CLAUDE.md, 팀 표준 → harness, 가능하면 메커니즘화), 아니면 프로젝트
  (사람 정책 → repo CLAUDE.md, 발견된 사실 → .claude/rules.md). 승격은 미리
  판단하지 않고 반복이 신호: 같은 Episode 반복 → Rule, 같은 Rule이 여러 프로젝트에
  반복 → harness로. 미해결 빈칸: "팀 글로벌 텍스트 규칙"의 집이 아직 없음
  (setup이 ~/.claude/CLAUDE.md에 관리 섹션을 주입하는 안이 후보).

- 스코프 불변식: harness = 엔진(배포·기억 루프·계측·기본 가드레일·범용 워크플로우·
  팀 장치) + 확장 계약. 커스텀 스킬/훅은 userland(개인 ~/.claude, 프로젝트 .claude/,
  팀은 fork) — harness repo에 받지 않는다. **harness는 자기가 만든 항목만
  건드린다**: 사용자 항목 삭제/덮어쓰기 금지, 일회성 추가(deny 규칙)는 최초 설치
  1회만.

# Episodes

## 2026-07-14 — auto-update의 setup 재실행이 사용자가 지운 deny 규칙을 부활시키던 회귀
- auto-update 성공 시 setup 재실행(새 스킬 자동 링크용)을 넣자, setup이 deny 규칙을
  무조건 재추가해서 사용자가 지운 규칙이 매 업데이트마다 부활 — "자기가 만든 것만
  건드린다" 계약 위반.
- 해결: 기존 훅 basename 존재 = 기설치로 판정해 deny 추가를 최초 1회로 제한.
  dedupe도 basename 기준으로 바꿔 clone 이동 시 기존 항목을 repoint(이중 등록 제거).
- 주의: 사용자가 자기 훅을 harness 훅과 같은 파일명(예: check-types.sh)으로 만들면
  setup이 그 항목을 repoint할 수 있음 — 훅 파일명은 harness 고유하게 유지할 것.

## 2026-07-14 — dev repo에서 ./setup 실행 시 hook 이중 등록 위험
- 이 dev repo(~/Documents/Biscuit-harness)에서 setup을 실행해 hooks가 dev 경로로
  ~/.claude/settings.json에 등록됨. setup의 dedupe가 full-path 문자열 비교라, 나중에
  ~/.claude/skills/biscuit-harness로 정식 clone 후 setup을 또 돌리면 전 hook이 이중
  등록된다. basename 기준 dedupe 수정(TODO Phase 1)이 선행되어야 함.
- ~/.claude/skills/의 implement/ticket/scope-creation은 symlink가 아닌 옛 복사본이라
  setup이 스킵함 — repo 버전과 drift 중. 사용자 확인 후 지우고 재링크 필요.

## 2026-07-14 — learnings→rules 개명; hook 스크립트 파일명은 유지해야 함
- 사용자 결정으로 데이터 파일을 .claude/learnings.md → .claude/rules.md로 개명
  (업계 표준 대비 혼동 제거: CLAUDE.md/AGENTS.md/rules 역할 분담 명확화).
- 제약: learn-on-stop.sh/learn-recall.sh 스크립트 파일명은 개명 불가 — settings.json에
  절대경로로 등록되어 있어 파일명을 바꾸면 기존 설치에서 훅이 조용히 깨진다.
  setup dedupe(basename 기준) 수정 후에야 안전하게 개명 가능.

## 2026-07-14 — 학습 루프를 개인 로컬에서 repo 커밋으로 전환한 배경
- 원 설계는 "personal, never shared"(learn-on-stop 옛 주석). 사용자 결정으로 반전:
  공유 단위는 사람이 아니라 프로젝트고, repo에 쌓이면 clone하는 누구나 상속받는다.
- repo 밖 cwd는 개인 fallback 경로(~/.claude/rules/<project>.md)를 쓰고, recall은
  이 파일만 있으면 repo로의 마이그레이션 안내를 주입한다 — 이 경로를 지우면
  비-git 디렉토리 세션이 기록을 잃는다. (구 ~/.claude/learnings/ 폴더는 비어 있어
  마이그레이션 없이 제거함, 2026-07-14)
