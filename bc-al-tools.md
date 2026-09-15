# BC/AL poznámky — Nástroje, git & Azure DevOps

> Část rozděleného `bc-al-notes.md`. Sekce 7 vyčleněna z `bc-al-workflow.md`
> 2026-08-03; **7.11–7.19 (NuGet dependencies, CI build, deploy) od 2026-09-01
> žijí v `bc-al-build.md`** — odkazy „viz 7.11" a výš hledej tam. Archiv
> monolitu: `bc-al-notes.archived-2026-06-23.md`.
> Načítej, když řešíš: kompilaci z CLI (alc.exe), symboly z .alpackages
> (al-mcp-server), BC source na GitHubu, AL-Go CI, novou appku v multi-app repu,
> source závislé appky, git/commit/PR pravidla, verzování app.json, Azure DevOps
> MCP, case-only rename složky.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **7.** Nástroje a workflow — část **7.1–7.10** (7.11–7.19 → `bc-al-build.md`)

## 7. Nástroje a workflow (7.1–7.10)

### 7.1 Rychlá kompilace z CLI — `alc.exe` z AL extension

AL extension pro VS Code s sebou nese kompilátor `alc.exe`. Jde ho pustit
přímo bez čekání na `al: publish` — užitečné pro zpětnou vazbu
"prošlo/neprošlo" při větších změnách.

**Cesta:** `~/.vscode/extensions/ms-dynamics-smb.al-<version>/bin/win32/alc.exe`
(ve Windows, pro macOS `darwin`, pro Linux `linux`)

**Volání (bash):**

```bash
"$HOME/.vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/win32/alc.exe" \
  /project:"C:\full\path\to\app" \
  /packagecachepath:"C:\full\path\to\.alpackages" \
  /out:"C:\full\path\to\_compile_test.app"
```

**Gotchas:**

- **Cesty musí být absolutní.** S `/project:.` kompilátor uvidí jen `app.json`
  (hlásí "containing 1 file") a nenačte `.al` zdroje. S plnou cestou správně
  sesbírá celý adresář.
- **`/packagecachepath`** ukazuje na složku `.alpackages` (obsahuje závislosti
  jako `Microsoft_Base Application_*.app`). Většinou je o úroveň výš než
  `app/`.
- Bez chybových hlášek na výstupu = kompilace OK. Výstupní `.app` soubor je
  potřeba smazat, pokud jde o test (nebude odpovídat podepsanému buildu).
- Verze extension (`17.0.2273547`) se může lišit — najdi ji přes
  `ls ~/.vscode/extensions | grep ms-dynamics-smb.al`.
- **AL extension 18.0.x (2026-09) změnila layout:** `alc.exe` i `Microsoft.Dynamics.Nav.CodeCop.dll` /
  `PerTenantExtensionCop.dll` / `UICop.dll` leží přímo v `bin/` (žádné `bin/win32`, žádná `bin/Analyzers`);
  `BusinessCentral.LinterCop.dll` v extensionu není vůbec (VS Code si ho stahuje jinam) → CLI check jede jen
  s CodeCop + PTE + UICop, LinterCop nálezy hlídá VS Code / CI. Hledej `find <ext> -name alc.exe`, ne pevnou
  cestu. (2026-09-10, cust-alumistr-bc)
- **alc 18.0 při kompilaci PŘEPÍŠE Word layouty reportů (`*.docx`) v projektu** — po CLI buildu se objeví
  změněný `.docx` v `git status`, i když jsi na report nesáhl. Před commitem `git checkout -- <report>.docx`.
  Log alc 18 je UTF-8 (ne UTF-16 jako u 17) a chyby závislostí mají tvar `error AL1022: …` bez prefixu
  souboru — parser logu nefiltruj na `: error `, ale na `\b(error|warning) [A-Z]{2,3}\d{4}`. (2026-09-12, cust-alumistr-bc)
- **Extrakce z MS Base App `.app`:** `unzip -o -q -j app "src/*"` vytáhne jen zlomek souborů (tiše) — vždy nejdřív
  `unzip -l app | grep <Name>` a pak jmenovitě; názvy s mezerou v ZIPu jsou URL-encoded
  (`Translations/Base%20Application.cs-CZ.xlf`, 78 MB, 255k trans-unitů — CZ caption akce hledej v něm, ne pamětí).
  V Bash smyčce `for n in "Test Runner" …; cp …_${n}_…` bez uvozovek kolem `${n}` kopie tiše selže (word split)
  a alc pak hlásí `AL1022` na balíčky, které „v cache jsou". (2026-09-12, cust-alumistr-bc)
- **Analyzery z CLI:** `/analyzer:<path>\Microsoft.Dynamics.Nav.CodeCop.dll`
  (UICop, AppSourceCop a `BusinessCentral.LinterCop.dll` žijí v
  `<extension>/bin/Analyzers`). V **Git Bash** pozor — argumenty začínající
  `/analyzer:` MSYS přepíše na cestu (`C:\Program Files\Git\analyzer;…`).
  Oprava: prefixni volání `MSYS2_ARG_CONV_EXCL="*"` (pak ale musí být
  všechny cesty plné Windows cesty, žádné `~`).
- **`/ruleset` s externím (https) includem** alc odmítne — „external rulesets
  are not allowed" a žádný CLI přepínač to nepovoluje (funguje jen ve VS Code
  přes `al.allowExternalRulesets`). Pro CLI check pusť analyzery bez rulesetu
  a nálezy filtruj jen na své soubory.
- **Trans-unit ID do ručních překladů:** po CLI kompilaci (s feature
  `TranslationFile`) se přegeneruje `Translations/*.g.xlf` — ID nových
  trans-unitů opiš odtud, není nutné počítat FNV-1a hash ručně (viz 6.2).
