# Essence Configurator — poznámky z praxe

> Doménové poznámky k produktové appce **Essence Configurator** (publisher
> `Essence International s.r.o.`, app ID `45c32b8e-5eb2-49c6-8914-456284d2b7b8`,
> affix **COEBS**, repo `prod-ess-configurator-bc`, <https://dev.azure.com/essencebs/Projects/_git/prod-ess-configurator-bc>) a k zákaznickým
> rozšířením nad ní (`configuratorExtension` u Alumistra = affix **COALU**,
> u Zlomku **COZLK**).
>
> Načítej, když řešíš: konfigurační parametry a jejich podmínky, vzorce (číselné
> i textové), systémové parametry, dialog konfigurace varianty, akce kusovníku /
> postupu / prodejního řádku, identitu varianty.
>
> **Obecná AL pravidla platí dál** — `bc-al-style`, `bc-al-data`, `bc-al-ui`,
> u netriviální funkčnosti `bc-al-autotests`.
>
> Starší konfigurátorové poznatky žijí zatím i v `bc-al-objects.md`
> (5.x10 `Effective Hidden`, 5.x12 find-or-create varianty + public API dialogu,
> 5.x2b tracking na nabídce, 5.x8 Item Charge Assignment) a v `bc-al-data.md`
> (3.6b `Validate("No.")` → `Init()`, 5.x4 `Attached to Line No.`). Při dalším
> průchodu je sem přesuň; odkazy „viz X.Y" nechávej funkční.

## Obsah

- [C1. Systémové parametry](#c1-systémové-parametry)
- [C2. Kde se hodnota systémového parametru plní — a kde ne](#c2-kde-se-hodnota-systémového-parametru-plní--a-kde-ne)
- [C3. Číselné vzorce — `Action Formula Line COEBS`](#c3-číselné-vzorce--action-formula-line-coebs)
- [C4. Textové vzorce — `Text Formula Line COEBS`](#c4-textové-vzorce--text-formula-line-coebs)
- [C5. Identita varianty = množina hodnot parametrů](#c5-identita-varianty--množina-hodnot-parametrů)
- [C6. Diagnostika konfigurace v běžícím BC](#c6-diagnostika-konfigurace-v-běžícím-bc)
- [C7. Kusovník konfigurované varianty a pořizovací cena prodejního řádku (Alumistr)](#c7-kusovník-konfigurované-varianty-a-pořizovací-cena-prodejního-řádku-alumistr)
- [C8. Řádek kusovníku z konfigurátoru a pole EM Cutting Plan (Alumistr)](#c8-řádek-kusovníku-z-konfigurátoru-a-pole-em-cutting-plan-alumistr)
- [C9. MJ z akčního řádku přepíše Pricing Matrix přes Parametr A/B (Alumistr)](#c9-mj-z-akčního-řádku-přepíše-pricing-matrix-přes-parametr-ab-alumistr)

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
  Záporné Line No. musí být **unikátní napříč všemi appkami** — base drží −1,
  zvol si vlastní rozsah odvozený od svého object ID rozsahu.

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
vlastní procedurou `GetParameterValues` — projde jen řádky bufferu parametrů
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
i `Description 2` přepíšou z karty zboží (detail 3.6b v `bc-al-data.md`).

## C5. Identita varianty = množina hodnot parametrů

`Variant Configuration COEBS` (63143) — dialog `FindExistingVariantWithSameValues`
projde varianty zboží a `CompareParameterValues` porovná **všechny vyplněné**
hodnoty parametrů (per typ: Integer/Decimal i `Has Value`, Option/Table Lookup
`Value Code`, Text `Value Text`). Shoda = použije se existující varianta,
neshoda = vznikne nová.

**Důsledek pro návrh parametrů:** parametr, jehož hodnota závisí na kontextu
*prodejního řádku* (množství, datum, zákazník), do konfigurace **nepatří** —
vyrobil by novou variantu zboží pro každou hodnotu a při změně na řádku by se
stejně nepřepočítal (uložená varianta je sdílená mezi řádky). Takové veličiny
patří do vzorců **akce prodejního řádku**, kde se počítají při každém přepočtu.

Přepočet generovaných řádků při změně zdrojového řádku řeší
`Sales Line Config. Mgt. COEBS.CaptureSourceLineBeforeModify` + `RecalcAttachedLinesOnSourceLineModify`
(reaguje na změnu `No.` / `Variant Code` / `Quantity`) — **hodnoty parametrů varianty
ale nepřepočítává**, ty se jen čtou přes `LoadVariantParameterValues`.

Dialog kontext prodejního řádku **zná**: `SalesLineConfigMgt.HandleVariantCodeLookup`
volá `VariantConfigurationPage.SetSalesLineContext(DocType, DocNo, LineNo)`
(`SetSourceQuantity` naopak plní jen split mode ze `Sales Line Split Mgt. COEBS`).

**Rozšíření, které zapíše hodnotu parametru přímo do bufferu `Variant Config Params COEBS` (63147)**
(pageextension, ne zadání uživatelem), musí zavolat public **`RefreshAfterExternalValueChange()`** — obálka nad
`local RefreshAfterValueChange`, přepočítá závislé parametry a odkryje další (`AddNextEmptyParameter` jinak vidí
jen parametry s hodnotou a dialog se zasekne). Na feedu **od 28.0.24** (PR 9533 `QuoteTrackingVariantAlign`,
2026-09-18); 28.0.23 ji ještě nemá → minimum dependency `28.0.24.0`. Lokální buildy `28.0.22.1` / `28.0.22.2`
z `prod-ess-configurator-bc/app` ji mají, ale na feedu neexistují — minimum podle nich nenastavuj (7.11
v `bc-al-build.md`). Vzor: cust-zlomek-bc `Variant Cfg Params COZLK` (task 65364, 2026-09-23).

⚠️ **OK v dialogu `Variant Configuration COEBS` (63143) chce vyplněné VŠECHNY aktivní parametry** —
`OnQueryClosePage` → `SaveVariantConfiguration` → `ValidateAllParametersHaveValues` → `Variant Config Params
COEBS.ValidateAllValues` (vše kromě parametrů vypnutých podmínkou) → `Error('Following parameters must be filled: …')`.
Žádný event ani `IsHandled` tam není (COEBS 28.0.26), takže rozšíření **nedonutí dialog uložit neúplnou
konfiguraci**, ani když některé parametry dostanou hodnotu jinde (převzetí z hlavní konfigurace, vzorec). Featuru,
která část parametrů plní mimo dialog, proto neveď přes OK dialogu — nastavení dej na vlastní akci / stránku a
variantu ať runtime staví sám (vzor COZLK 65364: akce Převzít parametry na `SL Action Lines COEBS`, varianta na řádku
akce volitelná, `Nested Cfg Runtime COZLK` bere konfiguraci z aktivní definice zboží). Dosazovat „zástupné" hodnoty
jen kvůli OK nejde u Výběru / Vyhledávání / Textu bez výchozí hodnoty a navíc vyrobí variantu s nahodilými hodnotami.

**Varianta založená mimo dialog = zopakuj i výrobní akce.** `SaveVariantConfiguration` po zápisu `Item Variant` a
hodnot parametrů u **nové** varianty volá `BOM Action Cond. Mgt. COEBS.ExecuteBOMActions` a `Routing Action Cond Mgt.
COEBS.ExecuteRoutingActions` (obojí public, v balíčku i s ATEBS; kusovník `ItemNo-VariantCode` + registrace
v Alternative BOM/Routing, každé hlásí `Message`), znovu použitá varianta je nevolá. Kopie find-or-create logiky
v rozšíření (COZLK `Nested Variant Mgt.`) bez nich dá prodejnímu řádku variantu bez kusovníku a postupu — a další
použití téže varianty to už nenapraví. Chytil code review 2026-09-23 (cust-zlomek-bc 65364).

⚠️ **`Config. Condition Mgt. COEBS.ValidateParameterValue` u Table Lookup pustí cokoli** (COEBS 28.0.26): větev
volá `ValidateTableLookupValue`, výsledek zahodí a vrátí `true`; ta navíc filtruje jen základní `Source Table Filter`
+ atributy, **podmínkový** filtr (`GetConditionTableFilter`) ne. V dialogu to nevadí (lookup nabízí jen platné
kódy), ale hodnota dosazená z kódu (převzetí, import) projde i neexistující nebo mimo filtr. Obejití: vlastní
kontrola přes `RecordRef` + `SetView(GetConditionTableFilter(...))` + `Item Attr. Filter Mgt. COEBS.ApplyToRecRef(…,
GetConditionAttributeFilter(...))` + `SetRange` na zdrojové pole (vzor `Nested Cfg Runtime COZLK.TableLookupValueExists`).
Oprava patří do COEBS (vrátit výsledek + brát podmínkový filtr).

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

**Sort Order ≠ Line No.** V lookupu operandu vidíš u systémových parametrů sloupec
*Pořadí řazení* se zápornými čísly (`QUANTITY` −10000, CNC `X1` −20000 … `Z` −19970) —
to je jen řazení nad běžné parametry. Identifikátor je `Line No.` (−1, −51990…−51993).

⚠️ **Ověř nasazenou verzi appky, než porovnáš chování se zdrojákem** (page 2500,
nebo `get_installed_apps` přes d365bc-admin MCP — je to spolehlivější než grid
v prohlížeči). CI bumpuje build číslo, takže verze v prostředí bývá vyšší než
`version` v `app.json` na masteru; podstatné je, jestli v mezidobí někdo nenasadil
lokální build. Detail 5.x11 v `bc-al-objects.md`.

## C7. Kusovník konfigurované varianty a pořizovací cena prodejního řádku (Alumistr)

Konfigurátor po vytvoření varianty registruje její kusovník do **`Alternative Prod. BOM ATEBS`** (EM Alternative
BOM and Routing) přes `BOM Action Cond. Mgt. COEBS.RegisterAlternativeBOM`: `Item No.` + **`Variant Code`** +
`Location Code` prázdný + `Production BOM No.` + `Default = true`. Na kartě zboží tedy `Production BOM No.` typicky
zůstává prázdné — kdo hledá kusovník varianty jen přes kartu zboží, nenajde nic.

⚠️ **Táž tabulka nese u Alumistra dvě nezávislé osy:** base `Variant Code` (konfigurátor, varianta zboží) a vlastní pole
**`Price Variant Code PMALU`** (Pricing Matrix, cenová varianta ze `Sales Price Var. Code PMEBS` / `Price Worksheet Line`).
Záznam konfigurátoru má `Price Variant Code PMALU` prázdný a naopak. Lookup „kusovník podle varianty" musí říct, kterou
osu myslí — `Calc Cost Mgt. PMALU` původně bral každý neprázdný kód jako cenovou variantu a hodil chybu *An alternative
BOM for item %1 and price variant %2 was not found*, takže kód konfigurované varianty do něj poslat nešlo. Od 2026-09-22
reaguje jen na varianty s `Item Variant."Price Variant PMEBS"`.

**Pořizovací cena na prodejním řádku (`Cost Mgt. ALU.UpdateSalesLineUnitCost`, cust-alumistr-bc, větev
`SalesLineUnitCostVariantBOM`, 2026-09-22):** pořadí hledání kusovníku = alternativní kusovník podle `Variant Code`
(Default přednost, jen Certified) → event `OnAfterSetProdBOMHeaderFilters…` (PMALU cenová varianta) → `Production BOM No.`
z karty zboží. Výsledek `FixedCost × "Qty. per Unit of Measure"` jde do `Validate("Unit Cost (LCY)")`; **nula standardní
náklad nepřepisuje** (původní PMALU kód validoval i nulu a mazal tak náklad z karty u každého zboží bez fixní ceny).
Spouští se z `Sales Line ALU` `modify("No.") / ("Variant Code") / ("Unit of Measure Code") OnAfterValidate` — base triggery
všech tří polí volají `GetUnitCost()` a `Unit Cost (LCY)` resetují z karty zboží, takže hook musí běžet **až po nich**
(`OnAfterValidate` v tableextension to splňuje, `Validate("Variant Code")` konfigurátoru ho vyvolá taky). Podmínka výpočtu
z kusovníku: zboží má `Replenishment System = Prod. Order`; u nákupního zboží se bere `Unit Cost  - Fixed ALU`.
Historie: hook žil v PMALU (PR 8371, 2026-03) jen proto, že jediná appka se závislostí na ATEBS byla Pricing Matrix —
ne proto, že by náklad byl cenotvorba.

## C8. Řádek kusovníku z konfigurátoru a pole EM Cutting Plan (Alumistr)

`Configurator Events COALU.OnBeforeInsertProdBOMLine` přenáší z akčního řádku kusovníku `Qty. of Pcs.` a `Qty. per Piece`
do polí EM Cutting Plan na `Production BOM Line` (tableext `Production BOM Line CUEBS`, repo `prod-em-cuttingPlan-bc`).
Oba jejich `OnValidate` přepočítávají `Quantity per`, **každý jinak**:

- `Qty. of Pcs. CUEBS` → prostý součin: při `Qty. per Unit of Measure = 1` `Quantity per := Qty. per Piece × Qty. of Pcs.`,
  jinak `Quantity per := Qty. of Pcs.`; prázdné `Qty. per Piece` nejdřív nastaví na 1.
- `Qty. per Piece CUEBS` → přes délku: `Quantity per := Length / GetLengthTypeConstant(...)`. Od **EM Cutting Plan 28.0.4**
  (PR 9512, 2026-09-16) vrací `GetLengthTypeConstant(…, false)` u MJ **bez *Length Type*** (m², ks) nulu a trigger se
  **celý přeskočí** — dřív to u takové MJ spadlo na chybě.

⇒ **`Qty. of Pcs.` validuj jako poslední.** V opačném pořadí zůstane `Quantity per` na mezivýsledku prvního triggeru
(`1 × Qty. of Pcs.`), ne na součinu — Qty. per Piece 2,5 × 4 ks dá 4 místo 10. U MJ s typem délky vyjdou obě pořadí stejně.
Nulu nevaliduj (smazala by `Quantity per` místo výchozí 1). Dependency minimum `EM Cutting Plan 28.0.4.0` v app i test
`app.json`, test `QtyOfPcsAndQtyPerPieceGiveQuantityPerWithoutLengthType` (`Config. Ext. Tests ALU`; testovací zboží je
v PCS bez typu délky, takže starý kód spolehlivě chytí). Zdroj: cust-alumistr-bc, větev `ConfiguratorFormulaCancel`
(2026-09-22); úprava vznikla 2026-09-16 při analýze na BC-TEST2, kde běžel lokální build Cutting Planu (C6).

## C9. MJ z akčního řádku přepíše Pricing Matrix přes Parametr A/B (Alumistr)

Base `InitNewSalesLineFromAction` MJ z `SL Action Line."Unit of Measure Code"` validuje správně (`ApplyItemSpecificFields`,
až po `Validate("No.")`). Když na podřízeném řádku skončí jiná MJ, hledej v **`OnBeforeModifyNewSalesLineFromAction`**:
`Configurator Events COALU` (od PR 9480, 2026-09-14) přenáší na **každý** vytvořený řádek `Parameter A/B COALU` akčního
řádku (statika nebo vzorec) přes `Validate("Parameter A/B PMEBS")` → `Sales Line PMEBS.ValidateParametersPMEBS` →
`Pricing Matrix Mgt. PMEBS.ValidateAndUpdateUoM` → **`Validate("Unit of Measure Code", <matricová MJ>)`**.

⚠️ **Pricing Matrix nezná „nematicové" zboží.** S `Module Enabled PMEBS` projde enginem každé zboží s oběma parametry ≠ 0.
Rounding **Up** (`FindUoMForRoundingUp`) po neúspěchu „≥ A a ≥ B" padá do větve „největší pod požadavkem" (`< A`, `< B`) — a tu
splní **každá MJ bez os (0/0)**. Při shodě vyhraje první podle PK (`Item No., Code`) → abecedně první MJ zboží. Alumistr BC-TEST2
(konfigurace 0066, PO2500209): sklo `GL-12040000-04-TR` má základní/prodejní MJ `M2`, MJ `KS` i `M2` s nulovou šířkou/výškou
(osy = `Width`/`Height`, pole 7301/7302), vzorce Parametr A/B = rozměr skla → řádek skončil `KS` s A = 1000, B = 750.
Kdyby žádná MJ nevyhověla, `ValidateAndUpdateUoM` by zboží **založil rastrovou MJ** `B/A` (`CreateRasterUOM`).

**Oprava v COALU (větev `SLActionLineUoM_66358`, 2026-09-23):** `ValidateParametersKeepingTexts` (sdílí ji akční i aktuální
řádek) validuje A/B jen u zboží, které má aspoň jednu MJ s oběma osami ≠ 0 (`HasMatrixUnitOfMeasure` přes veřejné
`Features PMEBS.GetParameterA/BFieldNo` + `Pricing Matrix Mgt. PMEBS.AxisValue`); ostatnímu zboží A/B jen přiřadí a MJ nechá.
Pravidlo „akční řádek má vyplněnou MJ" nejde použít — `SL Action Line."No."` OnValidate MJ doplňuje sám z karty zboží.
Systémová oprava fallbacku patří do PMEBS (samostatný WI).

Diagnostika: page inspector na řádku prodeje (filtr „Parameter") — nenulové `Parameter A/B PMEBS` na řádku, kde čekáš jinou MJ,
= tahle cesta. Setup matice je na `Sales & Receivables Setup` (`UoM Rounding PMEBS`, `Parameter A/B Field No. PMEBS`,
`Use UoM Parameter Fields PMEBS`). (2026-09-23, PBI 66358 analýza; zdroje cust-alumistr-bc master aa320d2, prod-epb-pricingMatrix-bc
master, nasazeno COALU 28.0.20.3 / PMEBS 28.0.5.0 / COEBS 28.0.22.2.)
