# BC/AL poznámky — Nástroje, build, git & Azure DevOps

> Část rozděleného `bc-al-notes.md`. Sekce 7 vyčleněna z `bc-al-workflow.md`
> 2026-08-03 (soubor překročil 1000 řádků — pravidlo dělení viz rozcestník
> `bc-al-notes.instructions.md`). Archiv monolitu: `bc-al-notes.archived-2026-06-23.md`.
> Načítej, když řešíš: kompilaci z CLI (alc.exe), symboly z .alpackages
> (al-mcp-server), BC source na GitHubu, AL-Go CI, novou appku v multi-app repu,
> git/commit/PR pravidla, verzování app.json, Azure DevOps MCP, NuGet
> dependencies, lokální kompilaci test appek, kolize object ID, major version
> bump, Essence build gotchas.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **7.** Nástroje a workflow (7.1–7.15)

## 7. Nástroje a workflow

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
- **Víc package cache najednou:** `/packagecachepath:"C:\repo\.alpackages,C:\repo\base\app"`
  — čárkou oddělený seznam. Hodí se, když symbol sesterské appky repa není
  v `.alpackages`, ale leží jako hotový build v její složce (`base/app/*.app`)
  — netřeba nic kopírovat. (Ověřeno 2026-08-28, cust-sonnentor-bc.)

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

**Konfigurace (globální, per-user):** Server běží přes `npx -y al-mcp-server`
(vyžaduje Node 18+ a .NET SDK 8+). Cwd MCP procesu = cwd, ze které je AI
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
  pro CI ověř na feedu BCNugetPackages (flat2 `index.json`, viz 7.11), že
  existuje verze ve stejné minor řadě jako deklarované minimum (7.17
  MajorMinor constraint).

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
the Git 'ForcePush' permission`. `--force-with-lease` na tom nic nezmění (право je
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
- `repo_*`, `pipelines_*`, `wiki_*`, `core_*` — PRs, buildy, wiki, identity

**Vazba na repo:** Ticket většinou neuvádí, do kterého repa patří — odvoď z
**CWD** (`cust-zlomek-bc` = Zlomek, `prod-epb-pricingMatrix-bc` = produktová
Pricing Matrix…), z Area Path a Iteration Path.

**PAT:** base64(`email:rawPAT`) v `env.PERSONAL_ACCESS_TOKEN` v `.claude.json`,
scope min. Work Items R&W, expiruje ~90 dní (firemní policy). Po expiraci
vygeneruj nový na `https://dev.azure.com/essencebs/_usersSettings/tokens`,
zakóduj a přepiš v `.claude.json` (session pak restartovat).

**⚠️ PAT je read-only ZÁMĚRNĚ — 401 na zápisy NEobcházet:** MCP PAT má jen Read scopes **schválně** — Pull Requesty (a další zápisy do ADO) si uživatel dělá **sám**. Když `repo_create_pull_request` / `wit_link_work_item_to_pull_request` vrátí 401, **není to chyba k opravě** — je to záměrná zábrana. **Nikdy** neobcházet jiným credentialem (token z Git Credential Manageru přes `git credential fill`, az CLI, cokoliv jiného) — přesně to se stalo 2026-07-07 (PR 9096, prod-epb-pricingMatrix-bc) a uživatel to výslovně zakázal. Správný postup: připravit větev (merge, resoluce, push pokud je vyžádán), předat uživateli shrnutí + navrhovaný title/description PR a **nechat založení PR na něm**. Platí i když uživatel řekne „potřebuju udělat PR" — tím myslí, že ho udělá on, ne já.

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

### 7.11 NuGet „earliest match" — nízké minimum dependency = symbol bez novějších polí

Essence build stahuje závislosti z BC NuGet feedu strategií **„Earliest match"** —
pro deklarované `version: X.Y.Z.0` vezme **nejnižší** publikovanou verzi ≥ X.Y.Z (se
stejným major). Takže když v `app.json` deklaruješ dependency **starší, než reálně
potřebuješ**, feed ti stáhne přesně tu starou verzi — a když v ní ještě nejsou pole /
procedury, které tvůj kód volá, kompilace v CI padne na `AL0132 'Record X does not
contain a definition for Y'`, i když aktuální zdroják té závislosti dané pole má.

