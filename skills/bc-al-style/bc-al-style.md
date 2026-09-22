# BC/AL poznámky — Styl & psaní kódu

> Část rozděleného `bc-al-notes.md` (rozsekáno 2026-06-23; archiv: `bc-al-notes.archived-2026-06-23.md`).
> UI patterny stránek (sekce 4) vyčleněny 2026-09-08 do `bc-al-ui.md`.
> Načítej, když řešíš: konvence kódu, naming, Description/ToolTipy, prefixy, permission sety, přidělování ID,
> locale pasti (Format/Evaluate), moderní AL patterny podle app.json.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **1.** Konvence kódu a stylu
- **10.** Moderní AL patterny — výběr podle `app.json`

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
├── permissionset/
└── permissionsetextension/
```

**Permission sety — konkrétní konvence (ověřeno napříč repy, např.
`prod-ef-advanceCZ-bc`, `prod-em-operOutputChaining-bc`):**

- `permissionset` a `permissionsetextension` jsou **dva typy → dvě složky**:
  `src/permissionset/` a `src/permissionsetextension/`. Nemíchat je do jednoho
  souboru ani do jedné složky.
- **Jeden objekt = jeden soubor** (per objekt, ne per typ).
- Hlavní set: `<AppName>.PermissionSet.al`
  (např. `EFAdvanceCZ.PermissionSet.al`, `OperOutputChaining.PermissionSet.al`).
- Extension souboru pojmenuj **podle base setu, který rozšiřuje** (ne podle
  vlastní appky), se sufixem `.PermissionSetExt.al`:
  `D365BASIC.PermissionSetExt.al`, `D365READ.PermissionSetExt.al`,
  `D365SETUP.PermissionSetExt.al`. Typicky tři — extends `D365 BASIC` /
  `D365 READ` / `D365 SETUP`, všechny přes `IncludedPermissionSets` zatáhnou
  hlavní set appky.

**Vrstvení rolí (read / operate / admin):** když appka má setup/mapy + logy +
spouštění synců, nedávej jeden fat set s RIMD do všech tří D365 extensionů —
čtecí uživatel pak může editovat setup a mazat logy (např. import log = ochrana
proti duplicitnímu importu). Místo toho tři sety skládané přes
`IncludedPermissionSets`: **Read** (R na vlastní tabledata + X na view stránky)
⊂ **Oper** (X na sync codeunity + hub page + insert do log tabulek) ⊂ **Admin**
(RIMD všech vlastních tabulek + setup page + connect/install codeunity).
Mapování: `D365 READ` → Read, `D365 BASIC` → Oper, `D365 SETUP` → Admin. Zápisy,
které dělá běh syncu (watermarky v setupu, import log, mirror tabulky), pokryj
`Permissions` property na sync codeunitách (elevace jako u posting codeunitů) —
Oper pak nepotřebuje přímý write na setup. Pozor: nepočítej s tím, že se elevace
přenese do volaných objektů — base app si každý posting codeunit deklaruje
vlastní `Permissions` a base codeunity bez ní (např. `Create Reserv. Entry`)
potřebují, aby **uživatel** měl grant přímo (proto Oper dostane např.
`Reservation Entry = RIMD` napřímo). Při refactoru existujícího setu zachovej
původní object name admin setu — přiřazení v Access Control vážou na Role ID.

**⚠️ PTE0018 — base-app granty nesmí být PŘÍMO v setu, který jde do
`permissionsetextension`.** PerTenantExtensionCop hlásí „permission set should
not be included through a permission set extension because it includes
permissions for objects defined in another application" — a Essence CI jede
`failOn warning`, takže to shodí build. Fix: cross-app tabledata vyčlenit do
samostatného **neassignable** setu (`Assignable = false`, „stavební blok") a do
role setu ho zatáhnout přes `IncludedPermissionSets` — **rule kontroluje jen
přímé Permissions includovaného setu, tranzitivní includes neprochází** (ověřeno
na buildu 27684: D365 SETUP ext s tranzitivními base granty warning nedostal,
D365 BASIC ext s přímými ano). Efektivní práva zůstávají stejné.

**⚠️ PTE0012 (InternalsVisibleTo) + Essence CI ruleset:** repo ruleset
`<repo>.ruleset.json` v rootu se do `CompileALApps2.ps1` **sám nepředá** —
fallback skriptu hledá `*Ruleset*.json` jen rekurzivně UVNITŘ app folderu
(= konvence z 12.4 v bc-al-workflow: ruleset patří do složky projektu vedle
`app.json`, vzor prod-ess-configurator-bc). Bez rulesetu každý warning
(i PTE0012, které má každé repo s test appkou na internals) shodí build.
Dvě funkční cesty: (a) **konvence** — ruleset soubor per app folder, build
ho najde sám; (b) override `compileSteps` v `azure-pipelines.yml` (kopie
defaultu ze šablony ALBuildPipeline2 + `rulesetFile:
'$(System.DefaultWorkingDirectory)\<repo>.ruleset.json'`; template s aliasem
`templates\CompileALApps2.yml@essence_templates` — vzor cust-smartwings/kalas/
suys) — takhle jede dotykackaConnector, ruleset v rootu se pak aplikuje na app
i test projekt. PTE0012 v rulesetu jako Hidden s justification. (2026-08-05,
prod-ess-dotykackaConnector-bc, buildy 27684/27689.)

**⚠️ `permissionset` název objektu má limit 20 znaků (AL0305) — ne 30!**
Na rozdíl od skoro všech ostatních AL objektů (codeunit/table/page/report…
mají 30 znaků) je identifikátor permissionsetu omezený na **20 znaků** (mapuje
se na `Role ID` v Access Control). Pozor: suffix firmy (`OOEBS`, `AOEBS`,
`ZLK`…) + mezera žere ~6 znaků, takže na vlastní název zbývá ~14 → dlouhé app
názvy se **musí zkrátit**. Příklad: codeunit klidně `"Oper. Output Chaining
OOEBS"` (27 zn., OK), ale stejnojmenný permissionset to **nezkompiluje** —
zkráceno na `"Oper Output Ch OOEBS"` (20 zn.). `Caption` limit nemá, takže
plný název dej tam (`Caption = 'EM Operation Output Chaining'`) — to uživatel
vidí v UI; zkrácený object name je jen interní identifikátor.
(Zjištěno 2026-06, `prod-em-operOutputChaining-bc`.)

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
- **Pozor: `reportextension` property `Description` NEMÁ** — kompilátor hodí
  `AL0124` ("The property 'Description' cannot be used in this context").
  Na rozdíl od `tableextension` / `pageextension`. Účel reportextension popiš
  běžným `//` komentářem nad objektem. (Ověřeno 2026-06, Sonnentor reportext
  54800 na `Shpfy Add Item to Shopify`.)

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

