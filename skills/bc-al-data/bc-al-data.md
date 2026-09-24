# BC/AL poznámky — Database & Event subscribery

> Část rozděleného `bc-al-notes.md` (rozsekáno 2026-06-23; archiv: `bc-al-notes.archived-2026-06-23.md`).
> Načítej, když řešíš: FindSet/locking, Insert/Modify/Delete, TempBlob/streaming, SetLoadFields, event subscribery, propagaci vlastních polí přes posting.
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
v moderním AL zastaralá — nepoužívat.

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
  pole ze Sales Header do Item Ledger Entry při účtování — viz 3.5)
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

### 3.5 Propagace vlastního pole přes Sales posting + Warehouse Shipment

Typický zákaznický pattern: vlastní pole na Sales Line se musí propsat do
Item Ledger Entry a/nebo Warehouse Shipment Line.

**Sales Line → Item Journal Line (při účtování)** — event v `Sales-Post`
(Codeunit 80):

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnPostItemJnlLineOnAfterPrepareItemJnlLine, '', false, false)]
local procedure SalesPost_OnPostItemJnlLineOnAfterPrepareItemJnlLine(var ItemJournalLine: Record "Item Journal Line"; SalesLine: Record "Sales Line")
begin
    if ItemJournalLine.IsTemporary() then
        exit;
    ItemJournalLine."My Field" := SalesLine."My Field";
end;
```

**Item Journal Line → Item Ledger Entry (při účtování)** — event v
`Item Jnl.-Post Line` (Codeunit 22):

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Line", OnAfterInitItemLedgEntry, '', false, false)]
local procedure ItemJnlPostLine_OnAfterInitItemLedgEntry(var NewItemLedgEntry: Record "Item Ledger Entry"; var ItemJournalLine: Record "Item Journal Line"; var ItemLedgEntryNo: Integer)
begin
    if NewItemLedgEntry.IsTemporary() then
        exit;
    NewItemLedgEntry."My Field" := ItemJournalLine."My Field";
end;
```

**Sales Line → Warehouse Shipment Line (při vytváření shipmentu)** — event v
`Sales Warehouse Mgt.` (Codeunit 5991):

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales Warehouse Mgt.", OnAfterCreateShptLineFromSalesLine, '', false, false)]
local procedure SalesWarehouseMgt_OnAfterCreateShptLineFromSalesLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header")
begin
    WarehouseShipmentLine."My Field" := SalesLine."My Field";
    WarehouseShipmentLine.Modify(false);
