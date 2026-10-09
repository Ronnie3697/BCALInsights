# Business Central / AL – autotesty (poznámky z praxe)

Sběrnice znalostí o psaní automatizovaných testů v AL pro Business Central. Roste s tím, jak budeme testy psát a narážet na věci.

> **Rozděleno 2026-10-09** (soubor měl 1009 řádků / 77 KB): sestavení test appky (`app.json`, závislosti,
> `internalsVisibleTo`, permissionset, struktura, ruleset), symboly, lokální kompilace, spouštění z CLI /
> kontejneru a čtení CI failů → `bc-al-autotests-infra.md` (skill `bc-al-autotests-infra`); pasti konkrétních
> oblastí BC (projekty, prodejní a nákupní doklady, Job Queue, výroba, konvence cust-soitron-bc) →
> `bc-al-autotests-domains.md` (skill `bc-al-autotests-domains`, kde už jsou plánování, CZZ a CZB). Tady zůstává
> povinnost, kanonický vzor, mechanika testů (handlery, TestPage, `asserterror`, `Library - *`) a obecné gotchas.

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

> Doménové gotchas (projekty / Job, doklady, Job Queue, výroba, cust-soitron-bc) → `bc-al-autotests-domains.md`;
> kompilace test appky a čtení CI → `bc-al-autotests-infra.md`.

