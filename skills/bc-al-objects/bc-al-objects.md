# BC/AL poznámky — Specifické objekty & API

> Část rozděleného `bc-al-notes.md` (rozsekáno 2026-06-23; archiv: `bc-al-notes.archived-2026-06-23.md`).
> Shopify Connector (5.y2) a SaaS/Cloud gotchas (sekce 11) vyčleněny 2026-09-08 do `bc-al-integrations.md`.
> Načítej, když řešíš: No. Series, Upgrade Tag, All Profile, NMEBS vazba SO↔VZ,
> Unix timestamp, atributy zboží, DateFormula, CaptionClass/Translation Helper, CZ↔EN terminologie, CZZ zálohy, Attached to Line No. /
> parent↔child řádky, VerifyOnInventory, Auto Format / částky v textu, Retention Policy pro vlastní logy (5.x24).
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".
> **Essence Configurator** má od 2026-09-21 vlastní soubor `ess-configurator-notes.md` (parametry, vzorce, systémové parametry, varianty) — sekce 5.x10 a 5.x12 tam přesunuty 2026-10-01 jako C13 / C14; 5.x8 (Item Charge Assignment) je obecné BC a zůstává tady.
> **Item Tracking** (5.x, 5.x2, 5.x2b, 5.x15) má od 2026-10-07 vlastní soubor `bc-al-tracking.md` (skill `bc-al-tracking`).
> **Hromadné objednávky HNO/HPO, Requisition Line a přepočet ceny bez ceníku** (5.x5, 5.x9, 5.x21) mají od 2026-10-19 vlastní soubor
> `bc-al-blanket.md` (skill `bc-al-blanket`).

Obsahuje:
- **5.** Specifické objekty a API (bez 5.y2 Shopify → `bc-al-integrations.md`)

## 5. Specifické objekty a API

### 5.1 `All Profile` — vytvoření záznamu

- Při `Scope::Tenant` musí být `App ID` **prázdný GUID** (výchozí po `Init()`)
- Nastavení `AllProfile."App ID" := AppInfo.Id()` způsobí chybu při instalaci
- `Scope::System` vyžaduje vyplněné `App ID`

### 5.2 Upgrade Tag pattern

- Upgrade tag definice v samostatné codeunitě s EventSubscriberem na
  `OnGetPerCompanyUpgradeTags`
- V Upgrade codeunitě: nejdřív `HasUpgradeTag` → pokud false, provést upgrade
  → na konci `SetUpgradeTag`
- V Install codeunitě: v `CompanyInitialize` subscriber volat
  `UpgradeTag.SetAllUpgradeTags()`

### 5.3 `No. Series` codeunit — `GetNextNo` vs `PeekNextNo`

`Codeunit "No. Series"` (Business Foundation, ID 310) má dvě metody pro
získání čísla z série, které se chovají rozdílně vůči counter advance.
**Volba mezi nimi rozbíjí konzistenci s posting flow** — nedá se naslepo
zaměnit, ohlásí se to off-by-one chybou typu *"Číslo dokladu musí být rovno
'X+1'... Současná hodnota je 'X'."*

#### `GetNextNo(seriesCode, usageDate)` — vrátí + posune

- Vrátí příští dostupné číslo a **rovnou posune** "Last No. Used" v sérii.
- Po volání už ten number patří **tobě** — nikdo jiný ho nedostane.
- Žádný další subsystém ho už nemá kde "konzumovat".

**Použít, když:** zapisuješ číslo na záznam a sám ho reálně používáš jako
finální (např. `ItemJnlLine."Document No." := GetNextNo(...)` a pak voláš
`Item Jnl.-Post Line.RunWithCheck(ItemJnlLine)` — direct posting bez
průchodu deníkovou tabulkou).

#### `PeekNextNo(seriesCode, usageDate)` — vrátí bez posunu

- Vrátí příští dostupné číslo, **counter neposune**.
- Volání je idempotentní — po něm je série ve stejném stavu.
- Předpokládá, že **posun udělá někdo jinej** (typicky downstream posting
  codeunit při zaúčtování dokumentu).

**Použít, když:** předvyplňuješ Doc No. na záznamu, který se pak musí
zaúčtovat přes batch posting codeunit (`Item Jnl.-Post` 241, `Gen. Jnl.-Post`
231…). Ten codeunit si sérii konzumuje sám během postingu — pokud bys ji
posunul ty (`GetNextNo`), posting pak vidí Doc No. < current next a hodí
chybu *"Číslo dokladu musí být rovno..."*.

#### Pravidlo palce

| Posting cesta                                                    | Doc No. zdroj           |
| ---------------------------------------------------------------- | ----------------------- |
| `Item Jnl.-Post Line.RunWithCheck(ItemJnlLine)` — direct, bez Insert | `GetNextNo`            |
| `ItemJnlLine.Insert(true)` + `Codeunit.Run(Codeunit::"Item Jnl.-Post", ItemJnlLine)` | `PeekNextNo` |
| Manuální post z deníku (uživatel klikne Post)                    | `PeekNextNo` (ekvivalent) |
| Plain Insert do tabulky bez postingu (audit log apod.)           | `GetNextNo`            |

#### Praktické debug-flag

Když ti během postingu vyletí chyba *"Číslo dokladu musí být rovno
'5143250011'... Současná hodnota je '5143250010'."* a ty si jseš jistej,
že jsi sérii volal jenom jednou — **používáš `GetNextNo` tam, kde patří
`PeekNextNo`**. Nesnaž se odečítat 1 ručně, prostě přepni metodu.

#### Caller přes batch flow — typické volání

```al
local procedure DetermineDocumentNo(ItemJnlBatch: Record "Item Journal Batch"): Code[20]
var
    NoSeries: Codeunit "No. Series";
    HHTLbl: Label 'HHT-%1', Locked = true, Comment = '%1 - user id';
begin
    if ItemJnlBatch."No. Series" <> '' then
        exit(NoSeries.PeekNextNo(ItemJnlBatch."No. Series", WorkDate()));
    exit(CopyStr(StrSubstNo(HHTLbl, UserId()), 1, 20));
end;
```

Fallback (no series defined) je `HHT-{UserId}` — informativní, žádná
counter logika.

#### Codeunit.Run("Item Jnl.-Post") vyžaduje napozicovaný Rec

Posting codeunit `Item Jnl.-Post` (241) si na začátku dělá `ItemJnlLine.Copy(Rec)`
a hned čte field values přímo (nikoli přes filtry):

```al
ItemJnlTemplate.Get(ItemJnlLine."Journal Template Name");
TempJnlBatchName := ItemJnlLine."Journal Batch Name";
```

Když mu předáš Rec se SetRange filtry, ale neudělal jsi `FindFirst`/`FindSet`
před `Codeunit.Run`, oba fieldy budou prázdné a `Get('')` rovnou padne
chybou *"Šablona deníku zboží neexistuje. Identifikační pole a hodnoty:
Název=''."*. Vždy napozicuj Rec před voláním:

```al
ItemJnlLine.SetRange("Journal Template Name", Setup."Pre-Receipt Item Jnl.Template");
ItemJnlLine.SetRange("Journal Batch Name", Setup."Pre-Receipt Item Jnl.Batch");
if ItemJnlLine.FindFirst() then
    Codeunit.Run(Codeunit::"Item Jnl.-Post", ItemJnlLine);
```

### 5.4 Test `Document No.` proti číselné řadě žije JEN v `*-Post Batch`

Validaci, že `Document No.` na řádku deníku odpovídá číselné řadě (a jejímu
**období** podle zúčtovacího data), dělá standard **výhradně** v
`*-Post Batch` codeunitě (`Job Jnl.-Post Batch` 1013, `Gen. Jnl.-Post Batch`
13, `Item Jnl.-Post Batch` 23 …):

```al
if (Batch."No. Series" <> '') and ("Document No." <> LastDocNo) then
    TestField("Document No.", NoSeriesBatch.GetNextNo(Batch."No. Series", "Posting Date"));
```

**`*-Check Line` ani `*-Post Line` ji NEvolají.** Ověřeno ve zdroji:
`Job Jnl.-Check Line` (1011) testuje Job/Task/No./Posting Date/Quantity,
dimenze, stav projektu, množství, bin… ale **ne** číslo dokladu. Důsledek:
když si stavíš vlastní pre-posting kontrolu nad `*-Check Line` nebo
per-řádek `*-Post Line.RunWithCheck`, **číslo dokladu ti propadne** a chyba
*„Číslo dokladu musí být rovno 'X'…"* vyskočí až při ostrém účtování. Tu
kontrolu musíš doplnit ručně.

#### Nedestruktivní kontrola čísla dokladu — `No. Series - Batch` + simulation mode

Pro **read-only** ověření (kontrola před účtováním, error-collect, náhled)
replikuj logiku `*-Post Batch`, ale s `No. Series - Batch` (codeunit 308) v
**simulation módu** — řada se posouvá jen v paměti a na DB se **nikdy**
nezapíše:

```al
NoSeriesBatch.SetSimulationMode();   // pojistka: SaveState je no-op
repeat
    if (not Line.EmptyLine()) and (Line."Document No." <> LastDocNo) then begin
        ExpectedNo := NoSeriesBatch.GetNextNo(Batch."No. Series", Line."Posting Date", true); // HideErrors
        if (ExpectedNo <> '') and (Line."Document No." <> ExpectedNo) then
            LogError(Line, ExpectedNo);   // sbírej místo TestField (které hodí Error a zastaví)
    end;
    if not Line.EmptyLine() then
        LastDocNo := Line."Document No.";
until Line.Next() = 0;
```

Klíčové detaily, ať to odpovídá ostrému postu:

- **`No. Series - Batch` (308), ne `No. Series` (310).** 308 drží stav
  **in-memory per No. Series Line** (období), takže mix dat 2025/2026 v jedné
  dávce dostane správná čísla z příslušného období. 310 by šel pokaždé na DB.
- **`SetSimulationMode()` + nikdy `SaveState()`** = zaručeně nedestruktivní.
  308 má `InherentPermissions = X` → **netřeba** ho dávat do permission setu.
- **`GetNextNo` jen pro NOVÉ `Document No.`** (≠ předchozí řádek) — pattern
  `LastDocNo` z base app. Víc řádků na jeden doklad je tak legitimní.
- **Stejný filtr a pořadí jako `*-Post Batch`** (`Copy` + `SetRange`
  Template/Batch + `SetFilter Quantity <> 0`) → kontrola = přesná predikce
  ostrého postu.
- **`HideErrorsAndWarnings := true`** v `GetNextNo` → když řada nepokrývá
  období, vrátí `''` místo erroru; ošetři jako samostatný nález, ať kontrola
  nespadne.

Reálně použito v `cust-mxb-bc` → `Check Job Jnl. Lines MXB.CheckDocumentNos`
(deník projektů, task 63889).

#### Generátor řádků deníku (suggest report) → `PeekNextNo` per `Posting Date`

Když report/codeunit **navrhuje** řádky do deníku a přiřazuje `Document No.`,
ber číslo z řady **podle `Posting Date` každého řádku** přes `No. Series.PeekNextNo`:

```al
if NoSeriesCode <> '' then
    Line."Document No." := NoSeries.PeekNextNo(NoSeriesCode, Line."Posting Date");
```

- **`PeekNextNo`, ne `GetNextNo`.** PeekNextNo **neposouvá** řadu a je
  idempotentní → všechny řádky **jednoho období** dostanou **totéž** číslo
  (2025 řádky jedno, 2026 řádky druhé). To je žádaný stav deníku: **jeden
  doklad per období**, ne per řádek. Řadu posune až ostrý post (`*-Post Batch`
  přes `SaveState`).
- **`GetNextNo` je tu špatně** — posouvá sekvenci, takže každé volání vrátí
  jiné číslo → *N řádků = N dokladů*. (Platí i pro `No. Series - Batch` v
  simulation módu: posun je sice jen in-memory, ale výsledek je pořád „číslo
  per řádek/datum", ne „per období".) `GetNextNo` (simulation) patří do
  **kontroly**, co replikuje posun postu (viz výše `CheckDocumentNos`), **ne**
  do generátoru, kde chceš jedno číslo per období.
- **Anti-pattern:** `PeekNextNo(code, Today())` volané **jednou** pro celý běh
  → všem řádkům totéž číslo bez ohledu na období → 2025 řádky dostanou číslo
  z 2026 řady a post je odmítne. (Přesně tahle chyba byla v
  `ExtTimeSheetJobJournalMXB` (51700) — opraveno na `PeekNextNo` per
  `Posting Date`.)
- **Pozor na pořadí při více obdobích v jedné dávce.** `*-Post Batch` posouvá
  řadu při každém *novém* `Document No.` (logika `LastDocNo2`). Aby „jedno
  číslo per období" prošlo, musí být řádky jednoho období **souvislé** v pořadí
  účtování (Line No.). Při chronologickém generování to obvykle platí; když se
  období v dávce míchají nechronologicky, post u druhého výskytu období hlásí
  *„Číslo dokladu musí být X"* — pak generuj řádky seřazené podle data (chytne
  to i `CheckDocumentNos`).

---

### 5.5 Unix timestamp v AL — NE přes `GetCurrUTCDateTime().Date()/.Time()`

**Trap:** `Type Helper.GetCurrUTCDateTime()` je interně `DotNet DateTime.UtcNow`
a do AL `DateTime` se marshaluje jako **instant** (AL DateTime je vnitřně UTC).
Následné `.Date()` / `.Time()` (DT2Date/DT2Time) pak fasádu zobrazí **v timezone
session** — dekompozice tedy vrací lokální wall-clock, ne UTC číslice. Unix
timestamp poskládaný z těchhle částí je posunutý o timezone offset (CEST = +2 h
do budoucnosti).

Reálný dopad (2026-06, Dotykačka connector): Connect endpoint má toleranci
timestampu **±1 minuta** → podepsaný request vždy spadl na „platnost připojení
vypršela", protože timestamp byl o 2 h jinde.

**Správný pattern — duration od epochy:** rozdíl dvou `DateTime` hodnot běží
nad UTC instanty a na timezone session nezávisí. Epochu naparsuj přes XML
formát (9), kde se `Z` vyhodnotí jako skutečný UTC instant:

```al
local procedure CurrentUnixTimestamp(): BigInteger
var
    EpochDateTime: DateTime;
    MsSinceEpoch: BigInteger;
begin
    Evaluate(EpochDateTime, '1970-01-01T00:00:00Z', 9);
    MsSinceEpoch := CurrentDateTime() - EpochDateTime;
    exit(MsSinceEpoch div 1000);
end;
```

- `Format(UnixSeconds, 0, 9)` pro text bez oddělovačů tisíců.
- Stejný trik (`Evaluate(..., 9)` s `Z` stringem) platí pro parsování
  jakéhokoliv ISO 8601 UTC času — bez formátu 9 se string parsuje podle
  regional settings a může selhat nebo posunout.
- Ověření při debugování: porovnej vygenerovaný timestamp s `date -u` /
  mtime staženého souboru — posun přesně o timezone offset = tenhle trap.

### 5.5a `DateTime` v SQL má přesnost 1/300 s — porovnání s hodnotou v paměti ujede o milisekundu

BC ukládá `DateTime` do SQL typu `datetime` (zaokrouhlení na 0/3/7 ms). Hodnota, kterou zapíšeš (`Rec.X := CurrentDateTime() + 5 * 60 * 1000`)
a pak přečteš z tabulky (nebo ji z tabulky přečte kód, který testuješ, a uloží dál, např. do `Job Queue Entry."Earliest
Start Date/Time"`), je tedy až o ~2 ms **menší** než proměnná, kterou sis nechal v paměti → `Assert.IsTrue(Stored >= InMemory)`
padá **nedeterministicky** (podle ms složky času běhu), lokálně třeba nikdy, v CI ob build. Řešení: po `Modify` udělej
`Get` a porovnávej proti hodnotě z DB (`NextAttemptAt := Rec."Next Attempt At"`), ne proti proměnné; do hlášky assertu dej
obě hodnoty (`StrSubstNo(Label, ...)` — plain string v `StrSubstNo` = AA0217). (2026-09-22, cust-sonnentor-bc build 28397,
`ScheduleFollowUpWaitsForNextAttempt`.)

### 5.x, 5.x2, 5.x2b → vyčleněno do `bc-al-tracking.md`

Item Tracking (výběr šarže vlastní stránkou z Item Tracking Lines, source pole u Prod. Order Line, tracking na Sales Quote
Prospect vs Surplus) žije od 2026-10-07 ve skillu `bc-al-tracking` (soubor `bc-al-tracking.md`). Číslování zůstalo.

### 5.x3 EM Net Make to Order — `Sales Production Ref. NMEBS` (64120) = vazba SO řádek ↔ VZ řádek

Když potřebuješ z výrobní zakázky najít řádek prodejní objednávky (nebo obráceně)
v repu závislém na **EM Net Make to Order** (NMEBS), **nepoužívej** navigaci přes
`Production Order."Source No."` + předpoklad „Line No. VZ řádku = Line No.
prodejního řádku" — ten u NMEBS-plánovaných VZ (merge/split, vlastní číslování)
neplatí. Autoritativní mapování drží tabulka **`Sales Production Ref. NMEBS` (64120)**:

- Klíčová pole: `"Sales Line Document Type"` / `"Sales Line Document No."` /
  `"Sales Line No."` ↔ `"Prod. Order Status"` / `"Prod. Order No."` /
  `"Prod. Order Line No."` (+ req. worksheet trojice pro fázi plánování).
- Sekundární klíče **oběma směry** (Key002 podle sales řádku, Key003 podle VZ
  řádku) → efektivní lookup z obou stran.
- Řádky můžou mít `"Prod. Order Line No."` = 0 (fáze requisition) — při čtení
  odfiltrovat.
- Vzor použití: `UpdatePromisedDelDate.Report.al` a `ItemTrackingMgt.Codeunit.al`
  v cust-zlomek-bc (factbox 64189 — serial čísla z prodejních řádků zobrazená
  na navázaných řádcích Vydané VZ). (2026-07-08, pokyn DNEM.)
- **Kde vazba vzniká a mizí** (zdroj `ManufacturingSubscribersNMEBS`, master 2026-10-13): Carry Out ze sešitu
  (`Mfg. Carry Out Action.OnInsertProdOrderLineOnAfterProdOrderLineInsert` přepíše req. trojici na řádek VZ),
  Sales Order Planning (`Create Prod. Order from Sale`) i Refresh VZ se zdrojem Sales Header (`Create Prod. Order
  Lines.OnCopyFromSalesOrderOnAfterProdOrderLineModify`) — tedy **i VZ ze `Source Type` = Item** vazbu má. Změna
  stavu VZ vazbu přepíše na nové číslo/stav (`OnAfterTransProdOrder`), smazání VZ / řádku VZ ji smaže — **kromě
  Refreshe** (guard `RefreshProdOrder_GetIsActiveFor`), který ale u zdroje Sales Header založí vazby znovu. Po
  opakovaném Refreshi tak řádek VZ může mít **duplicitní vazby** a po přečíslování řádků (změněná objednávka) i
  **zastaralou vazbu na jiný prodejní řádek**. Kdo čte vazby podle řádku VZ: prodejní řádky deduplikuj a vazbu
  filtruj i na `Item No.` / `Variant Code` řádku VZ. (Odvozeno ze zdroje, v BC neověřeno; cust-alumistr-bc 63339,
  code review tisku CNC za celou VZ.)

### 5.y al-mcp `al_search_object_members` — `ByReference` u event parametrů NEVĚŘIT

`al_search_object_members` vrací u **integration event** parametrů `ByReference: false`
i tam, kde je parametr ve skutečnosti `var` (ověřeno 2026-07 na
`Item Jnl.-Post Line.OnBeforeCalcExpirationDate` — tool hlásil všechno by-value,
reálná signatura v BC28 zdrojáku je `var ItemJnlLine; var ExpirationDate; var IsHandled`).
Var-ness eventu **vždy ověř extrakcí zdrojáku z .app** (MS .app = zip se 40B headerem,
`unzip` to zvládne s warningem):

```bash
unzip -l "Microsoft_Base Application_*.app" | grep -i "NazevSouboru"   # najdi cestu
unzip -o -j "….app" "src/…/Soubor.Codeunit.al" -d cil                  # vytáhni
grep -n -B3 -A2 "procedure OnBeforeXxx" cil/Soubor.Codeunit.al          # signatura
```

Pozor zpětně: závěr v 5.x o `OnAfterRetrieveLookupData` (všechno by-value) byl
podložený právě tímhle ByReference výstupem — při příštím použití toho eventu
raději přeověřit ve zdrojáku.

### 5.w Atributy zboží — filtrování items podle atributů = hotové base app API

Když potřebuješ „nabídni/filtruj zboží podle hodnot atributů" (custom lookup,
konfigurátor, výběrová stránka), **nestav vlastní logiku** — base app má celý
mechanismus akce *Filter by Attributes* z Item Listu znovupoužitelný 1:1:

- **Tabulky:** 7500 `Item Attribute` (ID AutoIncrement, Name), 7501 `Item
  Attribute Value` (per atribut, ID AutoIncrement), **7505 `Item Attribute
  Value Mapping`** = persistentní vazba (`Table ID, No., Item Attribute ID →
  Item Attribute Value ID`). Pozor: 7504 `Item Attribute Value Selection` a
  7506 `Filter Item Attributes Buffer` jsou **jen temporary buffery** — data
  nikdy nehledej tam.
- **Dialog:** page 7506 `Filter Items by Attribute` (StandardDialog nad temp
  7506 bufferem, páry Attribute+Value, AssistEdit hodnot, OK → `Action::LookupOK`,
  OnQueryClosePage maže řádky s prázdnou hodnotou). Jde volat
  `Page.RunModal(Page::"Filter Items by Attribute", TempBuffer)` z vlastní appky.