- **Claude Code Bash tool (Windows) sráží `\\` na `\` i v quoted heredocu (`<<'EOF'`).** Python skript v heredocu s `'\\'` dostane `'\'` (SyntaxError), a `"C:\\WorkTasks\\…"` se v ne-raw stringu změní na řídicí znaky (`\b`, `\a` → backspace/bell v zapsaném souboru). Backslash v heredocu skládej přes `chr(92)` (nebo skript ulož Write toolem a spusť ze souboru); raw stringy s JEDNÍM backslashem projdou beze změny. Zachyceno 2026-09-02 (cust-sonnentor-bc, oprava `logo` v app.json).
- **`/analyzer:` na `Microsoft.Dynamics.Nav.Analyzers.Common.dll` NEpředávat.** alc 17.0 pak u každého
  spuštění hlásí `warning AL1003: An instance of analyzer ... cannot be created ... Could not load file or
  assembly 'Microsoft.Dynamics.Nav.Analyzers.Common'` a část pravidel CodeCop/PTE (PermissionSet rules,
  PTE0018, Rule026 AllowInCustomizations…) se **vůbec nenačte** — build vypadá čistší, než je. Common
  analyzery jsou v alc vestavěné; z CLI stačí CodeCop + UICop + PerTenantExtensionCop (+ LinterCop). CI název
  „Analyzers.Common" je jen jméno v BcContainerHelper. (2026-09-04, cust-alumistr-bc)
- **Log alc přesměrovaný v Git Bash (`> log 2>&1`) je UTF-16 (BOM) a `iconv -f UTF-16` občas uprostřed
  spadne** → fallback `cp` + `grep` pak hlásí 0 chyb / 0 warningů (falešně, stejně jako PS `*>` v bodě níže).
  Spolehlivé: malý python dekodér, který zkusí `utf-8-sig` / `utf-16` / `utf-16-le` (i s posunem o 1 bajt)
  a vezme variantu, ve které je vidět text `Compilation`. Pozor při grepu na `error`: LC0084 obsahuje
  „error handling" — filtruj `: error ` / `: warning `. (2026-09-04, cust-alumistr-bc)