**Příznak:** lokálně to „funguje" (máš v `.alpackages` novější symbol nebo jsi ho
dočasně obešel), ale CI padá na chybějícím poli/proceduře cizí appky. `AL1076 name/
publisher changed` v logu je vodítko, že tažená appka se přejmenovala (feed matchuje
podle **GUID**, ne názvu — název v dependency je jen kosmetika).

**Diagnostika:** v build logu **„Download Dependencies from NuGet"** najdi řádek
`Best match for package ... Version X` a `Copying ..._X.app` — to je verze, kterou CI
reálně vzala. Porovnej ji s verzí, kde pole vzniklo (git historie zdrojáku té appky,
větev `BC<major>`).

**Fix:** zvedni `version` dependency na verzi, která člen obsahuje (klidně nejvyšší
publikovanou v daném major — earliest-match pak vezme ji, ne BC+1). Ověř lokálně:
naklonuj `BC<major>` větev té appky, `alc` ji zkompiluj do `.app` (produktové appky
bývají bez vlastních deps → rychlé; **verzi přepiš v jejím `app.json`**, ne jen v názvu
souboru — `.app` nese interní verzi a `alc` matchuje podle ní, ne podle filename), dej
symbol do package cache a zkompiluj svou appku proti němu. Zachyceno: cust-alumistr-bc
PR 9116 (build 27280) — `configuratorExtension` deklaroval `EM Cutting Plan 27.0.1.0`,
feed vzal 27.0.1 bez `Production BOM Line CUEBS` polí → fix na `27.0.3.0`.

**⚠️ Multi-app repo: RŮZNÁ minima téže dependency napříč app.json = 404 při
stahování symbolů — i když feed všechny verze MÁ.** Essence build
(`DownloadALDependenciesNuget.ps1`) posbírá dependencies ze všech `app.json`
v repu a **dedupuje per GUID — vyhrává PRVNÍ nalezená deklarace** (pořadí
složek), ne nejvyšší. Jen tahle jedna verze se stáhne z NuGetu a nainstaluje
do build containeru. Compile pak symboly bere z **container endpointu**
(`.../packages?appId=...&versionText=...`), který zná jen nainstalovanou
verzi — projekt deklarující VYŠŠÍ minimum dostane `Error downloading symbols
... 404 (Not Found)` a shodí celý Compile AL Apps krok (žádné AL0132, umře to
před kompilátorem). Zrádnost: 404 vůbec neznamená, že verze na feedu chybí —
krok „Download Dependencies from NuGet" v témže build logu klidně ukazuje
`Earliest version matching ... is <ta verze>` ve výpisu dostupných verzí.

- **Fix: sjednotit deklaraci sdílené dependency na JEDNU verzi ve VŠECH
  app.json repa** — na nejvyšší, kterou některá appka reálně potřebuje.
- **Diagnóza:** v logu „Download Dependencies from NuGet" najdi řádek
  `GUID: <id>, ..., Version: X` (verze po dedupe) a srovnej s `versionText=`
  v URL 404ky. Výpis `First version is ... / Earliest version matching ...`
  říká, co feed skutečně nabízí.
- **Zelený master nic nedokazuje:** master může mít jedinou (konzistentní)
  deklaraci a projít, zatímco PR přidávající druhou appku s jiným minimem
  spadne — vypadá to jako „feed ztratil verzi", ale je to kolize minim.
- Řádek `Downloading symbols: <appka>_X.app` nese verzi z dedupe, `versionText=`
  v URL minimum daného projektu — směrodatná je URL.
- Feed `BCNugetPackages` (pkgs.dev.azure.com/essencebs/Projects) jde číst i
  lokálně s MCP PAT (Basic auth, flat2 URL) — stažený `.nupkg` rozbal a ověř
  kompilaci proti reálnému balíčku (viz 7.12).
