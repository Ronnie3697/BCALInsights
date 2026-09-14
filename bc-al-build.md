# BC/AL poznámky — Dependencies, CI build & deploy (Essence pipeline)

> Část rozděleného `bc-al-notes.md`. Sekce **7.11–7.19** vyčleněny z `bc-al-tools.md`
> 2026-09-01 (soubor přestal jít přečíst jedním Readem — pravidlo dělení viz skill
> `bc-al` / rozcestník `bc-al-notes.instructions.md`). **7.1–7.10** (alc, al-mcp,
> BC source, AL-Go, nová appka, source závislé appky, git/PR, verzování app.json,
> Azure DevOps MCP, case-only rename) zůstávají v `bc-al-tools.md`. Archiv
> monolitu: `bc-al-notes.archived-2026-06-23.md`.
> Načítej, když řešíš: NuGet dependencies a minima (MajorMinor / LatestMatching,
> dedupe per GUID), symboly test frameworku z MSSymbols feedu, kolize object ID
> po merge, major version bump, Essence build (faily testů, squash merge PR,
> Microsoft Subcontracting ≥ 28.3 + BC_ARTIFACT), Deploy Staging sync mode /
> ForceSync / obsolete dvoufázově, smíchané verze MS symbolů v `.alpackages`.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **7.** Nástroje a workflow — část **7.11–7.19** (dependencies, CI build, deploy)

## 7. Nástroje a workflow — dependencies, build & deploy (7.11–7.19)
### 7.11 NuGet „earliest match" — nízké minimum dependency = symbol bez novějších polí

Essence build stahuje závislosti z BC NuGet feedu strategií **„Earliest match"** —
pro deklarované `version: X.Y.Z.0` vezme **nejnižší** publikovanou verzi ≥ X.Y.Z (se
stejným major). Takže když v `app.json` deklaruješ dependency **starší, než reálně
potřebuješ**, feed ti stáhne přesně tu starou verzi — a když v ní ještě nejsou pole /
procedury, které tvůj kód volá, kompilace v CI padne na `AL0132 'Record X does not
contain a definition for Y'`, i když aktuální zdroják té závislosti dané pole má.

> **Update 2026-08 (šablona v2-0):** download jede s `versionConstraint = 'MajorMinor'`
> a select **`LatestMatching`** — z deklarovaného minima `X.Y.Z.0` vznikne range
> `[X.Y.0.0, X.Y+1.0.0)` a bere se v ní **nejnovější** publikovaná verze. Důsledek:
> minimum dependency drž ve **stejné minor řadě**, jaká je na feedu publikovaná,
> jinak range nic nenajde a Compile spadne (detail a případ Subcontracting v 7.17).
> Dedupe past níže platí beze změny.

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
- **⚠️ Lokalizační MS appky (CZ packy, Banking Documents…) mají na MSSymbols od BC 28
  jiné package ID — s country infixem:** `microsoft.<název>.cz.symbols.<guid>`
  (např. `microsoft.bankingdocumentslocalizationforczech.cz.symbols.8730dafb-13cd-42c9-987c-decb6354269d`,
  stejně `corelocalizationpackforczech.cz.symbols…`, `advancedlocalizationpackforczech.cz.symbols…`).
  Staré ID bez `.cz.` na feedu **dál existuje, ale končí u 27.0.x** — flat2 `index.json`
  tak tiše vrátí jen staré verze a vypadá to, že 28.x nikdo nepublikoval. Když pro
  balíček nenajdeš očekávanou řadu, projeď `…/MSSymbols/nuget/v3/query2/?q=<název-bez-mezer>`
  — vypíše všechny varianty ID s nejnovější verzí. Zachyceno 2026-09-02 (cust-sonnentor-bc,
  symbol Banking Documents Localization for Czech 28.3 po merge PR 9394 — nová dependency base/app).

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

- **Pipeline bez PR validace = testy běží poprvé až na masteru.** `prod-ess-configurator-bc`
  (definice 158) triggeruje jen `refs/heads/master` — `pipelines_build list` nemá pro feature
  větev žádný build, PR se mergne bez jediného běhu testů a master zčervená hned po merge
  (build 28149, 2026-09-08: 16 failů z čerstvě přidaných testů, viz 3.9 v `bc-al-data.md`).
  Než ohlásíš „testy ověří CI", zkontroluj, jestli pro větev vůbec nějaký build vzniká; když ne,
  netriviální testy prožeň lokálně v kontejneru, nebo aspoň projdi obě cesty (TestPage i
  `Rec.Validate + Modify`) čtením kódu. Oprava pak jde novou větví z masteru (squash merge,
  původní větev je obsahem identická s masterem — 7.16).
  Stejně `prod-epb-pricingMatrix-bc` (build 28219, 2026-09-14): PR 9476 squash → první běh testů až
  na masteru, 2 faily (assert přes `Get` generovaného kódu UoM, zbytečný `MessageHandler` — viz
  `bc-al-autotests.md`, sekce CreateItem base UoM); fix novou větví z `origin/master`.

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

