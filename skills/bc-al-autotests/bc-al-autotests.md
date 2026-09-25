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
- **Jeden test = jeden scénář** – nesmí na sobě záviset (úklid DB běží až po celém codeunitu a AutoCommit data prošlých testů commitne, takže je vidí testy, co běží po nich — viz `asserterror` a `Library - Random` níže → unikátní kódy, vlastní batch)
- **Komentáře `[SCENARIO]`, `[GIVEN]`, `[WHEN]`, `[THEN]`** – čitelnost + automatické reporty
- **Test data v testu, ne v setupu** – ať je vidět co se testuje
- **Negative testy** – `asserterror` + `Assert.ExpectedError` pro očekávaná selhání

## Gotchas

- **`Library - Setup Storage`: pohodlné wrappery `SaveSalesSetup()` / `SavePurchasesSetup()` / `SaveGeneralLedgerSetup()` …
  mají scope OnPrem** → v test appce s `"target": "Cloud"` `error AL0296 ... has scope 'OnPrem'`. Použij generické
  `LibrarySetupStorage.Save(Database::"Sales & Receivables Setup")` + `Restore()` v `Initialize()` (Restore hned po
  `OnTestInitialize`, Save při prvním suite initu před `Commit`). Izoluje změny setupu i při lokálním běhu
  v dev kontejneru, kde po testu nezůstane v setupu testovací zákazník. (2026-09-04, cust-alumistr-bc 65916)
- **Negativní test `TestStatusOpen` po `ReleaseSalesDocument` — validuj na NOVÉ instanci recordu.** `Sales Line`
  si hlavičku cachuje v globální proměnné instance (`GetSalesHeader` znovu nečte, když sedí Document Type + No.);
  `SalesLine` proměnná, kterou prošel `LibrarySales.CreateSalesLine`, tak drží hlavičku se Status Open i po
  release a `asserterror SalesLine.Validate(pole)` nespadne. Fix: `ReleasedSalesLine.Get(SalesLine."Document Type",
  "Document No.", "Line No.")` a Validate na ní; chybu ověř `Assert.ExpectedTestFieldError(SalesHeader.FieldCaption(Status),
  Format(SalesHeader.Status::Open))` (MS Assert 130000, BC 24+). Undo dodávky v testu bez dialogu: `SalesShipmentLine.SetRecFilter()`
  + `UndoSalesShipmentLine.SetHideDialog(true)` + `.Run(SalesShipmentLine)` (bez `SetRecFilter` projde `Code()` celou
  tabulku); `LibrarySales.UndoSalesShipmentLine` existuje, ale tělo (dialog) z MCP nevidíš. Kompilace test appky: temp
  cache = MS 28.3 symboly + `Test Runner`, `Tests-TestLibraries`, `System Application Test Library`, `Application Test
  Library`, `Permissions Mock` (z dotykacka `.alpackages`) + build hlavní appky — tranzitivní `Any` / `Library Assert` /
  `Library Variable Storage` / `Business Foundation Test Libraries` v cache být NEMUSÍ, alc 17.0 projde.
  ⚠️ Platí jen pro **tranzitivní** závislosti: když je test `app.json` deklaruje **explicitně** (prod-ef-bank-bc/Test má
  `Library Assert`, `Library Variable Storage`, `Any`), alc je chce v cache (`AL1022 … could not be found`). Hotové 28.3
  `.app` bez stahování: `find /c/Users/<user>/AppData/Local/Temp/claude /c/WorkTasks /c/WorkingFolder/AL -maxdepth 6
  -iname "Microsoft_Tests-TestLibraries*"` — scratchpady dřívějších seancí (2026-09: alumistr `testsym/` = Test Runner,
  Tests-TestLibraries, SysApp Test Lib, App Test Lib, Permissions Mock, Library Assert 28.3; soitron `cache/` = Any,
  Library Variable Storage 28.3). Do vlastního `testcache/` zkopíruj, ať kompilace nezávisí na cizím temp adresáři.
  (2026-09-25, prod-ef-bank-bc/Test, `ParseSymbolsFromText` testy.)
- **Undo dodávky označí `Correction = true` i na PŮVODNÍM řádku dodávky** (`Undo Sales Shipment Line.Code`: původní řádek
  dostane `Quantity Invoiced := Quantity`, `Correction := true`, `Modify`; teprve pak `InsertNewShipmentLine` vloží korekční
  řádek se záporným množstvím, taky `Correction = true`). `SetRange(Correction, true) + FindFirst` tedy vrátí původní řádek
  (+4) → `Expected -4, Actual 4`. Korekční řádek filtruj `SetFilter(Quantity, '<0')` (nebo `Line No.` > původní).
  (2026-09-15, cust-alumistr-bc build 28247, `UndoShipmentNegatesSKEndCustomerTotalOnCorrectionLine`.)
