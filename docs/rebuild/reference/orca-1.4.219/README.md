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

## Estado da F0-3 (captura visual)

**Status: pendente de captura.** `manifest.json` existe com `records: []` e a lista do que falta. Nenhum PNG foi gravado.

- **Motivo:** a captura passiva não produziu tela utilizável. O Stage Manager está ligado (`com.apple.WindowManager GloballyEnabled=1`) e a janela do Orca (CGWindowID 125, `kCGWindowOwnerName` = `Orca`) aparece só como miniatura de 143x160 pt em (15, 669), com distorção 3D. Uma captura assim não serve de referência de medida, então não foi salva.
- **Não feito (depende do dono):** `screens/<tela>/<estado>@1440x900.png` e `@760x480.png`, `crops/`, `tokens/measured-layout.json`, a comparação de medidas com `02-design-system.md` §5 e `03-screens.md` §1 e a lista de divergências. Nenhuma medida foi inventada: sem captura, não há valor medido para comparar.
- **Para destravar:** o dono deixa a janela do Orca em tela normal, com tema escuro, em 1440x900 e depois em 760x480 (pode ser com o Stage Manager desligado). Com ela visível, uma sessão recaptura com `screencapture -x -o -l <windowID>` (PNG @2x), gera os recortes com PIL e grava as medidas em pontos (pixels / 2).
- **Fixtures:** os estados que exigem projetos, sessões e panes de exemplo (05 §0.3) também ficam para essa sessão, porque exigem manipular o Orca.
- **Já feito e válido:** tokens em `tokens/` (extraídos do `app.asar`, sem captura).

## Captura fornecida pelo dono (2026-10-16)

`screens/owner/main-session-topleft@2x.png` — screenshot do Orca 1.4.219 feita pelo dono (2000×795 px, @2x ⇒ 1000×397.5 pt), recorte superior-esquerdo da janela principal: titlebar com semáforos, nome "Orca", toggle da sidebar e voltar/avançar; Search, Tasks, Automations, Orca Mobile; seção Projects com ações; cards de worktree (bolinha de status, nome, branch, badge `primary`, badge de erro `rename failed`, linha de atividade do agente com tempo); tab row (tab ativa com status + logo do Claude + nome + fechar, botão +), "▷ Command" e toggle do painel direito; ícones do canto do pane. É a referência visual primária até a sessão de captura com o dono (Stage Manager impediu a captura passiva).
