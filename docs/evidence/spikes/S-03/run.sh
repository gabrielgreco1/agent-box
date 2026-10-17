#!/bin/bash
cd /private/tmp/claude-501/s03 || exit 1
A=012fce5b7ba145e1e880f0be16ac9601783a8f6d
REQ="identifier \"app.agentbox.mac\" and certificate leaf = H\"$A\""
SOCK=/private/tmp/claude-501/s03/p.sock
for c in cliA cliAcli cliB cliAdhoc cliUnsigned; do
  ./srvA serve $SOCK "$REQ" 1 > out-$c.txt 2>&1 &
  SP=$!
  sleep 0.4
  ./$c client $SOCK 400 2>&1 | head -2
  wait $SP
  echo "### server=srvA(cert A) client=$c"
  tail -n +2 out-$c.txt
done
echo "### server=srvAdhoc client=cliAdhoc requirement=anchor-less identifier only"
./srvAdhoc serve $SOCK 'identifier "app.agentbox.mac"' 1 > out-adhoc.txt 2>&1 &
SP=$!
sleep 0.4
./cliAdhoc client $SOCK 400
wait $SP
tail -n +2 out-adhoc.txt
echo "### in-process (xctest-like) cliUnsigned is killed by arm64 loader:"
./cliUnsigned self; echo "exit=$?"