Podruhé tamtéž 2026-09-02, větev `BlanketOrders_64046` po squashi PR 9380 (`96a7513`): jediný
„konflikt" byl trans-unit `Codeunit 1429337669 - NamedType 3648368596`, který obě strany přidaly
na **jinou pozici** v `.cs-CZ.xlf` (HEAD o 12 řádků níž než master) — resoluce = nechat pozici
masteru a HEAD blok zahodit (vzít obojí = AL0479 duplicita, viz 6.4). `git diff --cached
origin/master` po resoluci prázdný → merge commit má strom bit-identický s masterem; kompilaci
pak dokazuje zelený CI build masteru (28038) na tomtéž stromu, lokální `alc` netřeba. Nová dependency
z masteru `Banking Documents Localization for Czech` má symbol 28.3 na MSSymbols feedu pod ID
s infixem `.cz.` (viz 7.12) — staré ID bez infixu končí u 27.0.x, tam bys ho marně hledal.

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
- **Force Sync NENÍ jen sandbox:** od BC19 jde PTE nasadit se *Schema Sync Mode = Force* i na
  SaaS **produkci** (Extension Management → page 2507 *Upload And Deploy Extension*, Admin Center
  → Manage Apps → Sync Mode, automation API `schemaSyncMode`). Cena = nenávratná ztráta dat
  odstraněných polí (jen point-in-time restore). U appky s live zákazníkem proto radši
  `ObsoleteState = Pending` (verze N, upgrade codeunit pole ještě přečte) → `Removed` (N+1).
  (Ověřeno ve zdroji System Application 28.3 `UploadAndDeployExtension`, 2026-08-31.)
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
  které skočí rovnou z verze N−1 na N+1, spadne stejně. U live zákazníka to
  skládej s bodem výše: `Pending` (N, migrace dat) → `Removed` (N+1) → smazat (N+2).
- ⚠️ ForceSync **nenávratně zahodí data** odstraněných polí — u zákazníka v ostrém
  provozu patří před destruktivní změnu obsolete fáze + migrace, ne ForceSync.
  (Zachyceno 2026-08-05, prod-epb-pricingMatrix-bc build 27692 — odstranění
  Width/Height PMEBS při parametrizaci os; zákazník nebyl live → ForceSync OK.)

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

### 7.20 Release deploy: „You must install .NET to run this application" (altool.exe) = agent bez .NET 10 runtime

Classic Release (`Publish-PerTenantExtensionApps`, SaaS deploy přes Automation API) spadne
po pár sekundách s `PowerShell exited with code '1'`; v logu těsně před tím:

```
You must install .NET to run this application.
App: C:\ProgramData\BcContainerHelper\alLanguageExtension\18.0.2732683\extension\bin\altool.exe
App host version: 10.0.12
.NET location: Not found
  Environment variable: DOTNET_ROOT_X64 = <not set> / DOTNET_ROOT = <not set>
  Default location: C:\Program Files\dotnet
ExitCode: -2147450749
Commandline: ...altool.exe GetPackageManifest "<appka>.app"
At ...\BcContainerHelper\6.1.18\HelperFunctions.ps1:130
```

- **Příčina:** BcContainerHelper (od 6.1.18 ověřeno) čte manifest `.app` přes **`altool.exe`
  z nejnovější AL Language extension** (18.x), která je **apphost pro .NET 10**. Agent
  bez .NET 10 x64 runtime (má třeba jen .NET 6/8 — „.NET tam určitě je") to nespustí.
  Není to chyba appky ani repa — **retry na tomtéž agentovi nepomůže.**
- **Diagnóza:** řádek `Agent: <jméno>` v hlavičce jobu. Srovnej s posledním zeleným
  deployem / druhou stage téhož releasu — v poolu `Essence` se agenti liší výbavou
  (2026-09-14: `LAB-DOCK-APP22-2` padá, `LAB-DOCK-BLD22-6` s tímtéž helperem 6.1.18
  prošel). Pool přiděluje agenta náhodně, proto „dvakrát stejná chyba" = dvakrát
  ten samý agent.
- **Fix na agentovi (pipeline tým / Igor):** doinstalovat **.NET 10 Runtime x64**
  (odkaz z logu `aka.ms/dotnet-core-applaunch?...apphost_version=10.0.12`), nebo
  nastavit `DOTNET_ROOT` na existující instalaci .NET 10. Alternativa v šabloně:
  `$bcContainerHelperConfig.alToolVersion`/pinnout starší AL extension, ale to je
  workaround, ne řešení.
- **Workaround hned:** Redeploy, dokud stage nepadne na agenta, který .NET 10 má
  (nebo dočasně `demands` na jméno agenta v release definici).
- Bonus z téhož dne: `-schemaSyncMode ForceSync` u `Publish-PerTenantExtensionApps`
  **není platná hodnota** — ValidateSet je jen `Add, Force` (sandbox attempt #1 releasu
  14979). V release variables tedy `Force`, ne `ForceSync` (Sync-NavApp má naopak
  `ForceSync`, viz 7.18).

Zachyceno 2026-09-14, cust-alumistr-bc release 14979 (28.0.29), stage „deploy to live". Totéž
den předtím prod-epb-pricingMatrix-bc release 14970 (28.0.5): attempt #1 na APP22-2 identický
pád, attempt #2 (Redeploy) na BLD22-6 prošel — Redeploy jako workaround ověřený.
