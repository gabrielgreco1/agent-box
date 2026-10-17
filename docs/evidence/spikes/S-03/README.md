# S-03 · Peer auth do socket do daemon (`LOCAL_PEERTOKEN` + `SecCodeCheckValidity`)

Data: 2026-10-17 · Máquina: macOS 27 (Darwin 27.0.0), arm64, Xcode 26 toolchain · Resultado: **APROVADO**. O plano B (`getpeereid` + Team ID ad-hoc só em DEBUG, 09 §7 item 3) **não** foi necessário.

## Pergunta

O daemon consegue, na aceitação da conexão, (1) provar que o peer é o mesmo usuário e (2) que o binário do peer é o app (`identifier "app.agentbox.mac"` + mesma folha de certificado do daemon), sem confiar em PID, e isso funciona com certificado efêmero (CI), ad-hoc e processo de teste?

## Método

`peerprobe.swift` (esta pasta) é um servidor UDS que, a cada `accept`, lê `getpeereid`, `LOCAL_PEERPID`, `LOCAL_PEERTOKEN` (32 bytes, `audit_token_t`), chama `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)`, `SecCodeCheckValidity` (strict) sem requisito e com o requisito, e imprime JSON. O mesmo binário serve de cliente. Cópias dele foram assinadas por `sign.sh` e exercitadas por `run.sh` (caminhos e SHA-1 são os da execução; reproduza gerando seus próprios certificados). Certificados: `scripts/make-dev-cert.sh --ephemeral` duas vezes (A e B, ambos "Agent Box Local Signing", keychains temporários, sem confiança de usuário, sem senha). Requisito do daemon: `identifier "app.agentbox.mac" and certificate leaf = H"<sha1 de A>"`.

## Resultados

| Daemon (servidor) | Peer (cliente) | Resultado | Observação |
|---|---|---|---|
| assinado com A (`app.agentbox.ptyd`) | assinado com A, id `app.agentbox.mac` | **ACEITO** (`reqStatus 0`) | token, PID e uid coerentes (`tokenPid == LOCAL_PEERPID`) |
| idem | assinado com A, id `app.agentbox.cli` (o helper) | recusado (`-67050`, `errSecCSReqFailed`) | mesma folha, identificador errado |
| idem | assinado com B, id `app.agentbox.mac` | recusado (`-67050`) | outro certificado, mesmo identificador |
| idem | ad-hoc, id `app.agentbox.mac` | recusado (`-67050`) | sem folha |
| ad-hoc | ad-hoc, id `app.agentbox.mac`, requisito só por identificador | aceito | ad-hoc não tem folha: só dá para prender identificador (fraco). Por isso o modo ad-hoc usa só uid, explícito e registrado |
| (c) processo do `swift test` | xctest assinado pela Apple | recusado contra o requisito do app; aceito contra o requisito do próprio processo | `PeerAuthTests.testRunnerProcessFailsTheAppRequirementAndPassesItsOwn` |
| (b) binário sem assinatura nenhuma | | o kernel o mata (`Killed: 9`, exit 137) em arm64 | "não assinado" não existe de fato; o pior caso é ad-hoc/linker-signed |

Todos os casos: `getpeereid` = 501, `LOCAL_PEERTOKEN` ok (len 32), `SecCodeCopyGuestWithAttributes` = 0, `SecCodeCheckValidity` sem requisito = 0 (também com hardened runtime). Saídas brutas em `run-signed-server.out` e `run-adhoc-server.out`.

## Achados que mudam a implementação

1. **Funciona com certificado autoassinado sem confiança de usuário.** A checagem do requisito `certificate leaf = H"..."` compara o hash da folha embutida na assinatura do peer; não avalia cadeia nem pede trust. Logo o CI não precisa de `add-trusted-cert` (que pede senha).
2. **`codesign` não acha identidade não confiável por SHA-1.** `codesign -s <SHA1>` responde `no identity found` para o certificado efêmero (`CSSMERR_TP_NOT_TRUSTED`, `security find-identity -v` não lista). Funciona assinando **por nome** e passando `--keychain <caminho absoluto>` (caminho relativo falha). `scripts/build.sh` ganhou `AGENTBOX_SIGN_KEYCHAIN` para isso. O DR resultante (`identifier "<id>" and certificate leaf = H"<sha1>"`) é o mesmo da identidade local.
3. **O daemon deriva o requisito do próprio certificado** (`SecCodeCopySelf` → `SecCodeCopySigningInformation` → folha), então não há SHA-1 embutido em código nem variável de ambiente: o mesmo `agentboxd` serve com a identidade local, com a efêmera do CI e com Developer ID depois.
4. **Use o audit token, nunca o PID.** `LOCAL_PEERTOKEN` carrega a versão do PID; `LOCAL_PEERPID` serve só para log. Ler as credenciais no `accept` (T1-07 faz no `UDSListener`) evita perder o peer se ele fechar logo.
5. `audit_token_to_pid` não linka (libbsm); o PID está em `val[5]` se for preciso.
6. Chamadas do Security.framework são síncronas e lentas (ms a dezenas de ms): rodam em `BlockingIOBridge`.

## Receita de CI (08 §8.4)

```bash
export TMPDIR="$RUNNER_TEMP/"                        # keychain e certificado ficam aqui
OUT="$(scripts/make-dev-cert.sh --ephemeral)"        # cria keychain temporário + certificado (sem prompt)
KC="$(sed -n 's/^AGENTBOX_EPHEMERAL_KEYCHAIN=//p' <<<"$OUT")"
AGENTBOX_SIGN_KEYCHAIN="$KC" scripts/build.sh        # assina agentbox, agentboxd e o app com a identidade efêmera
swift test --package-path Packages/AgentBoxKit       # PeerAuthDaemonTests geram os próprios certificados efêmeros
security delete-keychain "$KC"                       # sempre, mesmo em falha (if: always())
security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db"  # o script acrescenta o keychain à lista do usuário
```

Notas: `make-dev-cert.sh --ephemeral` inclui o keychain temporário na lista de busca do usuário (o runner é descartável; num Mac de verdade restaure a lista, como acima). Os testes do daemon (T1-07) não tocam a lista: criam keychains próprios e assinam por nome com `--keychain`. Execução completa da receita neste Mac, com restauração da lista: `docs/evidence/slice1/T1-07/ci-recipe-ephemeral.out`.

## Conclusão

`LOCAL_PEERTOKEN` + `SecCodeCopyGuestWithAttributes` + `SecCodeCheckValidity` com requisito por identificador e folha de certificado atende AR-503 e TA-103 no Mac e no CI, com certificado efêmero. Limites registrados: (i) ad-hoc não permite prender identidade, daí o modo uid-only explícito (T1-07); (ii) o requisito vale para o código em disco carregado no processo; um processo do mesmo usuário com permissão de depurar o app assinado (`task_for_pid`) não é coberto, já assumido em AR-501/AR-503 ("não é fronteira contra o agente no Mac").