- **Konvence package ID na BCNugetPackages:** `<Publisher><Name>.<guid>`,
  kde publisher i name jsou zbavené mezer a interpunkce („Essence International
  s.r.o." + „Essence Configurator" → `essenceinternationalsro.essenceconfigurator.45c32b8e-…`;
  „Essence Business Solutions" + „Alumistr SE Extension" →
  `essencebusinesssolutions.alumistrseextension.f83a70cc-…`). Verze balíčku
  vypíše flat2 `index.json`; hledání podle GUID funguje přes `query2?q=<guid>`.
  Ověřeno 2026-08-06 (cust-alumistr-bc, lokální ověření merge).
- **⚠️ K ověřování kompatibility nepoužívej balíčky z lokálních `.alpackages`**
  — bývají to lokální dev buildy aktuálního zdrojáku s podvrženým číslem verze
  (obsahují členy, které v reálném release té verze nejsou). Reálný balíček
  stáhni z feedu.

Zachyceno: cust-alumistr-bc PR 9116 (buildy 27281→27294, 2026-07-09/10) —
`configuratorExtension/app+test` deklarovaly `EPB Pricing Matrix 27.0.8.0`,
`pricingMatrixExtension/app` `27.0.11.0`; dedupe vzal 27.0.8 → 404 pro PM
extension (a proti reálné 27.0.8 by se ani nezkompiloval: event
`OnAfterInsertOrModifyPriceWorksheetLine` + protected `ModuleEnabledPMEBS`
přišly až v PM 27.0.10, PR 8330). Feed měl 27.0.8–27.0.11 i 28.0.0 celou dobu.
Fix: všude `27.0.11.0`. Dvě mezikola téhle ságy („publikované maximum je
27.0.8", „feed ztratil verze ≥ 27.0.11") byly chybné diagnózy — obě vyvrátil
až výpis dostupných verzí v NuGet kroku build logu.

### 7.12 Lokální kompilační ověření test appky — symboly test frameworku z veřejného feedu

Test appky (Test Runner, Tests-TestLibraries, System Application Test Library,
Library Assert…) se lokálně nedají zkompilovat, dokud nemáš jejich symboly —
v zákaznických `.alpackages` obvykle nejsou a interní dev endpoint
(`http://172.23.99.9:7049/BC/dev/packages`) je dostupný jen z build labu.
**Řešení: veřejný MS Symbols NuGet feed** (bez autentizace):

```
https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/flat2/<id>/index.json          → verze
https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/flat2/<id>/<ver>/<id>.<ver>.nupkg → balíček
```

- `<id>` = `microsoft.<název-bez-mezer-lowercase>.symbols.<appId GUID>`, např.
  `microsoft.testrunner.symbols.23de40a6-dfe8-4f80-80db-d70f83ce8caf`,
  `microsoft.tests-testlibraries.symbols.5d86850b-0d76-4eca-bd7b-951ad998e997`.
  GUIDy opiš z CI build logu (řádky `Processing dependency Microsoft_...`).
  Další ověřené GUIDy (2026-07, BC28):
  `microsoft.systemapplicationtestlibrary.symbols.9856ae4f-d1a7-46ef-89bb-6ef056398228`,
  `microsoft.applicationtestlibrary.symbols.d852d5d2-a39d-4179-baeb-f99a19e32510`,
  `microsoft.permissionsmock.symbols.40860557-a18d-42ad-aecb-22b7dd80dc80`,
  `microsoft.aitesttoolkit.symbols.2156302a-872f-4568-be0b-60968696f0d5`
  (AI Test Toolkit, ověřeno 2026-08-18; GUIDy MS deps jdou opsat i z
  `test/app.json` `dependencies` — netřeba CI log).
- **GUID tranzitivní závislosti bez CI logu:** vytáhni ho z manifestu už staženého
  balíčku — `.app` je ZIP se 40B hlavičkou, uvnitř `NavxManifest.xml` se sekcí
  `<Dependency Id="..." Name="..."/>` (Tests-TestLibraries → Application Test
  Library, Permissions Mock…). Iteruj: stáhni → alc → AL1022 chybějící jméno →
  GUID z manifestu → stáhni.