end;
```

> **Proč NE `OnAfterCreateShptLine` v `Whse.-Create Source Document` (Codeunit 5750)?**
> Signature: `OnAfterCreateShptLine(var WarehouseShipmentLine)` — Sales Line
> tam **není jako parametr**. Musel bys Sales Line dohledávat z DB přes
> Source Type/No./Line No. — zbytečně složité.
> `OnAfterCreateShptLineFromSalesLine` má přímo `SalesLine` i
> `WarehouseShipmentLine` jako parametry.

**Poznámky:**

- `Modify(false)` u Warehouse Shipment Line je nutné — `OnAfterCreateShptLineFromSalesLine`
  se volá **po** Insert()
- Codeunit s těmito subscribery: `EventSubscriberInstance = StaticAutomatic`
- Stejný pattern funguje analogicky pro Purchase Line → Purchase Receipt
  (`OnAfterPurchRcptLineInsert`, …) a Purchase Line → Warehouse Receipt Line
  (události v `Whse.-Create Source Document` nebo `Purch. Warehouse Mgt.`)

### 3.6 Vlastní pole na Sales/Purchase Header/Line — kompletní rozšíření

Když přidáš vlastní pole na `Sales Header` nebo `Sales Line` (případně
`Purchase Header` / `Purchase Line`), **nezapomeň ho rozšířit i na archive a
posted dokumenty** — jinak se data ztratí ve chvíli, kdy se dokument
zaarchivuje nebo zaúčtuje.

#### Sady tabulek, které musíš pokrýt

**Sales — header:**

- `Sales Header` (36) — zdroj
- `Sales Header Archive` (5107) — archive při Release/Reopen/Delete
- `Sales Invoice Header` (112) — posted invoice
- `Sales Cr.Memo Header` (114) — posted credit memo
- `Sales Shipment Header` (110) — posted shipment
- `Return Receipt Header` (6660) — posted return receipt

**Sales — line:**

- `Sales Line` (37) — zdroj
- `Sales Line Archive` (5108)
- `Sales Invoice Line` (113)
- `Sales Cr.Memo Line` (115)
- `Sales Shipment Line` (111)
- `Return Receipt Line` (6661)

**Purchase — header:**

- `Purchase Header` (38)
- `Purchase Header Archive` (5109)
- `Purch. Inv. Header` (122)
- `Purch. Cr. Memo Hdr.` (124)
- `Purch. Rcpt. Header` (120)
- `Return Shipment Header` (6650)

**Purchase — line:**

- `Purchase Line` (39)
- `Purchase Line Archive` (5110)
- `Purch. Inv. Line` (123)
- `Purch. Cr. Memo Line` (125)
- `Purch. Rcpt. Line` (121)
- `Return Shipment Line` (6651)

> **Tip:** Stejné field ID použij ve **všech** tabulkách dané sady — kód
> propagace pak může být šablonový (kopírovat field-by-field bez mapování).

> **⚠️ `AutoFormatExpression` u Decimal polí na posted řádcích:** `Sales Invoice Line` a `Sales Cr.Memo
> Line` **nemají pole `Currency Code`** (žije na hlavičce) — `AutoFormatExpression = Rec."Currency Code"`
> v tableextension skončí `AL0132`. Base vzor je `AutoFormatExpression = Rec.GetCurrencyCode();`
> (procedura na obou tabulkách). `Sales Line`, `Sales Line Archive`, `Sales Shipment Line` a `Return
> Receipt Line` `Currency Code` mají. (2026-09-04, cust-alumistr-bc, SK ceny na řádcích)

#### Propagace probíhá automaticky přes `TransferFields` — ale **jen pokud existuje pole se stejným ID a typem**

Standardní BC posting / archiving rutiny používají `TransferFields` mezi
zdrojovou a cílovou tabulkou:

- **Sales-Post** → `SalesShptLine.TransferFields(SalesLine)`,
  `SalesInvoiceLine.TransferFields(SalesLine)`, …
- **ArchiveManagement** → `SalesHeaderArchive.TransferFields(SalesHeader)`, …

`TransferFields` zkopíruje všechna pole, kde **field number sedí a typ je
kompatibilní**. Takže **stačí přidat field ve všech tabulkách sady se stejným
ID a typem — žádný subscriber není potřeba**.

```al
// Sales Header ZLK
field(52340; "My Custom Field ZLK"; Code[20]) { Caption = '...'; ... }

// Sales Header Archive ZLK
field(52340; "My Custom Field ZLK"; Code[20]) { Caption = '...'; ... }

// Sales Invoice Header ZLK
field(52340; "My Custom Field ZLK"; Code[20]) { Caption = '...'; ... }

