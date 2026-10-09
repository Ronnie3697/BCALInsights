# BC/AL poznámky — Database & Event subscribery

> Část rozděleného `bc-al-notes.md` (rozsekáno 2026-06-23; archiv: `bc-al-notes.archived-2026-06-23.md`).
> Načítej, když řešíš: FindSet/locking, Insert/Modify/Delete, TempBlob/streaming, SetLoadFields, event subscribery.
> Propagace vlastních polí přes posting / archiv / kopii dokladu (3.5–3.6f) je od 2026-09-29 v `bc-al-posting.md`.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **2.** Database operace
- **3.** Event Subscribery — patterny

## 2. Database operace

### 2.1 `FindSet` — bez argumentu pro čtení, `ReadIsolation::UpdLock` pro zápis

- **`FindSet()`** (bez argumentu) — když v cyklu jen **čteš** hodnoty.
  Rychlejší, nedělá zámky pro update.
- **`FindSet(true)`** — historicky pro iteraci s `Modify`/`Delete`. Funguje,
  ale `FindSet(ForUpdate)` overload je postupně označován jako deprecated.
- **Preferovaně v BC 22+ (runtime 11.0+): `Rec.ReadIsolation := IsolationLevel::UpdLock` + `FindSet()`**
  místo `LockTable()`.

**Proč `ReadIsolation` místo `LockTable`:**

`LockTable()` zvedne isolation level pro **celou transakci** vůči té
tabulce — všechna následující čtení přes jakoukoli instanci recordu té
tabulky berou `UPDLOCK`, dokud se necommituje. To je problém zvlášť v
event subscriberech: tvůj `LockTable` ovlivní downstream kód, který o
něm nic neví, a může vyvolat zbytečnou kontentci.

`Record.ReadIsolation := IsolationLevel::UpdLock` zvedne isolation level
**jen pro tu jednu record instanci** — zbytek transakce čte jak by čet
jinak. Per-instance scope = předvídatelný, lokální dopad.

```al
// Čtení — bez argumentu
if SalesLine.FindSet() then
    repeat
        TotalAmount += SalesLine.Amount;
    until SalesLine.Next() = 0;

// Modifikace — preferováno: ReadIsolation::UpdLock per-instance
SalesLine.ReadIsolation := IsolationLevel::UpdLock;
SalesLine.SetRange("Document No.", DocNo);
if SalesLine.FindSet() then
    repeat
        SalesLine."My Flag" := true;
        SalesLine.Modify(false);
    until SalesLine.Next() = 0;
```

**V reportech / dataitem:** `ReadIsolation` se nastavuje v
`OnPreDataItem` na samotném dataitem recordu — runtime pak použije
update lock i při interním načítání záznamů přes dataitem cursor:

```al
dataitem(SalesHeader; "Sales Header")
{
    trigger OnPreDataItem()
    begin
        SalesHeader.ReadIsolation := IsolationLevel::UpdLock;
    end;
    // …
}
```

**Když naopak chceš lock hned na první read** (klasický pattern „get
next entry no" v subscriberu, kde nechceš zámek držet pro celou
transakci — potřebuješ jen ten jeden řádek):

```al
local procedure GetNextEntryNo(): Integer
var
    GLEntry: Record "G/L Entry";
begin
    GLEntry.ReadIsolation := IsolationLevel::UpdLock;
    GLEntry.FindLast();
    exit(GLEntry."Entry No." + 1);
end;
```

**`LockTable()` zůstává validní fallback** pro starší codebase nebo
kdy reálně potřebuješ povýšit isolation pro celou transakci (vzácné).
V novém kódu ale defaultně sahej po `ReadIsolation`.

**Pozn.:** Starší dvouargumentová forma `FindSet(ForUpdate, UpdateKey)` je
v moderním AL zastaralá — nepoužívat. **ALCops FormattingCop FC0005** hlásí přiřazení `Rec.ReadIsolation := …` —
piš **`Rec.ReadIsolation(IsolationLevel::UpdLock);`** (metoda, ne property); příklady výše platí sémanticky. (2026-09-30, cust-soitron-bc)

### 2.2 `Insert` / `Modify` / `Delete` — vždy explicitní argument

Vždy piš **explicitně** `Insert(true)` / `Insert(false)` (a stejně tak
`Modify`, `Delete`), nikdy volání bez argumentu. Čtenář pak na první pohled
ví, jestli triggery mají běžet.

- **`Insert(true)` / `Modify(true)` / `Delete(true)`** — spustí table triggery
  `OnInsert` / `OnModify` / `OnDelete`. Použij, když chceš aby se zapojila
  standardní business logika tabulky (defaultní hodnoty, validace, závislé
  inserty do child tabulek apod.).
