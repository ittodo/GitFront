# GitFront 기능 목록

이 문서는 현재 소스 트리의 실제 동작을 기준으로 작성한다. 릴리스별 포함 변경은 `release-notes.md`에서 별도로 관리한다.

상태 표기:

- **지원**: 데스크톱 UI에서 해당 작업을 끝까지 수행할 수 있다.
- **부분 지원**: 조회 또는 일부 흐름만 제공하며 아래에 제한 사항을 함께 적는다.
- **제외**: 현재 버전에 포함하지 않는다.

## 기능 현황 요약

| 영역 | 상태 | 현재 범위 |
| --- | --- | --- |
| 여러 저장소 | 지원 | 새 저장소 생성, 로컬 열기, 고급 URL 복제, 앱 내부 탭, 최근 저장소와 열린 탭 복원 |
| 변경 파일과 diff | 지원 | staged/unstaged/untracked/conflict, 파일·hunk stage/unstage, unified/side-by-side diff |
| 커밋과 로그 | 지원 | 커밋 작성, 200개 단위 로그, 그래프, 상세 diff, ref 배지와 커밋 작업 메뉴 |
| 로컬 브랜치 | 지원 | 생성, 전환, 이름 변경, 삭제, merge, rebase |
| 원격 브랜치 | 부분 지원 | remote별 계층 목록, tracking branch 생성·checkout과 커밋 배지를 지원하지만 원격 삭제는 없음 |
| 원격 작업 | 지원 | remote 관리, clone, fetch, pull, push, 선택적 upstream 설정, force-with-lease |
| Git 설정 | 지원 | 저장소·전역 config 조회/편집, 상속 출처, 고급 key/value와 민감 값 보호 |
| Sparse checkout | 부분 지원 | cone-mode 디렉터리 설정·변경·비활성화 지원, non-cone pattern은 제외 |
| Submodule | 지원 | 지연 목록, 초기화, 기록/원격 업데이트, 동기화, 새 탭 열기, 추가와 안전 제거 |
| Subtree | 지원 | 공식 Git 소스에서 고정한 내장 helper, 로컬 연결 등록, add/pull/push/split, squash 선택, 진행 로그와 취소 |
| 고급 이력 작업 | 지원 | merge, rebase, interactive rebase, cherry-pick, revert, reset |
| stash | 지원 | 생성, 목록, diff, apply, pop, drop |
| 충돌 해결 | 지원 | 텍스트 3-way 편집, ours/theirs/both, 직접 편집, 외부 도구 |
| 다국어 | 부분 지원 | 시스템 언어·한국어·영어 선택을 제공하지만 일부 고급 메뉴와 진단 문구는 영어로 남아 있음 |
| 업데이트와 배포 | 지원 | Windows VeloPack 설치·포터블 패키지, GitHub Releases 업데이트 |

## 저장소와 화면

- **지원** 로컬 폴더에서 Git 저장소를 찾고 연다. 하위 폴더를 선택해도 상위 저장소를 탐색한다.
- **지원** 일반 working-tree 저장소를 새 폴더 또는 기존 폴더에 초기화한다.
- **지원** 초기 브랜치, README, 내장 `.gitignore` 템플릿과 선택적 `origin`을 지정한다. 첫 커밋·fetch·push는 자동 실행하지 않는다.
- **지원** Git URL과 대상 폴더를 입력해 저장소를 복제한다. remote 이름, branch/tag, depth, single branch, no-tags, submodule, blobless와 cone sparse 옵션을 제공한다.
- **지원** 여러 저장소를 상단 탭으로 열고 드래그로 순서를 바꾸며 저장소별 선택 파일, diff, 로그, busy/error 상태를 분리한다. 바뀐 탭 순서는 설정에 즉시 저장한다.
- **지원** 왼쪽 브랜치·원격 브랜치·stash, 가운데 변경 또는 로그, 오른쪽 diff·커밋 상세의 3패널 구성을 사용한다.
- **지원** 왼쪽과 오른쪽 패널 폭을 드래그로 조정하고 오른쪽 상세 패널을 접거나 다시 연다.
- **지원** 열린 탭, 활성 탭, 최근 저장소(최대 12개), 패널 크기와 표시 여부를 재시작 후 복원한다.
- **제외** bare 저장소는 데스크톱 작업 화면에서 열지 않는다.