- **Claude Code Bash tool (Windows): heredoc `<<'EOF'` s apostrofem v OBSAHU** (AL `item''s`, `can''t`,
  python `'`) skončí `unexpected EOF while looking for matching `''` a **celý příkaz se neprovede** — u
  `cd x && cat > a <<EOF …` se nezapíše nic, u příkazů na samostatných řádcích za spadlým `cd` se soubory
  zapíšou do aktuální cwd (která mezi voláními přežívá). AL soubory s apostrofy (ToolTipy, Labely) zapisuj
  **Write toolem**, Bash nech na příkazy; python patch skripty ukládej do souboru a spouštěj ze souboru.
  (2026-09-04, cust-alumistr-bc)
- **Volné object ID hledej BOM-aware.** `grep "^codeunit "` (kotva `^`) přeskočí soubory s UTF-8 BOM (první řádek
  začíná `ï»¿`) → seznam ID je neúplný a nové ID kolidují až v kompilaci (`AL0264 … already declared by the
  extension`). Použij `for f in src/**/*.al; do head -1 "$f" | sed 's/^ï»¿//'; done | grep -oE "codeunit [0-9]+"`
  nebo grep bez `^`. (2026-09-07, prod-ess-configurator-bc: `Condition Tree Mgt.` 63156, `Configuration Copy Tests` 63189,
  `Condition Tree Tests` 63182 měly BOM a v prvním výpisu chyběly — tři kolize za sebou.)
- **Víc package cache najednou:** `/packagecachepath:"C:\repo\.alpackages,C:\repo\base\app"`
  — čárkou oddělený seznam. Hodí se, když symbol sesterské appky repa není
  v `.alpackages`, ale leží jako hotový build v její složce (`base/app/*.app`)
  — netřeba nic kopírovat. (Ověřeno 2026-08-28, cust-sonnentor-bc.)
- **PowerShell `*> soubor` (i `> soubor`) zapisuje výstup alc jako UTF-16 LE** → následný
  `grep`/`wc` na souboru nic nenajde a „0 errors / 0 warnings" je **falešné** (EXIT=0 přitom
  platí). Před grepem `iconv -f UTF-16 -t UTF-8`, nebo v PS `| Out-File -Encoding utf8`.
  (2026-09-02, cust-zlomek-bc)
- **`sed -i` v Git Bash (Claude Code Bash tool) tiše přepíše CRLF → LF v celém souboru**, i když
  měníš jediný řádek. Git s `core.autocrlf=true` to v diffu nezobrazí (normalizuje), ale working
  copy `.al` / `.xlf` už není CRLF a `file` hlásí jen „ASCII text". Po `sed -i` na CRLF souboru
  pusť `unix2dos -q <soubor>` (je v Git Bash), nebo drobné edity dělej Edit toolem. Kontrola:
  `tr -cd '\r' < soubor | wc -c` (0 = CR pryč). (2026-09-08, cust-zlomek-bc, rename captionu 65648)
- **`.alpackages` prázdná (VS Code zrovna stahuje symboly / někdo ji vyčistil) → `AL1022` na
  všech dependencies.** Nečekej a nesahej na cizí cache: poskládej **dočasnou package cache ve
  scratchpadu z KOPIÍ** ze sibling rep (`ls C:/WorkTasks/*/.alpackages/*.app | grep <name>`) —
  jedna řada MS symbolů (Application + Base App + System App + Business Foundation + System +
  CZ packy stejné minor řady; starší CZ pack pod novější `Application` umbrellou nevadí,
  obráceně ano — 7.19 v `bc-al-build.md`) + Essence appky z `prod-*/.alpackages` nebo
  `prod-*/app/*.app`, a `/packagecachepath` nasměruj tam. (2026-09-02, cust-zlomek-bc)

### 7.2 Čtení symbolů z `.alpackages` — al-mcp-server

MCP server [`al-mcp-server`](https://github.com/StefanMaron/AL-Dependency-MCP-Server)
(npm balíček `al-mcp-server`) umí číst stažené symboly přímo z `.alpackages`
aktuálního AL repa. Globálně nakonfigurovaný v **Claude Code**, **GitHub
Copilot CLI** i **Codex CLI**. Nástroje:

- `al_packages` — výpis dostupných app balíčků
- `al_search_objects` — hledání objektů (table, page, codeunit, report,
  enum…) napříč symboly
- `al_search_object_members` — hledání fields, procedur, triggerů uvnitř
  objektu
- `al_get_object_summary` — přehled objektu (members, properties)
- `al_get_object_definition` — plná definice objektu
- `al_find_references` — kde se objekt/member používá

**Konfigurace (globální, per-user):** kompletní jednorázový postup pro nový stroj
(všechny čtyři MCP servery, PAT, `MCP_TIMEOUT`, ověření) je v `mcp-setup.md` v kořeni
notes repa — níže jen původní varianta a proč se od ní odešlo. Server běží přes
`npx -y al-mcp-server` (vyžaduje Node 18+ a .NET SDK 8+). Cwd MCP procesu = cwd, ze které je AI
klient spuštěný, takže `.alpackages` se najde sám, pokud klienta pouštíš z
root složky AL repa.

- **Claude Code**: `claude mcp add al-mcp-server -- npx -y al-mcp-server`
  (zapíše do `~/.claude.json`)
- **GitHub Copilot CLI**: `~/.copilot/mcp-config.json`

  ```json
  {
    "mcpServers": {
      "al-symbols-mcp": {
        "type": "stdio",
        "command": "npx",
        "args": ["-y", "al-mcp-server"]
      }
    }
  }
  ```

- **Codex CLI**: `~/.codex/config.toml`

  ```toml
  [mcp_servers.al-symbols-mcp]
  command = "npx"
  args = ["-y", "al-mcp-server"]
  ```

**⚠️ Studený start — index je po startu seance PRÁZDNÝ.** Server sice naběhne
automaticky, ale packages si sám nenačte (`al_packages list` → `[]`, hledání
nic nenajde). První použití v každé seanci proto začni `al_packages` s
`action: "load"` a `path` = **root repa** — tam žije sdílená `.alpackages`;
cesta na podsložku appky (`<extension>/app`) selže, autodiscover hledá jen
směrem dolů. Load je rychlý (~11k objektů pod 1 s). Totéž platí pro
**bc-code-intelligence**: do zavolání `set_workspace_info` vrací všechny jeho
tooly „Server Not Yet Initialized" (proto je ten call v startup checklistu
rozcestníku). Ověřeno 2026-08-18 (cust-zlomek-bc).

**⚠️ MCP server „není dostupný" v seanci = typicky CONNECT_TIMEOUT při startu, ne rozbitý
balíček.** Claude Code dává každému MCP serveru **30 s** na handshake; servery spouštěné přes
`cmd /c npx -y <balíček>` sahají při každém startu na npm registry (i s cachovaným balíčkem) a při
síťovém/AV zásekem to nestihnou → server pro celou seanci zmizí z nabídky (žádná chyba v UI).
Diagnóza: `%LOCALAPPDATA%\claude-cli-nodejs\Cache\<projekt>\mcp-logs-<server>\<timestamp>.jsonl`
(řádek `Connection failed (CONNECT_TIMEOUT)`); ruční `npx -y <balíček>` + JSON-RPC `initialize`
na stdin ukáže, že server sám o sobě běží. **Fix (nasazeno 2026-08-25):** (a) `npm i -g` balíček a
v `~/.claude.json` volat přímo shim z `%APPDATA%\npm` (`cmd /c bc-code-intelligence-mcp`,
`cmd /c al-mcp-server`, `cmd /c mcp-server-azuredevops essencebs --authentication pat`) — start
pod 1 s místo 6–30 s; (b) pojistka `"env": {"MCP_TIMEOUT": "90000"}` v `~/.claude/settings.json`.
V seanci jde spadlý server oživit přes `/mcp` → reconnect. Nevýhoda globální instalace: verze se
sama neaktualizuje — občas `npm update -g`.
**Codex CLI má tentýž 30s limit** (`MCP client for al-symbols-mcp timed out after 30 seconds`,
config klíč `startup_timeout_sec`); `command = "npx"` tam naběhne za ~1,5 s, ale při pomalém
startu Node (2026-09-08: i `node.exe` s azure-devops serverem startoval 29 s) to nestihne.
Fix: `command = 'C:\Program Files\nodejs\node.exe'`,
`args = ['<%APPDATA%>\npm\node_modules\al-mcp-server\dist\cli\install.js']`,
`startup_timeout_sec = 60` (snippet v `README.md`, sekce Codex). Pozor na `cmd /c <shim>`:
klient při ukončení zabije jen `cmd.exe`, `node` zůstane jako sirotek — proto raději `node.exe`
přímo. Diagnostika Codexu: `~/.codex/logs_2.sqlite`, tabulka `logs`, target
`codex_rmcp_client::stdio_server_launcher` (úspěch = „AL MCP Server started successfully").

**Kdy co použít:**

- **Microsoft Base app / System app / CZ lokalizace** — nejdřív zkus
  `al-mcp-server` (rychlé, lokální). GitHub `StefanMaron/MSDyn365BC.Code.History`
  je fallback, když potřebuješ historii nebo větší kontext mezi soubory.
- **Třetí strany a zákaznické extension** (např. ForNAV, Continia, vlastní
  per-tenant extension) — `al-mcp-server` je **jediný způsob**, jak se na ně
  podívat. Na GitHubu ani context7 nejsou.
- **context7** — pouze pro oficiální MS docs / AL language reference, ne pro
  source code.

**⚠️ MCP vrací jen SIGNATURY, ne těla procedur (base app).** `al_get_object_definition`
u Microsoft base/system app vrátí parametry, návratový typ, properties a fields —
ale **ne implementaci**. Jakmile potřebuješ vidět **tělo procedury** (pochopit chybu
z call stacku, najít konkrétní řádek, vidět co volá / kde indexuje pole), MCP ti
nestačí a **nesmíš se zaseknout na hádání nad signaturou — jdi rovnou na GitHub**
(sekce 7.3). Workflow, který funguje:

1. `al_get_object_definition` vrátí pole **`ReferenceSourceFileName`**
   (např. `Foundation/Reporting/ReportLayoutsImpl.codeunit.al`) = přesná relativní
   cesta k souboru v repu. Vezmi z něj **název souboru**.
2. Najdi plnou cestu přes git tree (plná cesta bývá
   `BaseApp/Source/Base Application/<ReferenceSourceFileName>`):

   ```bash
   gh api "repos/StefanMaron/MSDyn365BC.Code.History/git/trees/<branch>?recursive=1" \
     --jq '.tree[].path | select(test("<NazevSouboru>";"i"))'
   ```

3. Stáhni tělo:

   ```bash
   gh api "repos/StefanMaron/MSDyn365BC.Code.History/contents/<path>?ref=<branch>" \
     --jq '.content' | base64 -d
   ```

`<branch>` ber dle `app.json` (`w1-27`, `cz-27`…, viz 7.3). Pozor: čísla řádků
v compiled call stacku (BC error) **nesedí** přesně na StefanMaron source (jiný
build) — orientuj se podle logiky procedury, ne podle čísla řádku.

Pro **třetí strany** je to obráceně: tělo procedury na GitHubu **není**, MCP
z `.app` symbolů taky vrátí jen signaturu — plný kód jen když máš jejich source
repo (sekce 7.6).

#### 7.2b Oficiální AL MCP server od Microsoftu (`altool launchmcpserver`) — spouštění autotestů v BC

Jiný server než komunitní `al-mcp-server` výše. Je součástí AL extensionu (`<ext>/bin/altool.exe`,
od AL 18 vedle `alc.exe`) a kromě kompilace umí **`al_run_tests`** — spustí test codeunit přímo v BC
(kontejner i SaaS, BC 28+) jako Test Explorer ve VS Code. Registrace do Claude Code (local scope repa):

```bash
claude mcp add --scope local al-official -- \
  "C:\Users\<user>\.vscode\extensions\ms-dynamics-smb.al-<ver>\bin\altool.exe" launchmcpserver \
  "C:\<repo>\base\app" "C:\<repo>\base\test" --packagecachepath "C:\<repo>\.alpackages"
```

- **Projekty vyjmenuj** (bez cest server nenastartuje), `--packagecachepath` až **za** projekty. Tooly se
  objeví až v nové seanci Claude Code.
- Připojení bere z `launch.json` projektu (`--project`), explicitní parametry mají přednost
  (`--environmenttype Sandbox --environmentname X --tenant Y`).
- **Windows: auth na SaaS jede rovnou** — `altool` sdílí s VS Code cache
  `%LOCALAPPDATA%\Microsoft\BusinessCentral\DevTools\TokenCache.dat` („Using VS Code authentication").
  Kopírování klíčů klíčenky je potřeba jen na macOS. `al_auth_login` netřeba.
- Totéž z CLI bez MCP: `altool runtests <codeunitId> --project <test-app> --raw`; dále `publishapp`,
  `auth login/logout`, `compile`, `graph`.
- **„1 skipped" + EXIT 0 = test codeunit v prostředí NEEXISTUJE** (`Test codeunit with ID … not found`) —
  server hlásí úspěch, čti text zprávy.
- Server nic nenasazuje: v prostředí musí být **test toolkit** (Test Runner + `Tests-TestLibraries` +
  `System Application Test Library`, tzn. i `Permissions Mock`) **a** hlavní i test appka. Na **SaaS
  sandboxu** MS test toolkit **nejde** nahrát přes dev endpoint (`altool publishapp` → „vydavatel je
  'Microsoft'… zakazuje publikování rozšíření Microsoftu na úrovni klienta") ani přes Admin Center API
  (`install_app` → „Target app version was not found … Country Code CZ"); zbývá Extension Management v BC,
  pokud tam MS appku nabízí. Plné runtime `.app` toolkitu (ne symbol-only) jsou na MSApps feedu
  (`…/DynamicsBCPublicFeeds/_packaging/MSApps/nuget/v3/flat2/microsoft.tests-testlibraries.<guid>/index.json`).
- `almcp.exe --help` se **nevrátí** (nastartuje HTTP server na 5000) — help ber z `altool launchmcpserver --help`.
- Bash tool: cestu k `.app` skládej `"$DIR/$f"` (lomítko), `"$DIR\\$f"` se sráží na `\$f` a soubor „not found".

(2026-09-15, cust-alumistr-bc, AL 18.0.2732683, sandbox BC-TEST2 — testy zatím nespuštěné, chybí toolkit.)

### 7.3 Práce s BC source na GitHubu

Repo: `https://github.com/StefanMaron/MSDyn365BC.Code.History`

**Výběr správné větve:**

- Větve jsou pojmenované konvencí `<country>-<major>`, např. `w1-27`, `w1-28`,
  `cz-27`, `cz-28`…
- **Major verzi neber natvrdo** — přečti `app.json` v aktuálním repozitáři
  (pole `"application"` nebo `"platform"`, např. `"27.0.0.0"` → větev `w1-27`)
- Pokud je v `app.json` `"28.0.0.0"`, použij `w1-28` (resp. `cz-28`) — verze
  BC se mění každých pár měsíců

**W1 vs CZ větev:**

- **W1 větev** (`w1-<major>`) — base app: Item, Sales, Purchase, Warehouse,
  Inventory, Posting routines, většina business logiky
- **CZ větev** (`cz-<major>`) — česká lokalizace: DPH, Intrastat, Cash Desk,
  Banking (ABO/Gemini), lokální reporty, daňové dokumenty, specifika české
  legislativy
- Když řešíš něco, co se dotýká české legislativy nebo lokálních objektů,
  **musíš se dívat do CZ větve**, ne do W1 — některé tabulky/codeunity v W1
  vůbec nejsou nebo mají jinou implementaci

**Tipy pro fetch:**

- Pro prozkoumání konkrétního souboru je často lepší **raw URL** než GitHub
  UI:

  ```
  https://raw.githubusercontent.com/StefanMaron/MSDyn365BC.Code.History/<branch>/<path>
  ```

- WebFetch na běžné GitHub URL může u dlouhých souborů vracet ořezaný obsah
- Seznam větví: `https://github.com/StefanMaron/MSDyn365BC.Code.History/branches`

**Lokální sparse checkout (celá appka / diffy mezi verzemi):** blobless klon
je rychlý a malý — `git clone --filter=blob:none --no-checkout --branch w1-28
--single-branch <url>` + `git sparse-checkout init --cone` + `set <TopFolder>`
(např. `Shopify`) + `git checkout w1-28`. Commity na w1-* větvích = jednotlivé
buildy (`w1-28.4.53241.0`), takže `git diff <sha1>..<sha2> -- <folder>` dává
čistý diff mezi minor verzemi.

> **⚠️ Windows MAX_PATH: checkout TIŠE vynechá soubory s dlouhou cestou.**
> Bez `git config core.longpaths true` skončí soubory nad ~260 znaků chybou
> „Filename too long", checkout ale **nespadne** — soubory prostě chybí a
> `git status` je ukazuje jako deleted. U Shopify Connectoru tak tiše chybělo
> 20 objektů (celá složka `Order Return Refund Processing` — RetRefProc
> codeunity, Cr.Memo/Return Receipt tableextensions). Prevence: hned po klonu
> `git config core.longpaths true`, po checkoutu **zkontroluj `git status`
> čistý** a klonuj do krátké cesty. Zachyceno 2026-08-18
> (BCShopifyConnectorDocs update na 28.4).

### 7.4 AL-Go for GitHub — CI je zdroj pravdy

Pokud má repo **AL-Go for GitHub** (workflow files pod `.github/workflows/`,
typicky `CICD.yaml`, `PullRequestHandler.yaml`, `Current.yaml`, `NextMajor.yaml`,
`NextMinor.yaml`), pak build / test / publish flow řídí ten pipeline, ne tvůj
lokální AL extension. Při potížích:

- **Nebypassuj** workflow ručním `alc.exe` buildem a manuálním uploadem do
  sandboxu, když repo používá AL-Go — můžeš tím skrýt skutečný problém v
  konfiguraci. Místo toho oprav `settings.json` AL-Go (`.AL-Go/settings.json`),
  workflow inputs nebo dependencies, ať CI projde.
- Lokální dev container z AL-Go (`.AL-Go/cloudDevEnv-*.ps1`) je v pohodě —
  využívá stejnou konfiguraci jako CI, takže odhalí stejné chyby dřív.
- Když ti CI failne, podívej se do `pipelines` runu (Azure DevOps / GitHub
  Actions) na **build artifact `.app` files** a `BuildOutput.txt` — bývá tam
  konkrétnější diagnostika než v UI summary.

### 7.5 Nová appka v multi-app zákaznickém repu — postup

Zákaznická repa typicky drží víc appek vedle sebe (`base/app`, `pricingMatrixExtension/app`,
`configuratorExtension/app`…), sdílí jedny `.alpackages` a jeden VS Code workspace.
Když přidáváš další extension, nezakládej ji od nuly — **zkopíruj existující appku**,
máš tím rovnou launch.json, ruleset, lintercop, AppSourceCop, logo a strukturu složek.

**Postup:**

1. **Vyber šablonu.** Nejbližší co dělá to samé co tvoje nová appka (typicky
   nejnovější extension v repu). Zkopíruj celou složku, např.
   `cp -r pricingMatrixExtension configuratorExtension`.
2. **Vykliď kopii:**
   - Smaž zkopírované buildy (`rm *.app` v rootu appky)
   - Smaž obsah `src/` a `Translations/` (složky nech prázdné — kompilace si do
     Translations vygeneruje `.g.xlf`)
   - Smaž `.snapshots/` pokud tam je (per-app cache)
3. **Vygeneruj nový GUID** (`python -c "import uuid; print(uuid.uuid4())"` nebo
   `[guid]::NewGuid()` v PowerShellu). **Nikdy nerecykluj** GUID z původní
   appky — instalace by se hlásila jako update té druhé.
4. **Uprav `app.json`:**
   - `id` — nový GUID
   - `name` — finální název appky (typicky `<Customer> SE <Feature> Extension`)
   - `brief` — krátký popis k čemu je (objeví se v Extension Management)
   - `dependencies` — minimálně base/app repa (ta drží shared utilities a obvykle
     ostatní extension v repu na ní stojí) plus appka, kterou rozšiřuješ
   - `idRanges` — **unikátní blok** v repu, nepřekrývej s ostatními appkami
     (mrkni jejich `app.json`). Zákaznická repa drží přidělené rozsahy a v
     repu se domluv velikost na appku (typicky 10–40 ID na extension).
   - **ID jsou unikátní per typ objektu** — table, tableextension, page,
     pageextension, codeunit, enum, permissionset i permissionsetextension
     mají každý **vlastní ID namespace**. U těsného range (např. 20 čísel)
     proto **každý typ čísluje od začátku range** (`table 63210` +
     `page 63210` + `pageextension 63210` + `permissionsetextension 63210`
     vedle sebe v pohodě koexistují). Nedělej jeden globální counter napříč
     typy ani neposouvej extension typy „za" základní typ — zbytečně to
     pálí čísla z range.
5. **Per-app suffix** — každá extension v repu má **vlastní customer affix**
   kvůli AppSourceCop / LinterCop. Drží se na **dvou místech v appce**:
   - `.vscode/settings.json` → `"CRS.ObjectNameSuffix": "XXXX"` — pro CRS AL
     Language Extension (auto-rename souborů, generování objektů)
   - `AppSourceCop.json` → `"mandatoryAffixes": ["XXXX"]` — pro kompilátor +
     AppSourceCop (vynutí, že všechna nová pole/objekty mají affix v názvu)

   Affix volíme **per extension**, ne per repo — typicky 2-písmenný klíč
   featury + 2-3 písmenný customer kód (např. `PMALU` = Pricing Matrix +
   Alumistr, `COALU` = Configurator + Alumistr). Repo-level
   `CRS.ObjectNameSuffix` ve `*.code-workspace` je jen fallback pro složky,
   které vlastní settings nemají.

   Pro **Essence produktové appky** (rodina `prod-ef-*`, `prod-em-*`…) je affix
   místo customer kódu **`xxEBS`** (2 písmena featury + `EBS`, např. `APEBS` =
   Advance Payment, `VPEBS` = VAT Payer) a `AppSourceCop.json` používá
   `"mandatorySuffix": "EBS"` (objekty pak pojmenuj ručně `…xxEBS`). Před volbou
   `xxEBS` ověř, že kód není obsazený napříč repy — `azure-devops search_code`
   na `"<KÓD>"`, `count: 0` = volné (obsazené: AAEBS, ADEBS, ALEBS, ACEBS,
   EXEBS, ATEBS…). Kódy se mezi appkami neopakují.
6. **Přidej do workspace** — uprav `<repo>.code-workspace`, sekci `folders`,
   přidej `{ "name": "<appName>", "path": "<appFolder>/app" }`. Bez toho ji
   ve VS Code File Exploreru neuvidíš a CRS extension nebude vědět, kterou
   appku právě edituješ.
7. **(Volitelně) `launch.json`** — pokud má kopírovaná appka launch profil pro
   úplně jiný sandbox/tenant, uprav `environmentName` a `tenant`. V rámci
   jednoho zákaznického repa to ale obvykle sedí beze změny.
8. **Permission sety** — drž vzor base/app (sonnentor):
   - **NEDĚLEJ** permission set kvůli polím na `tableextension` /
     `pageextension` — extension fields dědí práva z base tabulky, takže
     `tabledata` na rozšiřovanou tabulku je zbytečné (a dává nadměrná práva).
   - **Vlastní permission set** appky dej **execute (`= X`) na codeunity a
     reporty** appky. Pokud appka má **vlastní tabulky**, přidej k nim
     `tabledata … = R / RIMD` (jako sonnentor `Quality Code SON`,
     `Item Text SON`). `Assignable = true`, `Access = Public`, `Caption` Locked.
   - Přidej **3 `permissionsetextension`** rozšiřující standardní role
     `D365 BASIC`, `D365 READ`, `D365 SETUP`, každá
     `IncludedPermissionSets = "<vlastní set>"` — tím se appka zařadí do
     standardních uživatelských rolí (jinak by admin musel set přiřazovat ručně).

   ```al
   permissionset 65529 "Advance Check APEBS"
   {
       Access = Public;
       Assignable = true;
       Caption = 'EF Advance Check', Locked = true;
       Permissions =
           codeunit "Sales Advance Mgt. APEBS" = X,
           report "Update Sales Adv. Status APEBS" = X;
   }

   permissionsetextension 65530 "D365 BASIC APEBS" extends "D365 BASIC"
   {
       IncludedPermissionSets = "Advance Check APEBS";
   }
   ```

**Gotchas ze zakládání (cust-sonnentor-bc `warehouseMobileExtension`, 2026-08-28):**

- **Uživatel má v hlavním klonu rozpracovanou práci → novou větev zakládej
  jako `git worktree`** (`git worktree add -b <Branch> <sibling-folder>
  origin/master`), ne `checkout -b` — checkout s dirty tree buď selže, nebo
  zatáhne cizí změny do nové větve. Pak **`git branch --unset-upstream`**
  (7.7 — upstream by mířil na origin/master). `.alpackages` je gitignored,
  takže ve worktree chybí → **junction na sdílenou cache** hlavního klonu:
  `cmd /c mklink /J <worktree>\.alpackages <hlavní-klon>\.alpackages`
  (bez admin práv; symboly stažené z jedné strany vidí obě).
- **Prázdný `permissionset` (bez `Permissions`) se zkompiluje** — skeleton
  OBJECT/READ/EDIT (vzor sonnentor base) jde založit hned, plnit až s objekty.
- **Permission set název ≤ 20 znaků** (viz 1.2 v bc-al-style) — `"Whse.
  Mobile-OBJECT WMSON"` je 25 → `"WhseMob-OBJECT WMSON"` (20); plný název do Caption.
- **`Translations/` v gitu:** `.g.xlf` je gitignored, takže složka bez ručního
  `<App>.cs-CZ.xlf` v gitu neexistuje — založ prázdný XLIFF skeleton
  (`<group id="body"></group>`), NAB AL Tools ho pak plní.
- **Symbol Essence produktové appky pro lokální kompilaci:** sibling repo
  `C:\WorkTasks\prod-*` mívá v `.alpackages` vlastní lokální build — zkopíruj;
  pro CI ověř na feedu BCNugetPackages (flat2 `index.json`, viz 7.11
  v `bc-al-build.md`), že existuje verze ve stejné minor řadě jako deklarované
  minimum (7.17 tamtéž, MajorMinor constraint).

**Co po kopírování NEMĚNIT (pokud nemáš důvod):**

- `runtime`, `platform`, `application` verze — drží konzistenci s repem
- `applicationInsightsConnectionString` — sdílený za customer/publisher
- `essence.png` (logo), `cust-<…>.ruleset.json`, `lintercop.json` — sdílené
  konvence pro celý repo

**Checklist před prvním commitem:**

- [ ] Nový GUID v `app.json` (ne recyklovaný)
- [ ] `idRanges` nepřekrývá žádnou jinou appku v repu
- [ ] `CRS.ObjectNameSuffix` v `.vscode/settings.json` = affix
- [ ] `mandatoryAffixes` v `AppSourceCop.json` = stejný affix
- [ ] `dependencies` ukazují na správné GUID + minimální verze, kterou app reálně potřebuje
- [ ] Přidáno do `<repo>.code-workspace`
- [ ] Permission set (execute codeunitů/reportů; tabledata jen pro vlastní tabulky) + `D365 BASIC`/`READ`/`SETUP` extensions
- [ ] Vyklizené `src/`, `Translations/`, žádné `*.app` artefakty v gitu

### 7.6 Source závislé appky — kde hledat plný kód (včetně triggerů)

`al-mcp-server` (7.2) i symboly z `.alpackages` ti dají **strukturu** objektu
(pole, properties, signatury procedur), ale **ne těla triggerů** (`OnLookup`,
`OnValidate`, `OnInsert`…) ani implementaci procedur. Když potřebuješ vidět
reálnou logiku závislé appky — typicky proto, abys ji 1:1 zopakoval ve své
extension — postupuj v tomhle pořadí:

1. **Nejdřív hledej sibling repo v `C:\WorkTasks`.** Závislosti zákaznických
   repů jsou často naše vlastní produktové appky, které tam máš naklonované
   jako **samostatný repozitář se zdrojákem**. Naming: `prod-*` = produktové
   appky, `cust-*` = zákaznické. Příklad: `cust-alumistr-bc` závisí na
   *Essence Configurator* → zdroj žije v
   `C:\WorkTasks\prod-ess-configurator-bc\app`. Otevři `app.json` kandidáta a
   ověř `name` / `id` proti `dependencies` své appky. Tohle je vždycky
   nejlepší — máš plný, aktuální a čitelný source bez extrakce.

2. **Pak extrakce source z `.app` — rovnou si přečti kód.** Číst reálný
   source je vždycky lepší než luštit strukturu z metadat. Když autor source
   do balíčku přibalil (`allowDownloadingSource` / `includeSourceInSymbolFile`
   — naše produktové appky to obvykle mají), `.app` v `.alpackages` je **ZIP
   s ~40-bytovou hlavičkou** — ZIP data začínají signaturou `PK\x03\x04`.
   Najdi offset, odřízni hlavičku, rozbal:

   ```powershell
   $bytes = [System.IO.File]::ReadAllBytes($appPath)
   # najdi PK\x03\x04 v prvních ~100 bytech
   $idx = 0..100 | Where-Object {
       $bytes[$_] -eq 0x50 -and $bytes[$_+1] -eq 0x4B -and
       $bytes[$_+2] -eq 0x03 -and $bytes[$_+3] -eq 0x04
   } | Select-Object -First 1
   $zip = New-Object byte[] ($bytes.Length - $idx)
   [Array]::Copy($bytes, $idx, $zip, 0, $zip.Length)
   [IO.File]::WriteAllBytes("$out\pkg.zip", $zip)
   Expand-Archive "$out\pkg.zip" $out -Force
   # .al soubory (vč. trigger těl) pak najdeš v $out\src\...
   ```

   Extrakci po sobě **ukliď** (temp složka mimo git / gitignore). Tohle není
   v rozporu s 9.3 — pravidlo „`.alpackages` nečíst přes Read/cat/grep" platí
   pro přímé čtení binárky; tady ji řízeně rozbalíš PowerShellem.

3. **`al-mcp-server`** (7.2) jako rychlý fallback / vyhledávač — když source
   není přibalený (`.app` neobsahuje `src/`), nebo ti stačí jen rychle najít
   objekt / pole / signaturu / reference napříč **všemi** symboly
   (`al_search_objects`, `al_find_references`) bez rozbalování. Pozor:
   trigger / procedure těla neukáže — na reálnou logiku se vrať ke kroku 2.

### 7.7 Git commit / push / PR — **nikdy nedělat sám, ani commit**

**Jediná výjimka: notes repo `C:\WorkTasks\BCALInsights`** (osobní poznámky,
GitHub `Ronnie3697/BCALInsights`) — tam se nový poznatek commitne a pushne
rovnou, bez ptaní; smyslem repa je verzovat každou změnu (viz skill `bc-al`).
Všechno níže platí pro pracovní repa (cust-*, prod-*).

Lokální git operace, které jsou OK bez vyžádání:

- `git checkout` / `git checkout -b` (přepínání a vytváření branchů)
- `git add` / `git restore --staged` (stage / unstage do indexu — neměnný
  hash, jen příprava)
- `git cherry-pick`, `git merge`, `git rebase` (pokud uživatel nepoví jinak)
- `git stash`, `git restore` (lokální správa working tree)
- `git fetch`, `git pull --ff-only` (synchronizace s origin pro read)
- `git reset --soft` / `git reset` (zpětné rušení commitů, když uživatel
  řekne; měnit historii bez pokynu ne)

**Co NEDĚLAT bez explicitního vyžádání:**

- `git commit` (ani na feature branch, ani amend) — *commit* už mění
  historii, kterou bude uživatel potřebovat upravit / squashnout / zahodit
- `git push` (ani `-u origin`, ani `--force`, ani na nový branch)
- `git push --delete` / mazání remote branchů
- Vytváření Pull Requestů (`mcp__azure-devops__repo_create_pull_request`,
  `gh pr create`, jakákoli jiná cesta)
- Mergování do master / shared branche

**Po dokončení lokální práce:**

1. Změny nech jako **unstaged / staged** v working tree, **necommituj**.
2. Zastav a oznam uživateli: *„Změny pro `<task>` jsou připravené v
   working tree — můžeš zkontrolovat a zacommitovat / pushnout."* Uveď
   stručný souhrn co se změnilo a v jakých souborech.
3. Čekej na další pokyn. *Commit / push / PR provedu, až dostanu výslovný
   povel* („zacommituj to", „push to", „otevři PR", apod.).

**⚠️ Worktree/branch z CIZÍ upstream + holý `git push` = tichý push do cizí větve.**
`git worktree add -b NováVětev origin/CizíVětev` (nebo `git checkout -b`) nastaví
nové lokální větvi **upstream na `origin/CizíVětev`**. Pak holý `git push` (nebo
`push.default=simple/upstream`) pošle commity **do té cizí větve**, ne pod jménem
tvé nové — a když je tvůj HEAD fast-forward nad jejím tipem, **projde to bez
varování** (cizí větev + její PR se posunou o tvé commity). Prevence: hned po
založení buď `git branch --unset-upstream <větev>`, nebo první push dělej vždy
explicitně `git push -u origin <NováVětev>` (jméno větve v příkazu přebije špatný
upstream a rovnou nastaví správný tracking). Zachyceno: cust-alumistr-bc 2026-07-09
(větev ConfiguratorExtensionOdPNEZ omylem pushnutá do kolegovy ConfiguratorExtension).

**⚠️ Vrátit cizí větev zpět NEJDE — dev nemá ForcePush.** V essencebs ADO běžný
vývojář **nemá `Git 'ForcePush'` permission** na (sdílené) větve → jakýkoli
non-fast-forward push (reset větve na starší commit) skončí `TF401027: You need
the Git 'ForcePush' permission`. `--force-with-lease` na tom nic nezmění (právo je
server-side). Takže když omylem posuneš cizí větev dopředu, **sám ji nevrátíš** —
revert nech na **autorovi větve** (má práva na svou branch) nebo na **adminovi
repa**. Nouzově jde přidat *revert-commity* dopředu (fast-forward, bez force), ale
to zašpiní historii i cizí PR — poslední volba.

**Proč:**

- Uživatel chce konsolidovat víc změn do jednoho commitu / PR podle
  vlastního uvážení (parent PBI vs. dělené tasky), volit přesné commit
  message, případně z části změn slevit.
- Commit, push a PR mají dopad na CI pipeline a review timing — to je
  rozhodnutí uživatele, ne moje.
- Když rovnou commitnu / pushnu, vede to k nadbytečným reset/rebase
  manévrům na úklid.

### 7.8 Verzování `app.json` — nepovyšovat sám

`version` v `app.json` (ani jinou formu verzování extension) **neměnit z
vlastní iniciativy** — verze je součást release procesu, který si řídí
uživatel ručně podle vlastní konvence (kdy se major povyšuje).

- **Pro PR** musí být verze ve tvaru **`XX.0.0.0`** (jen major, zbytek nuly —
  např. `27.0.0.0`). Mezilehlé tvary (`27.0.5.1`) můžou být přechodné během
  vývoje, ale do PR je uživatel sám sníží na `XX.0.0.0`.
- Když uživatel **výslovně** řekne „povyš verzi na X" → uděláš.
- V dokumentačních MD (sekce 8) **nezmiňuj aktuální verzi** extension jako
  součást scope ticketu — verze se mění nezávisle.
- Při code review neobvyklý tvar verze (`27.0.5.1`) jen **zmiň**, neřeš za
  uživatele.

**Proč:** Automatický bump rozhodí release workflow / PR validaci. Verzování
je rozhodnutí uživatele, ne moje (stejná logika jako git commit/push/PR — 7.7).

### 7.9 Azure DevOps MCP — tickety, PRs, pipelines

Tickety a repa Essence BC projektů (Zlomek, Kalas, JIRI, produktové appky…)
žijí v Azure DevOps org **`essencebs`**, projekt **`Projects`**. Work item URL:
`https://dev.azure.com/essencebs/Projects/_workitems/edit/<ID>`.

Když uživatel zmíní číslo ticketu („task 64359", „bug 62667") nebo pošle
`dev.azure.com/essencebs/...` URL, sáhni po MCP serveru **`azure-devops`**
(`@azure-devops/mcp`, globálně v `~/.claude.json`, PAT auth, loaduje se sám):

- `wit_get_work_item` (id) — fetch ticketu; `expand: all` přitáhne i parent /
  relations
- `wit_my_work_items`, `search_workitem` (fulltext)
- `wit_create_work_item`, `wit_update_work_item`, `wit_add_work_item_comment`
  (zápisové — s read-only PAT vrátí 401, viz ⚠️ níže)
- `repo_*`, `pipelines_*`, `wiki_*`, `core_*` — PRs, buildy, wiki, identity

**Vazba na repo:** Ticket většinou neuvádí, do kterého repa patří — odvoď z
**CWD** (`cust-zlomek-bc` = Zlomek, `prod-epb-pricingMatrix-bc` = produktová
Pricing Matrix…), z Area Path a Iteration Path.

**PAT:** base64(`email:rawPAT`) v `env.PERSONAL_ACCESS_TOKEN` v `.claude.json`,
scope záměrně jen **Read** (viz ⚠️ níže), expiruje ~90 dní (firemní policy). Po expiraci
vygeneruj nový na `https://dev.azure.com/essencebs/_usersSettings/tokens`,
zakóduj a přepiš v `.claude.json` (session pak restartovat).

**⚠️ PAT je read-only ZÁMĚRNĚ — 401 na zápisy NEobcházet:** MCP PAT má jen Read scopes **schválně** — Pull Requesty (a další zápisy do ADO) si uživatel dělá **sám**. Když `repo_create_pull_request` / `wit_link_work_item_to_pull_request` vrátí 401, **není to chyba k opravě** — je to záměrná zábrana. **Nikdy** neobcházet jiným credentialem (token z Git Credential Manageru přes `git credential fill`, az CLI, cokoliv jiného) — přesně to se stalo 2026-07-07 (PR 9096, prod-epb-pricingMatrix-bc) a uživatel to výslovně zakázal. Správný postup: připravit větev (merge, resoluce, push pokud je vyžádán), předat uživateli shrnutí + navrhovaný title/description PR a **nechat založení PR na něm**. Platí i když uživatel řekne „potřebuju udělat PR" — tím myslí, že ho udělá on, ne já.

- **`search_code` vrací multi-MB blob (5–6 MB i pro 14 hitů)** — výsledek se uloží do souboru a
  Read ho nepřečte. Repo + cestu vytáhni pythonem regexem (`"path":"..."`, `"repository":{"name"`),
  pak soubor stáhni `repo_file get_content`. Hledá jen indexovaná repa — když CUEBS/… objekt
  nenajde, ověř `repo_repository list` s `repoNameFilter`. (2026-09-01)

**Gotcha — IPv6 reset (ECONNRESET):** Některé MS endpointy (`aex.dev.azure.com`)
resolvují primárně na IPv6 a corp síť/firewall jejich spojení **resetuje**
(`fetch failed` / „Failed to fetch tenant for ADO org essencebs"). IPv4 přes
stejný host funguje. Fix: `NODE_OPTIONS=--dns-result-order=ipv4first` v `env`
sekci toho MCP serveru v `.claude.json` (ne globálně). Stejný workaround platí
pro jakýkoli Node/npm MCP server volající MS API (Graph, M365…).

### 7.10 Case-only rename složky appky = časovaná bomba na Windows build agentech

Git je case-sensitive, NTFS ne. Když jedna větev drží složku `configuratorExtension`
a druhá `ConfiguratorExtension` (case-only rozdíl), **merge commit může obsahovat
OBĚ cesty najednou** (git je bere jako nezávislé adds → žádný konflikt). Na
Windows build agentovi se pak při checkoutu obě složky **sesypou do jedné** —
soubory se stejnou relativní cestou přepíší (přežije jeden `app.json`, druhý
zmizí), soubory unikátní pro každou stranu se smíchají dohromady.

**Příznaky v Essence buildu:** `Sort-AppFoldersByDependencies` na začátku
Compile AL Apps hlásí `WARNING: Dependency <guid>:<publisher>_<name>_<ver>.app
not found` pro appku, která "v repu je" — a když na ní závisí jiná appka
(testovací), kompilace spadne na `Error downloading symbols ... 404 (Not Found)`
(symboly nejsou v NuGetu, v containeru, ani se nekompilují ze zdrojáků, protože
její `app.json` checkout přepsal).

**Detekce case-only duplicit ve stromu** (spustit před pushem po mergi):

```bash
git ls-tree -r HEAD --name-only | sort -f | uniq -di
```

Prázdný výstup = OK. **Fix:** nikdy nedělat case-only rename složky; převzít
casing masteru. Na Windows (case-insensitive checkout) rename dvoukrokově:
`git mv SlozkaX tmp && git mv tmp slozkaX`. Zachyceno: cust-alumistr-bc PR 8756
(build 27263, 2026-07-08) — merge obsahoval `configuratorExtension` (master) i
`ConfiguratorExtension` (větev) současně.