// Sales Cr.Memo Header ZLK, Sales Shipment Header ZLK, Return Receipt Header ZLK
// — totéž
```

Po deployi: nová Sales Header s vyplněným polem → po Post se hodnota objeví
v Sales Invoice Header / Sales Shipment Header automaticky. **Bez subscriberu.**

#### Kdy přidat subscriber navíc

**Pozor na vlastní celkovou částku řádku při částečném účtování.** Shodné ID
zajistí kopii hodnoty, ale nepřepočítá ji na účtované množství. V BC 28.3
`Sales Invoice Line.InitFromSalesLine` po `TransferFields(SalesLine)` přiřadí
`Quantity := SalesLine."Qty. to Invoice"`; `Sales Shipment Line` obdobně
`Quantity := SalesLine."Qty. to Ship"`. Vlastní `Total = Quantity × Unit Price`
tak zůstane za CELÝ zdrojový řádek (10 × 132 = 1320 i při dodání 3 kusů).
Jednotkovou cenu přenes 1:1, celkovou částku dopočítej v tabulkovém
`OnAfterInitFromSalesLine` z cílového Quantity a zaokrouhlení měny — event je
na **všech čtyřech** posted line tabulkách, ale s **různým pořadím parametrů**
(ověřeno ve zdrojích 28.3): `Sales Invoice Line` / `Sales Cr.Memo Line`
`(var Line, Header, SalesLine)`, `Sales Shipment Line` / `Return Receipt Line`
`(Header, SalesLine, var Line)`; al-mcp u všech hlásí `ByReference: false`
(5.y v `bc-al-objects.md`). Invoice/Cr.Memo Line nemají `Currency Code` → měnu
ber ze `SalesLine`. **Storno dodávky / příjemky vratky** (`Undo Sales Shipment
Line.InsertNewShipmentLine`, `Undo Return Receipt Line.InsertNewReceiptLine`)
dělá `NewLine.Copy(OldLine)` + `Quantity := -Old.Quantity` → vlastní total
zůstane kladný u záporného množství; otoč znaménko v
`OnBeforeNewSalesShptLineInsert(var New, Old)` / `OnBeforeNewReturnRcptLineInsert`.
Test musí zahrnout částečné účtování (order i return order) a undo; plná
fakturace tuhle chybu neodhalí. (2026-09-07, cust-alumistr-bc 65916, code
review; implementace `SK Branch Mgt. ALU`, zdroje Base Application 28.3.52162.53506.)

Subscriber typu `OnAfterTransferFields` (nebo `OnBeforeInsertEvent` na cílové
tabulce) potřebuješ jen v těchto případech:

- **Mapping** — chceš pole `A` na zdroji do pole `B` na cíli (jiný název /
  jiný typ / dopočet hodnoty)
- **Field je na zdroji `FlowField`** — `TransferFields` ho neumí přenést,
  musíš ho v subscriberu spočítat (`CalcFields`) a uložit ručně do non-flow
  pole na cíli
- **Cíl má jiné pole číslo** než zdroj (legacy, špatný design — radši to
  nedělej, ale občas to nejde jinak)
- **Zdroj nemá pole vůbec** a hodnota se odvozuje z jiné tabulky

Příklad subscriberu pro Sales Line → Sales Invoice Line, když je zdrojové
pole FlowField:

```al
[EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnAfterSalesInvLineInsert, '', false, false)]
local procedure SalesPost_OnAfterSalesInvLineInsert(var SalesInvLine: Record "Sales Invoice Line"; SalesLine: Record "Sales Line")
begin
    if SalesInvLine.IsTemporary() then
        exit;
    SalesLine.CalcFields("My FlowField ZLK");
    SalesInvLine."My Snapshot ZLK" := SalesLine."My FlowField ZLK";
    SalesInvLine.Modify(false);