## 변경 파일

- **지원** 충돌, staged, unstaged를 그룹으로 나누고 untracked 파일을 별도 상태로 식별한다.
- **지원** 추가, 수정, 삭제, 이름 변경, 타입 변경, 충돌 상태를 파일 배지로 표시한다.
- **지원** 이름이 변경된 파일에는 이전 경로를 함께 표시한다.
- **지원** 파일 단위 stage와 unstage를 제공한다.
- **지원** 여러 변경 행을 체크해 한 번에 stage/unstage하며, 경로는 NUL 구분 pathspec 입력으로 전달해 파일 수와 특수문자에 안전하다.
- **지원** untracked 파일을 내용 없이 index에 표시하는 intent-to-add를 선택 파일 묶음에 적용한다.
- **지원** diff hunk 단위 stage와 unstage를 제공한다.
- **지원** Unified diff의 추가·삭제 줄을 골라 같은 hunk 안에서도 선택 줄만 stage/unstage하거나 확인 후 폐기한다.
- **지원** hunk를 적용하기 전에 diff fingerprint를 다시 확인한다. 파일이 바뀌었으면 오래된 선택을 거부하고 새로고침을 요구한다.
- **지원** tracked 파일 변경 폐기는 확인 후 Git restore로 수행한다.
- **지원** untracked 파일 폐기는 영구 삭제 대신 Windows 휴지통으로 이동한다.
- **부분 지원** 자동 hunk 재분할과 patch 원문 직접 편집은 아직 제공하지 않는다.

## Diff 보기

- **지원** 작업 트리와 index diff, 선택한 커밋의 diff, 선택 커밋에서 현재 `HEAD` 방향의 비교 diff를 표시한다.
- **지원** 기본 unified 모드와 파일별 side-by-side 모드를 전환한다.
- **지원** 이전·새 줄 번호와 추가·삭제 배경색을 표시한다.
- **지원** Dart, Rust, JavaScript/TypeScript, Python, JSON, YAML, TOML 등 자주 쓰는 확장자에 가벼운 구문 강조를 적용한다.
- **지원** binary, 비 UTF-8, 5MB 초과 파일은 전체 본문 대신 요약을 표시하고 외부 열기를 제공한다.
- **지원** 비정상적으로 긴 한 줄은 UI 정지를 막기 위해 표시 길이를 제한한다.

## 커밋 작성

- **지원** staged 변경을 커밋 메시지와 함께 커밋하고 저장소별 작성 중 메시지를 설정 파일에 자동 보존한다.
- **지원** 시스템 Git을 사용하므로 사용자의 hook, GPG 서명, Git 설정을 그대로 따른다.
- **지원** amend, sign-off, allow-empty, 커밋별 서명 사용/해제, 작성자와 작성 시각을 지정한다.
- **지원** `commit.template`을 작성창에 불러오고 `commit.cleanup` 및 설정된 서명 정책은 Git에 맡긴다.
- **지원** 성공 또는 충돌 상태 변화 후 저장소를 다시 읽어 변경 목록과 로그를 갱신한다.
- **지원** 최근 로그의 대상을 골라 autosquash용 fixup/squash 커밋을 만든다.

## 커밋 로그와 ref

- **지원** topological + time 순서로 커밋을 읽고 그래프 lane, 작성자, 시간, 제목, 축약 SHA를 표시한다.
- **지원** 처음 200개를 읽고 스크롤 끝에서 200개씩 추가한다. 커서 캐시가 이전 offset을 다시 순회하지 않고 페이지 사이 그래프 lane을 이어 간다.
- **지원** 커밋 선택 시 전체 메시지, 부모, 변경 파일과 커밋 diff를 오른쪽 패널에 표시한다.
- **지원** 동일 커밋을 가리키는 `HEAD`, 로컬 브랜치, 원격 브랜치, 태그를 종류별 아이콘·색상·텍스트 배지로 표시한다.
- **지원** ref는 `HEAD → 로컬 브랜치 → 원격 브랜치 → 태그` 순서로 정렬한다.
- **지원** 배지가 많으면 `+N`으로 접고 tooltip과 접근성 설명에서 전체 목록을 제공한다.
- **지원** detached HEAD와 annotated tag의 peeled 대상 커밋을 올바르게 표시한다.

