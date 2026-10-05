# BCALInsights — poznámky z BC/AL praxe

Sbírka poznámek (known limitations, patterny, gotchas) pro vývoj Business Central
extensions v AL. Slouží jako **povinný kontext pro AI asistenty** (Claude Code,
GitHub Copilot, Codex, Antigravity) před jakoukoliv AL prací. Router „typ úkolu →
soubor / skill" a startup checklist drží **skill `skills/bc-al/SKILL.md`** —
jediný zdroj; always-on soubory jednotlivých nástrojů na něj jen odkazují.

Notes leží **vedle svého skill-wrapperu** ve `skills/<název>/` (podpůrný soubor skillu podle
Agent Skills spec). Skill na ně odkazuje jen jménem, relativně k vlastnímu adresáři — proto
**klon repa může být kdekoli** a v repu není žádná absolutní cesta (hlídá `check-skills.py`).
V kořeni zůstává README, průvodce prvotním nastavením `SETUP.md` (+ jeho spouštěč `AGENTS.md` /
`.claude/CLAUDE.md`), `mcp-setup.md`, šablona launcheru `setup/ado-mcp.mjs`, `check-skills.py` a archiv.

| Soubor (ve `skills/<název>/`, pokud není uvedeno jinak) | Obsah |
|---|---|
| `bc-al-style.md` | konvence, naming, ToolTipy, přidělování ID, locale pasti, moderní patterny (sekce 1, 10) |
| `bc-al-ui.md` | UI patterny stránek — RunModal/RoleCenter, ConfirmManagement, factbox, CaptionClass, Visible, MultiLine/RichContent (sekce 4) |
| `bc-al-data.md` | database operace, event subscribery (sekce 2, 3.1–3.4, 3.7–3.9) |
| `bc-al-posting.md` | propagace vlastních polí do účtovaných dokladů, archivu a kopií — stejné field ID, částečné účtování, Blob + CalcFields, `Validate("No.")` → `Init()` (sekce 3.5–3.6f) |
| `bc-al-objects.md` | specifické objekty/API — No. Series, Item Tracking, Attached to Line No., Requisition Line… (sekce 5) |
| `bc-al-projects.md` | projekty — Job Planning Line: účto skupina a dimenze do deníku projektů, Location Code, vazba budget ↔ billable, návazné doklady projektu, guardy `OnDelete` (sekce 5.x17–5.x20) |
| `bc-al-integrations.md` | Shopify Connector, HttpClient na SaaS, SecretText/Isolated Storage, Business Events / Power Automate, vlastní API page pro zápis, Dataverse/CDS sync (5.y2, sekce 11) |
| `bc-al-workflow.md` | lokalizace/XLIFF, dokumentace vč. uživatelské příručky, verifikace (sekce 6, 8, 9, 12) |
| `bc-al-tools.md` | nástroje (alc, al-mcp, BC source), nová appka, git/PR, Azure DevOps (sekce 7.1–7.10) |
| `bc-al-build.md` | NuGet dependencies, test symboly, kolize ID, major bump, Essence CI build & deploy gotchas (sekce 7.11–7.19) |
| `bc-al-autotests.md` | automatizované testy — codeunits, libraries, runner, povinnost |
| `bc-al-autotests-saas-fallback.md` | příloha autotestů — vlastní Assert/Library pro SaaS-only test appku bez `Tests-TestLibraries` (reference) |
| `bc-al-autotests-domains.md` | autotesty — doménové recepty: plánování / Carry Out, CZZ zálohy s platbou, párování CZB (vyčleněno 2026-10-01) |
| `ess-configurator-notes.md` | Essence Configurator — parametry, systémové parametry, vzorce, varianty, akce (sekce C1–C6) |
| `skills/bc-al/bc-al-mcp-server.md` | **draft** — oficiální BC MCP server (konfigurace v BC, auth / device login, Claude Code `--mcp-config` + `headersHelper`); bez skill-wrapperu, v Routeru jen jako řádek |
| `SETUP.md` (kořen) | **průvodce prvotním nastavením pro AI agenta** — ptá se na cesty, nástroje, PAT a krok za krokem nastaví junctiony, always-on soubory a MCP; **není notes** |
| `AGENTS.md` (kořen) + `.claude/CLAUDE.md` | always-on pro agenta otevřeného přímo v tomhle repu: chybí napojení skillů → nabídne `SETUP.md`. `.claude/CLAUDE.md` jen importuje `AGENTS.md` pro Claude Code — v kořeni být nesmí, `claude plugin validate` by varoval („CLAUDE.md at the plugin root is not loaded") |
| `mcp-setup.md` (kořen) | jednorázová instalace MCP serverů pro Claude Code (npm, `claude mcp add`, PAT, timeouty) — **není notes**, skilly ho nenačítají; ostatní nástroje viz níže |
| `setup/ado-mcp.mjs` | šablona launcheru Azure DevOps MCP — kopíruje se do `MCP_PAT\` vedle `DevOpsPAT.txt` (`mcp-setup.md`, krok 3) |
| `bc-al-notes.archived-2026-06-23.md` (kořen) | archiv původního monolitu — **needitovat**, jen reference |

## Pravidla údržby

- Číslování sekcí (1–12) je napříč soubory původní kvůli odkazům „viz X.Y" — neměnit.
- Soubor nad **1000 řádků** rozděl (vyčleň ucelené sekce do nového `skills/<název>/<název>.md`,
  přidej vedle něj skill-wrapper `SKILL.md`, aktualizuj Router ve `skills/bc-al/SKILL.md`
  + tento README; always-on soubory ostatních nástrojů Router nedrží).
  Prakticky: ~750+ řádků / ~50 KB se už do jednoho Read (~25k tokenů) nevejde — děl dřív.
  Vzory: 7.11–7.19 → `bc-al-build.md` (2026-09-01); sekce 4 → `bc-al-ui.md` a 5.y2 + 11 →
  `bc-al-integrations.md` (2026-09-08, `bc-al-objects.md` měl 57 KB = 26k tokenů a Read ho ořízl);
  3.5–3.6f → `bc-al-posting.md` (2026-09-29, `bc-al-data.md` přesáhl 1000 řádků).
  Doménové recepty testů → `bc-al-autotests-domains.md` (2026-10-01, `bc-al-autotests.md` přesáhl 1000 řádků).
  5.x10 + 5.x12 (Configurator) → `ess-configurator-notes.md` C13/C14 (2026-10-01, `bc-al-objects.md` by přesáhl 1000 řádků).
  5.x17–5.x20 (projekty) → `bc-al-projects.md` (2026-10-05, `bc-al-objects.md` přesáhl 1000 řádků).
- Každý nový poznatek = commit s krátkou zprávou, co a odkud (repo, PR, datum).

Klon může ležet kdekoli — od 2026-09-22 se notes odkazují relativně k adresáři skillu (dřív
absolutní cestou na pevné místo `C:\WorkTasks\…`; do 2026-08-28 žilo repo v OneDrive `AI\BCALInsights`,
`ShopifyConnector/` zůstal tam — má vlastní GitHub repo).

## Nový stroj / kolega — jak si to přidat

`SKILL.md` je otevřený formát [Agent Skills](https://agentskills.io/specification), který
čtou Claude Code, GitHub Copilot, Codex i Antigravity. `.claude-plugin/plugin.json` je jen
manifest pro Claude Code, ostatní nástroje ho ignorují. **Samotný klon ale nestačí** — každý
nástroj potřebuje čtyři kroky (nejrychleji je nechá provést AI — viz **Prvotní nastavení s AI**
níže):

1. **Klon kamkoli:** `git clone https://github.com/essencebs/BCALInsights.git` (přístup dá
   DNEM). Cesta je libovolná — skilly odkazují na notes relativně k vlastnímu adresáři. Dál
   v návodu je tvůj klon označen `<KLON>`.
