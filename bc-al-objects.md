# BC/AL poznámky — Specifické objekty & API

> Část rozděleného `bc-al-notes.md` (rozsekáno 2026-06-23; archiv: `bc-al-notes.archived-2026-06-23.md`).
> Shopify Connector (5.y2) a SaaS/Cloud gotchas (sekce 11) vyčleněny 2026-09-08 do `bc-al-integrations.md`.
> Načítej, když řešíš: No. Series, Upgrade Tag, All Profile, Item Tracking/Lot (i Sales Quote), Reservation Entry u VZ, NMEBS vazba SO↔VZ,
> Unix timestamp, atributy zboží, DateFormula, CaptionClass/Translation Helper, CZ↔EN terminologie, CZZ zálohy, Attached to Line No. /
> parent↔child řádky, Requisition Line / Req. Wksh.-Make Order, VerifyOnInventory, Auto Format / částky v textu.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

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

### 5.x Item Tracking — filtrování/obohacení výběru šarže (Lot No.)

Když potřebuješ **omezit nebo obohatit výběr šarže** při zadávání item trackingu
(typicky consumption na Prod. Order Component — výběr Lot No. dle vlastního kritéria,
zobrazení vlastních polí z Lot No. Information), **nepokoušej se rozšiřovat nativní
výběrový dialog** `Item Tracking Summary` (page 6500 nad tabulkou `Entry Summary` 338).
Dva tvrdé blokátory:

- **`Entry Summary` (338) nemá `Item No.`** (jen Lot/Serial/Package No. + qty + Source
  Subtype + Table ID). Lot No. Information (klíč Item No.+Variant+Lot No.) odtud
  spolehlivě nedohledáš.
- **`Item Tracking Data Collection` (6501) event `OnAfterRetrieveLookupData(TrackingSpecification;
  FullDataSet; TempGlobalReservEntry; TempGlobalEntrySummary)` nepředává entry summary
  buffer `var`** — subscriber ho neumí filtrovat ani plnit. (Ověřeno přes al-mcp
  `al_search_object_members` — všechny parametry ByReference=false.)

**Funkční pattern (Sonnentor 64042 — výběr šarže dle kvality):** vlastní výběrová stránka
otevřená **akcí z `Item Tracking Lines` (page 6510, source `Tracking Specification` 336)**.
Řádek 6510 (`Rec`) **má `Item No.`, `Variant Code`, `Location Code` i Source pole**, takže:

- Komponentu VZ dohledáš ze Source: `Source Type = Database::"Prod. Order Component"`,
  `Source Subtype`→Status (Option→Integer→`"Production Order Status".FromInteger`),
  `Source ID`→Prod. Order No., `Source Prod. Order Line`→Prod. Order Line No.,
  `Source Ref. No.`→Line No.
- Kandidátní šarže naplníš do **temp buffer tabulky** (`TableType = Temporary` → žádný
  permission/tabledata) z `Lot No. Information` (+ vlastní pole), zůstatek lotu vezmi
  z **FlowField `Inventory`** (`CalcFields(Inventory)` s `SetRange("Location Filter", …)`)
  — nemusíš sám sumarizovat Item Ledger Entry.
- Výběrová `page` (List, `SourceTableTemporary`, lookup mode) si buffer plní v `OnOpenPage`;
  „rozpustit filtr" = akce, která přenaplní buffer bez filtru (ne mazání řádků).
- Po `RunModal = LookupOK` vrať Lot No. na řádek 6510 a v `OnAction` zavolej
  `CurrPage.Update(true)` — tím proběhne standardní tracking validace, neobcházíš ji.

Business logiku (resolve required code, build buffer) dej do codeunitu s **public**
procedurami → testovatelné z test appky bez TestPage (UI tracking přes TestPage je fragile).

### 5.x2 Item Tracking — mapování Source polí u řádku VZ (Prod. Order Line)

`Reservation Entry` (337) i `Tracking Specification` (336) plní source pole pro
**Prod. Order Line** takto (base app `Prod. Order Line-Reserve.InitFromProdOrderLine`):

```al
SetSource(Database::"Prod. Order Line", Status.AsInteger(), "Prod. Order No.", 0, '', "Line No.");
//        Source Type                   Source Subtype      Source ID          ^Source Ref. No. = 0
//                                                                             Source Prod. Order Line = "Line No."
```

