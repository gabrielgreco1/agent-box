#!/bin/bash
# Variante sem SMAppService: launchctl bootstrap de um plist de teste (label app.agentbox.ptyd.test-s01plain) com o daemon do spike.
# Prova launch_activate_socket, launchctl getenv e a ativacao sob demanda sem depender de aprovacao de Itens de Inicio.
set -uo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
D="$S/ABS01.app/Contents/MacOS/s01d"
LABEL=app.agentbox.ptyd.test-s01plain
PL="$S/$LABEL.plist"
rm -f /tmp/s01-daemon.log
cat > "$PL" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>Program</key><string>$D</string>
<key>KeepAlive</key><false/>
<key>EnvironmentVariables</key><dict><key>S01_LOG</key><string>/tmp/s01-daemon.log</string><key>S01_IDLE</key><string>8</string></dict>
<key>Sockets</key><dict><key>Listeners</key><dict>
  <key>SecureSocketWithKey</key><string>AGENTBOX_PTYD_SOCK_V1</string>
</dict></dict>
</dict></plist>
EOF
trap 'launchctl bootout gui/501/$LABEL 2>/dev/null; echo "--- bootout; getenv agora: [$(launchctl getenv AGENTBOX_PTYD_SOCK_V1)]"' EXIT
echo "--- bootstrap"; launchctl bootstrap gui/501 "$PL"; echo "rc=$?"
SOCK="$(launchctl getenv AGENTBOX_PTYD_SOCK_V1)"
echo "--- launchctl getenv AGENTBOX_PTYD_SOCK_V1 => $SOCK (len ${#SOCK})"
echo "--- job antes de qualquer conexao"; launchctl print gui/501/$LABEL | grep -E "^	state|runs =|secure key|	path = /var|mode ="
ls -la "$(dirname "$SOCK")"
echo "--- nc -U acorda o daemon"
(echo hi | nc -U "$SOCK" & P=$!; for i in 1 2 3 4 5; do kill -0 $P 2>/dev/null || break; sleep 1; done; kill $P 2>/dev/null)
launchctl print gui/501/$LABEL | grep -E "^	state|runs =|pid ="
echo "--- aguardando saida por ociosidade (8 s)"
for i in $(seq 1 30); do launchctl print gui/501/$LABEL | grep -q "^	state = running" || break; sleep 1; done
launchctl print gui/501/$LABEL | grep -E "^	state|runs =|last exit"
echo "--- nova conexao relanca o daemon, mesmo caminho"
(echo again | nc -U "$SOCK" & P=$!; for i in 1 2 3 4 5; do kill -0 $P 2>/dev/null || break; sleep 1; done; kill $P 2>/dev/null)
launchctl print gui/501/$LABEL | grep -E "^	state|runs ="
echo "--- log do daemon"; cut -c1-170 /tmp/s01-daemon.log
