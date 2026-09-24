---
name: ess-configurator
description: >-
  Essence Configurator (COEBS, repo prod-ess-configurator-bc) a zákaznická
  rozšíření nad ní (COALU Alumistr, COZLK Zlomek) v Business Central / AL:
  konfigurační parametry a podmínky, dialog konfigurace varianty, systémové
  parametry (QUANTITY Line No. -1, CNC X1/X/Y/Z -51990..-51993, eventy
  OnAddNumericSystemParameters / OnGetSystemParameterCode) a past tichých nul, číselné vzorce Action Formula
  Line (PK bez Field Type, Line No. napříč typy polí, Math Expression Parser),
  textové vzorce Text Formula Line (konkatenace {KOD:Value}/{KOD:ValueName} + řádek
  Formula {= A * QUANTITY} s Expression No., běží i na poznámkovém řádku), identita varianty = množina hodnot
  parametrů (FindExistingVariantWithSameValues), akce kusovníku / postupu /
  prodejního řádku a eventy jejich kopie, diagnostika (service stránky,
  inspector), Zrušit editorů (WasCancelled, EditFormula), pole EM Cutting
  Plan na kusovníku, MJ řádku přepsaná Pricing Matrix přes Parametr A/B. Načti u konfigurátoru, vzorců, variant a
  konfigurovaných řádků prodeje.
user-invocable: true
---

# Essence Configurator — parametry, vzorce, varianty

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
2. Obecná AL pravidla platí dál: `bc-al-style`, `bc-al-data` (3.6b `Validate("No.")`
   → `Init()`, 5.x4 `Attached to Line No.`), `bc-al-ui`, u netriviální funkčnosti
   `bc-al-autotests`. Starší konfigurátorové poznatky zatím i v `bc-al-objects.md`
   (5.x10, 5.x12, 5.x2b, 5.x8).
3. Změna v produktové appce → release + bump dependency minima v zákaznickém repu.
4. Nový poznatek → do `ess-configurator-notes.md` + commit + push do obou remotů
   (viz skill `bc-al`).

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
- **Identita varianty = množina vyplněných hodnot parametrů**
  (`FindExistingVariantWithSameValues` + `CompareParameterValues`). Parametr závislý
  na kontextu prodejního řádku (množství, datum, zákazník) do konfigurace **nepatří** —
  množil by varianty zboží a při změně na řádku by se stejně nepřepočítal. Takové
  veličiny patří do vzorců **akce prodejního řádku**.
- **Dialog kontext prodejního řádku zná** (`SetSalesLineContext` z
  `SalesLineConfigMgt.HandleVariantCodeLookup`) — chybějící hodnota ve slovníku
  parametrů není o nedostupnosti kontextu, ale o tom, že ji tam nikdo nedává.
- **Diagnostika dat zákazníka:** service stránky URL `?page=<ID>&filter=…` —
  **63163** operandy číselných vzorců, **63193** skladba popisů, **63149** uložené
  hodnoty varianty, 63173 definice parametrů, 63184/63185 akce prodejního řádku.
  Page inspector (Ctrl+Alt+F1) píše u polí klíče `PK` — nejrychlejší ověření,
  jestli změna vyžaduje migraci.
- ⚠️ **Nasazenou verzi appky ověř** (page 2500 / `get_installed_apps` přes
  d365bc-admin MCP), než porovnáš chování se zdrojákem — CI bumpuje build číslo,
  takže verze v prostředí je vyšší než `version` v `app.json`.
