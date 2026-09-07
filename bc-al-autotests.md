# Business Central / AL – autotesty (poznámky z praxe)

Sběrnice znalostí o psaní automatizovaných testů v AL pro Business Central. Roste s tím, jak budeme testy psát a narážet na věci.

## ⚠️ Povinnost autotestů — kdy testy psát

**Autotesty jsou povinná součást implementace každé netriviální funkčnosti** —
nová business logika, validace, výpočty, posting / propagace dat přes víc
tabulek, integrace, nový business flow. Nečekej, až si je uživatel vyžádá —
naplánuj je rovnou jako součást úkolu a zmiň je v souhrnu odvedené práce.

**Kdy testy NEpsat** (banality, kde by byly jen ceremonie):

- pouhé přidání pole na tabulku/page bez vlastní logiky (žádný OnValidate
  s business pravidlem)
- Caption / ToolTip / Description úpravy, překlady XLIFF
- kosmetické UI změny (přesun pole, visibility, action image, cuegroup)
- čistý refactor beze změny chování, který už je pokrytý stávajícími testy

**Šedá zóna** (použij úsudek, případně se zeptej): drobný event subscriber
s jednoduchou propagací hodnoty — pokud nese business pravidlo (podmínky,
transformace), test ano; pokud jen kopíruje pole 1:1, stačí bez testu.