- **`LibrarySales.CreateCustomer` si založí firemní kontakt + Contact Business Relation sám** (Marketing Setup v CRONUS má
  `Bus. Rel. Code for Customers`). Když v testu založíš k tomu zákazníkovi DALŠÍ kontakt přes `LibraryMarketing.CreateCompanyContact`
  + `CreateBusinessRelationBetweenContactAndCustomer` a použiješ ho jako Sell-to Contact dokladu, `Sales Header` OnInsert →
  `Bill-to Contact No.` OnValidate → `CheckContactRelatedToCustomerCompany` spadne *„Contact X is related to a different company
  than customer Y"* (`ContBusRel.FindByRelation(Customer, CustNo)` najde první relaci = auto-kontakt). Správně vezmi existující
  kontakt: `ContactBusinessRelation.FindByRelation(ContactBusinessRelation."Link to Table"::Customer, Customer."No.")` →
  `Contact.Get(ContactBusinessRelation."Contact No.")` (fallback na CreateCompanyContact jen když relace není).
  (2026-09-15, cust-alumistr-bc build 28247, `QuoteFromOpportunityIsBilledToOpportunityBillToCustomer`.)
- **Chybové hlášky spadlých testů z CI:** MCP `testplan_show_test_results_from_build_id` vrací jen id/outcome a build log
  „Run Tests in container" jen jména testů. Text chyby + stack: REST
  `https://dev.azure.com/essencebs/Projects/_apis/test/Runs/<runId>/results?outcomes=Failed&api-version=7.1` — s MCP PAT
  vrací HTML (chybí scope Test), ale otevřený v přihlášeném Chromu (Claude in Chrome tab) vrátí JSON
  (`errorMessage`, `stackTrace`). `runId` je v logu kroku Publish Test Results. (2026-09-15)
  (2026-09-07, cust-alumistr-bc 65916, 2. kolo review)
- **Editace řádků prodejního dokladu přes `TestPage "Sales Order".SalesLines`** (`"No."`/`Quantity`/`"Variant Code"`
  `.SetValue`) — před tím `LibrarySales.SetStockoutWarning(false)` + `LibrarySales.SetCreditWarningsToNoWarnings()`,
  jinak base hlásí dostupnost/kreditní limit (notifikace/dialogy) a test padá na neobslouženém UI. Confirm/Message
  z table triggeru s guardem `CurrFieldNo = FieldNo(X)` vyvolá jen TestPage; `Rec.Validate` má `CurrFieldNo = 0` →
  negativní test „změna z kódu je tichá" = test bez `[HandlerFunctions]`. **Odmítnutý Confirm (`Error('')`) přes
  TestPage NEtestuj `asserterror`** — tichý error s prázdnou hláškou TestPage spolkne (`SetValue` doběhne bez výjimky)
  a `asserterror` spadne na „An error was expected inside an ASSERTERROR statement" (CI build 28157). Správně:
  `[ConfirmHandler]` s `Reply := false`, který si otázku uloží do globální proměnné; `Commit()` po GIVEN (tichý error
  přesto odroluje k poslednímu commitu); holé `Page.Field.SetValue(...)`; pak assert, že se otázka položila, a DB stav
  (hodnota nezměněná). `ExpectedError('')` nikdy (`StrPos(x, '')` = 0 → vždy fail).
  (2026-09-07 / oprava 2026-09-09, prod-ess-configurator-bc `Attached Lines Tests COEBS`)