## 커밋 우클릭 메뉴

커밋 행의 우클릭, `…` 버튼 또는 `Shift+F10`에서 같은 메뉴를 연다.

- **지원** 전체 커밋 SHA 복사
- **지원** 선택 커밋 → 현재 `HEAD` 비교
- **지원** 선택 커밋에서 로컬 브랜치 생성, 필요하면 즉시 전환
- **지원** annotated 또는 lightweight 태그 생성
- **지원** detached HEAD checkout
- **지원** 한 개 커밋 cherry-pick
- **지원** 우클릭한 커밋을 현재 HEAD에 메모리로 미리 적용해 실제 변화가 없으면 cherry-pick을 비활성화하고, 충돌 예상 여부를 표시한다. 과거에 포함됐더라도 이후 revert된 변경은 다시 적용할 수 있다.
- **지원** 한 개 커밋 revert (`--no-edit`)
- **지원** 현재 브랜치를 선택 커밋 기준으로 rebase
- **지원** 현재 로컬 브랜치를 선택 커밋으로 soft, mixed, hard reset
- **지원** merge commit을 cherry-pick 또는 revert할 때 부모 SHA를 보여주고 mainline parent를 선택한다.
- **지원** merge/rebase/cherry-pick/revert가 진행 중이면 복사와 비교를 제외한 변경 메뉴를 잠근다.
- **제외** 여러 커밋을 한 번에 선택하는 cherry-pick과 revert는 제공하지 않는다.

## 로컬 브랜치

- **지원** 새 로컬 브랜치를 만들고 바로 checkout한다.
- **지원** 로컬 브랜치 전환, 이름 변경, 삭제를 제공한다.
- **지원** 선택한 로컬 브랜치를 현재 브랜치에 merge한다.
- **지원** 현재 브랜치를 선택한 브랜치 또는 커밋 위로 rebase한다.
- **지원** 현재 checkout된 브랜치는 삭제할 수 없다.
- **지원** 강제 삭제는 브랜치 이름 재입력 확인을 요구한다.
- **지원** attached/unborn/detached HEAD 상태와 현재 브랜치의 upstream, ahead/behind를 표시한다.
- **부분 지원** 성능을 위해 실시간 ahead/behind 계산은 현재 checkout된 브랜치에만 수행한다. 다른 로컬 브랜치는 upstream 이름은 유지하지만 checkout되기 전에는 카운트를 계산하지 않는다.

## 원격과 원격 브랜치

- **지원** `origin`에 한정하지 않고 저장소의 모든 remote-tracking branch를 읽는다. 예: `origin/main`, `upstream/develop`.
- **지원** 원격 브랜치는 왼쪽 `Remotes` 구역과 해당 커밋의 ref 배지에 표시한다.
- **지원** 모든 remote를 대상으로 `fetch --all --prune`을 수행한다.
- **지원** Git 설정 사용, merge, rebase, fast-forward only 중 하나를 선택해 pull한다.
- **지원** 현재 브랜치를 push하고 upstream이 없을 때 remote와 원격 브랜치명을 선택해 최초 upstream을 설정한다.
- **지원** 현재 브랜치에 한해 브랜치 이름 재입력 확인 후 `--force-with-lease` push를 제공한다.
- **지원** remote 이름과 fetch/push URL을 조회하고 추가·이름 변경·URL 수정·삭제한다.
- **지원** remote-tracking branch를 remote별로 묶어 표시하고 선택 항목에서 로컬 tracking branch를 만들어 checkout한다.
- **부분 지원** 여러 fetch/push URL은 읽지만 전용 편집 화면은 첫 URL만 다룬다. 전체 값은 고급 Git config 화면에서 관리한다.
- **부분 지원** 이력이 갈라졌을 때 전용 선택 대화상자를 자동으로 띄우지는 않는다. 사용자가 Pull 메뉴에서 Git 설정, merge, rebase, fast-forward only를 선택한다.
- **제외** 원격 브랜치 삭제는 제공하지 않는다.

