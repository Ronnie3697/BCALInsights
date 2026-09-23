# BC/AL poznámky — UI patterny stránek

> Vyčleněno z `bc-al-style.md` 2026-09-08 (sekce 4; původně část `bc-al-notes.md`, archiv
> `bc-al-notes.archived-2026-06-23.md`). Konvence kódu (1.x) a moderní patterny (10.x) zůstávají v `bc-al-style.md`.
> Načítej, když řešíš: chování page / pageextension — RunModal a výběr záznamu na RoleCenter, OnDrillDown vs OnLookup,
> ConfirmManagement default, factbox SubPageLink, CaptionClass cache, názvy controlů / expression pole, modify cizí
> pageextension, smyčka aktualizace v OnAfterGet*Record, Visible/Enabled přes page proměnnou, MultiLine / RichContent /
> control add-in.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **4.** UI patterny (4.1–4.10)

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

### 4.5 Factbox ListPart se `SourceTableTemporary` — `Rec.Reset()` maže SubPageLink filtry

Když si factbox (ListPart, `SourceTableTemporary`) plní buffer procedurou volanou
z host page a uvnitř dělá `Rec.Reset()` + `Rec.DeleteAll()` + refill, pozor:
**`Reset()` smaže i filtry aplikované platformou ze `SubPageLink`** (žijí ve
**filter group 4**). Platforma je znovu aplikuje až při změně recordu provideru
(`Provider = SalesLines/ProdOrderLines`), ne po tvém `CurrPage.Update`.

**Symptom z praxe (Zlomek 64189):** factbox po otevření stránky prázdný (jiný bug),
ale po akci Refresh „záhadně" ukázal data — ve skutečnosti **celý nefiltrovaný
buffer** (tracking všech řádků dokladu), protože Reset odnesl link filtr.

**Fix — ulož a vrať filter group 4 kolem reloadu:**

```al
Rec.FilterGroup(4);
SubPageLinkView := Rec.GetView(false);
Rec.FilterGroup(0);

Rec.Reset();
Rec.DeleteAll(false);
// ...refill bufferu...

Rec.FilterGroup(4);
Rec.SetView(SubPageLinkView);
Rec.FilterGroup(0);
CurrPage.Update(false);
```

Ukládej/obnovuj **přesně to, co tam bylo** (i prázdný view je validní stav — na
page open ještě link nemusí být aplikovaný), nevymýšlej filtry ručně.

### 4.6 Dynamické captiony přes `CaptionClass` — cache v session

Pro pole, jejichž caption se řídí setupem (osy pricing matice, dimenze…), se
používá `CaptionClass = '<Area>,<Expr>'` + subscriber na
`Codeunit::"Caption Class"` `OnResolveCaptionClass` (vzor: `Features PMEBS`,
`CaptionClass = 'PMEBS,A'` — priorita: uživatelský název ze setupu → fallback
na `Field."Field Caption"` vybraného pole). Statický `Caption` nech jako
fallback pro případ, že resolver nic nevrátí.

**⚠️ Gotcha: resolvnuté captiony se cachují s metadaty stránek per session.**
Po změně setupu, ze kterého resolver čte (přejmenování osy/parametru), web
klient dál ukazuje staré captiony — nepomůže zavřít/otevřít stránku. Fix:
**Ctrl+F5** (hard refresh) nebo odhlásit/přihlásit. Při ladění „proč se caption
nezměnil" nejdřív vyluč cache a per-company setup, až pak hledej bug v kódu.
(Ověřeno 2026-08, Zlomek 62464 / PMEBS parametry A/B.)

### 4.6b Přeměna pole na „expression" control — název controlu NEMĚŇ

Když statické `field(Description; Rec.Description)` předěláváš na expression pole
(statická hodnota vs. náhled formule, `field(...; DescriptionExpressionText)`), nech
**název controlu původní** a změň jen `SourceExpr`. Jméno controlu je veřejné API
stránky: závislé appky na ně kotví `addafter(Description)` / `modify(...)` (→ AL0270
při kompilaci závislé appky, kterou v CI base appky nevidíš), personalizace i XLIFF
trans-unit ID (hash z názvu controlu) na něm visí. Nové controly pojmenuj podle pole
tabulky, ne `XyzExpression`. Po změně zkompiluj závislé appky proti novému buildu
(alc `/packagecachepath` s kopií jejich `.alpackages` bez starého symbolu base appky,
aby vyhrál nový build). (Ověřeno 2026-09, Configurator textové formule vs. Alumistr
`addafter(Description)` na BOM/Routing/SL Action Lines.)

