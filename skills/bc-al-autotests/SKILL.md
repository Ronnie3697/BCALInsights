---
name: bc-al-autotests
description: >-
  BC/AL autotesty (Business Central): kdy jsou povinné (netriviální
  funkčnost), vzor Essence (MS Assert + Library - *, vlastní library jen pro
  custom tabulky, target Cloud + Test Runner/Tests-TestLibraries/SysApp Test
  Library), [Test]/[HandlerFunctions]/[TransactionModel], TestPage,
  TestPermissions Disabled, RunModal bez request page, OnBeforeActionEvent jen
  přes TestPage, CreateItem base UoM past, asserterror rollbackne GIVEN →
  Commit, bez placeholder testů, SaaS-only helpery, Setup Storage Save/Restore
  (AL0296), TestPage Sales Order řádky (stockout/credit, Type vs
  FilteredTypeField u nového řádku), ConfirmHandler Reply false + asserterror,
  modální Worksheet bez Cancel, Library - Random seed → PK FindLast + 1,
  BindSubscription na globální proměnnou, HttpClientHandler OnPrem-only,
  ExpectedError a CaptionClass. Načti při psaní/opravě testů a u netriviální
  funkčnosti; kompilace, běh a CI test appky → bc-al-autotests-infra, pasti
  projektů, dokladů, Job Queue, výroby a plánování → bc-al-autotests-domains.
user-invocable: true
---

# BC/AL — Autotesty