## Merge와 Rebase

- **지원** 일반 merge와 rebase를 시작한다.
- **지원** 진행 중인 merge에 continue와 abort를 제공한다.
- **지원** 진행 중인 rebase에 continue, skip, abort를 제공한다.
- **지원** interactive rebase에서 커밋 순서 변경과 pick, reword, squash, fixup, drop을 제공한다.
- **지원** interactive rebase helper가 Git sequence editor와 commit message editor 역할을 한다.
- **지원** merge commit이 포함된 범위는 `--rebase-merges` 없이 평탄화될 수 있음을 시작 전에 경고한다.
- **지원** rebase, cherry-pick, revert는 tracked 작업 트리와 index가 깨끗하지 않으면 시작하지 않는다. 자동 stash는 하지 않는다.

## Stash

- **지원** 메시지와 untracked 포함 여부를 지정해 stash를 만든다.
- **지원** stash 목록과 선택한 stash의 diff를 표시한다.
- **지원** apply, pop, drop을 제공한다.
- **지원** drop은 `stash@{N}` 재입력 확인을 요구한다.

## 충돌 해결

- **지원** index의 base, ours, theirs 내용을 읽어 텍스트 3-way 충돌 편집기를 연다.
- **지원** 충돌 블록별 ours, theirs, both 선택과 최종 결과 직접 편집을 제공한다.
- **지원** rebase에서는 단순한 ours/theirs 대신 실제 브랜치·커밋 의미를 설명하는 label을 표시한다.
- **지원** 해결 결과를 저장한 뒤 바로 stage한다.
- **지원** 충돌 해결 후 merge/rebase/cherry-pick/revert의 continue, skip, abort 흐름으로 이어진다.
- **지원** binary, 비 UTF-8, 대용량 충돌은 파일 전체 기준 ours/theirs 선택 또는 외부 도구 처리를 제공한다.
- **지원** Visual Studio Code, 시스템 기본 앱, Git mergetool, 사용자 지정 실행 파일을 외부 편집기로 선택한다.

## Reset 안전 장치

- **지원** reset은 detached HEAD가 아닌 현재 로컬 브랜치에서만 허용한다.
- **지원** 실행 전에 이동 대상, 사라질 수 있는 커밋, 영향을 받는 tracked 경로와 충돌 가능한 untracked 경로를 미리 보여준다.
- **지원** hard reset은 현재 브랜치 이름 재입력을 요구한다.
- **지원** hard reset이 덮어쓸 untracked 경로는 먼저 Windows 휴지통으로 이동하고 작업 로그에 남긴다.
- **지원** 미리보기 fingerprint와 실행 시점 상태가 달라졌으면 reset을 거부하고 다시 확인하게 한다.

## 설정과 복원

- **지원** 시스템/한국어/영어 언어 설정과 시스템/밝게/어둡게 테마를 저장한다.
- **지원** 열린 저장소, 최근 저장소, 활성 탭, 패널 폭, 상세 패널 표시 여부, 외부 편집기, 마지막 업데이트 확인 시각을 JSON으로 저장한다.
- **지원** release는 시스템 문서 폴더의 `GitFront\settings.json`을 사용한다.
- **지원** debug/profile은 시스템 문서 폴더의 `GitFront\develop\settings.json`을 사용한다.
- **지원** 문서 폴더는 하드코딩하지 않고 Windows의 실제 경로를 조회하므로 OneDrive로 이동된 문서 폴더도 따른다.
- **지원** 임시 파일과 백업 파일, 직렬화된 저장으로 중간 종료와 동시 저장에 대비한다.
- **지원** release의 새 설정이 없을 때만 이전 AppData SharedPreferences 설정을 옮기고, 새 파일 검증 후 기존 파일을 삭제한다.
- **지원** 테스트용 release 설정이 완전히 비어 있고 develop 설정에 저장소가 있으면 최초 한 번 값을 복사한다. 이후 두 설정은 독립적으로 저장하며 develop 파일은 보존한다.
- **지원** 저장된 저장소 하나가 삭제되었거나 열리지 않아도 나머지 탭 복원을 계속하고 앱 초기 화면을 정상 표시한다.

