// agentboxd-launch: launcher estável do LaunchAgent (T1-24, S-01).
//
// O launchd prende o job registrado ao cdhash do binário do `BundleProgram` (LWCR). Com o `agentboxd` como `BundleProgram`,
// toda atualização do app deixa o job em `spawn failed` até um `unregister`+`register` que (a) mata o daemon e (b) só
// funciona depois que o BTM atualiza o registro, o que leva minutos (S-01, `docs/evidence/spikes/S-01/`). Por isso o job é
// registrado com ESTE binário, que quase nunca muda (cdhash estável: sem dependências, sem caminhos embutidos, símbolos
// removidos por scripts/build.sh), e ele só faz `exec` do `agentboxd` ao lado, com os mesmos argumentos. O daemon novo
// entra na próxima conexão ao socket, sem novo registro. O descritor do socket do launchd (fd 3) é herdado pelo `exec`.
//
// Não altere este arquivo sem necessidade: mudar o launcher muda o cdhash e exige re-registro (o app faz sozinho, com o
// daemon parado).

#include <limits.h>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    (void)argc;
    char executable[PATH_MAX];
    uint32_t size = (uint32_t)sizeof executable;
    if (_NSGetExecutablePath(executable, &size) != 0) return 70;
    char resolved[PATH_MAX];
    if (realpath(executable, resolved) == NULL) return 70;
    char target[PATH_MAX];
    if (snprintf(target, sizeof target, "%s/agentboxd", dirname(resolved)) >= (int)sizeof target) return 70;
    argv[0] = target;
    execv(target, argv);
    perror("agentboxd-launch: exec agentboxd");
    return 70;
}