**`Source Ref. No.` je 0** — číslo řádku VZ žije v **`Source Prod. Order Line`**!
(U komponent 5407 je to jinak: `Source Prod. Order Line` = řádek VZ,
`Source Ref. No.` = Line No. komponenty.) Důsledek: SubPageLink / filtr factboxu
nad tracking daty pro Prod. Order Line **musí** linkovat
`"Source Prod. Order Line" = field("Line No.")` — link přes `Source Ref. No.`
nikdy nematchne a part je věčně prázdný (chyba ze Zlomek 64189; u Sales Line je
naopak správně `Source Ref. No.`). Ověřeno extrakcí z BC 27.5 base app.

### 5.x2b Item Tracking na Sales Quote — standard ho umí, přenáší se do Order

**Prodejní nabídka má standardní item tracking.** Na `Sales Quote Subform` (95)
je akce **„Item Tracking Lines"** (`Rec.OpenItemTrackingLines()`, jen pro
`Type = Item`, ne pro ATO řádky) a tracking se ukládá do `Reservation Entry`
(337) se `Source Type = 37`, **`Source Subtype = 0`** (Quote), `Source ID` =
číslo nabídky, `Source Ref. No.` = Line No. Při **Make Order** (`Sales-Quote to
Order`, 86) se rezervační položky přenesou na objednávkový řádek přes
`SalesLineReserve.TransferSaleLineToSalesLine(SalesQuoteLine, SalesOrderLine,
"Outstanding Qty. (Base)")` — SN/šarže zadané na nabídce tedy na SO nezmizí.
Totéž platí pro Blanket Order → Order (87). Neplést s **rezervací** skladu:
`Reserve` na nabídce nedělá nic užitečného, ale tracking (jednostranné entries
s SN) na ní žije. Ověřeno w1-28 (2026-09-02, nacenění Zlomek 62661).

⚠️ **Tracking na nabídce má `Reservation Status = Prospect`, ne Surplus.**
`Item Tracking Lines` (6510) `SetSourceSpec` dává `Surplus` jen „order network
entitám" a `Item Tracking Management.IsOrderNetworkEntity` bere u `Sales Line`
**jen Subtype 1 (Order) a 5 (Return Order)** — nabídka (0) a rámcová objednávka
(4) padnou do `else` větve = `Prospect`. Na Surplus to překlopí až
`TransferSaleLineToSalesLine` během Make Order. Důsledky:

- Vlastní kód, který jednostranný tracking hledá `SetRange("Reservation
  Status", …::Surplus)`, na nabídkách **tiše nedělá nic** (žádná chyba, žádný
  záznam) → filtruj `'%1|%2'` Surplus + Prospect. Párované (`Reservation` /
  `Tracking`) nech být — `CreateReservEntry.CreateEntry` pro ně zakládá dvě
  řádky a protistrana drží starou hodnotu.