2. **Junction skillů** do složky, odkud tvůj nástroj skilly čte (per nástroj níže). Bez toho
   nástroj skilly nevidí — pracuješ v `cust-*-bc` / `prod-*-bc` repech, ne tady.
3. **Startup pravidlo** do always-on instrukčního souboru nástroje (šablona níže). Bez něj
   agent skill načte jen, když si ho sám vybere podle `description`, nebo ručně.
4. **MCP servery.** Globální npm instalace je společná (`mcp-setup.md`, krok 1:
   `npm i -g al-mcp-server bc-code-intelligence-mcp @azure-devops/mcp @demiliani/d365bc-admin-mcp`),
   registrace je per nástroj (Claude Code = zbytek `mcp-setup.md`, ostatní níže). Azure DevOps
   PAT patří do `<MCP_PAT>\DevOpsPAT.txt` a server spouští launcher `<MCP_PAT>\ado-mcp.mjs`
   (šablona `setup/ado-mcp.mjs`, `mcp-setup.md` krok 3). Bez MCP skilly fungují, agent jen hádá
   signatury z paměti.

### Prvotní nastavení s AI — `SETUP.md`

Naklonuj repo a **otevři svůj AI nástroj přímo v klonu**. Nástroje, které čtou `AGENTS.md` /
`.claude/CLAUDE.md` v repu (Claude Code, Codex, Copilot), si všimnou, že skilly ještě nejsou
napojené, a samy nabídnou průvodce `SETUP.md`. Jinak napiš **„proveď SETUP.md"**.