**Zdroj pravdy:** `bc-al-autotests.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, snippety handlerů, helperů a rulesetů jsou
v souboru.

## Co udělat

1. **Přečti `bc-al-autotests.md` z adresáře tohoto skillu celý.** Vejde se do jednoho Read; když
   se výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej. Přílohu
   `bc-al-autotests-saas-fallback.md` (vlastní Assert/Library bez `Tests-TestLibraries`) čti jen
   u SaaS-only test appky bez OnPrem CI.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sesterské skilly (vyčleněno 2026-10-01 a 2026-10-09, soubor přesáhl 1000 řádků):
   - `bc-al-autotests-infra` (soubor `bc-al-autotests-infra.md`) — `app.json` test appky,
     `internalsVisibleTo`, permissionset, struktura, test ruleset, symboly, lokální kompilace,
     spouštění z CLI / kontejneru, čtení CI failů. Načti při zakládání test appky, kompilaci,
     běhu testů a rozboru CI failu.
   - `bc-al-autotests-domains` (soubor `bc-al-autotests-domains.md`) — pasti projektů (Job), prodejních
     a nákupních dokladů, Job Queue, výroby, cust-soitron-bc + recepty plánování / Carry Out, CZZ záloh
     a párování CZB. Načti u testů těchto oblastí.
4. Sousední témata: symboly test frameworku z MSSymbols feedu a sandbox
   package cache → `bc-al-build` (7.12); Confirm / `CurrFieldNo` chování
   Sales Line → `bc-al-objects` (5.x4); ID test objektů od konce range
   → `bc-al-style` (1.12 „Přidělování ID"); ruleset konvence →
   `bc-al-workflow` (12.4).

## TL;DR — nejtvrdší pravidla

- **Po každém vyžádaném push** (nejdřív push, pak testy) pusť celé testy repa v lokálním Docker
  kontejneru (`<PRACOVNÍ-REPA>\bc-test-container\Test-Repo.ps1 -RepoPath <repo>`, 7.7b v `bc-al-tools`,
  7.23 v `bc-al-build`); fail = opravit dalším commitem + push. Jen v rámci push, ne po každé změně
  ani po implementaci — PR buildy testy nespouští, jinak se fail ukáže až na masteru. Jen kdo kontejner
  v setupu přijal (always-on `Lokální testovací kontejner: ano`); `ne` = autotesty nepouštět ani nenabízet nikdy.
- **Povinnost:** netriviální funkčnost (business logika, validace, výpočty,
  posting/propagace, integrace, flow) = testy **součást úkolu**, bez
  vyžádání, zmíněné v souhrnu. Ne u banalit (pole bez logiky, captiony,
  XLIFF, kosmetika UI, čistý refactor s pokrytím). **Žádné placeholder
  testy** (`Assert.IsTrue(true)`) — nejde-li scénář postavit, zaznamenej
  blokátor a řekni to.
- **Kanonický vzor (Essence prod moduly):** `prod-ess-configurator-bc/test`.
  MS `Assert` (130000) + `Library - Sales/Inventory/ERM/Utility/Test
  Initialize`; **vlastní library jen jako data factory pro custom tabulky
  modulu**. `app.json`: `"target": "Cloud"` + `Test Runner`,
  `Tests-TestLibraries`, `System Application Test Library` + explicitní dep na
  každou appku, jejíž typy používáš. `AppSourceCop.json` s `mandatoryAffixes`
  v `test/`. Vlastní `Assert XXX` / helpery = **fallback jen pro SaaS-only bez
  OnPrem CI**.
- Codeunit: `Subtype = Test;` + **`TestPermissions = Disabled;` explicitně
  v každé** (default je `Restrictive` → insert do tabulek cizích appek padá).
  ID od konce range. `Initialize()` přes `Library - Test Initialize`;
  `Commit()` vždy s komentářem (LC0002).
- AAA komentáře `[SCENARIO] / [GIVEN] / [WHEN] / [THEN]`; UI → `[HandlerFunctions]`
  + handler v téže codeunit; `ConfirmHandler` má `Question: Text[1024]`.
- `TransactionModel` default AutoCommit; `AutoRollback` → `Commit()` hodí error.
- **`asserterror` rollbackne i GIVEN data** → před kontrolou DB stavu
  `Commit();` (s komentářem); dva `asserterror` za sebou → vlastní testy.
- **Setup v testu:** `Library - Setup Storage` wrappery (`SaveSalesSetup()`…)
  mají scope OnPrem (AL0296 v Cloud test appce) → generické
  `Save(Database::"Sales & Receivables Setup")` + `Restore()` v `Initialize()`.
- **Negativní test s Confirm:** Confirm z table triggeru s `CurrFieldNo` guardem vyvolá jen
  `TestPage.SetValue` (z `Rec.Validate` je `CurrFieldNo = 0`) → odmítnutí =
  `[ConfirmHandler]` `Reply := false` (otázku si ulož), **bez `asserterror`**
  (TestPage tichý `Error('')` spolkne), `Commit()` po GIVEN, assertuj DB stav
  a položenou otázku (ne `ExpectedError('')`). Řádky přes `TestPage "Sales
  Order".SalesLines` → napřed `LibrarySales.SetStockoutWarning(false)` +
  `SetCreditWarningsToNoWarnings()`; nový řádek (`New()`) nemá zaručený
  `Type` → nastav ho (`Type` / `FilteredTypeField` podle `Visible()`).
  Release / undo dodávky / projekty → TL;DR skillu `bc-al-autotests-domains`.
- Testuj **obě cesty** — TestPage i `Rec.Validate + Modify(true)`; logika
  na `xRec` v modify triggeru z kódu nefunguje (3.9 v `bc-al-data`).
- `MinValue`/`MaxValue`/`NotBlank` programový `Validate` **nevynucuje** →
  explicitní `OnValidate` check nebo TestPage. Expected DateTime přes
  `Evaluate(DT, '…Z', 9)`, ne `CreateDateTime` (DST).
- **`LibraryInventory.CreateItem` dá base UoM = abecedně první Unit of
  Measure** → data-dependent faily; testové jednotky přes `GenerateRandomCode`.
- **Data mezi testy téhož codeunitu zůstávají** (AutoCommit + TestIsolation Codeunit) a `Library - Random`
  má před každým testem stejný seed → PK vlastních záznamů `FindLast` + 1, jména na lookup přes
  `CreateGuid()`, ne `RandInt` / `GenerateGUID`. Manual-instance codeunity bindni přes **lokální** proměnnou.
- `OnBeforeActionEvent` subscribery jen přes `TestPage.Action.Invoke()`;
  report bez request page: `Report.RunModal(ID, false, false, Rec)` + `SetRecFilter`.
- Test appka jako projekt (`internalsVisibleTo`, bez permissionsetu, struktura, ruleset, symboly,
  lokální kompilace, CI) → TL;DR skillu `bc-al-autotests-infra`.
