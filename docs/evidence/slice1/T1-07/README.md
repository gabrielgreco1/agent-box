# T1-07 · Peer auth do daemon

Base: spike S-03 (`docs/evidence/spikes/S-03/README.md`, aprovado). Código: `RackyPlatform/PeerAuth/` (`PeerCredentials`, `CodeIdentity`, `PeerAuthPolicy`, `PeerAuthenticator`), leitura no `accept` em `UDSListener`, decisão em `rackyd/DaemonServer.swift` (`authorize`).

## Comportamento

Na aceitação, antes de ler o `hello`:

1. `getpeereid`/`LOCAL_PEERTOKEN`/`LOCAL_PEERPID` são lidos do socket no `accept`.
2. uid do peer == uid do daemon, **sempre**.
3. O modo vem da assinatura do próprio daemon (`PeerAuthPolicy.resolve`):

| Daemon | Build | Política | Efeito |
|---|---|---|---|
| assinado com certificado (identidade local, efêmera de CI, Developer ID) | qualquer | `signed` | exige `identifier "app.racky.mac" and certificate leaf = H"<folha do daemon>"` via `SecCodeCheckValidity` no audit token |
| ad-hoc | flag de compilação `RACKY_ALLOW_ADHOC_PEERS` | `adhoc-development` | só uid. É o modo do dono até rodar `scripts/make-dev-cert.sh` |
| ad-hoc | sem a flag | `deny-all` | recusa todos e loga o motivo na subida |
| assinatura ilegível | qualquer | `deny-all` | idem |

4. Recusa: `error{code:"peerRejected", message:"peer not authorized: <categoria>"}` sem `id`, conexão fechada, log `app.racky.ptyd`/`auth` (motivo detalhado com `privacy: .private`). Código novo no protocolo, com fixture `v1/error-peerRejected.json` e spec 06/08 atualizadas.

Flag de compilação (nunca variável de ambiente nem argumento): `Package.swift` a define para o alvo `rackyd` só em `debug` (é o que faz o `swift test` rodar em modo ad-hoc); `scripts/build.sh` passa `-Xswiftc -DRACKY_ALLOW_ADHOC_PEERS` **somente** quando assina ad-hoc. Com certificado a flag não é passada e, mesmo que fosse, daemon assinado ignora o modo uid-only. `build.sh` também ganhou `RACKY_SIGN_KEYCHAIN` (assinar por nome em keychain efêmero; ver achado 2 do S-03).

Quando o dono rodar `make-dev-cert.sh` e `build.sh`, o daemon passa sozinho para `signed`; nada a configurar.

## Testes (todos passam: `swift test` = 460 testes, 0 falhas; `scripts/lint.sh` OK)

- `PlatformTests/PeerAuthTests` (12): credenciais reais (uid, pid, token de 32 bytes), uid igual aceito no modo ad-hoc, **uid diferente simulado** (daemon esperando outro uid) recusado em todos os modos, sem credenciais, `deny-all`, sem token, requisito malformado, o processo de teste (xctest) recusado contra o requisito do app e aceito contra o próprio, derivação da política (assinado ignora a flag; ad-hoc exige opt-in).
- `DaemonTests/PeerAuthDaemonTests` (2), com o `rackyd` real copiado e assinado com certificados efêmeros gerados no teste (keychains temporários, sem tocar login nem lista de keychains): daemon assinado com A aceita só `peerprobe` assinado com A e id `app.racky.mac`; recusa com `peerRejected` o helper `app.racky.cli` (mesma folha), outro certificado B, ad-hoc e o próprio xctest; segue aceitando o app depois. Daemon ad-hoc em modo desenvolvimento aceita peers do mesmo uid.
- `ProtocolTests`: fixture do novo código de erro.

## Evidência [L] (`daemon.auth`)

- `release-adhoc-modes.out`: daemon do `build.sh` ad-hoc (Release, com flag): `peer auth: ad-hoc development mode (uid only)`, peer aceito. Release ad-hoc sem flag: `DENY ALL`, peer recusado com `peerRejected`, logs de recusa.
- `ci-recipe-ephemeral.out`: receita de CI completa neste Mac: `make-dev-cert.sh --ephemeral` + `RACKY_SIGN_KEYCHAIN=… build.sh` (DR `identifier "app.racky.ptyd" and certificate leaf = H"…"`), daemon do bundle em modo `signed`: peer assinado com o mesmo certificado e id do app aceito, peer ad-hoc recusado, logs `auth`; keychain removido e lista de keychains restaurada. As linhas de motivo aparecem como `<private>` no `log show` (por desenho, AR-601).

Nada foi instalado no keychain de login e nenhuma senha foi pedida.

## Limites e pendências

- O app (T1-xx de UI/launch) ainda precisa ser assinado com `app.racky.mac` e a mesma identidade do daemon (já é o que `build.sh` faz).
- O `ctl`/helper `racky` não fala com o daemon (AR-503): continua recusado por desenho.
- Ativação por launchd (T1-24) não muda a checagem: ela usa o fd aceito, igual ao `bind` direto.
