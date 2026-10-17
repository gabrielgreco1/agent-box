#!/usr/bin/env bash
# lint.sh - Swift 6 sem warnings + proibições de AR-131 por ripgrep (T1-01).
#
# Contrato
#   Entrada : código Swift novo em Packages/*/Sources e App/ (nunca legacy/). Env: LINT_ROOT (raiz; padrão = repositório).
#   Falha em : (1) warnings/erros do build Swift 6 estrito (swift build -Xswiftc -warnings-as-errors, a menos que --no-build);
#              (2) violações da tabela AR-131 (blocking/sleep, locks sem "// LOCK:", Process/posix_spawn/forkpty fora de
#              Platform, import GRDB fora de Store, FileManager/URLSession/Process na UI, .sheet/NSToolbar/.toolbar,
#              print/NSLog/debugPrint, @unchecked Sendable/nonisolated(unsafe) sem "// SAFETY:", Task.detached sem
#              "// DETACHED:", DispatchQueue.main.sync, try!/fatalError, UserDefaults, strings proibidas,
#              setUseMetal(false), LocalProcessTerminalView/TerminalFindBarView). Linhas só de comentário são ignoradas.
#   Self-test: --self-test roda um caso que DEVE falhar e um que DEVE passar para cada regra (AR-131).
#   Escopo   : regras de UI (literais fora de DS.*, List(, Button fora do registro) ficam em scripts/lint-ui.sh.
#   Saída   : exit 0 em sucesso; exit 1 em violação/warning; exit 2 uso inválido.
# Uso: scripts/lint.sh [--no-build] [--self-test] [--help]
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT="${LINT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

NO_BUILD=0; SELF_TEST=0
for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0 ;;
    --no-build) NO_BUILD=1 ;;
    --self-test) SELF_TEST=1 ;;
    *) usage >&2; exit 2 ;;
  esac
done

command -v rg >/dev/null 2>&1 || { echo "ERRO: rg (ripgrep) não encontrado" >&2; exit 1; }

# --- motor de regras ---------------------------------------------------------------------------
VIOLATIONS=0
# Diretórios varridos (relativos a ROOT): Packages/*/Sources e App (calculado em run_rules).
SCAN_EXPANDED=""

