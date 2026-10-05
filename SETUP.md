# SETUP — průvodce prvotním nastavením (provádí AI agent)

> **Pro koho:** tenhle soubor čte **AI agent** (Claude Code, Codex, Copilot, Antigravity), když si
> kolega čerstvě naklonuje BCALInsights a otevře v něm svůj AI nástroj. Spouští ho `AGENTS.md`
> (Claude Code přes `.claude/CLAUDE.md`); ručně stačí napsat „proveď SETUP.md". Referenční detaily (snippety
> konfigů per nástroj, proč co jak) jsou v `README.md` (sekce „Nový stroj / kolega") a
> `mcp-setup.md` — tady je pořadí kroků, otázky a kontroly.

## Pravidla průvodce

- Mluv česky a tykej (dokud si uživatel v kroku 7 neřekne jinak), stručně. Na začátku řekni, co
  ho čeká: 9 kroků, ~15 minut, jde kdykoli přerušit a pustit znovu — kroky jsou idempotentní.
- **Jedna otázka naráz**, počkej na odpověď. Co jde zjistit samo (cesty, verze, existující
  soubory), zjisti a nech jen potvrdit.
- **Před každým zápisem mimo tenhle repo** (junction, always-on soubor, MCP konfig, npm instalace)
  ukaž přesně co a kam a počkej na souhlas. Existující obsah souborů nech být — připisuj,
  nepřepisuj. Před editací JSON / TOML konfigu udělej zálohu `<soubor>.bak`.
- Co už existuje a sedí, **přeskoč a řekni to**. Co existuje a nesedí (junction vede jinam,
  konfig má jiný tvar), ukaž a zeptej se.
- **PAT nikdy nečti, nevypisuj a neříkej si o něj do chatu.** Uživatel ho uloží do souboru
  sám; ty ověřuješ jen, že soubor existuje a není prázdný.
- Zjištěné hodnoty dosazuj všude dál: `<KLON>`, `<PRACOVNÍ-REPA>`, `<NÁSTROJE>`, `<MCP_PAT>`.
- Windows příkazy (junction, `claude mcp add … cmd /c …`) spouštěj přes **PowerShell**. Git Bash
  (Bash tool Claude Code) přepisuje argumenty začínající `/` (`/c` → `C:/`, `/J` …) a příkaz se
  tiše pokazí (7.2b v `bc-al-tools.md`).
- Průběžně veď checklist ✅ / ⏭️ (přeskočeno, už bylo) / ❌ a na konci ho celý ukaž.

## Krok 1 — Prostředí

Zjisti a ukaž: OS (Windows / WSL), `git --version`, `node --version` (≥ 18), `npm prefix -g`
(ta cesta musí být v `PATH`), `dotnet --version` (≥ 8, potřebuje `al-mcp-server`) a ve kterém
AI nástroji právě běžíš.

Chybí-li něco, nabídni instalaci a spusť ji až po souhlasu: `winget install Git.Git`,
`winget install OpenJS.NodeJS.LTS`, `winget install Microsoft.DotNet.SDK.8`. Nový `PATH` uvidí až
nový terminál / nová seance — řekni to a případně pokračuj po restartu (průvodce jde pustit znovu).

## Krok 2 — Klon (`<KLON>`)

- `<KLON>` = kořen tohohle repa (`git rev-parse --show-toplevel`); ověř, že existuje
  `skills/bc-al/SKILL.md`. Řekni cestu a nech potvrdit. Klon může být kdekoli, ale **teď je
  poslední chvíle ho přesunout** — junctiony z kroku 5 by po přesunu vedly do prázdna.
- `git remote -v` → `origin` = `https://github.com/essencebs/BCALInsights.git`; `git pull --ff-only`.

## Krok 3 — „Kde máš složku s repozitáři?" (`<PRACOVNÍ-REPA>`)

Zeptej se, ve které složce má (nebo bude mít) klony `cust-*-bc` / `prod-*-bc` (např.
`C:\WorkTasks`). Ověř, že existuje (jinak nabídni založení), a pro kontrolu vypiš pár nalezených
`cust-*` / `prod-*`. Prázdná složka je OK. Agent ji pak používá na sibling repa, sdílenou
`.alpackages` a zdroje závislých appek.

## Krok 4 — „Které AI nástroje používáš?" (`<NÁSTROJE>`)

Nabídni Claude Code, GitHub Copilot (VS Code), Copilot CLI, Codex, Antigravity — víc najednou je
OK, nástroj, ve kterém běžíš, předvyplň. Kroky 5, 6 a 8c dělej pro každý zvolený nástroj.

## Krok 5 — Junction skillů

| Nástroj | Junction (`<CESTA>`) | → cíl |
|---|---|---|
| Claude Code | `%USERPROFILE%\.claude\skills\bcal-insights` | `<KLON>` (celé repo = plugin `bcal-insights@skills-dir`) |
| Copilot (VS Code, CLI), Codex | `%USERPROFILE%\.agents\skills` | `<KLON>\skills` (jeden junction pro všechny tři) |
| Antigravity | `%USERPROFILE%\.gemini\config\skills` | `<KLON>\skills` |

```powershell
New-Item -ItemType Directory -Force (Split-Path "<CESTA>") | Out-Null
New-Item -ItemType Junction -Path "<CESTA>" -Target "<CÍL>"
```

- `<CESTA>` existuje → `(Get-Item "<CESTA>").Target`: míří na `<CÍL>` = ⏭️; jinam = ukaž a zeptej
  se. Je to **běžná složka s jinými skilly** → nemaž ji, nabídni junction per skill
  (`<CESTA>\<skill>` → `<KLON>\skills\<skill>` pro každou podsložku `skills/`).
- Junction nepotřebuje admin práva. Kontrola: `Test-Path "<CESTA>\bc-al\SKILL.md"` (u Claude
  Code `"<CESTA>\skills\bc-al\SKILL.md"`).

## Krok 6 — Startup pravidlo do always-on souborů

| Nástroj | Always-on soubor |
|---|---|
| Claude Code | `%USERPROFILE%\.claude\CLAUDE.md` |
| Copilot (VS Code) | `%APPDATA%\Code\User\prompts\bc-al-notes.instructions.md` (+ frontmatter `applyTo: "**/*.al"` z README) |
| Copilot CLI | `%USERPROFILE%\.copilot\copilot-instructions.md` (jen odkaz na soubor VS Code, viz README) |
| Codex | `%USERPROFILE%\.codex\AGENTS.md` |
| Antigravity | `%USERPROFILE%\.gemini\GEMINI.md` (agent ve WSL → přidej k cestám i variantu `/mnt/c/…`) |

Vezmi „Šablonu startup pravidla" z `README.md`, dosaď `<KLON>`, `<SKILL-DIR>` a `<RUČNĚ>`
(tabulka pod šablonou) a `<PRACOVNÍ-REPA>`. Ukaž výsledný text a po souhlasu ho **připiš na
konec** souboru (neexistuje → založ). Pravidlo tam už je (hledej `Povinný startup pro AL`) →
ukaž rozdíl a zeptej se, jestli ho aktualizovat.

## Krok 7 — „Jak se mnou chceš mluvit?"

Zeptej se na jazyk (čeština, angličtina…) a tón (tykání a pohoda / věcně a formálně…). Zapiš to
jako krátkou sekci `## Jazyk a tón` do stejných always-on souborů jako v kroku 6 — je to osobní
preference, do repa nepatří. Od teď mluv podle ní.

## Krok 8 — MCP servery

### 8a — npm balíčky

Ukaž příkaz a proč globálně (`mcp-setup.md`, krok 1 — `npx` nestihne 30s handshake):

```
npm i -g al-mcp-server bc-code-intelligence-mcp @azure-devops/mcp @demiliani/d365bc-admin-mcp
```

`@demiliani/d365bc-admin-mcp` je volitelný (potřebuje admin roli v BC tenantech zákazníků) —
zeptej se. Po souhlasu spusť a ověř `npm ls -g --depth=0`.

### 8b — „Máš PAT do Azure DevOps?" (složka `MCP_PAT`)

1. Navrhni `<MCP_PAT>` = `<PRACOVNÍ-REPA>\MCP_PAT` (jiné místo je OK). Podmínky: **mimo git
   repo** (`git -C "<MCP_PAT>" rev-parse --show-toplevel` musí selhat) a mimo OneDrive / sdílené
   složky — je v ní token.
2. Založ složku a zkopíruj do ní launcher `<KLON>\setup\ado-mcp.mjs`. Už tam je a liší se →
   ukaž diff a zeptej se, jestli přepsat.
3. Nemá PAT → proveď ho založením tokenu: `https://dev.azure.com/essencebs/_usersSettings/tokens` →
   **New Token**, organizace `essencebs`, expirace max. 90 dní (firemní policy), scopes **jen
   Read**: Work Items, Code, Build, Wiki, Project and Team, Identity. **Žádný Write** — zápisy do
   ADO a PR dělá člověk, read-only je záměrná zábrana (7.9 v `bc-al-tools.md`).
4. „Ulož ho do `DevOpsPAT.txt` ve složce `MCP_PAT`": založ prázdný `<MCP_PAT>\DevOpsPAT.txt` a
   otevři ho uživateli (`notepad "<MCP_PAT>\DevOpsPAT.txt"`). Do souboru patří **jen surový PAT
   na jednom řádku** — bez e-mailu a bez base64, launcher si ho zakóduje sám. Výslovně řekni:
   **nevkládej ho do chatu**.
5. Až řekne hotovo, ověř bez čtení obsahu: `(Get-Item "<MCP_PAT>\DevOpsPAT.txt").Length -gt 0`.

Launcher při každém startu MCP serveru (= start seance AI nástroje) přečte `DevOpsPAT.txt` vedle
sebe, předá token serveru `@azure-devops/mcp` (org `essencebs`) a řeší i IPv6 reset na corp síti.
Token tak není v žádném konfigu a všechny nástroje sdílí jeden soubor.

### 8c — Registrace per nástroj

- **Claude Code** (scope `user` = všechna repa; přes PowerShell, viz pravidla nahoře):

  ```
  claude mcp add -s user al-mcp-server -- cmd /c al-mcp-server
  claude mcp add -s user bc-code-intelligence -- cmd /c bc-code-intelligence-mcp
  claude mcp add -s user azure-devops -- node "<MCP_PAT>\ado-mcp.mjs"
  claude mcp add -s user d365bc-admin -- cmd /c d365bc-admin-mcp
  ```

  (poslední jen když v 8a chtěl `d365bc-admin`). Do `%USERPROFILE%\.claude\settings.json` přimerguj
  `"env": { "MCP_TIMEOUT": "90000" }` (`mcp-setup.md`, krok 4) — ostatní obsah souboru zachovej.
- **Copilot (VS Code / CLI), Codex, Antigravity:** snippety v `README.md`, sekce daného nástroje.
  `azure-devops` je všude `node` + `<MCP_PAT>\ado-mcp.mjs`, bez `env` a bez tokenu.
- Server se jménem `azure-devops` už existuje a má token v `env` (`PERSONAL_ACCESS_TOKEN`, starý
  způsob) → nabídni přepnutí na launcher: PAT ulož do `DevOpsPAT.txt` (8b) a záznam nahraď.

## Krok 9 — Ověření a shrnutí

- **Claude Code:** `claude plugin validate "<KLON>"`, `claude plugin details bcal-insights`,
  `claude mcp list` (všechny `✔ Connected`; `postman` / `claude.ai …` „Needs authentication" jsou
  jiné pluginy, ignoruj).
- **Ostatní nástroje:** podle jejich sekce v `README.md` (`/mcp` v Codexu a Copilot CLI, ve VS Code
  „MCP: List Servers").
- Řekni, ať **nástroj restartuje** — skilly, always-on soubory i MCP servery se načtou až v nové
  seanci. Po restartu ať v libovolném BC repu zkusí `/bc-al` (Codex `$bc-al`, Antigravity „bc-al"
  jménem) a „vidíš ticket <číslo>?" (Azure DevOps `wit_work_item` get). 401 na zápis do ADO je
  správně.
- Ukaž celý checklist ✅ / ⏭️ / ❌ a co zbývá udělat ručně.
- Na rozloučenou údržba:
  - `git pull` v `<KLON>` stačí, junctiony míří na živé soubory.
  - PAT vyprší (max. 90 dní) → nový přepsat do `<MCP_PAT>\DevOpsPAT.txt` + restart seance.
  - Občas `npm update -g`.
  - Když se v repu změní `setup/ado-mcp.mjs`, zkopírovat ho znovu do `<MCP_PAT>`.