- **Max ~200 znaků.** Delší ToolTip zestručni — detaily (fallback chování,
  dědění, edge case) patří do `Description` objektu nebo dokumentace, ne do
  ToolTipu. Jeden krátký příklad se do limitu vejde a je cennější než výčet
  všech větví logiky. (Feedback DNEM 2026-07, Sonnentor VYR-169.)
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

### 1.8 Prefix `Temp` — jen pro skutečně temporary recordy (CodeCop AA0073 / AA0237)

Prefix `Temp` u proměnné typu `Record` je v AL **rezervovaný pro
`Record X temporary`**. CodeCop na to má dvě pravidla: **AA0073** (temporary
proměnná musí mít prefix `Temp`) a **AA0237** (ne-temporary proměnná ho mít
nesmí). Obě jsou default Warning → na Essence CI (`failOn warning`) shodí build.

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

### 1.9 `StyleExpr` — `Text`/`Boolean`/`Code` proměnná plněná `Format(PageStyle::X)`, ne string literal (LC0086)

Property `StyleExpr` na page kontrolu **nepřijímá** `PageStyle` enum přímo — akceptuje
jen `Boolean`, `Text` nebo `Code` (enum přímo = chyba kompilátoru). Na druhou stranu
hardcoded string literál (`LineStyle := 'Favorable'`) hlásí LinterCop **LC0086**
(„Use the new `PageStyle` datatype instead string literals"). Správná cesta je
tedy kombinace obojího: pomocná proměnná + `Format(PageStyle::X)`.

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

**LC0035 — pole na tableextension, které není na žádné page:** LinterCop
(„Explicitly set AllowInCustomizations for fields omitted on pages") chce u
custom pole, které nepřidáš na žádnou page přes pageextension, **explicitní**
`AllowInCustomizations`. Rozhodni podle povahy pole:
- **Interní výpočetní FlowField / pomocné pole** (nemá user value) →
  `AllowInCustomizations = Never`.
- **Business pole, které jen omylem chybí na page** → radši ho **doplň na
  page** (pageextension) — LC0035 zmizí a je to konzistentní. `Never` použij,
  jen když pole opravdu nemá být vidět. (2026-06, `prod-em-operOutputChaining-bc`:
  pole bylo na 6 routing/journal pages, jen na Planning Routing chybělo →
  doplněn pageextension místo potlačení.)

### 1.11b Typed `Record` před `RecordRef.Open(...)` + ruční iterací polí

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

### 1.11c Array parametry — kompilátor NEkontroluje velikost (jen typ prvku)

AL compiler (ověřeno alc 17.0) **nehlásí chybu**, když do `var` parametru typu
`array[2] of Integer` předáš proměnnou `array[3] of Integer` — kompilace projde
bez warningu. Runtime bounds se kontrolují proti deklaraci **v daném scope**
(callee s `array[2]` smí sáhnout jen na indexy 1–2). Důsledek: nesoulad velikostí
mezi signaturami je tichý a odhalí se až runtime chybou, když callee sáhne mimo
svou deklaraci, nebo vůbec. Při refactoru drž velikost pole ve **všech**
signaturách stejnou — kompilátor tě nepodrží. (Zjištěno 2026-07,
prod-epb-pricingMatrix-bc: `ImportCaseOne` měl `array[2]`, zbytek `array[3]`.)

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
jako zdrojová tabulka kvůli `TransferFields`, viz 3.6 v `bc-al-data.md`) a **enum values**
(per-enum namespace).

**Proč:** Range se zbytečně nevyčerpává (20 ID stačí na 20 objektů *každého*
typu, ne 20 celkem) a ID jsou predikovatelná.

**Test app** (sdílí range s hlavní appkou): test codeunity čísluj **od konce
range** (např. 60149, 60148, …) — codeunit ID namespace je sdílený napříč
nainstalovanými appkami, takže hlavní appka roste od začátku, testy od konce
a nepotkají se. **Platí to pro KAŽDÝ typ objektu, ne jen codeunity** — i test
`tableextension`/`pageextension` sdílí namespace s hlavní appkou (AL0264
„already declared by the extension X"). Test double objekty (např. tableext
s testovacím polem) čísluj taky od konce range hlavní appky; pokud test app má
deklarovaný užší idRange, nejdřív ho rozšiř tak, aby konec range pokrýval.
(2026-08, prod-epb-pricingMatrix-bc: test tableext 65505 kolidoval s
SalesCrMemoLine 65505 hlavní appky → přečíslováno na 65519 + rozšířen test range.)

**Pozor (opakovaná chyba z praxe):** při migraci nebo zakládání objektů
nepřenášet globální/offsetové číslování z předlohy — vždy přečíslovat per typ
od začátku range. (2026-06: migrace EF Advance CZ — první návrh čísloval
globálně 60120…60132 napříč typy, správně per typ od 60120.)

### 1.13 `Format(EnumValue)` vrací CAPTION — nestavět z něj strojově parsované texty

`Format()` na enum hodnotě vrací **caption v jazyce session** (přeložitelný přes
XLIFF), ne name hodnoty. Když se z něj skládá text, který pak parsuje stroj
(výrazový parser, klíč do dictionary, API payload), funguje to jen náhodou —
dokud caption == name a překlad ho nemění. Jakmile caption dostane mezeru/závorku
(`'Arctan (Deg)'`) nebo český překlad, parsování se rozbije.

- **Fix pattern:** explicitní mapovací procedura enum → token (case přes všechny
  hodnoty + `else Format(...)` fallback pro extension hodnoty), umístěná u
  konzumenta tokenů (parser). Vzor: `Math Expression Parser COEBS.GetFunctionToken`
  v prod-ess-configurator-bc (2026-08 — přidání Arctan/Arcsin/Arccos s captiony
  `'Arctan (Deg)'`; evaluace i validace formulí dřív stavěly výraz přes
  `Format("Function")`).
- Pro **zobrazovací** texty (preview vzorce, error message) je `Format(enum)`
  naopak správně — uživatel má vidět caption.
- Bonus poznatek: System Application codeunit **`Math`** má i inverzní
  trigonometrii — `Atan`, `Asin`, `Acos`, `Atan2` (radiány) — netřeba DotNet
  ani vlastní aproximace.

### 1.14 `Evaluate(Decimal, Text)` / `Format(Decimal)` bez formátu = locale session — v datové pipeline vždy formát 9

`Evaluate(Dec, Txt)` a `Format(Dec)` **bez** parametru formátu jedou podle regionálního
nastavení session (cs-CZ: `,` desetinná, mezera/nbsp tisíce). Když jedna strana pipeline
zapisuje `Format(x, 0, 9)` (XML, tečka — správně, jazykově nezávislé) a druhá čte holým
`Evaluate`, na českém serveru `Evaluate(Dec, '4.2489')` **selže** (vrátí false, ne 42489) a
kód typicky tiše skončí „podmínka nesplněna". Zákeřné: **celočíselné hodnoty (`5`) projdou
v každém jazyce**, takže bug vypadá jako „porovnání funguje jen někdy". V EN session je to
naopak: `Evaluate(Dec, '4,5')` → **45** (čárka = tisíce), žádná chyba, jen špatné číslo.

- **Pravidlo:** text ↔ číslo v datové pipeline (dictionary hodnot, filtry podmínek, API,
  uložené texty) **vždy s formátem 9 na obou stranách**. Uživatelský vstup normalizuj:
  `DelChr(Txt, '=', ' ' + Format(Nbsp))` (`Nbsp: Char := 160`) → `.Replace(',', '.')` →
  `Evaluate(..., 9)`. Vzor: `Cond. Comparison Mgt. COEBS.TryParseDecimal/TryParseInteger`
  (prod-ess-configurator-bc, WI 65684, 2026-08-26). `Format` bez formátu jen pro zobrazení.
- **Testy maskují locale bugy**, když expected/actual stavíš přes `Format(x)` — obojí se
  formátuje v locale test runneru a test projde všude, i když produkce plní data přes
  `Format(x, 0, 9)`. V testech drž **tvar produkčních dat** (`Format(x, 0, 9)`) a přidej
  případ, který padá v obou locale (filtr `'4,5'` vs hodnota `'4.7'` → `>=` musí být true:
  EN by četlo 45, CZ by nezparsovalo tečku).
- Region session **nejde v testu přepnout** (`GlobalLanguage` mění jen jazyk captionů, ne
  number format) — proto testuj přes normalizační helper, ne přes „nastav CZ".
- **Excel Buffer (`ReadSheet`) ukládá číselné buňky do `"Cell Value as Text"` přes `Format(Round(x), 0, 1)`**
  = desetinný oddělovač podle **locale session, bez oddělovačů tisíců** (ověřeno ve zdroji BC 28.3
  `ExcelBuffer.ParseCellValue`). Holý `Evaluate(Dec, "Cell Value as Text")` k tomu tedy sedí v každém
  jazyce — normalizace na tečku + format 9 by tu naopak rozbila CZ (`62,5` → `62.5` OK, ale `Evaluate(...,9)`
  na `1200` fajn, na CZ text s čárkou ne). Robustní vzor pro import: nejdřív locale `Evaluate`, až při
  neúspěchu (textová buňka zadaná ručně s druhým oddělovačem) `DelChr` mezer/NBSP + `,`→`.` + `Evaluate(…, 9)`.
  (2026-09-01, prod-epb-pricingMatrix-bc, code review importu matice.)

### 1.15 AL **umí** přetěžování procedur (overloading) — rozlišuje podle typů parametrů, ne podle názvů

Dlouho platilo „AL overloading nemá" a training memory to drží dodnes — **na AL 18 /
runtime 17 to už neplatí**. Dvě procedury stejného jména v jednom objektu se zkompilují,
pokud se liší **typy** parametrů (a tím i jejich počtem):

```al
// Projde — obálka, která zahodí výstupní parametry, jež volající nepotřebuje
local procedure CreateConfiguredVariant(ItemNo: Code[20]; var ItemVariant: Record "Item Variant")
var
    ConfigNo: Code[20];
    ParamLineNo: Integer;
begin
    CreateConfiguredVariant(ItemNo, ItemVariant, ConfigNo, ParamLineNo);
end;

local procedure CreateConfiguredVariant(ItemNo: Code[20]; var ItemVariant: Record "Item Variant"; var ConfigNo: Code[20]; var ParamLineNo: Integer)
begin
    …
end;
```

- Rozlišuje se **typ** parametru, ne jeho jméno: `Helper(A: Integer)` + `Helper(A: Text)`
  projde, `Helper(Alpha: Integer)` + `Helper(Beta: Integer)` skončí
  `error AL0440: The Codeunit 'X' already defines a method called 'Y' with the same parameter types`.
  Platí pro `local`, `internal` i `public` procedury.
- **Kdy to použít:** tenká obálka nad plnou variantou (jako výše — AL nemá volitelné
  parametry, takže overload je jediná cesta, jak nenutit každého volajícího deklarovat
  `var` proměnné, které ho nezajímají). Ne pro dvě různé logiky pod jedním jménem —
  čtenář pak u volání netuší, která větev jede.
- **Ověř kompilací, než na to vsadíš ve starším repu.** Ověřeno na `alc` 18.0.41.45789
  (AL extension 18.0.2732683, runtime 17.0, BC 28.3); od kterého runtime přesně to
  funguje, ozkoušené není. Sonda je triviální — dvě procedury + jedno volání, `alc`
  přes 7.1 v `bc-al-tools.md`.

(2026-09-18, prod-ess-configurator-bc, review testů větve `QuoteTrackingVariantAlign` —
`System Param Tests COEBS.CreateConfiguredVariant` vypadal jako duplicita, která nemůže
projít; kompilace test appky přitom byla čistá.)

---


## 10. Moderní AL patterny — výběr podle `app.json`

BC se hýbe rychle. Namespaces, interfaces, isolated storage, Cloud-first
patterny jsou tady, ale training data + starší code stále tlačí na deprecated
přístupy. **Pravidlo palce: vyber nejnovější pattern, který runtime projektu
podporuje — ne nejnovější pattern, který si pamatuješ.**

### 10.1 Workflow před výběrem patternu

1. **Otevři `app.json`** a podívej se na `application`, `platform`, `target`.
2. **Pak vybírej:** modernější pattern preferuj, ale jen pokud ho runtime
   uveze.
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