- **`Library - Setup Storage`: pohodlné wrappery `SaveSalesSetup()` / `SavePurchasesSetup()` / `SaveGeneralLedgerSetup()` …
  mají scope OnPrem** → v test appce s `"target": "Cloud"` `error AL0296 ... has scope 'OnPrem'`. Použij generické
  `LibrarySetupStorage.Save(Database::"Sales & Receivables Setup")` + `Restore()` v `Initialize()` (Restore hned po
  `OnTestInitialize`, Save při prvním suite initu před `Commit`). Izoluje změny setupu i při lokálním běhu
  v dev kontejneru, kde po testu nezůstane v setupu testovací zákazník. (2026-09-04, cust-alumistr-bc 65916)
  ⚠️ **`Save` assertuje přesně jeden záznam** („Setup table with only one entry is allowed. Expected:<1> Actual:<0>") —
  vlastní setup tabulka v CI DB **neexistuje** (nic ji nezaložilo), takže před `Save(Database::"<Setup> XXX")` zavolej
  `Setup.GetSetup()` (= Get-or-Insert). Lokálně to neuvidíš, dev DB setup má. (2026-09-30, cust-soitron-bc build 28552, 4 testy.)
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
- **Po `asserterror Part.Pole.SetValue(x)`, který odmítne `Error` z `OnValidate`, se TestPage na jiný řádek nepřesune** —
  `Part.First()` vrátí `false` (build 28617: helper „jdi na řádek podle jména" hned po odmítnutí hlásil, že parametr v dialogu
  není), ačkoli temp řádky partu zůstaly (temp tabulky transakce nerolují). Navazující kroky ve stejné stránce (přečíst
  hodnotu jiného řádku, OK) tedy po odmítnuté hodnotě nestav. Ověřuj jinak: chybu nech **dojít z `ModalPageHandler`**
  (`SetValue` bez `asserterror` jako poslední krok handleru) a chyť ji na volání `asserterror Page.RunModal()` +
  `Assert.ExpectedError`; že se stav nezměnil, testuj o vrstvu níž (engine / codeunit nad bufferem). `MessageHandler`
  pak z `[HandlerFunctions]` vyhoď — dialog nic neuloží a nevyužitý handler test shodí. Pravděpodobná příčina: stránka
  drží odmítnutý text na řádku jako klient (opustit řádek nejde, dokud se neopraví) — příčina neověřená; původní test lokálně
  spadl stejně jako v CI a přepsaný prošel (7.23 v `bc-al-build.md`, 2026-10-05).
  (2026-10-05, prod-ess-configurator-bc `Var. Config Dialog Tests COEBS`, větev `VarConfigDialogTestsFix`.)
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
- **`LibrarySales.CreateSalesOrder(SalesHeader)` (jen s hlavičkou) založí i řádek s náhodným zboží** (`CreateSalesOrderForCustomerNo`
  → `CreateSalesLine(…, CreateItemWithUnitPriceAndUnitCost, RandInt(100))`). Testovaný řádek přidaný po ní je až **druhý** →
  `TestPage.SalesLines.First()` stojí na cizím řádku; ber `Last()` (vzor `System Param Tests COEBS`), nebo hlavičku zakládej
  `CreateSalesHeader`. Zdrojáky MS test knihoven (`.app` je nemají): **microsoft/BCApps `src/Layers/W1/Tests/ApplicationTestLibrary/`**
  (raw.githubusercontent, `main`; najdeš přes `gh api "search/code?q=<procedura>+filename:<Soubor>.Codeunit.al"`).
  (2026-09-29, prod-ess-configurator-bc review větve ParametersForPrint.)
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
- **`BindSubscription` na GLOBÁLNÍ proměnnou test codeunitu = od druhého testu „The binding of codeunit 132458 was
  unsuccessful. The codeunit has already been bound."** Instance test codeunitu žije přes všechny jeho testy, globální
  `LibraryJobQueue: Codeunit "Library - Job Queue"` zůstane nabindovaná z prvního testu a druhý `BindSubscription` spadne
  (všechny testy kromě prvního červené). Manual-instance codeunity (`Library - Job Queue`, vlastní test codeunit s
  override subscriberem) bindovat **přes lokální proměnnou** testu / helperu — odváže se na konci procedury sama.
  (2026-10-06, cust-soitron-bc build 28703, `QB Buffer Job Queue Test SOI`.)
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

- **`[HttpClientHandler]` je OnPrem-only** (MS docs: „supported only in Business Central on-premises", runtime 15+) → v test
  appce s `"target": "Cloud"` mock HTTP volání nenapíšeš. Odchozí HTTP (Jira `PUT /rest/api/3/issue/{id}`) testuj po vrstvách:
  stav fronty + payload builder v testu, samotný request ručně v sandboxu; blokátor řekni uživateli, žádný placeholder test.
  (2026-10-02, cust-soitron-bc `Jira JPL Change Test SOI`.)
- **Změna textu Labelu = projdi `Assert.ExpectedError` v testech** — ExpectedError hledá podřetězec, přepsaná hláška shodí test
  až v CI (build 28636: `its check did not pass` → `its check ended with the status`). Po úpravě labelu grepni test appku na
  jeho klíčová slova.
- **CodeCop `AA0181` + `AA0175` na `Find('=')` uvnitř `Assert.IsTrue/IsFalse`** („Find only with Next", „queries the database but
  does not use the queried record") — oba warning → s `failOn warning` CI fail. Existenci záznamu assertuj `Rec.SetRecFilter()` +
  `Assert.RecordIsNotEmpty(Rec)` / `RecordIsEmpty(Rec)` (funguje i po `Delete`, PK v proměnné zůstává), refresh hodnot přes
  `Get(PK)`. (2026-10-02, cust-soitron-bc)
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

`internalsVisibleTo` v hlavní appce (PTE0012, AL0161 při nesedícím GUIDu) a proč test appka nemá permissionset
→ `bc-al-autotests-infra.md`.

## Poznámky z praxe (Zlomek Extension – první testy)

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
`Sales-Post.OnAfterCheckSalesDoc` (detail v 3.6d v `bc-al-posting.md`). Test pak testuje i tu
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

### `Codeunit.Run` s návratovou hodnotou v testu po zápisech = „An error occurred and the transaction is stopped"

`PostingSucceeded := Codeunit.Run(Codeunit::"Gen. Jnl.-Post Batch", GenJournalLine)` nebo `if Codeunit.Run(Codeunit::"Match Bank
Payment CZB", …)` v testu, který už předtím něco zapsal (Insert řádku deníku, založený dodavatel…), skončí na řádku `Run`
generickou chybou **„An error occurred and the transaction is stopped. Contact your administrator or partner for further
assistance."** — i když volaný kód sám žádnou chybu nehodí (ověřeno 2026-09-22, prod-ef-bank-bc: totéž volání jako statement
proběhlo bez chyby). Skutečný text případné vnitřní chyby se tím ztratí. V testech proto **Codeunit.Run volej jako statement**
(chyba doběhne do runneru s textem a stackem), negativní scénář řeš `asserterror`. Pattern `Run + Assert.IsTrue(ok, GetLastErrorText())`
nepoužívat.

## Odkazy

- [MS Docs – Testing the Application](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-testing-application)
- [MS Docs – Test Codeunits and Test Functions](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-test-codeunits)
- [ALGuidelines – Testing](https://alguidelines.dev/docs/vibrantcode/testing/)