## Git 설정과 Sparse checkout

- **지원** 현재 저장소의 local config와 사용자 global config를 구분해 조회·수정·해제한다.
- **지원** system, include 등에서 상속된 유효값과 원본 scope·파일을 함께 표시하되 local/global만 수정한다.
- **지원** 사용자 이름·이메일, autocrlf, editor, 기본 브랜치, pull/fetch/push, GPG 관련 주요 설정을 빠른 목록으로 제공한다.
- **지원** 고급 표에서 임의 key/value를 검색하고 추가·교체·정확한 값 삭제를 수행한다.
- **지원** extra header와 access token 등 민감 config 값은 마스킹하고 작업 로그에서도 제거한다.
- **지원** cone-mode sparse checkout 디렉터리 목록을 설정·변경·비활성화한다.
- **지원** sparse 변경 전 진행 중 작업과 tracked 변경을 검사하며, 제외된 skip-worktree 파일을 삭제 변경으로 잘못 표시하지 않는다.
- **제외** system config 쓰기와 non-cone sparse pattern 편집은 제공하지 않는다.

## 업데이트와 패키징

- **지원** 패키징된 Windows 앱에서 GitHub Releases의 VeloPack feed를 확인한다.
- **지원** 앱 시작 시 하루 한 번 조용히 확인하고 설정 화면에서 수동 확인, 다운로드, 재시작 적용을 제공한다.
- **지원** debug/profile 빌드에서는 업데이트를 비활성화한다.
- **지원** per-user `Setup.exe`, `Portable.zip`, full NuGet package와 `releases.win.json`을 생성한다.
- **지원** preview 릴리스와 미서명 패키지를 허용한다.
- 현재 버전 규칙은 `0.0.1 → ... → 0.0.99 → 0.1.0`이며 별도 Flutter `+build` 번호를 사용하지 않는다.

## 성능을 위한 현재 설계

- Submodule과 Subtree 정보는 초기 snapshot에서 읽지 않는다. 해당 패널을 펼칠 때만 Submodule을 100개 단위로 읽고 Subtree 로컬 등록 정보를 불러온다.
- 변경 파일은 250개 단위로 Rust에서 잘라 전달하고 스크롤 끝에 가까워지면 다음 페이지를 자동으로 읽는다. 전체 개수와 staged 개수는 작은 요약값으로 별도 유지한다.
- 로컬·원격 브랜치도 250개 단위로 전달하고 왼쪽 목록의 스크롤 위치에 따라 이어서 읽는다. 현재 브랜치는 정렬상 첫 페이지에 유지한다.
- 변경 파일, 브랜치·원격·stash, 커밋 로그, diff 본문은 화면에 보이는 행 중심의 가상 목록으로 렌더링한다.
- 초기 화면과 저장소 개요를 먼저 표시하고 커밋 로그는 비동기로 채운다. 큰 저장소의 topological 정렬이 진행 중이어도 창과 변경 파일 화면을 막지 않는다.
- 로그 reader는 첫 요청에서 전체 커밋 ID를 모으지 않고 화면의 200개와 다음 페이지 확인용 1개만 전진한다. 같은 reader를 다음 페이지에서도 이어 사용하며 메타데이터·ref·그래프 lane도 보이는 범위만 생성한다.
- 저장소별 변경·로그 캐시는 최근 8개 저장소로 제한하고 HEAD 또는 working-tree generation이 바뀌면 오래된 커서를 거부한다.
- 수백 개 브랜치가 있는 저장소에서 모든 브랜치의 graph ahead/behind를 매번 계산하지 않는다.
- 파일 감시 이벤트는 300ms 동안 모아서 중복 경로를 제거한 뒤 처리한다.
- 일반 파일 변경은 working tree만 갱신하고, `.git` 이력 변경이 있을 때 필요한 로그를 다시 읽는다.
- 저장소별 요청 번호로 오래 걸린 이전 응답이 최신 화면을 덮지 못하게 한다.
- 패널 드래그 중에는 로컬 크기만 갱신하고 드래그 종료 시 한 번만 설정을 저장한다.
- 긴 diff line과 대용량·binary 파일의 렌더링을 제한한다.