- **`Insert(false)` / `Modify(false)` / `Delete(false)`** — přeskočí triggery.
  Použij, když record už je ve stavu, který chceš zapsat, a spuštění triggerů
  by jen přepsalo hodnoty nebo vyvolalo nežádoucí vedlejší efekty (např. v
  event subscriberu po `OnAfterInsertEvent`, v transformaci dat, při účtování
  apod.).

```al
// Standardní business insert — triggery běží
SalesLine.Init();
SalesLine."Document Type" := SalesHeader."Document Type";
SalesLine."Document No." := SalesHeader."No.";
SalesLine.Validate("Line No.", NewLineNo);
SalesLine.Insert(true);

// Propsání vlastního pole v subscriberu — triggery už proběhly, jen uložit
[EventSubscriber(...)]
local procedure OnAfterCreateShpt(var WhseShptLine: Record "Warehouse Shipment Line"; SalesLine: Record "Sales Line")
begin
    WhseShptLine."My Field" := SalesLine."My Field";
    WhseShptLine.Modify(false);
end;
```

**Výjimka — triggery v tableextension:** Uvnitř `trigger OnBeforeInsert` /
`OnAfterInsert` / `OnBeforeModify` **nevolej Insert ani Modify vůbec** (ani
s argumentem) — zápis proběhne automaticky jako součást původní operace.
**Jediná výjimka je `OnAfterModify`** — tam změnu musíš uložit
`Rec.Modify(false)`, jinak se ztratí. Detail a odůvodnění v sekci 3.1.

**Vždy explicitní `RunTrigger` (LinterCop LC0040):** parametr piš na **všech**
build-in metodách, co ho mají — nejen `Insert`/`Modify`/`Delete`, ale i
`DeleteAll`/`ModifyAll`. Bez argumentu = LC0040 warning.

```al
TempBuffer.DeleteAll(false);
TempBuffer.Insert(false);
```

**U temporary tabulek/bufferů preferuj `false`**, pokud triggery vyloženě
nepotřebuješ — temp záznam stejně nejde do DB, a `true` by zbytečně pálil
table triggery (a u některých scénářů hrozí, že omylem rozjedeš
nontemporary side-effect přes subscriber). `true` použij jen na **reálné**
(nontemporary) tabulky, kde chceš standardní business logiku (defaulty,
validace, child inserty).

### 2.3 `TempBlob` a streaming — preferuj `Codeunit "Temp Blob"`

Pro práci s binárními daty (PDF, XML, JSON exports) nepoužívej
`Record TempBlob temporary` (zastaralé), ale `Codeunit "Temp Blob"`:

```al
var
    TempBlob: Codeunit "Temp Blob";
    OutStr: OutStream;
    InStr: InStream;
begin
    TempBlob.CreateOutStream(OutStr, TextEncoding::UTF8);
    OutStr.WriteText(JsonContent);

    TempBlob.CreateInStream(InStr, TextEncoding::UTF8);
    DownloadFromStream(InStr, '', '', '', 'export.json');
end;
```

**Proč:** Codeunit API je čistší (žádný overhead s temp recordem), funguje
v cloud / SaaS bez problémů a je preferované MS od BC 18+. Starý
`Record "TempBlob"` je v base appce stále, ale označený jako legacy.

### 2.4 `SetLoadFields()` — pro read-only čtení na širokých tabulkách

Když ze široké tabulky (Item, Customer, Sales Line, Job Ledger Entry…) potřebuješ
jen pár polí, **dej `SetLoadFields(...)` před `FindSet`/`FindFirst`/`Get`**. SQL
roundtrip se zúží na ta pole + primární klíč, místo tahání celého recordu.

```al
SalesLine.SetLoadFields("Document No.", "Line No.", "No.", "Quantity");
SalesLine.SetRange("Document No.", DocNo);
if SalesLine.FindSet() then
    repeat
        TotalQty += SalesLine.Quantity;
    until SalesLine.Next() = 0;
```

**Pravidla:**

- Funguje od BC 20. Bez `SetLoadFields` se táhnou všechny fields (i FlowFields kde
  jsou ve view, BLOBy ale pořád lazy).
- Když pak v cyklu sáhneš na pole, které jsi nezahrnul, runtime ho dotáhne extra
  SQL roundtripem — zruší tím benefit. Při refaktoru kódu **zkontroluj
  `SetLoadFields` list**, pokud přibyla referencovaná pole.
- **Nepoužívat**, když děláš `Modify` — chybí ti pak load polí pro replikaci.
  V `Modify` scénáři buď `SetLoadFields` neaplikuj, nebo si zavolej `Get`
  bez něj (nebo použij dedikovaný cyklus pro update).

### 2.5 `SetFilter` — wildcard `*` + placeholder `%1` = LC0050; bezpečné separátory

Když potřebuješ **„contains" filtr s dynamickou hodnotou**, **nikdy** nepiš wildcard
přímo k placeholderu v argumentu `SetFilter`:

```al
// ŠPATNĚ — LinterCop LC0050. Placeholder se s '*' nenahradí správně → nečekané chování.
Item.SetFilter("Webshop Filter SON", '*%1*', Token);
```

