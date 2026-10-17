# Pacote de referência visual do Orca 1.4.219

Gerado por `scripts/extract-orca-reference.sh`. Não editar à mão.

| Campo | Valor |
|---|---|
| Versão do Orca | 1.4.219 (`package.json` dentro do `app.asar`) |
| Data da extração | 2026-10-17 (UTC) |
| Caminho do `app.asar` | `/Applications/Orca.app/Contents/Resources/app.asar` |
| Tamanho do `app.asar` | 125667563 bytes |
| SHA-256 do `app.asar` | `579d814bca0d04448414d07ac9547ca06b1c84ff9d008c98951fb6a91a066218` |
| Ferramenta de extração | `@electron/asar@4.3.1` (via `npx`) |
| CSS usado para os tokens | `out/renderer/assets/I18nProvider-b7VZ0bXG.css` (sha256 `7ee249f776f7b5497d08f92037eabbd09e0faaae7673377719fa6e56fbaf6dd2`) |

## Conteúdo

- `tokens/colors.json`: variáveis do tema escuro (`.dark`) e claro (`:root`), e a escala de cores do Tailwind.
- `tokens/typography.json`: famílias, `@font-face`, escala `--text-*`, tamanhos e pesos usados.
- `tokens/spacing.json`: base `--spacing` e as unidades das utilidades de padding, margin e gap.
- `tokens/radii.json`: `--radius` e os raios usados.
- `tokens/motion.json`: curvas `--ease-*`, animações, durações e atrasos usados.
- `source/index.json`: índice com tamanho e SHA-256 dos CSS do renderer. Os arquivos não são copiados.
- Pendentes de F0-3 (capturas com Gravação de Tela): `screens/`, `crops/` e `manifest.json`. Este script não os gera.

## Como recapturar os tokens

1. Instale o Orca 1.4.219 em `/Applications/Orca.app`.
2. Rode `scripts/extract-orca-reference.sh` (ou `scripts/extract-orca-reference.sh --asar <caminho>`).
3. O script aborta se a versão do `app.asar` não for 1.4.219. Ele só lê o arquivo: nada do Orca é executado.
4. Duas execuções sobre o mesmo `app.asar` geram os mesmos JSON byte a byte. Se o SHA-256 mudar, o diff dos tokens mostra o que mudou no Orca.

Divergências entre estes tokens e `docs/rebuild/spec/02-design-system.md` estão listadas em `docs/evidence/slice0/`.