## 인증, 오류와 진단

- 네트워크와 변경 작업은 shell 문자열을 만들지 않고 시스템 Git에 인자 배열로 전달한다.
- 기존 Git Credential Manager, SSH 설정과 credential helper를 그대로 사용한다.
- 작업 성공, 실패, 원본 Git 출력은 접을 수 있는 작업 로그에 남긴다.
- URL에 포함된 자격 증명과 민감한 값은 오류 및 진단 출력에서 제거한다.
- Git 명령이 충돌 때문에 실패 코드를 반환해도 저장소 상태를 다시 읽어 해당 작업 배너와 충돌 파일을 표시한다.

## Git Bash 대비 미지원 또는 제한 기능

여기서 Git Bash는 Git for Windows에 포함된 shell 자체가 아니라, 그 안에서 실행하는 Git CLI 기능을 뜻한다. Git의 내부용 plumbing 명령 전체가 아니라 데스크톱 클라이언트 사용자가 직접 사용할 가능성이 높은 workflow를 비교한다.

### 저장소 생성과 설정

| Git Bash 기능 | GitFront 현재 상태 |
| --- | --- |
| `git init`, `git init --bare` | **부분 지원** 일반 저장소 초기화와 초기 파일·branch·origin 설정을 제공하지만 bare 저장소는 만들지 않는다. |
| `git config` 조회·수정 | **부분 지원** local/global과 고급 key/value 편집을 제공한다. system config 쓰기와 설정 파일 원문 편집은 없다. |
| `git remote add`, `rename`, `set-url`, `remove` | **지원** remote 관리 화면에서 수행한다. 복수 URL의 세부 관리는 고급 config 표를 사용한다. |
| `git clone --branch`, `--depth`, `--filter`, `--recurse-submodules` | **부분 지원** 실용 옵션을 제공하지만 임의 인자, mirror/bare, reference clone은 없다. |
| `git sparse-checkout` | **부분 지원** cone-mode 디렉터리 목록은 관리하지만 non-cone pattern과 고급 명령 옵션은 없다. |

### 변경 파일과 커밋

| Git Bash 기능 | GitFront 현재 상태 |
| --- | --- |
| `git add -p`의 hunk 분할·검색·patch 직접 편집 | **부분 지원** hunk와 임의 변경 줄 stage/unstage는 가능하다. 자동 hunk 분할·검색·patch 원문 편집은 없다. |
| `git add --intent-to-add`, `--update`, pathspec 고급 선택 | **부분 지원** 다중 선택 intent-to-add와 안전한 NUL pathspec 전달을 지원한다. `--update`와 임의 pathspec 식 편집은 없다. |
| `git restore -p`, `git checkout -p` | **부분 지원** 파일·hunk·선택 변경 줄 폐기를 제공하지만 CLI식 대화형 patch 편집은 없다. |
| `git clean`의 패턴·dry-run·ignored 파일 삭제 | **의도적 제한** untracked 파일 한 개를 확인 후 Windows 휴지통으로 보내는 방식만 제공한다. |
| `git commit --amend` | **지원** 작성 옵션에서 마지막 커밋을 수정한다. |
| `git commit --fixup`, `--squash`, `--allow-empty` | **지원** 로그 대상을 고른 fixup/squash와 빈 커밋을 제공한다. |
| `git commit --author`, `--date`, `--signoff` | **지원** 작성자·ISO 8601 날짜·sign-off를 커밋별로 지정한다. |
| `git commit --no-verify`, `-S`, `--no-gpg-sign` | **부분 지원** 서명 사용/해제는 제공하고 hook은 항상 실행한다. `--no-verify`는 의도적으로 제공하지 않는다. |
| commit template와 cleanup 옵션 | **지원** template을 작성창에 불러오고 cleanup 설정은 시스템 Git에 맡긴다. |

