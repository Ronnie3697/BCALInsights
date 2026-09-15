# BCALInsights — poznámky z BC/AL praxe

Sbírka poznámek (known limitations, patterny, gotchas) pro vývoj Business Central
extensions v AL. Slouží jako **povinný kontext pro AI asistenty** (Claude Code,
GitHub Copilot, Codex, Antigravity) před jakoukoliv AL prací. Router „typ úkolu →
soubor / skill" a startup checklist drží **skill `skills/bc-al/SKILL.md`** —
jediný zdroj; always-on soubory jednotlivých nástrojů na něj jen odkazují.

| Soubor | Obsah |
|---|---|
| `bc-al-style.md` | konvence, naming, ToolTipy, přidělování ID, locale pasti, moderní patterny (sekce 1, 10) |
| `bc-al-ui.md` | UI patterny stránek — RunModal/RoleCenter, ConfirmManagement, factbox, CaptionClass, Visible, MultiLine/RichContent (sekce 4) |
| `bc-al-data.md` | database operace, event subscribery (sekce 2, 3) |
| `bc-al-objects.md` | specifické objekty/API — No. Series, Item Tracking, Attached to Line No., Requisition Line… (sekce 5) |
| `bc-al-integrations.md` | Shopify Connector, HttpClient na SaaS, SecretText/Isolated Storage, Business Events / Power Automate (5.y2, sekce 11) |
| `bc-al-workflow.md` | lokalizace/XLIFF, dokumentace vč. uživatelské příručky, verifikace (sekce 6, 8, 9, 12) |
| `bc-al-tools.md` | nástroje (alc, al-mcp, BC source), nová appka, git/PR, Azure DevOps (sekce 7.1–7.10) |
| `bc-al-build.md` | NuGet dependencies, test symboly, kolize ID, major bump, Essence CI build & deploy gotchas (sekce 7.11–7.19) |
| `bc-al-autotests.md` | automatizované testy — codeunits, libraries, runner, povinnost |
| `ew-mobile-ui-notes.md` | UI poznámky k Essence Warehouse Mobile (čtečky) |
| `bc-al-mcp-server.md` | **draft** — oficiální BC MCP server (konfigurace v BC, auth / device login, Claude Code `--mcp-config` + `headersHelper`); bez skill-wrapperu, v Routeru jen jako řádek |
| `mcp-setup.md` | jednorázová instalace MCP serverů pro Claude Code (npm, `claude mcp add`, PAT, timeouty) — **není notes**, skilly ho nenačítají; ostatní nástroje viz níže |
| `bc-al-notes.archived-2026-06-23.md` | archiv původního monolitu — **needitovat**, jen reference |

## Pravidla údržby

- Číslování sekcí (1–12) je napříč soubory původní kvůli odkazům „viz X.Y" — neměnit.
- Soubor nad **1000 řádků** rozděl (vyčleň ucelené sekce do nového `bc-al-*.md`,
  přidej skill-wrapper do `skills/`, aktualizuj Router ve `skills/bc-al/SKILL.md`
  + tento README; always-on soubory ostatních nástrojů Router nedrží).
  Prakticky: ~750+ řádků / ~50 KB se už do jednoho Read (~25k tokenů) nevejde — děl dřív.
  Vzory: 7.11–7.19 → `bc-al-build.md` (2026-09-01); sekce 4 → `bc-al-ui.md` a 5.y2 + 11 →
  `bc-al-integrations.md` (2026-09-08, `bc-al-objects.md` měl 57 KB = 26k tokenů a Read ho ořízl).
- Každý nový poznatek = commit s krátkou zprávou, co a odkud (repo, PR, datum).

Lokální klon: `C:\WorkTasks\BCALInsights` (do 2026-08-28 žilo v OneDrive
`AI\BCALInsights`; `ShopifyConnector/` zůstal tam — má vlastní GitHub repo).

## Nový stroj / kolega — jak si to přidat