Wildcard operátory (`*`, `?`, `@`) zkombinované s `%1`/`%2` v `SetFilter` filter
expression jsou buggy. Sestav celý string **přes `StrSubstNo` PŘED** `SetFilter`:

```al
// SPRÁVNĚ — string hotový, SetFilter dostane '*~CZ~*', wildcard funguje.
Item.SetFilter("Webshop Filter SON", StrSubstNo('*%1*', Token));
```

(Stejné platí pro `@*%1*`, `??%1*` atd.) Pozor: `StrSubstNo` hodnotu **nefilter-escapuje**
— vloží ji doslova. Pokud může obsahovat filter operátor, musíš ji ošetřit sám.

**Bezpečné separátory pro multi-value string v jednom poli** (storage `~A~B~`, filtr
`*~A~*`): povolené filter operátory jsou jen **`< > & | = .. * ? @ ( ) <>`** (a `'...'`
pro literály) — viz MS Learn „Filter on values that contain symbols". Jako oddělovač
ber znak **mimo** tenhle seznam: **`~`** je ideál (není operátor, v Code polích se
nevyskytuje). `|` je OR, `&` je AND, `,`/`..` taky operátory → jako separátor je nepoužívej.

### 2.6 Copy-loop s `TransferFields(Source, false)` — VŠECHNA PK pole nastavit explicitně, každou iteraci

Dvě AL zákeřnosti, které se v kopírovací smyčce sečtou do runtime chyby „record already exists":

- **`TransferFields(Source, false)`** nepřenáší **žádné** pole primárního klíče.
- **`Init()`** PK pole **nečistí** — nechá v bufferu hodnoty z předchozí iterace
  (včetně `Line No.` doplněného OnInsert triggerem!).