### Diff와 이력 탐색

| Git Bash 기능 | GitFront 현재 상태 |
| --- | --- |
| `git diff <임의 ref>..<임의 ref>` | **제한** 작업 트리/index, 선택 커밋 상세, 선택 커밋 → 현재 HEAD 비교만 제공한다. 두 임의 ref를 고르는 화면은 없다. |
| `git diff --word-diff`, `--stat`, `--name-only`, whitespace 옵션 | **미지원** unified와 side-by-side 본문 보기에 집중한다. |
| `git log`의 author/date/message/path/branch 필터 | **미지원** 전체 topological 로그를 페이지 단위로 읽지만 검색·필터 UI는 없다. |
| `git log --all`, `--first-parent`, `--merges` 등 traversal 선택 | **미지원** 로그 순서와 탐색 범위를 사용자가 변경할 수 없다. |
| `git reflog` | **미지원** 이동하거나 삭제된 HEAD·branch 이력 복구 화면이 없다. |
| `git show`, `git grep`, `git shortlog`, `git describe` | **부분 대체** 선택 커밋 상세와 diff는 볼 수 있지만 각 명령의 전체 옵션과 별도 UI는 없다. |
| `git blame` | **미지원** 줄별 작성 커밋과 작성자 추적 UI가 없다. |
| `git bisect` | **미지원** 이진 탐색으로 문제 커밋을 찾는 workflow가 없다. |
| `git format-patch`, `git am`, `git apply` | **미지원** patch 내보내기·가져오기·적용 UI가 없다. |

### 브랜치, 태그와 원격

| Git Bash 기능 | GitFront 현재 상태 |
| --- | --- |
| remote-tracking branch에서 로컬 tracking branch 생성 | **지원** remote별 목록에서 로컬 이름을 지정해 생성하고 checkout한다. |
| `git branch --set-upstream-to`, `--unset-upstream` | **제한** 최초 push 때 remote와 branch를 선택할 수 있지만 기존 upstream 변경·해제 전용 UI는 없다. |
| `git branch --merged`, `--contains`, `--points-at` | **미지원** 브랜치 검색과 관계 필터가 없다. |
| orphan branch와 강제 branch 재지정 | **미지원** `git switch --orphan`, `git branch -f`에 해당하는 UI가 없다. |
| 원격 브랜치 삭제 | **미지원** `git push <remote> --delete <branch>`에 해당하는 메뉴가 없다. |
| 선택 remote/refspec push | **제한** 현재 브랜치를 기본 upstream으로 push하는 흐름만 제공한다. |
| 모든 브랜치·모든 태그 push | **미지원** `git push --all`, `git push --tags`를 제공하지 않는다. |
| 일반 `--force` push | **의도적 미지원** 현재 upstream에 대한 `--force-with-lease`만 확인 후 허용한다. |
| tag 목록 관리, 삭제, 원격 push | **제한** 커밋의 tag 배지와 tag 생성은 지원하지만 별도 목록·삭제·push UI는 없다. |
| signed tag와 tag signature 검증 | **미지원** `git tag -s`, `git tag -v`에 해당하는 UI가 없다. |

### Merge, Rebase, Cherry-pick과 Reset

| Git Bash 기능 | GitFront 현재 상태 |
| --- | --- |
| 여러 커밋 또는 범위 cherry-pick/revert | **제한** 한 번에 선택한 커밋 하나만 처리한다. |
| `cherry-pick --no-commit`, `revert --no-commit` | **미지원** 결과를 commit 전 상태로만 적용하는 옵션이 없다. |
| merge strategy와 `-X` strategy option | **미지원** 일반 merge만 제공하며 ours/theirs, patience, subtree 등 전략 옵션을 고를 수 없다. |
| octopus merge | **미지원** 여러 branch를 한 명령으로 merge하는 UI가 없다. |
| `rebase --onto`의 세 기준점 직접 지정 | **제한** branch 또는 선택 커밋 위로 rebase할 수 있지만 upstream/onto/branch 세 값을 자유롭게 구성할 수 없다. |
| `rebase --rebase-merges` | **미지원** interactive rebase에서 merge commit 구조를 보존하지 않는다. 시작 전에 평탄화 가능성을 경고한다. |
| `rebase --autosquash`, `--autostash`, `--exec` | **미지원** 자동 stash나 임의 명령 실행 없이 명시적인 interactive plan만 사용한다. |
| path 단위 reset, `reset --merge`, `reset --keep` | **제한** 현재 로컬 branch 전체에 대한 soft/mixed/hard reset만 제공한다. |
| `git revert` 메시지 편집 | **의도적 제한** 기본 메시지를 사용하고 편집기 대기를 피하기 위해 `--no-edit`로 실행한다. |

