#!/usr/bin/env bash
# build.sh - gen + build Release + embute helpers + assina + verifica (08 AR-901).
#
# Contrato
#   Entrada : project.yml, Packages/AgentBoxKit. Env: DEVELOPER_DIR, AGENTBOX_SIGN_IDENTITY (nome do
#             certificado; padrão "Agent Box Local Signing"; "-" força ad-hoc), AGENTBOX_BUILD_DIR (padrão build/AgentBox).
#   Efeitos : compila o app (xcodebuild Release, Swift 6 estrito, warnings como erro) e os executáveis SPM
#             agentbox/agentboxd (swift build -c release), embute-os em Contents/MacOS e assina de dentro
#             para fora (agentbox, agentboxd, app), SEM --deep, com --options runtime e sem entitlements.
#   Assinatura: com a identidade local, designated requirement = identifier "<id>" and certificate leaf = H"<sha1>".
#             Sem a identidade (make-dev-cert.sh ainda não rodado) cai para ad-hoc ("-"), com AVISO; o DR é
#             então cdhash e muda a cada build (perde ACL do Keychain/TCC; ver 08 AR-530).
#   Saída   : "<AGENTBOX_BUILD_DIR>/Agent Box.app" verificado com codesign --verify --strict; exit != 0 em falha.
# Uso: scripts/build.sh [--help]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
fail() { echo "ERRO: $*" >&2; exit 1; }

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT="${AGENTBOX_BUILD_DIR:-$ROOT/build/AgentBox}"
APP="$OUT/Agent Box.app"
DD="$OUT/DerivedData"
IDENT_NAME="${AGENTBOX_SIGN_IDENTITY:-Agent Box Local Signing}"
cd "$ROOT"

"$ROOT/scripts/gen.sh"

BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
mkdir -p "$OUT"

echo "build: xcodebuild Release (app)"
xcodebuild -project AgentBox.xcodeproj -scheme AgentBox -configuration Release \
  -derivedDataPath "$DD" -skipPackagePluginValidation -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build \
  | { if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else cat; fi; } \
  > "$OUT/xcodebuild.log" 2>&1 || { tail -40 "$OUT/xcodebuild.log" >&2; fail "xcodebuild falhou (log: $OUT/xcodebuild.log)"; }
tail -3 "$OUT/xcodebuild.log"

echo "build: swift build -c release (agentbox, agentboxd)"
for prod in agentbox agentboxd; do
  swift build -c release --package-path Packages/AgentBoxKit --product "$prod"
done
BIN="$(swift build -c release --package-path Packages/AgentBoxKit --show-bin-path)"

rm -rf "$APP"
ditto "$DD/Build/Products/Release/Agent Box.app" "$APP"
# APFS é case-insensitive: o executável do app ("Agent Box") não pode colidir com o helper "agentbox".
[ ! -e "$APP/Contents/MacOS/agentbox" ] || fail "Contents/MacOS/agentbox já existe antes de embutir o helper (colisão de nome com o executável do app)"
install -m 755 "$BIN/agentbox" "$APP/Contents/MacOS/agentbox"
install -m 755 "$BIN/agentboxd" "$APP/Contents/MacOS/agentboxd"
# LaunchAgent plist (Contents/Library/LaunchAgents) e Info.plist embutido do daemon entram com a tarefa do daemon.

# Identidade de assinatura
IDENT="-"; SHA=""
if [ "$IDENT_NAME" != "-" ]; then
  SHA="$(security find-certificate -c "$IDENT_NAME" -Z 2>/dev/null | awk '/^SHA-1 hash:/{print $3; exit}' || true)"
  if [ -n "$SHA" ]; then IDENT="$SHA"; fi
fi
if [ "$IDENT" = "-" ]; then
  echo "AVISO: identidade '$IDENT_NAME' ausente; assinando AD-HOC (rode scripts/make-dev-cert.sh uma vez para assinatura estável)." >&2
fi

sign() { # path identifier
  if [ "$IDENT" = "-" ]; then
    codesign --force --options runtime --timestamp=none --sign - --identifier "$2" "$1"
  else
    codesign --force --options runtime --timestamp=none --sign "$IDENT" --identifier "$2" \
      -r="designated => identifier \"$2\" and certificate leaf = H\"$SHA\"" "$1"
  fi
}
sign "$APP/Contents/MacOS/agentbox" app.agentbox.cli
sign "$APP/Contents/MacOS/agentboxd" app.agentbox.ptyd
sign "$APP" app.agentbox.mac

echo "build: verificando assinatura"
codesign --verify --strict --verbose=2 "$APP"
for pair in "$APP/Contents/MacOS/agentbox:app.agentbox.cli" "$APP/Contents/MacOS/agentboxd:app.agentbox.ptyd" "$APP:app.agentbox.mac"; do
  p="${pair%%:*}"; id="${pair##*:}"
  codesign --verify --strict "$p"
  dr="$(codesign -dr - "$p" 2>&1 | grep 'designated =>' || true)"
  if [ "$IDENT" = "-" ]; then
    case "$dr" in *"cdhash H"*) ;; *) fail "DR inesperado para $p: $dr" ;; esac
  else
    want="designated => identifier \"$id\" and certificate leaf = H\"$SHA\""
    [ "$(printf '%s' "$dr" | tr 'A-F' 'a-f')" = "$(printf '%s' "$want" | tr 'A-F' 'a-f')" ] || fail "DR inesperado para $p: $dr (esperado: $want)"
  fi
done
codesign -dv "$APP" 2>&1 | grep -E 'flags=|Identifier=' || true
echo "build: OK -> $APP"