- **Výpočet:** codeunit 7500 `Item Attribute Management` —
  `FindItemsByAttributes(TempBuffer, var TempItem)` (AND přes atributy) +
  `GetItemNoFilterText(TempItem, var Count)` (komprimovaný `No.` filtr s
  rozsahy; `'<>*'` = nic nematchuje). Value filtr umí výrazy (`>100`, `A|B`,
  `*` = má atribut) přes `ItemAttributeValue.SetValueFilter` (numeric/date/text
  attribute types řeší sama).
- Buffer řádky s neexistujícím jménem atributu se v `FindItemsByAttributes`
  **tiše přeskočí** (filtr se nezúží!) — když persistuješ atributové filtry,
  validuj existenci atributů sám a ukládej **ID + jméno** (rename-safe resolve
  dle ID). (2026-08-18, prod-ess-configurator-bc, PBI 58056 — Attribute Filter
  na Table Lookup parametrech, vzor codeunit `Item Attr. Filter Mgt. COEBS`.)

**Hodnotu atributu typu Option nikdy nerozpoznávej podle `Item Attribute Value.ID`.** `ID` (pole 2 tabulky 7501) je
`AutoIncrement` **napříč všemi atributy** (stejně `Item Attribute.ID` v 7500), takže „Ano“ atributu 83 nemá ID 2 jen proto,
že je to druhá z jeho dvou hodnot — podmínka `Mapping."Item Attribute Value ID" = 2` tiše nikdy neplatí (Product Specification
SON, pole Pesticidy, 2026-10-16). Porovnávej text: uložené `ItemAttributeValue.Value` (nepřeložené, `UpperCase` na obou
stranách) proti konstantě z dat zákazníka jako `Label 'Ano', Locked = true` s komentářem, že jde o data; `GetValueInCurrentLanguage()`
jen pro tisk. V testu atribut s pevným ID založ `ItemAttribute.ID := 83; Insert(false)` (explicitní hodnota do AutoIncrement pole
projde), hodnotu s `ID := 0` (přidělí SQL) a mapping `Item Attribute Value Mapping` (`Table ID` = `Database::Item`) ručně.

### 5.z DateFormula — možnosti a limity (půlrok NEjde)