### 4.6c `modify(Control) { StyleExpr = … }` jde přepsat — ale výraz si musíš spočítat CELÝ znovu

`StyleExpr` base controlu se z pageextension přebít dá (ověřeno alc 18 na `Variant Config Params COEBS`),
jenže base proměnnou, kterou tam base page plní, **z rozšíření nepřečteš** — `CurrPage.<Control>.StyleExpr`
neexistuje. Jakmile `StyleExpr` přepíšeš, zodpovídáš za **všechny** větve, i ty, které tě nezajímají,
takže původní pravidla base musíš zrcadlit (a s nimi i případné `local` helpery, které je počítají).
Než do toho půjdeš, zvaž, jestli kosmetika stojí za duplikaci, která se rozejde při každé změně base.
Totéž platí pro `Editable`, `Visible` a další výrazové properties.

Druhá půlka téhož problému: **co se v poli zobrazí, přebít nejde vůbec**, když hodnotu plní base
proměnná (`field(Value; ValueText)`). `modify` mění jen properties, ne `SourceExpr`. Jediné cesty jsou
schovat base control a postavit vedle vlastní (pak ale duplikuješ i jeho `OnValidate`/`OnAssistEdit`
logiku), nebo doplnit chybějící API do base appky.
(2026-09-17, cust-zlomek-bc 65364 — parametr konfigurátoru, jehož hodnota se přebírá odjinud, se měl
zobrazit prázdně; nakonec jen ztlumený styl.)

---

### 4.7 `modify()` na kontrolu z CIZÍ pageextension — jde to, s dependency

Když jiná appka přidá na stejnou base page svoje pole a ty ho potřebuješ schovat
(duplicitní caption, mrtvá featura), **`modify("<Control Name>") { Visible = false; }`
ve vlastním pageextension funguje** — podmínka je **přímá dependency** na tu appku
v `app.json`. Bez ní kompilátor kontrolu nevidí a hodí
`AL0270: The control '"X"' is not found in the target '<Page>'`.

- Kompilátor jména kontrol **ověřuje** (ověřeno záměrným překlepem → AL0270), takže
  úspěšná kompilace = kontrola opravdu existuje a modify na ni sedí.
- Funguje i na pole s **`Access = Internal`** — `modify` pracuje se **jménem kontroly**,
  ne se source expression, takže internal access to neblokuje (číst/zapisovat to pole
  z vlastního kódu pořád nemůžeš).
- Cena: přidání přímé dependency má dopad na CI (NuGet download + dedupe minim per GUID,
  viz 7.11 v `bc-al-build.md`). Když je appka už nainstalovaná tranzitivně, runtime se nemění.
- Jméno kontroly zjistíš z al-mcp (`al_search_objects` s `packageName` té appky →
  `ControlChanges` → `Name`) nebo ze zdrojáku.

(2026-08-25, cust-sonnentor-bc PBI 64046: Essence Distribution Base přidávala na
`Blanket Purchase Order` pole `Starting/Ending Date AAEBS` se stejným captionem jako
naše SON pole → schováno přes modify.)

---

### 4.8 „Smyčka aktualizace mezi aktivačními událostmi stránky" — zápis/Update uvnitř OnAfterGet*Record

Platformní chyba *„V rozšíření 'X' byla zjištěna smyčka průběžné aktualizace mezi
aktivačními událostmi stránky"* (EN cca „update loop detected between page
activation events in extension 'X'") = NST guard proti nekonečnému ping-pongu
klient↔server, když **aktivační trigger** stránky (`OnAfterGetCurrRecord`,
`OnAfterGetRecord`) sám vyvolá další aktivaci. Dva spouštěče:

- **Zápis do vlastní source table uvnitř `OnAfterGetCurrRecord`** (Modify/ModifyAll
  + klidně `Commit()`) — platforma po triggeru vidí změněnou row version, re-fetchne,
  trigger zapíše znovu… Přesně tohle MS řešil platformním hotfixem **411517 (BC 18.6,
  10/2021): „An endless loop between client and server when modifying records by the
  OnAfterGetCurrRecord trigger"** — od té doby to místo zamrznutí hodí tuhle chybu.
  Zákeřné: **ne-idempotentní** přepočet (`ModifyAll(pole, 0)` a pak `Modify` zpět na
  stejnou hodnotu) mění row version i když se data nezměnila → smyčka záleží na datech
  a fokusu (`RefreshOnActivate = true`, `UpdatePropagation = Both`), takže chyba
  vypadá „náhodně".
- **`CurrPage.Update()` v `OnAfterGetRecord` / `OnAfterGetCurrRecord`** — dokumentovaný
  anti-pattern; Update znovu spustí aktivační triggery.

Hláška jmenuje extension, **jejíž objekt zrovna běžel** — u zákaznické appky, která
kopíruje vzor z produktové, to klidně bude zákaznická (a stejně tak časem i produktová).

**Pravidla:** v aktivačních triggerech jen čtení + nastavení page proměnných; přepočty
stromů / sort orderů do explicitních akcí (New/Edit/Delete/Refresh) nebo `OnOpenPage`,
a **idempotentně** (porovnej před `Modify`, žádný `ModifyAll` na 0, žádný `Commit`).
**Fix pattern (2026-08-25, prod-ess-configurator-bc `Condition Tree Mgt. COEBS`):** přepočet stromu
do codeunitu, který načte vazby do Dictionary, spočítá pořadí v paměti (`ComputeTreeOrder`, guard proti
cyklům/dangling odkazům) a pak `Modify(false)` jen na řádcích, kde se hodnota liší; vrací počet zápisů
(→ test idempotence: 2. běh = 0). Stránky ho volají z `OnOpenPage` + akcí (New/Edit/Show/Delete/Copy/Refresh).
Ověření konkrétního výskytu: App Insights `traces | where customDimensions.eventId ==
"RT0030"` (error dialog) → `alObjectName` / `alStackTrace` ukáže trigger, kde to prasklo.
(2026-08-25, cust-alumistr-bc / prod-ess-configurator-bc: `LoadHierarchicalData` v
`OnAfterGetCurrRecord` tree-list partů podmínek + `CurrPage.Update(false)` v
`OnAfterGetRecord` Cond Card/Dlg stránek — stejný vzor v base i v Alumistr CNC kopii.)

---

### 4.9 `Visible = not Rec."Pole"` v pageextension — kompiluje, ale za běhu „The identifier … could not be found"

`Visible`/`Enabled` výraz na page controlu **nesmí odkazovat na `Rec.<pole>`** (ani s `not`): alc to
přeloží bez varování, ale web klient při otevření stránky hodí *„The identifier 'Use UoM Parameter
Fields PMEBS' could not be found"* — runtime vyhodnocuje výrazy jen proti **proměnným stránky a jménům
controlů**, ne proti recordu. Správný vzor: page (`protected`) `Boolean` proměnná, nastavit ji **už v
`OnOpenPage`** (u setup karet base page Rec načte před tím, než pageextension trigger běží; samotný
`OnAfterGetRecord` se stihne až po prvním renderu → pole zůstanou skrytá — reprodukováno) a znovu v
`OnAfterGetRecord` + v `OnValidate` řídícího pole s `CurrPage.Update()`, ať se závislá pole schovají hned
po kliknutí a nečeká se na změnu záznamu. Jednoduché `Visible = Rec.Bool`
bez `not` u base-app stránek občas funguje, ale nespoléhat — proměnná je vždy bezpečná.
(2026-09-01, prod-epb-pricingMatrix-bc — setup page Sales & Receivables Setup, chyba reprodukovaná na sandboxu.)

