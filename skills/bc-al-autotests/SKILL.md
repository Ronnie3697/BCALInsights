---
name: bc-al-autotests
description: >-
  BC/AL automatizované testy z praxe (Business Central): kdy jsou povinné
  (netriviální funkčnost), vzor Essence (MS Assert + Library - *, vlastní
  library jen pro custom tabulky, target Cloud + Test
  Runner/Tests-TestLibraries/System Application Test Library),
  [Test]/[HandlerFunctions]/[TransactionModel], handlery, AAA, TestPage,
  ExpectedError, TestPermissions = Disabled, internalsVisibleTo, PTE0012,
  test app bez permissionsetu, Report.RunModal bez request page,
  OnBeforeActionEvent jen přes TestPage, CreateItem base UoM past,
  asserterror rollbackne GIVEN → Commit, carry-out vlastní batch,
  placeholder testy zakázány, test ruleset dědí hlavní, SaaS-only helpery,
  Library - Setup Storage generický Save/Restore (wrappery OnPrem, AL0296),
  negativní test na nové instanci, TestPage Sales Order řádky
  (stockout/credit warning), ConfirmHandler Reply false + asserterror, undo
  dodávky bez dialogu, kompilace ze sibling .alpackages, Library - Random
  stejný seed per test (PK přes FindLast + 1). Načti při
  psaní/opravě testů, zakládání test appky a implementaci netriviální
  funkčnosti.
user-invocable: true
---

# BC/AL — Autotesty

**Zdroj pravdy:** `C:\WorkTasks\BCALInsights\bc-al-autotests.md`
(v repu `../../bc-al-autotests.md` relativně k tomuto skillu). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, snippety handlerů, helperů a rulesetů jsou
v souboru.

## Co udělat

1. **Přečti `C:\WorkTasks\BCALInsights\bc-al-autotests.md` celý.** Vejde se do jednoho Read; když
   se výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: symboly test frameworku z MSSymbols feedu a sandbox
   package cache → `bc-al-build` (7.12); Confirm / `CurrFieldNo` chování
   Sales Line → `bc-al-objects` (5.x4); ID test objektů od konce range
   → `bc-al-style` (1.12 „Přidělování ID"); ruleset konvence →
   `bc-al-workflow` (12.4).

## TL;DR — nejtvrdší pravidla

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
- **Negativní test po release / s Confirm:** validuj na **nové instanci**
  recordu (`Sales Line` si hlavičku cachuje, stará instance chybu nehodí).
  Confirm z table triggeru s `CurrFieldNo` guardem vyvolá jen
  `TestPage.SetValue` (z `Rec.Validate` je `CurrFieldNo = 0`) → odmítnutí =
  `[ConfirmHandler]` `Reply := false` + `asserterror`, `Commit()` po GIVEN,
  assertuj DB stav (ne `ExpectedError('')`). Řádky přes `TestPage "Sales
  Order".SalesLines` → napřed `LibrarySales.SetStockoutWarning(false)` +
  `SetCreditWarningsToNoWarnings()`. Undo dodávky bez dialogu:
  `SetRecFilter()` + `SetHideDialog(true)` + `Run`.
- `MinValue`/`MaxValue`/`NotBlank` programový `Validate` **nevynucuje** →
  explicitní `OnValidate` check nebo TestPage. Expected DateTime přes
  `Evaluate(DT, '…Z', 9)`, ne `CreateDateTime` (DST).
- **`LibraryInventory.CreateItem` dá base UoM = abecedně první Unit of
  Measure** → data-dependent faily; testové jednotky přes `GenerateRandomCode`.
- **Carry Out Action Message bere celý list** → každý carry-out test vlastní
  batch (`CreateRequisitionWkshName`).
- `OnBeforeActionEvent` subscribery jen přes `TestPage.Action.Invoke()`;
  report bez request page: `Report.RunModal(ID, false, false, Rec)` + `SetRecFilter`.
- Main appka s `Access = Internal` → `internalsVisibleTo` v jejím `app.json`
  **nemazat**; PTE0012 schovat v rulesetu. Test app **bez permissionsetu**.
- Struktura: flat `test/src/`, affix v názvu souboru netřeba (AppSourceCop ho
  odečte). Test ruleset **dědí hlavní** (`includedRuleSets`) + `LC0015` Hidden;
  aby byl aktivní, `al.ruleSetPath` do `test/.vscode/settings.json`
  (folder-level), workspace-level se resolvuje na hlavní.
- Symboly `Tests-TestLibraries` nejsou v `.alpackages` → Local-DevEnv
  s `installTestLibraries` / `AL: Download Symbols` / MSSymbols feed (7.12
  v `bc-al-build`). Lokální kompilace bez kontejneru: **celá** `.alpackages`
  sibling repa (tranzitivní deps) v `/packagecachepath` + build dir hlavní
  appky; MS test `.app` nemají zdrojáky → signatury přes al-mcp.