### Stash

| Git Bash 기능 | GitFront 현재 상태 |
| --- | --- |
| pathspec을 지정한 부분 stash | **미지원** 저장소 전체 변경을 대상으로 한다. |
| `stash --keep-index`, `--staged`, `--all`, `--patch` | **제한** 메시지와 untracked 포함 여부만 선택할 수 있다. |
| `git stash branch` | **미지원** stash 기준 branch 생성 workflow가 없다. |
| stash 이름 변경·내보내기·가져오기 | **미지원** 목록, diff, apply, pop, drop만 제공한다. |

### 저장소 구조와 유지보수

| Git Bash 기능 | GitFront 현재 상태 |
| --- | --- |
| `git submodule` | **지원** 재귀 상태 조회, 초기화, 기록된 커밋/원격 업데이트, URL 동기화, 추가, 새 탭 열기와 확인 기반 제거를 제공한다. |
| `git subtree` | **지원** GitFront가 공식 Git 소스의 고정된 subtree helper를 내장한다. 시스템 Git의 subtree 설치가 빠졌거나 손상돼도 Git for Windows의 Git·Bash를 이용해 add/pull/push/split을 실행한다. |
| `git worktree` | **미지원** 추가 checkout 생성·이동·삭제 UI가 없다. |
| Git LFS 명령 | **미지원** LFS 추적 규칙, pull/push, lock 관리 UI가 없다. 시스템 Git 동작 중 LFS hook이 실행되는 것은 막지 않는다. |
| `git gc`, `maintenance`, `repack`, `prune` | **미지원** 저장소 최적화와 정리 UI가 없다. |
| `git fsck` | **미지원** object 무결성 검사 화면이 없다. |
| `git archive`, `git bundle` | **미지원** 저장소 snapshot·bundle 생성과 복원 UI가 없다. |
| `git notes`, `git replace` | **미지원** 보조 metadata와 object 대체 관리 UI가 없다. |

### 호스팅 서비스와 플랫폼

| Git Bash 또는 별도 CLI 기능 | GitFront 현재 상태 |
| --- | --- |
| GitHub/GitLab PR·이슈·리뷰 | **미지원** 호스팅 서비스 API와 연결하지 않는다. Git 자체의 fetch/push만 제공한다. |
| GitHub CLI `gh`, GitLab CLI `glab` workflow | **미지원** 별도 CLI를 호출하거나 그 결과를 UI에 통합하지 않는다. |
| Windows 이외 플랫폼 | **제한** Rust/Flutter 구조는 확장 가능하지만 현재 배포와 검증은 Windows 10/11 x64만 대상으로 한다. |

이 목록에 없는 Git CLI 옵션은 지원되는 것으로 간주하지 않는다. GitFront가 명시적으로 제공하는 workflow는 이 문서 앞부분을 기준으로 판단하고, 고급 옵션이 필요하면 현재는 Git Bash를 병행해야 한다.

## v1 명시적 제외 범위

- 원격 브랜치 삭제와 복수 remote URL 전용 UI
- tag 삭제·이름 변경·원격 push
- Git worktree와 Git LFS 관리 UI
- blame
- GitHub/GitLab 등 호스팅 서비스의 PR·이슈 연동
- 여러 커밋을 묶은 cherry-pick/revert
- Windows 이외 플랫폼의 배포와 검증