- `Sales-Quote to Order` volá na **každé** položce
  `ReservEntry.TestItemFields(SalesLine."No.", "Variant Code", "Location Code")`
  → jakýkoliv nesoulad varianty mezi řádkem a jeho rezervačními položkami
  vybouchne až tady (*„Kód varianty musí být rovno…"*), ne při samotné změně.
  Konfigurátorové scénáře, které mění `Variant Code` řádku se sledováním, proto
  musí variantu na entries srovnat samy — a `CreateReservEntry.TransferReservEntry`
  ji s sebou nese přes `TransferFields(OldReservEntry, false)`, takže po přesunu
  položky na jiný řádek zůstává stará.

(2026-09-17, prod-ess-configurator-bc WI 66066 — rozdělení řádku nabídky
s konfigurací; `Sales Line Split Mgt. COEBS.AlignTransferredTrackingVariant`
srovnával jen Surplus, na nabídce tedy nic, a Make Order padal. Zdroje Base
Application 28.3.52162.53506, extrakce z .app.)

**Praktický dopad:** report/factbox „rozpad SN z řádků nabídky" se čte z 337
(+ 336 pro handled) s filtrem `Source Subtype = 0`, žádné vlastní pole na
řádku není potřeba. U Zlomku to sbírá hotová codeunit `Item Tracking Mgt. ZLK`
(`CollectForDocument(Database::"Sales Line", DocType, DocNo, TempBuffer)`,
viz doc 64189 v `cust-zlomek-bc`) — při dalších reportech nad SN nabídky ji
znovu použij, nepiš nový sběr.

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

### 5.x5 Requisition Line — `OnAfterGetDirectCost` jako hook „po přecenění" + past v Req. Wksh.-Make Order (BC 28.3)

- `Requisition Line.GetDirectCost(CalledByFieldNo)` volá standard z OnValidate **8 polí**: `No.`
  (přes `CopyFromItem`), `Vendor No.` (jen když Type = Item, `No.` <> '' a není prod. order),
  `Variant Code`, `Location Code`, `Unit of Measure Code`, `Order Date`, `Currency Code`, `Quantity`.
  Uvnitř `PriceCalculation.ApplyDiscount + ApplyPrice` a `Rec := Line` (přepíše `Direct Unit Cost`
  i `Line Discount %` z ceníků) — jen pro `Replenishment System = Purchase` a ne subcontracting;
  event **`OnAfterGetDirectCost(var Rec, CalledByFieldNo)` se ale volá VŽDY na konci** (i mimo
  Purchase → filtruj sám). `OnBeforeGetDirectCost` s `IsHandled` → OnAfter se nevolá.
- `Quantity (Base)` je při `Validate(Quantity)` spočtené **před** `GetDirectCost` → v subscriberu už sedí.
- `Direct Unit Cost` (10) ani `Line Discount %` (7002) **nemají OnValidate** → `Validate` z subscriberu
  nezpůsobí rekurzi. Base app nemá na Requisition Line obdobu ochrany `BlanketOrderIsRelated`
  z Purchase Line → vlastní cenu musíš po každém `GetDirectCost` obnovit sám.
- ⚠️ `Req. Wksh.-Make Order`: `OnAfterInsertPurchOrderLine(var PurchOrderLine, var NextLineNo,
  var RequisitionLine, var PurchOrderHeader)` běží hned po `PurchOrderLine.Insert()` (bez následného
  Modify — vlastní změny ulož sám), ale **řádek sešitu se maže až ve `FinalizeOrderHeader`** po
  vložení všech řádků téže objednávky (stejný dodavatel/ship-to/měna/purchasing code). Logika, která
  z řádků sešitu počítá „rezervace" (čerpání rámcovky apod.), tak během carry-out vidí souběžně řádek
  sešitu i z něj vzniklý řádek NO → **dvojí započtení** pro další řádky téhož běhu. Fix: po přenosu
  rezervaci na řádku sešitu zrušit (`Modify(false)` na var parametru), nebo vést seznam už
  převedených RecordId.
- `Carry Out Action Msg. - Req.` filtruje jen Worksheet Template Name + Journal Batch Name (celý list,
  `Accept Action Message = true`) → v testech se sdíleným listem se provedou i cizí řádky s Accept.
- Plánování (`Inventory Profile Offsetting`) maže řádky listu po jednom `Delete(true)` →
  `OnAfterDeleteEvent` chodí per řádek (pattern „list prázdný → reset session stavu" funguje).

(2026-08-28, cust-sonnentor-bc PBI 64046 — review větve BlanketOrders_64046.)

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

### 5.x9 Poptávka → Requisition Line → Purchase Line: kde plánování tvoří řádek a jak přenést vlastní pole (BC 28.4)

Vlastní pole z poptávky (Sales Line / Prod. Order Component) se na řádek sešitu požadavků samy nedostanou — každá
cesta vzniku řádku má jiný hook. Ověřeno ve zdrojích Base App 28.4 (cust-alumistr-bc 65774, 2026-09-12):

| Cesta | Kde řádek vzniká | Hook | Vazba |
|---|---|---|---|
| Order Planning (page 5522, Make Orders / Copy to Req. Wksh) | `Requisition Line.TransferFromUnplannedDemand` | table event `OnAfterTransferFromUnplannedDemand(var ReqLine; UnplannedDemand)` — Sales: `Demand SubType` = doc type, `Demand Order No.`/`Demand Line No.`; Production: `Demand SubType` = status, `Demand Order No.` = VZ, `Demand Line No.` = řádek VZ, `Demand Ref. No.` = komponenta | 1:1 |
| Get Sales Orders (report 698, drop shipment / special order) | `InsertReqWkshLine` | `OnBeforeInsertReqWkshLine(var ReqLine; SalesLine; SpecOrder)` | 1:1 |
| Calculate Plan (report 699 / 99001017) | `Inventory Profile Offsetting.MaintainPlanningLine` | `OnMaintainPlanningLineOnBeforeReqLineInsert(var ReqLine; var SupplyInvtProfile; …; var DemandInvtProfile; …)` — poptávka v `DemandInvtProfile."Source Type/Order Status/ID/Ref. No./Prod. Order Line"` (Sales Line: Ref. No. = Line No.; komponenta 5407: Prod. Order Line + Ref. No.) | jen když `SupplyInvtProfile.Binding = "Order-to-Order"` (Reordering Policy Order nebo MTO planning level, `PrepareOrderToOrderLink` + `TransferAttributes`); Lot-for-Lot / ROP agregují víc poptávek → nekopírovat |
| Carry Out (sešit → NO) | `Req. Wksh.-Make Order.InsertPurchOrderLine` | `OnInsertPurchOrderLineOnAfterTransferFromReqLineToPurchLine(var PurchOrderLine; RequisitionLine)` | `Description`/`Description 2` kopíruje base sám v `InitPurchOrderLine`; `TransferFromReqLineToPurchLine` je v 28.4 prázdná obálka jen s eventem |

- `Copy to Req. Wksh` (`Carry Out Action.CarryOutToReqWksh`) dělá `RequisitionLine2 := RequisitionLine` → extension pole
  přejdou sama. Kontrolní guard na `SupplyInvtProfile."Action Message" = New` (jen nové řádky).
- Base Sales Order (42/46/99000883) **nemá** akci „Přenést do sešitu požadavků" — takové akce dodávají jiné appky;
  ptej se, kterou cestu volají, ne po captionu.
- **EPB Pricing Matrix 28.0.3.1** má `Requisition Line PMEBS` (Parameter A/B, Sales Price Var. Code) a v `Price Mgt. PMEBS`
  propagaci Sales Line → Req. Line pro Get Sales Orders + Order Planning (ne pro Calculate Plan) + reverse fill z UoM
  při `TransferFromPurchaseLine/TransLine`. Verze **28.0.3.0 to nemá** → dependency minimum zvedni na 28.0.3.1.
  Ověření obsahu symbolu bez MCP: python `zipfile` na `.app` od offsetu `PK\x03\x04`, `SymbolReference.json` →
  `TableExtensions[].Name` (MS test knihovny mají objekty vnořené v `Namespaces[]`, projdi rekurzivně).
- **EM Net Make to Order (NMEBS)** přidává na Sales Order akci *Transfer Lines to Plan* (CZ „Přenést do sešitu požadavků",
  za akcí Plánování) a na subform *Transfer Line to Plan*: report 64120 `CreateReqLineFromSales NMEBS` →
  `Manufacturing Mgmt. NMEBS.InsertRequisitionLineFromSalesLine` skládá řádek sešitu **sám** (`Insert(false)` + Validate
  No./Variant/Location/UoM/Quantity/Due Date, vazba `Target Order No./Line No./Type NMEBS` + `Sales Production Ref. NMEBS`;
  nákup → Req. template, výroba → Planning template z Manufacturing Setup / User Setup). Žádná standardní cesta výše se nevolá;
  do 28.0.3.0 jen `OnBeforeInsertRequisitionLineFromSalesLine` (IsHandled). Event
  `OnInsertRequisitionLineFromSalesLineOnBeforeRequisitionLineModify(var ReqLine; var SalesLine; var SalesHeader; var Item)`
  před `Modify(false)` přidán 2026-09-12 (větev `ReqLineFromSalesEvent`, čeká na release). Zdroj: sibling repo
  `prod-em-netMakeToOrder-bc`; NMEBS nemá žádné dependencies, takže závislost zákaznické appky na ní je levná.
- Test knihovny BC 28: `Library - Planning` / `Library - Manufacturing` / `Library - Sales` jsou v **Application Test
  Library**, ne v Tests-TestLibraries (tam zbyla jen `Library - Manufacturing OnPrem`). Užitečné: `CalcRequisitionPlanForReqWkshAndGetLines(var ReqLine; var Item; From; To)`,
  `CarryOutReqWksh(var ReqLine; ExpirationDate; OrderDate; PostingDate; ExpectedReceiptDate; YourRef)`,
  `LibraryPurchase.CreateDropShipmentPurchasingCode`, `OrderPlanningMgt.PlanSpecificSalesOrder(var ReqLine; SONo)`,
  `OrderPlanningMgt.SetDemandType("Demand Order Source Type"::"Production Demand") + GetOrdersToPlan(var ReqLine)`.

### 5.x10 Essence Configurator: `Effective Hidden` na `Variant Configuration COEBS` JE persistovaný

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
zdroje prod-em-cuttingPlan-bc master, prod-ess-configurator-bc master.)
