# Business Central / AL – autotesty: infrastruktura test appky (app.json, symboly, kompilace, běh, CI)

Vyčleněno z `bc-al-autotests.md` 2026-10-09 (1009 řádků / 77 KB, nevešel se do jednoho Read). Tady je
**všechno kolem test appky jako projektu**: `app.json` a závislosti, `internalsVisibleTo` hlavní appky, test
appka bez permissionsetu, název souborů a struktura `src/`, test ruleset, symboly test frameworku, lokální
kompilace (sibling `.alpackages`, temp cache, jedna minor řada MS knihoven), spouštění testů z CLI / Dockeru /
AL Test Runneru a čtení chyb z CI. Povinnost testů, kanonický vzor a psaní testů (handlery, TestPage,
`asserterror`, `Library - *`) zůstávají v `bc-al-autotests.md`, pasti konkrétních oblastí BC
v `bc-al-autotests-domains.md`. Pravidla jsou závazná stejně jako v hlavním souboru.

## Test appka — app.json, závislosti, struktura, ruleset

### Explicitní dependencies v `app.json` (ne transitivní)

Test app s `"target": "Cloud"` musí v `app.json` deklarovat **každou** závislost, jejíž typy přímo používá:

- `Record "Sales Adv. Letter Header CZZ"` → `Advance Payments Localization for Czech`
- `Record "Alternative Prod. BOM ATEBS"` → `EM Alternative BOM and Routing`

Spoléhat na transitive dep přes hlavní extension je sice občas funkční, ale linter / AL kompilátor to nezaručuje a v Cloud targetu to padá.

### Main appka s `Access = Internal` → `internalsVisibleTo` v app.json NEMAZAT

