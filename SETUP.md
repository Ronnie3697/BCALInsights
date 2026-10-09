# SETUP — průvodce prvotním nastavením (provádí AI agent)

> **Pro koho:** tenhle soubor čte **AI agent** (Claude Code, Codex, Copilot, Antigravity), když si
> kolega čerstvě naklonuje BCALInsights a otevře v něm svůj AI nástroj. Spouští ho `AGENTS.md`
> (Claude Code přes `.claude/CLAUDE.md`); ručně stačí napsat „proveď SETUP.md". Referenční detaily (snippety
> konfigů per nástroj, proč co jak) jsou v `README.md` (sekce „Nový stroj / kolega") a
> `mcp-setup.md` — tady je pořadí kroků, otázky a kontroly.

## Pravidla průvodce

- Mluv česky a tykej (dokud si uživatel v kroku 7 neřekne jinak), stručně. Na začátku řekni, co
  ho čeká: 10 kroků, ~15 minut (+ ~25 minut stavby testovacího kontejneru na pozadí), jde kdykoli
  přerušit a pustit znovu — kroky jsou idempotentní.
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
(tabulka pod šablonou) a `<PRACOVNÍ-REPA>`; `<TEST-KONTEJNER>` zatím vynech — větu doplní krok 9. Ukaž výsledný text a po souhlasu ho **připiš na
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

## Krok 9 — „Chceš lokální kontejner na autotesty?" (`<PRACOVNÍ-REPA>\bc-test-container`)

Agent pouští autotesty repa v lokálním Docker kontejneru **po každém vyžádaném push** (nejdřív push, pak testy; 7.7b
v `bc-al-tools.md`) — PR buildy testy nespouští a nový test by poprvé běžel až na masteru po merge. Vysvětli to a zeptej se, jestli kontejner
chce. **K otázce rovnou řekni, co to stojí:**

- **RAM:** běžící kontejner si vezme ~7–8,5 GB (limit `memoryLimit` 8 GB) → v počítači doporučeno **≥ 16 GB**. Když se
  netestuje, jde zastavit (`docker stop bctest28`, RAM se uvolní) — `Test-Repo.ps1` si ho před testy nastartuje sám.
  Kdo pouští testy z víc seancí najednou a má ≥ 24–32 GB, může mít **pool dvou** (`bctest28b`, viz README nástroje) —
  jinak běhy čekají ve frontě na jeden kontejner.
- **Disk:** ~20–25 GB — Docker image BC ~11 GB, artefakty BC 28.4 ~3,6 GB, kontejner s databází jednotky GB, pracovní
  složka kontejneru ~1 GB. Počítej s **~30 GB volného** na `C:`.
- **Čas:** první stavba ~25 min (běží na pozadí); jeden běh testů repa 4–6 min (Zlomek 144 testů 3:45, konfigurátor
  ~900 testů ~5,5 min), jen po push.
- Instalace Docker Desktopu a členství v `docker-users` chtějí jednou admina.

**Odmítne → celý krok ⏭️** a do always-on souborů z kroku 6 připiš větu
`Lokální testovací kontejner: ne — autotesty nepouštěj (SETUP.md krok 9).` Agent pak autotesty **nepouští
nikdy**, nenabízí je a ani se na ně u push neptá (7.7b). **Přijme →** body 1–8 a nakonec do stejných souborů
`Lokální testovací kontejner: ano — <PRACOVNÍ-REPA>\bc-test-container\Test-Repo.ps1, autotesty po každém push (7.7b).`
Rozmyslí si to později → průvodce pusť znovu, krok 9 větu přepíše.

Šablona nástroje a jeho README: `<KLON>\setup\bc-test-container\`, detail a pasti 7.23 v `bc-al-build.md`.

1. **Zjisti a ukaž:** Docker Desktop (`Test-Path "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"`), mód
   (`docker version --format '{{.Server.Os}}'` = `windows`, když Docker běží), členství v `docker-users` **dvakrát** —
   v přihlašovacím tokenu (`whoami /groups`; z Git Bash `MSYS2_ARG_CONV_EXCL="*" whoami.exe /groups`) a ve skupině
   samotné (`net localgroup docker-users`; `Get-LocalGroupMember` u doménových účtů občas spadne), RAM (≥ 16 GB,
   kontejner si vezme ~8,5 GB) a volné místo na `C:` (~40 GB). Docker Desktop už běží a `docker version` odpoví →
   členství je v pořádku a bod 3 přeskoč (⏭️); mód rozhoduje `Server.Os` (bod 4).
2. **Chybí Docker Desktop** → nabídni `winget install Docker.DockerDesktop` (instalace chce admina a restart).
   Řekni, že licence Docker Desktopu je pro firmy nad 250 lidí / 10 M$ obratu placená.
3. **`docker-users` podle výsledku bodu 1** (nikomu neříkej, ať se přidá, dokud to neověříš):
   - v tokenu je → ✅, nic nedělej;
   - ve skupině je, v tokenu ne (přidaný, ale od té doby se neodhlásil) → **jen odhlásit / restart**, nic nepřidávat;
   - není ani ve skupině → to **udělá uživatel sám jako správce** (bezpečnostní nastavení systému, agent admin nemá
     ani ho nemá obcházet): PowerShell jako správce →
     `Add-LocalGroupMember -Group docker-users -Member "<celé jméno z whoami>"` → **odhlásit / restart** (členství je
     v přihlašovacím tokenu).

   U obou posledních upozorni, že odhlášení ukončí i seanci AI nástroje — po přihlášení průvodce pusť znovu (kroky
   jsou idempotentní), v Claude Code `claude --continue`. Bez členství v tokenu Docker Desktop hlásí *„checking group
   membership: user is not a member of the group"*.
4. **Docker v Linux módu** → `& "$env:ProgramFiles\Docker\Docker\DockerCli.exe" -SwitchWindowsEngine`.
5. **Nástroj:** zkopíruj `<KLON>\setup\bc-test-container\*` do `<PRACOVNÍ-REPA>\bc-test-container\` (existuje a liší
   se → ukaž rozdíl a zeptej se). Zapiš tam `settings.json` s `"patFile"` = `<MCP_PAT>\DevOpsPAT.txt` z kroku 8b
   (ostatní klíče — `containerName` `bctest28`, `containerNames` (pool), `version` `28.4`, `country` `cz`, `memoryLimit`
   `8G` — jen když chce jiné). Soubor piš nástrojem pro zápis souborů, ne Bash heredocem — ten sráží `\\` v JSON cestě na `\`.
6. `powershell -NoProfile -ExecutionPolicy Bypass -File "<PRACOVNÍ-REPA>\bc-test-container\Install-Helper.ps1"` —
   BcContainerHelper do `.\Modules` (bez admina; `Install-Module -Scope CurrentUser` do `Documents` umí selhat).
7. `New-TestContainer.ps1` stejně, **na pozadí** — první stavba ~25 min (artefakty + generic image). Mezitím pokračuj
   krokem 10. Varování *„does NOT have Full Control to C:\ProgramData\BcContainerHelper"* a k `hosts` jsou neškodná.
8. **Kontrola:** `docker ps` → kontejner `Up`; když má uživatel naklonované repo s testy, volitelně pilot
   `Test-Repo.ps1 -RepoPath <repo> -TestCodeunit <id jednoho test codeunitu>` (~5 min, končí `SUMMARY: … 0 failed`).

## Krok 10 — Ověření a shrnutí

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
  - Když se změní `setup/bc-test-container/`, zkopírovat `*.ps1` + `README.md` znovu do
    `<PRACOVNÍ-REPA>\bc-test-container\` (`Modules\`, `credential.xml` a `settings.json` zůstanou); BcContainerHelper
    občas aktualizovat `Install-Helper.ps1`.
