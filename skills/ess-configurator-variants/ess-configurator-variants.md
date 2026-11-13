# Essence Configurator — varianty, dialog konfigurace, engine a API

> Vyčleněno z `ess-configurator-notes.md` 2026-11-04 (soubor přesáhl 1000 řádků). Číslování sekcí C5, C11, C13, C14
> a C16 je původní, aby fungovaly odkazy „viz Cx" z ostatních souborů. Systémové parametry, vzorce, strom podmínek
> a diagnostika (C1–C4, C6, C12, C15, C17) zůstávají v `ess-configurator-notes.md`, napojení zákaznických rozšíření
> (C7–C10) je v `ess-configurator-extensions.md`.
> Načítej, když řešíš: identitu varianty (find-or-create, `FindExistingVariantWithSameValues`), dialog `Variant
> Configuration COEBS` (63143) a ListPart `Variant Config Params COEBS` (63147) — OK chce všechny parametry,
> `RefreshAfterExternalValueChange`, varianta založená mimo dialog = výrobní akce, rozdělení řádku a sleva, kontrola
> hodnoty Table Lookup a filter groups —, API konfigurace varianty (66387) a `Variant Config. Engine COEBS`,
> `Effective Hidden`, *Kopírovat hodnotu z* mezi typy a filtr Vyhledání hodnotou jiného parametru.
>
> **Obecná AL pravidla platí dál** — `bc-al-style`, `bc-al-data`, `bc-al-ui`, u netriviální funkčnosti `bc-al-autotests`.

## Obsah

