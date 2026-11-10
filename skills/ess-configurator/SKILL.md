---
name: ess-configurator
description: >-
  Essence Configurator (COEBS, prod-ess-configurator-bc) a rozšíření COALU Alumistr / COZLK Zlomek (BC/AL),
  jádro: systémové parametry (QUANTITY -1, UNIT_PRICE -2, CNC X1/X/Y/Z, OnAddNumericSystemParameters, tiché
  nuly), číselné vzorce Action Formula Line (PK bez Field Type, Math Expression Parser), textové vzorce Text
  Formula Line ({KOD:Value}/{KOD:ValueName} + řádek Formula {= A * QUANTITY} s Expression No., i na poznámkovém
  řádku), Zrušit editorů (WasCancelled, EditFormula), strom podmínek parametru (zastaralé Root Condition No.,
  kořen ze struktury 66845, report 63140 Config. Data Repair, OnAfterRepairConfiguration), nerecyklovaná čísla
  parametrů a odkazy (Param. Reference Mgt., OnCollectParameterReferences), Číslo z parametru na řádku SL akce
  (Item From Parameter), diagnostika (service stránky), konfigurační balíček RapidStart.
  Varianty / dialog / API → ess-configurator-variants, kusovník / Cutting Plan / Pricing Matrix / kopie →
  ess-configurator-extensions. Načti u konfigurátoru, vzorců, podmínek.
user-invocable: true
---

# Essence Configurator — parametry, vzorce, podmínky

**Zdroj pravdy:** `ess-configurator-notes.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`).
Tenhle skill je jen wrapper — níže je výcuc stabilních pravidel, detaily,
signatury a diagnostické postupy jsou v souboru.

Repa: produktová appka `prod-ess-configurator-bc` (Azure DevOps: <https://dev.azure.com/essencebs/Projects/_git/prod-ess-configurator-bc>; affix **COEBS**,
publisher Essence International s.r.o.), zákaznická rozšíření
`cust-alumistr-bc/configuratorExtension` (**COALU**) a `cust-zlomek-bc` (**COZLK**).

## Co udělat

1. **Přečti `ess-configurator-notes.md` z adresáře tohoto skillu celý.**
   Když se Read ořízne, dočti přes `offset` — částečně přečtený soubor
   = nepřečtený.
2. Sesterské skilly (od 2026-11-04, číslování C1–C18 společné): **`ess-configurator-variants`**
   (C5, C11, C13, C14, C16 — identita varianty, dialog, engine a API, `Effective Hidden`,
   *Kopírovat hodnotu z*, filtr Vyhledání) a **`ess-configurator-extensions`** (C7–C10 — kusovník
   a cena varianty, EM Cutting Plan, Pricing Matrix přes Parametr A/B, eventy kopie). Úkol přes
   varianty nebo napojení COALU / COZLK → načti i příslušný sesterský skill.
3. Obecná AL pravidla platí dál: `bc-al-style`, `bc-al-posting` (3.6b `Validate("No.")`
   → `Init()`), `bc-al-ui`, u netriviální funkčnosti `bc-al-autotests`. Další
   konfigurátorové poznatky: `bc-al-objects.md` (5.x4 `Attached to Line No.`, 5.x8),
   `bc-al-tracking.md` (5.x2b).
4. Změna v produktové appce → release. Bump dependency minima v zákaznickém repu jen když
   novou verzi potřebuje **jeho kód** (nové pole / procedura / event), ne kvůli samotné opravě
   v base — buildy i zákazník berou nejnovější verzi (`bc-al-build` 7.11).
5. Nový poznatek → do souboru podle tématu (`ess-configurator-notes.md` / `-variants.md` /
   `-extensions.md`) + commit + push do všech remotů (viz skill `bc-al`).

## TL;DR

- **Systémový parametr = záporné `Line No.`** (`QUANTITY` = −1). V tabulce
  `Configuration Parameter COEBS` **neexistuje** — vzniká jen v temp bufferu
  lookupu, takže FlowField `Parameter Code` na řádku vzorce zůstane prázdný
  (page inspector: `(Neznámé)`). To je diagnostická stopa, ne chyba.
- ⚠️ **Hodnota `QUANTITY` se plní JEN v cestě akcí prodejního řádku**
  (`SL Action Cond. Mgt. COEBS` → `InjectSalesLineSystemParameters`, čte
  `SalesLine.Get` z DB). Ve **výchozí / min / max hodnotě parametru**, v podmínkách
  a v akcích kusovníku/postupu k dispozici **není** a
  `Formula Evaluation Mgt. COEBS.ResolveParameterValueText` vrátí tiše **`'0'`**.
  Vzorec `A * QUANTITY` tam prostě dá 0 — bez chyby, bez varování.
- ⚠️ **Lookup operandu kontext neřeší** — nabídne `QUANTITY` (i CNC `X`/`Y`/`Z`)
  ve všech vzorcích, i tam, kde se nikdy nenaplní. Než hledáš chybu ve výpočtu,
  zjisti `Source Type` + `Field Type` řádku vzorce.
- **`Action Formula Line COEBS` (63148) nemá `Field Type` v PK** — je to jen pole,
  na které se filtruje, a `Line No.` se čísluje napříč typy polí. Další nezávislý
  „kanál" vzorců = nová hodnota enumu `Formula Field Type COEBS` (Extensible)
  a případně **pole mimo PK**. **PK nasazené tabulky neměň.**
- **Textový vzorec (`Text Formula Line COEBS`, 63155) = konkatenace** Text / Parameter
  Name / Parameter Value / Parameter Value Name **+ řádek `Formula`** (`{= A * QUANTITY}`,
  větev `TextFormulaExpression` 2026-09-22, do releasu jen konkatenace). Operandy výrazu
  = `Action Formula Line` s `Field Type = Text Expression` a `Expression No.` — samostatné
  číslo napříč Field Types zdrojového řádku, **ne** `Line No.` textového řádku (C4).
  Výraz počítá nad týmž slovníkem jako textový vzorec → `QUANTITY` má jen v akcích
  prodejního řádku (C2).
- **Texty se aplikují i na poznámkový řádek** (`ApplyActionLineTexts` je
  v `InitNewSalesLineFromAction` nad větví `if not IsCommentLine`). Nula v popisu
  poznámky je vždy nula toho parametru, ne vlastnost typu řádku.
- **Texty přiřazuj až po `Validate("Variant Code")` / `Validate("Unit of Measure Code")`** —
  oba je přepíšou z karty zboží přes `Item Reference Management`.
- **Diagnostika dat zákazníka:** service stránky URL `?page=<ID>&filter=…` —
  **63163** operandy číselných vzorců, **63193** skladba popisů, **63149** uložené
  hodnoty varianty, 63173 definice parametrů, 63184/63185 akce prodejního řádku.
  Page inspector (Ctrl+Alt+F1) píše u polí klíče `PK` — nejrychlejší ověření,
  jestli změna vyžaduje migraci.
- ⚠️ **Nasazenou verzi appky ověř** (page 2500 / `get_installed_apps` přes
  d365bc-admin MCP), než porovnáš chování se zdrojákem — CI bumpuje build číslo,
  takže verze v prostředí je vyšší než `version` v `app.json`.