Jednotky: `D`, `WD1–WD7` (den v týdnu), `W`, `M`, `Q`, `Y`. Prefix `C` = current
(konec aktuálního období: `CM` = konec měsíce, `CQ` = konec kvartálu, `CY` = konec
roku; se znaménkem minus začátek: `-CM` = první den měsíce). Vyhodnocuje se
**sekvenčně zleva doprava**: `<CM+1M>` = konec měsíce, pak +1 měsíc.
V CZ klientu lokalizované zkratky (R = rok, takže „+3R" = `<+3Y>`); v kódu vždy
language-independent `<...>` literál nebo `Evaluate(..., 9)`.

**Co NEjde:** žádná jednotka půlrok, žádné podmínky. Zaokrouhlení na konec
pololetí (30.6./31.12.) **nelze** vyjádřit jedním DateFormula — kompozice
CM/CQ/CY + pevných offsetů dává krokové funkce s periodou 1/3/12 měsíců, nikdy 6.
Near-miss ukázka: `<CY+3Y-6M>` dá pro 11.4.26 → 30.6.29 ✓, ale pro 1.9.26 → 30.6.29 ✗
(správně 31.12.29). Řešit enum (typ zaokrouhlení) + DateFormula, zaokrouhlení v kódu.
(Zjištěno 2026-07, Sonnentor VYR-169 expirace šarže.)

### 5.z2 CaptionClass resolver + jazyk dokumentu — `Translation Helper` (codeunit 53), ne holý `GlobalLanguage()`

Subscriber `Caption Class.OnResolveCaptionClass(CaptionArea, CaptionExpr, Language,
var Caption, var Resolved)` dostává **`Language`** (jazyk dokumentu/reportu) — když
caption stavíš z dat závislých na jazyce (Field."Field Caption", captions z metadat),
**nesmíš ho ignorovat**, jinak tištěný doklad dostane caption v jazyce session.
Správný pattern = **`Codeunit "Translation Helper"` (Base App, ID 53)**:

```al
TranslationHelper: Codeunit "Translation Helper";
if Language <> 0 then
    TranslationHelper.SetGlobalLanguageById(Language);
Caption := ...; // Field caption / metadata read runs in the requested language
if Language <> 0 then
    TranslationHelper.RestoreGlobalLanguage();
```

Holý `GlobalLanguage(x)` switch funguje taky, ale LinterCop **LC0022** ho hlásí —
Translation Helper je base-app idiom (má i `SetGlobalLanguageByCode` a
`GetTranslatedFieldCaption(LanguageCode, TableID, FieldId)`). User-defined texty ze
setup tabulky (jednojazyčné Text pole) se nepřekládají — jazykový switch se týká jen
fallbacku na Field caption. (2026-08, prod-epb-pricingMatrix-bc, CaptionClass os matice.)

### 5.z4 CZ ↔ EN terminologie BC

České termíny v BC mají ustálené EN ekvivalenty (názvy tabulek, polí,
captionů). Nezaměňovat za "doslovný" překlad ze slovníku.

| CZ                                | EN v BC                                 | Poznámka                                                       |
| --------------------------------- | --------------------------------------- | -------------------------------------------------------------- |
| Montáž                            | **Assembly**                            | Ne "Mounting"! Standardní moduly: Assembly Order, Assembly BOM |
| Nastavení financí                 | **General Ledger Setup**                | Ne "Finance Setup". Tabulka 98, page 118                       |
| Účto skupina zboží (DPH)          | **VAT Product Posting Group**           | Tabulka 324                                                    |
| Účto skupina obch. partnerů (DPH) | **VAT Business Posting Group**          | Tabulka 325                                                    |
| Účto skupina zboží                | **Gen. Product Posting Group**          | Tabulka 251                                                    |
| Účto skupina obch. partnerů       | **Gen. Business Posting Group**         | Tabulka 250                                                    |
| Záloha                            | **Advance** (CZZ) / **Prepayment** (W1) | V CZ se preferuje Advance (Advance Letter CZZ)                 |
| Přijatá záloha                    | **Sales Advance Letter**                | CZZ extension                                                  |
| Položka zboží                     | **Item Ledger Entry**                   | Ne "Skladová transakce". Page Item Ledger Entries = Položky zboží |
| Řádek deníku zboží                | **Item Journal Line**                   | Page Item Journal = Deník zboží                                |
| Lokace                            | **Location**                            |                                                                |
| Sklad                             | **Warehouse**                           |                                                                |
| Zboží                             | **Item**                                | Standardní BC CZ překlad. Ne "Položka".                        |
| Přihrádka                         | **Bin**                                 | Bin Code = Kód přihrádky. Ne "Koš", ne "Kontejner".            |
| Šarže                             | **Lot**                                 | Lot No. = Číslo šarže                                          |
| Sériové číslo                     | **Serial No.**                          | Caption "Serial No." → "Sériové číslo" (ne "Sériové č.")        |
| Datum expirace                    | **Expiration Date**                     | Ne "Datum platnosti", ne "Datum exspirace"                     |
| Skladová příjemka                 | **Warehouse Receipt**                   | Posted Whse. Receipt = Zaúčtovaná skl. příjemka                |
| Skladová dodávka                  | **Warehouse Shipment**                  |                                                                |
| Šablona / List                    | **Template** / **Batch**                | Whse. Jnl. Template = Šablona skl. deníku, Batch = List        |
| Přeřazení                         | **Reclassification**                    | Movement Reclass Journal = deník přeřazení                     |
| Sledování (zboží)                 | **Tracking** / **Item Tracking**        | Ne "Trasování" — base app cs-CZ používá Sledování              |
| Rezervační položka                | **Reservation Entry**                   |                                                                |
| Cílová přihrádka                  | **Destination Bin** / **To Bin**        |                                                                |
| Příjmová přihrádka                | **Receipt Bin**                         | Bin, kam se účtuje warehouse receipt                           |
| Zachytit / Zachycený              | **Capture** / **Captured**              | "Capture lot/serial" = zachytit šarži/sériové číslo            |
| Zbývající                         | **Outstanding** / **Remaining**         |                                                                |
| Kód varianty                      | **Variant Code**                        |                                                                |
| Měrná jednotka                    | **Unit of Measure**                     | Code → Kód měrné jednotky                                      |
| Vydaná výrobní zakázka            | **Released Production Order**           | Released = **Vydaná**, ne "Uvolněná". Stavy VZ: Simulated = Simulovaná, Planned = Plánovaná, Firm Planned = Pevně plánovaná, Released = Vydaná, Finished = Dokončená |
| Řádek výrobní zakázky             | **Prod. Order Line**                    | Komponenta = Prod. Order Component                             |
| Výrobní kusovník                  | **Production BOM**                      | Certified = Certifikovaný                                      |

Když si nejsi jistý, podívej se do XLIFF (`Translations\*.cs-CZ.xlf`) base
appky nebo do CZ lokalizační větve `cz-<major>` repa
`StefanMaron/MSDyn365BC.Code.History` (viz 7.3).


### 5.z3 CZZ Advance Payments — vazba záloha↔objednávka a scoped guard přes manual bind

Poznatky z EF Advance CZ (WI 63636, 2026-08):

- **Vazbu zálohy na doklad drží `Advance Letter Application CZZ` (31007)** (PK: Letter
  Type, Letter No., Document Type, Document No.), ne pole na hlavičce zálohy. Pole
  `"Order No."` na `Sales Adv. Letter Header CZZ` je jen zrcadlo: `OnDelete` tabulky
  31007 ho **vymaže (i `"Posting Description"`) a standard ho při novém propojení
  NIKDY neobnoví** — extension logika postavená na `Order No.` po unlink+relink tiše
  přestane fungovat. Obnovu je nutné dopsat subscriberem na `OnAfterInsertEvent` 31007.
- **Uživatelské odpojení** jde přes dialog `LinkAdvanceLetter` (page 31175 „Advance
  Letter Appl. Edit CZZ", volá `SalesAdvLetterManagementCZZ.LinkAdvanceLetter`) —
  chybějící řádky po LookupOK se mažou `Delete(true)` **bez IsHandled eventu**.
  Tatáž tabulka se ale maže i systémově (`SalesPostHandlerCZZ` po vyfakturování,
  `SalesAdvLetterPostCZZ` při Close, ApplyChanges při usage) — plošný subscriber na
  `OnBeforeDeleteEvent` by rozbil účtování.
- **Pattern „scoped guard": codeunit s `EventSubscriberInstance = Manual`** a
  subscriberem na `OnBeforeDeleteEvent` + na page nahradit standardní akci vlastní,
  která udělá `BindSubscription(Guard)` → volání standardní logiky → `Unbind`.
  Kontrola tak platí přesně pro interaktivní dialog a systémové cesty nevidí.
  Lokální codeunit proměnná v OnAction drží subscription po dobu volání. V guardu
  nezapomenout `IsTemporary()` exit (dialog pracuje s temp buffery téže tabulky).

### 5.z5 CZZ `Create Sales Adv. Letter CZZ` (report 31012) — kde upravit generovaný řádek zálohy

- **`OnCreateAdvanceLetterLineOnBeforeInsert(var SalesAdvLetterLineCZZ; SalesAdvLetterHeaderCZZ)`** běží těsně před `Insert(true)`
  každého generovaného řádku, v obou režimech (seskupení podle DPH i *Navrhnout podle řádku*). Správné místo pro úpravu řádku (např.
  `Description` podle DPH skupiny); subscriber na `OnInsert` tabulky by přepsal i ručně pořízené řádky na kartě zálohy.
- `UpdateAmounts` dělá před eventem `TestField("VAT Prod. Posting Group")` → generovaný řádek **nikdy nemá prázdnou** DPH skupinu
  zboží (větev „prázdná skupina" testuj přímo na proceduře, report ji nevyrobí).
- `Sales Adv. Letter Line CZZ.Description` je **Text[100]** → delší text ze setupu `CopyStr(…, 1, MaxStrLen(Description))`.
- Report na konci položí Confirm *„Chcete otevřít vytvořenou zálohu?"* → v testu `[ConfirmHandler]` (Reply false). Z prodejní
  objednávky: *Akce → Záloha → Vytvořit zálohovou fakturu…* (request page *Vytvořit prodejní zálohu*: Kód zálohy, Záloha %,
  Částka zálohy, Navrhnout podle řádku; to poslední jde zapnout jen na request page → test s `RequestPageHandler`, viz
  „Report s request page v testu po zápisech" v `bc-al-autotests.md`).

(2026-10-21, cust-zlomek-bc PBI 65149, zdroj cz-28, ověřeno v BC-DEV 28.5.)

### 5.z6 Duplicita IČ / DIČ zákazníka a dodavatele — kde standard jen varuje a jak ji tvrdě zablokovat

- **IČ je v BC 28 CZ pole W1 `"Registration Number"` (25)**; `"Registration No. CZL"` je od 26.0 Removed. DIČ = `"VAT Registration No."`.
- Standardní varování o duplicitě je jen **Message**: IČ přes `Customer CZL` / `Vendor CZL` `modify("Registration Number")`
  `OnAfterValidate` → `Registration No. Mgt. CZL.CheckRegistrationNo`, pak případně ARES; DIČ v triggeru pole → `UpperCase` →
  `VAT Registration No. Format.Test` → `CheckCust` / `CheckVendor`, pak případně VIES. Na zákazníka žádný IsHandled.
- **Tvrdý blok = subscriber na `OnBeforeValidateEvent` pole** (Customer i Vendor, obě pole): `Error` přijde dřív než standardní
  hláška, test formátu i ARES/VIES. DIČ porovnávej `UpperCase` (trigger ho ukládá velkými), prázdnou a nezměněnou hodnotu (`= xRec`)
  přeskoč (legacy duplicity pak neblokují editaci karty), vlastní `"No."` vyřaď. `Error` vrátí pole na `xRec` — nová karta zůstane
  prázdná, existující dostane původní hodnotu; v klientu je to inline chyba pole (12.3 v `bc-al-workflow.md`).
- **Založení zákazníka / dodavatele z kontaktu** (`CustVendBank-Update`) kopíruje IČ/DIČ přes `TransferFields` bez validace → kontrolou
  neprojde (stejně jako standardní varování).
- Test v CZ databázi: vlastní země bez formátu DIČ (`LibraryERM.CreateCountryRegion()`), VIES vypnout
  (`VAT Reg. No. Srv Config`.ModifyAll(Enabled, false)), hodnoty z `CreateGuid`, `Commit()` po GIVEN kvůli `asserterror`.
- Název záznamu dávej v hlášce do závorky (`zákazníka %3 (%4).`) — název končící tečkou (`s.r.o.`) jinak dá dvě tečky za sebou.

(2026-10-21, cust-zlomek-bc PBI 65649 `Reg. No. Duplicity Check ZLK`, ověřeno v BC-DEV 28.5.)

### 5.x4 Sales Line "Attached to Line No." (pole 80) — co standard s vazbou dělá

Prověřeno kompletním grepem Base App **BC 28.3** (extrakce z .app). Pole plní
extended texty, od BC20+ i user akce *Attach to inventory item line* (non-invt
řádky) a CRM write-in produkty. Dá se bezpečně použít pro vlastní parent↔child
vazbu item řádků (např. řádky generované konfigurátorem):

- **Sales-Post žádnou kontrolu na poli nemá** — doklad se zaúčtuje normálně;
  hodnota se přes `TransferFields` propíše do posted/archive tabulek (field 80
  existuje všude). Prepayment logika pole používá jen na temp bufferu a přepisuje
  si ho. `Release` ho nečte.
- **Smazání hlavního řádku kaskádně smaže attached řádky** (`Sales Line.OnDelete`
  → `DeleteAll(true)`, bez filtru na Type). Pokud attached řádek už má dodávky,
  jeho Delete(true) spadne → hlavní řádek nejde smazat.
- **Změna `No.` na hlavním řádku smaže attached řádky** — subformy volají
  `TransferExtendedText.SalesCheckIfAnyExtText` → `DeleteSalesLines` (maže vše
  s `Attached to Line No.` = řádek, bez filtru na Type; jen řádky s Line No. >
  hlavní).
- **Get Shipment Lines / Get Posted Doc Lines to Reverse** auto-přitahují s hlavním
  jen attached řádky `Type = " "` (texty); item attached řádky si uživatel vybírá
  sám. Vazba se přemapovává přes `Transfer Old Ext. Text Lines` buffer (plní se pro
  každý vložený řádek) — když hlavní řádek není ve výběru, vazba skončí 0 (OK).
- **Copy Document / Blanket→Order / VAT Rate Change** vazbu korektně přemapují.
- **Setup „Auto Post Non-Invt. via Whse." = Attached/Assigned** (S&R Setup):
  non-inventory attached řádky se při postingu whse shipmentu / inv. picku
  automaticky dodají s hlavním (`Qty. to Ship := Outstanding Quantity`). Opt-in.
- `IsExtendedText()` = `Type=" " AND Attached<>0 AND Qty=0` — item attached řádky
  pod guardy pro texty nespadají.
- FlowField 7011 „Attached Lines Count" na Sales Line počítá attached řádky s Qty<>0.

(2026-08-19, cust-zlomek-bc task 65364 — konfigurátor v konfigurátoru; child řádky
SL akcí dostávají Attached to Line No. subscriberem na
`OnBeforeModifyNewSalesLineFromAction`.)

Doplněno 2026-09-07 (přesun vazby do base `prod-ess-configurator-bc`, větev `AttachedToLineNo`):

- **Vazbu plní base přímo** v `SL Action Cond. Mgt. COEBS.InitNewSalesLineFromAction` (`"Attached to Line No." :=
  SourceSalesLineNo`); zákaznický subscriber u Zlomka odstraněn. Přepočet návazných řádků při změně hlavního řádku
  = `tableextension "Sales Line COEBS"` → `trigger OnBeforeModify` si přečte **uloženou verzi řádku** (`Get` +
  `SetLoadFields` No./Variant Code/Quantity do instance codeunitu) a `trigger OnAfterModify` proti ní porovná `Rec` a volá
  `RecalculateConfigCreatedLines` (smaže + znovu vytvoří děti z uložené konfigurace varianty; **hlavní řádek
  nemodifikuje a nedává Message**, protože běží uvnitř jeho vlastního Modify).
  ⚠️ **Původní verze porovnávala `Rec` vs `xRec` — a `xRec` je v `OnModify`/`OnAfterModify` při `Modify(true)` z kódu
  shodný s `Rec`** (plní ho jen stránka; base `Sales Line.OnModify` ho používá jen jako pojistku pro UI). Přepočet z kódu
  (`Validate("Variant Code")` + `Modify(true)`, Copy Document, split, API) proto nikdy neproběhl, testy přes TestPage
  procházely — master build 28149 (2026-09-08): 15 červených testů. Ve field `OnValidate` je `xRec` spolehlivý i z kódu
  (obnova vazby po `Validate("No.")` funguje). Obecné pravidlo + vzor viz 3.9 v `bc-al-data.md`. Druhý dopad: uvnitř
  `ExecuteSalesLineActions` může CL Quantity override (Modify hlavního řádku) přepočet z triggeru spustit → úklid dětí
  (`DeleteConfigCreatedLines`) musí běžet **až těsně před** jejich vytvořením, jinak dvě sady.
- **`Sales Line.Validate("No.")` dělá `Init()` a `Attached to Line No.` NEobnovuje** (obnovuje jen Type/No./Line No./
  SystemId…) → u vlastní parent↔child vazby obnov pole 80 i vlastní link pole z `xRec` v `modify("No.") OnAfterValidate`.
- **Interaktivní vs. programová změna:** `CurrFieldNo = FieldNo(X)` jen při editaci na page; konfigurátor, Copy Document,
  RecreateSalesLines i jiné appky validují s `CurrFieldNo = 0` → dotaz („řádek je svázaný s řádkem X… změnit přesto?")
  jen pro uživatele, v testech ho vyvolá jen `TestPage.SetValue`, ne `Rec.Validate`. Odmítnutí řeš standardně
  `if not ConfirmManagement.GetResponseOrDefault(Qst, true) then Error('')` — tichý error vrátí hodnotu pole bez
  dalšího dialogu (v testu **bez** `asserterror` — TestPage tichý error spolkne, `SetValue` doběhne; `Commit()` po GIVEN
  a assert DB stavu + uložené otázky z ConfirmHandleru, viz `bc-al-autotests.md`).
- `Sales Order Subform.QuantityOnAfterValidate` už pro Item řádky volá **`CurrPage.SaveRecord()`** → Modify (a tvůj
  OnAfterModify) proběhne hned v OnValidate; aby se nově vložené řádky ukázaly, stačí v pageextension `OnAfterValidate`
  `CurrPage.SaveRecord(); CurrPage.Update(false)` (vzor standardu `InsertExtendedText` → `UpdateForm(true)`).
  **Úpravy téhož řádku, které jdou přes jinou instanci recordu** (`Get` + `Validate` + `Modify(true)` v codeunitě), dělej
  na úrovni stránky **po `SaveRecord`** a pak `Rec.Get(...)` + `CurrPage.Update(false)` (vzor base
  `LocationCodeOnAfterValidate`: SaveRecord → AutoReserve → Update); uvnitř table triggeru téhož řádku by druhá instance
  rozhodila row version buffer stránky. Na novém řádku (DelayedInsert) SaveRecord = Insert, OnAfterModify nefire → logika
  „po uložení" se chytne až na dalším Modify (typicky Quantity).
- **Číslování generovaných child řádků: do mezery pod parent řádek, ne na konec dokladu.** Standard to dělá u rozšířených
  textů (`TransferExtendedText.InsertSalesExtTextRetLast`: `LineSpacing := (NextLineNo - LineNo) div (1 + Count)`,
  bez následujícího řádku 10000, při 0 error). Stejný vzor pro vlastní parent↔child: spočítej horní odhad počtu řádků,
  mezeru rozděl (klidně cap 10000, ať jsou čísla hezká), při mezeře 0 radši fallback `poslední + 10000` než error.
  Bonus: po smazání a znovuvytvoření dostanou děti **stejná čísla** (mezera se uvolní) — stabilní pořadí v UI.
  (2026-09-07, prod-ess-configurator-bc `InitNewLineNumbering`; dřív `LastLineNo + 10000` = řádky utíkaly na konec.)
- **Mazání dětí při změně `No.` hlavního řádku dělá jen subform** (`NoOnAfterValidate` → `InsertExtendedText(false)` →
  `SalesCheckIfAnyExtText` → `DeleteSalesLines`: `SalesLine2 := SalesLine; Find('>')` = jen řádky s vyšším Line No.);
  table-level `Validate("No.")` děti nemaže → pokrýt vlastním přepočtem v OnAfterModify.
- **Copy Document:** event `Copy Document Mgt.OnAfterCopySalesLineExtText(ToSalesHeader, var ToSalesLine, FromSalesHeader,
  FromSalesLine, DocLineNo, var NextLineNo, var TransferOldExtLines, RecalculateLines)` běží hned po
  `ToSalesLine."Attached to Line No." := TransferOldExtLines.TransferExtendedText(...)` a **před `Insert`** → ideální místo
  pro přemapování vlastního „source line" pole (`:= "Attached to Line No."`; při Recalculate Lines i obnova flagu, Init
  ho vynuloval). Quote→Order a Blanket→Order čísla řádků zachovávají, přemapování netřeba. Děti, které `Delete(true)`
  odmítne (Quantity Shipped/Invoiced/Return Qty. Received ≠ 0), před přepočtem odfiltruj a uživatele informuj.

### 5.x5, 5.x21 → vyčleněno do `bc-al-blanket.md`

Requisition Line (`OnAfterGetDirectCost`, Req. Wksh.-Make Order / Carry Out, Calculate Plan bez dotazů) a přepočet ceny z Množství
bez ceníku (`IsPriceUpdateNeeded`, ruční sleva) včetně hromadných objednávek HNO/HPO (vazba řádků, Recreate lines, změny z hlavičky)
žijí od 2026-10-19 ve skillu `bc-al-blanket` (soubor `bc-al-blanket.md`). Číslování zůstalo.

### 5.x6 „Nemáte dostatečné množství zboží … na skladě" u spotřeby/transferu — `VerifyOnInventory` ignoruje Prevent Negative Inventory

- `Item Ledger Entry.VerifyOnInventory` volá `Item Jnl.-Post Line.InsertItemLedgEntry` **jen když je nová
  položka `Open`**. Záporná položka, která zůstala Open (= po aplikaci zbylo `Remaining Quantity <> 0`),
  skončí u **Consumption / Assembly Consumption / Transfer VŽDY chybou** `IsNotOnInventoryErr`
  („You have insufficient quantity of Item %1 on inventory."); ostatní typy (Sale, Negative Adjmt.…)
  padnou jen když `Item.PreventNegativeInventory()` (Item → Default → Inventory Setup). Spotřeba a
  transfer prostě nesmí do mínusu (náklad musí odněkud přijít), setup je irelevantní.
- „Open" vzniká v `ItemQtyPosting → ApplyItemLedgEntry`: filtr (`ApplyItemLedgEntrySetFilters`) =
  **Item No. + Variant Code + Location Code + Open + Positive** (+ Lot/Serial/Package při specific
  trackingu, + rezervační vazby); z každé kladné položky jde použít jen `Remaining Quantity −
  Reserved Quantity`; výstup **téže VZ a téhož řádku VZ** se na spotřebu neaplikuje
  (`AllowProdApplication`). **Bin Code ani Posting Date do aplikace nevstupují** (přihrádky hlídá
  Whse. Jnl. jinou chybou).
- Diagnostika: stav ber v **base MJ per Item + Variant + Location** (ILE `Open=true, Positive=true`,
  minus rezervace) a porovnej s `Quantity (Base)` řádku deníku, ne s Quantity v MJ řádku.
- ⚠️ `Item Journal Line.Validate("Unit of Measure Code")` **přepíše `Qty. per Unit of Measure`**
  hodnotou z Item Unit of Measure (`UOMMgt.GetQtyPerUnitOfMeasure`). Vlastní qty-per (např. délkové
  kusy komponenty z Cutting Planu) přiřazuj **až po** Validate UoM a pak znovu `Validate(Quantity)`,
  jinak `Quantity (Base)` = Quantity × Item-UoM qty-per — posting bere uložené `Quantity (Base)`
  (`Code()`: `Quantity := "Quantity (Base)"`), nic nepřepočítává. Zachyceno 2026-09-01,
  prod-em-cuttingPlan-bc `Production Journal Mgt. CUEBS.InsertConsumptionJnlLine` (analýza chyby
  z kiosku: přiřazení qty-per z komponenty stojí PŘED `Validate("Unit of Measure Code")`).

### 5.x7 Formát částek v textu (e-mail, export) — `Auto Format.ResolveAutoFormat` vrací `<C,CZK>` prefix; skládej `<Precision,x:y>` sám

- Base app subscriber `Amount Auto Format` (codeunit 347, BC 26+ „Show Currency") do výsledku
  `ResolveAutoFormat(AmountFormat/UnitAmountFormat, CurrencyCode)` **vždy přidá prefix `<C,<ISO kód>>`**
  (`PrefixCurrencyCodeFormatString`) a podle GL Setup i symbol měny — je to formát pro klientský rendering
  page fieldů, ne pro `Format(Decimal, 0, Fmt)` v serverovém textu (e-mail HTML, CSV). Nepoužívat naslepo.
- Chceš-li v textu **stejnou přesnost jako pole na dokladu** (AutoFormatType 1 = částky, 2 = jednotkové
  ceny), slož formát sám: `'<Precision,' + DecimalPlaces + '><Standard Format,0>'` (label
  `'<Precision,%1><Standard Format,0>'`, Locked + Comment kvůli AA0470), kde `DecimalPlaces` =
  `Currency."Amount Decimal Places"` / `"Unit-Amount Decimal Places"` pro FCY a `General Ledger Setup` totéž
  pro LCY. **`Currency.Initialize('')` / `InitRoundingPrecision()` plní jen Rounding Precision, decimal places
  NE** → pro LCY čti GL Setup přímo. Jedním `<Precision,2:2>` pro jednotkové ceny zaokrouhlíš 1,23456 na 1,23
  a příjemce dostane jiný total než odesílatel (code review cust-alumistr-bc 65916, 2026-09-07).
- Test: nastav GL Setup `Unit-Amount Decimal Places = '2:5'` / `Amount Decimal Places = '2:2'` (+ rounding
  precision) přímo v testu (`Modify(false)`, GL Setup v `Library - Setup Storage`), expected přes
  `Format(x, 0, '<Precision,2:5><Standard Format,0>')` — locale-nezávislé, jednotková cena musí vyjít
  s pěti místy, total se dvěma.
- **Prázdné `Amount Decimal Places` / `Unit-Amount Decimal Places` u měny = `<Precision,><Standard Format,0>` →
  `Format(Dec, 0, Fmt)` padá za běhu.** Base `Amount Auto Format` (codeunit 347, w1-28) pro `AmountFormat` /
  `UnitAmountFormat` u nalezené měny žádný fallback nemá (`GetFCYFormat` bere pole přímo); kontrola `<> ''` je jen
  u `CurrencySymbolFormat` (`GetCurrencyAndAmount`). Vlastní skládání formátu tedy: měna → když prázdné, GL Setup →
  když prázdné i tam, pevně `2:2` / `2:5` (Locked labely). Test: `LibraryERM.CreateCurrency` +
  `CreateExchangeRate(Code, WorkDate(), 1, 1)`, pak `Modify(false)` s prázdnými decimal places a rounding precision
  `0.01` / `0.00001` (jinak `Currency.Initialize` spadne na TestField), `SalesHeader.Validate("Currency Code")`.
  (2026-09-10, cust-alumistr-bc 65916, code review `GetAmountFormats`.)


### 5.x8 Item Charge Assignment (Sales) z kódu — `Validate("Qty. to Assign")` padá, když má cílový řádek `Quantity = 0`

- `Item Charge Assgnt. (Sales).InsertItemChargeAssignmentWithValues(…)` (BC 28.3) při `QtyToAssign <> 0` volá
  `ItemChargeAssgntSales.Validate("Qty. to Assign", QtyToAssign)`. Ten trigger (tabulka 5809) dělá
  `SalesLineInvoiced()` = `SalesLine.Quantity = SalesLine."Quantity Invoiced"` na **řádku, ke kterému se poplatek
  přiřazuje** → řádek s `Quantity = 0` (nic fakturováno) vyhodnotí jako „plně fakturovaný" a hodí
  `You cannot assign item charges to the Sales Line because it has been invoiced…`. Zavádějící hláška, příčina je
  nulové množství cílového řádku.
- Typicky to trefí generátory řádků (konfigurátor, import), které poplatek zakládají dřív, než uživatel vyplní
  množství hlavního řádku (sloupec Variant Code před Quantity). Guard: přiřazení dělej jen pro
  `SourceSalesLine.Quantity <> 0` (a případně `Quantity <> "Quantity Invoiced"`), zbytek nech na přepočet po
  změně množství / ruční přiřazení.
- Dále v tom triggeru: `SalesLine.TestField("Qty. to Invoice")` na **řádku poplatku** (když S&R Setup „Default
  Quantity to Ship" ≠ Blank) a `TestField("Applies-to Doc. Line No.")`; `Amount to Assign` se přepočítá jako
  `Qty. to Assign × Unit Cost` (parametr AmountToAssign se přepíše).

(2026-09-11, prod-ess-configurator-bc — analýza „SL Action Line Charge (Item) se nezaloží"; zdroj Base Application 28.3.52162.53506, extrakce z .app.)

### 5.x9 → vyčleněno do `bc-al-blanket.md`

Poptávka → Requisition Line → Purchase Line (kde plánování tvoří řádek, přenos vlastních polí, NMEBS Transfer Lines to Plan)
žije od 2026-10-19 ve skillu `bc-al-blanket` (soubor `bc-al-blanket.md`). Číslování zůstalo.

### 5.x11 EM Cutting Plan `Qty. of Pcs.` / `Qty. per Piece` na Production BOM Line — přepíšou `Quantity per`; tři pasti

`tableextension "Production BOM Line CUEBS"` (prod-em-cuttingPlan-bc) počítá z dvojice polí
`Qty. of Pcs. CUEBS` × `Qty. per Piece CUEBS` jak `Length`, tak **`Quantity per`** — tedy přepíše
množství, které řádku dal kdokoliv před tím (u konfigurátoru `BOM Action Cond. Mgt. COEBS.AddBOMLines`:
`Validate("Quantity per", CalculateBOMQuantity(...))` → `TransferBOMLineFields` → event
`OnBeforeInsertProdBOMLine` → zákaznický subscriber → `Insert`). Větvení podle
`Item Unit of Measure."Qty. per Unit of Measure"`: `= 1` → `Quantity per = Qty. per Piece × Qty. of Pcs.`,
jinak `Quantity per = Qty. of Pcs.` a `Length = Qty. per Piece × konstanta`.

- **Asymetrický default nuly.** `ValidateQtyOfPcsCUEBS` má pojistku `if "Qty. per Piece CUEBS" = 0 then := 1`,
  `ValidateQtyPerPieceCUEBS` obdobnou pro `Qty. of Pcs.` **nemá** → validace samotného `Qty. per Piece`
  nad řádkem s nulovým počtem kusů **vynuluje `Quantity per`** (u qty-per-UoM = 1 přes `Length / konstanta`,
  jinak přímo `:= Qty. of Pcs.`). Subscriber, který nulové hodnoty přeskakuje
  (`if QtyOfPcs <> 0 then Validate(...)`, vzor `Configurator Events COALU` v cust-alumistr-bc), tím problém
  neřeší — chrání jen případ, kdy jsou nulové obě.
- **`Optimalization Mgt. CUEBS.GetLengthTypeConstant` vrací `Integer`, ale pro kombinaci Item UoM `mm` +
  Manufacturing Setup `m` dělá `exit(0.001)`** → AL zaokrouhlí na **0**: `Length` vyjde 0 a
  `ValidateQtyPerPieceCUEBS` spadne na dělení nulou. Návratový typ patří `Decimal`.
- **Plošné / kusové MJ bez „Length Type"** (`Unit of Measure."Length Type CUEBS"` = ' ') skončí v `else`
  větvi `GetLengthTypeConstant` = **Error**. U Alumistra má `M2` (sklo) Length Type prázdný, `KS`/`M` = m,
  `MM` = mm → jakmile se pro řádek s M2 zavolá `Validate("Qty. of Pcs. CUEBS")`, mělo by to padnout;
  kontroluj to dřív, než budeš hledat chybu ve výpočtu.

⚠️ **Než budeš porovnávat chování testovacího prostředí se zdrojákem produktové appky, ověř nasazenou
verzi** (Extension Management, page 2500, sloupec „Je nainstalováno") **a zeptej se jejího vlastníka na
rozpracované změny.** Na Alumistr BC-TEST2 byl 2026-09-16 nahraný lokální build Cutting Planu, ne CI build
z masteru — řádek s `M2` tam místo erroru tiše spočítal `Quantity per = Qty. of Pcs.`, což podle masteru
nemůže nastat. Hodinu analýzy sežral rozpor, který nebyl v kódu, ale v tom, že běžel jiný kód.

Pořadí validací v subscriberu má vliv: `Validate("Qty. of Pcs.")` jako první nastaví `Qty. per Piece` na 1
(pojistka výše) a spočítá množství, druhá validace ho pak přepíše správně — výsledek sedí, ale `Quantity per`
i `Length` se počítají dvakrát.

(2026-09-16, cust-alumistr-bc — analýza kusovníků variant 103200-COEBS0209/0210, definice konfigurace 0052;
zdroje prod-em-cuttingPlan-bc master, prod-ess-configurator-bc master.) Slučování komponent VZ přes `Length` → C8 v `ess-configurator-notes.md`.

**Na komponentě VZ (`Prod. Order Component CUEBS`) je to jinak než na kusovníku — bez větvení podle MJ.** Refresh zakázky
(`Calculate Prod. Order.OnTransferBOMProcessItemOnBeforeGetPlanningParameters`) zkopíruje `Qty. of Pcs.` z řádku kusovníku
a validuje `Qty. per Piece` → `CalcQtyFieldsCUEBS`: `Quantity per := Qty. of Pcs.`, **`Qty. per Unit of Measure := Qty. per Piece`**,
`Length := Qty. per Piece × konstanta`. Jedna „jednotka" komponenty je tedy jeden kus, `Expected Quantity` = počet kusů (base
`CalculateComponents` ji po eventu přepočítá přes `Validate("Routing Link Code")`) a **délka kusu je v základní MJ zboží**, ne v MJ
komponenty → text typu „22x 1,87 M" skládej ze základní MJ (`Item."Base Unit of Measure"`). `Qty. of Pcs.` je na jednotku řádku VZ
(v jeho MJ; `ProdOrderNeeds` násobí `ProdOrderLine.Quantity`). cs-CZ captiony: `Qty. of Pcs.` = **„Množství (výrobní jednotky)"**,
`Qty. per Piece` = **„Množství ve výrobní jednotce"** — zadání od konzultanta „Množství (výrobní jednotky) x Množství (výrobní
jednotky)" myslí právě tahle dvě pole. Test bez Cutting Plan setupu: pole na komponentě po refreshi **přiřaď** (`Validate` chce
`Unit of Measure."Length Type CUEBS"`, `TestField`). Zákaznická appka, která pole čte, potřebuje vlastní dependency na EM Cutting
Plan (tranzitivně přes configurator ne). (2026-10-02, cust-alumistr-bc 66397 — kooperace lakování, poznámky komponent na NO.)

### 5.x13 Délka profilu z výrobního kusovníku: pole `Length` (40) — a `Version Nos.` NENÍ kód verze

Rozměry řádku výrobního kusovníku drží standardní pole **`Production BOM Line."Length"` (ID 40, Decimal)**,
vedle `Width` / `Depth` / `Weight`; uplatní se podle `Calculation Formula` na témže řádku (cs-CZ „Délka",
„Vzorec výpočtu"). U řezaných profilů (Alumistr) je to zdroj délky řezu — šířka a výška profilu naopak
sedí na kartě zboží, ne na kusovníku.

⚠️ **`Production BOM Header."Version Nos." (50)` je číselná řada verzí** (`TableRelation = "No. Series"`),
**ne** kód verze. Filtr `ProdBOMLine.SetRange("Version Code", ProdBOMHeader."Version Nos.")` proto vypadá
správně, ale porovnává jablka s hruškami: dokud je `Version Nos.` prázdné, filtruje `''` = řádky hlavní
verze a všechno „funguje"; jakmile někdo číselnou řadu verzí nastaví, filtr nenajde nic a kód spadne na
„řádek/profil nenalezen". Správně:

- hlavní (neverzovaná) sada řádků → `SetRange("Version Code", '')`,
- **aktivní verze ke dni** → `VersionManagement.GetBOMVersion(BOMHeaderNo, Date, OnlyCertified)`
  (codeunit **99000756** `VersionManagement`, vrací `Code[20]`; sesterské `GetRtngVersion` pro postup,
  `GetBOMUnitOfMeasure` pro MJ verze).

(2026-09-21, cust-alumistr-bc, `CNC Print Mgt. COALU.GetProfileLengthFromBOM` — zachyceno při psaní
uživatelské příručky k PBI 62959.)

### 5.x14 Job Queue z účtování a z kódu — práva, follow-up a proč `ScheduleRecurrentJobQueueEntry*` nevytvoří opakovanou entry

Zdroj w1-28 `Modules/System/JobQueue/JobQueueEntry.Table.al` + `JobQueueEnqueue.Codeunit.al` (cust-sonnentor-bc 63637, 2026-09-22):

- **`Job Queue Entry.ScheduleJobQueueEntryForLater(CodeunitID, StartDateTime, CategoryCode, JobParameter)`** → `EnqueueTask`
  → **`CheckRequiredPermissions`** = `WritePermission()` na `Job Queue Log Entry`, `Error Message Register`, `Error Message`
  (s `[SecurityFiltering(SecurityFilter::Ignored)]`), jinak `Error`. Codeunit `Job Queue - Enqueue` (453) má vlastní
  elevaci na `Job Queue Entry`/`Job Queue Category`, tu tedy uživatel mít nemusí; kategorie se založí sama. Když entry
  plánuješ **ze subscriberu při účtování** (`Sales-Post.OnAfterPostSalesDoc`), zrcadli ty tři `WritePermission()` +
  `TaskScheduler.CanCreateTask()` a při neúspěchu tiše přeskoč — jinak účtující uživatel bez JQ práv shodí posting.
  `TryFunction` kolem toho nedávej (uvnitř jsou DB zápisy). Bez práv musí frontu spolehlivě odbavit **opakovaná** entry.
  ⚠️ `TaskScheduler.CanCreateTask()` vrací v Essence build kontejneru `false` (task scheduler vypnutý) — zrcadlo obal do
  lokální procedury s `IntegrationEvent`, aby si ho testy mohly přepnout na `true`, jinak testy plánování v CI padají
  (`Actual: 0`); detail a vzor v `bc-al-autotests-domains.md`. (2026-09-22, build 28396.)
- **`ScheduleRecurrentJobQueueEntry(WithFrequency)` filtruje jen `Object Type/ID to Run` (+ `Record ID to Process`, je-li
  vyplněné)** — najde i **dokončenou jednorázovou** entry téhož codeunitu a opakovanou pak **nikdy nezaloží**. Když
  codeunit používáš pro one-off i recurring, skládej recurring entry sám: `SetRange("Recurring Job", true)` + `FindFirst`,
  jinak `InitRecurringJob(Minuty)` (public; nastaví Recurring, všechny dny, interval) + `Object Type/ID`, kategorie,
  `Description`, `Maximum No. of Attempts to Run`, `Rerun Delay (sec.)` → `Codeunit.Run(Codeunit::"Job Queue - Enqueue", JobQueueEntry)`.
  Kategorie je `Code[10]`.
- **Follow-up z runneru:** runner (`TableNo = "Job Queue Entry"`) po dávce zjistí, jestli zůstaly řádky k odbavení, a
  naplánuje další one-off s `Earliest Start = max(now, min(Next Attempt At))`; při kontrole „už je naplánováno" (Ready /
  In Process, `Recurring Job = false`) vynech vlastní `Rec.ID` — runner sám je právě In Process.
- **Testy:** `BindSubscription(LibraryJobQueue)` (`Library - Job Queue`, Tests-TestLibraries, `EventSubscriberInstance =
  Manual`) před účtováním/plánováním — subscriber `OnBeforeJobQueueScheduleTask` nastaví `DoNotScheduleTask`, entry se
  založí ve stavu On Hold a v testu nevznikne skutečný scheduled task. Lokální proměnná codeunitu se na konci testu
  odváže sama. Otevření `Job Queue Entry Card` přes `Page.Run` chce `[PageHandler]`.
- **„Spustit jednou (na popředí)" (`Run once (foreground)`) NENÍ test běhu na pozadí.** Akce na `Job Queue Entries` / kartě
  volá `Job Queue Management.RunJobQueueEntryOnce` → kopie entry + `Codeunit.Run(Codeunit::"Job Queue Dispatcher", …)`
  **v UI session uživatele** → `GuiAllowed() = true`, takže `ConfirmManagement.GetResponseOrDefault` / `Confirm` dialog
  **ukáže a úloha „čeká na potvrzení"**. Skutečný scheduled task běží bez GUI: `Confirm Management Impl.IsGuiAllowed` →
  `GetResponseOrDefault` vrátí default bez dialogu, `GetResponse` vrátí `false`, holý `Confirm()` hodí chybu (entry
  skončí ve stavu Chyba, nevisí). Hlášení „automatická úloha se zasekla a ptá se" = skoro jistě běh na popředí — nejdřív se
  zeptej, jak ji spouštěl. Zdroj w1-28.4 `JobQueueManagement.Codeunit.al`, `ConfirmManagementImpl.Codeunit.al`
  (2026-10-05, cust-sonnentor-bc PBI 64046 — dotaz na HNO při Calculate Plan z fronty).
- **„Spusť existující Ready entry hned (nebo za N sekund)" (trigger z API / z kódu) = nastav `Earliest Start Date/Time`
  na teď (+ prodleva) a znovu `Codeunit.Run(Codeunit::"Job Queue - Enqueue", Entry)`.** `Job Queue - Enqueue.InitEntryForSchedulerWithDelayInSec` posune
  start na `CurrentDateTime + 1 s` **jen když je v minulosti** — budoucí (naplánovaný) start nechá, takže samotný Enqueue
  opakovanou úlohu „teď" nespustí; `Restart()` start taky nemění (jen Inactivity Timeout). Enqueue existující entry
  (`ID <> null`) zruší starý task (`CancelTask`), založí nový a vrátí Status Ready; po běhu si opakovaná entry další start
  spočítá sama. Vzor: entry hledej `Object Type/ID to Run` + `Status = Ready` pod `ReadIsolation(UpdLock)` (paralelní API
  volání se serializují, jinak `Modify` v Enqueue spadne na souběhu), už splatný start (`<= CurrentDateTime`) přeskoč, před
  tím zrcadlo práv (`ReadPermission` na JQE + tři `WritePermission` z `CheckRequiredPermissions` + `CanCreateTask` přes
  IntegrationEvent pro testy) → bez práv tiše nic, ať API POST nespadne. Test: entry Ready se startem zítra +
  `BindSubscription(LibraryJobQueue)` → po volání `Earliest Start <= now + minuta` (status s DoNotScheduleTask zůstane On
  Hold — neassertovat). Zdroj Base App 28.5 `JobQueueEnqueue.Codeunit.al`. (2026-10-06, cust-soitron-bc
  `QB Buffer Automation Mgt. SOI.StartScheduledAutomation` — start QB automatizace z API page bufferu.)
- **Codeunit pro Job Queue musí mít `TableNo = "Job Queue Entry"` (nebo žádné `TableNo`)** — Job Queue Dispatcher volá
  `Codeunit.Run(ID, JobQueueEntry)`, takže codeunita s `TableNo` na vlastní tabulku skončí hned chybou
  `Record(472) is not compatible with Codeunit.Run(Record(<vlastní tabulka>))` (472 = Job Queue Entry) — v testech přes
  `AutomationMgt.RunAutomation(Rec)` se to neukáže. Jeden codeunit pro „dávka z fronty" i „jeden záznam v error boundary
  (`if not Runner.Run(Rec)`)" tedy nejde; error-boundary běh dej do samostatné malé codeunity s `TableNo` = vlastní tabulka,
  která zavolá zpět orchestrátor. Test: `Codeunit.Run(Codeunit::X, JobQueueEntry)` s `Init()` entry (bez Insert) po `Commit()`
  GIVEN dat (`Codeunit.Run` s návratovou hodnotou uvnitř chce zavřenou write transakci). (2026-10-20, cust-soitron-bc
  `QB Buffer Automation Mgt. SOI` / `QB Buffer Automation Run SOI`, chyba z Job Queue na testu zákazníka.)

### 5.x15 → vyčleněno do `bc-al-tracking.md`

Tracking na fakturačním řádku z Get Shipment Lines (jen Prospect z dodávky) a předvyplnění šarže na Item Tracking Lines
(5.x15b) žijí od 2026-10-07 ve skillu `bc-al-tracking`. Číslování zůstalo.

### 5.x16 Data Exchange Framework (import bankovních výpisů camt.053) — pasti definice a mapování

Ověřeno v Base Application 28.3 (`ProcessDataExch.Codeunit.al`, `TransformRuleReplace/Match.Codeunit.al`) při ladění
importu Raiffeisenbank v prod-ef-bank-bc (2026-09-24). **Definice (řádky, sloupce, mapování, transformační pravidla,
Post-Mapping codeunit) žije jen v DB zákazníka** — v repu bývá jen hlavička (`Data Exch. Def` Insert). K diagnóze si
vždy vyžádej export (Definice výměny dat → Export definice výměny dat), screenshot nestačí.

- **Více sloupců do jednoho textového pole = spojení s mezerou.** `Process Data Exch.SetAndMergeTextCodeField` bez
  `Overwrite Value` dělá `StrSubstNo('%1 %2', stará, nová)` → `1041045226 /5500`. Mapováním se mezera **neodstraní**
  (každé pravidlo vidí jen svou hodnotu) → `DelChr(..., '=', ' ')` v post-mapping codeunitu. Mezera vadí: CZB párování
  (`Match Bank Payment CZB`) porovnává `Bank Account No. CZL` s bankovními účty přes `SetRange`, tedy přesně.
- **Regex pravidlo pro VS/KS/SS = „Regular Expression - Match" (typ 10), ne „Replace" (typ 6).** Replace při neshodě
  vrátí **celý původní text** (`Regex.Replace`), takže `VS:123` skončí i v KS/SS (oříznuté na `Code[10]`). Match při
  neshodě vrátí `''`, při shodě spojí zachycené skupiny (bez skupiny 0) → vzor `VS:(\d+)`.
- **ID polí `Bank Acc. Reconciliation Line` (274):** 4 Document No., **6 Description**, 7 Statement Amount, 15
  Related-Party Name, **16 Additional Transaction Info** (ne Description!), 23 Transaction Text, 24 Related-Party Bank
  Acc. No., 25/26 Address/City, 70 Transaction ID. EF Banking `Import Payment Launcher EBS` bere do popisu řádku výpisu
  přednostně 23, jinak 6.
- **Chybná cesta sloupce se neohlásí** — sloupec jen nikdy nedostane hodnotu (XML import páruje `Path` přesně; např.
  vynechaný uzel `/Ntry/`). `DataExchField.GetFieldName()` vrací **Name** sloupce, ne Path → kód, který hledá sloupce
  podle názvu (`Stmt/Ntry/NtryDtls/TxDtls/RltdPties/Cdtr/Nm`), závisí na konvenci pojmenování v definici.
- **Import XML definice existující kód NEPŘEPÍŠE** („Záznam v tabulce Definice výměny dat již existuje") → napřed
  smazat, nebo importovat pod jiným kódem a přepnout `Bank Export/Import Setup."Data Exch. Def. Code"`. Transformační
  pravidla v XML se zakládají podle `Code` → změnu typu pravidla dělej pod **novým** kódem (`VS-MATCH`), ne úpravou
  existujícího.
- Standardní `SEPA CAMT 053-08` z base app (`resources/DataExchangeDefinitions/*.xml` v .app) je pro namespace
  `camt.053.001.08` a strukturu `Dbtr/Pty/Nm`; CZ banky (Raiffeisen) posílají `camt.053.001.02` s `Dbtr/Nm` → vlastní
  definice, standardní se nedá použít ani jako základ 1:1.
- EF Banking specifika (`Import SEPA Post Mapping CBEBS`): VS/KS/SS parsuje z `Description 2 EBS` (token `/VS`, KB SK)
  a při neshodě **přepíše namapované symboly prázdnem** + přilepí text k popisu s čárkou → do `Description 2 EBS`
  nemapuj `EndToEndId`; protistranu skládá jen z cest `.../DbtrAcct|CdtrAcct/Id/IBAN`, tuzemské `Othr/Id` nechává
  z mapování; `SetValueFromPostExchField('POPIS1'|'CREDIT'|'DEBIT')` hledá sloupce podle **`Data Format`** jako tagu.
- **Výsledný návrh IMEBS (2026-09-25, `prod-ep-itemManagement-bc`, větev features/misc):** rozhodnutí per nákupní řádek v subscriberu
  `OnPostItemJnlLineJobConsumption` — `IsHandled` jen když projekt má Skip Purchase Consumption **a** na Budget JPL nákupního řádku
  ukazuje Billable JPL přes `Purch. Job Cont.Entry No.IMEBS`; bez vazby standardní spotřeba při příjemce. Guard vazby v `OnValidate`
  pole (tableextension → codeunit `ValidatePurchJobContractEntryNo(Rec, xRec)`): nová vazba zamítnuta při existující **spotřebě**
  cílové Budget JPL = `Job Usage Link` **nebo** standardní spotřební ILE (`Entry Type = Negative Adjmt.`, `Job No.`, `Job Task No.`,
  `Order Line No.` = `Job Contract Entry No.` Budget JPL — Item Jnl.-Post Line tam ukládá `ItemJnlLine."Job Contract Entry No."`,
  Purch.-Post ho plní z `PurchLine."Job Planning Line No."`); pouhá příjemka bez spotřeby (historicky přeskočená) musí jít dovázat.
  Změna/odpojení zamítnuto při příjemce **nebo** spotřebě staré Budget JPL, jedna Budget JPL ↔ jedna Billable JPL. Page `OnLookup`
  vrací hodnotu přes `Text` + `exit(true)` (page sám validuje, žádný `Rec.Modify` v triggeru). `Update Job Item Cost` restore jen pro
  JLE nad `ILE."Entry Type" = Purchase`. Analyzer pasti při tom: **PC0023** `IsHandled := <bool výraz>` (musí být `if … then IsHandled
  := true`), **FC0003** `RecordId` bez závorek (`RecordId()`). Testy `Purch. Consumption Test IMEBS` (65142).
- **Standard při příjmu nákupu s projektem NEzakládá Job Ledger Entry ani Job Usage Link** — `Purch.-Post.PostItemJnlLineJobConsumption`
  při příjmu zaúčtuje jen spotřební ILE Negative Adjmt. s projektem (zboží odejde ze skladu), `PrepareJobLine` → `Job Post-Line.
  PostJobOnPurchaseLine` → JLE Usage + Usage Link běží jen `if QtyToBeInvoiced <> 0`, tj. při **fakturaci** nákupu. Test „usage po
  příjmu" tak dá 0 i v čistém standardu (build 28479+, `Purch. Consumption Test IMEBS`, 2026-09-25): po `PostPurchaseDocument(true,
  false)` assertuj ILE, pro JLE/Usage Link doúčtuj `Get` hlavičky + `PostPurchaseDocument(false, true)`. Guard „spotřeba už existuje"
  proto nesmí stát jen na Usage Linku (viz výše).

### 5.x17–5.x20 → vyčleněno do `bc-al-projects.md`

Projekty (Job, Job Task, Job Planning Line, deník projektů): účto skupina a dimenze řádku plánování do Job Journal Line,
Location Code z Job / Job Task, vazba budget ↔ billable (`Purch. Job Cont.Entry No.IMEBS`), návazné doklady projektu
a guardy `Job Planning Line.OnDelete` žijí od 2026-10-05 ve skillu `bc-al-projects` (soubor `bc-al-projects.md`). Číslování zůstalo.

### 5.x22 Přihrádka (Bin Code) na řádcích prodejní / nákupní objednávky a její cesta do skladové dodávky / příjemky (BC 28)

Ověřeno ve zdrojích w1-28 při PBI 65239 (cust-sonnentor-bc, 2026-10-09 — výchozí přihrádka zákazníka / dodavatele
na hlavičce → řádky → skladový doklad):

- **Kde standard přihrádku řádku dokladu počítá:** `Sales Line.GetDefaultBin()` (public) / `Purchase Line.GetDefaultBin()`
  (local) — volá se z validace `No.`, `Location Code` a `Variant Code` řádku zboží. Vynuluje `Bin Code`, u Drop Shipment
  skončí, jinak při `Location."Bin Mandatory" and not "Directed Put-away and Pick"` vezme **výchozí Obsah přihrádky**
  (`WMS Management.GetDefaultBin` = Bin Content s `Default = true`). **Prodejní řádek ji navíc vůbec nenastaví, když má
  lokace `Require Shipment` a existující `Shipment Bin Code`** (`IsShipmentBinOverridesDefaultBin`) — proto bývá na
  prodejních řádcích přihrádka prázdná, zatímco na nákupních je vyplněná. Hook pro vlastní default = **`OnAfterGetDefaultBin(var
  SalesLine)` / `(var PurchaseLine)`** na konci procedury (běží i ve větvi, kde base nic nenastavil; pro ne-Item řádky se
  nevolá). Přiřazení do `Rec` je jen v paměti, stejně jako base — žádný `Modify`, žádná `IsTemporary` výjimka.
- **Řádek skladové příjemky / dodávky z objednávky:** `Purchases Warehouse Mgt.PurchLine2ReceiptLine` / `Sales Warehouse
  Mgt.FromSalesLine2ShptLine` dají `Bin Code` z **hlavičky skladového dokladu** (= `Location."Receipt Bin Code"` /
  `"Shipment Bin Code"`, když lokace sedí) a přihrádku řádku objednávky jen jako fallback při prázdné; pak ještě
  `Whse.-Create Source Document.UpdateReceiptLine/UpdateShipmentLine` hlavičkovou přihrádku znovu `Validate`. Přihrádka
  z řádku objednávky se tedy do skladového dokladu **standardně nedostane**, když lokace má příjmovou / expediční
  přihrádku. Poslední místo před `Insert` = **`OnBeforeWhseReceiptLineInsert(var WarehouseReceiptLine)` /
  `OnBeforeWhseShptLineInsert(var WarehouseShipmentLine)`** (codeunit 5750) — zdrojový řádek tam není parametrem, dohledej
  `Purchase Line.Get(Order, "Source No.", "Source Line No.")`. Alternativa s řádkem v parametru:
  `OnAfterCreateRcptLineFromPurchLine` / `OnAfterCreateShptLineFromSalesLine` (po `Insert`, nutný `Modify(false)`).
- **`Validate("Bin Code")` na řádku objednávky z kódu / testu = `Message`**: `Bin Code.OnValidate` volá `CheckWarehouse(true)`
  a u typu Objednávka v lokaci s `Require Receive` (nákup) / `Require Shipment` (prodej) bez existujícího řádku skladového
  dokladu skončí `Message(WhseRequirementMsg)` → test potřebuje `[MessageHandler]`; s existujícím řádkem skladového dokladu
  je to `Error`. Prodejní řádek má navíc `TableRelation` na **Bin Content** (Order s `Quantity >= 0`) a `CheckBinCodeRelation`
  → přihrádka bez obsahu pro dané zboží se na prodejní řádek z kódu nedá zadat (`LibraryWarehouse.CreateBinContent` před
  `Validate`). Přímé přiřazení (`"Bin Code" := …` + `Modify`) žádnou z kontrol nespouští. `Validate(Quantity)` z kódu
  dialog nedává (`CheckWarehouseForQtyToShip` / `CheckLocationRequireReceive` jen při `CurrFieldNo <> 0`).
- **Hlavička → řádky:** `UpdatePurchLinesByFieldNo` / `UpdateSalesLinesByFieldNo` nejdřív udělají `Modify()` hlavičky a pak
  validují řádky; subscriber na `OnAfterValidateEvent("Location Code")` hlavičky běží **až po** nich, takže hodnota, kterou
  v něm na hlavičku dosadíš, se na řádcích při téže validaci ještě neprojeví — dorovnej řádky v tom subscriberu sám.
- **Sales Order Subform má sloupec `Bin Code` `Visible = false`** (Purchase Order Subform `true`) → bez `modify("Bin Code")
  { Visible = true; }` uživatel přihrádku na prodejním řádku nezmění ani nevidí. `TestPage` ji pak také nevidí (bc-al-autotests).
- Testovací setup: `LibraryWarehouse.CreateLocationWMS(Location, BinMandatory, PutAway, Pick, Receive, Shipment)` +
  `CreateBin(Bin, Loc, Code, '', '')` + `Location.Validate("Receipt Bin Code" / "Shipment Bin Code")` +
  `CreateWarehouseEmployee(WhseEmployee, Loc, false)`; skladový doklad `CreateWhseReceiptFromPO(PurchaseHeader)` /
  `CreateWhseShipmentFromSO(SalesHeader)` po `Release…Document` (bez dialogu). `LibraryUtility.GenerateRandomCode` vrací
  `Code[10]`.

### 5.x24 Retention Policy (Retenční zásady) pro vlastní logy — registrace bez install codeunity, zamčené filtry

- **Registrace stačí přes subscriber** `[EventSubscriber(ObjectType::Codeunit, Codeunit::"Reten. Pol. Allowed Tables",
  OnRefreshAllowedTables, '', false, false)]` → `RetenPolAllowedTables.AddAllowedTable(Database::"Můj Log", FieldNo(<DateTime pole>), …)`.
  Event je `internal` (volat ho nejde), ale vyvolá ho System App sám: stránka **Retention Policy Setup List** v `OnOpenPage`
  i akcí *Refresh* a karta zásady (BCApps `RetentionPolicySetupList.Page.al`). Admin tabulku uvidí, jakmile otevře retenční
  zásady — install/upgrade kód netřeba (hodí se, když appka install/upgrade codeunity v testovací fázi nechce). Vzor v
  cust-sonnentor-bc `VoucherDiscountMgt.Codeunit.al` a prod-ess-dotykackaConnector-bc `Dotykacka Subscribers DCEBS`.
- Mazání jde přes `RetenPolDeleteImpl` → `DeleteAll(RecRef, true)` = **s triggery** → kaskáda na detailní tabulku v
  `OnDelete` hlavičky logu funguje, detail se registrovat nemusí (uživatel / job ale potřebuje D i na detail).
- **Řádky, které se smazat nesmí** (import log s JSONem nedokončených záznamů): registruj tabulku se **zamčenými řádky
  filtrů s obdobím „Never Delete"** na nedokončené stavy (`AddTableFilterToJsonArray` s `Locked = true`). Engine (BCApps)
  v druhém průchodu odznačí všechny záznamy zamčeného „Never Delete" řádku → nesmaže je ani řádek, který si admin přidá,
  a „Apply to all records" nejde zapnout. Dokončené stavy dej jako **odemčené** řádky s výchozím obdobím (admin si je změní).
  Opačně (zamčené řádky na dokončené) by admin období neměnil a nedokončené by nic nechránilo.
- Test: registraci vytáhni do `internal procedure` a assertuj přes public API `Reten. Pol. Allowed Tables.IsAllowedTable`;
  skutečné mazání jde otestovat během `Apply Retention Policy` nad záznamy s datem 400 dní zpět (engine jde po dnech → pár
  sekund). (2026-10-14, prod-ess-dotykackaConnector-bc code review — Sync Log + Import Log.)

### 5.x26 Skladový přesun / vyskladnění z kódu: `Validate("Bin Code")` na řádku Take a registrace jednoho páru Take/Place

Ověřeno ve zdrojích w1-28 (`WarehouseActivityLine.Table.al`, `WhseActRegisterYesNo` / `WhseActivityRegister.Codeunit.al`,
`WMSManagement.CheckBalanceQtyToHandle`, `BinContent.Table.al`) při review prod-ew-mobileBase-bc 66918 (2026-10-20):

- **`Warehouse Activity Line."Bin Code".OnValidate` dělá kontroly jen při `CurrFieldNo <> 0`** (= ze stránky). Z kódu
  (`TakeLine.Validate("Bin Code", …)`) se přeskočí: `BinType.TestField(Receive, false)` u Take řádku, `CheckWhseDocLine`,
  dostupnost v přihrádce (`CheckExceedQtyAvailBase`) i u řízené lokace `CreatePick.CalcTotalAvailQtyToPick`. Kdo mění
  přihrádku Take řádku z kódu (sken na čtečce), musí si kontroly napsat sám a **zrcadlit base**:
  - Obsah přihrádky hledej v MJ podle `GetUOMCode`: řízená lokace (*Directed Put-away and Pick*) = `"Unit of Measure Code"`
    řádku, **jinak základní MJ zboží** (`WMS Management.GetBaseUOM`) — na základní lokaci je Bin Content v základní MJ,
    `BinContent.Get(…, řádek."Unit of Measure Code")` s jinou než základní MJ nenajde nic a dostupnost vyjde 0.
  - Typ aktivity: `Pick`, `Invt. Pick`, `Invt. Movement` → `BinContent.CalcQtyAvailToPick(0)`, **`Movement` →
    `CalcQtyAvailToTake(0)`**. `CalcQtyAvailToPick` vrací **0 pro dedikovanou přihrádku** a pro `Block Movement` =
    Outbound/All (exit bez hodnoty), `CalcQtyAvailToTake` dedikaci neřeší.
  - Při jiné zóně nejdřív `Validate("Zone Code", Bin."Zone Code")` (TableRelation `Bin Code` filtruje podle zóny řádku),
    `Zone Code.OnValidate` vyprázdní `Bin Code` / `Bin Ranking` / `Bin Type Code`.
- **Registrace jen jednoho páru jde přes standard:** `Codeunit.Run(Codeunit::"Whse.-Act.-Register (Yes/No)", Lines)` s filtrem
  `"Line No." = Take|Place`. `Yes/No` dělá `WhseActivLine.Copy(Rec)`, `CheckBalanceQtyToHandle` kopíruje filtry volajícího a
  `Whse.-Activity-Register.Code` jen přidá `Activity Type` / `No.` / `Qty. to Handle (Base) <> 0` → zapíše se jen pár a
  bilance Take = Place se kontroluje jen na něm. Potvrzovací dialog přeskočí manuálně bindovaný subscriber na
  `OnBeforeConfirmRegister(var Line; var Result; var IsHandled)` (`Result := true; IsHandled := true`).
- **Po částečné registraci standard sám vyplní `Qty. to Handle` na všech zbylých řádcích** (`AutofillQtyToHandle`), pokud
  hlavička nemá `Do Not Fill Qty. to Handle`; plně zapsané řádky a prázdnou hlavičku smaže (`Header.Get` = false → doklad hotový).
- **Párování Take ↔ Place nemá v tabulce vazbu.** Standard (Create Pick / Create Inventory Pick/Movement) zakládá Take a hned za
  ním Place, ale **`Split Line` na Take řádku vloží nový Take mezi ně** (`Line No.` = půlka mezery) → „nejbližší předchozí
  Take" pak ukáže na odštěpenou část s menším množstvím. Robustnější filtr: zboží, varianta, tracking, MJ,
  `"Whse. Document Line No."` / `"Source Line No."` a kontrola 1:1 (`Qty. Outstanding (Base)` Take = Place), jinak srozumitelná
  chyba „zpracuj v BC".