- [C5. Identita varianty = množina hodnot parametrů](#c5-identita-varianty--množina-hodnot-parametrů)
- [C11. API konfigurace varianty (task 66387) — ověření na Alumistr BC-TEST2](#c11-api-konfigurace-varianty-task-66387--ověření-na-alumistr-bc-test2)
- [C13. `Effective Hidden` na `Variant Configuration COEBS` JE persistovaný](#c13-effective-hidden-na-variant-configuration-coebs-je-persistovaný)
- [C14. „najdi nebo vytvoř variantu" je `local` v dialogu 63143 — z jiné appky ji nezavoláš](#c14-najdi-nebo-vytvoř-variantu-je-local-v-dialogu-63143--z-jiné-appky-ji-nezavoláš)
- [C16. Kopírovat hodnotu z parametru jiného typu a filtr Vyhledání hodnotou parametru](#c16-kopírovat-hodnotu-z-parametru-jiného-typu-a-filtr-vyhledání-hodnotou-parametru)

---

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

**Rozdělení řádku (`Sales Line Split Mgt. COEBS.ProcessSplitLine`) re-pricuje obě linky** — nová linka vzniká řetězem
`Validate(… Variant Code / Quantity)`, originál `Validate(Quantity)`, `ApplyCurrentLineOverrides` validuje variantu nové
linky znovu. Každá validace spustí `ApplyDiscount` a `Line Discount %` spadne na slevu z ceníku (0), ruční cena zůstane
(5.x21 v `bc-al-blanket.md`). Od PBI 66392 (větev `66392_SplitLineDiscount`, 2026-10-06) si split slevu originálu
pamatuje a na konci ji vrací **na obě linky** — i přes CL slevu z konfigurace (rozhodnutí: ručně přepsaná sleva musí
přežít i split se stejnou konfigurací). Nový krok do splitu, který mění řádek přes `Validate`, dej **před** `RestoreLineDiscount`.
**Eventy splitu pro rozšíření (PBI 66431, větev `66431_SplitLineHook`, 2026-11-04):** getter `Variant Configuration COEBS.GetSplitSourceSalesLine`,
event stránky `OnAfterCheckSplit` (OK v split mode, po kontrole sledování, před uložením varianty; chyba nechá dialog otevřený)
a `Sales Line Split Mgt. COEBS.OnAfterProcessSplitLine` (konec, po vrácení ceny a slevy). Zlomek přes ně dělí Pozici; vzor
manuálně bindované instance z pageextension je v 4.21 `bc-al-ui.md`.
**PBI 66392 znovuotevřeno 2026-10-27 (sleva po změně množství):** ruční změna množství konfigurovaného nebo vytvořeného řádku
vrací slevu z doby před změnou (`Sales Line COEBS` `modify(Quantity)` → `Sales Line Config Mgt.KeepLineDiscountOnQuantityChange`,
jen `CurrFieldNo = Quantity`); vytvořené řádky při přepočtu kvůli samotnému množství převezmou slevy smazaných
(`RecalculateConfigCreatedLines(…; KeepLineDiscounts)`, akční sleva / vzorec vyhrává; platí i pro originální linku splitu). Vzor
v 5.x21 `bc-al-blanket.md`. Větev `66392_QuantityChangeKeepsLineDiscount` (worktree `prod-ess-configurator-bc-66392`).

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
syntaxi → test bere `'BADDATA'` (větev `65364_InvalidViewTestFix`, 2026-09-29, PR zakládá uživatel). `Source Table Filter` se
ukládá přes `FilterPageBuilder.GetView(…, false)` = **čísla polí**, ne captiony (`VERSION(1) SORTING(Field1) WHERE(Field1=1(AL-…))`,
karta parametru, 2026-10-20) → na jazyku relace nezávisí; dřívější obava „captiony v jiném jazyce" neplatí.
**API (dořešeno 2026-10-02, větev `VariantConfigEngineUnify`, čeká na PR):** filtr `value`/`displayText` v `FillTableLookupValues`
(`TrySetRecRefFieldFilter`) šel do skupiny filtru tabulky → filtr parametru na `No.` přepsal. Teď `RecRef.FilterGroup(11)` pro
`value` a `12` pro `displayText` (odvozeno z `AttributeFilterGroup() + 1/+2`), po nich `FilterGroup(0)`; test
`AllowedValuesOfATableLookupKeepTheTableFilterOfTheParameter`. Popis PR 9577 (sekce *Pro review*) ho vedl jako známé omezení. `Param. Display Text Mgt.GetTableLookupDisplayText` beze změny (hledá přesnou vybranou
hodnotu, přepsání filtru tabulky na stejném poli výsledek nemění).

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
  `SetParameterValue(…; PickedDisplayText)` **vždy, i prázdný** — „prázdný = dohledej podle hodnoty" by u neunikátního zdrojového
  pole (MJ zboží…) vzal popis jiného řádku; code review); Enter (skrytá akce `ConfirmValue`) uloží jen změněnou hodnotu na editovatelném
  řádku — dřív opakovaný Enter smazal ručně zadané závislé hodnoty. Veřejný parametr, který nová implementace nepotřebuje
  (`LoadParameters(…; NewTempVariantCode; …)`), **neignoruj potichu** (code review): ověř konzumenty (COEBS běží jen u Alumistru
  a Zlomka — `git grep` přes všechny větve obou rep) a když ho nikdo nevolá, změň podpis rovnou (rozhodnutí uživatele 2026-10-02,
  bez obsolete fáze); jinak nový overload + starý `[Obsolete]`, který nepodporovanou hodnotu odmítne chybou.
- **Table Lookup nad polem mimo Code/Text:** lookup nabízí `Format()` hodnoty (lokalizované číslo, caption Option), `FldRef.SetRange(Text)`
  na takovém poli nesedí → `ValidateTableLookupValue` číslo, které se `Evaluate` + `Format` vrátí na stejný text, filtruje typovaně
  (klíč), jinak / bez nálezu porovná `UpperCase(Format(FldRef.Value()))` přes vyfiltrované řádky (průchod u širokého lookupu je drahý).
- Testy: TestPage dialogu přes `ModalPageHandler` a výběr řádku podle `"Parameter Name".Value()` (pořadí/kurzor neassertovat);
  neviditelnou akci (`Visible = false`, ShortcutKey) TestPage nevyvolá. Nový codeunit `Var. Config Dialog Tests COEBS` (63173).
- **Master build 28617 (PR 9639, 2026-10-02) – 2 faily dialogových testů:** (1) filtr `Effective Hidden = false` z `LoadParameters`
  volaného z `OnOpenPage` dialogu 63143 otevření ListPartu nepřežije → znovu otevřená varianta ukázala parametr skrytý podmínkou
  (chyba už ze starého ListPartu, 4.14 v `bc-al-ui.md`); oprava = `ApplyParameterView()` i v `OnOpenPage` ListPartu. (2) test
  po `asserterror SetValue('abc')` pokračoval v téže TestPage a `First()` vrátilo `false` → chyba teď dojde z handleru na
  `asserterror RunModal()`, že hodnoty zůstanou, drží engine test (`bc-al-autotests.md`). Větev `VarConfigDialogTestsFix` z masteru eeba4b9.
  Ověřeno v lokálním kontejneru (7.23 v `bc-al-deploy.md`): master padá na týchž 2 testech jako CI, větev projde.
- Follow-up: COZLK `Nested Variant Mgt.` (kopie find-or-create s TODO „nahradit public COEBS helperem") → engine; jejich kopie
  neukládá `Effective Hidden` a nevolá `UpdatePrintParameters`.

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

## C16. Kopírovat hodnotu z parametru jiného typu a filtr Vyhledání hodnotou parametru

> Analýza 2026-10-20 nad master 635a1f1 (COEBS 28.0.37), nic neimplementováno. Plán: `prod-ess-configurator-bc/docs/Configurator -
> Filtr vyhledání hodnotou jiného parametru a kopie hodnoty mezi typy - plán.md`.

- **Typ zdroje u *Kopírovat hodnotu z* hlídá jen lookup.** Filtr `Parameter Type` = typ cíle + `Sort Order` < cíl nastavuje `OnLookup`
  pole `Copy Value From Param TrueNo` na kartě i v dialogu podmínky (dvě kopie, `Page.RunModal(…, Rec)` → filter group 0). Pole má
  `TableRelation` jen na konfiguraci a `OnValidate` jen `CalcFields` → ruční zadání jiného typu (i parametru za cílem) projde.
- **`Variant Config. Engine.InitializeParameterCopiedValue` polyká chyby převodu.** Převádí podle cílového typu a vrací `true`, i když
  číslo nepřečte → cíl zůstane prázdný, výchozí hodnota se nepoužije a u skrytého cíle se přeskočí `VerifyHiddenParameterHasValue`
  (chyba až na OK se jménem parametru, který uživatel nevidí). Vlastní normalizace maže jen obyčejnou mezeru, ne NBSP → lokalizovaná
  hodnota Vyhledání nad číselným polem `1 234,56` se nepřečte; `Cond. Comparison Mgt.TryParseDecimal` NBSP i čárku zvládne.
  Cíl Výběr / Vyhledání dostane `Value Code` **bez kontroly** (hodnoty výběru, tabulka, filtr) — platí i pro kopii stejného typu.
- **Efektivní filtr Vyhledání za běhu jde jedinou procedurou `GetConditionTableFilter`** (lookup dialogu, auto-výběr jediné hodnoty,
  `ValidateTableLookupValue`, API `FillTableLookupValues`, COZLK `Nested Cfg Runtime`). Novou osu filtru, která potřebuje hodnoty
  parametrů, jde „zapéct" tam (`SetView` → `FldRef.SetRange` → `GetView(false)`; escapování hodnoty řeší platforma) bez zásahu do
  konzumentů. Surový `Source Table Filter` čtou jen design-time místa (auto-doplnění *Výchozí hodnoty kódu*, výběr hodnot v podmínkách)
  a `Param. Display Text Mgt.GetTableLookupDisplayText` — ten s filtrem podle parametru může vzít popis z cizího záznamu (neunikátní
  zdrojové pole, `Item Variant.Code`). ⚠️ Vrátit z `GetConditionTableFilter` **neplatné** view nejde: konzumenti ho přes `TrySetView`
  tiše vynechají a nabídnou všechno; „nic nenabídnout" = platný filtr bez výsledku (`'%1&<>%1'`).
- `FilterPageBuilder` (okno *Filtr stránky*) je platformní dialog — vlastní tlačítko / lookup do něj přidat nejde. Zástupný text
  (`{PROFIL}`) v něm projde jen u Code/Text pole a jen do délky pole; u Decimal pole (`Unit Price`) nebo s 22 znaky v Code[20]
  okno po OK hlásí „Jeden nebo více filtrů je neplatný a bude ignorován“ a filtr zahodí.
- **Ověřeno 2026-10-20 na Alumistr BC-DEV** (COEBS 28.0.35, konfigurace A00005 / zboží CLAUDE-CFG / nabídka 1006, data ponechaná):
  Vyhledání nad `Unit Price` s jediným záznamem dá `1 337,44` s NBSP (znak 160) → kopie do Desetinného i Celé ← `2.5` zůstanou
  prázdné bez výchozí hodnoty, kopie do Výběru uloží neexistující kód; OK pak hlásí „Následující parametry musí být vyplněny“.
  Filtr typu v lookupu jde vymazat v menu sloupce (*Vymazat filtr*).

**Implementováno (filtr, ne kopie) v PBI 67238** (2026-10-21, větev `67217_DeleteConditionWithChildren`, necommitnuto; doc
`docs/67238 - Configurator - Filtr vyhledání v tabulce dle parametrů (COEBS).md`, CONFIGURATOR-DOCUMENTATION 5.4):
- Zadání chtělo **textový vzorec** jako hodnotu (ne operátor + parametr) a dva filtry: *Filtr zdrojové tabulky dle parametrů* +
  *Filtr atributů dle parametrů*. Výsledek vzorce = **filtr jako ručně napsaný** (`FldRef.SetFilter`), prázdný = nefiltruje,
  neplatný pro typ pole = nic (platný filtr `hodnota&<>hodnota` na tomtéž poli přes `FldRef.Value()` jako jokér). Rozhodnutí
  konzultanta (Josef Blaha).
- Řádky v tabulce 63166 s PK `Configuration No., Line No.` — `Line No.` **jedinečné v konfiguraci**, protože textový vzorec
  odkazuje `Source Type = Lookup Filter` (5) + `Source Line No.` = řádek filtru, `Field Type = Lookup Filter Value` (60).
  Kopie konfigurace tak může nechat `Line No.` beze změny. Nové `Source Type` hlídej ve všech `Copy*FormulaLines`
  (filtrují podle Source Type → izolované), v `Param. Reference Mgt.GetFormulaOwnerLineNo` (vlastník = parametr řádku filtru,
  jinak by vlastní filtr blokoval smazání vlastníka) a v `GetDependentParamLineNosInt`.
- Kontrola „pole už je filtrované" bez parsování textu: `RecRef.SetView(view)` + `FldRef.GetFilter() <> ''`.
- Vzorce filtru čtou `{KOD:ValueName}` **bez** filtrů dle parametrů (interní `EvaluateTextFormula(…; false)`), jinak by se
  filtry po přeházení pořadí parametrů sestavovaly navzájem donekonečna. Veřejné `EvaluateTextFormula` je s nimi.
- Desetinné hodnoty parametrů jsou ve slovníku invariantně (`12.5`) — pro pole Decimal se tečka mezi číslicemi převádí na
  oddělovač relace (`..` zůstává). Test `DecimalParameterValueFiltersADecimalField` zatím jen zkompilovaný (kontejner po pushi).
- Výchozí hodnota kódu parametru s filtry dle parametrů se použije, jen když ji filtr nabízí (`IsTableLookupValueAllowed`);
  jinak by zůstala stará hodnota z návrhu (auto-doplněná z pevného filtru) a přebila automatický výběr jediné hodnoty.
- Ověřeno na Alumistr BC-DEV (dev 28.0.37.67239, A00005 / nabídka 1006): duplicita v obou směrech, PROFIL → CENA a znovu
  po změně, filtr atributů `Barva = {BARVA_TXT:Value}` (Červený / Modrý / `Červený|Modrý`), odmítnutí hodnoty mimo filtr.
  Editor potřeboval `Commit()` před `RunModal` (4.25 v `bc-al-ui.md`).
