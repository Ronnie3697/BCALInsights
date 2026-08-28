# Business Central / AL — poznámky z praxe

Sbírka praktických poznatků, gotchas a konvencí z reálného AL vývoje.
Cíl: nehledat dvakrát stejnou věc, držet konzistentní styl napříč projekty.

> **Pozn.:** Vše kolem automatizovaných testů (test codeunits, libraries,
> runner, gotchas) má vlastní soubor: [bc-al-autotests.md](bc-al-autotests.md).

---

## Obsah

1. [Konvence kódu a stylu](#1-konvence-kódu-a-stylu)
2. [Database operace](#2-database-operace)
3. [Event Subscribery — patterny](#3-event-subscribery--patterny)
4. [UI patterny](#4-ui-patterny)
5. [Specifické objekty a API](#5-specifické-objekty-a-api)
6. [Lokalizace a CZ↔EN](#6-lokalizace-a-czen)
7. [Nástroje a workflow](#7-nástroje-a-workflow)
8. [Dokumentace requirements (PBI/Task → MD)](#8-dokumentace-requirements-pbitask--md)
9. [Před úpravou AL objektu — co si přečíst](#9-před-úpravou-al-objektu--co-si-přečíst)
10. [Moderní AL patterny — výběr podle app.json](#10-moderní-al-patterny--výběr-podle-appjson)
11. [SaaS gotchas — HttpClient a Cloud target](#11-saas-gotchas--httpclient-a-cloud-target)
12. [Verifikace a analyzery (AA / CA / PTE / LC)](#12-verifikace-a-analyzery-aa--ca--pte--lc)

---

## 1. Konvence kódu a stylu

### 1.1 Jazyk identifikátorů a textů — vždy EN

Veškerý kód i UI texty v AL píšu **anglicky**, bez ohledu na to, že zákazník je
český. Lokalizace se řeší přes překladové XLIFF soubory, ne v kódu.

**Co musí být anglicky:**

- Názvy polí, objektů, proměnných, parametrů, procedur (i s customer suffixem
  jako `ZLK`, `CZZ` atd.)
- `Caption`, `ToolTip`, `Label`, error messages — překlad jde do XLIFF

**Proč:**

- Konzistence s base app a všemi ostatními rozšířeními
- Code review, search, sdílení snippetů přes týmy/komunitu
- XLIFF lokalizační workflow předpokládá EN jako zdrojový jazyk
- Mix CZ/EN v identifikátorech vypadá amatérsky a komplikuje IntelliSense

České texty patří **výhradně** do `.xlf` souborů jako překlad EN stringů.

### 1.2 Strukturování projektu — složky podle typu objektu

Source files ukládej do `src/` rozdělené **podle typu objektu**, ne podle
business modulu nebo featury:

```
app/src/
├── codeunit/
├── page/
├── pageextension/
├── table/
├── tableextension/
├── enumextension/
├── report/
├── reportextension/
└── permissionset/
```

**Proč:**

- VS Code File Explorer + naming konvence `<Name>.<Type>.al` = okamžitě vidíš,
  co kde je, bez otevírání souboru
- Cross-cutting featury obvykle zasahují do víc typů (table + tableext + page +
  pageext + codeunit + report) — rozdělení podle featury vede k duplicitě a
  hádkám "kam to patří"
- Sjednocuje to projekty, kde se střídá víc vývojářů nebo AI asistentů

**Výjimka:** Extrémně velký scope (stovky objektů jedné featury) → jde dělit
jako `src/<feature>/<type>/`, ale i pak držet typ-složku jako spodní úroveň.

### 1.3 Naming konvence — doprovodné soubory k AL objektům

Když AL objekt má vedlejší soubor (Word/RDLC layout u `report` /
`reportextension`, JS/CSS/HTML u `controladdin` atd.), pojmenuj ho **stejně
jako ten `.al` soubor, včetně sufixu typu objektu**.

**Příklady:**

- `CNCLabel.Report.al` → `CNCLabel.Report.docx` (ne `CNCLabel.docx`)
- `FooBar.ReportExt.al` → `FooBar.ReportExt.docx`
- `MyScanner.ControlAddIn.al` → `MyScanner.ControlAddIn.js`

Po přejmenování doprovodného souboru nezapomeň upravit i `LayoutFile` /
`Scripts` / jinou file-path property v `.al` souboru.

**Proč:** Ve VS Code File Exploreru musí být na první pohled vidět, ke kterému
AL objektu doprovodný soubor patří. Bez sufixu typu (`.Report`, `.ReportExt`,
`.ControlAddIn`…) není vazba jasná ani pro člověka, ani pro Copilot, který si
ten doprovodný soubor otevře bez kontextu.

Pokud v daném repu běží Copilot, je fajn pravidlo zrcadlit i do
`.github/copilot-instructions.md`.

### 1.4 `Description` property

U `codeunit`, `report`, `pageextension` a `tableextension` piš `Description` —
krátký popis k čemu objekt slouží. Je to pro **vývojáře a AI**, ne pro
koncového uživatele, takže se **nepřekládá** (angličtina stačí).

**Pravidla:**

- Stručně, jedna až dvě věty — co objekt dělá / k čemu je
- Anglicky, není v XLIFF
- U extensions piš **co konkrétně přidáváš a proč**, ne jen "extends X" (to už
  je v deklaraci)
- Při změně logiky objektu **zkontroluj Description** a aktualizuj ho

```al
codeunit 52310 "Update Sales Order Adv. Status ZLK"
{
    Description = 'Recalculates Advance Status ZLK on sales orders based on linked sales advance letters. Used by the Update Sales Order Advance Status report and triggered on advance letter posting.';
}

tableextension 52316 "Sales Header ZLK" extends "Sales Header"
{
    Description = 'Adds advance-letter linkage fields (Advance Status, Advance Rounding) and assignment tracking used by the sales advance workflow.';
}

pageextension 52310 "Sales Order ZLK" extends "Sales Order"
{
    Description = 'Surfaces advance-letter fields and the Create Advance Letter action driven by codeunit 52310.';
}
```

**Proč:**

- AI asistent i nový vývojář v týmu si při hledání rychle načte, k čemu objekt
  je, bez čtení celého kódu
- Pomáhá u code review — recenzent vidí záměr objektu
- Drží disciplínu — když po změně Description už neodpovídá, je to signál, že
  se rozjíždí scope objektu

### 1.5 ToolTipy — jak je psát

ToolTip u pole nebo akce piš **uživatelsky**, ne technicky. Cíl je, aby
uživatel po najetí myší pochopil, k čemu pole/akce slouží a jak se projeví v
jeho workflow.

**Kam ToolTip patří:**

- **Pole** → ToolTip definuj na poli v `table` / `tableextension`. Od BC 22+
  se odtud automaticky propaguje na všechny page kontroly, kde se pole
  zobrazuje. **Na `pageextension` ToolTip u field controlu už nepiš** — je
  to duplicita a stará konvence. (Starší pageextensions v repu, které ToolTip
  na page mají, jsou legacy — při průchodu kolem je čistě na úvaze, ale
  nový kód piš s ToolTipem jen na tableextension.)
- **Akce** → ToolTip patří přímo na `action(...)` v page / pageextension —
  akce nemá tabulkový protějšek.

**Pravidla obsahu:**

- Popiš **funkčnost** — co pole drží nebo co akce dělá, z pohledu uživatele
- Vyhni se technickému žargonu (názvy tabulek, event subscribery, interní flagy)
- Techniku přidávej jen když je logika opravdu složitá nebo neintuitivní —
  pak doplň krátký lehký příklad, ne výpis kódu
- Na pole začínej `'Specifies ...'`, na akce slovesem `'Creates ...'`,
  `'Opens ...'`, `'Updates ...'` — drží to konvenci base app

**Příklady:**

```al
// Dobře — uživatelsky, doplňuje kontext k Captionu
field("Advance Status ZLK"; Enum "Advance Letter Doc. Status CZZ")
{
    Caption = 'Advance Status';
    ToolTip = 'Specifies the status of the related sales advance letter linked to this order. Updated by the Update Sales Order Advance Status report.';
}

// Dobře — uživatelsky, s příkladem u nenulové logiky
field("Advance Rounding ZLK"; Decimal)
{
    ToolTip = 'Specifies the rounding precision of the advance amount (e.g., 1 = whole units, 10 = tens, 100 = hundreds).';
}

// Dobře — jednoduché pole, žádný příklad netřeba
field("Comment 1 ZLK"; Text[250])
{
    ToolTip = 'Specifies additional comment 1 for the sales document.';
}

// Špatně — technický detail bez uživatelské hodnoty
field("Advance Rounding ZLK"; Decimal)
{
    ToolTip = 'Decimal field used by Round() call in OnAction trigger of CreateAdvanceLetterZLK.';
}

// Akce — co dělá + proč by to uživatel chtěl použít
action(ToggleAcceptActionMsgZLK)
{
    Caption = 'Toggle Accept Action Message';
    ApplicationArea = Planning;
    ToolTip = 'Flips the Accept Action Message checkbox on all selected lines, so you can accept or reject many planning proposals in one go.';
}
```

**Poznámka:** Pokud je extension pro AppSource, ToolTip je povinný (LinterCop,
AppSourceCop) — ne skrytý `ToolTip = ''`.

### 1.6 `IntegrationEvent` publishery — vždy na konec objektu

Publishery (`[IntegrationEvent]` procedury) dávej **vždy na konec codeunit /
report / table objektu**, pod všechny ostatní procedury. Ne uprostřed nebo
hned za proceduru, ze které se volají.

**Proč:** Přehlednost — subscriberi se hledají a čtou jako samostatná sekce
na konci souboru. Zamíchané mezi běžné lokální procedury se špatně hledají.

### 1.7 `actionref` — vždy na konec `actions {}`

Když v pageextension přidáváš promoted `actionref`, dávej ho **až za všechny
`action(...)` definice**, na konec bloku `actions {}`. Nejdřív definuj akci,
pak její odkaz.

```al
actions
{
    addafter(CarryOutActionMessage)
    {
        action(ToggleAcceptActionMsgZLK) { ... }
    }

    // actionref až úplně na konci
    addlast(Category_Process)
    {
        actionref(ToggleAcceptActionMsgZLKRef; ToggleAcceptActionMsgZLK) { }
    }
}
```

**Proč:** Čitelnost — nejdřív vidíš definici akce (co dělá), pak teprve kam
se promuje. Obrácené pořadí nutí čtenáře skákat tam a zpět.

### 1.8 Prefix `Temp` — jen pro skutečně temporary recordy (AA0228 / AA0021)

Prefix `Temp` u proměnné typu `Record` je v AL **rezervovaný pro
`Record X temporary`**. LinterCop na to má pravidla AA0228 / AA0021.

```al
// Špatně — TempReqLine není temporary, jen filter holder
TempReqLine: Record "Requisition Line";

// Dobře — pojmenuj podle účelu
FilterReqLine: Record "Requisition Line";
BufferReqLine: Record "Requisition Line";

// Dobře — skutečně temporary
TempReqLine: Record "Requisition Line" temporary;
```

**Proč:** Prefix `Temp` mate čtenáře (čeká `temporary` chování — žádné zápisy
do DB, isolated buffer) a linter to označí. Pojmenuj podle role: `Filter*`,
`Buffer*`, `Existing*`, `New*`, …

### 1.9 `StyleExpr` — vždy `Text`/`Boolean`/`Code`, ne enum literal (LC0086)

Property `StyleExpr` na page kontrolu **nepřijímá** `PageStyle` enum přímo. Akceptuje
jen `Boolean`, `Text` nebo `Code`. Když tam šoupneš `PageStyle::Favorable`, vypadne
LC0086.

Správně — drž si pomocnou `Text` proměnnou a plň ji přes `Format(...)`:

```al
var
    LineStyle: Text;
begin
    if SalesLine.Overdue then
        LineStyle := Format(PageStyle::Unfavorable)
    else
        LineStyle := Format(PageStyle::Favorable);
end;

// na page
field("Amount"; Rec.Amount)
{
    StyleExpr = LineStyle;
}
```

`Boolean` varianta se hodí pro jednoduché on/off zvýraznění (true = bold).

### 1.10 `Access = Public` na interních objektech — nezvyšovat bez schválení

Když je objekt nebo procedura `Access = Internal`, **nepřepínej ji na `Public`**
bez explicitní domluvy s uživatelem nebo majitelem appky. Internal = vědomý
kontrakt že to není public API extension. Změna na Public uzamkne API
(breaking change pro upgrade) a vystaví interní logiku konzumentům.

Pokud reálně potřebuješ z jiné appky volat něco, co je `Internal`, řekni to
uživateli a zvaž `internalsVisibleTo` v `app.json` místo widening.

### 1.11 Page fieldy víceřádkově; ApplicationArea / DataClassification bez redundance

**Fieldy na page piš vždy víceřádkově** — deklarace, `{`, properties a `}` na
samostatných řádcích. Žádné one-linery `field("X"; Rec."X") { ApplicationArea = All; }`
— blbě se čtou v diffu a properties se do nich špatně přidávají. Platí i pro
field bez properties (prázdné tělo). Prázdný `actionref(...) { }` může zůstat
one-line.

```al
// Špatně
field("Receipt Number"; Rec."Receipt Number") { ApplicationArea = All; }

// Dobře
field("Receipt Number"; Rec."Receipt Number")
{
}
```

**Redundantní properties (LinterCop LC0020 / LC0019):**

- `ApplicationArea` definuj na **page úrovni**; na field controly ji piš jen
  tehdy, když se od page liší. Výjimka: **pageextension** fieldy potřebují
  vlastní `ApplicationArea` — z properties base page se nedědí.
- `DataClassification` definuj na **table úrovni**; na fieldech jen když se
  od tabulky liší.

**Související gotcha (AL0667):** `AllowInCustomizations = Always` je od BC 16
deprecated — používej `AsReadOnly` (pole jen pro čtení v personalizaci) nebo
`AsReadWrite`.

### 1.12 Typed `Record` před `RecordRef.Open(...)` + ruční iterací polí

`RecordRef` má své místo (generická utility, která nezná tabulku v compile-time —
data export, validace napříč tabulkami…), ale pro běžnou business logiku, kde
tabulku znáš, **vždycky** typed `Record`. Compiler ti hlídá field names a typy,
IntelliSense funguje, refactor je bezpečný.

```al
// Špatně — bezdůvodný RecordRef
RecRef.Open(Database::"Sales Line");
FieldRef := RecRef.Field(1);
FieldRef.SetRange(SalesHeader."No.");
if RecRef.FindSet() then ...

// Dobře — typed
SalesLine.SetRange("Document No.", SalesHeader."No.");
if SalesLine.FindSet() then ...
```

### 1.12 Přidělování ID — každý typ objektu od začátku idRange

AL má **samostatný ID namespace per typ objektu** (tableextension, pageextension,
codeunit, report, enumextension, permissionset, permissionsetextension, …).
Při přidělování ID v rámci `idRanges` appky proto **každý typ začíná od začátku
range** — nečísluje se globálně sekvenčně napříč typy.

**Příklad (range 60120–60149):**

```
tableextension          60120, 60121, 60122, …
pageextension           60120, 60121, 60122, …
codeunit                60120, 60121, …
report                  60120, …
enumextension           60120, …
permissionset           60120
permissionsetextension  60120, 60121, 60122
```

Stejně tak **field ID** (per-table namespace — první custom pole na každé
tabulce = začátek range; výjimka: posted/archive sady drží stejné field ID
jako zdrojová tabulka kvůli `TransferFields`, viz 3.6) a **enum values**
(per-enum namespace).

**Proč:** Range se zbytečně nevyčerpává (20 ID stačí na 20 objektů *každého*
typu, ne 20 celkem) a ID jsou predikovatelná.

**Test app** (sdílí range s hlavní appkou): test codeunity čísluj **od konce
range** (např. 60149, 60148, …) — codeunit ID namespace je sdílený napříč
nainstalovanými appkami, takže hlavní appka roste od začátku, testy od konce
a nepotkají se.

**Pozor (opakovaná chyba z praxe):** při migraci nebo zakládání objektů
nepřenášet globální/offsetové číslování z předlohy — vždy přečíslovat per typ
od začátku range. (2026-06: migrace EF Advance CZ — první návrh čísloval
globálně 60120…60132 napříč typy, správně per typ od 60120.)

---

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
`OnAfterInsert` / `OnBeforeModify` / `OnAfterModify` **nevolej Insert ani
Modify vůbec** (ani s argumentem) — zápis proběhne automaticky jako součást
původní operace. Viz sekce 3.1.

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
      (sekce 1.4)
- [ ] Test: vytvoř doc → vyplň pole → Post → ověř hodnotu na posted dokumentu

---

## 4. UI patterny

### 4.1 `RunModal` vs `Run`

- `Page.Run()` je **asynchronní** — kód pokračuje dál bez čekání na zavření
  stránky
- `Page.RunModal()` **blokuje** — kód čeká, dokud se stránka nezavře
- Na **RoleCenter CardPart** stránkách `RunModal` s návratovou hodnotou
  (`Action::LookupOK` / `Action::OK`) **nefunguje spolehlivě** — modální
  dialog se nevrátí správně

### 4.2 Výběr záznamu z List page na RoleCenter

- `Page.RunModal(0, Record)` ani `Page.RunModal(PageID, Record)`
  **neaktualizuje** record proměnnou na vybraný záznam
- `LookupMode(true)` + `GetRecord()` nefunguje na RoleCenter CardPartu
- **Správné řešení**: vlastní stránka s akcí "Vybrat" (`CurrPage.Close()`) +
  `SingleInstance` codeunit pro předání hodnoty:
  1. `SingleInstance` codeunit uchovává vybranou hodnotu
     (`SetSelectedLocation`, `GetSelectedLocation`, `ClearSelectedLocation`)
  2. Výběrová stránka v akci uloží hodnotu do SingleInstance + `CurrPage.Close()`
  3. Volající kód: `ClearSelectedLocation` → `Page.RunModal(...)` →
     `GetSelectedLocation()`

### 4.3 `OnDrillDown` vs `OnLookup`

- `OnDrillDown` funguje i na `Editable = false` polích
- `OnLookup` vyžaduje `Editable = true`
- Na RoleCenter jsou obě omezené pro RunModal — viz řešení v 4.2
- Dle MS dokumentace jsou `DrillDown` a `Lookup` ve web klientu
  **"partially supported"** — fungují jako hyperlink, ale ne v Repeater
  controlu v read-only módu
- Omezení na RoleCenter CardPart **není explicitně zdokumentováno**
  Microsoftem — zjištěno experimentováním

### 4.4 `ConfirmManagement` — default Yes pro běžné akce, No pro destruktivní

**Default `true` (Yes) pro běžné akce:**

```al
if not ConfirmManagement.GetResponseOrDefault(ConfirmQst, true) then
    exit;
```

**Proč Yes:** Když už uživatel akci vyvolal (kliknul na tlačítko / položku
menu), jeho záměr je jasný — dialog je jen ochranná pojistka proti překliku.
Default Yes = Enter dialog potvrdí a uživatel pokračuje bez zbytečného cílení
myší na "Ano". Default No nutí uživatele vždy přepnout, což zdržuje a otravuje
u opakovaných akcí.

**Default `false` (No) pro destruktivní / nevratné operace:**

- Hromadné `Delete` (delete selected lines, clear journal, …)
- Přepsání účetních dat bez možnosti undo (Reverse Posting, Force Posting Date)
- Spuštění úlohy, která modifikuje stovky+ záznamů bez transakční hranice
  (např. update všech Item "Costing Method")
- Operace, která pošle data ven (e-mail batch, EDI export, payment file)

```al
// Standard akce -> default Yes
if not ConfirmManagement.GetResponseOrDefault(StrSubstNo(UpdateQst, Count), true) then
    exit;

// Destruktivní akce -> default No (záchranná brzda)
if not ConfirmManagement.GetResponseOrDefault(DeleteAllQst, false) then
    exit;
```

**Pravidlo palce:** Když si položíš otázku _"Co se stane, když uživatel omylem
klikne Enter?"_ a odpověď je _"data jsou v háji a nejde to vrátit"_ → default
`false`. Jinak default `true`.

---

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
zaúčtovat přes batch posting codeunit (`Item Jnl.-Post` 23, `Gen. Jnl.-Post`
80…). Ten codeunit si sérii konzumuje sám během postingu — pokud bys ji
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

Posting codeunit `Item Jnl.-Post` (23) si na začátku dělá `ItemJnlLine.Copy(Rec)`
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

### 6.1 NAB AL Tools — workflow překladu XLIFF

V hodně AL repech sedí na překladech extension **NAB AL Tools** (VS Code).
Po `Refresh XLIFF` ti tool označí všechny chybějící nebo nejisté překlady
zvláštním prefixem v `<target>`. Pojmenování:

- **`[NAB: NOT TRANSLATED]`** — pro string nemá tool žádný kandidát z base
  appky / paměti překladů. Musíš dopsat ručně.
- **`[NAB: SUGGESTION]<návrh>`** — tool našel jeden nebo víc kandidátů
  (typicky z base appky, kde už existuje stejný source string). Trans-unit
  pak může mít **víc `<target>` řádků pod sebou**, každý s vlastním návrhem.

```xml
<trans-unit id="...">
  <source>Specifies the Item No. of the warehouse receipt line.</source>
  <target>[NAB: SUGGESTION]Určuje číslo zboží řádku skladové příjemky.</target>
  <target>[NAB: SUGGESTION]Určuje číslo položky řádku skladové příjemky.</target>
  <note from="Developer" annotates="general" priority="2"></note>
  <note from="NAB AL Tool Refresh Xlf" annotates="general" priority="3">Suggested translation inserted.</note>
  <note from="Xliff Generator" annotates="general" priority="3">...</note>
</trans-unit>
```

**Pravidla úpravy po `Refresh XLIFF`:**

1. **Vždy nech jen jeden `<target>`** — i když měl tool víc návrhů. XLIFF
   spec sice víc target tagů povoluje, ale BC kompilátor + runtime používají
   jen první a víc tagů jen mate. Vyber nejvhodnější návrh, nebo si vlož
   svůj překlad.
2. **Smaž prefix `[NAB: NOT TRANSLATED]` / `[NAB: SUGGESTION]`** úplně.
   Cokoliv co začíná `[NAB:` je pro tool flag "tohle ještě není hotovo" —
   po tvém zásahu tam patří jen čistý překlad.
3. **Note `NAB AL Tool Refresh Xlf`** můžeš nechat (tool si ho při příštím
   refreshi přepíše), ale klidně i smazat — nemá vliv na build.
4. **Note `Xliff Generator`** **nikdy nemaž** — drží kontext (object/field/
   property), který je důležitý pro jiné překladatele.

**Hromadné překlady (desítky+ míst):** Ručně editovat unit po unit je
zdlouhavé. Praktická cesta — Python skript s mapou `source_text →
překlad`, který:

- pro každou `<trans-unit>` najde `<source>`,
- pokud target obsahuje `[NAB:`, vyhodí všechny `<target>` řádky a vloží
  jeden s překladem ze source mapy,
- duplicitní source stringy v různých kontextech pokrývá jednou položkou
  v mapě (caption "Quantity" je vždy "Množství", ať je na poli nebo na
  page kontrolu).

Po skriptu **zkompiluj** (`alc.exe`, viz 7.1) — chytíš tím poškozenou
strukturu (escape `&` → `&amp;`, neuzavřený tag, špatná entita) hned, ne
až při deploy.

**Při překladu drž BC CZ konvence z tabulky výše** — zejména `Bin =
Přihrádka` (ne "Koš"), `Item = Zboží` (ne "Položka"), `Lot = Šarže`. Tool
sice nabídne `[NAB: SUGGESTION]Sériové č.` jako kratší variantu, ale base
app cs-CZ používá `Sériové číslo` v plném tvaru — drž to.

### 6.2 XLIFF trans-unit ID — hash algoritmus (ruční doplnění unitů bez rebuildu)

ID v `trans-unit` (`Table 66836948 - Field 922357686 - Property 2879900210`)
jsou hashe **jmen** elementů (ne textů). Algoritmus (ověřeno reverse-engineeringem
proti reálným .g.xlf hodnotám, zdroj: github.com/microsoft/AL issue #4361):
**FNV-1a 32-bit přes UTF-16LE bajty jména + offset 2147483647 (mod 2^32)**.

```python
def alhash(name: str) -> int:
    h = 0x811c9dc5
    for b in name.encode("utf-16-le"):
        h = ((h ^ b) * 16777619) % 2**32
    return (h + 2147483647) % 2**32
```

- Vstup je čisté jméno elementu: `alhash("Caption")` = 2879900210,
  `alhash("ToolTip")` = 1295455071, `alhash("CNC Macro COALU")` = 66836948.
- ID se skládá z `<Typ> <hash(jméno)>` po cestě od objektu k labelu:
  `Table X - Field Y - Property Z`. Source text se nehashuje — změna
  ToolTip textu ID nemění, **rename pole/objektu ano** (starý unit osiří).
- Use case: přidáváš pole a chceš rovnou doplnit překlad do `.cs-CZ.xlf`
  bez čekání na build + NAB Refresh — spočítej hash jména pole a napiš
  trans-unit ručně se správným ID. Refresh ho pak už jen potvrdí.

### 6.3 Přeložený `Error`/`Message`/`Label` + `%n` placeholder — musíš updatnout i XLF

Když u **přeloženého** labelu (objekt s `TranslationFile` featurou + locale `.xlf`)
změníš **zdrojový text** — typicky přidáš `%1`/`%2` pro víc kontextu (status, ID,
detail) — **nestačí změnit jen `.al`**. V cílové lokalizaci runtime bere **`<target>`
z `.xlf`**, párovaný přes **trans-unit ID** (hash *jmen* objektu/labelu, viz 6.2).
Změna zdrojového textu **ID nemění** → starý `<target>` (bez placeholderů) **zůstane**
a runtime ho použije. Výsledek: appka dál ukazuje **starou hlášku bez doplněných
argumentů**, i když `Error(NewLabel, arg1, arg2)` ty argumenty předává (chybějící
`%n` v targetu se prostě nevyplní, extra argumenty se zahodí).

**Příznak:** error/message vypadá jako „nezměněný" po rebuildu, ačkoli jsi label v kódu
upravil — a jen v lokalizovaném klientu (CZ), v EN by se nová verze ukázala.

**Fix:** uprav v `.cs-CZ.xlf` (a každé další locale) jak `<source>`, tak `<target>`
daného trans-unitu, ať nesou stejné `%n`:

```xml
<!-- .al: CreateErr: Label 'Category could not be created (HTTP %1). Response: %2'; -->
<source>Category could not be created (HTTP %1). Response: %2</source>
<target>Kategorii se nepodařilo vytvořit (HTTP %1). Odpověď: %2</target>
```

- `<source>` srovnej se zdrojovým labelem — jinak build/NAB hlásí source-mismatch.
- Pak **rebuild** (label resolving je compile-time). Historické záznamy (např. řádky
  v audit logu) drží text z doby zápisu — rich verze naskočí až u nových.
- Stejná past platí pro `Message`, `Confirm`, `FieldError`, `StrSubstNo` nad Labelem.
- Zachyceno: prod-ess-dotykackaConnector-bc (červen 2026) — obohacení chybové hlášky
  o HTTP status z API se v CZ klientu neprojevilo, dokud se neupravil `<target>` v XLF.

---

## 7. Nástroje a workflow

### 7.1 Rychlá kompilace z CLI — `alc.exe` z AL extension

AL extension pro VS Code s sebou nese kompilátor `alc.exe`. Jde ho pustit
přímo bez čekání na `al: publish` — užitečné pro zpětnou vazbu
"prošlo/neprošlo" při větších změnách.

**Cesta:** `~/.vscode/extensions/ms-dynamics-smb.al-<version>/bin/win32/alc.exe`
(ve Windows, pro macOS `darwin`, pro Linux `linux`)

**Volání (bash):**

```bash
"$HOME/.vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/win32/alc.exe" \
  /project:"C:\full\path\to\app" \
  /packagecachepath:"C:\full\path\to\.alpackages" \
  /out:"C:\full\path\to\_compile_test.app"
```

**Gotchas:**

- **Cesty musí být absolutní.** S `/project:.` kompilátor uvidí jen `app.json`
  (hlásí "containing 1 file") a nenačte `.al` zdroje. S plnou cestou správně
  sesbírá celý adresář.
- **`/packagecachepath`** ukazuje na složku `.alpackages` (obsahuje závislosti
  jako `Microsoft_Base Application_*.app`). Většinou je o úroveň výš než
  `app/`.
- Bez chybových hlášek na výstupu = kompilace OK. Výstupní `.app` soubor je
  potřeba smazat, pokud jde o test (nebude odpovídat podepsanému buildu).
- Verze extension (`17.0.2273547`) se může lišit — najdi ji přes
  `ls ~/.vscode/extensions | grep ms-dynamics-smb.al`.
- **Analyzery z CLI:** `/analyzer:<path>\Microsoft.Dynamics.Nav.CodeCop.dll`
  (UICop, AppSourceCop a `BusinessCentral.LinterCop.dll` žijí v
  `<extension>/bin/Analyzers`). V **Git Bash** pozor — argumenty začínající
  `/analyzer:` MSYS přepíše na cestu (`C:\Program Files\Git\analyzer;…`).
  Oprava: prefixni volání `MSYS2_ARG_CONV_EXCL="*"` (pak ale musí být
  všechny cesty plné Windows cesty, žádné `~`).
- **`/ruleset` s externím (https) includem** alc odmítne — „external rulesets
  are not allowed" a žádný CLI přepínač to nepovoluje (funguje jen ve VS Code
  přes `al.allowExternalRulesets`). Pro CLI check pusť analyzery bez rulesetu
  a nálezy filtruj jen na své soubory.
- **Trans-unit ID do ručních překladů:** po CLI kompilaci (s feature
  `TranslationFile`) se přegeneruje `Translations/*.g.xlf` — ID nových
  trans-unitů opiš odtud, není nutné počítat FNV-1a hash ručně (viz 6.2).

### 7.2 Čtení symbolů z `.alpackages` — al-mcp-server

MCP server [`al-mcp-server`](https://github.com/StefanMaron/AL-Dependency-MCP-Server)
(npm balíček `al-mcp-server`) umí číst stažené symboly přímo z `.alpackages`
aktuálního AL repa. Globálně nakonfigurovaný v **Claude Code**, **GitHub
Copilot CLI** i **Codex CLI**. Nástroje:

- `al_packages` — výpis dostupných app balíčků
- `al_search_objects` — hledání objektů (table, page, codeunit, report,
  enum…) napříč symboly
- `al_search_object_members` — hledání fields, procedur, triggerů uvnitř
  objektu
- `al_get_object_summary` — přehled objektu (members, properties)
- `al_get_object_definition` — plná definice objektu
- `al_find_references` — kde se objekt/member používá

**Konfigurace (globální, per-user):** Server běží přes `npx -y al-mcp-server`
(vyžaduje Node 18+ a .NET SDK 8+). Cwd MCP procesu = cwd, ze které je AI
klient spuštěný, takže `.alpackages` se najde sám, pokud klienta pouštíš z
root složky AL repa.

- **Claude Code**: `claude mcp add al-mcp-server -- npx -y al-mcp-server`
  (zapíše do `~/.claude.json`)
- **GitHub Copilot CLI**: `~/.copilot/mcp-config.json`

  ```json
  {
    "mcpServers": {
      "al-symbols-mcp": {
        "type": "stdio",
        "command": "npx",
        "args": ["-y", "al-mcp-server"]
      }
    }
  }
  ```

- **Codex CLI**: `~/.codex/config.toml`

  ```toml
  [mcp_servers.al-symbols-mcp]
  command = "npx"
  args = ["-y", "al-mcp-server"]
  ```

**Kdy co použít:**

- **Microsoft Base app / System app / CZ lokalizace** — nejdřív zkus
  `al-mcp-server` (rychlé, lokální). GitHub `StefanMaron/MSDyn365BC.Code.History`
  je fallback, když potřebuješ historii nebo větší kontext mezi soubory.
- **Třetí strany a zákaznické extension** (např. ForNAV, Continia, vlastní
  per-tenant extension) — `al-mcp-server` je **jediný způsob**, jak se na ně
  podívat. Na GitHubu ani context7 nejsou.
- **context7** — pouze pro oficiální MS docs / AL language reference, ne pro
  source code.

**⚠️ MCP vrací jen SIGNATURY, ne těla procedur (base app).** `al_get_object_definition`
u Microsoft base/system app vrátí parametry, návratový typ, properties a fields —
ale **ne implementaci**. Jakmile potřebuješ vidět **tělo procedury** (pochopit chybu
z call stacku, najít konkrétní řádek, vidět co volá / kde indexuje pole), MCP ti
nestačí a **nesmíš se zaseknout na hádání nad signaturou — jdi rovnou na GitHub**
(sekce 7.3). Workflow, který funguje:

1. `al_get_object_definition` vrátí pole **`ReferenceSourceFileName`**
   (např. `Foundation/Reporting/ReportLayoutsImpl.codeunit.al`) = přesná relativní
   cesta k souboru v repu. Vezmi z něj **název souboru**.
2. Najdi plnou cestu přes git tree (plná cesta bývá
   `BaseApp/Source/Base Application/<ReferenceSourceFileName>`):

   ```bash
   gh api "repos/StefanMaron/MSDyn365BC.Code.History/git/trees/<branch>?recursive=1" \
     --jq '.tree[].path | select(test("<NazevSouboru>";"i"))'
   ```

3. Stáhni tělo:

   ```bash
   gh api "repos/StefanMaron/MSDyn365BC.Code.History/contents/<path>?ref=<branch>" \
     --jq '.content' | base64 -d
   ```

`<branch>` ber dle `app.json` (`w1-27`, `cz-27`…, viz 7.3). Pozor: čísla řádků
v compiled call stacku (BC error) **nesedí** přesně na StefanMaron source (jiný
build) — orientuj se podle logiky procedury, ne podle čísla řádku.

Pro **třetí strany** je to obráceně: tělo procedury na GitHubu **není**, MCP
z `.app` symbolů taky vrátí jen signaturu — plný kód jen když máš jejich source
repo (sekce 7.6).

### 7.3 Práce s BC source na GitHubu

Repo: `https://github.com/StefanMaron/MSDyn365BC.Code.History`

**Výběr správné větve:**

- Větve jsou pojmenované konvencí `<country>-<major>`, např. `w1-27`, `w1-28`,
  `cz-27`, `cz-28`…
- **Major verzi neber natvrdo** — přečti `app.json` v aktuálním repozitáři
  (pole `"application"` nebo `"platform"`, např. `"27.0.0.0"` → větev `w1-27`)
- Pokud je v `app.json` `"28.0.0.0"`, použij `w1-28` (resp. `cz-28`) — verze
  BC se mění každých pár měsíců

**W1 vs CZ větev:**

- **W1 větev** (`w1-<major>`) — base app: Item, Sales, Purchase, Warehouse,
  Inventory, Posting routines, většina business logiky
- **CZ větev** (`cz-<major>`) — česká lokalizace: DPH, Intrastat, Cash Desk,
  Banking (ABO/Gemini), lokální reporty, daňové dokumenty, specifika české
  legislativy
- Když řešíš něco, co se dotýká české legislativy nebo lokálních objektů,
  **musíš se dívat do CZ větve**, ne do W1 — některé tabulky/codeunity v W1
  vůbec nejsou nebo mají jinou implementaci

**Tipy pro fetch:**

- Pro prozkoumání konkrétního souboru je často lepší **raw URL** než GitHub
  UI:

  ```
  https://raw.githubusercontent.com/StefanMaron/MSDyn365BC.Code.History/<branch>/<path>
  ```

- WebFetch na běžné GitHub URL může u dlouhých souborů vracet ořezaný obsah
- Seznam větví: `https://github.com/StefanMaron/MSDyn365BC.Code.History/branches`

### 7.4 AL-Go for GitHub — CI je zdroj pravdy

Pokud má repo **AL-Go for GitHub** (workflow files pod `.github/workflows/`,
typicky `CICD.yaml`, `PullRequestHandler.yaml`, `Current.yaml`, `NextMajor.yaml`,
`NextMinor.yaml`), pak build / test / publish flow řídí ten pipeline, ne tvůj
lokální AL extension. Při potížích:

- **Nebypassuj** workflow ručním `alc.exe` buildem a manuálním uploadem do
  sandboxu, když repo používá AL-Go — můžeš tím skrýt skutečný problém v
  konfiguraci. Místo toho oprav `settings.json` AL-Go (`.AL-Go/settings.json`),
  workflow inputs nebo dependencies, ať CI projde.
- Lokální dev container z AL-Go (`.AL-Go/cloudDevEnv-*.ps1`) je v pohodě —
  využívá stejnou konfiguraci jako CI, takže odhalí stejné chyby dřív.
- Když ti CI failne, podívej se do `pipelines` runu (Azure DevOps / GitHub
  Actions) na **build artifact `.app` files** a `BuildOutput.txt` — bývá tam
  konkrétnější diagnostika než v UI summary.

### 7.5 Nová appka v multi-app zákaznickém repu — postup

Zákaznická repa typicky drží víc appek vedle sebe (`base/app`, `pricingMatrixExtension/app`,
`configuratorExtension/app`…), sdílí jedny `.alpackages` a jeden VS Code workspace.
Když přidáváš další extension, nezakládej ji od nuly — **zkopíruj existující appku**,
máš tím rovnou launch.json, ruleset, lintercop, AppSourceCop, logo a strukturu složek.

**Postup:**

1. **Vyber šablonu.** Nejbližší co dělá to samé co tvoje nová appka (typicky
   nejnovější extension v repu). Zkopíruj celou složku, např.
   `cp -r pricingMatrixExtension configuratorExtension`.
2. **Vykliď kopii:**
   - Smaž zkopírované buildy (`rm *.app` v rootu appky)
   - Smaž obsah `src/` a `Translations/` (složky nech prázdné — kompilace si do
     Translations vygeneruje `.g.xlf`)
   - Smaž `.snapshots/` pokud tam je (per-app cache)
3. **Vygeneruj nový GUID** (`python -c "import uuid; print(uuid.uuid4())"` nebo
   `[guid]::NewGuid()` v PowerShellu). **Nikdy nerecykluj** GUID z původní
   appky — instalace by se hlásila jako update té druhé.
4. **Uprav `app.json`:**
   - `id` — nový GUID
   - `name` — finální název appky (typicky `<Customer> SE <Feature> Extension`)
   - `brief` — krátký popis k čemu je (objeví se v Extension Management)
   - `dependencies` — minimálně base/app repa (ta drží shared utilities a obvykle
     ostatní extension v repu na ní stojí) plus appka, kterou rozšiřuješ
   - `idRanges` — **unikátní blok** v repu, nepřekrývej s ostatními appkami
     (mrkni jejich `app.json`). Zákaznická repa drží přidělené rozsahy a v
     repu se domluv velikost na appku (typicky 10–40 ID na extension).
   - **ID jsou unikátní per typ objektu** — table, tableextension, page,
     pageextension, codeunit, enum, permissionset i permissionsetextension
     mají každý **vlastní ID namespace**. U těsného range (např. 20 čísel)
     proto **každý typ čísluje od začátku range** (`table 63210` +
     `page 63210` + `pageextension 63210` + `permissionsetextension 63210`
     vedle sebe v pohodě koexistují). Nedělej jeden globální counter napříč
     typy ani neposouvej extension typy „za" základní typ — zbytečně to
     pálí čísla z range.
5. **Per-app suffix** — každá extension v repu má **vlastní customer affix**
   kvůli AppSourceCop / LinterCop. Drží se na **dvou místech v appce**:
   - `.vscode/settings.json` → `"CRS.ObjectNameSuffix": "XXXX"` — pro CRS AL
     Language Extension (auto-rename souborů, generování objektů)
   - `AppSourceCop.json` → `"mandatoryAffixes": ["XXXX"]` — pro kompilátor +
     AppSourceCop (vynutí, že všechna nová pole/objekty mají affix v názvu)

   Affix volíme **per extension**, ne per repo — typicky 2-písmenný klíč
   featury + 2-3 písmenný customer kód (např. `PMALU` = Pricing Matrix +
   Alumistr, `COALU` = Configurator + Alumistr). Repo-level
   `CRS.ObjectNameSuffix` ve `*.code-workspace` je jen fallback pro složky,
   které vlastní settings nemají.

   Pro **Essence produktové appky** (rodina `prod-ef-*`, `prod-em-*`…) je affix
   místo customer kódu **`xxEBS`** (2 písmena featury + `EBS`, např. `APEBS` =
   Advance Payment, `VPEBS` = VAT Payer) a `AppSourceCop.json` používá
   `"mandatorySuffix": "EBS"` (objekty pak pojmenuj ručně `…xxEBS`). Před volbou
   `xxEBS` ověř, že kód není obsazený napříč repy — `azure-devops search_code`
   na `"<KÓD>"`, `count: 0` = volné (obsazené: AAEBS, ADEBS, ALEBS, ACEBS,
   EXEBS, ATEBS…). Kódy se mezi appkami neopakují.
6. **Přidej do workspace** — uprav `<repo>.code-workspace`, sekci `folders`,
   přidej `{ "name": "<appName>", "path": "<appFolder>/app" }`. Bez toho ji
   ve VS Code File Exploreru neuvidíš a CRS extension nebude vědět, kterou
   appku právě edituješ.
7. **(Volitelně) `launch.json`** — pokud má kopírovaná appka launch profil pro
   úplně jiný sandbox/tenant, uprav `environmentName` a `tenant`. V rámci
   jednoho zákaznického repa to ale obvykle sedí beze změny.
8. **Permission sety** — drž vzor base/app (sonnentor):
   - **NEDĚLEJ** permission set kvůli polím na `tableextension` /
     `pageextension` — extension fields dědí práva z base tabulky, takže
     `tabledata` na rozšiřovanou tabulku je zbytečné (a dává nadměrná práva).
   - **Vlastní permission set** appky dej **execute (`= X`) na codeunity a
     reporty** appky. Pokud appka má **vlastní tabulky**, přidej k nim
     `tabledata … = R / RIMD` (jako sonnentor `Quality Code SON`,
     `Item Text SON`). `Assignable = true`, `Access = Public`, `Caption` Locked.
   - Přidej **3 `permissionsetextension`** rozšiřující standardní role
     `D365 BASIC`, `D365 READ`, `D365 SETUP`, každá
     `IncludedPermissionSets = "<vlastní set>"` — tím se appka zařadí do
     standardních uživatelských rolí (jinak by admin musel set přiřazovat ručně).

   ```al
   permissionset 65529 "Advance Check APEBS"
   {
       Access = Public;
       Assignable = true;
       Caption = 'EF Advance Check', Locked = true;
       Permissions =
           codeunit "Sales Advance Mgt. APEBS" = X,
           report "Update Sales Adv. Status APEBS" = X;
   }

   permissionsetextension 65530 "D365 BASIC APEBS" extends "D365 BASIC"
   {
       IncludedPermissionSets = "Advance Check APEBS";
   }
   ```

**Co po kopírování NEMĚNIT (pokud nemáš důvod):**

- `runtime`, `platform`, `application` verze — drží konzistenci s repem
- `applicationInsightsConnectionString` — sdílený za customer/publisher
- `essence.png` (logo), `cust-<…>.ruleset.json`, `lintercop.json` — sdílené
  konvence pro celý repo

**Checklist před prvním commitem:**

- [ ] Nový GUID v `app.json` (ne recyklovaný)
- [ ] `idRanges` nepřekrývá žádnou jinou appku v repu
- [ ] `CRS.ObjectNameSuffix` v `.vscode/settings.json` = affix
- [ ] `mandatoryAffixes` v `AppSourceCop.json` = stejný affix
- [ ] `dependencies` ukazují na správné GUID + minimální verze, kterou app reálně potřebuje
- [ ] Přidáno do `<repo>.code-workspace`
- [ ] Permission set (execute codeunitů/reportů; tabledata jen pro vlastní tabulky) + `D365 BASIC`/`READ`/`SETUP` extensions
- [ ] Vyklizené `src/`, `Translations/`, žádné `*.app` artefakty v gitu

### 7.6 Source závislé appky — kde hledat plný kód (včetně triggerů)

`al-mcp-server` (7.2) i symboly z `.alpackages` ti dají **strukturu** objektu
(pole, properties, signatury procedur), ale **ne těla triggerů** (`OnLookup`,
`OnValidate`, `OnInsert`…) ani implementaci procedur. Když potřebuješ vidět
reálnou logiku závislé appky — typicky proto, abys ji 1:1 zopakoval ve své
extension — postupuj v tomhle pořadí:

1. **Nejdřív hledej sibling repo v `C:\WorkTasks`.** Závislosti zákaznických
   repů jsou často naše vlastní produktové appky, které tam máš naklonované
   jako **samostatný repozitář se zdrojákem**. Naming: `prod-*` = produktové
   appky, `cust-*` = zákaznické. Příklad: `cust-alumistr-bc` závisí na
   *Essence Configurator* → zdroj žije v
   `C:\WorkTasks\prod-ess-configurator-bc\app`. Otevři `app.json` kandidáta a
   ověř `name` / `id` proti `dependencies` své appky. Tohle je vždycky
   nejlepší — máš plný, aktuální a čitelný source bez extrakce.

2. **Pak extrakce source z `.app` — rovnou si přečti kód.** Číst reálný
   source je vždycky lepší než luštit strukturu z metadat. Když autor source
   do balíčku přibalil (`allowDownloadingSource` / `includeSourceInSymbolFile`
   — naše produktové appky to obvykle mají), `.app` v `.alpackages` je **ZIP
   s ~40-bytovou hlavičkou** — ZIP data začínají signaturou `PK\x03\x04`.
   Najdi offset, odřízni hlavičku, rozbal:

   ```powershell
   $bytes = [System.IO.File]::ReadAllBytes($appPath)
   # najdi PK\x03\x04 v prvních ~100 bytech
   $idx = 0..100 | Where-Object {
       $bytes[$_] -eq 0x50 -and $bytes[$_+1] -eq 0x4B -and
       $bytes[$_+2] -eq 0x03 -and $bytes[$_+3] -eq 0x04
   } | Select-Object -First 1
   $zip = New-Object byte[] ($bytes.Length - $idx)
   [Array]::Copy($bytes, $idx, $zip, 0, $zip.Length)
   [IO.File]::WriteAllBytes("$out\pkg.zip", $zip)
   Expand-Archive "$out\pkg.zip" $out -Force
   # .al soubory (vč. trigger těl) pak najdeš v $out\src\...
   ```

   Extrakci po sobě **ukliď** (temp složka mimo git / gitignore). Tohle není
   v rozporu s 9.3 — pravidlo „`.alpackages` nečíst přes Read/cat/grep" platí
   pro přímé čtení binárky; tady ji řízeně rozbalíš PowerShellem.

3. **`al-mcp-server`** (7.2) jako rychlý fallback / vyhledávač — když source
   není přibalený (`.app` neobsahuje `src/`), nebo ti stačí jen rychle najít
   objekt / pole / signaturu / reference napříč **všemi** symboly
   (`al_search_objects`, `al_find_references`) bez rozbalování. Pozor:
   trigger / procedure těla neukáže — na reálnou logiku se vrať ke kroku 2.

### 7.7 Git commit / push / PR — **nikdy nedělat sám, ani commit**

Lokální git operace, které jsou OK bez vyžádání:

- `git checkout` / `git checkout -b` (přepínání a vytváření branchů)
- `git add` / `git restore --staged` (stage / unstage do indexu — neměnný
  hash, jen příprava)
- `git cherry-pick`, `git merge`, `git rebase` (pokud uživatel nepoví jinak)
- `git stash`, `git restore` (lokální správa working tree)
- `git fetch`, `git pull --ff-only` (synchronizace s origin pro read)
- `git reset --soft` / `git reset` (zpětné rušení commitů, když uživatel
  řekne; měnit historii bez pokynu ne)

**Co NEDĚLAT bez explicitního vyžádání:**

- `git commit` (ani na feature branch, ani amend) — *commit* už mění
  historii, kterou bude uživatel potřebovat upravit / squashnout / zahodit
- `git push` (ani `-u origin`, ani `--force`, ani na nový branch)
- `git push --delete` / mazání remote branchů
- Vytváření Pull Requestů (`mcp__azure-devops__repo_create_pull_request`,
  `gh pr create`, jakákoli jiná cesta)
- Mergování do master / shared branche

**Po dokončení lokální práce:**

1. Změny nech jako **unstaged / staged** v working tree, **necommituj**.
2. Zastav a oznam uživateli: *„Změny pro `<task>` jsou připravené v
   working tree — můžeš zkontrolovat a zacommitovat / pushnout."* Uveď
   stručný souhrn co se změnilo a v jakých souborech.
3. Čekej na další pokyn. *Commit / push / PR provedu, až dostanu výslovný
   povel* („zacommituj to", „push to", „otevři PR", apod.).

**Proč:**

- Uživatel chce konsolidovat víc změn do jednoho commitu / PR podle
  vlastního uvážení (parent PBI vs. dělené tasky), volit přesné commit
  message, případně z části změn slevit.
- Commit, push a PR mají dopad na CI pipeline a review timing — to je
  rozhodnutí uživatele, ne moje.
- Když rovnou commitnu / pushnu, vede to k nadbytečným reset/rebase
  manévrům na úklid.

### 7.8 Verzování `app.json` — nepovyšovat sám

`version` v `app.json` (ani jinou formu verzování extension) **neměnit z
vlastní iniciativy** — verze je součást release procesu, který si řídí
uživatel ručně podle vlastní konvence (kdy se major povyšuje).

- **Pro PR** musí být verze ve tvaru **`XX.0.0.0`** (jen major, zbytek nuly —
  např. `27.0.0.0`). Mezilehlé tvary (`27.0.5.1`) můžou být přechodné během
  vývoje, ale do PR je uživatel sám sníží na `XX.0.0.0`.
- Když uživatel **výslovně** řekne „povyš verzi na X" → uděláš.
- V dokumentačních MD (sekce 8) **nezmiňuj aktuální verzi** extension jako
  součást scope ticketu — verze se mění nezávisle.
- Při code review neobvyklý tvar verze (`27.0.5.1`) jen **zmiň**, neřeš za
  uživatele.

**Proč:** Automatický bump rozhodí release workflow / PR validaci. Verzování
je rozhodnutí uživatele, ne moje (stejná logika jako git commit/push/PR — 7.7).

### 7.9 Azure DevOps MCP — tickety, PRs, pipelines

Tickety a repa Essence BC projektů (Zlomek, Kalas, JIRI, produktové appky…)
žijí v Azure DevOps org **`essencebs`**, projekt **`Projects`**. Work item URL:
`https://dev.azure.com/essencebs/Projects/_workitems/edit/<ID>`.

Když uživatel zmíní číslo ticketu („task 64359", „bug 62667") nebo pošle
`dev.azure.com/essencebs/...` URL, sáhni po MCP serveru **`azure-devops`**
(`@azure-devops/mcp`, globálně v `~/.claude.json`, PAT auth, loaduje se sám):

- `wit_get_work_item` (id) — fetch ticketu; `expand: all` přitáhne i parent /
  relations
- `wit_my_work_items`, `search_workitem` (fulltext)
- `wit_create_work_item`, `wit_update_work_item`, `wit_add_work_item_comment`
- `repo_*`, `pipelines_*`, `wiki_*`, `core_*` — PRs, buildy, wiki, identity

**Vazba na repo:** Ticket většinou neuvádí, do kterého repa patří — odvoď z
**CWD** (`cust-zlomek-bc` = Zlomek, `prod-epb-pricingMatrix-bc` = produktová
Pricing Matrix…), z Area Path a Iteration Path.

**PAT:** base64(`email:rawPAT`) v `env.PERSONAL_ACCESS_TOKEN` v `.claude.json`,
scope min. Work Items R&W, expiruje ~90 dní (firemní policy). Po expiraci
vygeneruj nový na `https://dev.azure.com/essencebs/_usersSettings/tokens`,
zakóduj a přepiš v `.claude.json` (session pak restartovat).

**Gotcha — IPv6 reset (ECONNRESET):** Některé MS endpointy (`aex.dev.azure.com`)
resolvují primárně na IPv6 a corp síť/firewall jejich spojení **resetuje**
(`fetch failed` / „Failed to fetch tenant for ADO org essencebs"). IPv4 přes
stejný host funguje. Fix: `NODE_OPTIONS=--dns-result-order=ipv4first` v `env`
sekci toho MCP serveru v `.claude.json` (ne globálně). Stejný workaround platí
pro jakýkoli Node/npm MCP server volající MS API (Graph, M365…).

---

## 8. Dokumentace requirements (PBI/Task → MD)

Pro každý dodělaný PBI / Task v Azure DevOps se v zákaznickém repu vede
Markdown s popisem requirementu a technickou dokumentací implementace.

**Kam to patří:**

```
<repo-root>/docs/<PBI-ID> - <feature-kód> - <krátký popis>.md
```

Příklad: `docs/63103 - FIN_039 - Kontrola EU zák. plátce DPH.md`.
Pokud `docs/` ještě neexistuje, vytvoř ji. **Žádná podsložka
`requirements/`** — všechny ticketové MD jdou rovnou do `docs/`.

**Co MD obsahuje (v tomhle pořadí):**

1. **Meta info** — PBI/Task ID, parent, customer, area, iterace, stav,
   assigned to, vytvořeno (kdo + datum), effort, priorita, External ID,
   sourozenecké tickety pokud sdílí implementaci.
2. **Upravené appky** — tabulka `Appka | Repo | Typ změny`. Zachyť
   **každou appku, kterou tahle implementace mění** (nová appka, úpravy
   stávající extension, úpravy base / dependency appky). Závislosti, ze
   kterých jen čteš, sem nepatří — ty jdou do "Technické dokumentace".
   Použij customer affix v závorce, ať čtenář hned ví, čí extension to je.
3. **Description** — popis řešení z PBI (obvykle z parent PBI, pokud je
   zdrojem Task, který má description prázdný).
4. **Acceptance Criteria** — pokud existují (často nejsou explicitní →
   sekci pak vynech).
5. **Odkazy v popisu** — přepiš odkazy z HTML descriptionu (Dataverse
   incident, BC Job Planning Line, BC Job, …) jako Markdown linky.
6. **Příklad využití v reálu** — co uživatel reálně udělá, krok po kroku
   (golden path + případné edge case scénáře).
7. **Technická dokumentace** — **jen pokud se reálně dělaly** nové objekty
   nebo nová pole:
   - Tabulka nových objektů (typ, ID, název, krátký popis funkčnosti)
   - Tabulka nových polí (tabulka, ID, jméno, typ, popis)
   - Datový tok / event flow (textově nebo ASCII diagram pro neintuitivní
     propagaci přes víc tabulek/codeunit)
   - Codeunits a reporty — krátký odstavec o roli (jaké eventy odběrá,
     co dělá, kdy se spouští)

   **Pokud žádný nový objekt nebo pole, sekci úplně vynech.**

**Konvence obsahu:**

- Identifikátory (názvy objektů, polí) drž **anglicky** — stejně jako kód
  (viz 1.1). Popisy a kontext česky.
- Technická dokumentace cílí na vývojáře, který se k ticketu vrátí za půl
  roku — ne na koncového uživatele. Stručné, věcné, bez marketingových
  obratů.
- Když implementace pokrývá víc PBI (např. FIN_039 EU + FIN_041 CZ sdílí
  jeden codeunit), zmiň to v meta info v sekci „Sourozenecké PBI" a
  technickou dokumentaci napiš jen jednou (do MD toho hlavního PBI).
- Odkazy na DevOps work itemy: `https://dev.azure.com/essencebs/Projects/_workitems/edit/<ID>`.

**Proč:**

- Repo má jeden zdroj pravdy o tom, **co bylo dodáno a jak** — bez nutnosti
  mít otevřenou DevOps a hrabat se v komentářích.
- Při code review / regresi za půl roku má vývojář kontext po ruce.
- Pomáhá při handoveru projektu jinému týmu / customer success.

**Workflow tip:** MD piš až po dokončení implementace, ne při startu —
ujistí se, že popis odpovídá tomu, co je opravdu nasazené, a že
technická dokumentace nezakonzervuje původní (pravděpodobně neaktuální)
představu z PBI descriptionu.

---

## 9. Před úpravou AL objektu — co si přečíst

Než sáhneš na objekt, projdi si pár věcí — ušetří ti to zmatky typu "stejně se
jmenující procedura znamená v jiném scope něco jiného" a "tahle API vůbec na
Cloudu neexistuje".

### 9.1 Hlavička objektu

Přečti si **prvních pár řádek objektu**: `id`, `namespace` (pokud je),
deklarace (`tableextension X extends Y` vs `table X`). Stejný název procedury
může v jiném scope znamenat něco úplně jiného. U extension navíc rozlišuj,
**zda rozšiřuješ base app, jinou MS appku, nebo 3rd-party** — určuje to, kde
hledat eventy a jaké patterny použít.

### 9.2 `app.json` — vždycky před netriviální změnou

Než navrhneš řešení, kouni do `app.json` a zaznamenej:

- **`idRanges`** — kam smíš dávat nová ID
- **`dependencies`** — co máš dostupné, jakou verzi
- **`target`** — `Cloud` vs `OnPrem` (rozhoduje o tom, co můžeš použít —
  viz sekce 10 a 11)
- **`runtime`** a **`platform`** — určují, které moderní featury jsou
  dostupné (namespaces od runtime 11.0, atd.)
- **`application`** — verze BC, na kterou stavíš

Bez toho návrh často sjede do "ano použijeme namespaces" v repu, který je
na runtime 9.0, nebo do `DotNet` callu v Cloud extensionu.

### 9.3 `.alpackages/` je **binární ZIP** — nečíst přes Read/cat/grep

Velký pozor: `.alpackages/*.app` soubory jsou **podepsané ZIPy se symboly a IL**.
Když je zkusíš otevřít přes `Read`, `cat`, `head`, `Grep`, dostaneš odpadky
nebo error a může to vypadat jako že symbol neexistuje — což není pravda.

Pro lookup symbolů ze závislostí použij (v pořadí preference):

1. **`al-mcp-server`** (viz 7.2) — strukturovaný symbol lookup ze `.alpackages`.
   Funguje na MS base/system app, CZ lokalizaci, ForNAV, Continia, vlastní
   per-tenant extensions atd. **Tohle je primární nástroj.**
2. **VS Code AL extension** — Go to Definition (F12), Find All References,
   AL Object Browser. Vyžaduje, aby uživatel byl ve VS Code — pokud asistuješ
   přes CLI, nech si to udělat uživatelem.
3. **Microsoft Learn MCP** — pro **standardní** BC objekty (base app tables,
   codeunits, pages od Microsoftu). Aktuální dokumentace, čistý markdown.
4. **GitHub `StefanMaron/MSDyn365BC.Code.History`** (viz 7.3) — pro hluboký
   kontext, historii změn, nebo pokud potřebuješ vidět víc souborů najednou.
5. Vygenerované `.dal` text artefakty (pokud projekt produkuje) — fallback.

**Pokud jméno procedury "zní správně", ale nedokážeš ho potvrdit přes některý
z výše uvedených zdrojů, ber to jako že neexistuje.** Lepší se zeptat /
ověřit než vygenerovat call na neexistující signature.

### 9.4 Permission set kontrola

Když měníš permission-relevantní objekt (tabulka, codeunit se sensitivní
logikou, nový report obsahující změnu dat), **ověř nebo aktualizuj příslušný
`permissionset`**. Repa typicky mají per-app permission set objekt
(`<App> Permission Set XXXX.PermissionSet.al`) — drž ho v synchronizaci.

---

## 10. Moderní AL patterny — výběr podle `app.json`

BC se hýbe rychle. Namespaces, interfaces, isolated storage, Cloud-first
patterny jsou tady, ale training data + starší code stále tlačí na deprecated
přístupy. **Pravidlo palce: vyber nejnovější pattern, který runtime projektu
podporuje — ne nejnovější pattern, který si pamatuješ.**

### 10.1 Workflow před výběrem patternu

1. **Otevři `app.json`** a podívej se na `application`, `platform`, `target`.
2. **Pak vybírej:** modernější pattern preferuj, ale jen pokud ho runtime
   uvezene.
3. **Nedowngraduj** repo, který už moderní patterny používá. Pokud existující
   kód má namespaces a interfaces, **drž to** — nezačínej míchat flat namespace
   a enum-with-Case-dispatch "pro jistotu".
4. **Nestavěj featuru, kterou runtime neumí.** Pokud `application` = `21.0.0.0`
   a projekt nemá namespaces, nepřidávej je sám. Zmiň upgrade path v PR
   description, pokud to dává smysl.

### 10.2 Konkrétní moderní patterny

- **Namespaces** (BC22+, runtime 11.0+) — pro nové moduly. Drž konvenci
  existujícího projektu. Nemíchej namespaced a non-namespaced soubory v jednom
  modulu, pokud projekt už nemíchá.
- **Interfaces** + implementující codeunits (BC17+) — místo enum + `case ...
  of` dispatchu, když chování závisí na typu. Lepší extensibilita a čistší
  testy.
- **Isolated Storage** — per-tenant secrets (API tokeny, OAuth credentials).
  **Ne** vlastní hidden tabulka.
- **`SecretText`** (BC22+) — pro credentials, které putují mezi procedurami.
  Místo plain `Text`. Runtime ho neloguje a hlídá si propagaci.
- **Member metody na DateTime** (novější runtime) — `DT.Date()`, `DT.Time()`
  místo `DT2Date(DT)`, `DT2Time(DT)`. LinterCop to vynucuje přes **LC0083**
  („Use the new method X.Time() to extract specific parts of date/time
  values"). Stejný pattern: `JsonHelper.GetDateTime(...).Date()`.
- **LC0088** („Option types should be avoided, use enum") má **odůvodněný
  false positive**: lokální `Option` proměnná deklarovaná kvůli volání System
  App API, které Option parametr vyžaduje (např. `Cryptography
  Management.GenerateHash(..., HashAlgorithmType: Option HMACMD5,HMACSHA1,
  HMACSHA256,...)`). Enum do Option parametru předat nejde — info nech být
  nebo lokálně potlač pragmou.
- **Telemetrie** — `Session.LogMessage(eventId, message, verbosity, dataClass,
  scope, ...)` se stabilním event ID a verbosity. **Ne** free-form `Message()`
  / `Error()` pro logging. Eventy se pak dají filtrovat v Application Insights.
- **Permission sets jako AL objekty** (`permissionset 50001 "My App" { ... }`)
  místo XML souborů. Nový kód = AL objekt vždycky.
- **API pages / API queries** pro integrační endpointy. **Ne** custom OData
  webservice pages (Search webservice tabulkou) pro nové integrace.

### 10.3 Cloud target — čeho se vyhnout

V extensionu s `"target": "Cloud"` v `app.json` **nepoužívej**:

- `DotNet` — compiler ji odmítne (občas to neudělá hned, runtime padne)
- `File` namespace přes filesystem (`File.Open`, …) — místo toho streaming +
  `DownloadFromStream`/`UploadIntoStream`
- `XmlPort` s `Format = Variable Text` čtený z filesystému — stejně, streaming
- `Automation` (COM) — OnPrem-only
- `WindowsLanguage` a podobné Windows-only API

Model ti tyhle věci občas navrhne — odmítni a použij Cloud-kompatibilní cestu
(streaming přes `InStream`/`OutStream`, `HttpClient`, …).

### 10.4 Když si nejsi jistý API — ověř, nehádej

Pro AL syntax, BC API reference a analyzer rule descriptions je **Microsoft
Learn MCP** preferovaný zdroj (`microsoft_docs_search`, `microsoft_docs_fetch`,
`microsoft_code_sample_search`) — vrací čistý markdown, je aktuální.

Pro LinterCop pravidla Microsoft Learn nepomůže — použij web search na kód
pravidla (např. `LC0086`) nebo přímo LinterCop wiki na GitHubu.

**Training memory ber jako hint, ne fakt** — zvlášť u věcí kolem BC22+,
namespaces, interfaces, `SecretText`, nedávných analyzer rules.

---

## 11. SaaS gotchas — HttpClient a Cloud target

### 11.1 HttpClient na SaaS — silent fail bez Allow HttpClient Requests

V SaaS sandboxu / produkci `HttpClient.Get()` / `HttpClient.Send()` může
vracet **`false` s prázdným `GetLastErrorText()`**, pokud extension nemá
povolený outbound HTTP. Uživatel to musí povolit v:

**Extension Management → najít extension → Configure → zapnout
"Allow HttpClient Requests"**

Důsledky pro vývoj:

- **V README** příslušné appky to popsat — "tato extension volá X, vyžaduje
  zapnutý Allow HttpClient Requests".
- **V kódu** mít čistou error message — pokud `Send`/`Get` vrátí `false` a
  `LastErrorText` je prázdný, je to skoro jistě tohle. Hlasit uživateli
  konkrétně, ne generic "HTTP failed".
- **V container / OnPrem buildu toggle neexistuje** — HTTP funguje vždycky.
  Rozdíl mezi dev container a SaaS je častý zdroj zmatku ("u mě to fungovalo!").
  Při hlášení problému vždycky řekni, **na jakém scope jsi testoval**.

### 11.2 `HttpClient.UseDefaultNetworkWindowsAuthentication()` = OnPrem-only

Compiler ji v `target: "Cloud"` extensionu **přijme** (!), ale runtime padne.
Pro Cloud target tuhle metodu nepoužívej. Pokud potřebuješ autentizaci, jdi
přes OAuth (`SecretText` token v `HttpRequestMessage` headerech) nebo Basic
auth se secretem z Isolated Storage.

### 11.3 Další Cloud-only gotchas

- `HttpClient.SkipDefaultUserAgentSet := true` — funguje, ale BC ti pak
  posílá header `User-Agent: Dynamics 365 Business Central` defaultně.
  Pokud cílový endpoint kontroluje UA, nastav vlastní.
- `Codeunit.IsolatedStorage` má **scope** parametr (`User`, `Company`,
  `CompanyAndUser`, `Module`). Module je defaultní pro per-extension secrets
  — sdílené napříč companies, izolované od jiných extension.

### 11.4 `SecretText.Unwrap()` = OnPrem-only (AL0296)

`SecretText` jde na Cloud targetu vytvořit i poslat do HttpClient headeru
(`SecretStrSubstNo`), ale **zpátky na Text ho nedostaneš** — `Unwrap()` má
scope OnPrem a compiler hodí `AL0296: ... has scope 'OnPrem' and cannot be
used for 'Cloud' development`.

Důsledky:

- Hodnota, kterou někdy potřebuješ v plaintextu (HTML formulář ke stažení,
  query string, obsah souboru), **nesmí žít jen v SecretText / Isolated
  Storage** — ulož ji jako normální pole setup tabulky. Typicky OAuth
  `client_id`: posílá se stejně v browser formuláři, není to secret (na
  rozdíl od `client_secret`).
- Crypto nad secretem řeš overloady, které berou SecretText jako parametr:
  `Cryptography Management.GenerateHash(InputString: Text; Key: SecretText;
  HashAlgorithmType: Option HMACMD5,HMACSHA1,HMACSHA256,HMACSHA384,HMACSHA512): Text`
  spočítá HMAC bez unwrapu a vrátí **UPPERCASE hex** (ne Base64) jako plain
  Text. Lowercase hex → `LowerCase()`.

---

## 12. Verifikace a analyzery (AA / CA / PTE / LC)

### 12.1 Po každém AL editu — build a čti diagnostiku

Po každé netriviální změně AL kódu spusť **build** (přes VS Code AL
extension `AL: Package`, přes `alc.exe`, viz 7.1, nebo přes CI při pushi).
Diagnostika přijde ve čtyřech rodinách rulů — všechny mají svůj smysl:

- **AA-series** — Microsoft AL analyzer (oficiální AL rules)
- **CA-series** — CodeCop (style + best practices od MS)
- **PTE-series** — Per-Tenant Extension rules (specifické pro PTE distribution)
- **LC-series** — LinterCop (community analyzer, často nejpřísnější)

Některá pravidla jsou informational (`LC0082` info-level "Count > 1"), jiná
warning, jiná error. Default behavior závisí na `ruleset.json` v repu —
zákaznická repa typicky mají vlastní ruleset, který upravuje severities.

### 12.2 Když nevíš, co pravidlo znamená — vyhledej

Neopravuj warning naslepo přepsáním kódu. **Najdi popis pravidla:**

- **AA / CA / PTE** — Microsoft Learn MCP server (`microsoft_docs_search` s
  kódem pravidla, např. `AA0233`)
- **LC** — Microsoft Learn nepokrývá; jdi web search na `LC0086` nebo přímo
  LinterCop wiki na GitHubu (`StefanMaron/BusinessCentral.LinterCop` wiki).

Některá pravidla jsou v rozporu (typický příklad: `LC0082` říká "nahraď
`Count() > 1` smyslem `FindFirst() + Next()`", ale tím triggeruješ `AA0233`
+ `AA0181`). U malých filtrovaných setů (např. po `SetSelectionFilter`) je
`Count() > 1` v pohodě a `LC0082` se dá ignorovat. Vždycky si ověř, **co je
v daném kontextu nejmenší zlo**.

### 12.3 Runtime errory — žádné spekulační smyčky

Když ti při běhu BC vyletí error, **nedělej dva tři pokusy "co kdyby" v
kódu na základě domněnek o tom, jak vypadá data.** Stack + error message
typicky ukazují na konkrétní field / record / operaci.

Workflow:

1. Z chyby vyčti **co konkrétně se rozbilo** (table, field, codeunit, řádek).
2. Udělej **nejpravděpodobnější fix** podle textu chyby a stacku.
3. **Build, publish, předej uživateli k re-runu na jeho datech.**
4. Iteruj na **výsledcích reálného běhu**, ne na hypotézách "data asi vypadají
   takhle".

Loop "fix → guess data → fix → guess data" bez skutečného běhu utopí hodinu
za nic.

### 12.4 Essence build — ruleset per projekt konvencí

Essence BC build (`azure-pipelines.yml` → template `ALBuildPipeline2.yml` →
`CompileALApps2.yml` → `scripts/CompileALApps2.ps1`, repo
**tools-devops-essence-bc-yaml-lib@v2-0** v ADO org essencebs) aplikuje ruleset
**per projekt konvencí** — pro každou složku s `app.json` najde **první
`*Ruleset*.json` rekurzivně v té složce** a předá ho kompilátoru:

```powershell
$useRulesetFile = (Get-ChildItem -Path $appFolder -Recurse -Filter '*Ruleset*.json').FullName | Select-Object -First 1
```

`-Filter` je case-insensitive → matchuje i `*.ruleset.json`. `externalRulesets`
default **true** (HTTP `includedRuleSets` jako essence-default povolené).
`failOn = 'warning'` → **jakýkoli warning failuje build**.

**Co NEfunguje:**

- **`app.json` `"ruleSetPath"`** → `error AL0124` (není podporovaná property
  pro app.json v AL 17 / runtime 16). Build breaker.
- **`.vscode/settings.json`** je gitignored (`**/.vscode` v `.gitignore`) →
  `al.ruleSetPath` tam je jen lokální, do buildu se nedostane.
- **`.code-workspace` `al.ruleSetPath`** řídí jen VS Code editor, **ne** build.

**Správně = `*Ruleset*.json` přímo ve složce projektu** (vedle `app.json`).
Build ho najde sám. Tak to dělá prod-ess-configurator-bc
(`app/ess-configurator.ruleset.json`, `test/ess-configurator-test.ruleset.json`).
Test ruleset typicky dědí root přes `includedRuleSets`
(`..\..\<repo>.ruleset.json`) a přidá výjimky (např. `LC0015` Hidden —
permission set coverage netřeba pro test codeunity).