**Sales Order / Sales Quote (BC 28) nemají control `"Bill-to Customer No."`** — plátce se mění přes `BillToOptions`
+ lookup na `field("Bill-to Name")`, který v `OnAfterLookup` volá `Rec.Validate("Bill-to Customer No.", …)` a pak
`CurrPage.Update()`. Důsledky: (a) `modify("Bill-to Customer No.")` v pageextension **nezkompiluje** (control neexistuje) —
code-review návrh „přidej OnAfterValidate na Bill-to Customer No." na kartách dokladů zahoď; (b) `CurrPage.Update()` po
lookupu spustí `OnAfterGetCurrRecord`, takže page proměnná pro `Visible` akce plněná v `OnOpenPage` +
`OnAfterGetRecord` + `OnAfterGetCurrRecord` se po změně plátce přepočítá sama, bez vlastního triggeru.
(2026-09-15, cust-alumistr-bc 65916 — akce Send to SK Branch.)

---

### 4.10 `MultiLine` pole má ve web klientu pevné ~3 řádky — výšku nezvětšíš; „vidět celé" = RichContent nebo control add-in

`MultiLine = true` vykreslí web klient jako textareu s pevnou výškou cca 3 řádky + scrollbar.
**Žádná AL property výšku neovlivní** (existuje jen `Width`), délka pole (`Text[250]` vs
`Text[2048]` vs Blob) taky ne, `RowSpan` / grid / samostatná group to nemění (MS docs + komunita,
ověřeno 2026-09-02). Base app `Work Description` na Sales Order je přesně tenhle vzor: Blob +
Text proměnná + `MultiLine = true` + `ShowCaption = false` sama v root group `"Work Description"`
→ **stejný třířádkový box**, Blob řeší jen délku.

Když má uživatel vidět dlouhý text celý:

- **Rich text editor** (BC23+ / runtime 12+): page field na **Text proměnnou** s
  `ExtendedDatatype = RichContent` + `MultiLine = true`, control musí být **sám v root-level
  group (FastTab)** — v pageextension tedy `addafter(General) { group(...) { field(...) } }`.
  Hodnota je **HTML** → ukládat do **Blob** (Text[n] přeteče, obrázky jsou base64 inline;
  `RichContent` na table field = compile error). Editor roste s obsahem do stropu (MS ho
  nekvantifikuje), prázdný nejde zmenšit na jeden řádek, toolbar (obrázky, tabulky) nejde
  omezit. Get/Set podle `Sales Header.GetWorkDescription/SetWorkDescription`: `CalcFields` +
  `CreateInStream(InStream, TextEncoding::UTF8)` + `Type Helper.TryReadAsTextWithSepAndFieldErrMsg(InStream, TypeHelper.LFSeparator(), FieldCaption(...))`
  / `Clear(Blob)` + `CreateOutStream(..., UTF8)` + `WriteText` + `Modify(false)`; proměnnou
  plnit v `OnAfterGetCurrRecord`, ukládat v `OnValidate` pole. Na tisk je nutná konverze
  HTML → text. Propagace Blobu do posted/archiv dokladů viz 3.6c v `bc-al-data.md`.
- **Vlastní control add-in** (textarea s vlastní výškou, plain text) — když má zůstat čistý
  text a nemá se sahat na posting/reporty; výška add-inu je přes `RequestedHeight` pevná,
  iframe se obsahu nepřizpůsobí. Ověřený vzor (prototyp `Comment Editor ZLK` v cust-zlomek-bc
  2026-09-02, kompiloval čistě; **v repu nezůstal** — uživatel ho odmítl jako „moc velké
  obcházení standardu", takže u zákaznických rep počítej s tím, že add-in na kartě dokladu
  neprojde): `src/controladdin/CommentEditor.ControlAddIn.{al,js,css}`, cesty v
  `Scripts`/`StyleSheets` relativní k app rootu, `RequestedHeight = 200`, `procedure LoadText(Text; MaxLength; IsEditable)`
  → `window.LoadText`, eventy `ControlAddInReady()` (volá se na konci Scripts, `StartupScript`
  netřeba) a `TextChanged(Text)` (debounce 700 ms při psaní + okamžitě na `blur`/`change`, posílá
  jen když se hodnota liší od naposledy poslané); page: `Ready` flag + `LoadText` v
  `OnAfterGetCurrRecord`, v `TextChanged` `Validate` + `Modify(true)` jen když `"No." <> ''`
  (nový neuložený doklad vloží page sama i s hodnotou). JS jen v externím souboru (CSP), hodnotu
  v `LoadText` přepisuj jen když se liší (jinak skáče kurzor). `CurrPage.Editable` chce závorky
  (`LC0077`).