Když má main appka objekty `Access = Internal` (standard u Essence prod modulů)
a test appka je referencuje napřímo (`Codeunit "Xxx" ...`), je
`"internalsVisibleTo": [{ id/name/publisher test appky }]` v **app.json main
appky** povinné — bez něj test appka nezkompiluje („cannot access internal…").
Že to jiná (zákaznická) repa nemají, znamená jen, že jejich appky nejsou
Internal-everything. Vedlejší efekt: PerTenantExtensionCop hlásí **PTE0012**
(warning) na app.json — s Essence CI `failOn warning` to shodí build → schovat
v repo rulesetu (`"id": "PTE0012", "action": "Hidden"` + justification), **ne**
mazat internalsVisibleTo ani zveřejňovat objekty (viz 1.10 v bc-al-style).
(2026-08-05, prod-ess-dotykackaConnector-bc, build 27684.)

⚠️ **`PTE0012` přiletí i do appky, která žádný `Access = Internal` objekt nemá** —
pravidlo hlídá **existenci** `internalsVisibleTo`, ne jeho využití. Fix je stejný
(Hidden v rulesetu); smazat nepoužívané `internalsVisibleTo` je taky validní, ale
u prod modulu, který k Internal kontraktu směřuje, se to jen vrátí. Jak takový fail
vypadá v CI (krok „Compile AL Apps" doběhne bez `##[error]`, pozná se až podle
`SucceededNode() → False` u dalších kroků) → **7.21 v `bc-al-build.md`**.
(2026-09-22, prod-ef-advanceCZ-bc, build 28371.)

⚠️ **`internalsVisibleTo` musí nést PŘESNĚ `id` z `test/app.json`.** Když GUID nesedí (test appka založená s jiným
GUIDem, než se zapsalo do hlavní appky), test appka nezkompiluje s *`error AL0161: 'Procedura(…)' is inaccessible due
to its protection level`* na každém volání `internal` procedury — hláška o GUIDu nic neříká, tak porovnej `id` v obou
`app.json` (`grep -n internalsVisibleTo -A4 app/app.json; grep '"id"' test/app.json`). Oprav GUID v hlavní appce
(identita test appky už žije v CI / `.alpackages`). (2026-10-01, cust-soitron-bc CZ/CDS.CZ: `Soitron CDS CZ Tests`
30a70d4b vs d8b7ff02.)

### Test app nepotřebuje vlastní permissionset

**Do test appky NEpiš permissionset** (execute permissiony na test codeunity).
Je to mrtvý objekt — testy u nás běží **lokálně na serveru v dočasně
vytvořeném OnPrem BC prostředí (kontejner/CI) pod `SUPER`**, a všechny test
codeunity mají `TestPermissions = Disabled` (= taky `SUPER`). Permissionset
by se uplatnil jen u `Restrictive` testů, které stejně nepíšeme (viz `TestPermissions` v `bc-al-autotests.md`).
Žádný `*.PermissionSet.al` v `test/src/` → jeden objekt míň, žádný affix/ID
k řešení. (Zachyceno: prod-ess-dotykackaConnector-bc, červen 2026.)

### File naming test codeunit — affix v názvu souboru NENÍ nutný, když je `AppSourceCop.json` s `mandatoryAffixes`

Když má test app `AppSourceCop.json` s `mandatoryAffixes`, LinterCop ten
registrovaný affix zohlední a **název souboru affix obsahovat nemusí** — affix
se z očekávaného názvu souboru odečte (bere se „base" jméno objektu bez affixu).
Žádný warning.

```
// objekt: codeunit "Sales Advance Tests AOEBS"
// + AppSourceCop.json s mandatoryAffixes: ["AOEBS"]
SalesAdvanceTests.Codeunit.al        ✅  (affix v názvu souboru netřeba)
SalesAdvanceTestsAOEBS.Codeunit.al   ✅  (projde taky, ale je to redundantní)
```

Affix v **názvu objektu** (`... AOEBS`) zůstává povinný — to hlídá AppSourceCop
přes `mandatoryAffixes`. Jen do **názvu souboru** ho už tahat nemusíš.

> **Oprava dřívější poznámky:** dřív tu stálo, že soubor *musí* mít affix v
> názvu. To platí jen tam, kde `AppSourceCop.json` s `mandatoryAffixes` chybí.
> S přítomným `AppSourceCop.json` je naopak správně název souboru bez affixu.
> (Zachyceno: prod-ef-advanceCZ-bc, červen 2026.)

### Struktura složek test appky — vždy `src/`, bez podsložek po typu

V každé AL appce v repu musí existovat složka `src/` a v ní všechny objekty. Pro **test appku** stačí placatá `src/` se všemi codeunity vedle sebe — nedělej `src/Codeunits/`, `src/Tests/` apod., testů typicky není tolik aby to mělo cenu rozdělovat.

```
base/test/
├── app.json
└── src/
    ├── AssertZLK.Codeunit.al
    ├── LibraryZlomek.Codeunit.al
    ├── MasterDataTestsZLK.Codeunit.al
    └── …
```

Base produkční app naopak většinou má v `src/` ještě podsložky po typu (`Tables/`, `Pages/`, `Codeunits/`, `TableExtensions/`, …) protože objektů je víc — to je v pořádku, jen v testech to není potřeba.

### Test projekt = vlastní ruleset, co dědí hlavní + skrývá LC0015

Test appka má mít **vlastní `*.ruleset.json`**, který **dědí hlavní app ruleset**
přes `includedRuleSets` a navíc skryje `LC0015` (permission set coverage) — ten pro
test codeunity nedává smysl.

```json
// test/ef-advanceCZ-test.ruleset.json
{
    "name": "EF Advance CZ Tests Ruleset",
    "includedRuleSets": [
        { "action": "Default", "path": "..\\app\\ef-advanceCZ.ruleset.json" }
    ],
    "rules": [
        { "id": "LC0015", "action": "Hidden",
          "justification": "Test projects - permission set coverage not required for test codeunits" }
    ]
}
```

- **Dědit hlavní ruleset** (`includedRuleSets` na `..\app\<main>.ruleset.json`) — tím
  test projekt zdědí všechna projektová pravidla (vč. hidden LC0010 apod.) a jen navíc
  schová LC0015 / AC0010. Takhle to dělá Zlomek (`cust-zlomek-bc-test.ruleset.json`)
  i configurator (`ess-configurator-test.ruleset.json`, doplněno 2026-09-18 — předtím
  nedědil a přicházel tím o hlavní i remote pravidla; detail dopadu v 12.1b
  v `bc-al-workflow.md`). Pravidla, která hlavní ruleset už skrývá (`LC0090`, `PC0037`),
  do test rulesetu **nekopíruj** — zdědí se a ruční kopie se při příští změně rozejde.
- Hlavní ruleset typicky dědí remote `essence-default.ruleset.json` z blob storage →
  test settings potřebují `"al.enableExternalRulesets": true`.

**Past na aktivaci (důležité):** `al.ruleSetPath` se v AL extensionu resolvuje
**relativně k folderu AL projektu**, ne k workspace souboru. Workspace-level
`al.ruleSetPath` bývá `..\app\<main>.ruleset.json` — a ta cesta se **z test složky
resolvuje zpátky na hlavní ruleset** (`test\..\app\...` = `app\...`), takže dedikovaný
test ruleset zůstane **fakticky neaktivní** (přesně případ Zlomka i configuratoru — soubor
existuje, ale VS Code jede hlavní ruleset). Aby byl test ruleset reálně aktivní, dej
**folder-level** override do `test/.vscode/settings.json`:

```json
{
  "CRS.ObjectNameSuffix": "AOEBS",
  "CRS.RemoveSuffixFromFilename": true,
  "al.enableExternalRulesets": true,
  "al.ruleSetPath": "ef-advanceCZ-test.ruleset.json"
}
```

Folder settings přebijí workspace per-klíč (ostatní klíče z workspace se dědí dál).
Ovlivní jen lokální VS Code analýzu — **CI ruleset řeší přes build template/parametr**,
ne přes `.vscode/settings.json`, takže tahle změna build neovlivní.

## Symboly a lokální kompilace test appky

### Test framework symboly nejsou v `.alpackages`

`Tests-TestLibraries` a `System Application Test Library` nejsou v běžných `.alpackages` zákaznického repa. Pro lokální editaci/intellisense:

1. Spustit `scripts/Local-DevEnv.ps1` (vytvoří BC kontejner s `installTestLibraries:true`)
2. Ve VS Code z `test/` složky: `AL: Download Symbols`

V CI to řeší `Run-AlPipeline -installTestLibraries:$true` z `BcContainerHelper`. **Bez stažených symbolů test app vůbec nezkompiluje** (chybí `Library - Sales`, `Library - Inventory`, `Library Assert`, …).

**Lokální kompilace test appky bez kontejneru (ověřeno 2026-09-01, prod-epb-pricingMatrix-bc):**
`Tests-TestLibraries`, `Test Runner` a `System Application Test Library` `.app` bývají v `.alpackages` některého
sibling repa — najít přes `ls /c/WorkTasks/*/.alpackages/*Tests-TestLibraries*` (2026-09: `prod-ess-dotykackaConnector-bc`;
pozor, `ls … | grep -i test` matchne i složku `kalas-TEST-DNEM` jako hlavičku, soubory tam nejsou).
`Tests-TestLibraries` má **tranzitivní závislosti** (Application Test Library, Permissions Mock, Any, Library Assert,
Library Variable Storage, Business Foundation Test Libraries), takže alc potřebuje **celou tu `.alpackages` složku**,
ne jen tři soubory: `/packagecachepath:"C:\…\sibling\.alpackages,C:\…uild-dir-s-hlavní-appkou"` (čárkou oddělený
seznam, viz 7.1 v `bc-al-tools.md`; jiná minor verze Base App v sibling cache pro compile-check nevadí). MS test `.app`
**neobsahují zdrojáky** (0 `.al` v ZIPu) → signatury `Library - *` procedur přes al-mcp (`al_packages load` na sibling
repo, pak `al_search_object_members`); `al_packages load` index **nahrazuje**, po dohledání znovu load na vlastní repo.
`AA0215` (název souboru bez affixu) v test appce vyřeší `test/AppSourceCop.json` s `mandatoryAffixes` — potvrzeno
lokálně (alc + CodeCop). Compile main → test: test appka bere hlavní appku z build diru, takže po každé změně hlavní
appky přeložit nejdřív ji.
**Dependency, která lokálně nikde není (`AI Test Toolkit` v prod-ess-configurator-bc/test):** pro compile-check
nekopíruj `test/app.json` ručně — zkopíruj celou `test/` (src, app.json, AppSourceCop.json, logo) do scratchpadu,
v kopii `app.json` závislost python skriptem vyhoď (zdrojáky testů ji nepoužívají) a kompiluj kopii proti vlastní
cache (MS 28.3 symboly z vlastní `.alpackages` **bez** staré verze hlavní appky + čerstvý build hlavní appky +
Tests-TestLibraries/Test Runner/SysApp Test Lib/App Test Lib/Permissions Mock z dotykacka `.alpackages`).
Dvě verze téže appky v jedné cache (stará `.alpackages` + nový build) = nejasné, kterou alc vezme → do cache jen jednu.
(2026-09-08, prod-ess-configurator-bc, typ řádku Parameter Value Name)

### Temp package cache a kompilace kopie test appky

- **Kompilace test appky: temp cache** = MS 28.3 symboly + `Test Runner`, `Tests-TestLibraries`, `System Application Test Library`, `Application Test
  Library`, `Permissions Mock` (z dotykacka `.alpackages`) + build hlavní appky — tranzitivní `Any` / `Library Assert` /
  `Library Variable Storage` / `Business Foundation Test Libraries` v cache být NEMUSÍ, alc 17.0 projde.
  ⚠️ Platí jen pro **tranzitivní** závislosti: když je test `app.json` deklaruje **explicitně** (prod-ef-bank-bc/Test má
  `Library Assert`, `Library Variable Storage`, `Any`), alc je chce v cache (`AL1022 … could not be found`). Hotové 28.3
  `.app` bez stahování: `find /c/Users/<user>/AppData/Local/Temp/claude /c/WorkTasks /c/WorkingFolder/AL -maxdepth 6
  -iname "Microsoft_Tests-TestLibraries*"` — scratchpady dřívějších seancí (2026-09: alumistr `testsym/` = Test Runner,
  Tests-TestLibraries, SysApp Test Lib, App Test Lib, Permissions Mock, Library Assert 28.3; soitron `cache/` = Any,
  Library Variable Storage 28.3). Do vlastního `testcache/` zkopíruj, ať kompilace nezávisí na cizím temp adresáři.
  (2026-09-25, prod-ef-bank-bc/Test, `ParseSymbolsFromText` testy.)
- **Kompilace kopie test appky ve scratchpadu:** `test/app.json` mívá `"logo": "..\\app\\essence.png"` → vedle kopie `test/`
  musí ležet složka **`app/`** s logem (jinak `AL1001 Source file '..\app\essence.png' could not be found`). A test `app.json`
  musí deklarovat **explicitní dependency na každou appku, jejíž tabulku test čte** — `Record "External Time Sheet Line TSEBS"`
  bez `Essence Project TimeSheets` v deps = `AL0185 Table ... is missing`, i když hlavní appka na ní závisí. (2026-10-02)

### MS test knihovny v temp cache drž v JEDNÉ minor řadě; testy za `#IF TESTS` ověř kopií projektu

- **Smíchané minor verze MS test knihoven** (Tests-TestLibraries / Test Runner / Library Assert 28.3 + `Library Variable
  Storage` 28.4) v jedné package cache = `error AL1022: A package with publisher 'Microsoft', name 'Library Assert', and a
  version compatible with '28.4.0.0' could not be found` — 28.4 knihovna si tranzitivně chce 28.4 Assert, i když test
  `app.json` deklaruje jen `28.0.0.0`. Zákeřné: dvě kompilace se stejnou cache prošly a třetí spadla (rozlišení závislostí
  není stabilní). Ber celou sadu z jednoho místa — hotová **28.4.53241.53504** sada (Test Runner, Tests-TestLibraries, SysApp
  Test Lib, App Test Lib, Permissions Mock, Library Assert, Library Variable Storage) leží v soitron scratchpadu `cache_soi/`
  (`find /c/Users/<user>/AppData/Local/Temp/claude -iname "Microsoft_Library Variable Storage_28.4*"`), `Any` 28.3 k ní nevadí.
- **Test appka s testy za `#IF TESTS` a `"preprocessorSymbols": ["TESTS_Skip"]`** (prod-ef-replications-bc, commit „test skip"
  2026-05) se v CI přeloží na prázdno — nové testy piš pod stejný guard (konzistence s rozhodnutím repa) a lokálně je ověř
  kopií `test/` ve scratchpadu se symbolem přepnutým na `TESTS` (`sed` na `app.json` kopie); jinak se chyby v testech neukážou.
  (2026-09-29, prod-ef-replications-bc, Send With Parent Record.)

### Re-analýza VS Code po změně `app.json`

Když smažeš dependency v `test/app.json` (např. `Tests-TestLibraries`), VS Code AL extension **necachuje** změnu okamžitě. Diagnostiky stále hlásí "Codeunit 'Library Assert' is missing" pro již refaktorované kódy. Řešení:

1. `Ctrl+Shift+P` → `AL: Download Symbols`
2. Pokud nepomohlo → `Developer: Reload Window`

## Spouštění z CLI / CI

- `BcContainerHelper`: `Run-TestsInBcContainer` – PowerShell
- **Lokální Docker běh celé sady jako CI (`Run-AlPipeline`, ověřeno 2026-10-05, cust-soitron-bc, BC 28.2 cz):**
  repo template skripty (`scripts/Local-DevEnv.ps1`) jsou zastaralé (artifact 18.3, Key Vault) → vlastní skript:
  `Run-AlPipeline -containerName bc28 -imageName '' -reUseContainer -keepContainer -useDevEndpoint
  -installTestRunner -installTestFramework -installTestLibraries -licenseFile C:\WorkingFolder\Essence.28.0.Latest.bclicense`
  + `-installApps` Essence závislostí (plné `.app` z `.alpackages` jdou publikovat — mají src, layouty, překlady).
  Pasti: (a) **BcContainerHelper < 6.1.18 + AL extension 18** → `altool.exe … bin\win32 not found` už při
  `Get-AppJsonFromAppFile` (řazení deps) — `Install-Module BcContainerHelper -RequiredVersion 6.1.18 -Scope CurrentUser`
  (vyžaduje .NET 10 + ASP.NET Core 10, viz 7.20 v `bc-al-build.md`); (b) **bez `-imageName ''` staví Run-AlPipeline
  cache image** (dočasný kontejner s náhodným jménem + commit, +7–14 GB) — na malém disku vypnout; (c)
  `-testResultsFile` musí ležet **uvnitř `-baseFolder`**; (d) kompiluj **kopii repa** (robocopy do scratchpadu), alc
  přepisuje `.docx` layouty; (e) Essence partner licence má expiraci — při startu testů warning „license expires in N days".
  Jeden sdílený kontejner na BC verzi pro víc projektů = před publikací odpublikovat ne-Microsoft appky cizích projektů
  (`Get-BcContainerAppInfo -sort DependenciesLast` + `Unpublish-BcContainerApp -unInstall -doNotSaveData -doNotSaveSchema`),
  PTE ID rozsahy zákazníků kolidují. Image `ltsc2025` (~10,8 GB) + artifact jsou sdílené napříč kontejnery. Celkem ~26 min
  při prvním běhu (testy 5 min, 204 testů), opakovaný běh ~11 min.
  ⚠️ **Verze Essence závislostí ber stejné, jaké bere CI** (NuGet `LatestMatching` = nejnovější 28.0.x, 7.11 v `bc-al-build.md`),
  ne „co leží v `.alpackages`": s Item Management 28.0.7.0 padaly 2 testy Get Shipment Lines (*Project No. must be equal to … in
  Sales Shipment Line … Current value is ''*), s 28.0.16.0 (= CI) prošlo všech 204 — falešný fail prostředí, ne kódu. Upgrade
  v běžícím kontejneru: `Publish-BcContainerApp -skipVerification -sync -install -upgrade` (závislé appky zůstanou), pak
  `Unpublish-BcContainerApp` staré verze. Hotový `.app` z DevOps: MCP `pipelines_artifact download` vrátil 0B ZIP → buď `.app`
  od kolegy / z feedu, nebo kompilace ze zdrojáků na `sourceVersion` buildu s verzí přepsanou v `app.json`.
- AL-Go for GitHub: má built-in test step
- Lokálně: VS Code task nebo `bc-test-runner` extension
- **Lokální testovací kontejner pro všechna repa** (Docker + BcContainerHelper bez admina, závislosti z NuGetu, nahrát → testy →
  odinstalovat; reprodukuje CI) → **7.23 v `bc-al-build.md`**, nástroj `<PRACOVNÍ-REPA>\bc-test-container\Test-Repo.ps1`;
  pouští se **po každém vyžádaném push** (7.7b v `bc-al-tools.md`), jen kdo kontejner v setupu přijal.
- **VS Code extension AL Test Runner** (James Pearson, `jamespearson.al-test-runner`; dřív tu chybně „luc-vandyck")
  — codelens "Run Test" / "Debug Test", Testing pane, zvýraznění padající řádky, code coverage. **Kontejner nevyrábí**:
  appku publikuje přes `launch.json` (nebo PowerShell) a testy pouští přes BcContainerHelper `Run-TestsInBcContainer`
  v Docker kontejneru — lokálním, nebo na vzdáleném hostu přes PS remoting (`.altestrunner/config.json`: `containerName`,
  `dockerHost`, `remoteContainerName`, `launchConfigName`); varianta `runTestsViaUrl` volá vlastní appku *Test Runner Service*
  (doinstaluje si ji, `testRunnerServiceUrl`), přes ni jde i debug testu. Test toolkit musí v cílovém BC být → na SaaS sandbox
  s `Tests-TestLibraries` nepoužitelné. Pro denní vývoj jeď AL Test Runner, pro release ověření Test Tool page (130401).
  (Ověřeno z readme/changelogu 10.16.8 a `package.json`, 2026-10-05.)

## Diagnostika CI failů

- **Chybové hlášky spadlých testů z CI:** MCP `testplan_show_test_results_from_build_id` vrací jen id/outcome a build log
  „Run Tests in container" jen jména testů. Text chyby + stack: REST
  `https://dev.azure.com/essencebs/Projects/_apis/test/Runs/<runId>/results?outcomes=Failed&api-version=7.1` — s MCP PAT
  vrací HTML (chybí scope Test), ale otevřený v přihlášeném Chromu (Claude in Chrome tab) vrátí JSON
  (`errorMessage`, `stackTrace`). `runId` je v logu kroku Publish Test Results. (2026-09-15)
  (2026-09-07, cust-alumistr-bc 65916, 2. kolo review)
- **Čtení CI logu: stejné `Document No.` v chybách několika testů za sebou = každý z nich spadl a odroloval se**
  (číselná řada se vrátila); prošlý test commitne a číslo posune. Runner úspěšné testy nevypisuje, ale z čísel dokladů
  v hláškách jde poznat, které testy mezi faily prošly (build 28149: „1003" u testů 3–5, „1005" od testu 9 = testy 6 a 8
  prošly). Logika ověřená jen na TestPage cestě a ne z kódu (`Rec.Validate + Modify(true)`) = typický kandidát na
  `xRec = Rec` past (3.9 v `bc-al-data.md`).
