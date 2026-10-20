# T4-04 Observabilidade (AC-T17), smoke ao vivo

App Release isolado (`RACKY_HOME` temporario, `open -g -n`, daemon filho), build 209. Roteiro: `Settings > Diagnostics` (`diagnostics-page.png`),
`help.exportDiagnostics` mostra a lista de arquivos antes de salvar (`export-preview.png`, `export-files.txt`), log em disco redigido
(`logs-listing.txt`), metrica `boot.first_window` gravada (`metrics.txt`, 185 ms), `kill -9` do app e reabertura: aviso unico com "Copy Details"
(`last-crash.json`, `copy-details.json`, `crash-ui.txt`, `after-crash.png`); apos saida limpa o aviso nao volta.
Testes: LogRedactorTests, DiskLogTests, PerfTests, MetricStoreTests, CrashMonitorTests, DiagnosticsBundleTests (zip sem segredo), DiagnosticsControllerTests.