- **Verze na feedu nemusí sedět s Base App buildem přesně** — vezmi nejvyšší
  dostupnou ze stejné minor řady (index.json balíčku), např. Base App
  `28.2.50931.52241` v cache vs. test symboly `28.2.50931.51111` na feedu —
  kompiluje to v pohodě.
- **curl s `-L`** (redirect na blob storage; bez něj 0 B soubor). `.nupkg` je ZIP,
  `.app` je uvnitř — rozbal a hoď do package cache.
- Verzi ber ze stejné řady jako Base App symboly v cache (např. `27.5.46862.*`).

**Sandbox workflow** (ověření fixu test appky bez CI round-tripu): do temp složky
poskládej package cache z (a) MS symbolů z jiného repa / feedu, (b) závislých
appek z `.alpackages` sousedních klonů, (c) chybějící produktové appky zkompiluj
ze sibling repa (`BC<major>` větev; **verzi v jejím `app.json`** zvedni na deklarované
minimum — alc matchuje podle vnitřní verze, ne filename, viz 7.11), (d) appky
z vlastního repa zkompiluj ze zdrojáků do téže cache. Pak `alc /project:<test>
/packagecachepath:<cache>` + 4 CI analyzery (`Analyzers.Common`, `CodeCop`,
`PerTenantExtensionCop`, `UICop` — pro test projekty Essence build ruleset
nepředává). `info` diagnostiky build neshodí, `failOn = 'warning'` → warning ano.
Zachyceno: cust-alumistr-bc PR 9116 (build 27287, 2026-07-10) — testy z forku psané
proti neexistujícímu COEBS schématu (`"Configuration No."` Integer na Configuration
Definition; reálně `"No."` Code[20] po refactoringu 97c5ce7), ~90 chyb AL0122/0132/
0133/0193 → hromadný přepis `EntryNo: Integer` → `ConfigNo: Code[20]` + explicitní
`"No."` před `Insert(true)` (OnInsert s No. Series se přeskočí, když je No. vyplněné).

### 7.13 Kolize object ID po merge — rozhodují nasazená data, ne „kdo je v masteru"

Když se po merge masteru do feature větve duplikují object ID (dvě paralelní
feature si vzaly stejná čísla z range), **nepřečíslovávej automaticky stranu,
která „ještě není v masteru"**. Rozhoduje, čí objekty už **běží v prostředí
s daty** — u nasazených objektů se ID nemění (data/companion tabulky,
personalizace, permission záznamy v DB zákazníka vázané na ID). Přečísluj
stranu, která nasazená není, i když už je mergnutá v masteru. Stav nasazení
z gitu nepoznáš → **zeptej se uživatele, která strana smí změnit ID**, než
začneš přečíslovávat. Autorům přečíslovaných objektů dej vědět — změna se
k nim dostane až mergem feature větve. Zachyceno: cust-sonnentor-bc
2026-07-10 (voucher/webshop objekty na větvi už běžely s daty → přečíslovaly
se Opportunity Sync objekty z masteru, ne naopak).

### 7.14 Major version bump repa (BC N → N+1) — checklist

