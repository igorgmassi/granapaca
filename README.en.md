<div align="center">

# GranaPaCá

**All your bank accounts in one place, on your device or on your own machine.**

Open source, local-first, self-hosted personal finance app for Brazil: start right on your phone or computer with no server, or run your own instance with Open Finance through Pluggy and optional free-tier AI.

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
![Status: active development](https://img.shields.io/badge/status-active%20development-brightgreen)
[![secret-scan](https://github.com/igorgmassi/granapaca/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/igorgmassi/granapaca/actions/workflows/secret-scan.yml)

[Português](README.md) · [Web demo](https://igorgmassi.github.io/granapaca/) · [Ways to use](#ways-to-use-from-zero-setup-to-self-hosted) · [Architecture](#architecture) · [Roadmap](#roadmap) · [Security](SECURITY.md) · [Contributing](CONTRIBUTING.md)

</div>

> [!NOTE]
> **Active development — MVP implemented.** The backend (.NET 10 + PostgreSQL 18), the Docker Compose stack with Tailscale and encrypted backup guides, the YAML onboarding profiles catalog ([`profiles/`](profiles/)), and the Flutter app with a [browsable web demo](https://igorgmassi.github.io/granapaca/) are already working in this repository. Post-MVP features are actively being built.

## What it is

GranaPaCá brings your personal finances together in one place — balances, statements, credit cards, bills, budgets, and goals — with no central server and no data harvesting. Deterministic rules and the **Paçoca** assistant categorize transactions and answer questions about your money, always showing the exact numbers and period used.

You can start **right on your own device without installing Docker or a database**, or run **your own instance (self-hosted, single-tenant)** with your own Pluggy and optional AI provider credentials. There is no central server: whoever maintains the project has no access to anyone's data.

## Ways to use (from zero-setup to self-hosted)

Start as simply as you want today and grow later without losing your history ([ADR-030](docs/adr/0030-modo-local-no-aparelho-e-ia-gratuita.md), in Portuguese):

1. **On this device only (no server):** open the app, store everything encrypted on your own phone or computer, lock with PIN/biometrics, import OFX/CSV statements or NFC-e receipts, log expenses on the spot, and export/restore a JSON backup in one tap — **zero Docker, zero PostgreSQL, and no paid AI account required**.
2. **Explore the demo:** try the full app right in your browser ([web demo on GitHub Pages](https://igorgmassi.github.io/granapaca/)) without installing anything, using 100% synthetic data.
3. **Your own instance (Docker Compose):** for automatic daily bank sync through Open Finance (Pluggy), multiple synced devices, and encrypted daily off-machine backups with `restic`. See [Running your own instance](#running-your-own-instance).

## Principles

- **Privacy first.** Data stays on your device or in your instance, secrets never reach the app, and nothing goes to an AI provider without minimization.
- **Read-only.** The app never initiates payments or moves money.
- **AI as an assistant, not a decision-maker.** Every classification comes with an explanation and can be corrected; rules suggested by AI only apply after you confirm them.
- **Non-judgmental labels.** Three levels of essentiality: Essential, Important and Flexible.
- **Bank data preserved.** Corrections live in their own layer, with history, and the daily sync never erases a correction.
- **Secure by default.** There are no default credentials, and the system refuses to start without a master key and a strong password.

## Features

| Area | What it does | Status |
|---|---|---|
| On this device only | Encrypted local database on your phone or computer, PIN/biometric lock, quick expense entry, OFX/CSV and NFC-e import, and one-tap JSON backup/restore — no server required | Evolving ([ADR-030](docs/adr/0030-modo-local-no-aparelho-e-ia-gratuita.md)) |
| Demo mode | Try it in the browser ([GitHub Pages demo](https://igorgmassi.github.io/granapaca/)) or in the app with 100% synthetic data, no bank connection needed | Available (MVP) |
| Accounts and banks | Connection through Meu Pluggy, automatic synthetic mode, consolidated and per-bank statements, cards/bills and daily sync | Available (MVP) |
| Rule-based categorization | Layered deterministic engine (manual corrections, user rules, profile rules and system rules), review queue, history and undo | Available (MVP) |
| Charts | Donut by category, ranking of the heaviest categories and essentiality breakdown | Available (MVP) |
| Onboarding guide | YAML catalog ([`profiles/`](profiles/)) by occupation, household and commute generating explained essentiality rules | Available |
| Security and operations | TOTP 2FA, opaque tokens with rotating refresh, envelope field encryption, encrypted offline cache, in-app alerts inbox and encrypted `restic` backups | Available |
| Import and export | OFX/CSV file import (available); CSV, XLSX, PDF export and full JSON backup | Partial (post-MVP) |
| Cash | Quick entry of cash expenses, working offline | Post-MVP |
| Paçoca assistant & AI | Free offline local deterministic engine by default; optional generative AI via free tiers (Google Gemini Flash, Groq, OpenRouter `:free`), local Ollama, or paid providers, always with minimization and pseudonymization | Post-MVP |
| Receipts and NFC-e | Per-file encrypted local volume storage, deterministic NFC-e XML/QR parser (ES first) and optional AI vision fallback | Post-MVP |
| Planning and alerts | Budgets, goals, projections, forgotten subscriptions and optional push notifications via `ntfy` | Post-MVP |

### Paçoca assistant & AI (no paid AI account required)

You **do not need any paid AI account** to use GranaPaCá:

- **Free and offline by default:** Paçoca works with zero accounts and zero internet using the local deterministic engine (layered rules + financial Q&A covering balances, categories, merchants, budgets, goals, 50/30/20 breakdown, projections, and subscriptions), both on-device and in the backend (`provider = "none"`).
- **Optional free-tier or local generative AI:** if you want generative answers, ready-made presets support **Google Gemini Flash** (free tier via Google AI Studio), **Groq** (free OpenAI-compatible tier), **OpenRouter** (`:free` models), and local **Ollama** (100% free on your own machine), alongside OpenAI and Anthropic.
- **Privacy preserved even on free tiers:** every external request goes through mandatory PII minimization and reversible pseudonymization ([ADR-023](docs/adr/0023-minimizacao-e-pseudonimizacao-ia.md)), stripping CPF, CNPJ, account numbers, emails, and phone numbers, paired with a clear notice about third-party free-tier retention policies before you enable a key.

## Architecture

```mermaid
flowchart LR
  app["Flutter app<br/>Android · iOS · Windows · macOS · Linux<br/>encrypted local mode or offline cache"]
  demo["Web demo<br/>Flutter Web on GitHub Pages<br/>synthetic data, no backend"]

  subgraph instance["Your optional instance (Docker Compose)"]
    api["Backend<br/>.NET 10 · ASP.NET Core<br/>modular monolith"]
    db[("PostgreSQL")]
    files[("Receipts<br/>encrypted volume")]
  end

  pluggy["Pluggy<br/>Open Finance"]
  ai["AI providers (optional)<br/>Google Gemini · Groq · OpenRouter<br/>Ollama · OpenAI · Anthropic"]

  app -- "optional: private network (Tailscale)" --> api
  api --> db
  api --> files
  api -- "read-only" --> pluggy
  api -- "minimized data" --> ai
```

In **On this device only** mode, the app keeps everything encrypted locally and runs deterministic Paçoca offline with no server at all. With **your own instance**, only the backend talks to Pluggy and optional AI providers, so secrets never reach the app and the API stays on a private network (Tailscale) by default. The **web demo** runs entirely in the browser with no backend.

## Reference stack

| Layer | Technology |
|---|---|
| App (mobile, desktop and web demo) | Flutter and Dart 3 (serverless encrypted local mode, offline cache and web demo) |
| Backend (optional self-hosted instance) | .NET 10 (LTS) and ASP.NET Core, as a modular monolith |
| Data | Encrypted on-device storage; PostgreSQL 18, Dapper and DbUp on the instance |
| AI | Free local deterministic engine (default) + optional typed HTTP clients (Google Gemini Flash, Groq, OpenRouter, Ollama, OpenAI and Anthropic) |
| Banking integration | OFX/CSV and NFC-e import on-device; Pluggy (Meu Pluggy) on the instance |
| Infrastructure | Docker Compose (amd64 and arm64), Tailscale, optional Caddy and restic backups |
| Quality | GitHub Actions, xUnit, Testcontainers, ArchUnitNET and flutter_test |

All 30 architecture decisions are recorded as ADRs in [`docs/adr`](docs/adr) (in Portuguese), and any change to the stack needs a new ADR.

## Roadmap

1. **Phase 0, Foundation (completed):** repository, CI, security baseline, multi-arch Docker Compose and app and backend skeletons.
2. **Phase 1, Browsable demo (completed):** Flutter Web with synthetic data, published on GitHub Pages.
3. **Phase 2, Real data (completed):** Pluggy connection (plus synthetic mode), daily sync, OFX/CSV import and per-bank statements.
4. **Phase 3, MVP (completed):** rule-based categorization and YAML profiles, manual correction with history, review queue, alerts inbox, TOTP 2FA, encrypted offline cache and charts.

After the MVP come cash entries, AI with minimization and pseudonymization, receipts and NFC-e invoices, planning (budgets, goals and projections), push via `ntfy` and full export.

## Running your own instance

> [!TIP]
> **Optional:** you only need a self-hosted instance if you want automatic Open Finance bank sync (Pluggy), multiple synced devices, or off-machine `restic` backups. For individual use with no server, just choose **On this device only** ("Só neste aparelho") when opening the app.

All you need is Docker with Compose v2, on `amd64` or `arm64`:

```bash
cd infra
./init-secrets.sh
cp .env.example .env
docker compose up --build --detach --wait
```

Verify that the API and database came up healthy:

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/api/v1/server-info
```

If `PLUGGY_CLIENT_ID` and `PLUGGY_CLIENT_SECRET` are left blank in `infra/.env`, the instance automatically starts in **Synthetic** mode (`"providerMode": "synthetic"`), so you can try the full flow without connecting real bank accounts. By default, the API binds only to `127.0.0.1:8080` and exposes no ports to the internet.

- **Full instance guide:** [`infra/README.md`](infra/README.md) (in Portuguese)
- **Private remote access (Tailscale) and optional Caddy:** [`infra/TAILSCALE.md`](infra/TAILSCALE.md)
- **Encrypted daily backups with `restic` and restore runbook:** [`infra/BACKUP.md`](infra/BACKUP.md)
- **YAML onboarding profiles catalog:** [`profiles/README.md`](profiles/README.md)
- **Try without installing anything:** [web demo on GitHub Pages](https://igorgmassi.github.io/granapaca/) (100% synthetic data, right in the browser)

Each person creates their own Pluggy account and connects their own banks in Meu Pluggy. That mode is for personal, non-commercial use; check Pluggy's current terms before using it.

## Security and privacy

- Never report a vulnerability in a public issue: use [private reporting](SECURITY.md).
- Never paste statements, screenshots, CPF numbers, account numbers, tokens or keys into issues, PRs or commits. Use synthetic data.
- The repository holds only code and documentation. Credentials live in each instance's `.env`, outside Git.

## Contributing

Documentation and issues are written in Brazilian Portuguese, but issues in English are welcome. Read the [contributing guide](CONTRIBUTING.md) and the [code of conduct](CODE_OF_CONDUCT.md).

## License

[GNU AGPL-3.0](LICENSE). You may use, study, modify and host GranaPaCá. Anyone who offers a modified version as a network service must make that version's source code available to its users.

GranaPaCá is not affiliated with Pluggy or any bank. Names mentioned belong to their respective owners.