Důsledek: pokud PK obsahuje i „nenápadná" pole (enum `Result Type`, `Line No.`…)
a nastavíš po TransferFields jen část PK, zbytek PK se tiše recykluje z minulé
iterace → druhý Insert spadne na duplicitním klíči (nebo hůř — projde se špatným
scope a data „zmizí" z filtrovaných subpages).

```al
// Pattern: po Init + TransferFields(,false) přiřaď VŠECHNA PK pole, ne jen ta „hlavní"
NewRec.Init();
NewRec.TransferFields(SourceRec, false);
NewRec."Configuration No." := NewConfigNo;    // PK 1 (remap)
NewRec."Parameter Line No." := NewParamLineNo; // PK 2 (remap)
NewRec."Condition Line No." := NewCondLineNo;  // PK 3 (remap)
NewRec."Result Type" := SourceRec."Result Type"; // PK 4 — BEZ tohohle zůstane ' ' / stará hodnota!
NewRec."Line No." := SourceRec."Line No.";       // PK 5 — BEZ tohohle zůstane Line No. z minulé iterace!
NewRec.Insert(true);
```

Před psaním copy procedury si **otevři definici PK cílové tabulky** a odškrtej
pole jedno po druhém. (Zachyceno 2026-07, prod-ess-configurator-bc:
`CopyConditionResultValues` — PK má 5 polí, nastavovala se 3 → kolize na
`Line No.` 10000 + `Result Type` ' '.)

Recidiva 2026-09-09 (tentýž repo, `CopyTextFormulaLinesForLine`): PK `Text Formula Line` má 6 polí, kopie nastavila 5 —
enum `Field Type` (PK) zůstal ' ' → kopie „proběhla", ale řádky skončily pod prázdným typem pole a test hledající
`Field Type = Search Name` našel 0 (master buildy 28149/28157). Zrádné: žádná chyba, s jedním typem pole ani kolize
klíče; dvě skupiny formulí by se srazily na `Line No.` 10000. Při review copy kódu porovnej **každé** přiřazení po
`TransferFields(…, false)` s PK — enum/option PK pole se přehlédnou nejsnáz.

Recidiva 2026-10-09 (prod-ess-dotykackaConnector-bc, `Sync Log.LogRun` — temp buffer detailů → reálná tabulka s
**`AutoIncrement`** `Entry No.`): `Init()` + `TransferFields(Temp, false)` + `Insert` ve smyčce na jedné proměnné → první
řádek dostal číslo z AutoIncrementu, druhý si ho po `Init()` nesl dál a spadl na *„The record … already exists. Entry No.='1'"*.
AutoIncrement přiděluje číslo **jen při 0** — před `Insert` vždy `"Entry No." := 0`. Test s jedním řádkem bufferu to neodhalí,
až dva řádky (lokální kontejner, 2 z 97 testů).

### 2.6a Remap helper s „chybí v mapě → vynuluj" — projdi VŠECHNY volající a jejich mapy

Když sdílený remap helper (`TryRemapParamLineNo(var Field, Mapping)`) přepneš z „není v mapě → nech" na „není v mapě
→ 0" (správně: kopie čísluje bez mezer, osiřelý odkaz by se tiše chytil cizího záznamu), pohlídej **každého volajícího
a jak si mapu staví**. Kopie celé konfigurace má mapu úplnou, ale kopie **jednoho záznamu v téže konfiguraci**
(`CopyParameter`) si do mapy dávala jen `zdroj → nový` a spoléhala na „nech" — odkazy na ostatní, existující parametry
najednou skončily jako 0 (master build 28221, test `CopyParamReplicatesConditions`, 2026-09-14). Fix: doplnit do mapy
identitu `X → X` pro všechny ostatní záznamy konfigurace (`AddIdentityMappingOfOtherParameters`), helper má jednu
sémantiku. Lokální kompilace to neodhalí — teprve testy; proto při změně sémantiky helperu grep na jeho jméno **i na
místa, kde se mapa plní** (`.Add(`), ne jen na volání.

### 2.6b `Mark`/`MarkedOnly` + `Record.Copy` — nespoléhat, že marks přejdou na kopii

Když engine označí záznamy (`Mark(true)` + `MarkedOnly(true)`) a pak pro dílčí hledání dělá `Other.Copy(Rec)`
a hledá v `Other`, hrozí, že **marks na kopii nejsou** (`Copy` bez `ShareTable` přenáší filtry, klíč a stav
`MarkedOnly`, o mark bufferu dokumentace mlčí — code review 2026-09-01 to označil za ztrátu marks, kopie by pak
s `MarkedOnly = true` nenašla nic). `ShareTable = true` je jen pro temporary recordy. Bezpečný vzor: dílčí filtry
a `SetCurrentKey` dělat **na téže instanci**, výsledek si odnést přiřazením (`Found := Rec`) a dočasné filtry
po hledání zase `SetRange(pole)` sundat. Alternativa `SetFilter(Code, 'A|B|…')` místo marks škáluje špatně
(stovky hodnot → dlouhý filtr). (prod-epb-pricingMatrix-bc `FindUoMByMode`, 2026-09-01.)

### 2.6c Trvalý filtr na pole, které helper filtruje dočasně — dej ho do vlastní `FilterGroup`

Když helper nad předanou instancí nastavuje na **stejné pole** dočasné filtry (`SetFilter(Pole, '<%1', x)`) a po hledání
je sundává `SetRange(Pole)`, trvalý filtr volajícího na tom poli **přepíše první `SetFilter` a smaže první `SetRange`** —
ve skupině 0 má pole jen jeden filtr. Řešení bez zásahu do helperu: trvalou podmínku nastav v jiné filter group
(`Old := Rec.FilterGroup(); Rec.FilterGroup(10); Rec.SetFilter(Pole, '<>%1', 0); Rec.FilterGroup(Old);`). Filtry různých
skupin platí současně (AND) a `SetFilter`/`SetRange` ve skupině 0 skupinu 10 nevidí; `MarkedOnly` na instanci zůstává.
Skupiny **−1..7 používá platforma** (4 = SubPageLink, 7 = factboxy, −1 = OR napříč sloupci), max 255 (MS Learn
`Record.FilterGroup`) → ber 10+. (prod-epb-pricingMatrix-bc `FilterUoMsWithAxisValues`, PBI 66358, 2026-09-24 — MJ bez os
se nesměly dostat do zaokrouhlovacích fallbacků `FindUoMByMode`.)

**Totéž s `RecordRef`: `SetView(<uložený filtr>)` + `FldRef.SetRange(hodnota)` na stejném poli = uložený filtr je pryč.**
Typicky „existuje hodnota pod filtrem z nastavení?" (filtr z `FilterPageBuilder` / pole *Table Filter* + `SetRange` na
lookup pole): když uložený filtr míří na totéž pole, `SetRange` ho přepíše a projde každá existující hodnota. Fix: po
`SetView` `RecRef.FilterGroup(10)` a teprve pak `FldRef.SetRange` (`FieldRef` filtruje v aktuální skupině svého `RecordRef`);
každý další nezávislý filtr (atributy, …) do vlastní skupiny. Kompilace ani analyzery nic nehlásí, chytí to jen test, kde
filtr a hledané pole splývají. (cust-zlomek-bc `Nested Cfg Runtime COZLK.TableLookupValueExists`, master build 28453,
2026-09-24; stejný vzor v COEBS `ValidateTableLookupValue` — detail C5 v `ess-configurator-notes.md`.)

