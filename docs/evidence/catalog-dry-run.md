# T2-10 catalog dry-run (real user folders, read-only)

Only names and counts. No file bodies, paths or frontmatter text.

## Sources

| Source | Present | Items | Invalid |
|---|---|---|---|
| `~/.claude/agents` | yes | 13 | 0 |
| `~/.claude/skills` | yes | 131 | 0 |
| `~/.agents/skills` | yes | 44 | 0 |
| `~/.codex/agents` | yes | 12 | 0 |
| `~/.codex/skills` | yes | 3 | 0 |
| `plugin vercel agents` | yes | 3 | 0 |
| `plugin vercel skills` | yes | 37 | 0 |

Absent sources: `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `plugin swift-lsp agents`, `plugin swift-lsp skills`

## Totals

- agents/skill: 44
- claude/agent: 13
- claude/skill: 131
- codex/agent: 12
- codex/skill: 3
- plugin/agent: 3
- plugin/skill: 37
- total items: 243
- items with invalid frontmatter/TOML: 0
- name conflicts (same kind and name, same client): 4
- shadowed items: 4
- agents out of sync between `.md` and `.toml`: 1

## Names

### agents/skill (44)

ask-matt, claude-handoff, code-review, codebase-design, design-an-interface, diagnosing-bugs, domain-modeling, edit-article, find-skills, git-guardrails-claude-code, grill-me, grill-with-docs, grilling, handoff, implement, improve-codebase-architecture, loop-me, migrate-to-shoehorn, obsidian-vault, orchestration, prototype, qa, request-refactor-plan, research, resolving-merge-conflicts, rti-crawler-builder, rti-ui, scaffold-exercises, setup-matt-pocock-skills, setup-pre-commit, setup-ts-deep-modules, tdd, teach, to-spec, to-tickets, triage, ubiquitous-language, wayfinder, webscraping-expert, wizard, writing-beats, writing-fragments, writing-great-skills, writing-shape

### claude/agent (13)

data-engineer, llm-engineer, ocr-engineer, qa-engineer, rti-analyst, rti-crawler-builder, security-diff-reviewer, swift-desktop-optimizer, swiftui-ux-designer, ui-mockup-designer, web-scraper, webscraper-engineer, webscraping-expert

### claude/skill (131)

racky, apk-redteam-pipeline, ask-matt, bb-local-toolkit, bb-methodology, bug-bounty, bugcrowd-reporting, claude-handoff, cloud-iam-deep, code-review, codebase-design, cyber-web-pentest, cyber-web-pentest, design-an-interface, diagnosing-bugs, domain-modeling, edit-article, enterprise-vpn-attack, evidence-hygiene, git-guardrails-claude-code, grill-me, grill-with-docs, grilling, handoff, humanizer, hunt-api-misconfig, hunt-aspnet, hunt-ato, hunt-auth-bypass, hunt-brute-force, hunt-business-logic, hunt-cache-poison, hunt-captcha-bypass, hunt-cicd, hunt-clickjacking, hunt-cloud-misconfig, hunt-cors, hunt-csrf, hunt-deserialization, hunt-dispatch, hunt-dom, hunt-exceptional-conditions, hunt-file-upload, hunt-forgot-password, hunt-graphql, hunt-grpc, hunt-host-header, hunt-html-injection, hunt-http-smuggling, hunt-idor, hunt-jwt-crypto, hunt-k8s, hunt-laravel, hunt-ldap, hunt-lfi, hunt-llm-ai, hunt-mfa-bypass, hunt-misc, hunt-nextjs, hunt-nodejs, hunt-nosqli, hunt-ntlm-info, hunt-oauth, hunt-open-redirect, hunt-race-condition, hunt-rag-vector, hunt-rce, hunt-saml, hunt-session, hunt-shadow-api, hunt-sharepoint, hunt-source-leak, hunt-spa-api, hunt-springboot, hunt-sqli, hunt-ssrf, hunt-ssti, hunt-subdomain, hunt-tls-network, hunt-websocket, hunt-xss, hunt-xxe, implement, improve-codebase-architecture, ios-redteam-pipeline, loop-me, m365-entra-attack, meme-coin-audit, mid-engagement-ir-detection, migrate-to-shoehorn, motion-designer, motion-designer, obsidian-vault, offensive-osint, okta-attack, osint-methodology, prototype, qa, recon-scope-triage, redteam-mindset, redteam-report-template, report-writing, request-refactor-plan, research, resolving-merge-conflicts, rti-crawler-builder, rti-ui, scaffold-exercises, security-arsenal, setup-matt-pocock-skills, setup-pre-commit, setup-ts-deep-modules, supply-chain-attack-recon, tdd, teach, to-spec, to-tickets, triage, triage-validation, ubiquitous-language, vmware-vcenter-attack, wayfinder, web2-recon, web3-audit, webscraping-expert, webscraping-expert, wizard, writing-beats, writing-fragments, writing-great-skills, writing-shape

### codex/agent (12)

data-engineer, llm-engineer, ocr-engineer, qa-engineer, rti-analyst, rti-crawler-builder, security-diff-reviewer, swift-desktop-optimizer, ui-mockup-designer, web-scraper, webscraper-engineer, webscraping-expert

### codex/skill (3)

frontend-design, web-design-guidelines, webscraping-expert

### plugin/agent (3)

vercel:ai-architect, vercel:deployment-expert, vercel:performance-optimizer

### plugin/skill (37)

vercel:access-protected-vercel-deployment, vercel:ai-gateway, vercel:ai-sdk, vercel:auth, vercel:bootstrap, vercel:build-agents, vercel:cdn-caching, vercel:chat-sdk, vercel:create-a-backend, vercel:custom-metrics, vercel:deployments-cicd, vercel:env-vars, vercel:eve, vercel:flags-sdk, vercel:knowledge-update, vercel:marketplace, vercel:microfrontends, vercel:next-cache-components, vercel:next-forge, vercel:next-upgrade, vercel:nextjs, vercel:queues, vercel:react-best-practices, vercel:routing-middleware, vercel:runtime-cache, vercel:shadcn, vercel:turbopack, vercel:vercel-agent, vercel:vercel-cli, vercel:vercel-connect, vercel:vercel-firewall, vercel:vercel-functions, vercel:vercel-sandbox, vercel:vercel-services, vercel:vercel-storage, vercel:verification, vercel:workflow

## Conflicts

- skill `cyber-web-pentest` (claude): 1 shadowed
- skill `motion-designer` (claude): 1 shadowed
- skill `webscraping-expert` (claude): 1 shadowed
- skill `webscraping-expert` (codex): 1 shadowed

## Out of sync with Codex agent

llm-engineer