- **Modální `PageType = Worksheet` (i List mimo lookup mode) nemá built-in Cancel.** `TestPage.Cancel().Invoke()`
  v `[ModalPageHandler]` spadne na *„The built-in action = Cancel is not found on the page."* — a reálné BC
  to má stejně: zavření Worksheetu (X, handler bez `Invoke`, `TestPage.Close()`) vrátí z `RunModal()` **`Action::OK`**
  (Cancel vrací jen StandardDialog / PromptDialog / ConfirmationDialog; StefanMaron AL.Runner issues #3059, #3284
  a **ověřeno ručně v BC sandboxu 2026-09-22**: dočasná akce nad seznamem zboží otevřela `Text Formula COEBS` přes
  `RunModal`, zavření křížkem → `Action::OK`). Důsledek: větev `if Page.RunModal() <> Action::OK then <restore>` u Worksheet
  editoru je z UI **nedosažitelná** (backup/restore = mrtvý kód) a test na „Cancel vrátí data" nejde napsat —
  řešení = explicitní akce *Cancel* na stránce: `CancelRequested := true; CurrPage.Close();`, `OnQueryClosePage`
  při flagu přeskočí validaci, veřejné `WasCancelled(): Boolean`, volající `if (Page.RunModal() = Action::OK) and not
  Page.WasCancelled() then` (volání metody page proměnné po `RunModal` funguje jako u `GetRecord`); v testu handler
  `Page.CancelEdit.Invoke()` (akce podle jména). Bez toho test vynech a zavírej `OK().Invoke()`. (2026-09-22, prod-ess-configurator-bc build 28404,
  `Text Formula COEBS` / `Action Formula COEBS`; ověřeno ve stejné codeunit už dřív: „Worksheet pages always have OK".)
- **Nový řádek přes `TestPage "Sales Order".SalesLines.New()` nemá zaručený `Type`.** `Sales Order Subform.OnNewRecord`
  bere `Type` z `xRec` (řádek, na kterém subform stál; `InitType`) a default ze `Sales & Receivables Setup."Document
  Default Line Type"` jen když `xRec."Document No." = ''` (`SetDefaultType`) — v CI (build 28149) tak jeden ze dvou
  identicky napsaných testů dostal prázdný Type a `"No.".SetValue(zboží)` spadlo na „The Standard Text does not exist".
  Nastavuj Type explicitně; který control je viditelný, závisí na Application Area (`Type` bez Foundation,
  `FilteredTypeField` = Type as text s Foundation): `if SalesOrder.SalesLines.Type.Visible() then
  SalesOrder.SalesLines.Type.SetValue("Sales Line Type"::Item) else
  SalesOrder.SalesLines.FilteredTypeField.SetValue(Format("Sales Line Type"::Item))`.
  (2026-09-09, prod-ess-configurator-bc `Attached Lines Tests COEBS`, helper `SetNewSubformLineTypeItem`)
- **Čtení CI logu: stejné `Document No.` v chybách několika testů za sebou = každý z nich spadl a odroloval se**
  (číselná řada se vrátila); prošlý test commitne a číslo posune. Runner úspěšné testy nevypisuje, ale z čísel dokladů
  v hláškách jde poznat, které testy mezi faily prošly (build 28149: „1003" u testů 3–5, „1005" od testu 9 = testy 6 a 8
  prošly). Logika ověřená jen na TestPage cestě a ne z kódu (`Rec.Validate + Modify(true)`) = typický kandidát na
  `xRec = Rec` past (3.9 v `bc-al-data.md`).
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
- **`LibraryRandom.RandInt*` jako PK vlastního záznamu = kolize napříč testy téhož codeunitu.** `Library - Random`
  je `SingleInstance` a před každou test metodou má stejný seed (starý `CAL Test Runner` volá v `OnBeforeTestRun`
  `SetSeed(1)`, default bez seedu je taky `SetSeed(1)`; pod `Test Runner - Isol. Codeunit` v Essence CI to dopadá
  stejně), takže první `RandIntInRange(100000, 999999)` vrátí **v každém testu totéž číslo**. Data prošlých testů
  přitom v DB zůstávají do konce codeunitu (AutoCommit + TestIsolation Codeunit) → druhý test, který stejným helperem
  zakládá záznam, spadne na `The record in table X already exists. Id='323801'`. Lokálně to neuvidíš (jeden test
  = jeden seed). Pro Integer/BigInteger PK vlastního helperu použij **`FindLast` + 1** (nebo `LibraryUtility.GetNewRecNo`),
  ne random; kódy přes `LibraryUtility.GenerateRandomCode` / `GenerateGUID` v témže runu nekolidovaly. Zachyceno
  2026-09-08, cust-sonnentor-bc build 28134 (`TestWebshopFilterSON`, `Shpfy Product` Id 323801 ve třech testech).
  ⚠️ **Dodatek 2026-09-22 (cust-soitron-bc): `LibraryUtility.GenerateGUID()` se v témže codeunitu opakuje taky** —
  jméno stavěné jako `'BU-' + LibraryUtility.GenerateGUID()` vyrobilo v každém testu **stejný text**, takže lookup
  podle jména (`SetRange(Name, …)` + `FindFirst`) našel záznam **prvního** testu (AutoCommit ho nechal v DB). Příznak:
  první test s tím jménem projde, další padají na `Assert.AreEqual` s **jiným, ne prázdným** ID, a actual je menší než
  expected (FindFirst bere nejnižší PK). Pro jména, na která se pak hledá, ber **`DelChr(Format(CreateGuid()), '=', '{}-')`**
  (platformový `CreateGuid()` seedovaný není), ne `GenerateGUID`. Předchozí věta („nekolidovaly") platila jen pro
  krátké kódy porovnávané na rovnost, ne pro lookup jménem — ověřeno na CRM Businessunit v `CRM Business Unit Test SOI`.
- **Účtování / plánování v testu zakládá skutečný scheduled task** (`Job Queue Entry.ScheduleJobQueueEntryForLater`,
  `Codeunit.Run("Job Queue - Enqueue")`) → před ním `BindSubscription(LibraryJobQueue)` (`Library - Job Queue`, Manual) —
  jeho subscriber `OnBeforeJobQueueScheduleTask` nastaví `DoNotScheduleTask`, entry zůstane On Hold a dá se assertovat.
  Setup záznamy sdílené napříč testy codeunitu (např. `Shpfy Shop` s vlastním enable flagem) **vypni v `Initialize()`
  před `if IsInitialized then exit`** (`ModifyAll(Flag, false, false)`), jinak „počet řádků per povolený shop" počítá
  i shopy z předchozích testů (AutoCommit). (2026-09-22, cust-sonnentor-bc `Test Voucher Discounts SON`.)
- **`TaskScheduler.CanCreateTask()` je v Essence build kontejneru `false`** (`CreateBCContainer2.ps1` nevolá
  `New-BcContainer -enableTaskScheduler`; BcContainerHelper pak `EnableTaskScheduler` do konfigurace vůbec nezapíše).
  Vlastní pre-check před `ScheduleJobQueueEntryForLater` („zrcadlo `CheckRequiredPermissions`", 5.x14 v bc-al-objects)
  tak v CI **tiše přeskočí založení entry** a `Assert.RecordCount(JobQueueEntry, 1)` spadne s `Actual: 0`, zatímco přímé
  `Codeunit.Run("Job Queue - Enqueue")` s bindnutou `Library - Job Queue` projde (base `CanCreateTask` nekontroluje, jen
  publikuje `OnBeforeJobQueueScheduleTask`). Řešení: pre-check obal do `local procedure CanCreateTask()` s
  `[IntegrationEvent] OnBeforeCheckCanCreateTask(var CanCreateTask; var IsHandled)`; test codeunit dostane
  `EventSubscriberInstance = Manual`, subscriber nastaví `true` + `IsHandled` a test ho bindne přes proměnnou vlastního
  typu (`TestX: Codeunit "Test X"; BindSubscription(TestX)`) hned za `BindSubscription(LibraryJobQueue)`. Na dev
  prostředí se zapnutým task schedulerem to lokálně neuvidíš. (2026-09-22, cust-sonnentor-bc build 28396, 2 testy.)
- **Platformový `Random()` v app kódu dostává v testech seed od `Library - Random`** (`SetSeed` = `Randomize(Seed)` na
  společném generátoru, před každým testem stejný — viz bullet o PK výše). Generátor typu „náhodný kód + kontrola
  unikátnosti + max 20 pokusů" (`GenerateActivationCode` u voucherů) proto v každém testu se stejnou preambulí navrhuje
  **tutéž sekvenci kandidátů**; data předchozích testů zůstávají do konce codeunitu (TestIsolation Codeunit) → N-tý test
  se stejnou preambulí vyčerpá všech 20 pokusů a spadne (`There is an issue with generating the activation code`),
  první testy projdou a lokálně (jeden test = jeden seed) to nevidíš. Fix v appce: při kolizi `Randomize()` bez seedu
  před dalším pokusem — v produkci se větev nikdy nespustí, v testu utrhne opakující se sekvenci.
  (2026-09-22, cust-sonnentor-bc build 28396, 4 testy z 39.)
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

⚠️ **`PTE0012` přiletí i do appky, která žádný `Access = Internal` objekt nemá** —
pravidlo hlídá **existenci** `internalsVisibleTo`, ne jeho využití. Fix je stejný
(Hidden v rulesetu); smazat nepoužívané `internalsVisibleTo` je taky validní, ale
u prod modulu, který k Internal kontraktu směřuje, se to jen vrátí. Jak takový fail
vypadá v CI (krok „Compile AL Apps" doběhne bez `##[error]`, pozná se až podle
`SucceededNode() → False` u dalších kroků) → **7.21 v `bc-al-build.md`**.
(2026-09-22, prod-ef-advanceCZ-bc, build 28371.)

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
**Dependency, která lokálně nikde není (`AI Test Toolkit` v prod-ess-configurator-bc/test):** pro compile-check
nekopíruj `test/app.json` ručně — zkopíruj celou `test/` (src, app.json, AppSourceCop.json, logo) do scratchpadu,
v kopii `app.json` závislost python skriptem vyhoď (zdrojáky testů ji nepoužívají) a kompiluj kopii proti vlastní
cache (MS 28.3 symboly z vlastní `.alpackages` **bez** staré verze hlavní appky + čerstvý build hlavní appky +
Tests-TestLibraries/Test Runner/SysApp Test Lib/App Test Lib/Permissions Mock z dotykacka `.alpackages`).
Dvě verze téže appky v jedné cache (stará `.alpackages` + nový build) = nejasné, kterou alc vezme → do cache jen jednu.
(2026-09-08, prod-ess-configurator-bc, typ řádku Parameter Value Name)

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
- **Podruhé tamtéž (build 28219, 2026-09-14) — tentokrát v ASSERTU, ne v produkčním kódu:**
  negativní kontrola `Assert.IsFalse(ItemUoM.Get(ItemNo, '1200/800'), 'no generated UoM')`
  spadla, protože dřívější test založil globální UoM `1200/800` a `CreateItem` ji dal
  novému itemu jako base UoM — „vygenerovaná" jednotka tam byla ještě před WHEN. Assert
  „nic nového nevzniklo" piš přes **počet** Item UoM před/po (`SetRange("Item No.")` +
  `Count()` → `Assert.RecordCount(ItemUoM, CountBefore)`), ne přes `Get` konkrétního kódu.
- **`[HandlerFunctions('MessageHandler')]` jen tam, kde dialog opravdu vyskočí.** Registrovaný
  handler, který se během testu nezavolá, shodí test na „The following UI handlers were not
  executed: MessageHandler" — i když všechny asserty prošly. `LibraryWarehouse.CreateWhseShipmentFromSO`
  (`CreateFromSalesOrderHideDialog`) ani `LibraryWarehouse.PostWhseShipment` žádnou zprávu
  nezobrazí, stejně `LibrarySales.ReleaseSalesDocument` a `LibraryInventory.PostItemJournalLine`.
  Handler přidávej až podle reálného dialogu (CI hláška „no handler" / dokumentovaný Message),
  ne preventivně. (build 28219, `WarehouseShipmentLineGetsParametersAndPostsThem`)

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

**Calculate Plan do vlastního batche:** `LibraryPlanning.CalcRequisitionPlanForReqWksh*` batch
neberou (jedou do defaultního listu z `SelectRequisitionWkshName`), takže Calculate Plan + Carry Out
test pusť report 699 přímo: `CalculatePlanReqWksh.SetTemplAndWorksheet(Template, Batch)` →
`InitializeRequest(StartDate, EndDate)` → `Item.SetRange("No.", …)` + `SetTableView(Item)` →
`UseRequestPage(false)` → `RunModal()`; řádky pak filtruj na Template + Batch + `"No."`. Report 699
procedury al-mcp nevidí (`Procedures: []` u reportů) — signatury ověří kompilace. (2026-09-14,
cust-alumistr-bc 65774, `Planning Transfer Tests ALU/PMALU` po code review.)

**Calculate Plan + Carry Out: poptávka na `WorkDate()` = „There is nothing to create."** `Inventory Profile
Offsetting.SetAcceptAction` nastaví `Accept Action Message := false` každému řádku, který má planning warning
(`PlanningTransparency.ReqLineWarningLevel(ReqLine) <> 0`); poptávka na WorkDate s nulovým lead time dá order
date před planning starting date (Emergency/Exception). `Req. Wksh.-Make Order` bere jen `Accept Action Message
= true` → report 493 skončí `Message('There is nothing to create.')` → „Unhandled UI: Message" (bez handleru).
Fix: poptávku datovat do budoucna (`SalesLine.Validate("Shipment Date", CalcDate('<+2W>', WorkDate()))`,
`ProductionOrder.SetUpdateEndDate()` + `Validate("Due Date", …)` **před** `RefreshProdOrder` — bez
`SetUpdateEndDate` Validate z kódu (`CurrFieldNo = 0`) Starting/Ending Date hlavičky nepřepočítá, `Create Prod.
Order Lines` je zkopíruje na řádek a komponenta zůstane na WorkDate → Emergency; build 28226) a před carry-out
`Assert.IsTrue(ReqLine."Accept Action Message", …)`, ať fail mluví. Zdroj: `Inventory/Tracking/
InventoryProfileOffsetting.Codeunit.al` (sparse clone `--filter=blob:none --sparse -b w1-28`, api.github.com
z Claude Code sandboxu nejede — `http 000`; raw.githubusercontent ano). (2026-09-14, cust-alumistr-bc build 28223.)

**Testy volající `SL Action Cond. Mgt. COEBS.ExecuteSalesLineActions` potřebují `[HandlerFunctions('…MessageHandler')]`**
— procedura končí nepodmíněným `Message('Sales Line actions have been executed …')`. Konfigurátorové testy to řeší
`MessageHandler`, v cust-alumistr-bc `SLActionsExecutedMessageHandler` (před přidáním nového handleru grepni
codeunit — duplicitní název = AL0518/AL0440). (2026-09-14, cust-alumistr-bc build 28223.)

### Doklad jen se záporným řádkem = „Celková částka faktury musí být 0 nebo větší" PŘED vlastní kontrolou

Test, který účtuje doklad obsahující **jen záporný řádek** (uplatnění poukazu, sleva, oprava),
spadne na standardní kontrole `The total amount for the invoice must be 0 or greater.` —
a to **dřív, než se dostane ke slovu vlastní kontrola** v `OnBeforeIsApprovedForPosting`
nebo jinde v posting flow. Negativní test pak selže na „Expected: <moje hláška>. Actual:
The total amount for the invoice must be 0 or greater." a vypadá to, jako že vlastní kontrola
nefunguje, přitom se jen nespustila.

**Fix:** dej do dokladu **kladný řádek běžného zboží** (`LibrarySales.CreateSalesLineWithUnitPrice(SalesLine,
SalesHeader, ItemNo, 1200, 1)`), ať je celková částka ≥ 0 — a to i u dobropisu, který vydává
nový poukaz. Reálný doklad tak taky vypadá (zákazník něco kupuje/vrací a poukazem platí část).
Prodejní (kladná) strana téhož scénáře projde bez zboží, takže „prodej funguje, uplatnění ne"
je typický příznak právě tohohle. (2026-09-15, cust-sonnentor-bc build 28270, `RedemptionWithWrongUnitPrice-
CannotBePosted` + `FullVoucherCycleWithReplacementKeepsValueAndExpiration`.)

### `Assert.ExpectedError` na `TestField` hlášce: caption pole může projít `CaptionClass`

`SalesLine.TestField("Unit Price", 500)` nehlásí „Unit Price must be equal to…", ale
**„Unit Price Excl. VAT must be equal to '199.47' in Sales Line: …"** — pole `Unit Price` má
`CaptionClass`, která podle `Prices Including VAT` vyrobí `Unit Price Excl. VAT` /
`Unit Price Incl. VAT`. `Assert.ExpectedError('Unit Price must be equal to')` proto **nikdy
nematchne** (hledá se podřetězec). K tomu je částka formátovaná v locale session (`199.47`
vs `199,47`), takže hardcoded číslo v expected textu je druhá past.

**Pravidlo:** u `TestField` asertů matchni **stabilní střed hlášky** (`'must be equal to'`),
nebo použij `Assert.ExpectedTestFieldError(Rec.FieldCaption(Pole), Format(Hodnota))` a ověř,
že `FieldCaption` u daného pole opravdu vrací to, co runtime vypíše. Pole s `CaptionClass`
(ceny, dimenze, matricové parametry) sem patří vždycky.

### `TestPage` repeater: opuštění řádku vyžaduje řádek, kam jít

`SubForm.Next()` / `.First()` na dokladu s **jediným řádkem** nikam nepřejde, takže
`OnModifyRecord` stránky se nespustí a guard v něm nic nehlásí — negativní test spadne na
„An error was expected". Dej na doklad **ještě jeden řádek** (běžné zboží) a pak na
kontrolovaný řádek `Last()`, hodnotu zapiš a odejdi `First()`:

```al
AddPlainItemLine(SalesHeader, 1);            // něco, kam se dá odejít
VoucherMgt.InsertNewVoucherOnSalesLine(…);   // testovaný řádek přijde poslední
…
SalesOrder.SalesLines.Last();
asserterror begin
    SalesOrder.SalesLines."Variant Code".SetValue('');
    SalesOrder.SalesLines.First();
end;
```

(2026-09-15, cust-sonnentor-bc, `VariantOfVoucherLineCannotBeChangedOnOrderPage` +
`RedemptionWithWrongUnitPriceCannotBePosted`.)

### Negativní test účtování: `asserterror` „An error was expected" = kontrola se nespustila, ne že je test špatný

Když `asserterror LibrarySales.PostSalesDocument(...)` skončí na **„An error was expected inside
an ASSERTERROR statement."**, doklad se zaúčtoval. Nejčastější příčina u vlastních kontrol:
kontrola visí na `Sales Header.OnBeforeIsApprovedForPosting`, který vyvolává jen `Sales-Post
(Yes/No)` (účtování z UI) — `LibrarySales.PostSalesDocument` jde přes `Sales-Post` přímo, takže
kontrolu mine. Fix je v produkčním kódu, ne v testu: přesunout / doplnit subscriber na
`Sales-Post.OnAfterCheckSalesDoc` (detail v 3.6d v `bc-al-data.md`). Test pak testuje i tu
cestu, kterou jedou integrace.

Druhá příčina téže hlášky u TestPage: **guard v `OnModifyRecord` se spustí až při opuštění řádku**,
ne při `SetValue`. `asserterror Page.SubForm."Pole".SetValue(x)` tedy chybu nedostane — dej do
`asserterror` i opuštění řádku:

```al
asserterror begin
    SalesOrder.SalesLines."Variant Code".SetValue('');
    SalesOrder.SalesLines.Next();
end;
Assert.ExpectedError('cannot be changed');
```

Naopak guard v `OnBeforeValidate` field triggeru (page `modify(...)`) chybu vrátí hned při
`SetValue` — proto může jeden test ze dvou „stejných" projít a druhý ne.
(2026-09-15, cust-sonnentor-bc buildy 28270/28271.)

### `TestPage.<pole>.SetValue` na skrytém controlu → „The field with ID = N is not found on the page"

`TestPage` vidí jen controly, které jsou na stránce **viditelné**. `SetValue`/`AssertEquals` na
control s `Visible = false` (i když je to base-app default, např. `Variant Code` na `Sales Order
Subform`) hodí *„The field with ID = <číslo> is not found on the page."* — číslo je control ID,
takže z hlášky nepoznáš, o které pole jde; dohledej ho podle toho, co test zkoušel nastavit.

Zrádná varianta: **`modify("<control>")` při portu z jiného repa přenese triggery, ale ne properties.**
Když předloha má `modify("Variant Code") { Visible = true; trigger OnLookup… }` a ty zkopíruješ
jen trigger, pole zůstane skryté — lookup i validace se stanou mrtvým kódem a uživatel hodnotu
nemá kde zadat. Při portu porovnej celý `modify` blok, ne jen jeho triggery. (2026-09-15,
cust-sonnentor-bc build 28270 vs. cust-kalas-bc `SalesOrderSubformKAL`.)

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

### SaaS Cloud target bez `Tests-TestLibraries` — fallback (vyčleněno)

> ⚠️ **FALLBACK, ne default.** Vlastní `Assert ZLK`, vlastní `Library` helpery bez `Library - *` a co nezvládnou bez setupu → `bc-al-autotests-saas-fallback.md` ve stejném adresáři. Platí jen pro čistý SaaS-only deploy test appky bez OnPrem CI; **pro Essence prod moduly to NEpoužívej** (viz kanonická sekce nahoře).

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

### CZZ nákupní záloha v testu, na kterou se má navázat platba — musí mít řádek a být VYDANÁ (release), jinak To Pay = 0

`Purch. Adv. Letter Header CZZ`."To Pay" je FlowField `-sum("Purch. Adv. Letter Entry CZZ".Amount)` přes typy Initial Entry |
Payment | Close — a **Initial Entry vzniká až při release** (`Rel. Purch.Adv.Letter Doc. CZZ`), ne založením hlavičky. Test helper,
který založí jen hlavičku a nastaví `Status := "To Pay"` napřímo (vzor `EF Banking Library EBS.CreatePurchAdvLetterHeader`),
dá zálohu s **To Pay = 0**; stačí pro testy párování/merge, ale `PurchAdvLetterManagementCZZ.PostAdvancePayment(...)` /
`Purch. Adv. Letter-Post CZZ.PostAdvancePayment` spadne na `Amount > "To Pay"` („ExceededAmountToPayErr"). Funkční recept
(`CreateReleasedPurchAdvLetter` tamtéž): hlavička (`Validate("Advance Letter Code")` → `Insert(true)` → `Validate("Pay-to Vendor No.")`,
datumy, `"Vendor Adv. Letter No."` — z něj release odvodí VS) **bez ručního Status**, řádek `Validate("VAT Prod. Posting Group",
<VAT Prod z LibraryERM.FindVATPostingSetup(Normal VAT)>)` (stejný setup, jaký `Library - Purchase.CreateVendor` dá dodavateli →
kombinace Bus/Prod existuje; řádek vyžaduje Status New) + `Validate("Amount Including VAT", X)`, pak
`Codeunit.Run(Codeunit::"Rel. Purch.Adv.Letter Doc. CZZ", Header)`. Šablona zálohy musí mít **"Advance Letter G/L Account"**
(`LibraryERM.CreateGLAccountNo()`) — účtování platby zálohy jde přes `"Use Advance G/L Account CZZ"` na tento účet místo účtu
závazků. `"Automatic Post VAT Document"` nechat false, jinak se při navázání účtuje i DPH doklad (potřebuje účty na VAT Posting
Setup, VAT Date…). **Transaction No. navázané zálohy** ber přes `PurchAdvLetterEntryCZZ."Vendor Ledger Entry No."` →
`Vendor Ledger Entry."Transaction No."`; položka zálohy typu Payment má `"Det. Vendor Ledger Entry No." = 0`
(`InitVendorLedgerEntry` plní jen VLE No., detailní položku plní až usage/VAT položky) → `DetailedVendorLedgEntry.Get(0)` spadne.
(2026-09-22, prod-ef-bank-bc `TestMergedPaymentFullFlow_MatchingAndPosting`, kontrola proti cz-28 source.)

### `Codeunit.Run` s návratovou hodnotou v testu po zápisech = „An error occurred and the transaction is stopped"

`PostingSucceeded := Codeunit.Run(Codeunit::"Gen. Jnl.-Post Batch", GenJournalLine)` nebo `if Codeunit.Run(Codeunit::"Match Bank
Payment CZB", …)` v testu, který už předtím něco zapsal (Insert řádku deníku, založený dodavatel…), skončí na řádku `Run`
generickou chybou **„An error occurred and the transaction is stopped. Contact your administrator or partner for further
assistance."** — i když volaný kód sám žádnou chybu nehodí (ověřeno 2026-09-22, prod-ef-bank-bc: totéž volání jako statement
proběhlo bez chyby). Skutečný text případné vnitřní chyby se tím ztratí. V testech proto **Codeunit.Run volej jako statement**
(chyba doběhne do runneru s textem a stackem), negativní scénář řeš `asserterror`. Pattern `Run + Assert.IsTrue(ok, GetLastErrorText())`
nepoužívat.

### Test párování `Match Bank Payment CZB` z kódu

`Codeunit.Run(Codeunit::"Match Bank Payment CZB", GenJournalLine)` jako statement: řádek deníku potřebuje `"Search Rule Code CZB"`
(nebo sumární řádek banky), `"Bal. Account Type/No."` = banka (jinak hledá sumární řádek), nenulové `Amount (LCY)` a banku bez
`"Disable Automatic Pmt Matching"`. **Variabilní symbol čte párování přes `GenJournalLine.GetVariableSymbolCZB()`**, které vrací
`"Variable Symbol CZL"` jen při `"Variable S. to Variable S. CZB" = true` (alternativně z Ext. Doc. No. / Description podle
dalších dvou příznaků); v provozu je kopíruje `CreateJournal` z bankovního účtu, ručně založený řádek v testu má příznak false →
VS „prázdný", pravidlo s VS nic nenajde a párování tiše skončí bez chyby (`"Search Rule Line No. CZB" = 0`). V helperu nastav
`GenJournalLine."Variable S. to Variable S. CZB" := true`. Vlastní pravidlo: `LibraryBankDocCZBEBS.CreateSearchRule`
(+ `CreateDefaultLines`) a pak `DeleteAll` řádků + `Insert(false)` jediného řádku s testovaným `Search Scope`, aby výsledek
neovlivnily standardní řádky. Výsledek čti po `Get` řádku (`"Search Rule Line No. CZB"` ≠ 0 = spárováno; při nespárování se řádek
NEmodifikuje). Směr částky: odchozí platba dodavateli z výpisu má na řádku deníku **kladný** `Amount` (Bal. Account = banka;
`MatchBankPaymentCZB` filtruje `Positive := Amount < 0` a toleranci z `-Amount (LCY)`).
- **`Issue Payment Order CZB` volá `Message`:** u příkazu s řádkem dodavatele jde přes `PaymentOrderHeaderCZB.ImportUnreliablePayerStatus()`
  (kontrola nespolehlivých plátců „vypršela" = nový příkaz vždy), import ze služby v test DB selže bez error textu →
  `Message('Unreliable Payer Status was not loaded.')` → test bez `[HandlerFunctions('MessageHandler')]` padá „Unhandled UI: Message".
  Confirm větve (neveřejný/cizí účet, nespolehlivý plátce) hrozí jen když `PaymentOrderLine.IsUnreliablePayerCheckPossible()`
  (CZ dodavatel s DIČ), což dodavatelé z `Library - Purchase` nesplňují. Test, který příkaz vydává, MessageHandler mít musí;
  test, který ho nevydává, ho mít nesmí (nevyužitý handler = fail). Párování ani `Vend. Entry-Edit` UI nevolají.
- **Defaultní řádky `Search Rule CZB.CreateDefaultLines` se liší podle verze BC** (CI 28.0.46665 má mezi Balance/Both řádky
  i jiné řádky, cz-28 HEAD = 28.3+ má 6× Balance/Both) — test na pořadí/vkládání řádků nesmí předpokládat konkrétní sadu;
  projdi všechny standardní řádky, očekávání odvozuj z předchozího řádku **jakéhokoli typu** a ověř i „žádný vložený řádek
  před ne-Balance řádkem" (spadlo 2026-09-22: Expected 20000, Actual 25000). Obecně: zdroják z GitHubu StefanMaron je HEAD
  dané major řady, CI kontejner může jet starší minor — chování defaultních dat si ověř až během. Konkrétní build najdeš
  přes commits API (`commits?sha=cz-28&path=<soubor>` → message `cz-28.0.46665.48549` → raw URL se SHA commitu).
- **Test symboly 28.3 z MSSymbols:** stejný set a package ID jako u 28.4 (viz výše), verze `28.3.52162.52273`, proti Base App
  `28.3.52162.52754` alc 17.0 čistě (2026-09-22, prod-ef-bank-bc/Test).
(2026-09-22, prod-ef-bank-bc `BankEBSTestsEBS`.)

## Odkazy

- [MS Docs – Testing the Application](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-testing-application)
- [MS Docs – Test Codeunits and Test Functions](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-test-codeunits)
- [ALGuidelines – Testing](https://alguidelines.dev/docs/vibrantcode/testing/)