Když se zákaznické repo zvedá na nový BC major (ověřený pattern z
cust-alumistr-bc, bumpy 25/26→27 „yml_File_v27" a 27→28, 2026-07-10):

1. **Všechny `app.json` v repu** (i test appky — `Glob **/app.json`):
   - `version`, `platform`, `application` → `N.0.0.0`
   - `runtime` +1 (BC 27 = 16.0, BC 28 = 17.0)
   - **`dependencies` minima → `N.0.0.0`** — i ta se specifickými minimy
     (`27.0.11.0` apod.): feature-minima z předchozího majoru jsou v `N.0.0.0`
     už obsažená (major se větví z head předchozího). Zároveň to sjednotí
     deklarace napříč app.json (dedupe past, viz 7.11).
2. **`azure-pipelines.yml`**: `BC_ARTIFACT` → `bcartifacts/onprem/N.0/cz/latest`,
   `Version.Major` → `N`. Bez toho CI kompiluje proti starým symbolům a
   s novým runtime spadne.
3. **Ověř na feedu**, že externí Essence dependencies mají publikovanou
   `N.0.x` (NuGet `query2` endpoint s MCP PAT Basic auth, hledej per GUID —
   viz 7.11). Microsoft deps neřeš — neberou se z BCNugetPackages feedu.
4. **In-repo cross-dependencies** (appka repa závisí na jiné appce téhož
   repa) klidně deklaruj `N.0.0.0`, i když na feedu ještě žádná `N.x` není:
   `DownloadALDependenciesNuget.ps1` stahuje jen `$unknownDependencies`
   ze `Sort-AppFoldersByDependencies` — tedy **jen externí** závislosti;
   in-repo se kompilují ze zdrojáků v pořadí závislostí.

### 7.15 Essence build: faily testů shazují build (od 2026-07-15) — „zelený" master nic nedokazoval

PR 9142 v `tools-devops-essence-bc-yaml-lib` (větev `v2-0`, merge 2026-07-15, Igor
Chladil): `scripts/TestBCApps.ps1` teď volá `Run-TestsInBcContainer` s
`-AzureDevOps "error"` + `-returnTrueIfAllPassed` a při jakémkoli failu udělá
`exit 1`; `PublishTestResults@2` v `ALBuildPipeline2.yml` má
`failTaskOnFailedTests: true`. **Do té doby byly faily testů jen `##[warning]`
a build zůstal zelený** — repa mohla dlouhodobě vozit červené testy bez
povšimnutí.

- **Příznak:** master „z ničeho nic" zčervená po merge nesouvisejícího PR.
- **Diagnóza:** srovnej „Run Tests in container" log s posledním zeleným
  buildem — když tam ty samé hlášky byly jako `##[warning]`, není to regrese
  kódu, ale zpřísněná šablona. Faily jsou ale **reálné** → testy oprav
  (dočasná objížďka: `disabledTests` parametr šablony).
- Platí pro všechny pipeline na `v2-0` šabloně (checkout alias
  `essence_templates`).

Zachyceno: cust-zlomek-bc buildy 27392/27395 (2026-07-16) — ~35 testů padalo
identicky už v „zeleném" buildu 27065 (2026-06-26); test helpery
(`LibraryZlomek.CreateCustomer/CreateItem`) vytvářejí holé záznamy bez
Gen. Bus. Posting Group / Base Unit of Measure a sales flow na tom padá.

### 7.16 Squash merge PR → falešné konflikty při dalším mergi + three-dot diff klame

Azure DevOps (a GitHub) umí PR zapsat jako **squash merge** — obsah větve doputuje
do masteru jako **jeden nový commit s jediným parentem**, původní commity větve
v masteru **nejsou** jako ancestor. Poznáš to takhle:

```bash
git log --format="%h parents:[%p]" -n1 <mergeCommit>   # 1 parent = squash, 2 = real merge
git branch -r --contains <commitVetve>                 # neukáže origin/master → squash
```

**Dopad 1 — falešné konflikty.** `git merge-base` zůstane na **starém** commitu z doby
před PR. Při dalším mergi masteru do té samé větve git porovnává obě strany proti
zastaralému base a vidí „obě strany nezávisle přidaly podobný kód na stejné místo"
→ **konflikt, i když je obsah fakticky identický**. Resoluce je pak typicky
„vzít obojí" a nic se nezahazuje.

**Dopad 2 — three-dot diff lže o tom, co větev přináší.** Tohle je ta zrádnější past:

| Příkaz | Co reálně ukáže |
|---|---|
| `git diff origin/master...HEAD` (**three-dot**) | změny větve **od merge-base** — u squashnuté větve tedy i to, co v masteru **už dávno je** |
| `git diff origin/master HEAD` (**two-dot**) | skutečný rozdíl stromů = **co má větev navíc** ✅ |
| `git diff --cached origin/master` (uprostřed merge) | jak bude výsledek merge vypadat proti masteru; **prázdný = větev nemá co nabídnout** ✅ |

Na squashnuté větvi three-dot vesele vypíše desítky souborů a stovky řádků „práce
na větvi", zatímco two-dot je prázdný — všechno už je v masteru. **Než ohlásíš
„větev přináší X", ověř to two-dot diffem**, jinak slíbíš PR, který nemá obsah.

Zachyceno: cust-sonnentor-bc 2026-08-03 — větev `ShipToAddressContact_Shopify…`
po mergi masteru vyšla **bit-identická s masterem** (`git diff --cached origin/master`
prázdný); její obsah tam doputoval už 2026-07-17 squashem PR 9168. Three-dot diff
přitom hlásil 22 souborů / 511 řádků — přesně obsah toho dávno mergnutého PR.

### 7.17 Microsoft Subcontracting dependency — minimum ≥ 28.3.0.0, jinak build spadne

**Microsoft „Subcontracting"** (GUID `1f32a50d-0057-4b95-b5df-cc04d7e89470`) je
nová MS appka, která **není v onprem bcartifacts** — Essence šablona
(`DownloadALDependenciesNuget.ps1`, v2-0) pro ni má od 2026-08-04 **výjimku**:
jediná Microsoft appka, která se stahuje z NuGetu (podmínka
`publisher -ne 'Microsoft' -or name -eq 'Subcontracting'`).

- Na MS public feedech (MSApps i MSSymbols) existuje **až od verze
  `28.3.52162.52273`** — žádná 28.0.x–28.2.x není publikovaná.
- Šablona jede s defaultem **`versionConstraint = 'MajorMinor'`**: deklarované
  minimum `28.0.0.0` → NuGet range `[28.0.0.0, 28.1.0.0)` → **žádná verze
  nematchne, symbol se nestáhne a Compile AL Apps spadne** na chybějící
  referenci. (Pozor: tenhle MajorMinor constraint je obecná vlastnost v2-0
  šablony — minimum dependency drž ve **stejné minor řadě**, jaká je na feedu
  publikovaná, jinak range nic nenajde. Liší se od earliest-match chování
  popsaného v 7.11; default select je teď `LatestMatching`.)
- **Fix:** deklarovat `"version": "28.3.0.0"` — a to **ve VŠECH app.json repa**
  (app i test), konzistence minim viz dedupe past 7.11.

- **⚠️ Bump minima nestačí — musí sedět i `BC_ARTIFACT`.** Subcontracting
  `28.3.52162.52273` deklaruje v manifestu **`Application: 28.3.0.0`**. Když
  pipeline kompiluje proti artifactu nižší řady (`bcartifacts/onprem/28.0/cz/…`
  = Base App 28.0.x), alc stažený balíček **tiše nemůže zapojit** — a místo
  AL1022 dostaneš matoucí `AL0118/AL0132/AL0405` na polích/enum hodnotách
  z jeho tableextensions („Transfer WIP Item", „Transfer Description",
  „Component Supply Method"…), přesně jako by appka neexistovala. Fix:
  `BC_ARTIFACT` v `azure-pipelines.yml` zvednout na stejnou minor řadu
  (`bcartifacts/onprem/28.3/cz/weekly`). Pozor: `28.0` v artifact cestě
  znamená **řadu 28.0.x**, ne „nejnovější BC 28" — weekly/latest selektor
  vybírá jen uvnitř té řady.
- Essence build od v2-0 šablony kompiluje přes **CompilerFolder** (žádný
  container) — `Compile-AppWithBcCompilerFolder`, symboly z
  `C:\ProgramData\BcContainerHelper\compiler\<verze>-cz\symbols` + `.dependencies`.
  V logu „Compile AL Apps" řádek `Enumerating Apps in CompilerFolder ...` říká
  přesnou verzi artifactu, proti které se reálně kompiluje.

Zachyceno: prod-ess-configurator-bc buildy 2026-08-04 (finálně 27659) — PR 9240
přidal Subcontracting `28.0.0.0`, build masteru spadl (range `[28.0,28.1)` na
feedu nic); fix Jan Lorenc: výjimka v šabloně (commit `4c58c18`) + bump
`app/app.json` na `28.3.0.0` (commit `5114694` přímo na master) → spadlo znovu,
protože `BC_ARTIFACT` zůstal `28.0/cz/weekly` (Base App 28.0.46665 <
Application 28.3.0.0 Subcontractingu). Definitivní fix: artifact `28.3/cz/weekly`
+ sjednocení minim `28.3.0.0` v obou app.json.

### 7.18 Essence Deploy Staging — `sync_mode` je hardcoded 'Add', destruktivní schema změna ho shodí

`ALBuildPipeline2.yml` (v2-0) má v Deploy stage job `DeployToStagingEnvironment`
(podmíněný proměnnou `BC_STAGING_CONTAINER` z variable group), který volá šablonu
`InstallALApps.yml` s **`sync_mode: 'Add'` natvrdo** — `InstallALApps.yml` sice
parametr `sync_mode` má (jde do `Publish-BcContainerApp -syncMode`), ale
ALBuildPipeline2 ho nepropaguje jako svůj parametr → **z repo `azure-pipelines.yml`
nejde sync mode nastavit** (literál, ani variable trik nefunguje).

- **Příznak:** Build (kompilace+testy) zelený, Deploy Staging spadne na
  `TableExtension ... The field 'X' cannot be located. Removing fields is not
  allowed.` — destruktivní schema změna (smazané/přejmenované pole) vs. SyncMode Add.
- **Jednorázový fix:** appka je v tu chvíli už publikovaná (padá až sync fáze) →
  na deploy agentovi ručně:
  ```powershell
  Invoke-ScriptInBcContainer -containerName <BC_STAGING_CONTAINER> -scriptblock {
      Sync-NavApp -ServerInstance BC -Name '<App Name>' -Mode ForceSync -Force
  }
  ```
  a pak v ADO „Rerun failed jobs" — Add už projde (schema srovnané) a dokončí
  install/upgrade i úklid starých verzí.
- **Systémově:** PR do `tools-devops-essence-bc-yaml-lib` — parametr
  `staging_sync_mode` (default `'Add'`) v ALBuildPipeline2.yml propsaný do
  InstallALApps.yml; pak jde jednorázově zapnout ForceSync z repa a zase vrátit.
- **Dvoufázově čistě v AL (bez ForceSync i bez trvalých stubů; tip od Essence
  pipeline týmu, 2026-08-06):** build N pole označí `ObsoleteState = Removed`
  (schema sync Add projde — metadata pole existují) a nasadí se; **build N+1 pole
  smaže úplně** — odstranění pole, které bylo v předchozí nasazené verzi Removed,
  už destructive check nehlásí. Stuby tak v kódu žijí jen jednu verzi. Pozor:
  všechna cílová prostředí musí mezikrok (verzi N) opravdu dostat — prostředí,
  které skočí rovnou z verze N−1 na N+1, spadne stejně.
- ⚠️ ForceSync **nenávratně zahodí data** odstraněných polí — u zákazníka v ostrém
  provozu patří před destruktivní změnu obsolete fáze + migrace, ne ForceSync.
  (Zachyceno 2026-08-05, prod-epb-pricingMatrix-bc build 27692 — odstranění
  Width/Height PMEBS při parametrizaci os; zákazník nebyl live → ForceSync OK.)

**Downstream konzumenti (zákaznická repa závislá na appce se Subcontracting
dependency):** Compile jim projde (alc tranzitivní symboly nepotřebuje), spadne
až **Publish BC Apps** — server při instalaci závislé appky hlásí `AL1024:
Symbols for the requested app Subcontracting ... could not be found in the
database` + `AL0185 Enum '...' is missing`. Tranzitivní download je
`allButMicrosoft`, takže NuGet výjimka nepomůže (funguje jen na PŘÍMÉ deps
z app.json). **Fix: stačí bump `BC_ARTIFACT` na `28.3` — cz 28.3 artifact
Subcontracting obsahuje jako vestavěnou appku** (důkaz: Publish log zeleného
buildu 27679 hlásí „**Upgrading** Subcontracting", ne „Installing"; v 28.0
artifactu není vůbec). Přímou dependency přidávat netřeba. Zachyceno:
cust-zlomek-bc build 27682 (2026-08-05) — configuratorExtension po stažení
Essence Configurator 28.0.8 z NuGetu.

**Třetí vrstva — staging/deploy prostředí:** Deploy stage šablony instaluje
build do dlouhoběžícího staging containeru (`BC_STAGING_CONTAINER` z variable
group `BC28DeployCommonVariables`). Staging na BC 28.0 → instalace appky se
Subcontracting 28.3 dependency spadne stejným `AL1024`. Temporary workaround
(Igor, commit `072eb2d` 2026-08-05): zakomentovaná celá variable group v
`azure-pipelines.yml` → Deploy joby se přeskočí (podmínka na existenci
proměnných). ⚠️ Vedlejší efekt: vypne se tím i `DeployToFileShare` — release
file share nedostává nové `.app`. Trvalé řešení: staging container přestavět
z cz 28.3 artifactu a variable group vrátit.


### 7.19 Smíchané verze MS symbolů v `.alpackages` → falešné AL0132 na polích lokalizace (bez AL1022)

Když v `.alpackages` leží **CZ packy novější řady** (např. `Core/Advanced Localization Pack
for Czech 28.4`) vedle **`Application` umbrelly starší řady** (28.3), `alc` hlásí na polích
z CZ packu **`AL0132: 'Record "Item Journal Line"' does not contain a definition for
'Invt. Movement Template CZL'`** — bez jediné chyby o závislostech. Pole přitom v symbolu
i ve zdrojáku (`cz-28`) existuje. Příčina: manifest CZ packu 28.4 deklaruje
`Application="28.4.0.0"`; `alc` balíček najde (přímá dependency v app.json sedí), ale
když umbrella `Application` v cache tuhle řadu nesplňuje, **tableextensions toho balíčku
tiše nepřipojí**. Nepomůže ani Base App 28.4 — rozhoduje právě `Application`.

- **Diagnóza:** `unzip -p <CZ pack>.app NavxManifest.xml | grep -o 'Application="[^"]*"'`
  vs. verze `Microsoft_Application_*.app` v cache. Před hledáním chyby v cizím kódu
  ověř, že master je v CI zelený (`pipelines_build list` na `refs/heads/master`).
- **Fix:** držet v cache jednu řadu — buď 28.4 CZ packy smazat, nebo doplnit celý 28.4
  set. `Application` umbrella na MSSymbols feedu **není** (`microsoft.application.symbols.<guid>`
  → Can't find the package); jde ji vyrobit z existující: `.app` = 40B NAVX hlavička + ZIP,
  v manifestu přepsat `Version` a `Application`, přebalit a **do hlavičky na offset 28
  zapsat novou délku ZIPu (`<Q`, little-endian)** — bez toho `alc` balíček ignoruje
  (AL1022). Base App / System App / Business Foundation 28.4 jsou na feedu normálně (7.12).
- Parsování `SymbolReference.json` u BC 28 MS appek: objekty jsou **vnořené v
  `Namespaces[]`** (rekurzivně), top-level pole `TableExtensions` je skoro prázdné; cíl
  extension je `TargetObject: "#<appid>#<Table Name>"`, ne property `Extends`. Číst s
  `utf-8-sig` (BOM).

Zachyceno 2026-08-28, cust-sonnentor-bc (větev BlanketOrders_64046 po merge PR 9378
Disposal Protocol): hodinu podezírán cizí kód, přitom šlo o cache s CZ 28.4 + Application 28.3.