Pokud testovaný scénář nejde spolehlivě postavit (nestabilní action names,
UI-only trigger…), zaznamenej blokátor a řekni to uživateli — **nepiš fake
placeholder testy** (viz „Placeholdery v testech jsou škodlivější než žádné
testy" níže).

## 🎯 Kanonický vzor pro Essence prod moduly — řiď se configuratorem

**Pravidlo palce pro každý nový test app v Essence produktovém modulu:** vzorem je
`prod-ess-configurator-bc/test` (a `prod-ef-advanceCZ-bc/test`, který ho kopíruje).
**Nevymýšlej pro každý modul vlastní testovací infrastrukturu** — používej MS
`Tests-TestLibraries`. Jeden sdílený vzor napříč moduly, ne snowflake per appka.

- **`Assert` codeunit = MS `Assert` (130000)** z `Tests-TestLibraries`. **Žádné
  vlastní `Assert ZLK` / `Assert COEBS`.** Metody: `IsTrue`, `IsFalse`, `AreEqual`,
  `AreNotEqual`, `RecordIsEmpty`, `RecordCount`, `ExpectedError`, …
- **Standardní BC entity** (Customer, Item, Sales/Purchase doc, G/L účet, Payment
  Method, Location…) → MS `Library - Sales` / `Library - Inventory` / `Library - ERM`
  / `Library - Utility` / `Library - Test Initialize`. Nepiš si vlastní `CreateCustomer`
  apod.
- **Vlastní test library codeunit píšeš JEN jako data factory pro custom tabulky
  daného modulu** (vzor `Config. Test Library COEBS`, `EF Advance Test Library AOEBS`).
  Wrappuje MS `Library - *` helpery + přidává `Create*` procedury pro vlastní tabulky
  modulu. Standardní entity necháváš na MS knihovnách.
- **`app.json`**: `"target": "Cloud"` + deps `Test Runner`, `Tests-TestLibraries`,
  `System Application Test Library` (+ `AI Test Toolkit` jen když ho fakt potřebuješ).
  Plus explicitní dep na **každou** knihovnu / extension, jejíž typy přímo používáš
  (např. `Advance Payments Localization for Czech` kvůli `Sales Adv. Letter Header CZZ`).
- **`AppSourceCop.json`** v `test/` s `mandatoryAffixes` (+ `supportedCountries`
  u lokalizačních modulů, např. `["CZ"]`).
- Codeunit: `Subtype = Test;` + `TestPermissions = Disabled;`. Test codeunity čísluj
  **od konce idRange** (60149, 60148, …) — sdílený codeunit namespace, hlavní appka
  roste odspodu.
- `Initialize()` pattern přes `Library - Test Initialize`
  (`OnTestInitialize` / `OnBeforeTestSuiteInitialize` / `OnAfterTestSuiteInitialize`).
- AAA komentáře `[SCENARIO]` / `[GIVEN]` / `[WHEN]` / `[THEN]`, případně `[FEATURE]`.
  UI volání → `[HandlerFunctions('MessageHandler')]` + handler v téže codeunit.

**Proč to funguje s Cloud targetem:** `Tests-TestLibraries` je onprem-only, ale
**po pull requestu se u nás buildí a na serveru vzniká testovací BC databáze OnPrem
(kontejner/CI)**, kde test codeunity i MS libraries žijí. Test app se **nikdy
nedeployuje do SaaS produkce** — jen do CI / kontejneru / dev sandboxu. Cloud target
appky se tedy proti té OnPrem test DB normálně zkompiluje i odběhne. Cajk.

> ⚠️ **Vlastní `Assert` / `Library` helpery (sekce „SaaS Cloud target = vlastní
> helpery", „Minimal vlastní Assert ZLK", „Vlastní helpery bez Library-*" níže) jsou
> FALLBACK jen pro scénář bez OnPrem CI** — čistý SaaS-only deploy test appky, kde
> `Tests-TestLibraries` není k dispozici. **Pro Essence prod moduly to NEpoužívej** —
> máme OnPrem build, takže default jsou MS knihovny. Sekce nech v souboru jako
> referenci pro ten okrajový případ.

## Základy

- Testovací objekty žijí v samostatném **test app** (vlastní `app.json`) – ne v produkčním extension
- `app.json` test appky má `"target": "OnPrem"` nebo `"Cloud"` dle prostředí + závislost na produkčním extension a na `Tests-TestLibraries` / `System Application Test Library` / `Test Runner`
- Codeunit s `Subtype = Test` – každá `[Test]` procedura je jeden testcase
- Spuštění: VS Code → AL: Run Tests, nebo přes Test Tool stránku (130401) v BC klientu

## Atributy testovacích procedur

- `[Test]` – běžný test
- `[HandlerFunctions('MyMsgHandler,MyConfirmHandler')]` – registrace UI handlerů (Message, Confirm, ModalPage, Report, Request page, StrMenu, Session settings)
- `[TransactionModel(...)]` – transakční chování test metody:
  - `AutoCommit` – **default** (dle MS docs „AutoCommit is the default value").
    `Commit()` v testu je povolený a funguje jako savepoint — při erroru
    (i chyceném přes `asserterror`) se rollbackuje jen k poslednímu Commitu.
    Úklid DB po testech řeší test runner přes `TestIsolation` (viz níže).
  - `AutoRollback` – rollback po testu; **`Commit()` v testu hodí error**
    („Calls to the COMMIT function during a test that is set to AutoRollback
    fail with an error")
- `[FailOnMissingPermission(true)]` – test selže, pokud chybí permission
- `[HttpClientHandler('MyHttpHandler')]` – mock HTTP volání (BC 22+)

## Handler funkce – typy

```al
[MessageHandler]
procedure MyMsgHandler(Message: Text) begin end;

[ConfirmHandler]
procedure MyConfirmHandler(Question: Text[1024]; var Reply: Boolean) begin Reply := true; end;

[ModalPageHandler]
procedure MyPageHandler(var MyPage: TestPage "My Page") begin end;

[ReportHandler]
procedure MyReportHandler(var MyReport: Report "My Report") begin end;

[RequestPageHandler]
procedure MyReqPageHandler(var ReqPage: TestRequestPage "My Report") begin end;

[StrMenuHandler]
procedure MyStrMenuHandler(Options: Text; var Choice: Integer; Instruction: Text) begin Choice := 1; end;
```

## AAA pattern (Arrange-Act-Assert)

Doporučený MS pattern:

```al
[Test]
procedure MyTestName()
var
    Customer: Record Customer;
begin
    // [SCENARIO] Krátký popis co se testuje
    Initialize();

    // [GIVEN] Příprava dat
    LibrarySales.CreateCustomer(Customer);

    // [WHEN] Spuštění akce
    Customer.Validate(Name, 'Test');
    Customer.Modify(true);

    // [THEN] Ověření výsledku
    Assert.AreEqual('Test', Customer.Name, 'Name should match');
end;
```

## Test Libraries (MS-poskytované)

Nejpoužívanější knihovny v `Tests-TestLibraries`:

- `Library - Sales` – `CreateCustomer`, `CreateSalesHeader`, `CreateSalesLine`...
- `Library - Purchase` – obdoba pro nákup
- `Library - Inventory` – `CreateItem`, `CreateLocation`...
- `Library - Random` – `RandInt`, `RandDec`, `RandText`
- `Library - Utility` – `GenerateGUID`, `GenerateRandomCode`...
- `Library - ERM` – G/L účty, dimenze, posting groups
- `Library - Setup Storage` – záloha/restore setupů mezi testy
- `Assert` codeunit (130000) – `AreEqual`, `AreNotEqual`, `IsTrue`, `RecordCount`, `ExpectedError`, `ExpectedMessage`...

## TestPage – simulace UI

```al
var
    CustomerCard: TestPage "Customer Card";
begin
    CustomerCard.OpenEdit();
    CustomerCard.GotoRecord(Customer);
    CustomerCard.Name.SetValue('New Name');  // simuluje uživatele, spustí OnValidate
    CustomerCard.Name.AssertEquals('New Name');
    CustomerCard.Close();
end;
```

- `SetValue` na poli triggeruje OnValidate (jako uživatel) – na rozdíl od `Customer.Name := 'X'`
- `Invoke()` na akci – spustí action trigger
- `OK.Invoke()` / `Cancel.Invoke()` na modální stránce
- Pro RequestPage reportu: `TestRequestPage` + handler

## ExpectedError pattern

```al
asserterror Customer.Delete(true);
Assert.ExpectedError('You cannot delete...');
// nebo přesněji:
Assert.ExpectedErrorCode('Dialog');
```

## Permission tests

- `[Test] [FailOnMissingPermission(true)]`
- Před testem: `LibraryLowerPermissions.SetO365Basic()` (nebo jiný profil)
- Po: `LibraryLowerPermissions.SetOutsideO365Scope()` pro reset

## Code coverage

- VS Code: `AL: Test Code Coverage` – generuje coverage report
- `launch.json` musí mít `"enableSqlInformationDebugger": true` a test runner config

## Best practices

- **Initialize() pattern**: každý test začíná `Initialize()` codeunit-level proceduru, která dělá one-time setup (`isInitialized` flag) a per-test reset. Standardní MS varianta jede přes `Library - Test Initialize` (`OnTestInitialize` → `if isInitialized exit` → `OnBeforeTestSuiteInitialize` → `Commit()` → `OnAfterTestSuiteInitialize`). **Pozor — LinterCop LC0002 vyžaduje komentář u každého `Commit()`** (i v testech), jinak warning. U suite-setup commitu použij např.: `Commit(); // Persist one-time suite setup as a savepoint so it survives the rollback between individual tests.`
- **Žádné hard-coded ID** – vše přes `Library` helpery, které generují unikátní hodnoty
- **Jeden test = jeden scénář** – nesmí na sobě záviset (Test Runner každý test odroluje, ale data commitnutá uvnitř codeunitu vidí testy, co běží po něm — viz `asserterror` níže → unikátní kódy, vlastní batch)
- **Komentáře `[SCENARIO]`, `[GIVEN]`, `[WHEN]`, `[THEN]`** – čitelnost + automatické reporty
- **Test data v testu, ne v setupu** – ať je vidět co se testuje
- **Negative testy** – `asserterror` + `Assert.ExpectedError` pro očekávaná selhání

## Gotchas

- **`Library - Setup Storage`: pohodlné wrappery `SaveSalesSetup()` / `SavePurchasesSetup()` / `SaveGeneralLedgerSetup()` …
  mají scope OnPrem** → v test appce s `"target": "Cloud"` `error AL0296 ... has scope 'OnPrem'`. Použij generické
  `LibrarySetupStorage.Save(Database::"Sales & Receivables Setup")` + `Restore()` v `Initialize()` (Restore hned po
  `OnTestInitialize`, Save při prvním suite initu před `Commit`). Izoluje změny setupu i při lokálním běhu
  v dev kontejneru, kde po testu nezůstane v setupu testovací zákazník. (2026-09-04, cust-alumistr-bc 65916)
- **Editace řádků prodejního dokladu přes `TestPage "Sales Order".SalesLines`** (`"No."`/`Quantity`/`"Variant Code"`
  `.SetValue`) — před tím `LibrarySales.SetStockoutWarning(false)` + `LibrarySales.SetCreditWarningsToNoWarnings()`,
  jinak base hlásí dostupnost/kreditní limit (notifikace/dialogy) a test padá na neobslouženém UI. Confirm/Message
  z table triggeru s guardem `CurrFieldNo = FieldNo(X)` vyvolá jen TestPage; `Rec.Validate` má `CurrFieldNo = 0` →
  negativní test „změna z kódu je tichá" = test bez `[HandlerFunctions]`. Odmítnutý Confirm (`Error('')`) testuj
  `[ConfirmHandler]` s `Reply := false` + `asserterror Page.Field.SetValue(...)`; GIVEN data před tím `Commit()`
  (rollback k poslednímu commitu) a assertuj jen DB stav, ne `ExpectedError('')` (`StrPos(x, '')` = 0 → vždy fail).
  (2026-09-07, prod-ess-configurator-bc `Attached Lines Tests COEBS`)
- **`MinValue`/`MaxValue`/`NotBlank` na poli programový `Rec.Validate()` NEvynucuje** —
  jsou to UI-entry kontroly (TestPage `SetValue` je chytí, record Validate ne).
  `asserterror VATMap.Validate("Rate", -5)` nad polem jen s MinValue spadne na
  „an error was expected". Test range validace = buď TestPage, nebo (lépe) doplň
  do pole explicitní `OnValidate` check s Error — pak platí i pro programové zápisy
  (config packages, kód). (2026-08-05, dotykackaConnector build 27689.)
- **Expected DateTime nikdy přes `CreateDateTime`, když testuješ instant sémantiku**
  (unix timestamp, ISO parsing): `CreateDateTime` vyrábí lokální wall-clock a
  „expected vzniká stejně jako actual → timezone-safe" NEPLATÍ přes DST — offset
  epochy (leden, CET +1) ≠ offset letního data (CEST +2), na CZ runneru to ujede
  o hodinu. Správně `Evaluate(ExpectedDT, '2024-06-11T14:40:00Z', 9)` (UTC-aware),
  viz 5.5 v bc-al-objects. Round-trip testy (tam a zpět touž funkcí) jsou OK s obojím.
- `Commit()` v testovaném kódu z test runu neprosákne (TestIsolation odroluje i explicitní commity), ale commitnutá data **vidí následující testy v téže codeunit** → izoluj data (unikátní kódy, vlastní batch); `AutoRollback` model `Commit()` rovnou zakazuje (error)
- Handler musí být v **stejné codeunit** jako test, který ho používá (nebo registrovaný přes `[HandlerFunctions]`)
- Pokud test spustí UI a chybí handler → **test selže** s "no handler"
- `TestPage` neumí všechno – pole s `AssistEdit`, některé FactBoxy a custom controly mají omezení
- Permission testy musí běžet pod **NAVUserPassword** auth, ne Windows

## Spouštění z CLI / CI

- `BcContainerHelper`: `Run-TestsInBcContainer` – PowerShell
- AL-Go for GitHub: má built-in test step
- Lokálně: VS Code task nebo `bc-test-runner` extension
- **VS Code extension `ALTestRunner`** (luc-vandyck) — codelens "Run Test" /
  "Debug Test" přímo v editoru. Nejrychlejší dev loop. Vyžaduje launch.json
  setup (sandbox/Docker container). Pro denní vývoj jeď ALTestRunner, pro
  release ověření Test Tool page (130401).

## `TestPermissions` — kdy co

> ⚠️ **Default je `Restrictive`, NE `Disabled`!** Když property vynecháš, test
> neběží pod SUPER — Insert/Modify do tabulek cizích extensions (např.
> `Shpfy Shop` ze Shopify Connectoru) spadne na *"Sorry, the current
> permissions prevented the action. (TableData 30102 Shpfy Shop … Insert:
> <test app>)"*. Proto `TestPermissions = Disabled;` piš do KAŽDÉHO test
> codeunitu explicitně. (Chyceno: cust-sonnentor-bc, TestWebshopFilterSON,
> build 27416, červenec 2026 — testy bez property padaly na insert do
> Shpfy Shop, testy bez DB zápisů prošly.)

- **`Disabled`** — test běží pod `SUPER`, žádné permission checky.
  Použij, když permissions nejsou předmětem testu (= 95 % případů).
  Cloud-friendly a zrychluje běh testů. **Vždy uváděj explicitně.**
- **`Restrictive`** (default!) — test běží pod definovaným permission set z `app.json`.
  Použij, když explicitně testuješ, že feature funguje i pro non-SUPER usera
  (typicky AppSource validace).
- **`NonRestrictive`** — kombo: SUPER + filtruje permission set z app.json.
  Mezistupeň, používá se zřídka.

`Restrictive` zapínej až ve chvíli, kdy řešíš permission bug nebo certifikaci.

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

### Test app nepotřebuje vlastní permissionset

**Do test appky NEpiš permissionset** (execute permissiony na test codeunity).
Je to mrtvý objekt — testy u nás běží **lokálně na serveru v dočasně
vytvořeném OnPrem BC prostředí (kontejner/CI) pod `SUPER`**, a všechny test
codeunity mají `TestPermissions = Disabled` (= taky `SUPER`). Permissionset
by se uplatnil jen u `Restrictive` testů, které stejně nepíšeme (viz výše).
Žádný `*.PermissionSet.al` v `test/src/` → jeden objekt míň, žádný affix/ID
k řešení. (Zachyceno: prod-ess-dotykackaConnector-bc, červen 2026.)

## Poznámky z praxe (Zlomek Extension – první testy)

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

### Spuštění reportu bez request page

Když má report `ProcessingOnly = true` ale automaticky vygenerovanou request page (přítomnost `RequestFilterFields` na `dataitem`), pro automatizaci v testu:

```al
SalesHeader.SetRecFilter();
Report.RunModal(Report::"Update Sales Adv. Status ZLK", false, false, SalesHeader);
//                                                       ^^^^^ ReqWindow = false → bez UI
```

`SetRecFilter()` nastaví filtr na 1 záznam, který se použije v dataitemu reportu (pokud má `DataItemTableView` se sortem na PK).

### `[EventSubscriber(OnBeforeActionEvent, ...)]` nelze invokovat externě

Subscribery na `OnBeforeActionEvent` na page actions se vyvolají **jen** když uživatel klikne na akci nebo když test simuluje klik přes `TestPage`:

```al
SalesOrderPage: TestPage "Sales Order";
SalesOrderPage.OpenEdit();
SalesOrderPage.GotoRecord(SalesHeader);
asserterror SalesOrderPage."Calculate Regen. Plan".Invoke();
Assert.ExpectedError('must have status Released');
```

Pokud je `CheckSalesHeaderReleased` (nebo podobná validační procedura) `local`, nemůžeš ji volat přímo z testu. **Trade-off:** buď refactor na `internal/public`, nebo testovat přes `TestPage` (fragile, závislé na exact action names z extension).

### Cyklický Production BOM v testech

`ProdBOMHeader.Validate(Status, ProdBOMHeader.Status::Certified)` má vestavěnou cycle detection a vrátí error. Pro test cyklického BOM:

1. Vyrob BOM přímými `Insert(false)` (header + lines obě tabulky)
2. Status nastav přímo `ProdBOMHeader.Status := ProdBOMHeader.Status::Certified; Modify(false);`

Tím obejdeš certify routine a můžeš testovat `VisitedItems` cycle guard v aplikační logice.

### ⚠️ `LibraryInventory.CreateItem` — base UoM = PRVNÍ Unit of Measure v abecedě (data-dependent kolize!)

`CreateItem` → `CreateItemWithoutVAT` → `CreateItemUnitOfMeasure(ItemUoM, ItemNo, '', 1)`
a ta s prázdným kódem dělá **`UnitOfMeasure.FindFirst()`** — vezme abecedně PRVNÍ
existující Unit of Measure a založí ji itemu jako base UoM (Qty=1, ostatní pole 0).

Důsledek: když dřívější test v témže codeunitu založí globální Unit of Measure
s kódem, který se řadí na začátek abecedy (**číslice < písmena** — např. `1200/62.5`),
KAŽDÝ další `CreateItem` dá novému itemu base UoM s TÍMTO kódem. Logika, která pak
dohledává Item UoM podle (vygenerovaného) kódu, najde base UoM bez vyplněných polí
→ „záhadné" faily závislé na pořadí testů (dřívější testy zelené, pozdější červené,
lokálně těžko reprodukovatelné).

- **Prevence v produkčním kódu:** při dohledání jednotky podle kódu nikdy slepě
  nepřebírat existující záznam — ověřit i hodnoty polí, o které jde (viz
  prod-epb-pricingMatrix `CreateRasterUOM`: osy sedí → použij; osy 0/0 → doplň;
  jinak error).
- **Prevence v testech:** pro jednotky zakládané testem používat
  `LibraryInventory.CreateItemUnitOfMeasureCode` / `GenerateRandomCode` kódy;
  nepředpokládat, že base UoM nového itemu je „neutrální".
- Zachyceno 2026-08-05, prod-epb-pricingMatrix-bc build 27690: test suite spadla
  až na 7. testu — CreateItem přiřadil itemu base UoM `1200/62.5` založenou 6. testem.

### Library helper konvence pro per-extension testy

Vytvoř vlastní `Library - <Extension> ZLK` codeunit:

- Wrappuje MS `Library - *` helpery + přidává `Create*` procedury pro vlastní tabulky
- Vrací `Code[20]` / `Code[10]` jako return value, plný record přes `var` parametr (umožňuje `:=` chaining)
- Pro custom Code generation: `LibraryUtility.GenerateRandomCode(FieldNo, Database::TableName)` + `CopyStr(..., 1, MaxStrLen)` (kompiler hlaše varování bez `CopyStr`)

### `Library - Manufacturing` není vždycky dostupné

Pokud chybí v `Tests-TestLibraries` build pro tvůj region (u některých CZ buildů chybělo; `prod-ess-configurator-bc/test` ho normálně používá — ověř v symbolech / na MSSymbols feedu, viz 7.12 v `bc-al-build.md`), Production BOM Header / Routing helper si musíš napsat sám:

```al
procedure CreateCertifiedProdBOMHeaderForItem(var ProdBOMHeader: Record "Production BOM Header"; ParentItem: Record Item)
begin
    ProdBOMHeader.Init();
    ProdBOMHeader."No." := CopyStr(LibraryUtility.GenerateRandomCode(...), 1, MaxStrLen(...));
    ProdBOMHeader."Unit of Measure Code" := ParentItem."Base Unit of Measure";
    ProdBOMHeader.Insert(true);
end;
```

### `TestPermissions = Disabled` na začátek

V kódu testů přidej `TestPermissions = Disabled;` na codeunit-level pokud nechceš řešit permission setup pro každý test. Pro permission testy naopak `[Test] [FailOnMissingPermission(true)]` + `LibraryLowerPermissions.SetO365Basic()`.

### ConfirmHandler signatura

```al
[ConfirmHandler]
procedure ConfirmYesHandler(Question: Text[1024]; var Reply: Boolean)
begin
    Reply := true;
end;
```

`Question` musí být `Text[1024]`, ne `Text` — jinak handler nebude rozeznán.

### `Report.RunModal` parametry

```al
Report.RunModal(ReportID: Integer; ReqWindow: Boolean; SystemPrintRecPage: Boolean; RecRef/Rec: Variant);
```

- `ReqWindow = false` → request page se neukáže (test mode)
- `SystemPrintRecPage = false` → pro `ProcessingOnly` reporty nehraje roli
- 4. parametr je filtr pro dataitem (typicky předfiltrovaný `var Record`)

### Generování krátkých unique kódů z GUID

`CopyStr(CreateGuid(), 1, 10)` **nezkompiluje** — `CreateGuid()` vrací `Guid`, `CopyStr` chce `Text/Code`. Správně:

```al
WkshTemplateName := CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 10);
```

`Format(CreateGuid())` vrátí `{xxxxxxxx-xxxx-...}`; `DelChr(..., '=', '{}-')` smaže závorky a pomlčky. Lepší alternativa pro skutečné Code-style identifikátory: `LibraryUtility.GenerateRandomCode(FieldNo, Database::TableName)`.

### `asserterror` rollbackne GIVEN data — před kontrolou DB stavu dej `Commit()`

Error uvnitř `asserterror` vrátí **celou nezakomitovanou transakci** — tedy i
GIVEN data vytvořená před `asserterror`. Pokud po `Assert.ExpectedError` chceš
ověřit, že se v DB nic nezměnilo (record pořád existuje, qty nedotčená),
dostaneš *"The ... does not exist"*, protože setup zmizel s rollbackem.

```al
// GIVEN
CreateTestData(SalesLine);
Commit(); // bez tohohle expected error odrolluje i GIVEN data

// WHEN
asserterror DoSomethingThatFails(SalesLine);

// THEN
Assert.ExpectedError('...');
SalesLine.Get(...); // díky Commit() záznam pořád existuje
```

Pod standardním Test Runnerem (TestIsolation = Codeunit, isol. codeunit 130450)
je `Commit()` bezpečný — po doběhnutí test codeunitu se odrolluje všechno
**včetně explicitně commitnutých dat** (MS docs k TestIsolation: „all database
changes are rolled back, including changes that were explicitly committed …
by using the Commit Method"). Mechanismus rollback-k-poslednímu-Commitu je
dokumentovaný u `TransactionModel` (AutoCommit, default): „If the code … calls
the COMMIT Function before an error occurs, then the transaction is rolled
back only to the point at which the COMMIT was called."

**Caveat:** commitnutá data vidí následující testy ve **stejném** codeunitu
(úklid běží až po codeunitu) — testy nesmí spoléhat na prázdnou DB, generuj
unikátní kódy. A pozor: s atributem `[TransactionModel(AutoRollback)]` na
metodě `Commit()` hodí error. (Chyceno v praxi: prod-ess-configurator-bc,
tracking split negativní test, run 18098.)

**Varianta: dva `asserterror` za sebou v jednom testu.** První `asserterror`
odroluje GIVEN data; když testovaná validace při chybějícím záznamu **tiše
exituje** (typicky `if not Rec.Get(...) then exit;` před vlastní kontrolou),
druhý `Validate` už žádný error nehodí a `asserterror` spadne na „an error was
expected". Lokálně to nevypadá jako rollback problém — fix je `Commit();` po
GIVEN (s komentářem), nebo každý negativní případ do vlastního testu. Zachyceno
2026-08-27, cust-alumistr-bc build 27980 (`FilterValueCodesRejectsNonNumeric…`,
`CheckNumericFilterValue` s `SourceParam.Get` → exit) — stejný test i
v prod-ess-configurator-bc PR 9375.

### Carry Out Action Message v testu bere CELÝ list sešitu — každý carry-out test si zakládá vlastní batch

`LibraryPlanning.CarryOutReqWksh(ReqLine, …)` → report 493 → `Req. Wksh.-Make Order.Code()`
filtruje jen `Worksheet Template Name` + `Journal Batch Name` (+ `Accept Action Message = true`)
podle předaného řádku — filtry na záznamu se sice kopírují (`ReqLine.Copy`), ale test je
typicky nemá. A **každý řádek sešitu založený přes `Validate("No.")` má `Accept Action
Message = true`** (`Requisition Line.CopyFromItem()` nastaví `Accept Action Message := true`
a `Action Message := New`). Kombinace s AutoCommit (data dřívějších testů téhož codeunitu
v DB zůstávají): carry-out ve **sdíleném** batchi (`FindFirst` na existující jméno listu)
zpracuje i řádky, které tam nechaly předchozí testy — vzniknou další nákupky, vyskočí jejich
confirmy (jiní dodavatelé/rámcovky → jiné cache klíče), případně to spadne na jejich datech.
Typický příznak: assert na počet confirmů (`Expected 2, Actual 6`) nebo „záhadné" faily
závislé na pořadí testů (první carry-out test v codeunitu projde, pozdější ne).

**Fix:** carry-out test si vždy založí vlastní batch
(`LibraryPlanning.CreateRequisitionWkshName(NewName, TemplateName)`) a řádky dává do něj;
sdílený list nechat jen testům, které carry-out nevolají. Zachyceno 2026-08-28,
cust-sonnentor-bc PR 9380 build 27993 (`ReqCarryOutRechecksRemainingQuantity`).

### Placeholdery v testech jsou škodlivější než žádné testy

`Assert.IsTrue(true, ...)` nebo `[Test]` procedura, která ve skutečnosti nic neověří, **dělá test suite zelenou bez regresní ochrany**. Pokud nemůžeš testovaný scénář spolehlivě postavit (např. `OnBeforeActionEvent` subscribery vyžadují TestPage + nestabilní action names), je správné nechat soubor bez `[Test]` procedur a zaznamenat blokátor v `plan.md`/issue, ne psát fake testy.

### Essence prod moduly: test app `target: Cloud` + Tests-TestLibraries JE validní kombinace

> Shrnutí téhle sekce + kdy vlastní helpery vs. MS knihovny řeší **kanonická sekce
> nahoře** („🎯 Kanonický vzor pro Essence prod moduly"). Tady jsou detaily proč to
> s Cloud targetem projde.

Vzor `prod-ess-configurator-bc/test/app.json`: **`"target": "Cloud"` + dependencies
`Test Runner` + `Tests-TestLibraries` + `System Application Test Library`** (případně
`AI Test Toolkit`) a normálně používá `Library - Inventory/Sales/Manufacturing` +
`Assert`. **Kompilace s Cloud targetem projde** a testy běží v BC kontejneru
(`installTestLibraries:true` v Local-DevEnv / CI pipeline). Omezení z následující
sekce se týká **nasazení do SaaS sandboxu** (tam Tests-TestLibraries nenainstaluješ),
ne kompilace ani container běhu. Pro Essence produktové moduly drž vzor
configuratoru — Cloud target, test library deps, testy pouštět jen v kontejneru/CI.
Do `test/` složky patří i vlastní `AppSourceCop.json` s `mandatoryAffixes`.

### SaaS Cloud target = vlastní helpery (Tests-TestLibraries je onprem-only)

> ⚠️ **FALLBACK, ne default.** Tahle a následující dvě sekce („Minimal vlastní
> Assert ZLK", „Vlastní helpery bez Library-*") platí **jen pro čistý SaaS-only
> deploy test appky bez OnPrem CI**. **Pro Essence prod moduly to NEpoužívej** —
> máme OnPrem build (testovací BC DB se po PR vytvoří na serveru), takže jedeme MS
> `Tests-TestLibraries`. Viz kanonická sekce nahoře. Tohle nech jen jako referenci.

`Tests-TestLibraries` (publisher Microsoft, ID `5d86850b-0d76-4eca-bd7b-951ad998e997`) **není v Cloud SaaS targetu dostupná**. Je publikována jako onprem-only. `System Application Test Library` (ID `9856ae4f-...`) sice jde nainstalovat v SaaS, ale obsahuje hlavně mocky pro System modules (Email, AI, Permissions) — **nemá** business helpery (`Library - Sales/Inventory/ERM/...`) ani univerzální `Assert` codeunit.

Pro AL test app s `"target": "Cloud"`:

1. V `app.json` **nesmí** být dependency na `Tests-TestLibraries`. Pak ji nelze deployovat ani lokálně do SaaS sandboxu.
2. Pokud chceš sdílet kompilační target s produkčním Cloud appem, **napiš si vlastní minimal helpery** (Assert + LibraryX wrapper).
3. Test app fyzicky publikujete jen do dev kontejneru / sandbox / CI — produkční tenant ji nikdy neuvidí. Ale i kompilace musí být Cloud-compatible (žádné `DotNet`, `File`, `Assembly`, …).

Alternativa: nechat test app `"target": "OnPrem"` + závislost `Tests-TestLibraries`. Test app pak ale jde jen do container/CI/dev sandboxu, do SaaS produkce nikdy.

### Minimal vlastní `Assert ZLK` codeunit

Stačí na 90 % testovacích scénářů. `Format(Variant)` zajistí porovnání i pro Decimal/Date/Enum/Code:

```al
codeunit 52329 "Assert ZLK"
{
    procedure AreEqual(Expected: Variant; Actual: Variant; Msg: Text)
    begin
        if Format(Expected) <> Format(Actual) then
            Error('Assert.AreEqual failed: %1\n  Expected: <%2>\n  Actual:   <%3>', Msg, Format(Expected), Format(Actual));
    end;

    procedure IsTrue(Cond: Boolean; Msg: Text) begin if not Cond then Error('IsTrue failed: %1', Msg) end;

    procedure ExpectedError(Expected: Text)
    var
        Actual: Text;
    begin
        Actual := GetLastErrorText();
        if Actual = '' then Error('ExpectedError: no error (expected <%1>)', Expected);
        if StrPos(Actual, Expected) = 0 then Error('ExpectedError: expected <%1>, got <%2>', Expected, Actual);
    end;
}
```

**Pozn.** locale rozdíl pro Decimal — `Format(132.5)` vrací `132.5` v en-US a `132,5` v cs-CZ. Jelikož se však `Format(Expected)` i `Format(Actual)` volá ve stejném testu/locale, vyjde to stejně a porovnání projde.

### Vlastní helpery bez `Library - *` — vzor

Pro Cloud testy nahrazujeme MS Library helpery vlastní implementací. Klíčové triky:

- **Unique kódy** přes GUID:

  ```al
  procedure GenerateUniqueCode20(): Code[20]
  begin
      exit(CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20));
  end;
  ```

  GUID po `DelChr` má 32 znaků hex → zaručeně se vejdou na 10/20/50, žádný retry/sequence.

- **`Sales Header` bez No. Series**: ručně přiřaď `"No."` před `Insert(true)`. `OnInsert` pak nezavolá NoSeriesMgt, pokud je `"No."` neprázdné:

  ```al
  procedure CreateSalesHeader(var SH: Record "Sales Header"; DocType: Enum "Sales Document Type"; CustNo: Code[20])
  begin
      SH.Init();
      SH."Document Type" := DocType;
      SH."No." := GenerateUniqueCode20();
      SH.Insert(true);
      SH.Validate("Sell-to Customer No.", CustNo);
      SH.Modify(true);
  end;
  ```

- **`Sales Line` ručně inkrementovaný `Line No.`** po existujícím `FindLast` na filtru `Document Type` + `Document No.`. Insert(true) PŘED Validate Type/No./Quantity, jinak Validate na neuložené řádce může selhat.

- **Customer/Item/G/L Account**: minimal `Init + "No." := GenerateUniqueCode20() + Insert(true)` funguje pokud máte CRONUS/standard demo data se setupy (Inventory Setup, Sales & Receivables Setup s defaultními posting groups).

- **Release Sales Document**: `Codeunit "Release Sales Document".PerformManualRelease(SH)` — žádný handler nepotřebuje.

### Co vlastní helpery NEZvládnou bez setupu

- **Post Shipment / Post Invoice** — vyžaduje plný posting setup (Customer Posting Group, Gen. Posting Setup, VAT Posting Setup, Inventory Posting Setup, Locations…). Pro tyhle scénáře buď generujte plný setup, nebo nechte E2E v rovině "Release" a posting nezahrnujte.
- **Worksheet Lines (Requisition, Item Journal)**: `"Worksheet Template Name"` musí buď existovat v setupu nebo si ho vyrobte přes ručně přiřazené kódy přes `Insert(false)` (viz Req. Line Mgt. test pattern).

### Re-analýza VS Code po změně `app.json`

Když smažeš dependency v `test/app.json` (např. `Tests-TestLibraries`), VS Code AL extension **necachuje** změnu okamžitě. Diagnostiky stále hlásí "Codeunit 'Library Assert' is missing" pro již refaktorované kódy. Řešení:

1. `Ctrl+Shift+P` → `AL: Download Symbols`
2. Pokud nepomohlo → `Developer: Reload Window`

### Explicitní dependencies v `app.json` (ne transitivní)

Test app s `"target": "Cloud"` musí v `app.json` deklarovat **každou** závislost, jejíž typy přímo používá:

- `Record "Sales Adv. Letter Header CZZ"` → `Advance Payments Localization for Czech`
- `Record "Alternative Prod. BOM ATEBS"` → `EM Alternative BOM and Routing`

Spoléhat na transitive dep přes hlavní extension je sice občas funkční, ale linter / AL kompilátor to nezaručuje a v Cloud targetu to padá.

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
  schová LC0015. Zlomek (`cust-zlomek-bc-test.ruleset.json`) to dělá takhle; configurator
  (`ess-configurator-test.ruleset.json`) **nedědí** a tím o hlavní pravidla přichází —
  ber Zlomek vzor.
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

## Odkazy

- [MS Docs – Testing the Application](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-testing-application)
- [MS Docs – Test Codeunits and Test Functions](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-test-codeunits)
- [ALGuidelines – Testing](https://alguidelines.dev/docs/vibrantcode/testing/)