Průvodce se ptá postupně (kde je klon, „Kde máš složku s repozitáři?", které nástroje používáš,
„Máš PAT? Ulož ho do `DevOpsPAT.txt` ve složce `MCP_PAT`", jazyk a tón) a podle odpovědí vytvoří
junctiony skillů, zapíše startup pravidlo do always-on souborů, nainstaluje a zaregistruje MCP
servery a na konci všechno ověří. Před každým zápisem mimo repo se zeptá, co už je hotové,
přeskočí, a PAT nikdy nečte do chatu. Cesty a preference žijí v **tvých** souborech mimo repo,
takže je `git pull` nikdy nepřepíše. Průvodce jde kdykoli pustit znovu, třeba po přidání dalšího
AI nástroje.

### Šablona startup pravidla (společná pro všechny nástroje)

Vlož do always-on souboru nástroje (kam přesně — viz sekce per nástroj), dosaď `<KLON>` (cesta
k tvému klonu), `<SKILL-DIR>` a `<RUČNĚ>` z tabulky pod šablonou. Jazyk a tón komunikace si
přidej podle sebe — to je osobní preference, ne součást notes.

```markdown
## Povinný startup pro AL / Business Central

Platí jen pro úkoly kolem AL / Business Central (repa `cust-*-bc`, `prod-*-bc`, `.al` soubory,
app.json, XLIFF, Essence pipeline). U ne-AL úkolů (PowerShell, dokumenty, jiné jazyky) startup
přeskoč. Nejsi si jistý → ber to jako AL.

Pokud úkol JE AL/BC, jako PRVNÍ akci (i u pouhé otázky, bez pobídnutí uživatele) načti skill
`bc-al` — je v <SKILL-DIR> (junction na `<KLON>\skills`); ručně <RUČNĚ>.
Pokud skilly nejsou k dispozici, přečti přímo `<KLON>\skills\bc-al\SKILL.md`.
Skill drží Router „typ úkolu → notes soubor / tematický skill", startup checklist (autotesty
u netriviální funkčnosti, al-mcp `al_packages load` pokud je MCP k dispozici, Sam Coder jen
u netriviálních úkolů a jen pokud je ten MCP k dispozici, oznámení checklistu ✅/❌ uživateli)
a pravidla údržby notes.

Podle Routeru pak načti tematické skilly (`bc-al-*`, `ess-configurator`) nebo rovnou notes
`<KLON>\skills\<název>\<název>.md` (leží vedle SKILL.md daného skillu) — VŽDY CELÉ, DO KONCE (oříznutý výstup hned dočti;
částečně přečtený soubor = nepřečtený). Bez načtení nemáš kontext a uděláš chybu. Pokud jsi to
neudělal a uživatel se zeptá, přiznej to a naprav.

Notes jsou závazné; rozpor s tvou expertizou → upozorni uživatele, nepřepisuj potichu. Router
žije JEN ve skillu `bc-al` — tady ho neduplikuj. Nový BC/AL poznatek → doplň do příslušného
`bc-al-*.md` + commit + push v `<KLON>` (jediná výjimka z „git nikdy sám"). Pushuje se do
**všech** remotů, které `git remote` vypíše (typicky jen `origin` = `essencebs/BCALInsights`) —
platí pro notes, skilly i README.
Pracovní BC repa (`cust-*-bc`, `prod-*-bc`) mám ve složce <PRACOVNÍ-REPA>.
V pracovních repech commit / push / PR nikdy bez pokynu, verzi `app.json` nepovyšuj, ADO PAT je
read-only záměrně (401 na zápis neobcházet). Jazyk kódu a UI textů anglicky, čeština jen do XLIFF.
```

| Nástroj | `<SKILL-DIR>` | `<RUČNĚ>` |
|---|---|---|
| Claude Code | `~/.claude/skills/bcal-insights` (plugin `bcal-insights@skills-dir`) | `/bc-al` |
| Copilot (VS Code, CLI) | `~/.agents/skills/` | `/bc-al` |
| Codex | `~/.agents/skills/` | `$bc-al`, přehled `/skills` |
| Antigravity | `~/.gemini/config/skills/` | zmínit „bc-al" jménem |

`<PRACOVNÍ-REPA>` = složka s tvými klony `cust-*-bc` / `prod-*-bc` (např. `C:\WorkTasks`) — agent
ji používá na sibling repa, sdílenou `.alpackages` a zdroje závislých appek.

### Claude Code

- **Skilly:** junction celého repa jako plugin (auto-load „skills-dir", bez marketplace):

  ```
  cmd /c mklink /J "%USERPROFILE%\.claude\skills\bcal-insights" "<KLON>"
  ```

  Příští seance plugin načte jako `bcal-insights@skills-dir`. Ověření:
  `claude plugin validate <KLON>`, `claude plugin details bcal-insights`,
  v seanci `/bc-al`.
- **Always-on:** `~/.claude/CLAUDE.md` (globální) — šablona výše.
- **MCP:** `mcp-setup.md` (npm, `claude mcp add -s user …`, read-only PAT v
  `MCP_PAT\DevOpsPAT.txt` + launcher, `MCP_TIMEOUT`, ověření `claude mcp list`).

### GitHub Copilot (VS Code + Copilot CLI)

- **Skilly:** junction pro Copilot i Codex (čtou stejnou složku):

  ```
  mkdir "%USERPROFILE%\.agents"
  cmd /c mklink /J "%USERPROFILE%\.agents\skills" "<KLON>\skills"
  ```

  VS Code Copilot čte i `~/.copilot/skills/` a `~/.claude/skills/<skill>/`; v chatu `/bc-al`.
- **Always-on (VS Code):** `%APPDATA%\Code\User\prompts\bc-al-notes.instructions.md` — šablona
  výše s frontmatterem, aby se pravidlo přilepilo ke každému `.al` souboru:

  ```markdown
  ---
  applyTo: "**/*.al"
  description: "BC/AL: jako první akci načti Agent Skill bc-al (Router + startup checklist) z <KLON>"
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
      "azure-devops":         { "type": "stdio", "command": "node", "args": ["<MCP_PAT>/ado-mcp.mjs"] }
    }
  }
  ```

  `<MCP_PAT>` = složka s launcherem a `DevOpsPAT.txt` (`mcp-setup.md`, krok 3); v JSON piš cestu
  s `/`, nebo zdvojuj `\\`.

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
  command = 'C:\Program Files\nodejs\node.exe'
  args = ['<MCP_PAT>\ado-mcp.mjs']
  startup_timeout_sec = 60
  ```

  Launcher předá další argumenty serveru: `args = ['<MCP_PAT>\ado-mcp.mjs', '-d', 'core', 'work-items']`
  omezí domény toolů (spolu s `enabled_tools = [...]` drží seznam toolů krátký).

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
  jde použít i pro `bc-code-intelligence-mcp` (`dist/index.js`). `@azure-devops/mcp` to má
  vyřešené v launcheru `ado-mcp.mjs` (spouští globální `dist/index.js` ve vlastním procesu).

### Antigravity

- **Skilly:** globální skilly jsou v `~/.gemini/config/skills/`:

  ```
  cmd /c mklink /J "%USERPROFILE%\.gemini\config\skills" "<KLON>\skills"
  ```

  Čte i `.agents/skills/` v repu. Spuštění = zmínit „bc-al" jménem v promptu.
- **Always-on:** `~/.gemini/GEMINI.md` (globální) — šablona výše. Když agent běží ve WSL,
  přidej k cestám i variantu `/mnt/c/...` tvého klonu.
- **MCP:** `~/.gemini/config/mcp_config.json` (nebo přes UI „MCP Servers → View raw config",
  které zapisuje tamtéž); formát `mcpServers` bez `type`:

  ```json
  {
    "mcpServers": {
      "al-symbols-mcp":       { "command": "cmd", "args": ["/c", "al-mcp-server"] },
      "bc-code-intelligence": { "command": "cmd", "args": ["/c", "bc-code-intelligence-mcp"] },
      "azure-devops":         { "command": "C:/Program Files/nodejs/node.exe", "args": ["<MCP_PAT>/ado-mcp.mjs"] }
    }
  }
  ```

  Launcher běží i ve WSL (Node z WSL, cesta `/mnt/c/…/MCP_PAT/ado-mcp.mjs`) — `DevOpsPAT.txt` hledá
  vždy vedle sebe.

### Co platí napříč nástroji

- Skilly, notes i Router jsou **jeden zdroj** (tenhle repo); always-on soubory drží jen
  startup pravidlo + osobní preference, **ne** Router — neduplikuj ho tam.
- Název MCP serveru je libovolný (`al-mcp-server` v Claude Code, `al-symbols-mcp` jinde);
  skilly mluví o toolech (`al_packages`, `al_search_objects`…), ne o názvu serveru.
- Azure DevOps PAT je **jeden soubor** `<MCP_PAT>\DevOpsPAT.txt` pro všechny nástroje — každý konfig
  volá stejný launcher `ado-mcp.mjs`, token v žádném konfigu není. Rotace = přepsat soubor +
  restart seance.
- `user-invocable: true` ve frontmatteru je specifikum Claude Code; ostatní nástroje neznámé
  klíče ignorují.
- Limit jednoho čtení souboru se liší per nástroj (Claude Code Read ≈ 25k tokenů); pravidlo
  „čti celé, do konce, oříznuté dočti" platí všude.
- Po `git pull` tohoto repa není třeba nic reinstalovat — junctiony míří na živé soubory.
- Kořen repa z adresáře skillu: `git -C <skill dir> rev-parse --show-toplevel` funguje i přes
  junction (git si reálnou cestu dohledá, na rozdíl od `..`) — tak skill `bc-al` najde
  `mcp-setup.md` a ví, kde commitovat nový poznatek.

## Claude Code skilly (plugin `bcal-insights`)

Repo je zároveň **Claude Code plugin**: `.claude-plugin/plugin.json` +
`skills/<název>/SKILL.md`. Každý skill je tenký wrapper nad jedním notes
souborem — frontmatter `description` = trigger (Claude Code si skill načte
sám podle typu úkolu), tělo = „přečti `<soubor>.md` z adresáře skillu celý" + TL;DR
stabilních pravidel. **Notes soubory zůstávají zdrojem pravdy.**

| Skill | Soubor | Kdy |
|---|---|---|
| `bc-al` (`/bc-al`) | rozcestník = Router + startup checklist + pravidla údržby | první akce každé AL/BC seance |
| `bc-al-style` | `bc-al-style.md` | konvence, naming, ToolTipy, ID, moderní patterny |
| `bc-al-ui` | `bc-al-ui.md` | chování page/pageextension, RoleCenter, factbox, Visible, MultiLine |
| `bc-al-data` | `bc-al-data.md` | DB operace, event subscribery |
| `bc-al-posting` | `bc-al-posting.md` | vlastní pole na dokladech → archiv, účtované doklady, kopie |
| `bc-al-objects` | `bc-al-objects.md` | No. Series, Item Tracking, Attached to Line No., Requisition Line… |
| `bc-al-projects` | `bc-al-projects.md` | Job Planning Line, deník projektů, návazné doklady projektu, mazání plánovacích řádků |
| `bc-al-integrations` | `bc-al-integrations.md` | Shopify Connector, HttpClient/SecretText na SaaS, Power Automate, Dataverse sync |
| `bc-al-workflow` | `bc-al-workflow.md` | XLIFF, dokumentace + uživatelská příručka, analyzery, ruleset |
| `bc-al-tools` | `bc-al-tools.md` | alc, symboly, nová appka, git/PR, ADO |
| `bc-al-build` | `bc-al-build.md` | NuGet, test symboly, kolize ID, major bump, CI build/deploy |
| `bc-al-autotests` | `bc-al-autotests.md` | testy + netriviální funkčnost |
| `ess-configurator` | `ess-configurator-notes.md` | konfigurátor — parametry, vzorce, varianty |

Všechny skilly mají `user-invocable: true` — jdou spustit i ručně (`/bc-al-tools`…);
normálně si je agent načítá sám podle `description` (limit 1024 znaků dle spec
[agentskills.io](https://agentskills.io/specification), u `description` to hlídej).
Notes leží **vedle `SKILL.md`** a skill na ně odkazuje jen jménem: Claude Code při načtení
hlásí „Base directory for this skill", ostatní nástroje mají adresář skillu z junctionu. Odkaz
`../../<soubor>.md` z `skills/<název>/` by u Copilota / Codexu / Antigravity nesedl — junction
vede jen na `skills/` a Windows resolvují `..` lexikálně (`~/.agents/skills/x/../..` =
`~/.agents`; ověřeno 2026-09-22 PowerShell `Test-Path` i Node `path.resolve`, Bash to naopak
resolvuje fyzicky a zavádí). Proto ani absolutní cesta, ani `..`, ale soubor ve složce skillu.

**Údržba skillů:**

- Nové gotchas jdou **do notes souborů**, ne do `SKILL.md` — TL;DR ve skillu
  se mění jen, když se mění pravidlo samo.
- **Nové téma** (nová sekce / objekt / nástroj) → doplň klíčové slovo do
  `description` skillu a do Routeru, jinak si ho agent nenačte. Limit 1024 znaků
  hlídá `python check-skills.py` (délky description + existence notes souborů).
- Při rozdělení notes souboru (> 1000 řádků / ~50 KB) přidej nový wrapper do `skills/`
  a řádek do Routeru ve `skills/bc-al/SKILL.md`.
- Změna skillů → bump `version` v `.claude-plugin/plugin.json`.
