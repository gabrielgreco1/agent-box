echo "--- re-registro (unregister + register) com o binario novo"
open -W -g -n --stdout /tmp/s01-out3.txt --stderr /tmp/s01-out3.txt "$APP" --args unregister
open -W -g -n --stdout /tmp/s01-out3.txt --stderr /tmp/s01-out3.txt "$APP" --args register
tail -4 /tmp/s01-out3.txt
SOCK="$(launchctl getenv AGENTBOX_PTYD_SOCK_V1)"; echo "sock=$SOCK"
(echo three | nc -U "$SOCK" & P=$!; for i in 1 2 3 4 5 6; do kill -0 $P 2>/dev/null || break; sleep 1; done; kill $P 2>/dev/null)
launchctl print gui/501/app.agentbox.ptyd.test-s01$SUF | grep -E "^	state|properties|runs =|last exit"
grep -E "start v" /tmp/s01-daemon.log | cut -c1-60
