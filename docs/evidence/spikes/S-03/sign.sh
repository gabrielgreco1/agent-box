#!/bin/bash
cd /private/tmp/claude-501/s03 || exit 1
A=012FCE5B7BA145E1E880F0BE16AC9601783A8F6D; B=64800D1C7763D1762ADD5E3A69822A173F1602C2
KA=/private/tmp/claude-501/s03/agentbox-ci-48317.keychain-db; KB=/private/tmp/claude-501/s03/agentbox-ci-48346.keychain-db
for n in srvA srvAdhoc cliA cliAcli cliB cliAdhoc cliUnsigned; do cp peerprobe $n; done
codesign --remove-signature cliUnsigned
codesign -f --options runtime -s "Agent Box Local Signing" --keychain $KA -i app.agentbox.ptyd srvA 2>&1
codesign -f --options runtime -s - -i app.agentbox.ptyd srvAdhoc 2>&1
codesign -f --options runtime -s "Agent Box Local Signing" --keychain $KA -i app.agentbox.mac cliA 2>&1
codesign -f --options runtime -s "Agent Box Local Signing" --keychain $KA -i app.agentbox.cli cliAcli 2>&1
codesign -f --options runtime -s "Agent Box Local Signing" --keychain $KB -i app.agentbox.mac cliB 2>&1
codesign -f --options runtime -s - -i app.agentbox.mac cliAdhoc 2>&1
for n in srvA srvAdhoc cliA cliB cliAdhoc cliUnsigned; do echo "== $n"; ./$n self 2>&1 | head -2; done