# matches REGEX [rg-globs...]  -> imprime "arquivo:linha:texto" (sem linhas só de comentário)
matches() {
  local re="$1"; shift
  local globs=()
  for g in "$@"; do globs+=(-g "$g"); done
  local dirs=()
  for d in $SCAN_EXPANDED; do dirs+=("$d"); done
  [ ${#dirs[@]} -gt 0 ] || return 0
  (cd "$ROOT" && rg -nP --no-heading --type swift ${globs[@]+"${globs[@]}"} -e "$re" "${dirs[@]}" 2>/dev/null || true) \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true
}

report() { # regra mensagem linhas
  [ -n "$3" ] || return 0
  echo "lint: [$1] $2" >&2
  echo "$3" | sed 's/^/    /' >&2
  VIOLATIONS=$((VIOLATIONS + $(echo "$3" | grep -c .)))
}

# rule NOME DESCRIÇÃO REGEX [globs...]  (globs: includes e !excludes)
rule() { local n="$1" d="$2" re="$3"; shift 3; report "$n" "$d" "$(matches "$re" "$@")"; }

# annotated NOME DESCRIÇÃO REGEX NOTA_REGEX [globs...] : cada ocorrência precisa de NOTA na mesma linha ou nas 2 anteriores
annotated() {
  local n="$1" d="$2" re="$3" note="$4"; shift 4
  local bad="" line file ln
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    file="${line%%:*}"; ln="${line#*:}"; ln="${ln%%:*}"
    local from=$((ln > 2 ? ln - 2 : 1))
    if ! sed -n "${from},${ln}p" "$ROOT/$file" | grep -qE "$note"; then bad+="$line"$'\n'; fi
  done <<< "$(matches "$re" "$@")"
  report "$n" "$d" "${bad%$'\n'}"
}

run_rules() {
  SCAN_EXPANDED="$(cd "$ROOT" && ls -d Packages/*/Sources App 2>/dev/null | tr '\n' ' ' || true)"

  rule blocking "DispatchSemaphore/Thread.sleep/usleep/sleep(/DispatchGroup.wait fora de Platform/Blocking* e agentboxd" \
    '\bDispatchSemaphore\b|\bThread\.sleep\b|\busleep\(|(?<![.\w])sleep\(' \
    '!**/AgentBoxPlatform/Blocking*' '!**/agentboxd/**'
  rule dispatchgroup "DispatchGroup.wait" '\bDispatchGroup\b[^\n]*\.wait\(|\.wait\((timeout|wallTimeout):' \
    '!**/AgentBoxPlatform/Blocking*' '!**/agentboxd/**'
  rule locks-global "locks fora de Platform e TerminalCore" \
    '\b(NSLock|NSRecursiveLock|os_unfair_lock|OSAllocatedUnfairLock)\b' \
    '!**/AgentBoxPlatform/**' '!**/AgentBoxTerminalCore/**'
  annotated locks-note "lock em Platform/TerminalCore sem comentário '// LOCK:'" \
    '\b(NSLock|NSRecursiveLock|os_unfair_lock|OSAllocatedUnfairLock)\b' '// LOCK:' \
    '**/AgentBoxPlatform/**' '**/AgentBoxTerminalCore/**'
  rule process "Process(/posix_spawn/forkpty fora de Platform/ProcessRunner* e agentboxd" \
    '(?<![.\w])Process\(|\bposix_spawn\b|\bforkpty\b' \
    '!**/AgentBoxPlatform/ProcessRunner*' '!**/agentboxd/**'
  rule grdb "import GRDB fora de AgentBoxStore" '^\s*(@\w+\s+)?import\s+GRDB\b' '!**/AgentBoxStore/**'
  rule ui-system "FileManager/URLSession/Process na UI e DesignSystem" '\b(FileManager|URLSession|Process)\b' \
    '**/AgentBoxUI/**' '**/AgentBoxDesignSystem/**'
  rule ui-chrome ".sheet(/NSToolbar/.toolbar { (00 T5)" '\.sheet\(|\bNSToolbar\b|\.toolbar\s*\{' \
    '**/AgentBoxUI/**' '**/AgentBoxDesignSystem/**' 'App/**'
  rule print "print(/NSLog(/debugPrint(" '\bprint\(|\bNSLog\(|\bdebugPrint\('
  annotated unchecked "@unchecked Sendable/nonisolated(unsafe) sem '// SAFETY:'" \
    '@unchecked\s+Sendable|nonisolated\(unsafe\)' '// SAFETY:'
  annotated detached "Task.detached sem '// DETACHED:'" '\bTask\.detached\b' '// DETACHED:'
  rule main-sync "DispatchQueue.main.sync" '\bDispatchQueue\.main\.sync\b'
  rule try-bang "try!" '\btry!'
  annotated fatal "fatalError( fora de required init?(coder:)" '\bfatalError\(' 'required init\?\(coder'
  rule userdefaults "UserDefaults fora de AgentBoxStore/LegacyDefaults" '\bUserDefaults\b' '!**/AgentBoxStore/LegacyDefaults*'
  rule banned-strings "strings proibidas (audit/02)" 'webscraping-expert|colima-agentbox-dev|ab019'
  rule metal "setUseMetal(false)" '\bsetUseMetal\(false\)' '**/AgentBoxUI/**'
  rule swiftterm-local "LocalProcessTerminalView/LocalProcess(/TerminalFindBarView/performFindPanelAction (T6, AR-122)" \
    '\bLocalProcessTerminalView\b|\bLocalProcess\(|\bTerminalFindBarView\b|\bperformFindPanelAction\b'
}

# --- self-test (AR-131: um caso que falha e um que passa por regra) ------------------------------
if [ "$SELF_TEST" = 1 ]; then
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  fails=0
  expect() { # nome caminho conteúdo resultado(fail|pass)
    local name="$1" path="$2" body="$3" want="$4" rc=0
    rm -rf "$T/r"; mkdir -p "$T/r/$(dirname "$path")"; printf '%s\n' "$body" > "$T/r/$path"
    LINT_ROOT="$T/r" "$SELF" --no-build >/dev/null 2>&1 || rc=$?
    local got=pass; [ "$rc" -ne 0 ] && got=fail
    if [ "$got" = "$want" ]; then echo "ok: $name ($want)"; else echo "FALHOU: $name esperado=$want obtido=$got" >&2; fails=$((fails+1)); fi
  }
  C=Packages/AgentBoxKit/Sources/AgentBoxCore/X.swift
  P=Packages/AgentBoxKit/Sources/AgentBoxPlatform/X.swift
  U=Packages/AgentBoxKit/Sources/AgentBoxUI/X.swift
  expect blocking-bad $C 'let s = DispatchSemaphore(value: 0)' fail
  expect blocking-ok $C 'try await Task.sleep(for: .seconds(1))' pass
  expect sleep-bad $C 'sleep(1)' fail
  expect usleep-bad $C 'usleep(10)' fail
  expect thread-sleep-bad $C 'Thread.sleep(forTimeInterval: 1)' fail
  expect blocking-platform-blocking-ok Packages/AgentBoxKit/Sources/AgentBoxPlatform/BlockingIOExecutor.swift 'let s = DispatchSemaphore(value: 0)' pass
  expect lock-core-bad $C 'let l = NSLock()' fail
  expect lock-platform-bad $P 'let l = NSLock()' fail
  expect lock-platform-ok $P $'// LOCK: sem I/O sob o lock\nlet l = NSLock()' pass
  expect process-bad $C 'let p = Process()' fail
  expect processinfo-ok $C 'let p = ProcessInfo.processInfo' pass
  expect grdb-bad $C 'import GRDB' fail
  expect grdb-store-ok Packages/AgentBoxKit/Sources/AgentBoxStore/X.swift 'import GRDB' pass
  expect ui-filemanager-bad $U 'let f = FileManager.default' fail
  expect ui-filemanager-store-ok Packages/AgentBoxKit/Sources/AgentBoxStore/X.swift 'let f = FileManager.default' pass
  expect sheet-bad $U 'Text("x").sheet(isPresented: b) {}' fail
  expect print-bad $C 'print("x")' fail
  expect fingerprint-ok $C 'let x = fingerprint(a)' pass
  expect unchecked-bad $C 'final class A: @unchecked Sendable {}' fail
  expect unchecked-ok $C $'// SAFETY: stress test X\nfinal class A: @unchecked Sendable {}' pass
  expect detached-bad $C 'Task.detached { }' fail
  expect detached-ok $C $'// DETACHED: motivo\nTask.detached { }' pass
  expect main-sync-bad $C 'DispatchQueue.main.sync { }' fail
  expect try-bang-bad $C 'let x = try! f()' fail
  expect fatal-bad $C 'fatalError("x")' fail
  expect fatal-coder-ok $C $'required init?(coder: NSCoder) {\n    fatalError("init(coder:)")\n}' pass
  expect userdefaults-bad $C 'UserDefaults.standard.set(1, forKey: "a")' fail
  expect banned-bad $C 'let s = "webscraping-expert"' fail
  expect swiftterm-bad $U 'let v = LocalProcessTerminalView()' fail
  expect comment-ignored $C '// print("x") is forbidden' pass
  [ "$fails" -eq 0 ] || { echo "lint self-test: $fails falha(s)" >&2; exit 1; }
  echo "lint self-test: OK"
  exit 0
fi

# --- (1) build Swift 6 estrito sem warnings ------------------------------------------------------
if [ "$NO_BUILD" = 0 ]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  echo "lint: swift build (Swift 6 estrito, warnings como erro)"
  if ! OUT="$(cd "$ROOT" && swift build --package-path Packages/AgentBoxKit --build-tests -Xswiftc -warnings-as-errors 2>&1)"; then
    echo "$OUT" | tail -40 >&2
    echo "lint: FALHOU (build)" >&2; exit 1
  fi
  if echo "$OUT" | grep -E 'warning:' | grep -vE 'SourcePackages|/checkouts/|\.build/checkouts' >/dev/null; then
    echo "$OUT" | grep -E 'warning:' >&2
    echo "lint: FALHOU (warnings no build)" >&2; exit 1
  fi
fi

# --- (2) proibições ------------------------------------------------------------------------------
run_rules
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "lint: FALHOU ($VIOLATIONS violação(ões))" >&2
  exit 1
fi
echo "lint: OK"