- `Microsoft.Dynamics.Nav.Client.WebPageViewer` s vlastním HTML `<textarea style="height:100%">`
  = totéž, ale HTML string v AL a ukládání přes `Callback` — hack, radši vlastní add-in.

(2026-09-02, cust-zlomek-bc — prototyp RichContent na `Comment 2 ZLK`, Sales Order.)

---

### 4.11 Výšku factboxu (partu) z AL nastavit NEJDE — a factbox ve factbox panelu se nedá sbalit

Klasický požadavek „ten ListPart ve factboxu scrolluje, zvětši ho". **Nejde to a není to
o hledání správné property.** MS docs [Page parts overview → Design considerations → Part
size](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-designing-parts):
*„The size of a part is automatically determined by the user interface and will vary depending on
where the part has been embedded on the page, other content surrounding the part, and the overall
available space of the display target. **Developers can't specify the preferred, minimum, or maximum
height or width of a part.**"*

Ověřeno alc 18 (všechno `error AL0124: The property … cannot be used in this context`):

| Kde | Zkoušené properties |
|---|---|
| `page … { PageType = ListPart; }` | `Height`, `MinHeight`, `RequestedHeight`, `RowsPerPage` |
| `part(X; "…")` v `addfirst(factboxes)` | `Height`, `RequestedHeight`, `RowsPerPage`, `RowSpan`, `ColumnSpan` |

(`RowSpan` / `ColumnSpan` existují jen na `field` / `group` v `grid`, ne na partu; `RequestedHeight`
je property **control add-inu**, ne page/partu — proto ten jediný pevnou výšku umí, viz 4.10.)

Další fakta z téhož docs, která se u toho hodí:

- **Part ve `FactBoxes` / `RoleCenter` area nejde sbalit** („parts can't be collapsed"); sbalit jde
  jen part v `Content` area na task dialog / card / document page a mimo FastTab. Takže „ať si
  uživatel ostatní factboxy sbalí" **není řešení** — jde jen **skrýt** je personalizací, a to
  uvolněnou výšku zbylým factboxům opravdu dá.
- Document page při prvním otevření automaticky rozbalí **první dvě** části/FastTaby, zbytek sbalí;
  vývojář počáteční stav neurčí.
- `addfirst(factboxes)` posune factbox nahoru (užitečné, uživatel na něj nemusí scrollovat), ale
  na výšku nemá vliv.

**Co reálně pomůže, když má uživatel vidět víc řádků:**

1. **Personalizace — skrýt ostatní factboxy** na té stránce (per uživatel, nulový kód).
2. **Přesunout part do `area(Content)` jako vlastní FastTab** (`addlast(Content)`): roztáhne se přes
   celou šířku, dostane víc vertikálního prostoru a jde sbalit. **`Provider = SalesLines` +
   `SubPageLink = field(...)` funguje i mimo factbox area** (ověřeno kompilací na `Sales Order`),
   takže vazba na aktivní řádek zůstane. Cena: není to vedle řádků, ale pod nimi.
3. Akce / `OnDrillDown` otevírající plnou list page s týmž filtrem.
4. Control add-in s `RequestedHeight` — jediná cesta k pevné výšce, u zákaznických rep počítej
   s odmítnutím (4.10).
5. Zvětšit okno / zmenšit zoom prohlížeče — banální, ale funguje.

`MultiLine = true` na poli ve factboxu výšku **řádku** zvětší (a tím zmenší počet viditelných
řádků) — opak toho, co uživatel chce.

(2026-09-15, cust-zlomek-bc 65148 — factbox „Detail konfigurace varianty" nad `Variant
Configuration COEBS` na Sales Order / Sales Quote.)

---

### 4.12 Page procedura se stejným jménem jako metoda `Rec` — volání se naváže na tabulku (AL0604 + AA0228)

V pageextension (i page) volání **bez kvalifikace** `EditParameterFormula(FieldType)`, když stejné jméno a signaturu
má `local procedure` stránky **i** procedura tabulky / tableextension zdrojové tabulky, přeloží alc 18 jako
**`Rec.EditParameterFormula(...)`** přes implicitní `with` — ne jako lokální proceduru stránky. Kompilace projde a
prozradí to jen dvojice warningů: `AL0604 Use of implicit 'with' will be removed … Qualify with 'Rec'` na řádku
volání a `AA0228 The local method 'X' is declared but never used` na proceduře stránky. Za běhu se tak přeskočí
všechno, co obálka stránky dělá navíc (`CurrPage.SaveRecord()`, `Commit()` před modálním dialogem, obnovení náhledů,
`CurrPage.Update`). Typicky vznikne při refaktoru „logiku přesuň na tabulku, stránce nech tenkou obálku“.

- **Fix:** obálku stránky pojmenuj jinak než metodu tabulky (`RunParameterFormulaEditor` → volá
  `Rec.EditParameterFormula`).
- **Kontrola:** po refaktoru grepni log alc na `AL0604` / `AA0228`. `AL0604` je warning **kompilátoru** (hlásí se i bez
  analyzerů) → s Essence `failOn warning` shodí CI; `AA0228` je CodeCop, který CI nespouští (7.21 v `bc-al-build.md`),
  ten uvidíš jen lokálně.

(2026-09-22, cust-alumistr-bc `SL Action Cond. Card/Dlg COALU` — obálka editoru vzorců Parametr A/B po code review.)

---

### 4.13 List page v `LookupMode(true)` se otevře **jen pro čtení** — zaškrtávací sloupec v něm nikdo nezaškrtne

Výběrový dialog postavený jako `PageType = List` nad temp bufferem s editovatelným `Boolean` sloupcem
(„Převzít", „Vybrat") a spuštěný přes `LookupMode(true)` + `RunModal() = Action::LookupOK` **v UI nefunguje**:
web klient otevře lookup v **režimu prohlížení** — boolean se kreslí jako text „Ne"/„Ano" (odkaz, ne checkbox)
a v liště přibude BC akce **„Upravit seznam"** (Edit List), teprve ta přepne do editace. Uživatel intuitivně
**vybere řádky** (checkbox výběru řádku vlevo / Ctrl+A) a dá OK → kód přečte `Taken = false` u všech a uloží
**prázdný výběr**. Žádná chyba, žádná hláška. Kompilace ani analyzery to nechytí; `Page.Editable` / `DeleteAllowed`
/ `InsertAllowed` na tom nic nemění.

Možnosti (vyber podle UX, neověřeno všechno):

- **Výběr řádků místo checkboxu:** po `LookupOK` vzít `CurrPage.SetSelectionFilter(TempBuffer)` (procedura
  stránky volaná po `RunModal`) — odpovídá tomu, co uživatel dělá; aktuální stav ukaž read-only sloupcem.
  Pozor: OK bez výběru vrátí aktuální řádek, „nic nevybrat" přes OK nejde → samostatná akce „Zrušit".
- **`PageType = StandardDialog` s editovatelným `ListPart` subpage** nad bufferem — OK/Storno má dialog
  nativně a part se otevře editovatelný.
- Ne `Worksheet`/`List` bez LookupMode — modálně nemají Storno a křížek vrací `Action::OK` (C4 v
  `ess-configurator-notes.md`).

**Na zelený test přes `TestPage` + `ModalPageHandler` se nespoléhej** (jestli TestPage v lookup módu do
pole zapíše, nebo spadne na needitovatelném poli, neověřeno) — výběrový dialog vždycky proklikej v prohlížeči.
(2026-09-23, cust-zlomek-bc 65364 BC-DEV2 — `Take Params Dialog COZLK`: uživatel „vybral všechny, OK",
tabulka `SL Act. Taken Param COZLK` zůstala prázdná.)

---