**Sdílený helper, který přidává filtr na cizí `RecordRef` (typicky „filtr atributů → `Item."No."`"), ať si skupinu přepne
sám:** `Old := RecRef.FilterGroup(); RecRef.FilterGroup(10); FldRef := RecRef.Field(…); FldRef.SetFilter(…); RecRef.FilterGroup(Old);`.
Oprava na jednom místě spraví všechny volající (i ty v cizích větvích / appkách, které helper volají) a volající, kteří si skupinu
nastavují sami, dostanou stejný výsledek. Test: filtr volajícího na stejném poli + helper → `Count()` pod oběma filtry a
`RecRef.FilterGroup() = 0` po návratu. (2026-09-29, prod-ess-configurator-bc 65364, `Item Attr. Filter Mgt.ApplyToRecRef`.)

**`SetView` s polem, které tabulka nemá, chybu NEhodí** — `RecRef.SetView('WHERE(No Such Field COEBS=CONST(X))')` proběhne
a filtr na tom poli se tiše neuplatní. Chybu dá jen text, který vůbec není pohledem tabulky (`'BADDATA'` — tak to testuje MS
`CRM Synch. Job Scenarios.SynchInvalidViewCausesError`, chyba vzniká v `IntegrationRecordSynch.SplitTableFilter` na `SetView`).
Důsledky: (1) `[TryFunction] TrySetView` jako „je filtr z nastavení platný?" neodhalí přejmenované / smazané pole ani filtr
uložený s captiony v jiném jazyce — filtr jen potichu zmizí a lookup / kontrola pustí víc hodnot; (2) test větve „filtr nejde
použít" potřebuje nesmyslnou syntaxi, ne neexistující pole — a předpoklad ověř v GIVEN přes vlastní `[TryFunction]` +
`Assert.IsFalse(…, 'SetView must reject the filter…')`, ne holým `asserterror` (ten při špatném předpokladu vrátí jen
*An error was expected inside an ASSERTERROR statement*). (2026-09-29, prod-ess-configurator-bc master build 28532, test
`ValidateTableLookupValueLeavesOutFilterThatCannotBeApplied`; oprava větev `65364_InvalidViewTestFix`.)

### 2.7 Nové flag/marker pole → projít i field-by-field copy procedury (šablony, buffery)

Když do tabulky přidáváš nové pole (typicky Boolean marker jako `Has Value` /
`Has Default Value`), cesty přes `TransferFields` ho vezmou samy — ale **ruční
field-by-field kopie do JINÉ tabulky** (šablona, buffer, mirror) ho tiše
vynechají a k tomu často chybí i samotné pole v cílové tabulce. Grep na název
zdrojové tabulky v copy codeunitách + přidat: pole v mirror tabulce (stejné
field ID), přiřazení v obou směrech kopie, field na service/Svc stránce, XLIFF.
Field hash v trans-unit ID závisí jen na jménu pole → stejné jméno v jiné
tabulce = stejný Field hash, mění se jen Table hash (ověř proti `.g.xlf`).
(2026-08-20, prod-ess-configurator-bc: `Has True Default Value` chybělo v
`Param. Tmpl. Condition` — podmínkový default 0 se ztrácel round-tripem šablonou.)


### 2.8 `TableRelation` na pole mimo primární klíč cílové tabulky — kompiluje, ale `Validate` za běhu spadne

`field(20; "Main Parameter Code"; Code[20]) { TableRelation = "Configuration Parameter COEBS"."Parameter Code" where("Configuration No." = field("Main Config. No.")); }`
projde `alc` i všemi analyzery (CodeCop, PTE, UICop, ALCops) bez varování. Jakmile ale uživatel do pole
zapíše hodnotu (nebo kód zavolá `Validate`), BC hodí *„Následující pole musí být zahrnuto do primárního klíče
tabulky: Pole: Kód parametru Tabulka: Configuration Parameter COEBS"* (EN „The following field must be included
in the table's primary key…"), protože kontrola relace hledá záznam **přes primární klíč**. `Parameter Code` tam
má jen sekundární klíč (`CodeKey`), PK je `Configuration No.` + `Line No.`.

- **Relace smí mířit na pole PK cílové tabulky** (typicky poslední pole PK + `where` na ta předchozí, vzor
  `"Item Variant".Code where("Item No." = field(...))`). Na „čitelný" kód mimo PK relaci nedávej.
- **Když uživatel má zadávat kód mimo PK:** pole bez `TableRelation`, lookup přes `OnLookup` na page fieldu
  (vlastní list page / `LookupMode` + `GetRecord`) a existenci ověř v `OnValidate` sám (`SetRange` + `FindFirst` +
  srozumitelný `Error`). Druhá možnost: ukládat PK pole (`Line No.`) s relací a kód jen zobrazovat.
- Test přes `Rec.Validate(pole, kód)` to chytí (spadne stejně), jen kompilace ne. (2026-09-23, cust-zlomek-bc 65364,
  `Param Selection Buffer COZLK` — okno Převzít parametry na BC-DEV2.)

---

## 3. Event Subscribery — patterny

### 3.1 Tableextension triggery vs event subscribery

V tableextension preferuj triggery `OnBefore*` / `OnAfter*` (`OnBeforeInsert`,
`OnAfterInsert`, `OnBeforeModify`, `OnAfterModify`) před ekvivalentními event
subscribery (`OnAfterInsertEvent`…), pokud logika patří k dané tabulce a stačí
ti upravit vlastní pole.

**Proč:**

- Triggery v tableextension běží jako součást původní Insert/Modify operace.
  Přiřazení do polí se ve většině případů zapíše s tou operací **automaticky**,
  ale **OnAfter* triggery mají háček** — viz níže.
- Kód patří přímo k tabulce, je v kontextu a nemusí se hledat v codeunitě.

**Volat / nevolat Insert/Modify uvnitř triggerů — podle typu:**

- **`OnBeforeInsert` / `OnBeforeModify`** — trigger běží **před** DB zápisem.
  Přiřazení do polí jde s tou operací automaticky. **Nevolat** `Insert()` /
  `Modify()`.
- **`OnAfterInsert`** — DB Insert už proběhl, ale runtime obvykle změny v `Rec`
  z triggeru zachytí a uloží jako součást Insertu. **Nevolat** `Insert()`.
- **`OnAfterModify`** — DB Modify už proběhl. Když v triggeru měníš pole na
  **stejném** `Rec` a chceš to uložit, **musíš explicitně volat
  `Rec.Modify(false)`** — jinak změna zůstane jen v paměti a do DB se
  nezapíše. Použij `Modify(false)`, ne `Modify(true)` — vyhneš se rekurzi
  zpátky do OnAfterModify.

```al
trigger OnAfterModify()
begin
    if SomeCondition() then begin
        Rec."Flag ZLK" := true;
        Rec.Modify(false); // bez tohohle se Flag ZLK do DB nedostane
    end;
end;
```

**Kdy naopak použít event subscriber (`OnAfterInsertEvent` apod.):**

- Když je logika cross-cutting nebo zasahuje do jiné domény (např. propagace
  pole ze Sales Header do Item Ledger Entry při účtování — viz 3.5 v `bc-al-posting.md`)
- V subscriberu je `Rec` už zapsaný v DB (u `OnAfter*Event`), takže pokud
  zapisuješ do polí, **musíš volat `Modify()`**
- Nezapomeň na `IsTemporary()` check (viz 3.2)

**Příklad — auto-fill Assigned User ID:**

```al
tableextension 52316 "Sales Header ZLK" extends "Sales Header"
{
    trigger OnAfterInsert()
    begin
        if "Assigned User ID" = '' then
            "Assigned User ID" := CopyStr(UserId(), 1, MaxStrLen("Assigned User ID"));
        // NEvolat Modify() — zapíše se s původním Insertem
    end;
}
```

### 3.2 `IsTemporary()` check v subscriberech

Když v subscriberu **zapisuješ do recordu** (`Modify`, `Insert`, validace s
efektem), hned na začátku testuj `IsTemporary()` a exitni:

```al
[EventSubscriber(...)]
local procedure MySub(var ItemJournalLine: Record "Item Journal Line")
begin
    if ItemJournalLine.IsTemporary() then
        exit;
    // ... vlastní logika
end;
```

**Proč:** Subscriber se volá pro všechny instance recordu včetně temporary.
Modify na temporary recordu neudělá nic užitečného v DB, ale může zmást
volající kód, který si temp record dočasně použil jako buffer. Typický
pattern: volající vytvoří dočasný Item Journal Line, volá nějakou Validate
nebo Insert, a subscriber by ten buffer "zmodifikoval" místo reálného recordu.

**Kdy NE:** V čistě read-only subscriberech, kde jen čteš hodnotu a nic
nezapisuješ, check není nutný.

### 3.3 `OnAfterValidateEvent` — init detection patterny

V `OnAfterValidateEvent` často potřebuješ rozeznat, jestli `Rec` je nově
inicializovaný (právě probíhá `Init` / `Insert`) nebo už existující záznam,
který user mění:

```al
// Nový záznam bez SystemId (před Insert)
if IsNullGuid(Rec.SystemId) then
    exit;

// Záznam bez primárního klíče (typicky Sales Header před přiřazením No.)
if Rec."No." = '' then
    exit;

// Temporary buffer
if Rec.IsTemporary() then
    exit;
```

**Proč:** Validate triggery se volají i při hromadném plnění polí v `Init()` /
pre-Insert sekvenci. Když subscriber dělá `Modify`, `LookupNo` nebo cross-table
updaty, dostaneš se do nekonečné rekurze nebo "Record does not exist" errorů.
Pojistka na začátku subscriberu = dvě řádky kódu, které ušetří hodiny debugu.

### 3.4 `SkipOnMissingLicense` / `SkipOnMissingPermission` — default `false, false`

Atribut `[EventSubscriber(ObjectType, ObjectID, EventName, ElementName, SkipOnMissingLicense, SkipOnMissingPermission)]`
má dvě poslední Boolean pozice — co se má stát, když uživatel, který triggeruje
event, **nemá licenci** nebo **permission** na objekt subscriberu:

- **`false, false`** — subscriber **vyhodí chybu**. Volající operace failne
  viditelně. Bug v permission setupu se ozve hned, ne až o tři měsíce později
  jako "podivná datová nekonzistence".
- **`true, true`** — subscriber se **tiše přeskočí**. Volající operace běží
  dál, jakoby žádný subscriber nebyl. Žádný error, žádný log.

**Pravidlo palce:**

- **Důležitá business logika** → `false, false`. Sales posting propagace pole,
  validace, kontrola dat, recalc statusu — když to neproběhne, máš nekonzistentní
  data. Lepší, ať to v sandboxu hned spadne s "permission missing", než aby ti
  to potichu propustilo špatný stav do prod DB.
- **Triviální / kosmetické věci** → `true, true`. Plnění info-only pole,
  cuegroup countů, telemetrie eventy, defaultní hodnoty na UI, kde uživatel
  bez permission stejně nic dál neudělá.

```al
// Důležité — propagace pole při účtování. Pokud user nemá rights, ať padne.
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnPostItemJnlLineOnAfterPrepareItemJnlLine, '', false, false)]
local procedure PropagateMyFieldToILE(...) begin ... end;

// Triviální — vyplnění info pole na UI při Init. Když user nemá rights, no big deal.
[EventSubscriber(ObjectType::Table, Database::"Sales Header", OnAfterInitRecord, '', true, true)]
local procedure SetCosmeticDefault(...) begin ... end;
```

> **Pozn.:** Starší poznámky a code style v tomhle projektu měly default
> `true, true`. **Nový kód piš s `false, false`**, a když potkáš `true, true`
> v existujícím subscriberu na critical-path logice, přepiš ho při průchodu.

### 3.5–3.6f → vyčleněno do `bc-al-posting.md`

Propagace vlastních polí do účtovaných dokladů, archivu a kopií (3.5 Sales posting + Warehouse Shipment,
3.6 kompletní rozšíření Header/Line, 3.6b `Validate("No.")` → `Init()`, 3.6c Blob + `CalcFields`, 3.6d kontrola
dokladu před účtováním, 3.6e guard na `OnModifyRecord`, 3.6f Job No. dodávka vs. faktura) žije od 2026-09-29
ve skillu `bc-al-posting` (soubor `bc-al-posting.md`). Číslování zůstalo.

### 3.7 `[EventSubscriber]` argumenty — identifier syntax, ne string literály (LC0028)

V moderním AL piš event name i element name (field/action) v atributu
`[EventSubscriber(...)]` jako **identifikátory**, ne string literály. LinterCop
to vynucuje přes **LC0028** („Event subscriber arguments now use identifier
syntax instead of string literals").

```al
// Staře — string literály
[EventSubscriber(ObjectType::Table, Database::"Item Journal Line", 'OnAfterValidateEvent', 'Operation No.', false, false)]
[EventSubscriber(ObjectType::Page, Page::"Output Journal", 'OnAfterActionEvent', 'Post', false, false)]

// Moderně — identifikátory (mezery/tečky → quoted identifier; prázdný element zůstává '')
[EventSubscriber(ObjectType::Table, Database::"Item Journal Line", OnAfterValidateEvent, "Operation No.", false, false)]
[EventSubscriber(ObjectType::Page, Page::"Output Journal", OnAfterActionEvent, Post, false, false)]
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post", OnBeforeCode, '', false, false)]
```

- Event name (3. arg) i element name (4. arg) → identifier. Mezery/tečky/spec.
  znaky vyžadují quoting (`"Operation No."`), jednoduchý název ne (`Post`).
- **Prázdný element** (`''`) zůstává prázdný string — prázdný identifier není.
- Výhoda: compiler/IntelliSense ověří, že event a field/action reálně existují
  (string literál se nekontroluje → překlep odhalíš až runtime).

### 3.8 Deprecated event/metoda při BC upgrade (AL0432) — ověř novou cestu, nehádej

Při upgradu na vyšší BC compiler hlásí `AL0432: Method 'X' is marked for
removal. Reason: Moved to ...; Tag: NN.0.`. Reason text říká **kam** se to
přesunulo — ale přesný object name a signaturu **ověř v symbolech** (al-mcp
`al_search_object_members` / `al_get_object_definition`), ne z hlavy.

Typický vzor BC27/28 — **manufacturing refactoring** rozsekal velké codeunity
do `Mfg. *` objektů a část metod přesunul na tabulky:
- event `OnAfterTransferRtngLine`: `Codeunit "Planning Line Management"` →
  `Codeunit "Mfg. Planning Line Management"` (signatura zůstala).
- metoda `NextOperationExist`: `Codeunit "Item Jnl.-Post Line"` (brala
  `ProdOrderRtngLine` parametrem) → **tabulka** `"Prod. Order Routing Line"`
  (bez parametru, operuje nad Rec): `ProdOrderRoutingLine.NextOperationExist()`.

Po opravě subscriberu na nový codeunit zkontroluj i **název procedury**
subscriberu (ať odráží nový zdroj) a smaž osiřelé `var` proměnné po přesunu
metody na tabulku. (2026-06, `prod-em-operOutputChaining-bc`, BC28.)

### 3.9 Tableextension gotchas: `modify()` patří do `fields {}`, klíč smí mít jen vlastní pole, globální `var` jako guard

- **`modify("Pole") { trigger OnAfterValidate() ... }` musí být UVNITŘ bloku `fields { }`** tableextensionu
  (vedle `field(...)`), ne na úrovni objektu za ním — jinak kaskáda `AL0198` („Expected one of the application
  object keywords…"), `AL0104` („'}' expected") a `AL0114` („integer literal expected"), která na první pohled
  nevypadá jako chyba umístění.
- **Klíč v tableextension smí obsahovat jen pole té extension.** `key(X; "Item No.", "My Field")` s base polem =
  `AL0423: The property 'X' can only be set if the specified fields are from the same table`. Řešení: klíč jen
  z vlastních polí + `SetRange` na base pole + `SetCurrentKey(vlastní pole)`; SQL si poradí (index bez base
  pole), u malých tabulek OK. Temporary record ten klíč pro in-memory řazení používá taky.
- **Globální `var` v tableextension je per instance recordu a přežije vnořené `Validate`** → hodí se jako guard
  proti smyčce „OnValidate pole A → `Validate(UoM)` → modify-trigger UoM → přepis pole A": flag nastavit před
  `Validate`, shodit po něm, modify-trigger na flag jen exituje. Guard přes `CurrFieldNo` **nefunguje**, když
  pole validují jiné appky z kódu (`CurrFieldNo = 0`, typicky konfigurátory).

(2026-09-01, prod-epb-pricingMatrix-bc task 65842 — reverse fill Parametr A/B ↔ Item Unit of Measure.)

- **`xRec` v `OnModify` / `OnBeforeModify` / `OnAfterModify` (i `OnBeforeModifyEvent`) je při `Rec.Modify(true)` z kódu
  SHODNÝ s `Rec`** — předchozí hodnoty dodá jen stránka (Kauffmann „How to get a reliable xRec", 2023; GitHub
  microsoft/AL #3366). Change-detection `if Rec.Quantity <> xRec.Quantity then …` v modify triggeru tak z kódu nikdy
  nezabere; testy přes `TestPage.SetValue` projdou, testy přes `Rec.Validate + Modify(true)` ne (a `Sales Line.OnModify`
  base používá xRec jen jako UI pojistku, ne důkaz, že funguje z kódu). **Vzor:** v `OnBeforeModify` načti uloženou verzi
  (`Old.SetLoadFields(pole); Old.Get(PK)` — DB má před zápisem ještě starý stav) do globální proměnné tableextension /
  instance codeunitu a v `OnAfterModify` porovnej `Rec` proti ní (po zápisu už `Get` vrátí nové hodnoty). Field
  `OnValidate` je jiný případ: tam `xRec` = stav před `Validate` i z kódu. Zachyceno 2026-09-08, prod-ess-configurator-bc
  build 28149 (`Sales Line COEBS.OnAfterModify`, 15 červených testů; testy před merge neběžely).

- **Vazební tabulka (link), jejíž trigger zapisuje do master záznamu, + master `OnValidate`, který ten link zakládá =
  „záznam změnil jiný uživatel".** Vzor: `Customer."CRM Business Unit SOI".OnValidate` → codeunit vloží řádek do
  `Customer CRM Business Unit SOI` (`Insert(true)`) → `OnInsert` linku udělá `Customer.Get + Modify` přes **druhou
  proměnnou** → karta pak uloží své `Rec` se starým timestampem a spadne (nebo přepíše hodnotu, kterou trigger zapsal).
  Řešení, které drží obě cesty: (a) link-originované změny (page linku, API) jdou přes triggery linku (`OnInsert/
  OnModify/OnDelete/OnRename` → `Master.Get` + `SetXxx` + `Modify(true)`); (b) master-originovaná cesta dostane **`var
  Master`**, link zapíše **`Insert(false)`/`Modify(false)`** (triggery přeskočí, komentář proč) a hodnotu nastaví **do
  paměti** předaného recordu — uloží ji volající (karta, Dataverse sync `Modify`). Signaturu `(No, Id)` změň na
  `(var Rec)`, ať se in-memory část nedá zapomenout; volající, kteří dřív `Modify` volali před syncem, přesuň za něj.
  Před-triggery (`OnInsert/OnDelete/OnRename`) běží **před** DB zápisem, takže „přepočítej vše z DB" tam nefunguje —
  dělej cílený zápis (`OnRename`: vyčisti `xRec` slot, nastav `Rec` slot). (2026-09-22, cust-soitron-bc, Business Unit 1-5.)

---
