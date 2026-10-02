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
> 5.x2b tracking na nabídce, 5.x8 Item Charge Assignment) a v `bc-al-posting.md`
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
- [C10. Kopie konfigurace — eventy pro zákaznická data řádků akcí](#c10-kopie-konfigurace--eventy-pro-zákaznická-data-řádků-akcí)
- [C11. API konfigurace varianty (task 66387) — ověření na Alumistr BC-TEST2](#c11-api-konfigurace-varianty-task-66387--ověření-na-alumistr-bc-test2)
- [C12. Strom podmínek parametru — zastaralé `Root Condition No.` (Zlomek)](#c12-strom-podmínek-parametru--zastaralé-root-condition-no-zlomek)

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
procedurou `GetParameterValues` (od větve `VariantConfigEngineUnify` jen obálka nad
`Variant Config. Engine COEBS.GetParameterValues`, chování stejné — viz C11) — projde jen řádky bufferu parametrů
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
i `Description 2` přepíšou z karty zboží (detail 3.6b v `bc-al-posting.md`).

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
Od větve `VariantConfigEngineUnify` (C11) je to obálka nad public **`Variant Config. Engine COEBS.RefreshAfterValueChange(var
TempBuffer)`** — změněnou hodnotu nejdřív ulož `Modify` (engine záznam znovu čte), vložený řádek potřebuje `Sort Order`
a Variant Code z `GetBufferVariantCode()`.

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
**Od COEBS 28.0.30 (PR 9577) kopii nepiš:** `Variant Config. Engine COEBS` (63162) je public a `CreateVariant` /
`FindOrCreateVariant` dělají Item Variant + hodnoty + text pro tisk + kusovník a postup; od `VariantConfigEngineUnify`
navíc `Effective Hidden` a `RefreshReusedVariant` u znovu použité varianty (C11, C13).

⚠️ **`Config. Condition Mgt. COEBS.ValidateParameterValue` u Table Lookup pustí cokoli** (COEBS 28.0.26): větev
volá `ValidateTableLookupValue`, výsledek zahodí a vrátí `true`; ta navíc filtruje jen základní `Source Table Filter`
+ atributy, **podmínkový** filtr (`GetConditionTableFilter`) ne. V dialogu to nevadí (lookup nabízí jen platné
kódy), ale hodnota dosazená z kódu (převzetí, import) projde i neexistující nebo mimo filtr. Obejití: vlastní
kontrola přes `RecordRef` + `SetView(GetConditionTableFilter(...))` + `Item Attr. Filter Mgt. COEBS.ApplyToRecRef(…,
GetConditionAttributeFilter(...))` + `SetRange` na zdrojové pole (vzor `Nested Cfg Runtime COZLK.TableLookupValueExists`).
Oprava patří do COEBS (vrátit výsledek + brát podmínkový filtr).
⚠️ **Každý z těch tří filtrů dej do vlastní filter group** (`SetView` ve 0, `RecRef.FilterGroup(10)` před `ApplyToRecRef`,
`FilterGroup(11)` před `SetRange` kódu). Ve stejné skupině drží pole jediný filtr: `SetRange` na zdrojové pole **přepíše**
filtr parametru na tomtéž poli (`WHERE(Code=CONST(X))` u Vyhledávání do MJ → projde jakýkoli existující kód) a u zboží
se zdrojovým polem `No.` i filtr atributů (`ApplyToRecRef` filtruje `Item."No."`). Stejnou chybu má `ValidateTableLookupValue`
v COEBS (`TrySetView` → `ApplyToRecRef` → `SetRange`, vše ve skupině 0) — až se v COEBS bude vracet výsledek, je potřeba ji
opravit taky. Chytil to až master build 28453 cust-zlomek-bc (2026-09-24, test `TakenLookupCodeMustPassTheFilterOfTheParameter`;
PR se tam netestují, 7.15 v `bc-al-build.md`). Obecné pravidlo 2.6c v `bc-al-data.md`.
Totéž má API 66387: `Config. API Session Mgt. COEBS.FillTableLookupValues` (povolené hodnoty) – `TrySetView` → `ApplyToRecRef` →
`TrySetRecRefFieldFilter` (filtr `value` z požadavku) ve skupině 0 → `value eq` přepíše filtr parametru na zdrojovém poli, bez filtru
`value` přepíše filtr atributů (`No.`) filtr tabulky na `No.`; stejně v dialogu `Table Values Lookup`, `Variant Config Params` a v
`Variant Config. Engine` (jediná hodnota). Uživatel 2026-09-24 rozhodl: oprava zůstává v tasku 65364 (větev
`65364_SLActionLineCopyEvent`, commit 599429a – kontrola už vrací výsledek, ale filter groups ještě ne), PR 66387 ji neobsahuje.
**Dokončeno 2026-09-29** (commit 739c732, větev pushnutá, PR zakládá uživatel): **`Item Attr. Filter Mgt.ApplyToRecRef` dává
filtr atributů sám do filter group 10** (`internal AttributeFilterGroup()`) a skupinu volajícího vrátí → opraveni všichni volající
najednou (lookup, auto-výběr jediné hodnoty, `GetSingleFilteredRecordValue`, kontrola hodnoty) a po merge i API 66387 (volá stejnou
proceduru); `ValidateTableLookupValue` dává hledanou hodnotu do skupiny 11. COZLK si 10/11 nastavuje sám, výsledek stejný.
⚠️ **Neplatný filtr tabulky: kontrola se musí chovat jako lookup.** `Table Values Lookup.SetTableAndField` filtr, který
`TrySetView` nepřijme, tiše vynechá a nabídne všechno; kontrola ho původně brala jako `false` → s novou chybou by neprošel
žádný ručně napsaný kód, i když ho lookup nabízí. Po review (2026-09-29) ho vynechá taky (`RecRef.Reset()`, kód jen musí
existovat), test `ValidateTableLookupValueLeavesOutFilterThatCannotBeApplied`. ⚠️ PR 9605 ho měl s filtrem na neexistující pole
a master build 28532 spadl — **`SetView` neznámé pole tiše ignoruje** (2.6c v `bc-al-data.md`), `TrySetView` selže jen na nesmyslné
syntaxi → test bere `'BADDATA'` (větev `65364_InvalidViewTestFix`, 2026-09-29, PR zakládá uživatel). Riziko neplatného filtru:
`Source Table Filter` se ukládá přes `FilterPageBuilder.GetView(…, false)` = **captiony** polí — kdyby je `SetView` v jiném jazyce
nepřečetl, filtr se ztratí potichu (bez chyby, víc nabízených hodnot); neověřeno.
**Zbývá jen API:** filtr `value`/`displayText` v `FillTableLookupValues` (`TrySetRecRefFieldFilter` ve skupině filtru tabulky) —
do 66387 nebo po merge obou větví. Popis PR 9577 (sekce *Pro review*) ho vede jako známé omezení „oprava v 65364", ale kód je jen
v 66387 → opraví ho větev, která se mergne druhá. `Param. Display Text Mgt.GetTableLookupDisplayText` beze změny (hledá přesnou vybranou
hodnotu, přepsání filtru tabulky na stejném poli výsledek nemění).

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
Záznam konfigurátoru má `Price Variant Code PMALU` prázdný a naopak. Pozor: EPB Pricing Matrix při výběru cenové varianty
(`Sales Price Var. Code PMEBS` OnValidate) zapíše tentýž kód i do **`Variant Code`** — cenová varianta je technicky `Item Variant`
s příznakem `Price Variant PMEBS`. Lookup „kusovník podle varianty" musí říct, kterou osu myslí — `Calc Cost Mgt. PMALU` původně
bral každý neprázdný kód jako cenovou variantu a hodil chybu *An alternative BOM for item %1 and price variant %2 was not found*
(padal tak i strom kusovníku / výpočet u vyráběné komponenty s obyčejnou variantou — COEBS umí `Variant Code` na řádku kusovníku).
Od PBI 66389 reaguje jen na variantu s příznakem `Price Variant PMEBS` **nebo** s kusovníkem pod `Price Variant Code PMALU`
(obojí, aby se chování cenové varianty nezměnilo ani u neoznačených kódů).

**Pořizovací cena na prodejním řádku (cust-alumistr-bc, PBI 66389, 2026-09-25, docs `66389_…md`):** `Cost Mgt. ALU` u výrobku
hledá nejdřív alternativní kusovník podle `Variant Code` (Default přednost, jen Certified); když ho nenajde, pokračuje beze změny
kusovníkem z karty + eventem `OnAfterSetProdBOMHeaderFilters…` (PMALU cenová varianta, jen při kusovníku na kartě). Na řádek zapisuje
base subscriber **`Sales Line.OnAfterGetUnitCost`** (ne triggery polí — `GetUnitCost` volá i `Location Code`, `Quantity`, `Return Reason
Code`, detail 3.6b v `bc-al-posting.md`) a **jen pro řádek, jehož varianta má vlastní kusovník** — `FixedCost × "Qty. per Unit of Measure"`,
nula nepřepisuje. Cenová varianta a řádek bez varianty zůstaly v PMALU (`Sales Line PMALU`: po `No.` a `Sales Price Var. Code`, zapisuje
i nulu, nenásobí MJ) — uživatel chtěl řešit jen výrobní variantu; sjednocení je otevřený bod v `docs/open-issues/59877_…md`.
Base čte `Alternative Prod. BOM ATEBS` na každém řádku s variantou → `tabledata … = R` v `Alumistr-READ ALU` + závislost base na ATEBS.
⚠️ **Stav kusovníku varianty určuje konfigurace:** `BOM Action Cond. Mgt.` bere status z podmínky kusovníku (`BOM Status`) nebo z
`Configuration Definition."Def. BOM Status"` a **výchozí je *Nový*** — necertifikovaný kusovník výpočet (ani výroba) nevezme, náklad pak
zůstane z karty. Registrace alternativního kusovníku proběhne v `SaveVariantConfiguration` dřív, než lookup vrátí variantu na řádek, takže
hook při `Validate("Variant Code")` kusovník už vidí. Historie: hook žil v PMALU (PR 8371, 2026-03) jen proto, že jediná appka se
závislostí na ATEBS byla Pricing Matrix — ne proto, že by náklad byl cenotvorba.

**Jednotková cena z kusovníku (Alumistr, 2026-09-25):** vlastní `Unit Price` pověšená na **`Sales Line.OnAfterUpdateUnitPrice`** přežije
všechny přepočty base i EPB Pricing Matrix (PMEBS po `UpdateUnitPrice` jen znovu validuje aktuální hodnotu `Validate("Unit Price")` bez
parametru). ⚠️ Konfigurátor ale na akcích prodejního řádku s vzorcem na *Jednotkovou cenu* volá `Validate("Unit Price", vzorec)` **přímo**
(`SL Action Cond. Mgt. COEBS` — `InitNewSalesLineFromAction` pro nové řádky, `ApplyCurrentLineOverrides` pro zdrojový řádek), mimo
`UpdateUnitPrice` → vyhraje, kdo byl poslední: vzorec při vytvoření/přepočtu akcí, vlastní cena po další změně množství / MJ. Když obojí
koexistuje, rozhodni pravidlo (vzorec má přednost = subscriber musí poznat řádek s cenovým vzorcem) — jinak se ceny „přetahují".

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

**Systémová oprava v PMEBS (PR 9573, release **28.0.6** = build 28454, 2026-09-24):** `ValidateAndUpdateUoM`
zboží bez maticové MJ hned vrátí `false` (žádná náhradní MJ, žádná `CreateRasterUOM`) a `FindMatrixUoM` hledá jen mezi MJ
s oběma osami ≠ 0 (filtr ve vlastní filter group — 2.6c v `bc-al-data.md`), takže fallback `< A, < B` už MJ 0/0 nesebere;
fallback na `Sales UoM` zůstal. Nová **public `Pricing Matrix Mgt. PMEBS.HasMatrixUnitOfMeasure(ItemNo)`** = stejná logika
jako lokální kopie v COALU. V cust-alumistr-bc (větev `PricingMatrixDependency_66358`) minimum EPB Pricing Matrix `28.0.6.0`
ve **všech čtyřech** `app.json` (COALU + PMALU, app + test) a zkratka z PR 9567 + lokální `HasMatrixUnitOfMeasure` v COALU
**odstraněny** — `Validate("Parameter A/B PMEBS")` u zboží bez maticové MJ teď v matici nic nedělá, výsledek stejný; COALU testy
z PR 9567 zůstaly a ověřují chování matice přes konfigurátor. Vedlejší efekt: první rastrovou MJ nového zboží už nezaloží
řádek dokladu (dřív u zboží bez `Sales UoM`), jen import matice / ruční Item UoM. A nový rastr z řádku (`CreateRasterUOM`
po prázdném výsledku hledání = maticové zboží bez `Sales UoM`) jen při zaokrouhlení **Equal** — bez toho by po vyřazení MJ 0/0
zaokrouhlení Dolů pod všemi rastry zakládalo rastry přesně pro zadaný rozměr (bez ceny); Up/Down bez nálezu MJ řádku nechají.
Pozor na obrácenou logiku testu: `…RoundingDownDoesNotCreateRaster` na původním masteru **projde** (vyhrála základní MJ 0/0 =
MJ řádku), padá až na mezistavu bez omezení na Equal — test proti regresi opravy, ne proti původní chybě. Dokumentace `prod-epb-pricingMatrix-bc/docs/66358 - …md`,
`cust-alumistr-bc/docs/66358_MJ-akcniho-radku-mimo-cenovou-matici.md`.

Diagnostika: page inspector na řádku prodeje (filtr „Parameter") — nenulové `Parameter A/B PMEBS` na řádku, kde čekáš jinou MJ,
= tahle cesta. Setup matice je na `Sales & Receivables Setup` (`UoM Rounding PMEBS`, `Parameter A/B Field No. PMEBS`,
`Use UoM Parameter Fields PMEBS`). (2026-09-23, PBI 66358 analýza; zdroje cust-alumistr-bc master aa320d2, prod-epb-pricingMatrix-bc
master, nasazeno COALU 28.0.20.3 / PMEBS 28.0.5.0 / COEBS 28.0.22.2.)

## C10. Kopie konfigurace — eventy pro zákaznická data řádků akcí

`Configuration Copy Mgt. COEBS` (63141) dává rozšířením k 28.0.26 jen dva eventy:

- **`OnAfterCopyBOMActionLine(var NewLine; var SourceLine)`** — po každém řádku akce kusovníku, v **obou** cestách
  (kopie celé konfigurace `CopyBOMActionLines` i kopie jedné akce v rámci konfigurace `CopyBOMActionLinesForCondition`),
  bez mapy parametrů. Vzor `Configurator Events COALU`.
- **`OnAfterCopyConfiguration(SourceConfigNo; NewConfigNo; var ParamLineNoMapping)`** — jen na konci kopie **celé**
  konfigurace; mapa parametrů ano, mapa podmínek a řádků akcí **ne** (`SLCondLineNoMapping` / `SLLineNoMapping` jsou
  lokální proměnné). Vzor `CNC Action Mgt. COALU`.
- ⚠️ **Řádky akcí prodejního řádku a postupu event nemají** a kopie jedné SL akce (`CopySLAction`) nevolá žádný.
  Zákaznická tabulka klíčovaná řádkem SL akce (`Configuration No.`, `Condition Line No.`, `Line No.` — COZLK
  `SL Act. Taken Param COZLK`, task 65364) se kopií tiše nepřenese. Rekonstruovat mapu řádků v `OnAfterCopyConfiguration`
  z pořadí (podmínky 10000, 20000… podle PK zdroje, řádky 10000… per podmínka) by šlo, ale opisuje interní číslování COEBS
  a na `CopySLAction` nepomůže → správně nový event v COEBS hned za `NewLine.Insert(true)` v `CopySLActionLines`
  i `CopySLActionLinesForCondition` (návrh `OnAfterCopySLActionLine(var NewLine; var SourceLine; var ParamLineNoMapping)`).
  Subscriber pozná kopii v rámci téže konfigurace podle `NewLine."Configuration No." = SourceLine."Configuration No."`
  (parametry beze změny), ne podle prázdné mapy.
- **Stav od větve `65364_SLActionLineCopyEvent`** (commit 599429a, čeká na PR): `OnAfterCopySLActionLine(var NewLine;
  SourceLine; var ParamLineNoMapping)` přidán, v obou cestách **před** kopií vzorců a textových vzorců řádku. `SourceLine`
  po review **bez `var`** — je to kurzor kopírovací smyčky (`SetRange` + `FindSet`/`Next`), subscriber by ho `SetRange`/`Find`
  rozbil; `OnAfterCopyBOMActionLine` ho má s `var` (starší, nechán kvůli kompatibilitě). ⚠️ **Vzorce nejsou u eventu zkopírované ani
  u `OnAfterCopyBOMActionLine` při kopii celé konfigurace** — `CopyBOMActionLines` ho volá hned po `Insert`, vzorce
  (`CopyBOMQtyFormulaLines`, `CopyActionTextFormulaLines`) jdou až dalším průchodem; jen `CopyBOMActionLinesForCondition`
  (kopie jedné BOM akce) ho volá až po vzorcích. Subscriber, který čte vzorce nového řádku, tedy v kopii celé konfigurace
  nic nenajde. (Code review 2026-09-29 — dokumentace větve tvrdila „už i s jeho vzorci".)
- **TODO v COZLK (cust-zlomek-bc) po vydání COEBS s větví `65364_SLActionLineCopyEvent`** — plný postup je v
  `prod-ess-configurator-bc/docs/65364 - Configurator - Event po kopii řádku SL akce a kontrola kódu Vyhledávání.md`,
  sekce *Navazující úpravy v COZLK*. Ve zkratce: (1) minimum `Essence Configurator` podle verze **na feedu** v
  `configuratorExtension/app` i `/test`; (2) subscriber `OnAfterCopySLActionLine` (`SourceLine` bez `var`) kopíruje
  `SL Act. Taken Param COZLK` — všechna 4 pole PK z `NewLine`, `Main Parameter Line No.` přes mapu jen při jiné
  `Configuration No.` (chybí v mapě → přeskočit), `Nested *` beze změny; (3) smazat `Nested Cfg Runtime
  COZLK.TableLookupValueExists` + její volání v `TryValidateParameterValue` (base to umí; rozdíl: neplatný filtr
  base vynechá); (4) testy kopie celé konfigurace (přečíslovaný parametr) a `CopySLAction`; (5) aktualizovat
  `docs/65364 - VYR_24 …(COZLK).md` (⚠️ o kopii a o nefunkční kontrole v 28.0.26).
  **Event i oprava kontroly Vyhledávání jsou v COEBS 28.0.28** (build 28533, master c45bcc2); 28.0.27 (build 28532) spadl
  a na feedu není → minimum `28.0.28.0`. Body (1)–(5) udělané na větvi `65364_CopyTakenParams` (review 2026-09-29).
- Mazání je v pořádku: `Configuration Definition.OnDelete` maže podmínky přes `DeleteAll(true)`, takže `OnAfterDeleteEvent`
  na `SL Action Condition/Line COEBS` běží per záznam a kaskáda v rozšíření (COZLK `Configurator Events`) data uklidí.
- ⚠️ **Smazání parametru odkazy v rozšířeních neuklidí a jeho `Line No.` se recykluje.** `Configuration Parameter COEBS.OnDelete`
  maže jen hodnoty, podmínky a vzorce parametru; `OnInsert` čísluje `FindLast + 10000` → nový parametr na konci konfigurace
  dostane `Line No.` smazaného posledního. Zákaznická tabulka s odkazem na `Parameter Line No.` (COZLK `SL Act. Taken Param` —
  hlavní i vnořený parametr) po smazání drží osiřelý odkaz, který se **tiše chytí nového parametru**. Kopie celé konfigurace
  ho zahodí sama (mapa parametrů ho nezná), kopie SL akce v rámci konfigurace ho zkopíruje. Úklid patří do subscriberu
  `OnAfterDeleteEvent` na `Configuration Parameter COEBS` (obě strany odkazu). (Code review 2026-09-29, cust-zlomek-bc.)

(2026-09-24, analýza plánu 65364 nad prod-ess-configurator-bc master 79fc306.)

## C11. API konfigurace varianty (task 66387) — ověření na Alumistr BC-TEST2

Skupina `essence/configurator/v2.0`, relace `configurationSessions` → `configurationSessionParameters` (PATCH `value`) →
`Microsoft.NAV.applyConfiguration`. Živý test přes REST 2026-09-24 (COEBS 28.0.22.3, testovací objednávka PO2500210):
relace s konceptem 0054 dala po 11 zadaných hodnotách **přesně stejné hodnoty všech ~90 parametrů** jako varianta
`COEBS0213` z dialogu (vzorce, výchozí hodnoty, podmínky) → znovupoužila ji a akce prodejního řádku daly stejné řádky jako
dialog (PO2500204). Nová varianta = kusovník `ItemNo-VariantCode` + postup jako z dialogu. REST gotchas (`$expand` podle
`EntitySetName`, nefiltrovatelné pole z proměnné stránky, prázdné tělo akce) v 11.7 `bc-al-integrations.md`.

**Přes oficiální MCP server BC** (konfigurace `Claude-66387` na BC-TEST2 — **nechat, uživatel ji chce ponechat**) to AI agent
(Sonnet, jen MCP nástroje) zvládl bez nápovědy: relace → změna SIRKA → apply, nová varianta `COEBS0123` jen se změněnou šířkou.
Detail nástrojů (názvy, `If-Match`, anglické hlášky) v M8 `bc-al-mcp-server.md`.

⚠️ **Chyba z akce kusovníku při apply není chyba API.** Alumistr aktivní definice **0039** (101000 ALUPLUS) má řádky akcí
kusovníku s `Item From Parameter` na nesmyslné parametry (`KOLEJ DOLE_KOOP` = Text „NE", `KOLEJ_DOLE_DELKA`, `TEXT_PRICKA`),
koncept 0054 na správné (`KOLEJ_DOLE_PROFIL`…) → apply padá *Pole Číslo z tabulky Řádek výrobního kusovníku obsahuje hodnotu
(NE)…* a dialog by padl stejně; z 0039 nikdy žádná varianta nevznikla. Vzor stop po přečíslování parametrů při kopii (66105).
Diagnostika přes API: `bomActionLines?$filter=configurationNumber eq '…' and itemFromParameterLineNumber ne 0` + mapa
`configurationParameters` (`parameterLineNumber` → `parameterCode`).

**Sjednocení dialogu s enginem (větev `VariantConfigEngineUnify` z masteru 339539c, 2026-10-02, čeká na PR):** ListPart 63147
už nemá vlastní kopii pravidel (dřív ~900 řádků a v enginu „keep both in step") — předává svůj temporary `Rec` jako buffer do
enginu 63162; ten je jediná implementace pro dialog i API. Co z toho plyne:
- **Předání page `Rec` (SourceTableTemporary, s filtrem `Effective Hidden = false` a klíčem Sort Order) přes `var` funguje** —
  engine nikde nemění filtry ani klíč volajícího: procházení přes `Copy(…, true)` + `Reset`, zápisy přes `Get`/`Insert`/
  `Modify`/`Delete` (filtry ignorují), `LoadParameters` maže přes kopii. Kurzor se hýbe → stránka si po volání sama nastaví
  pozici (`FindFirst` po načtení, první zobrazený bez hodnoty / `FindLast` po změně) a `CurrPage.Update(false)`.
  `OnAfterGetRecord` volá jen procedury nad kopií (`IsParameterEditable`, `GetValueAsText`, `GetParameterValues`) → kurzor drží.
- **Bug API do 28.0.30:** engine `Effective Hidden` nepočítal (dělal to jen ListPart) → varianty z API ho mají `false` a text pro
  tisk obsahuje parametry skryté podmínkou. Engine ho teď udržuje po každé změně, `CreateVariant` ho přepočítá a
  `RefreshReusedVariant` ho při znovupoužití zapíše i do uložených řádků (staré API varianty se tak opraví).
- **Změny chování dialogu:** neparsovatelné číslo = chyba *Value "abc" is not valid for parameter "Width".* (dřív tiché
  vymazání + smazání závislých parametrů — `ValidateParameterValue` vrací `false` jen u neparsovatelného čísla, rozsah / Option /
  Table Lookup hází chybu sám); výběr z lookupu se validuje jako napsaná hodnota (popis vybraného řádku drží overload
  `SetParameterValue(…; PickedDisplayText)`); Enter (skrytá akce `ConfirmValue`) uloží jen změněnou hodnotu na editovatelném
  řádku — dřív opakovaný Enter smazal ručně zadané závislé hodnoty.
- **Table Lookup nad polem mimo Code/Text:** lookup nabízí `Format()` hodnoty (lokalizované číslo, caption Option), `FldRef.SetRange(Text)`
  na takovém poli nesedí → `ValidateTableLookupValue` porovnává `UpperCase(Format(FldRef.Value()))` přes vyfiltrované řádky.
- Testy: TestPage dialogu přes `ModalPageHandler` a výběr řádku podle `"Parameter Name".Value()` (pořadí/kurzor neassertovat);
  neviditelnou akci (`Visible = false`, ShortcutKey) TestPage nevyvolá. Nový codeunit `Var. Config Dialog Tests COEBS` (63173).
- Follow-up: COZLK `Nested Variant Mgt.` (kopie find-or-create s TODO „nahradit public COEBS helperem") → engine; jejich kopie
  neukládá `Effective Hidden` a nevolá `UpdatePrintParameters`.

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
(3) upgrade / akce „přepočítat kořeny" pro existující data.

## C13. `Effective Hidden` na `Variant Configuration COEBS` JE persistovaný

> Přesunuto 2026-10-01 z `bc-al-objects.md` (sekce 5.x10); odkazy „viz 5.x10" míří sem.

Pole 14 `Effective Hidden` se plní v **temporary bufferu** dialogu
(`Variant Config Params COEBS.UpdateEffectiveHiddenStates` volá `Config. Condition Mgt.
COEBS.IsParameterHidden` nad `TempRec.Copy(Rec, true)`), takže na první pohled vypadá jako
čistě UI pomůcka. **Není** — `Variant Configuration COEBS.SaveVariantConfiguration` vytáhne
záznamy z toho bufferu přes `GetAllRecords` (dělá `Reset()`, takže vrací i skryté) a zapisuje je
`VariantConfigValue.TransferFields(TempConfigRecs)` + `Insert`, čímž se hodnota dostane do ostré
tabulky. Vlastní read-only zobrazení parametrů varianty (factbox, report) tedy může podmínkové
skrytí respektovat prostým filtrem `"Effective Hidden" = const(false)`, **bez přepočtu podmínek**.

- `IsParameterHidden` vrací true i pro **statický** `Configuration Parameter COEBS.Hidden`
  („Static hidden flag … takes priority"), takže snapshot pokrývá obě cesty skrytí.
- `Parameter Hidden` (FlowField ze statického flagu) si přesto nech ve filtru vedle něj:
  varianty uložené dřív, než konfigurátor snapshot plnil, mají `Effective Hidden = false`
  a statický Hidden by jinak prosákl.
- Pozor na obrácený omyl: „pole se plní jen v bufferu dialogu, takže je v uložených datech vždy
  false" je **nesprávný** závěr z pouhého grepu na název pole — rozhoduje `TransferFields`
  v ukládací proceduře, kde jméno pole nikde nefiguruje.

(2026-09-15, cust-zlomek-bc 65148 — code review factboxu parametrů konfigurátoru; ověřeno ve
zdrojáku prod-ess-configurator-bc na master.)

**Aktualizace 2026-10-02:** od větve `VariantConfigEngineUnify` počítá `Effective Hidden` **engine** (`Variant Config.
Engine COEBS`, local `UpdateEffectiveHiddenStates`), ListPart jen filtruje. Platí pro dialog i API; varianty z API
(28.0.30) ho mají `false`, dokud je někdo znovu nepoužije (`RefreshReusedVariant`) — detail C11.


## C14. „najdi nebo vytvoř variantu" je `local` v dialogu 63143 — z jiné appky ji nezavoláš

> Přesunuto 2026-10-01 z `bc-al-objects.md` (sekce 5.x12); odkazy „viz 5.x12" míří sem.
>
> ⚠️ **Od COEBS 28.0.30 (PR 9577) neplatí:** find-or-create je public v `Variant Config. Engine COEBS` (63162) —
> `LoadParameters` → `SetParameterValue` → `FindOrCreateVariant` (→ `ApplyToSalesLine`), a od větve `VariantConfigEngineUnify`
> je engine jediná implementace pravidel i pro dialog (`RefreshAfterValueChange` public, C11). Text níž popisuje stav
> do 28.0.29 a platí pro rozšíření s nižším minimem dependency.

Celý find-or-create mechanismus varianty (`FindExistingVariantWithSameValues`, `CompareParameterValues`,
`GenerateVariantCode`, ukládací část `SaveVariantConfiguration`) žije jako **`local procedure` na stránce**
`Variant Configuration COEBS` (63143), a `HasParameterValue()` na tabulce `Variant Configuration COEBS`
(63143) je **`internal`**. Rozšíření, které potřebuje variantu dohledat/založit z kódu (bez dialogu),
si tu logiku musí **zduplikovat** — page jde pustit jen `RunModal`, což v subscriberu při vytváření
prodejního řádku nechceš. Duplikát označ `TODO keep in sync` s ověřenou verzí COEBS (stejný vzor jako
`SL Act. Variant Lookup COZLK` u validity rules) a správné řešení — public helper v COEBS — nabídni.

Co je naopak z COZLK/COALU dosažitelné a nemusíš psát znovu:

- **`Config Param. Lookup COEBS` (63156)** — hotová výběrová page nad `Configuration Parameter COEBS`.
  Předfiltruj record (`SetRange("Configuration No.")`, `SetRange("Parameter Type")`), `SetTableView` +
  `LookupMode(true)` + `RunModal() = Action::LookupOK` + `GetRecord`. Base ji takhle používá v
  `SL Action Line COEBS."Item From Parameter"` OnLookup.
- **`Config. Condition Mgt. COEBS`** má procedury public (`GetCopiedValueFrom`, `IsParameterHidden`,
  `GetFilteredParameterValues`, `ValidateParameterValue`, …) — podmínky parametrů neřeš sám.
- **`Param. Display Text Mgt. COEBS` (63160)** — `GetOptionDisplayText` / `GetTableLookupDisplayText`
  pro dopočet `Display Text` u Option / Table Lookup hodnot.
- **`SL Action Line COEBS.HasPriceFormula()` / `HasDiscountFormula()` / `HasFormula()`** jsou public —
  hodí se, když v `OnBeforeModifyNewSalesLineFromAction` přepisuješ variantu a musíš rozhodnout, jestli
  po `Validate("Variant Code")` vrátit cenu z akce, nebo nechat vyhrát standardní cenotvorbu. Texty
  (`Description`, `Description 2`) vracej vždycky — validace varianty je přepíše z karty zboží (3.6b
  v `bc-al-posting.md`).

**Dialog pustí na další parametr, teprve když ten aktuální MÁ hodnotu.** `Variant Config Params COEBS`
(63147) staví seznam postupně: `AddNextEmptyParameter` → `FindLastFilledSortOrder` (bere jen parametry,
kde `HasParameterValue()`) a `HasUnfilledPreviousParameter` drží následující parametry read-only.
Rozšíření, které parametr „vyřeší" jinak než zadáním hodnoty (mapování na jiný parametr, převzetí odjinud),
proto **musí hodnotu stejně nastavit**, jinak se dialog zasekne. U `Integer`/`Decimal` stačí
`"Has Value" := true` (nula je platná hodnota), u `Text`/`Option`/`Table Lookup` musí být hodnota neprázdná —
neutrální hodnota tam neexistuje, takže tam nezbývá než nechat zadání na uživateli.
**Nula ale u číselného parametru s rozsahem neprojde** — dialog hodnotu při potvrzení kontroluje
(`SaveValueFromText` → `Config. Condition Mgt. COEBS.ValidateParameterValue` → `ValidateDecimalRange`),
takže u „Šířka 500–1900" musí startovní hodnota být default parametru, jinak **dolní mez rozsahu**
(`Configuration Parameter."Min. Decimal Value"` / `"Min. Integer Value"`; podmínkové override mezí
(`ApplyDecimalConditionOverrides`) jsou `local`, zvenku je nezjistíš).

Posun vpřed sám (`AddNextEmptyParameter`, `RefreshAfterValueChange`, `RebuildMissingParameters`) byl **`local`**;
od **COEBS 28.0.22.1** má page public obálku **`RefreshAfterExternalValueChange()`**, kterou rozšíření zavolá
po zápisu hodnoty do bufferu a dialog se přepočítá stejně, jako když hodnotu zadá uživatel. Bez ní zbývá
nechat uživatele hodnotu potvrdit (skrytá base akce `ConfirmValue` má `ShortcutKey = 'Return'`, takže Enter
ji vyvolá i bez změny hodnoty). Ostatní public procedury: `LoadParameters` (přenačte celý buffer od nuly —
zahodí rozdělané hodnoty), `GetAllRecords`, `GetParameterValues`, `ValidateAllValues`, `GenerateDescription`.
Defaultní hodnoty jde dopočítat mimo page — `Config. Condition Mgt. COEBS.HasDefaultDecimalValue` /
`HasDefaultIntegerValue` / `GetDefaultTextValue` / `GetDefaultCodeValue` jsou public a berou v potaz i podmínky.

Hodnoty parametrů putují v `Dictionary of [Code[20], Text]` klíčované `Parameter Code` a čísla v nich jsou
v **invariantním formátu** (`Format(x, 0, 9)`, tečka) — při zpětném parsování `Evaluate(…, 9)` po normalizaci
(`DelChr` mezer/NBSP, `,` → `.`), viz vzor `InitializeParameterCopiedValue` v `Variant Config Params COEBS`.

(2026-09-17, cust-zlomek-bc 65364 — přebírání hodnot parametrů z hlavní konfigurace do vnořené;
zdroje prod-ess-configurator-bc master, COEBS 28.0.22.0.)