`SKILL.md` je otevřený formát [Agent Skills](https://agentskills.io/specification), který
čtou Claude Code, GitHub Copilot, Codex i Antigravity. `.claude-plugin/plugin.json` je jen
manifest pro Claude Code, ostatní nástroje ho ignorují. **Samotný klon ale nestačí** — každý
nástroj potřebuje čtyři kroky:

1. **Klon přesně do `C:\WorkTasks\BCALInsights`.** Skilly odkazují na notes **absolutní
   cestou** (přes junction by relativní `../../` nesedělo). Máš klon jinde? Udělej junction:
   `cmd /c mklink /J C:\WorkTasks\BCALInsights <cesta ke klonu>`.
2. **Junction skillů** do složky, odkud tvůj nástroj skilly čte (per nástroj níže). Bez toho
   nástroj skilly nevidí — pracuješ v `cust-*-bc` / `prod-*-bc` repech, ne tady.
3. **Startup pravidlo** do always-on instrukčního souboru nástroje (šablona níže). Bez něj
   agent skill načte jen, když si ho sám vybere podle `description`, nebo ručně.
4. **MCP servery.** Globální npm instalace je společná (`mcp-setup.md`, krok 1:
   `npm i -g al-mcp-server bc-code-intelligence-mcp @azure-devops/mcp @demiliani/d365bc-admin-mcp`),
   registrace je per nástroj (Claude Code = zbytek `mcp-setup.md`, ostatní níže). Bez MCP skilly
   fungují, agent jen hádá signatury z paměti.

### Šablona startup pravidla (společná pro všechny nástroje)

Vlož do always-on souboru nástroje (kam přesně — viz sekce per nástroj), dosaď `<SKILL-DIR>`
a `<RUČNĚ>` z tabulky pod šablonou. Jazyk a tón komunikace si přidej podle sebe — to je osobní
preference, ne součást notes.

```markdown
## Povinný startup pro AL / Business Central

Platí jen pro úkoly kolem AL / Business Central (repa `cust-*-bc`, `prod-*-bc`, `.al` soubory,
app.json, XLIFF, Essence pipeline). U ne-AL úkolů (PowerShell, dokumenty, jiné jazyky) startup
přeskoč. Nejsi si jistý → ber to jako AL.

Pokud úkol JE AL/BC, jako PRVNÍ akci (i u pouhé otázky, bez pobídnutí uživatele) načti skill
`bc-al` — je v <SKILL-DIR> (junction na `C:\WorkTasks\BCALInsights\skills`); ručně <RUČNĚ>.
Pokud skilly nejsou k dispozici, přečti přímo `C:\WorkTasks\BCALInsights\skills\bc-al\SKILL.md`.
Skill drží Router „typ úkolu → notes soubor / tematický skill", startup checklist (autotesty
u netriviální funkčnosti, al-mcp `al_packages load` pokud je MCP k dispozici, Sam Coder jen
u netriviálních úkolů a jen pokud je ten MCP k dispozici, oznámení checklistu ✅/❌ uživateli)
a pravidla údržby notes.

Podle Routeru pak načti tematické skilly (`bc-al-*`, `ew-mobile-ui`) nebo rovnou notes
`C:\WorkTasks\BCALInsights\bc-al-*.md` — VŽDY CELÉ, DO KONCE (oříznutý výstup hned dočti;
částečně přečtený soubor = nepřečtený). Bez načtení nemáš kontext a uděláš chybu. Pokud jsi to
neudělal a uživatel se zeptá, přiznej to a naprav.

Notes jsou závazné; rozpor s tvou expertizou → upozorni uživatele, nepřepisuj potichu. Router
žije JEN ve skillu `bc-al` — tady ho neduplikuj. Nový BC/AL poznatek → doplň do příslušného
`bc-al-*.md` + commit + push v `C:\WorkTasks\BCALInsights` (jediná výjimka z „git nikdy sám").
V pracovních repech commit / push / PR nikdy bez pokynu, verzi `app.json` nepovyšuj, ADO PAT je
read-only záměrně (401 na zápis neobcházet). Jazyk kódu a UI textů anglicky, čeština jen do XLIFF.
```

| Nástroj | `<SKILL-DIR>` | `<RUČNĚ>` |
|---|---|---|
| Claude Code | `~/.claude/skills/bcal-insights` (plugin `bcal-insights@skills-dir`) | `/bc-al` |
| Copilot (VS Code, CLI) | `~/.agents/skills/` | `/bc-al` |
| Codex | `~/.agents/skills/` | `$bc-al`, přehled `/skills` |
| Antigravity | `~/.gemini/config/skills/` | zmínit „bc-al" jménem |

### Claude Code

- **Skilly:** junction celého repa jako plugin (auto-load „skills-dir", bez marketplace):

  ```
  cmd /c mklink /J "%USERPROFILE%\.claude\skills\bcal-insights" "C:\WorkTasks\BCALInsights"
  ```

  Příští seance plugin načte jako `bcal-insights@skills-dir`. Ověření:
  `claude plugin validate C:\WorkTasks\BCALInsights`, `claude plugin details bcal-insights`,
  v seanci `/bc-al`.
- **Always-on:** `~/.claude/CLAUDE.md` (globální) — šablona výše.
- **MCP:** `mcp-setup.md` (npm, `claude mcp add -s user …`, read-only PAT, `MCP_TIMEOUT`,
  ověření `claude mcp list`).

### GitHub Copilot (VS Code + Copilot CLI)

- **Skilly:** junction pro Copilot i Codex (čtou stejnou složku):

  ```
  mkdir "%USERPROFILE%\.agents"
  cmd /c mklink /J "%USERPROFILE%\.agents\skills" "C:\WorkTasks\BCALInsights\skills"
  ```

  VS Code Copilot čte i `~/.copilot/skills/` a `~/.claude/skills/<skill>/`; v chatu `/bc-al`.
- **Always-on (VS Code):** `%APPDATA%\Code\User\prompts\bc-al-notes.instructions.md` — šablona
  výše s frontmatterem, aby se pravidlo přilepilo ke každému `.al` souboru:

  ```markdown
  ---
  applyTo: "**/*.al"
  description: "BC/AL: jako první akci načti Agent Skill bc-al (Router + startup checklist) z C:/WorkTasks/BCALInsights"
  ---
  ```

- **Always-on (Copilot CLI):** `~/.copilot/copilot-instructions.md` — stačí odkaz: „před
  jakoukoliv BC/AL prací si přečti `C:\Users\<ty>\AppData\Roaming\Code\User\prompts\bc-al-notes.instructions.md`
  a řiď se jím" (jeden zdroj pro obě Copilot varianty).
- **MCP (VS Code):** `%APPDATA%\Code\User\mcp.json` (klíč `servers`, ne `mcpServers`):

  ```json
  {
    "servers": {
      "al-symbols-mcp":       { "type": "stdio", "command": "cmd", "args": ["/c", "al-mcp-server"] },
      "bc-code-intelligence": { "type": "stdio", "command": "cmd", "args": ["/c", "bc-code-intelligence-mcp"] },
      "azure-devops": {
        "type": "stdio", "command": "cmd",
        "args": ["/c", "mcp-server-azuredevops", "essencebs", "--authentication", "pat"],
        "env": { "NODE_OPTIONS": "--dns-result-order=ipv4first", "PERSONAL_ACCESS_TOKEN": "<base64 email:PAT, viz mcp-setup.md krok 3>" }
      }
    }
  }
  ```

- **MCP (Copilot CLI):** `~/.copilot/mcp-config.json` — stejné servery, ale pod klíčem
  `mcpServers` (formát jako Claude Code). Kontrola v CLI: `/mcp`.
- `npx -y al-mcp-server` místo `cmd /c al-mcp-server` funguje taky (tak to je v 7.2
  `bc-al-tools.md`), jen start trvá 6–30 s místo < 1 s.

### Codex (CLI / IDE)

- **Skilly:** stejný junction `~/.agents/skills` jako u Copilota (výše). Codex čte navíc
  `.agents/skills/` v repu, kde zrovna pracuješ. Ručně `$bc-al`, přehled `/skills`.
- **Always-on:** `~/.codex/AGENTS.md` (globální) — šablona výše.
- **MCP:** `~/.codex/config.toml`:

  ```toml
  [mcp_servers.al-symbols-mcp]
  command = 'C:\Program Files\nodejs\node.exe'
  args = ['C:\Users\<user>\AppData\Roaming\npm\node_modules\al-mcp-server\dist\cli\install.js']
  startup_timeout_sec = 60

  [mcp_servers.al-symbols-mcp.tools.al_packages]
  approval_mode = "approve"

  [mcp_servers.bc-code-intelligence]
  command = "cmd"
  args = ["/c", "bc-code-intelligence-mcp"]

  [mcp_servers.azure-devops]
  command = "cmd"
  args = ["/c", "mcp-server-azuredevops", "essencebs", "--authentication", "pat"]
  env = { NODE_OPTIONS = "--dns-result-order=ipv4first", PERSONAL_ACCESS_TOKEN = "<base64 email:PAT>" }
  ```

  Pracovní repa přidej do `[projects.'C:\WorkTasks\<repo>'] trust_level = "trusted"`, jinak
  Codex v nich nespouští nástroje. Kontrola: `/mcp` v TUI.

  ⚠️ **Codex a `npx` / `cmd /c` shim (2026-09-08):** Codex dává MCP serveru stejných 30 s na
  handshake jako Claude Code (`MCP client for al-symbols-mcp timed out after 30 seconds`).
  `command = "npx"` naběhne obvykle za ~1,5 s, ale při pomalém startu Node (AV sken, síť) to
  nestihne a server pro celou seanci zmizí — v `~/.codex/logs_2.sqlite` pak u
  `stdio_server_launcher` chybí řádek „AL MCP Server started successfully". Proto v Codexu
  volej rovnou `node.exe` + entry JS globálně nainstalovaného balíčku (cesta výše; po
  `npm update -g` zůstává) a přidej `startup_timeout_sec = 60`. `cmd /c <shim>` funguje, ale
  při ukončení seance klient zabije jen `cmd.exe` a `node` zůstane jako sirotek. Stejný vzor
  jde použít i pro `bc-code-intelligence-mcp` (`dist/index.js`) a `@azure-devops/mcp`
  (`dist/index.js`, argumenty `essencebs --authentication pat`).

### Antigravity

- **Skilly:** globální skilly jsou v `~/.gemini/config/skills/`:

  ```
  cmd /c mklink /J "%USERPROFILE%\.gemini\config\skills" "C:\WorkTasks\BCALInsights\skills"
  ```

  Čte i `.agents/skills/` v repu. Spuštění = zmínit „bc-al" jménem v promptu.
- **Always-on:** `~/.gemini/GEMINI.md` (globální) — šablona výše. Když agent běží ve WSL,
  přidej k cestám i variantu `/mnt/c/WorkTasks/BCALInsights/...`.
- **MCP:** `~/.gemini/config/mcp_config.json` (nebo přes UI „MCP Servers → View raw config",
  které zapisuje tamtéž); formát `mcpServers` bez `type`:

  ```json
  {
    "mcpServers": {
      "al-symbols-mcp":       { "command": "cmd", "args": ["/c", "al-mcp-server"] },
      "bc-code-intelligence": { "command": "cmd", "args": ["/c", "bc-code-intelligence-mcp"] },
      "azure-devops": {
        "command": "cmd",
        "args": ["/c", "mcp-server-azuredevops", "essencebs", "--authentication", "pat"],
        "env": { "NODE_OPTIONS": "--dns-result-order=ipv4first", "PERSONAL_ACCESS_TOKEN": "<base64 email:PAT>" }
      }
    }
  }
  ```

### Co platí napříč nástroji

- Skilly, notes i Router jsou **jeden zdroj** (tenhle repo); always-on soubory drží jen
  startup pravidlo + osobní preference, **ne** Router — neduplikuj ho tam.
- Název MCP serveru je libovolný (`al-mcp-server` v Claude Code, `al-symbols-mcp` jinde);
  skilly mluví o toolech (`al_packages`, `al_search_objects`…), ne o názvu serveru.
- `user-invocable: true` ve frontmatteru je specifikum Claude Code; ostatní nástroje neznámé
  klíče ignorují.
- Limit jednoho čtení souboru se liší per nástroj (Claude Code Read ≈ 25k tokenů); pravidlo
  „čti celé, do konce, oříznuté dočti" platí všude.
- Po `git pull` tohoto repa není třeba nic reinstalovat — junctiony míří na živé soubory.

## Claude Code skilly (plugin `bcal-insights`)

Repo je zároveň **Claude Code plugin**: `.claude-plugin/plugin.json` +
`skills/<název>/SKILL.md`. Každý skill je tenký wrapper nad jedním notes
souborem — frontmatter `description` = trigger (Claude Code si skill načte
sám podle typu úkolu), tělo = „přečti `../../<soubor>.md` celý" + TL;DR
stabilních pravidel. **Notes soubory zůstávají zdrojem pravdy.**

| Skill | Soubor | Kdy |
|---|---|---|
| `bc-al` (`/bc-al`) | rozcestník = Router + startup checklist + pravidla údržby | první akce každé AL/BC seance |
| `bc-al-style` | `bc-al-style.md` | konvence, naming, ToolTipy, ID, moderní patterny |
| `bc-al-ui` | `bc-al-ui.md` | chování page/pageextension, RoleCenter, factbox, Visible, MultiLine |
| `bc-al-data` | `bc-al-data.md` | DB operace, event subscribery, propagace polí |
| `bc-al-objects` | `bc-al-objects.md` | No. Series, Item Tracking, Attached to Line No., Requisition Line… |
| `bc-al-integrations` | `bc-al-integrations.md` | Shopify Connector, HttpClient/SecretText na SaaS, Power Automate |
| `bc-al-workflow` | `bc-al-workflow.md` | XLIFF, dokumentace + uživatelská příručka, analyzery, ruleset |
| `bc-al-tools` | `bc-al-tools.md` | alc, symboly, nová appka, git/PR, ADO |
| `bc-al-build` | `bc-al-build.md` | NuGet, test symboly, kolize ID, major bump, CI build/deploy |
| `bc-al-autotests` | `bc-al-autotests.md` | testy + netriviální funkčnost |
| `ew-mobile-ui` | `ew-mobile-ui-notes.md` | mobilní čtečky, Control AddIn, JS |

Všechny skilly mají `user-invocable: true` — jdou spustit i ručně (`/bc-al-tools`…);
normálně si je agent načítá sám podle `description` (limit 1024 znaků dle spec
[agentskills.io](https://agentskills.io/specification), u `description` to hlídej).
Skilly odkazují na notes **absolutní cestou** `C:\WorkTasks\BCALInsights\…` — přes
junction by relativní `../../` nesedělo.

**Údržba skillů:**

- Nové gotchas jdou **do notes souborů**, ne do `SKILL.md` — TL;DR ve skillu
  se mění jen, když se mění pravidlo samo.
- **Nové téma** (nová sekce / objekt / nástroj) → doplň klíčové slovo do
  `description` skillu a do Routeru, jinak si ho agent nenačte. Limit 1024 znaků
  hlídá `python check-skills.py` (délky description + existence notes souborů).
- Při rozdělení notes souboru (> 1000 řádků / ~50 KB) přidej nový wrapper do `skills/`
  a řádek do Routeru ve `skills/bc-al/SKILL.md`.
- Změna skillů → bump `version` v `.claude-plugin/plugin.json`.
