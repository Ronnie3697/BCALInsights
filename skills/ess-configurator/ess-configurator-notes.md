# Essence Configurator — poznámky z praxe

> Doménové poznámky k produktové appce **Essence Configurator** (publisher
> `Essence International s.r.o.`, app ID `45c32b8e-5eb2-49c6-8914-456284d2b7b8`,
> affix **COEBS**, repo `prod-ess-configurator-bc`, <https://dev.azure.com/essencebs/Projects/_git/prod-ess-configurator-bc>) a k zákaznickým
> rozšířením nad ní (`configuratorExtension` u Alumistra = affix **COALU**,
> u Zlomku **COZLK**).
>
> Načítej, když řešíš: systémové parametry, vzorce (číselné i textové), strom
> podmínek parametru a jeho opravu, nerecyklovaná čísla parametrů a odkazy
> na parametry, *Číslo z parametru* na řádku akce prodejního řádku, diagnostiku
> konfigurace v běžícím BC, konfigurační balíček (RapidStart) pro přenos definic.
>
> **Rozděleno 2026-11-04** (soubor přesáhl 1000 řádků / 98 KB). Číslování C1–C17 zůstává napříč
> soubory, odkazy „viz Cx" platí:
> - **`ess-configurator-variants.md`** (skill `ess-configurator-variants`) — C5, C11, C13, C14, C16:
>   identita varianty, dialog konfigurace, `Variant Config. Engine` a API, `Effective Hidden`,
>   find-or-create, *Kopírovat hodnotu z* a filtr Vyhledání hodnotou parametru.
> - **`ess-configurator-extensions.md`** (skill `ess-configurator-extensions`) — C7–C10: napojení
>   zákaznických rozšíření (kusovník a cena varianty, EM Cutting Plan, Pricing Matrix přes Parametr A/B,
>   eventy kopie konfigurace).
>
> **Obecná AL pravidla platí dál** — `bc-al-style`, `bc-al-data`, `bc-al-ui`,
> u netriviální funkčnosti `bc-al-autotests`.
>
> Další konfigurátorové poznatky mimo tyhle soubory: 5.x2b tracking na nabídce
> (`bc-al-tracking.md`), 5.x8 Item Charge Assignment a 5.x4 `Attached to Line No.`
> (`bc-al-objects.md`), 3.6b `Validate("No.")` → `Init()` (`bc-al-posting.md`).

## Obsah

- [C1. Systémové parametry](#c1-systémové-parametry)
- [C2. Kde se hodnota systémového parametru plní — a kde ne](#c2-kde-se-hodnota-systémového-parametru-plní--a-kde-ne)
- [C3. Číselné vzorce — `Action Formula Line COEBS`](#c3-číselné-vzorce--action-formula-line-coebs)
- [C4. Textové vzorce — `Text Formula Line COEBS`](#c4-textové-vzorce--text-formula-line-coebs)
- [C6. Diagnostika konfigurace v běžícím BC](#c6-diagnostika-konfigurace-v-běžícím-bc)
- [C12. Strom podmínek parametru — zastaralé `Root Condition No.` (Zlomek)](#c12-strom-podmínek-parametru--zastaralé-root-condition-no-zlomek)
- [C15. Strom podmínek ze struktury (66845) a nerecyklovaná čísla parametrů (66711)](#c15-strom-podmínek-ze-struktury-66845-a-nerecyklovaná-čísla-parametrů-66711)
- [C17. Číslo z parametru pro všechny typy řádků akce prodejního řádku (67541)](#c17-číslo-z-parametru-pro-všechny-typy-řádků-akce-prodejního-řádku-67541)
- [C18. Konfigurační balíček (RapidStart) pro přenos definic konfigurátoru](#c18-konfigurační-balíček-rapidstart-pro-přenos-definic-konfigurátoru)

Vyčleněno: C5, C11, C13, C14, C16 → `ess-configurator-variants.md`; C7–C10 → `ess-configurator-extensions.md`.

---

## C1. Systémové parametry

**Systémový parametr** = operand vzorce, který nepochází z konfigurace, ale
z kontextu běhu (množství prodejního řádku, souřadnice CNC věty). Drží je
codeunit **63154 `System Parameter Mgt. COEBS`** (`Access = Public`).

- **Identifikace = záporné `Line No.`** (`IsSystemParameter(LineNo) := LineNo < 0`).
  Base má zatím jediný: **`QUANTITY`, Line No. `-1`**, název *Source Line Quantity*,
  typ `Decimal`, Sort Order `-10000`.
- **V tabulce `Configuration Parameter COEBS` neexistují.** Vznikají jen
  v temporary bufferu pro lookup (`AddAllSystemParameters` / `AddNumericSystemParameters`
  → `AddSystemParameterToTemp`). Důsledek: FlowField `Parameter Code` / `Parameter Name`
  na řádku vzorce se u nich **nedopočítá** (page inspector ukazuje `(Neznámé)`,
  grid prázdno) — viz C6.
- **Hodnota putuje ve slovníku** `Dictionary of [Code[20], Text]` klíčovaném
  *Parameter Code*, čísla v **invariantním formátu** (`Format(x, 0, 9)`, tečka).
- **Rozšiřitelnost pro zákaznické appky** — čtyři integration eventy:
  `OnAddNumericSystemParameters(ConfigNo; var TempConfigParam)`,
  `OnGetSystemParameterCode/Name/Type(ParameterLineNo; var …; var IsHandled)`.
  Vzor: `CNC Formula Param COALU` (52011) v `cust-alumistr-bc` registruje
  `X1` / `X` / `Y` / `Z` pod Line No. **−51990…−51993** (Sort Order −20000…−19970).
  Záporné Line No. musí být **unikátní napříč všemi appkami** — base drží −1 a −2,
  zvol si vlastní rozsah odvozený od svého object ID rozsahu.
- **`UNIT_PRICE` (−2)**: vydáno v **COEBS 28.0.37** (PR 9774, master 635a1f1, build 28944, 2026-10-16).
  - Hodnota = `Item."Unit Price"` zboží toho řádku, **pro který se vzorec právě počítá**, v měně dokladu
    (`Currency Exchange Rate.ExchangeAmtLCYToFCY(SalesHeader.GetUseDate(), …, "Currency Factor")`, zaokrouhlené na
    `Unit-Amount Rounding Precision` měny jako standardní přepočet ceny). Jiný typ řádku má 0. `SetLineItemUnitPrice` je `internal`.
  - Přepsání aktuálního řádku bere cenu konfigurovaného zboží (`InjectSalesLineSystemParameters`). Vytvářený řádek bere cenu
    svého zboží (`SetLineItemUnitPrice` v `InitNewSalesLineFromAction`).
  - ⚠️ **Slovník je sdílený** všemi vytvářenými řádky i následným `UpdateVariantDescription`. Hodnotu řádku proto nastav a po
    `OnBeforeModifyNewSalesLineFromAction` + `Modify` **vrať uloženou hodnotu**. Znovu volat injekci ne: pro každý řádek by
    četla zdrojový řádek z DB a sahala i na ostatní systémové parametry (`QUANTITY`; do opravy C2 se mezi řádky měnilo).
  - Takhle přidávej každý systémový parametr závislý na řádku.
  - Názvy systémových parametrů jsou od té doby přeložitelné labely (`MaxLength = 100`, jinak `PC0022` při `exit` do
    `Text[100]`). `{QUANTITY:Name}` tak v české relaci vrací česky.
  - Doc: `prod-ess-configurator-bc/docs/Configurator - Systémový parametr UNIT_PRICE … - plán.md`, CONFIGURATOR-DOCUMENTATION 14.2/14.3.

## C2. Kde se hodnota systémového parametru plní — a kde ne

⚠️ **Tohle je nejčastější zdroj tichých nul ve vzorcích.**

Hodnotu `QUANTITY` do slovníku zapisuje **jediná procedura**
`System Parameter Mgt. COEBS.InjectSalesLineSystemParameters(var ParameterValues;
SalesDocType; SalesDocNo; SalesLineNo)` — `SalesLine.Get(…)` + `ParameterValues.Set('QUANTITY',
Format(SalesLine.Quantity, 0, 9))`. Čte se tedy **uložený řádek z DB**, ne rozepsaný
řádek na stránce.

Volá ji **jen `SL Action Cond. Mgt. COEBS`** (přes lokální `InjectSalesLineQuantity`,
3 vstupní body: `ApplyCurrentLineOverrides`, `ExecuteSalesLineActions`,
`RecalculateConfigCreatedLines`). Tedy **pouze cesta vykonávání akcí prodejního řádku**.

| Kontext vyhodnocení vzorce | `QUANTITY` k dispozici? |
|---|---|
| Akce prodejního řádku — Množství, Jednotková cena, Sleva %, texty (Popis, Popis 2) | ✅ |
| Akce prodejního řádku na **poznámkovém řádku** (`Type = " "`) | ✅ (viz C4) |
| **Výchozí / Min / Max hodnota konfiguračního parametru** (dialog konfigurace) | ❌ |
| Podmínky parametrů, filtry Table Lookup | ❌ |
| Akce kusovníku (BOM) a postupu (Routing) | ❌ |
| CNC tisk (`CNC Print Mgt. COALU`) — tam se plní X1/X/Y/Z, ne QUANTITY | ❌ |

**Proč dialog hodnotu nemá:** `Variant Config Params COEBS` (63147) si slovník staví
procedurou `GetParameterValues` (od větve `VariantConfigEngineUnify` jen obálka nad
`Variant Config. Engine COEBS.GetParameterValues`, chování stejné — viz C11 v `ess-configurator-variants.md`) — projde jen řádky bufferu parametrů
konfigurace. Systémové parametry v tom bufferu nejsou. Navíc při úplně prvním
načtení (`LoadParameters`) se default počítá nad **prázdným** slovníkem
(`EmptyParameterValues`).

**Jak se chyba projeví:** `Formula Evaluation Mgt. COEBS.ResolveParameterValueText`
u systémového parametru, který ve slovníku není, vrací natvrdo řetězec **`'0'`**.
Žádná chyba, žádné varování — vzorec `A * QUANTITY` prostě vrátí 0 a uloží se.

⚠️ **Lookup operandu kontext neřeší.** `Text Formula Line."Parameter Line No."`
i `Action Formula Line."Parameter Line No."` v `OnLookup` volají
`AddAllSystemParameters` / `AddNumericSystemParameters` **bez ohledu na `Source Type`
a `Field Type`** vzorce, který se právě edituje. Uživatel si tedy `QUANTITY`
(nebo CNC `X`/`Y`/`Z`) legitimně vybere i tam, kde se nikdy nenaplní, a nic ho
nevaruje. Při návrhu nového systémového parametru s tím počítej — buď lookup
filtruj podle kontextu, nebo hodnotu injektuj i do zbylých cest.

**Než začneš hledat chybu ve vzorci:** ověř, v jakém *kontextu* se vyhodnocuje
(`Source Type` + `Field Type` na řádku vzorce), a teprve pak, co je ve slovníku.

(2026-09-21, cust-alumistr-bc — Alumistr měl `SKLO_POCET` = `VYP_KRIDLO_POCET * QUANTITY`
jako výchozí hodnotu parametru; ve variantě se uložila 0 a odtud prosákla do popisů
prodejních řádků. Táž konfigurace používala `QUANTITY` 4× na Množství akce prodejního
řádku — tam počítá správně.)

⚠️ **Přepsání aktuálního řádku (pole `CL …`) se u nové varianty použije dvakrát** (COEBS do 76ea8d6). Code review
2026-10-16, potvrzeno čtením kódu. **Opraveno v COEBS 28.0.37** (PR 9774 spolu s `UNIT_PRICE`, 2026-10-16), detail níže
v *Oprava*.

- **Proč:** dialog i API (`Variant Config. Engine.ApplyToSalesLine`) volají u nové varianty nejdřív `ExecuteSalesLineActions`
  (vloží `QUANTITY` → `ModifyCurrentLine`) a hned potom `ApplyCurrentLineOverrides`. Ten znovu načte `QUANTITY` z DB, tedy už
  přepsané, a `ModifyCurrentLine` pustí podruhé.
- **Důsledky:**
  - Vzorec Množství aktuálního řádku, který sám obsahuje `QUANTITY` (`2 * QUANTITY`), dá 1 → 2 → **4**. Každé další OK se
    stejnou variantou ho znovu zdvojí.
  - Eventy `OnBefore/OnAfterModifyCurrentSalesLine` se volají dvakrát.
  - Rozdělení řádku (`Sales Line Split Mgt.`, :87–92) pustí `ExecuteSalesLineActions` i na původní řádek: 10 → 3 + 7 skončí jako
    12 + 14.
- **Kdy to nevadí:** vzorce bez `QUANTITY` (parametry, konstanty, `UNIT_PRICE`) dají v obou průchodech totéž.
- **Další mezery:**
  - Připojené řádky z `ExecuteSalesLineActions` počítají s `QUANTITY` **před** přepsáním. Injekce proběhne před
    `ModifyCurrentLine`.
  - Vzorce aktuálního řádku se po změně množství nepřepočítají (`RecalculateConfigCreatedLines` zdrojový řádek nemění).
  - `ApplyCLPricingOverrides` validuje Množství až po ceně a slevě.
- **Oprava (větev `UnitPriceQuantityFixes`):**
  - Veřejné `ExecuteSalesLineActions` zůstává beze změny. Přepíše aktuální řádek i vytvoří řádky. Na tom stojí testy COZLK
    (`SLActionParamTests` čeká přepsání Parametr A/B na aktuálním řádku).
  - Nové interní přetížení `(…; WithCurrentLineOverrides = false)` jen vytvoří řádky. Volá ho dialog, engine a rozdělení řádku.
    Přepsání pak jednou provede `ApplyCurrentLineOverrides`, po nastavení varianty (validace varianty řádek přecení).
  - Po přepsání se `QUANTITY` znovu načte.
  - Pořadí v `ApplyCLPricingOverrides` je Množství → Cena → Sleva.
  - Když žádná splněná podmínka Množství nepřepisuje (už ne), je `QUANTITY` skutečné množství a zapamatovaná pole se vynulují.
  - Rozdělení řádku už na původní řádek akce nepouští. Připojené řádky mu přepočítá trigger `Modify`.
    ⚠️ Druhé volání akcí ale původnímu řádku vracelo **cenu z přepsání**. `Validate(Quantity)` řádek přecení z ceníku nebo
    matice (`OnAfterUpdateUnitPrice`), takže ji split teď vrací sám (`RestoreUnitPrice`, stejně jako slevu). Testy bez řádku
    ceníku to neodhalí: bez ceníku si řádek cenu nechá (`IsPriceUpdateNeeded`, 5.x21 v `bc-al-blanket.md`). Chytilo to až review.
    Nová linka splitu dostane přepsání **bez Množství** (`ApplyCurrentLineOverrides(…; WithQuantityOverride = false)`),
    takže 10 → 6 + 4. Obě linky mají zapamatovaná pole vynulovaná. Kontrola „připojené řádky
    jsou dodané nebo fakturované“ je teď na začátku rozdělení (`CheckConfigCreatedLinesNotPosted`, label přesunutý → nové
    trans-unit ID, 6.2 v `bc-al-xliff.md`).
  - Testy: `CL Override Tests COEBS` (63253).
  - Rozhodnutí uživatele: po ruční změně množství se vzorce aktuálního řádku nepřepočítávají a `QUANTITY` v Popisu varianty
    zůstává povolené.
  - **Opakované potvrzení:** `QUANTITY` v přepsání aktuálního řádku je **zadané množství**. Řádek si pamatuje pole
    `Config. Entered Qty. COEBS` (z čeho přepsání Množství vycházelo) a `Config. Overridden Qty. COEBS` (co nastavilo). Dokud má
    řádek přepsané množství, dosadí se zadané, takže `2 * QUANTITY` dá pořád 2. Ruční změna po přepsání se bere jako nové
    zadané množství (5 → OK → 10). Totéž `QUANTITY` dostanou ceny, slevy i texty přepsání. Vytvořené řádky počítají se
    skutečným množstvím. Vzor pro každý „sebe-referenční“ vzorec, který se může použít opakovaně: uložit vstup i výsledek
    a vstup použít, dokud výsledek nikdo nezměnil.
- Detail review a tabulka po průchodech: `prod-ess-configurator-bc/docs/Configurator - Systémový parametr UNIT_PRICE … - plán.md`,
  sekce *Související nález*. Oprava: `docs/Configurator - Přepsání aktuálního řádku se použije jen jednou.md`.

## C3. Číselné vzorce — `Action Formula Line COEBS`

Tabulka **63148**, editor page **63162 `Action Formula COEBS`** (Worksheet),
service page **63163 `Action Formula Svc COEBS`**.

### PK **neobsahuje `Field Type`**

```al
key(PK; "Configuration No.", "Condition Line No.", "Source Type", "Source Line No.", "Line No.")
```

`Field Type` (pole 6, enum `Formula Field Type COEBS`) je **obyčejné datové pole**,
na které `EvaluateFormula` jen filtruje (`SetRange`). Dva důsledky:

- **`OnInsert` čísluje `Line No.` napříč všemi `Field Type`** téhož akčního řádku —
  vzorec pro Množství a vzorec pro Jednotkovou cenu tak sdílí jednu číselnou řadu
  a nekolidují. To je záměr, ne chyba.
- **Nový „kanál" vzorců na tentýž zdrojový řádek = nová hodnota enumu, ne změna klíče.**
  Když potřebuješ další rozlišovací osu (víc nezávislých výrazů na jednom řádku),
  přidej **pole mimo PK** a filtruj na něj stejně jako na `Field Type`. PK nasazené
  tabulky neměň.

### Enum `Formula Field Type COEBS` (63146, `Extensible = true`)

`0 " "`, `1 Quantity`, `2–5` časy postupu (Setup/Run/Wait/Move), `10 Default Value`,
`11 Min Value`, `12 Max Value`, `20 Unit Price`, `21 Line Discount %`,
`30 Item Variant Desc.`, `40 Description`, `41 Description 2`, `42 Search Name`
(40–42 = pole stavěná **textovými** vzorci), `50 Text Expression` (operandy výrazu
vloženého do textového vzorce, rozlišené polem `Expression No.` mimo PK — viz C4;
větev `TextFormulaExpression`, 2026-09-22).

### Vyhodnocení

`Formula Evaluation Mgt. COEBS` (63149) — `EvaluateFormula(ConfigNo; ConditionLineNo;
SourceType; SourceLineNo; FieldType; var ParameterValues; DefaultValue): Decimal`.
Poskládá text výrazu (`BuildFormulaText`) a pustí `Math Expression Parser COEBS`.
Bez řádků vzorce vrátí `DefaultValue`.

- Operand = buď `Parameter Line No.` (běžný i systémový parametr), nebo
  `Constant Value`. **Parametr má přednost** — když je `Parameter Line No.` <> 0,
  konstanta se ignoruje.
- Nenalezený parametr (běžný i systémový) → **`'0'`**, tiše (viz C2).
- Hodnoty se z textu parsují přes `Cond. Comparison Mgt. COEBS.TryParseDecimal`
  (locale-tolerantní) a zpět `Format(x, 0, 9)`.
- `EditFormula(…)` otevře editor modálně s backupem a **restore při Cancel** —
  hotová obálka, používej ji z pageextensions místo vlastního dialogu.

Výchozí / Min / Max hodnoty parametrů počítá `Config. Condition Mgt. COEBS`
(`HasDefaultDecimalValue` / `HasDefaultIntegerValue` / `ApplyConditionDefault*`)
voláním `EvaluateFormula` se `SourceType::Parameter` a `FieldType::"Default Value"`;
`Source Line No.` = `Line No.` parametru, `Condition Line No.` = 0 pro základní
default a číslo podmínky pro podmínkový override.

## C4. Textové vzorce — `Text Formula Line COEBS`

Tabulka **63155**, enum typu řádku **63154 `Text Formula Line Type COEBS`**,
codeunit **63153 `Text Formula Eval. Mgt. COEBS`**, service page **63193**.
PK: `Configuration No., Condition Line No., Source Type, Source Line No., Field Type, Line No.`
(tady `Field Type` **v klíči je**, na rozdíl od C3).

### Konkatenace + (od větve `TextFormulaExpression`) vložený číselný výraz

Typy řádku: `Text` (literál z `Text Value`), `Parameter Name`, `Parameter Value`,
`Parameter Value Name` (display text vybrané hodnoty, fallback na hodnotu samotnou).
Náhled v UI: `{KOD:Name}` / `{KOD:Value}` / `{KOD:ValueName}`.

**Systémové parametry textový vzorec umí** (`ResolveParameterCode` →
`SystemParamMgt.GetSystemParameterCode`), takže `{QUANTITY:Value}` funguje.
**Do releasu 28.0.22.x počítat neuměl** — „počet křídel × množství objednávky" se do
popisu přímo napsat nedalo a pomocný konfigurační parametr se vzorcem spadl do C2.

**Řádek typu `Formula` (5) — `{= VYP_KRIDLO_POCET * QUANTITY}`** (větev `TextFormulaExpression`,
commit 6269fbf pushnutý 2026-09-22, čeká na PR/release; pak bump minima v `cust-alumistr-bc`.
Uživatelská i technická dokumentace: `app/docs/CONFIGURATOR-DOCUMENTATION.md` kap. 13.7, white papery 10.2,
zadání `docs/Configurator - Aritmetika v textových formulích….md`):

- Operandy leží v `Action Formula Line COEBS` pod `Field Type = Text Expression` (50) a
  **`Expression No.`** (pole 7, mimo PK). Vyhodnocení `Formula Evaluation Mgt.EvaluateFormula(…;
  FieldType; ExpressionNo; …)` nad **týmž slovníkem**, jaký dostal textový vzorec — u popisů akcí
  prodejního řádku tedy `QUANTITY` **je** (C2). Výsledek `Format(x, 0, '<Precision,n:n><Standard
  Format,9>')` podle `Decimal Places` (pole 16) — tečka, stejný tvar jako `{KOD:Value}`.
- ⚠️ **`Expression No.` není `Line No.` řádku textového vzorce.** Je to samostatné pořadové číslo
  přidělované v `OnValidate("Line Type")` / `OnInsert` přes sekundární klíč `ExpressionNo`
  (`FindLast` + 1) **napříč všemi `Field Type` téhož zdrojového řádku** — textové vzorce *Popis*
  a *Popis 2* jednoho akčního řádku začínají obě řádkem 10000, ale jejich operandy sdílí jednu
  množinu `Action Formula Line` (`Field Type` textového vzorce tam nefiguruje). Druhý důvod: kopie
  konfigurace řádky textového vzorce přečíslovává (`GetNextGroupedTextFormulaLineNo`), zatímco
  `TransferFields(…, false)` přenese `Expression No.` beze změny → vazba přežije kopii bez remapu.
- Kaskády: `Text Formula Line.OnDelete` maže operandy; přepnutí typu z `Formula` je maže a nuluje
  `Expression No.` + `Decimal Places`; `EditTextFormula` zálohuje **i operandy** a při Cancel je
  vrací (smazání textových řádků by je kaskádou odstranilo).
- Editor `Text Formula COEBS`: u řádku `Formula` otevře tlačítko Pomoc (…) i akce *Upravit výraz*
  stávající editor `Action Formula COEBS` (`EditFormula(…; ExpressionNo; MaxParameterSortOrder)`),
  sloupec *Hodnota* jen zobrazuje náhled; OK validuje „bez výrazu" + `Formula Validation Mgt.`.
- ⚠️ **Kopie konfigurace a `Dictionary.Get` bez ošetření nuly.** `CopyBOMQtyFormulaLines` /
  `CopyRoutingTimeFormulaLines` mapovaly `Condition Line No.` i `Source Line No.` přes `Get` — do
  zavedení výrazů žádný `Action Formula Line` se `Source Type` BOM/Routing a nulou neexistoval.
  Operandy výrazu v *BOM Description* podmínky (`Source Line No.` 0) nebo *Def. BOM Description*
  definice (`Condition Line No.` 0) by kopii shodily na chybějícím klíči. Když přidáváš nový druh
  `Action Formula Line`, projdi všechny `Copy*FormulaLines` a ověř, že každý filtr tvůj kontext
  buď mapuje, nebo vyloučí (`SetFilter("Condition Line No.", '<>0')` + config-level kopie zvlášť).
- Šablony parametrů textové vzorce nenesou → `CopyFormulasToTemplate` řádky `Text Expression` vynechá.
- ⚠️ **Výchozí text z textového vzorce na PODMÍNCE se po změně vstupního parametru nepřepočítá** (COEBS 28.0.41 = master
  a76683f; analýza 2026-11-11, Alumistr BC-TEST, konfigurace 0079 / kopie 0103, parametr KOOP-BARVA-TEXT). Textový vzorec
  výchozí hodnoty se dá dát na parametr (`Condition Line No.` 0) i na podmínku (4fe0683 / PR 9533, 2026-09-18). Závislosti
  a *Přepočítat* ale pořád filtrují `TextFormulaLine.SetRange("Condition Line No.", 0)`. Platí to pro
  `Config. Condition Mgt.GetDependentParamLineNosInt` (smazání závislých po změně hodnoty) i pro `GetDerivedParameterLineNos`
  (akce *Přepočítat*). Číselné vzorce (`Action Formula Line`) podmínku nefiltrují.
  - Důsledek: parametr `IF BARVA-AL = RAL → {RAL-CISLO:Value} {RAL-POVRCH:Value}` se při první konfiguraci postaví dobře,
    protože se staví v pořadí. Změna RAL-CISLO ve znovu otevřené variantě ho ale nesmaže a *Přepočítat* ho nebere jako
    odvozený, takže zůstane starý text. Ten pak teče do textových vzorců kusovníku / TNG / prodejního řádku (barva kooperace).
  - Engine i ListPart před sjednocením (`eeba4b9^1`) vyplněný řádek nikdy znovu nevyhodnotí, jen smažou závislé. Nejde tedy
    o regresi sjednocení, nefungovalo to od zavedení vzorců na podmínce.
  - Obejití zákazníka: vnořené podmínky `IF RAL-CISLO <> '' → IF RAL-POVRCH <> ''`. Podmínka se zdrojem = vstup jde přes
    větev `Source Parameter Line No.`, která se sleduje.
  - Stejná díra: operandy řádku `Formula` (`{= …}`) ve výchozím textu leží v `Action Formula Line` s `Field Type = Text Expression`,
    ale závislosti filtrují jen `Default Value`.
  - **Opraveno ve větvi `CondTextFormulaDependency`** (worktree `prod-ess-configurator-bc-condtextdep`, 2026-11-11, zatím
    necommitnuto). V obou procedurách padl filtr `Condition Line No.` u textových vzorců. Závislosti berou `Action Formula Line`
    s `Field Type` `Default Value|Text Expression`. Testy jsou v `Cascade Dependent Tests` a `Config. Engine Tests`
    (znovu načtená varianta, Přepočítat, `{= SIRKA * 2}`).
  - Ověřeno na Alumistr BC-DEV CRONUS CZ (dev COEBS 28.0.41.1, konfigurace `CLAUDE-KOOP`, objednávka 101049). Před opravou
    zůstal `RAL-2000-MAT` i po Přepočítat, po opravě `RAL-3000-MAT`, `RAL-3000-LESK` a výraz 200 → 300.
  - Důsledek: parametr se vzorcem jen na jedné podmínce je odvozený celý. Ruční přepis jeho hodnoty změna vstupu i Přepočítat
    nahradí výchozí hodnotou splněné podmínky, stejně jako u číselných vzorců.
- ⚠️ **Kopie konfigurace nulovala systémové parametry ve vzorcích** — `TryRemapParamLineNo` přepsal každé
  `Parameter Line No.`, které není v mapě parametrů, na 0; `QUANTITY` (−1) ani CNC `X/Y/Z` tam nejsou → kopie
  `WINGS * QUANTITY` dala `WINGS *` → po trimu operátoru `WINGS` (test čekal „10 KS", přišlo „5 KS"). Platilo
  odjakživa i pro číselné vzorce Množství / Jednotková cena, jen to žádný copy test nepokrýval. Fix: záporné
  Line No. (`SystemParamMgt.IsSystemParameter`) zůstává beze změny; test `CopyKeepsSystemParameterOperandInSLFormula`.
  Šablony (`GetParameterCode` / `ResolveParamLineNo` přes `Parameter Code`) systémový parametr **pořád ztratí** —
  neřešeno, v kontextu výchozích hodnot parametrů stejně nemá hodnotu (C2). (2026-09-22, build 28404, commit 5791d84.)
- **Cancel editorů vzorců = akce *Zrušit* (`CancelEdit`) + `WasCancelled()`.** `Text Formula COEBS` a `Action Formula COEBS`
  jsou `PageType = Worksheet`; modálně nemají built-in Cancel a zavření křížkem vrátí `Action::OK` (ověřeno v BC), takže
  restore větev `EditTextFormula` / `EditFormula` z UI neběžela. Od větve `TextFormulaExpression` (2026-09-22) mají oba
  editory akci `CancelEdit` (flag → `OnQueryClosePage` bez validace, `WasCancelled()`); `EditFormula`, `EditTextFormula`
  i 12 přímých `RunModal` volání na stránkách akcí / parametrů / podmínek testují `= Action::OK and not WasCancelled()`.
  Nový přímý caller editoru musí dělat totéž, jinak Cancel uživateli změny ponechá. Detail vzoru v `bc-al-autotests.md`.
  **Zákaznické rozšíření s vlastním přímým `RunModal` editoru** ho radši nahraď obálkou `FormulaEvaluationMgt.EditFormula(…)`
  (záloha, Zrušit i obnova žijí v base, po OK stačí vynulovat statickou hodnotu) — takhle od 2026-09-22 Alumistr
  `SL Action Cond. Card/Dlg COALU` (Parametr A/B, dřív kopie base vzoru s `= Action::OK` → Zrušit ponechal změny bez validace
  a smazal statickou hodnotu). COALU editory přes `EditFormula` / `EditTextFormula` dostaly Zrušit zadarmo s bumpem na 28.0.26.
  TestPage na stránku podmínky otevírej `Trap()` + `Page.Run(Page::…, Rec)` a konfiguraci dej do **Draft** — `OnOpenPage`
  jinak stránku zamkne (`CurrPage.Editable(false)`) podle stavu konfigurace záznamu, na kterém se otevřela.

### Texty se aplikují i na poznámkový řádek

V `SL Action Cond. Mgt. COEBS.InitNewSalesLineFromAction` je volání textových
vzorců **záměrně nad** větví pro poznámku:

```al
IsCommentLine := SLActionLine.Type = SLActionLine.Type::" ";
…
ApplyActionLineTexts(NewSalesLine, SLActionLine, ParameterValues);   // běží vždy
if not IsCommentLine then begin                                      // množství, ceny, MJ, data, dimenze
    ApplyActionLineAmounts(…);
```

Takže `{QUANTITY:Value}` v popisu **poznámkového** řádku hodnotu dostane.
Když tam vyjde nula, hledej ji v parametru, který popis používá, ne v typu řádku.

⚠️ **Pořadí: texty až po `Validate("Variant Code")` a `Validate("Unit of Measure Code")`** —
oba triggery volají `Item Reference Management.EnterSalesItemReference` a `Description`
i `Description 2` přepíšou z karty zboží (detail 3.6b v `bc-al-posting.md`).

## C6. Diagnostika konfigurace v běžícím BC

Service stránky nad tabulkami konfigurátoru jsou `Editable`, ale pro **čtení** dat
zákazníka jsou nejrychlejší cesta — otevřeš je přímo URL (i bez `UsageCategory`):

```
…/<env>?company=<Company>&page=<ID>&filter=%27Configuration%20No.%27%20IS%20%270054%27
```

| Page | Tabulka | K čemu |
|---|---|---|
| 63163 `Action Formula Svc COEBS` | `Action Formula Line COEBS` | operandy číselných vzorců (`Typ zdroje`, `Typ pole`, `Číslo řádku parametru`, `Operátor`) |
| 63193 `Text Formula Svc COEBS` | `Text Formula Line COEBS` | skladba popisů (`Typ řádku`, `Hodnota textu`, `Kód parametru`) |
| 63149 `Variant Configurations COEBS` | `Variant Configuration COEBS` | **uložené hodnoty** parametrů varianty (filtr `'Variant Code' IS 'COEBS0230'`) |
| 63173 `Config. Params. Svc COEBS` | `Configuration Parameter COEBS` | definice parametrů |
| 63184 / 63185 | `SL Action Condition` / `SL Action Line COEBS` | akce prodejního řádku |
| 63176 `Cond. Result Values Svc COEBS` | `Condition Result Value COEBS` | povolené hodnoty z podmínek |

**Stopy, podle kterých poznáš systémový parametr ve vzorci:**
`Číslo řádku parametru` < 0 a `Kód parametru` / `Název parametru` **prázdný**
(page inspector: `Parameter Code (13, Code[20]) = (Neznámé)`) — FlowField hledá
záznam, který v `Configuration Parameter COEBS` neexistuje (C1).

**Page inspector (Ctrl+Alt+F1)** je nejrychlejší způsob, jak ověřit, co je v PK:
u polí klíče píše `PK` za typem (`Source Type (5, Option, PK)`), u ostatních ne.
Ušetří to hádání nad zdrojákem, když řešíš, jestli změna vyžaduje migraci.

**Kdo plní Parametr A/B (COZLK) — dotaz přes servisní stránky:** `63184` s `filter='CL Parameter A COZLK' IS '<>0'`, `63185` s
`'Parameter A COZLK' IS '<>0'` (filtr jde i na pole rozšíření, které stránka nezobrazuje) a `63163` s `'Field Type' IS 'Parametr A'`
(enum filtruj **captionem**, BC ho přepíše na ordinál `52410`; AL název `Parameter A COZLK` tiše vynechá). Zlomek BC-DEV2 / ZLOMEK
2026-11-04: všude 0 → A/B na nabídkách nejsou z konfigurátoru. Po upgradu na COZLK s 67458 jsou statiky v kódových polích →
filtr `'CL Parameter A Value COZLK' IS '<>'''''` / `'Parameter A Value COZLK' IS '<>'''''`; ordinál enumu `52410` zůstává
(je uložený ve vzorcích, nepřečíslovat). **Testovací konfigurace bez číselné řady:** definici založ přes
editovatelnou `63177` s ručním `No.` (na kartě 63141 je `No.` jen z `Configuration Nos.`). I ruční `No.` ale chce existující
záznam `Configurator Setup` (`OnValidate` volá `Get` + `TestManual`). Bez něj karta i 63177 hlásí *„Nastavení konfigurátoru
neexistuje“*. Prázdný záznam založí otevření stránky **63195** (`InsertIfNotExists`), s prázdnou řadou pak ruční číslo projde
(Alumistr BC-DEV CRONUS CZ, 2026-11-11); v editoru vzorce do *Hodnota* parametr
nepiš (chyba „Zadejte platnou číselnou hodnotu…“), vyber ho přes `…`. CRONUS CZ `TEST67458` (1936-S, `IF SIRKA > 0` → CL Parametr A
= (SIRKA), Výška 1970) dala přes COZLK 28.0.99.0 + PMEBS 28.0.7.6 řádky 1970/800 a nově založený rastr 1970/555. (PBI 67458.)

⚠️ **Posun parametru dolů končí na `Sort Order` 999 999.** `Configuration Parameters COEBS.MoveParameter` (od 7448d6b, 2025-12)
hledá souseda `SetRange("Sort Order", Current + 1, 999999)`. `OnInsert` parametru ale přiděluje max + 10000 bez stropu, takže
konfigurace s ~100 a víc parametry (nebo s mezerami po přesunech) má pořadí přes milion. Parametr, jehož dolní soused leží za
999 999, hlásí „Tento parametr je již na posledním místě.“ Posun nahoru funguje (`0 .. Current - 1`). Alumistr BC-TEST 0103
(2026-11-11): max 1 080 000, dolů nejde KOOP_HORIZONTAL (990 000) a všechno za ním.

**Sort Order ≠ Line No.** V lookupu operandu vidíš u systémových parametrů sloupec
*Pořadí řazení* se zápornými čísly (`QUANTITY` −10000, CNC `X1` −20000 … `Z` −19970) —
to je jen řazení nad běžné parametry. Identifikátor je `Line No.` (−1, −51990…−51993).

⚠️ **Ověř nasazenou verzi appky, než porovnáš chování se zdrojákem** (page 2500,
nebo `get_installed_apps` přes d365bc-admin MCP — je to spolehlivější než grid
v prohlížeči). CI bumpuje build číslo, takže verze v prostředí bývá vyšší než
`version` v `app.json` na masteru; podstatné je, jestli v mezidobí někdo nenasadil
lokální build. Detail 5.x11 v `bc-al-objects.md`.

## C12. Strom podmínek parametru — zastaralé `Root Condition No.` (Zlomek)

`Parameter Condition COEBS` je binární strom: `True Child Line No.` / `False Child Line No.` + pole **`Root Condition No.`**.
Engine (`Config. Condition Mgt. COEBS`, 28.0.26) stromové vazby **nečte od skutečného kořene**, věří uloženému rootu:

- `GetConditionTableFilter` / `GetConditionAttributeFilter` (i default / copy / hide / read-only) projdou **všechny** podmínky
  parametru s vyplněným filtrem v pořadí `Line No.` a pro každou volají `IsSatisfiedRootCondition` = průchod od
  **`Root Condition No.`** k uzlu. **Vyhrává poslední splněný podle `Line No.`** („deepest wins" je ve skutečnosti „nejvyšší Line No.").
- `EvaluateAllTrees` (povolené hodnoty Výběru) bere jako kořen každý uzel s `Root Condition No. = Line No.` a výsledky sjednotí.
- Stromová stránka `Param. Conditions List COEBS` (63151) počítá TRUE/FALSE/ROOT a odsazení **z vazeb potomků**, ne z rootu →
  uživatel vidí správný strom, i když engine počítá jinak. Rozbitý root z UI nepoznáš.

⚠️ **Zastaralý root vzniká připojením existující podmínky šipkou.** `LookupChildCondition` (karta/dialog podmínky, OnLookup
pole True/False Child Line No.) jen vrátí `Line No.` — připojené podmínce ani jejímu podstromu root **nepřepíše**. Podmínka založená
jako samostatná (root = vlastní Line No.) nebo kopie větve akcí **Kopírovat** ve stromu (`CopyParameterCondition` → kopie = nový kořen)
tak po připojení zůstane samostatným kořenem a vyhodnocuje se **bez podmínek nad sebou**. Tři tečky (`CreateAndOpenChildCondition`)
root nastaví správně, ale potomek zdědí root rodiče — pod rozbitým uzlem je rozbitý i nový potomek. Stejný lookup mají
i karty/dialogy podmínek kusovníku, postupu a SL akcí; jejich evaluátory ale `Root Condition No.` nečtou (grep 2026-09-25).

**Případ (2026-09-25, Zlomek BC-TEST, PBI 66430 / IN-017406, CONF0000072 Dveře SIMPLY, ZB00027 / O000030; analýza a plán opravy v `cust-zlomek-bc/docs/66430 - IN-017406 - …md`):** ZAMEK_TYP (Vyhledání v Item, filtr atributů
`Provedení`) má stromy `ZAMEK = PZ | BB | WC` → `ORIENTACE_AKT_DVERI = LEVE` → (ELSE) `= PRAVE` → `TYP` → řetěz `POUZITI`. ELSE uzly
`PRAVE` (1840000 u PZ, 2450000 u WC) mají root samy na sebe → pro pravé dveře projdou **obě** větve bez ohledu na ZAMEK a vyhraje
WC (vyšší Line No.) → nabídka jen WC zámků (i pro PZ a BB). Závěsy totéž: `PRAVE` pod `TYP = BEZFALCOVE` bez rootu → pravé falcové dveře dostanou filtr bezfalcových závěsů. Z 152 podmínek 118 se špatným rootem, simulace 540 ze 720 kombinací jinak než strom;
v celé konfiguraci 237 z 681 (ORIENTACE_AKT_DVERI, ZAVES, ZAMEK_TYP, ORIENTACE_PAS_DVERI). Na celém BC-TEST Zlomek 1 214 z 9 506 podmínek ve 34 z 50 definic, z toho **7 aktivních** (CONF0000062–68, ZB00027–33) — tiše počítají jinak, než ukazuje strom. Více rodičů / cyklus / odkaz na sebe 0, odkaz na neexistující podmínku 1 (koncept).

**Diagnostika:** service page 63175 `Param. Conditions Svc COEBS` (`?page=63175&filter='Configuration No.' IS '…'`) — sloupce
*Číslo kořenové podmínky*, *Číslo řádku potomka pravda/nepravda*; skutečný root = projdi rodiče přes vazby potomků a porovnej.
Grid je virtualizovaný — v Claude in Chrome čti DOM iframu (`document.querySelector('iframe').contentDocument`, hlavička je
`table[0]`, řádky `table[1]`) se scrollováním kontejneru a sbírej do `window` proměnné; výstup JS nástroje se ořezává kolem ~1,5 kB
a text připomínající query string vrací `[BLOCKED: Cookie/query string data]`.

Evaluátor navíc lookup v `CollectExcludedChildLineNos` nevyřazuje **předky** → jde připojit vlastní kořen jako potomka (cyklus, rekurze `EvaluateConditionTree`). Nejlepší místo pro údržbu rootu je `Condition Tree Mgt. COEBS.ComputeTreeOrder` — strom už prochází od skutečných kořenů kvůli pořadí a odsazení.

Podmínky **kusovníku, postupu a SL akcí** kořen odvozují ze struktury (`IsRootCondition` = na podmínku nikdo neodkazuje), jen podmínky parametrů čtou uložené pole. Validace vazby dnes = jen `TableRelation` (ruční zadání projde i s vlastním číslem, předkem nebo už připojenou podmínkou → cyklus / více rodičů); `ComputeTreeOrder` sdíleného potomka toleruje jen pro zobrazení (test `ComputeTreeOrderPlacesSharedChildOnlyOnce`). Tiché přeskočení neplatné části stromu nabídku **rozšíří** — prázdný seznam povolených hodnot = neomezený výběr (`ShouldIncludeParameterValue`). `OnLookup` pole potomka přiřazuje přímo do `Rec`, uloží se až `CurrPage.Update(false)` v `OnValidate` stránky → přepočet stromu (čte DB) patří až za `CurrPage.SaveRecord()` a po něm `Rec.Find('=')`. Plán v2 po review: `prod-ess-configurator-bc/docs/66430 - …md` (klon `-66430`).

⚠️ **Smazání podmínky + recyklace `Line No.` = tichá přestavba stromu.** Tabulky podmínek číslují `FindLast + 10000` (podmínky
parametru per konfigurace + parametr, SL / kusovník / postup per konfigurace) → nová podmínka dostane číslo smazané poslední.
Vazbu rodiče (`True/False Child Line No.`) na smazanou podmínku čistí **jen** akce Odstranit ve stromu parametrů
(`DeleteConditionWithChildren` → `ClearParentReferences`); `OnDelete` tabulek ne, karty / dialogy / service stránky mají
`DeleteAllowed = true` a akce Odstranit ve stromech SL / kusovníku / postupu volá holé `Delete(true)`. Nová podmínka se pak
**přilepí pod starého rodiče** a kontrola „odkaz na neexistující podmínku" ji už nechytí. `Condition Result Value COEBS`
(výsledné hodnoty podmínky parametru) **nemaže nikdo** (ani `OnDelete` podmínky, ani smazání parametru či definice — jen
service page), takže recyklovaná podmínka zdědí povolené hodnoty smazané. Zrušit v `CreateAndOpenChildCondition` maže
`Delete(false)` → zůstanou i vzorce a potomci založení v dialogu. (2026-09-29, doplněk k analýze 66430, COEBS master c45bcc2.)

**Oprava patří do COEBS:** (1) při připojení potomka (OnValidate/OnLookup child polí, ideálně centrálně v tabulce) přepsat root celého
připojeného podstromu na root rodiče; (2) evaluátor ať kořen odvozuje ze struktury (uzel, na který nikdo neukazuje), ne z pole;
(3) upgrade / akce „přepočítat kořeny" pro existující data. → **Implementováno v tasku 66845** (2026-10-08, zatím nevydáno), detail C15.

## C15. Strom podmínek ze struktury (66845) a nerecyklovaná čísla parametrů (66711)

> Stav 2026-10-08: obě větve v `prod-ess-configurator-bc` **nevydané** — `66845_ConditionTreeFromStructure` (lokální commit
> 9aaa017) a nad ní `66711_ParamLineNoReuse` (necommitnuto); COZLK část 66711 ve `cust-zlomek-bc` větev `66711_ParamLineNoReuse`.
> Testy jen zkompilované. Dokumentace: `docs/66845 - …md`, `docs/66711 - …md`, CONFIGURATOR-DOCUMENTATION 5.8 / 18.4 / 20.4.

**66845 — vyhodnocení podmínek parametru od skutečného kořene:**
- `Config. Condition Mgt. COEBS` načte podmínky parametru jedním `FindSet`, zkontroluje strom
  (`Condition Tree Mgt.CheckParameterConditionTree` — víc rodičů, cyklus, vlastní potomek, neexistující potomek = **Error**
  s konfigurací, parametrem a číslem podmínky) a projde od kořenů (podmínka, na kterou nikdo neodkazuje) splněnou cestu.
  `Root Condition No.` engine nečte; pole udržuje `UpdateParameterConditionTree` / `UpdateParamTemplateTree` a na stránkách je jen
  pro čtení. ⚠️ Neplatný strom teď **shodí dialog, API i vnořenou konfiguraci COZLK** (dřív tiše rozšířená nabídka) — po nasazení
  pustit report 63140 a neopravitelné stromy opravit ručně.
- **Od 67634 (IN-013595, 2026-11-05) udržují `Root Condition No.` i stromy BOM / Routing / SL** (`Update…ActionTree` s `RootOf`,
  karty a dialogy akcí volají `RefreshConditionTree` po změně vazby, report 63140 kořeny akcí počítá i srovná). Do té doby
  psaly jen pořadí a test `SLTreeRecalculationKeepsStoredRoot` to hlídal → kopie podmínky (*Kopírovat* = samostatný strom)
  připojená zadáním čísla do *Číslo řádku potomka* si nechala vlastní kořen. Evaluátory akcí kořen dál berou ze struktury,
  vada byla jen v zobrazeném poli. **COALU CNC strom** má stejný vzor a zatím ho neudržuje.
- Vazby True/False Child validuje `OnValidate` všech pěti tabulek podmínek (`CheckChildLink`: sám sebe, předek, už připojená
  podmínka, druhá větev — druhou větev bere **z paměti**, na kartě jdou změnit obě před uložením); šipka nenabízí předky (nový
  overload `Condition Page Helper.CollectExcludedChildLineNos` s mapou vazeb; starý overload a 5parametrový `ComputeTreeOrder`
  zůstaly kvůli COALU CNC). OnLookup vrací hodnotu přes `Text` + `exit(true)`, ať jde přes validaci.
- `OnDelete` podmínky odpojí rodiče (`ModifyAll` na rodičích, **s vyloučením sebe sama**) a u podmínky parametru smaže
  `Condition Result Value`. ⚠️ Hromadné mazání s triggerem (`DeleteAll(true)` z parametru, definice, „Delete All Records“
  service stránek) nejdřív vazby v rozsahu vynuluje `ModifyAll(..., 0, false)` — jinak by `OnDelete` jednoho řádku měnil
  sourozence, které `DeleteAll` vzápětí maže se zastaralou verzí. Podstrom se maže **pre-order** (rodič dřív než potomci).
  ⚠️ **Test toho předčištění potřebuje rodiče s vyšším `Line No.` než potomka** (vzor COEBS `CreateLinkedSLConditions`:
  C → True: A → False: B, kořen C založený poslední). `DeleteAll(true)` maže v pořadí PK; strom A → B → C v pořadí založení
  smaže rodiče dřív, než `OnDelete` potomka hledá rodiče, takže test projde i bez `ModifyAll(..., 0, false)` a regresi
  nehlídá. (Code review 2026-10-09, cust-alumistr-bc `CNC Data Repair Tests COALU.DefinitionWithLinkedCNCTreeIsDeleted`.)
- Místo upgrade codeunitu report **63140 `Config. Data Repair COEBS`** (bez UsageCategory, `?report=63140`, výchozí „Pouze
  zkontrolovat“, logika v codeunitu 63158): přepočet rootů, vazby na neexistující podmínky → 0, osiřelé výsledné hodnoty pryč,
  neopravitelné stromy do Error Messages. Pouští se v každé společnosti zvlášť.
- **Rozšíření s vlastním stromem podmínek** (COALU `CNC Action Condition`, vlastní kopie stromové logiky) se do reportu napojí
  eventem **`OnAfterRepairConfiguration(ConfigNo; CheckOnly; var TempErrorMessage; var Counters)`** (63158, na konci
  `RepairConfiguration`, po datech COEBS; větev 66845, 2026-10-09): respektovat `CheckOnly`, počty přes public `AddToCounter`
  do stávajících počitadel, vady `LogMessage` s kontextem na zprávě, bez `Commit`. Společná logika je public: `RemoveDanglingLinks`
  (63158) a `Condition Tree Mgt.` `ComputeTreeOrder` s `RootOf`, `FindTreeDefect`, `CheckChildLink`, `GetAncestorLineNos`.

**66711 — `Line No.` smazaného parametru se nepoužije znovu:**
- Čítač v **samostatné tabulce 63164 `Config. Param. Counter COEBS`**, ne v poli definice: `Configuration Parameter.OnInsert` běží
  pod otevřenou kartou definice (part Parametry, akce Nový) a `Modify` definice z triggeru řádku by kartě nechal zastaralý `Rec`
  (3.9 v `bc-al-data.md`). Čítač chybí (stará / nová / kopírovaná konfigurace) → dopočet z nejvyššího použitého čísla
  (`Param. Reference Mgt.GetHighestUsedParamLineNo`: parametry, všechny odkazy, vlastníci, zbylá data parametru); při smazání
  parametru se číslo rezervuje (`ReserveParameterLineNo`), jinak by smazání posledního parametru staré konfigurace číslo uvolnilo.
- Odkazy na parametr sbírá jeden codeunit **63159 `Param. Reference Mgt. COEBS`** do temp tabulky 63165 a rozšíření přidávají své
  přes **`OnCollectParameterReferences(ConfigNo; ParamLineNo; IncludeVariantValues; var TempParamReference)`**
  (`TempParamReference.AddReference(...)`); stejná data slouží čítači, kontrole mazání i výpisu v reportu 63140. COZLK
  přidává převzaté parametry (hlavní i vnořená strana; zastaralá vazba — zboží řádku akce se změnilo — neblokuje).
  **`BlocksDeletion` rozšíření = přesně pravidlo runtime**, ne „záznam existuje“: COZLK blokuje jen propojení, které by
  za běhu předalo hodnotu (`IsNestedItemLine` + `GetLinkedNestedConfigNo` + **oba** parametry propojení existují).
  Propojení na smazaný parametr druhé strany (data před 66711) se v okně Převzít parametry vůbec neukáže — kdyby
  blokovalo, chyba by jmenovala něco, co uživatel nenajde (review 2026-10-09). **`Source Record ID` ukazuj na záznam
  se stránkou:** tabulka bez `LookupPageId` (COZLK `SL Act. Taken Param`) nemá v *Chybových zprávách* co otevřít →
  COZLK dává řádek SL akce (`LookupPageId` = `SL Action Lines Svc COEBS`), bez něj hlavní definici. Popis odkazu piš ve
  tvaru COEBS (`line %1 of sales line action condition %2 (…)`) — v chybě se řadí vedle sebe.
  ⚠️ **COEBS od PR 9695 (master 8d50acc, 2026-10-08) má `publisher` `Essence Business Solutions`** (dřív `Essence
  International s.r.o.`; app, appCZ, test, testCZ). Konzument se starým vydavatelem v dependency dostane `info AL1076`,
  kompilace projde (párování podle GUID). Při bumpu minima srovnej `publisher` a ověř ID balíčku nové verze na feedu
  (`<Publisher><Name>.<guid>`, `query2?q=<guid>`, 7.11 v `bc-al-build.md`).
  **COALU CNC** (`CNC Action Condition."Source Parameter Line No."`, `CNC Action Line."Profile From Parameter"`) má subscriber od
  větve `66845_CNCConditionTree` (cust-alumistr-bc); operandy CNC vzorců sbírá base sám (`Action Formula Line` bez filtru na typ zdroje).
- ⚠️ **Kopie konfigurace v rozšíření s vlastními odkazy na parametry = remap jako base `TryRemapParamLineNo`**, ne „není v mapě →
  nech". Kopie čísluje parametry znovu od 10000 bez mezer, takže odkaz na parametr smazaný před 66711 se v kopii chytí **jiného**
  parametru (zdroj 10000/30000 + odkaz 20000 → v kopii HEIGHT = 20000) a čítač kopie (vzniká u prvního parametru, data rozšíření se
  kopírují až v `OnAfterCopyConfiguration`) ho nezvedne → i budoucí parametry. 0 a záporná čísla (systémové parametry) beze změny,
  mimo mapu → 0. **Kde 0 mění význam, nenuluj:** CNC podmínka bez parametru je vždy splněná (`EvaluateCondition`), ve zdroji je
  s neexistujícím parametrem nesplněná → COALU kopii **zastaví chybou** se seznamem podmínek (rozhodnutí uživatele 2026-10-14);
  profil z parametru a operand vzorce se nulují (výsledek tisku stejný: statické číslo profilu, operand 0). Testy
  `CopyStopsOnCNCConditionWithMissingSourceParameter`, `CopyClearsCNCProfileAndOperandOfMissingParameter` (`CNC Data Repair Tests
  COALU`). Rekurzivní kopie větve v rámci konfigurace (`CopyCNCAction`) nad starým stromem se sdíleným potomkem / cyklem padala na
  duplicitním klíči mapy, resp. nekončila → guard „uzel už je v mapě → Error".
- Použitý parametr nejde smazat (Error s výčtem až 10 použití); vlastní podmínky a vzorce parametru neblokují, uložené hodnoty variant
  taky ne. Výběr více parametrů a „Delete All Records“ jdou přes `DeleteParameters` (odkazy mezi mazanými parametry neblokují).
  Smazání definice kontrolu přeskočí (`SetSkipReferenceCheck` na instanci, globální proměnná tabulky).
  COZLK ale **smazání vnořené definice zastaví**, když do ní jiná konfigurace předává hodnoty platným propojením (stejné
  pravidlo `TakenParamApplies` jako u parametru; subscriber `OnBeforeDeleteEvent` definice, jen `RunTrigger` – běží před
  `OnDelete`, který parametry smaže). Neplatná propojení odejdou s definicí v `OnAfterDeleteRelatedRecords`. (Rozhodnutí
  uživatele 2026-10-09, dřív tichý úklid; cust-zlomek-bc `66711_ParamLineNoReuse`.)
- `Variant Configuration COEBS` neměla klíč na `Configuration No.` → každé filtrování podle konfigurace = scan celé tabulky; přidán
  klíč `ConfigParamLineKey (Configuration No., Parameter Line No.)`.

## C17. Číslo z parametru pro všechny typy řádků akce prodejního řádku (67541)

> Task 67541 (2026-11-03, worktree `prod-ess-configurator-bc-67541`, větev `67541_NoFromParameter`, ověřeno na Zlomek BC-DEV2 PTE 28.0.99.3).

- Pole 50 `Item From Parameter` na `SL Action Line COEBS` (caption *Číslo z parametru*) platí pro všechny typy kromě poznámky. AL název zůstal (COZLK `Nested Config Mgt.`, API `itemFromParameterLineNumber`). Runtime (`CreateNewSalesLines` / `InitNewSalesLineFromAction`) byl na typu nezávislý už dřív. Kopie a reference parametru taky.
- Převod typ → tabulka + pole `No.` je `SL Action Line.GetNoSourceTable`, kontrola parametru `GetNoFromParameterError` (prázdný text = pasuje; Vyhledání v tabulce + tabulka + zdrojové pole `No.`), lookup `SetNoFromParameterFilters` / `LookupNoFromParameter`. Kontrola při aktivaci (`CheckSLLinesHaveItemNo`) navíc hlásí smazaný parametr a parametr změněný po navázání.
- ⚠️ **Stránka 63183 zobrazuje *Popis* / *Popis 2* přes výrazové proměnné** (`DescriptionExpressionText`, kvůli textovým vzorcům). Když tabulkový trigger popis změní (výběr parametru maže `No.` + popisy, změna typu, zadání čísla), stránka dál ukazuje starý text, dokud se řádek znovu nenačte. DB je správně. Každý page trigger, který mění číslo / parametr / typ, musí volat `UpdateDescriptionExpressions` (u 67541 `RefreshAfterNoSourceChange`). Chytil to až průchod v BC, testy ne.
- `TableRelation` pole 50 (jen parametry *Vyhledání v tabulce*) se vyhodnotí před `OnValidate` — ruční zadání čísla parametru jiného typu skončí standardní chybou relace, vlastní hláška „není typu Vyhledání v tabulce“ jen při aktivaci.
- Testovací data na Zlomek BC-DEV2 (ZLOMEK): zboží ZB00047, zdroj CLAUDE67541 (ZDR00001 nemá obecnou účto skupinu → standardní chyba BC na řádku zdroje), CONF0000074 / CONF0000075, objednávka O000022.

## C18. Konfigurační balíček (RapidStart) pro přenos definic konfigurátoru

> 2026-11-10, Alumistr BC-TEST (Alumistr SE), balíček `CLAUDE_CONFIGURATOR` (COEBS 28.0.41, COALU 28.0.81). Mechaniku apply
> jsem ověřil ve zdrojáku `Config. Package Management` / `Config. XML Exchange` (w1-28). Import do cíle zatím nikdo nezkoušel.

**Tabulky (26):** COEBS 63140–63142, 63144–63156 (včetně 63156 `Configurator Setup`), šablony 63158–63160, **63164** čítač
čísel parametrů (bez něj cíl znovu použije čísla smazaných parametrů, C15) a 63166 filtry Vyhledání. Z COALU CNC tabulky 52008–52012 (podmínky, řádky, pozice,
strany, makra). Pole tableextensions (COALU na řádcích BOM / Routing / SL) jdou automaticky se svou tabulkou.
**Záměrně vynecháno:**
- 63143 `Variant Configuration` – hodnoty variant jsou bez `Item Variant` a kusovníků ATEBS v cíli k ničemu.
- 63161 / 63162 – runtime sessions API.
- 63157 / 63163 / 63165 – mají `TableType = Temporary`.

`Configurator Setup` je v balíčku na přání uživatele. Je to jediný záznam a import ho v cíli přepíše, včetně číselných řad
konfigurací a šablon. Když má cíl vlastní řady, smaž před importem řádek 63156 z balíčku.

**Nastavení pro import:**
- Apply jede ve dvou průchodech. Nejdřív se do všech tabulek vloží záznamy jen s PK poli, pak se doplní ostatní pole a
  zavolá `Modify`.
- `Skip Table Triggers` znamená `RecRef.Insert()` / `Modify(false)`. Vypne tedy jen `OnInsert` / `OnModify`
  (číslování `Line No.`, čítač, kaskády), **`OnValidate` ne**.
- `OnValidate` se řídí příznakem `Validate Field` u každého pole (`EvaluateTextToFieldRef(…, Validate)`), u PK polí už v prvním
  průchodu. Přidání tabulky zapne *Zahrnout* i *Ověřit* u všech polí. Hromadná akce na vypnutí není: *Nastavit zahrnuto*
  validaci zase zapne.
- U konfigurátoru validace import rozbije (těla triggerů ověřena v COEBS master a76683f):
  - `No.` definice: `NoSeries.TestManual("Configuration Nos.")` a vymaže `No. Series`.
  - `Item No.` definice: `Item.Get` spadne, když zboží v cíli chybí, a `Item Description` přepíše popisem cílového zboží.
  - `Parameter Type`: při změně typu nuluje `Has Default Value`. Když typ není *Vyhledání v tabulce*, smaže filtry Vyhledání
    (`DeleteParameterFilters`).
  - `Line Type` textového vzorce přidělí nové `Expression No.` (C4).
  - Vazby potomků spustí `CheckChildLink` (C15).
  - K tomu `OnAfterValidateEvent` subscribery cizích appek.
  - `Status` definice žádný `OnValidate` nemá.
  Vlastní `OnValidate` má 86 z 453 polí balíčku, takže je vypnuté u **všech** polí.
- Bez validace nic nehlásí ani *Ověřit balíček*, protože relace se kontrolují jen u polí s `Validate Field`. Kmenová data proto
  musí v cíli existovat: zboží, pracovní centra / TNG, MJ, číselné řady a stejné verze COEBS / COALU. Pozor na
  `Lookup Param. Filter."Attribute ID"`: je to celočíselné ID atributu, v jiné databázi může patřit jinému atributu.
- Import páruje podle PK. Řádky, které v cíli přebývají (podmínky nebo řádky smazané ve zdroji), proto zůstanou.
  `Delete Recs Before Processing` by smazal **celou** cílovou tabulku (`RecRef.DeleteAll()`), nepoužívat.
- Při přidání tabulky s podmíněnou `TableRelation` se BC zeptá „Některá pole mají 2 nebo více souvisejících tabulek…“.
  Odpověz *Ne*, výběr relace slouží jen validaci.
- Nastavení cestuje se souborem `.rapidstart`. XML nese `ValidateField="1"` jen u validovaných polí a `SkipTableTriggers`
  u každé tabulky.
- Starší balíček `KONFIGURATOR` v Alumistr BC-TEST (24 tabulek) má validaci všude a triggery nepřeskakuje. Chybí mu CNC a
  obsahuje 63143 / 63156 / API sessions, k importu se nehodí.
- ⚠️ Akce *Pole* na řádku balíčku znovu volá `InitPackageFields`. Pole, která přibyla s updatem appky, se tak přidají se
  zapnutou validací. Před každým exportem zkontroluj, že *Počet polí pro ověření* je u všech řádků 0.
- Jak validaci rychle vypnout u stovek polí: 12.3 v `bc-al-workflow.md` (hromadné přepnutí checkboxu v gridu).