end;
```

#### Page rozšíření = stejná hra

Když pole zobrazuješ na `Sales Order` page, většinou ho chceš vidět i na
`Posted Sales Invoice`, `Posted Sales Shipment`, `Sales Order Archive`.
Přidej `pageextension` na všechny příslušné posted/archive stránky se stejnou
field group / area umístěním.

#### Rychlý checklist před commitem nového pole

Když přidáváš pole na `Sales Header`/`Sales Line` (nebo Purchase ekvivalent):

- [ ] Field na zdrojové tabulce
- [ ] Field na archive tabulce (stejné ID, stejný typ)
- [ ] Field na všech 4 posted tabulkách (Invoice, CrMemo, Shipment/Receipt,
      Return Receipt/Shipment) — header i line dle toho, kam pole patří
- [ ] Page extension na zdrojové page
- [ ] Page extension na archive page (`Sales Order Archive`,
      `Posted Purchase Invoice`, …)
- [ ] Page extension na všech posted page (`Posted Sales Invoice`,
      `Posted Sales Shipment`, `Posted Sales Credit Memo`, …)
- [ ] Pokud zdroj je FlowField → subscriber na `OnAfter...Insert` cílové tabulky
- [ ] Description property u všech nových tableextension / pageextension
      (sekce 1.4 v `bc-al-style.md`)
- [ ] Test: vytvoř doc → vyplň pole → Post → ověř hodnotu na posted dokumentu

### 3.6b Sales Line `Validate("No.")` dělá `Init()` → vlastní pole se tiše ztratí v base cestách, které No. znovu validují

`Sales Line."No."` OnValidate (BC 28.3, `SalesLine.Table.al` ř. ~70) dělá `TempSalesLine := Rec; Init();`
a pak plní pole znovu ze zboží → **všechna extension pole na řádku se vynulují**. Stejné ID polí na
posted/archive tabulkách (3.6) tenhle problém neřeší, protože jde o cesty, kde base po
`TransferFields`/přiřazení recordu ještě zavolá `Validate("No.")`:

| Cesta                                              | Kde                                                                                  | Hook pro obnovu vlastních polí                                                                              |
| -------------------------------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| **Restore z archivu**                              | `ArchiveManagement.RestoreSalesLines`: `TransferFields(Archive)` + `Insert` + `Validate("No.")` + Validate Variant/UoM/Qty/Unit Price | `OnAfterTransferFromArchToSalesLine(var SalesLine; var SalesLineArchive)` — běží po validacích, před `Modify(true)`; prosté přiřazení z archivu |
| **Copy Document s Recalculate Lines**              | `Copy Document Mgt.CopySalesDocLine`: `ToSalesLine.Init()` + `Validate("No.")` + `Validate(UoM)` (bez recalc je `ToSalesLine := FromSalesLine` → OK) | `OnBeforeInsertToSalesLine(var ToSalesLine; var FromSalesLine; FromDocType; RecalcLines; …)` — kopírovat jen když `RecalculateLines` |
| **RecreateSalesLines** (změna Sell-to apod.)       | `Sales Header.CreateSalesLine`: Validate Type/No./UoM/Variant/Qty                    | `OnBeforeSalesLineInsert(var SalesLine; var TempSalesLine; SalesHeader)` — Temp nese původní hodnoty         |

Cesty, které jsou OK bez subscriberu: Quote → Order, Blanket → Order, Get Shipment Lines, Get Posted Doc Lines to
Reverse, Undo Shipment (přiřazení recordu / `TransferFields` z posted). Sdílený helper `Reapply<Fields>(var SalesLine; …)`
pro všechny tři subscribery. Pole odvozená z Item UoM se reverse-fillem „obnoví" sama, ale pole typu kód/varianta ne.
(2026-08-31, prod-epb-pricingMatrix-bc plán 65842 — archive restore ztrácel `Sales Price Var. Code PMEBS`.)

**`RecreateSalesLines` (změna Sell-to / Bill-to / Currency…) nejdřív udělá `Modify()` hlavičky** (BC 28
`SalesHeader.Table.al`, hned po potvrzení `RecreateSalesLinesMsg`) a teprve pak řádky znovu vytvoří přes
`CreateSalesLine`: `Validate(Type)` → `Validate("No.")` → `GetUnitCost` → `Validate("Unit Cost (LCY)")` → UoM →
Variant → `Validate(Quantity)`. Subscriber na řádku, který si hlavičku čte z DB (`SalesHeader.Get`), tedy vidí už
**nového** plátce — cenotvorba závislá na hlavičce se při přepnutí plátce na existujících řádcích spočítá sama; ručně
zadané hodnoty na řádku ale projdou Init a je třeba je vrátit z `TempSalesLine` v `OnBeforeSalesLineInsert`.
Code-review nález „změna Bill-to nechá na řádcích starou cenu" je proto planý, dokud přepočet visí na `Unit Cost (LCY)`
/ `OnAfterUpdateUnitPrice`. Signatura Copy Document hooku: `OnBeforeInsertToSalesLine(var ToSalesLine; var FromSalesLine;
FromDocType: Option; RecalcLines: Boolean; var ToSalesHeader; DocLineNo: Integer; var NextLineNo: Integer;
RecalculateAmount: Boolean; var IsHandled: Boolean)`. (2026-09-15, cust-alumistr-bc 65916 code review.)

**Totéž dělá `Validate(Type)`** (BC 28.3 `SalesLine.Table.al`, field 5 OnValidate: `TempSalesLine := Rec; Init();`
a zpět jen Type, System-Created Entry, Currency Code) → přepnutí řádku Item → G/L Account / Resource z UI vynuluje
vlastní pole samo. Code-review nález „změna typu nechá viset staré vlastní ceny" je tedy u UI cesty teoretický; přímé
přiřazení `Type`/`No.` z kódu Init nespustí, proto guard `Type <> Item or No. = '' → Clear` v přepočtu stejně drž
(levné, chování pak nezávisí na base Init). (2026-09-10, cust-alumistr-bc 65916, `SK Branch Mgt. ALU`.)

**`Validate("Unit of Measure Code")` a `Validate("Variant Code")` na Sales Line PŘEPÍŠOU `Description` i `Description 2`.** Oba triggery volají
`Item Reference Management.EnterSalesItemReference`, který u řádku zboží znovu naplní texty z Item Reference / Item Variant / Item
(+ `GetItemTranslation`) — ověřeno v Base App 28.4. Vlastní texty (z konfigurátoru, importu…) proto přiřazuj **až po** validaci
varianty a MJ, jinak tiše zmizí; když má vlastní text stejnou hodnotu jako popis zboží, bug se maskuje a projeví se jen na `Description 2`.
Totéž nepřímo přes **EPB Pricing Matrix**: `Validate("Parameter A/B PMEBS")` dohledá matricovou MJ a sám zavolá `Validate("Unit of Measure Code")`
→ subscriber, který parametry validuje až po nastavení textů, texty smaže. Vzor: texty před validací uložit a po ní vrátit
(`ValidateParametersKeepingTexts` v cust-alumistr-bc `Configurator Events COALU`).
(2026-09-13, prod-ess-configurator-bc `SL Action Cond. Mgt.InitNewSalesLineFromAction` + COALU — Popis 2 z akčního řádku se ztrácel u řádků s MJ / s parametry.)

**Bonus — `fieldgroups` z tableextension:** `fieldgroups { addlast(DropDown; "My Field") }` v tableextension funguje
(vzor base app `ReturnReasonExt.TableExt.al`) — nejlevnější způsob, jak vlastní atribut ukázat ve všech lookupech
(např. Item UoM dropdown na Sales/Req./Price řádcích místo holého kódu).

### 3.6c Blob pole na Sales Header → posted/archiv se přes `TransferFields` NEpřenese bez `CalcFields`; délky Text polí drž na celé sadě stejné (LC0044)

- **Blob je lazy** — v bufferu recordu je jen po `CalcFields`. `TransferFields` /
  `InitFromSalesHeader` proto nenačtený Blob **tiše nepřenese** (posted doklad má prázdný
  Blob, žádná chyba). Base app to u `Work Description` dělá explicitně:
  `SalesHeader.CalcFields("Work Description"); SalesOrderHeader."Work Description" := SalesHeader."Work Description";`
  (codeunit Sales-Quote to Order, `CreateSalesHeader`; stejně Sales-Post, Copy Document,
  Archive). Vlastní Blob pole na Sales Header tedy = subscriber na **každém** přenosu:
  faktura, dodávka, dobropis, vratka, archiv + obnova, nabídka → objednávka, kopie dokladu
  (Blob := Blob přiřazení mezi recordy funguje, jen zdroj napřed `CalcFields`). `Text[n]` tohle
  nepotřebuje — přenese se sám (3.6).
- **Stejné vlastní pole s jiným typem/délkou napříč Sales Header vs. posted/archive tabulkami**
  (`Comment 1 ZLK` `Text[2048]` na Sales Header, `Text[250]` na Invoice/Shipment/Cr.Memo/
  Return Receipt/Archive) hlásí LinterCop **`LC0044` „Conflicting ID, Name or Type with Table
  X"** na všech dotčených tableextensions (warning → Essence CI fail) a při postingu delšího
  textu hrozí overflow. Délku rozšiřuj vždy na celé sadě tabulek (checklist 3.6).

(2026-09-02, cust-zlomek-bc — rich text prototyp `Comment 2 ZLK`.)

### 3.6e Guard na page `OnModifyRecord` nestav na diffu `Rec` vs `xRec` — hlídej invarianty

Page trigger `OnModifyRecord` dostane **spolehlivý `xRec` jen z reálného UI vstupu**. Guard
napsaný jako „co se změnilo" (`if Rec.Pole <> xRec.Pole then Error`) proto **tiše propustí**:

- programovou změnu záznamu (`Rec.Modify` z kódu, integrace, import) — tam je `xRec = Rec`
  (viz 3.9),
- **`TestPage`** — negativní test spadne na „An error was expected inside an ASSERTERROR
  statement.", protože se nic nedetekovalo (ověřeno na třech různých variantách testu: samotný
  `SetValue`, `SetValue` + `Next()`, i s druhým řádkem a `Last()`/`First()`).

**Pravidlo:** guard piš jako **invarianty záznamu** („co musí platit"), ne jako diff:

```al
// místo: if Rec."Variant Code" <> xRec."Variant Code" then Error(...)
if not IsVoucherLine(SalesLine) then exit;
SalesLine.TestField("Variant Code");                     // nesmí být prázdný
if (SalesLine.Quantity <> 1) and (SalesLine.Quantity <> -1) then Error(QtyErr, …);
if (SalesLine."Line Discount %" <> 0) or (SalesLine."Line Discount Amount" <> 0) then Error(…);
```

Invarianty se navíc dají **testovat přímo** (`asserterror Mgt.CheckLine(SalesLine)`) bez TestPage
a platí i pro cesty, kam page trigger nedosáhne. Hodnoty, které se legitimně mění (Qty. to Ship /
Invoice, data, texty), do invariantů nedávej — tím zůstane doklad normálně použitelný.
Diff proti `xRec` si nech jen tam, kde opravdu jde o „uživatel přepsal ručně zadanou hodnotu",
a počítej s tím, že z kódu ani z testu to nezabere. (2026-09-15, cust-sonnentor-bc,
`CheckVoucherLineModify` na Sales Order Subform, buildy 28270–28273.)

### 3.6d Kontrola dokladu před účtováním: `OnBeforeIsApprovedForPosting` platí JEN pro účtování z UI

`Sales Header.OnBeforeIsApprovedForPosting` (a `Purchase Header` ekvivalent) vyvolává
**`Sales-Post (Yes/No)`**, tedy cesta „uživatel klikne Účtovat". **`Sales-Post.Run` sám ho
nevolá** — takže kontrola zavěšená na tomhle eventu **neplatí** pro:

- programové účtování z kódu a integrací (`SalesPost.Run(SalesHeader)`),
- importy a job queue,
- **testy** (`LibrarySales.PostSalesDocument` jde přes `Sales-Post` přímo).

Příznak v testech je zákeřný: negativní test `asserterror LibrarySales.PostSalesDocument(...)`
spadne na **„An error was expected inside an ASSERTERROR statement."** — doklad se zaúčtoval,
protože kontrola vůbec neproběhla. Vypadá to jako chyba testu, ale je to díra v produkčním kódu:
přes API / integraci projde i doklad, který by uživatel z UI nezaúčtoval.

**Správné místo pro kontrolu celého dokladu, která má platit vždy: `Codeunit "Sales-Post"`
`OnAfterCheckSalesDoc`** — běží po standardních kontrolách v každé cestě účtování.
Signatura (BC 28.4): `(var SalesHeader; CommitIsSuppressed: Boolean; WhseShip: Boolean;
WhseReceive: Boolean; PreviewMode: Boolean; ErrorMessageMgt: Codeunit "Error Message Management")`;
nepoužité parametry se v subscriberu smí vynechat. Alternativa na samý začátek je
`OnBeforePostSalesDoc`. UI subscriber si klidně nech vedle (chyba pak přijde dřív, před
zahájením účtování) — read-only kontrola dvakrát nic nezkazí; počítej ale s tím, že nový
subscriber běží na **každém** prodejním dokladu, takže z něj rychle vyskoč, když se ho netýká.

**Pozor na `var` u parametru subscriberu:** al-mcp hlásí u těchhle eventů `ByReference: false`
i tam, kde publisher má `var` (5.y v `bc-al-objects.md`) — ze symbolů to tedy nepoznáš.
Chybějící `var` chytí ALCops **`PC0010`** („Parameter must use the 'var' keyword if the publisher
parameter is 'var'"), takže lokální build s ALCops to řekne za tebe.

(2026-09-15, cust-sonnentor-bc build 28271 — kontrola plné hodnoty uplatněného poukazu
visela na `OnBeforeIsApprovedForPosting` a při programovém účtování se nespustila.)

### 3.6f Fakturace dodaného řádku: `Sales-Post.CheckJobNoOnShptLineEqualToSales` porovnává Job No. dodávky a řádku — doplnění Job No. až při účtování faktury spadne

`PostSalesLine` (BC 28) volá v tomhle pořadí: `OnPostSalesLineOnBeforeTestUnitOfMeasureCode` → `OnPostSalesLineOnBeforeUpdateSalesLineBeforePost`
→ `UpdateSalesLineBeforePost` → `PostItemLine` → `PostItemTracking` → `PostItemTrackingForShipment`, kde se pro každý dodaný, nevyfakturovaný
řádek dodávky testuje `SalesShptLine.TestField("Sell-to Customer No." / Type / "No." / Gen. Bus. / Gen. Prod. / **"Job No."** / UoM / Variant, SalesLine.X)`.
Job No. má vlastní wrapper `CheckJobNoOnShptLineEqualToSales` s hookem **`OnBeforeCheckJobNoOnShptLineEqualToSales(SalesShipmentLine, SalesLine,
var IsHandled)`**; celý blok testů jde vypnout přes `OnPostItemTrackingForShipmentOnBeforeTestLineFields`. U vratek (`Return Receipt Line`) je
analogický `TestField("Job No.")` v `CheckReturnRcptLine` s hookem `OnBeforeCheckReturnRcptLine`.

Past: řádek objednávky vygenerovaný z Job Planning Line (IMEBS `GenerateSalesOrderJobLines`) nese jen `Job Contract Entry No.`, Job No. má prázdné
(standard ho na objednávce vyžaduje prázdné — `TestField("Job No.", '')` v `PostSalesLine` pro Order). Dodávka tedy vznikne s **prázdným Job No.**
Faktura přes Get Shipment Lines (`InsertInvLineFromShptLine`: `SalesLine := SalesOrderLine`) zdědí prázdné Job No. + kontrakt. Když pak subscriber
na `OnPostSalesLineOnBeforeUpdateSalesLineBeforePost` (IMEBS `Project Item Management`, commit 1350b6f 2026-09-17 — kvůli `PostJobContractLine`
`TestField("Job No.")` u dobropisů z Correct/Cancel) doplní Job No. z planning line na fakturační řádek, běží to **před** `PostItemLine`, a
`TestField("Job No.", SalesLine."Job No.")` na dodávce spadne („Job No. must be equal to 'X' in Sales Shipment Line … Current value is ''"), debugger
ukazuje `Sales-Post.dal:8331`. Totéž pro `Skip Purchase Consumption` projekty přes starší subscriber `OnPostSalesLineOnBeforeTestUnitOfMeasureCode`.
Řešení: buď Job No. doplňovat až po item postingu (např. `OnAfterPostItemLine` / těsně před `PostJobContractLine`), nebo v
`OnBeforeCheckJobNoOnShptLineEqualToSales` nastavit `IsHandled`, když má dodávka prázdné Job No. a stejné `Job Contract Entry No.` jako řádek
(Sales Shipment Line to pole má). Zachyceno 2026-09-22, cust-soitron-bc (Sales Aggregation, částečná dodávka → faktura z Get Shipment Lines).

**Opraveno v prod-ep-itemManagement-bc (2026-09-22, `Project Item Management IMEBS`):** druhá varianta — subscriber
`OnBeforeCheckJobNoOnShptLineEqualToSales` nastaví `IsHandled`, jen když dodávka má prázdné Job No., shodné nenulové
`Job Contract Entry No.` s fakturačním řádkem **a** Job No. řádku = Job No. planning line s tím kontraktem (= hodnota, kterou
subscriber sám doplnil; ručně přepsaný jiný projekt standardní kontrola dál chytí). `IsHandled` u `OnBeforeCheckReturnRcptLine`
by naopak vypnul **všechny** `TestField` na řádku příjemky vratky (hook je před celým blokem), takže vratky zatím bez zásahu —
opravný dobropis z Correct/Cancel `Return Receipt No.` nemá a tou kontrolou neprochází. Test bez UI: `Sales-Get Shipment`
`SetSalesHeader(InvoiceHeader)` + `CreateInvLines(SalesShptLine s filtrem Document No.)` (`LibrarySales.GetShipmentLines`
otevírá výběrovou stránku); test `InvoiceFromShipmentLines_ShipmentLineWithBlankJobNo_PostsWithJobNoFromPlanningLine`
v `Job Sales Post Test IMEBS`. Test symboly 28.4 (`28.4.53241.53504`) z MSSymbols feedu proti Base App `28.4.53241.54031` — alc 17.0 čistě.
**`OnPostSalesLineOnBeforeTestUnitOfMeasureCode` se v BC 28 volá JEN pro `Type = Item`** (`PostSalesLine`: `if SalesLine.Type = Item then begin
… OnPostSalesLineOnBeforeTestUnitOfMeasureCode(…)`), zatímco `OnPostSalesLineOnBeforeUpdateSalesLineBeforePost` běží pro všechny typy. Subscriber
zavěšený na ten první (IMEBS Skip Purchase Consumption) tak doplní Job No. jen na řádky zboží → dodávka má u zboží Job No. vyplněné, u zdroje /
finančního účtu prázdné; při fakturaci z Get Shipment Lines pak padá právě řádek zdroje (zboží projde, hodnoty sedí). Zdroje procházejí
`PostItemTrackingForShipment` taky (`PostItemTrackingLine` běží před `case Type`), jen `PostItemJnlLine` je podmíněný `Type = Item`. Ověřeno v
w1-28 `SalesPost.Codeunit.al` (raw.githubusercontent, cesta `BaseApp/Source/Base Application/Sales/Posting/`).

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
