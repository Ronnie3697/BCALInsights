# BC/AL poznámky — UI patterny stránek

> Vyčleněno z `bc-al-style.md` 2026-09-08 (sekce 4; původně část `bc-al-notes.md`, archiv
> `bc-al-notes.archived-2026-06-23.md`). Konvence kódu (1.x) a moderní patterny (10.x) zůstávají v `bc-al-style.md`.
> Načítej, když řešíš: chování page / pageextension — RunModal a výběr záznamu na RoleCenter, OnDrillDown vs OnLookup,
> ConfirmManagement default, factbox SubPageLink, CaptionClass cache, názvy controlů / expression pole, modify cizí
> pageextension, smyčka aktualizace v OnAfterGet*Record, Visible/Enabled přes page proměnnou, MultiLine / RichContent /
> control add-in, filtr partu nastavený z hostitelova OnOpenPage.
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".

Obsahuje:
- **4.** UI patterny (4.1–4.28)

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
  HTML → text. Propagace Blobu do posted/archiv dokladů viz 3.6c v `bc-al-posting.md`.
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

**Víc `RichContent` polí v jedné FastTab = žádný rich text, ověřeno na sandboxu.** Čtyři pole s `ExtendedDatatype =
RichContent` + `MultiLine` v jedné root group se zkompilují bez varování a web klient je bez chyby vykreslí jako
**obyčejné třířádkové textarey** (DOM: 4× `textarea`, 0× `contenteditable`, žádný toolbar), dvě do sloupce. MS docs to
říkají přímo („must be the only control in that group"). **Nepomůže ani jedna FastTab s podskupinami** (`group(Comments)
{ group(Comment1) { field(…) } group(Comment2) { … } }`, každé pole v podskupině samo): opět 4× `textarea`, captiony
podskupin se kreslí jako popisky polí ve dvou sloupcích — editor musí být přímo v **root-level** group. Funkční je **jedna FastTab na jedno pole** (`addafter(General)
{ group(Comment1ZLK) {…} group(Comment2ZLK) {…} … }`, pole s `ShowCaption = false`, caption nese group).
**`Importance = Additional` na rich text poli funguje:** FastTab dostane třídu `contains-only-additional-fields`, ukáže
jen nadpis + „Zobrazit více" a editor s toolbarem se objeví až po kliknutí (base `Work Description` to má stejně).
Document page při otevření rozbalí první dvě FastTaby, takže záložka hned za `General` je rozbalená (ale díky Additional
prázdná) a další jsou sbalené. Hodnotu čte/zapisuje jeden generický helper přes `Temp Blob.FromRecord(RecVariant,
FieldNo)` (sám udělá `CalcField`, když Blob není načtený, ověřeno ve zdroji System App w1-28 `TempBlobImpl`)
a `Temp Blob.ToRecordRef` + `RecRef.SetTable` + `Modify(false)`. Posted/archive tabulky se stejným field ID tak čte
týž kód. (2026-09-29, cust-zlomek-bc PBI 65651, BC-DEV2.)

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

### 4.14 Filtr na `Rec` partu nastavený z hostitelova `OnOpenPage` otevření partu nepřežije

Dialog (StandardDialog / Card) v **svém `OnOpenPage`** naplní part přes veřejnou proceduru
(`CurrPage.<Part>.Page.LoadParameters(…)`), která temp `Rec` partu naplní a nastaví mu klíč a filtr
(`Rec.SetRange("Effective Hidden", false)`). **Data zůstanou, filtr ne** — part se otevírá až po hostitelově
`OnOpenPage` (pořadí host `OnOpenPage` → part `OnOpenPage` → host `OnAfterGetCurrRecord`; StefanMaron AL.Runner
issue #2689 popisuje reálné BC) a pohled, který mu procedura nastavila, při otevření nedrží. Repeater pak ukáže
i řádky, které měl filtr schovat — až do první akce, která filtr nastaví znovu (po změně hodnoty).

- **Fix:** filtr (a klíč) nastav **i v `OnOpenPage` partu** — sdílenou lokální procedurou, kterou volá i načítací
  procedura (pro případ, že se part otevře dřív, nebo se načítá znovu po otevření, např. po změně konfigurace v hlavičce).
- Řádky, které tím vynecháš, v temp tabulce zůstávají (filtr není `Delete`), takže `GetAllRecords` přes kopii s `Reset`
  je pořád vidí.
- Lokálně / ručně to snadno přehlédneš: u nového záznamu bývá všechno viditelné a první změna filtr nastaví. Projeví se
  u **znovu otevřeného** záznamu (varianta s parametrem skrytým podmínkou) a u řádků skrytých hned od začátku
  (statický příznak).

Zachyceno 2026-10-05, prod-ess-configurator-bc master build 28617: test `ReusingAVariantInTheDialogRepairsItsSavedHiddenState`
čekal `Color;Handle;`, dialog po otevření znovu použité varianty vypsal `Color;Width;Handle;` (WIDTH skrytý podmínkou).
**Ověřeno 2026-10-05 v lokálním testovacím kontejneru** (7.23 v `bc-al-build.md`): master eeba4b9 spadl stejně jako CI, s filtrem
i v `OnOpenPage` partu `Variant Config Params COEBS` (jediná změna v appce) test prošel — větev `VarConfigDialogTestsFix`. Stejný návrh měl ListPart i před sjednocením s enginem, chyba je tedy starší.

---

### 4.15 Cue CardPart na RoleCenteru se `SourceTableTemporary = true` — kostky zamrznou na hodnotách z otevření

Vlastní cue tabulka (FlowFieldy `count(...)`) + CardPart se `SourceTableTemporary = true`, `Rec.Insert` + `Rec.CalcFields(...)`
v `OnOpenPage` a background task (`CurrPage.EnqueueBackgroundTask`) taky jen v `OnOpenPage`: **kostky ukazují čísla z okamžiku,
kdy se Role Center otevřel**, a dál se nemění — drill-down (FlowField i vlastní `OnDrillDown` se `SetTableView`) přitom otevře
list s aktuálními řádky, takže „kostka má špatné číslo, po rozkliku jsou řádky správně". Platforma při návratu na Role Center
re-fetchne záznam partu, ale u temp tabulky nemá odkud FlowFieldy přepočítat (jsou jen v paměti instance z explicitního
`CalcFields`) a `OnOpenPage` znovu neběží; microsoft/AL issue #6007 („Tile in a Cue Group is not Updated, if SourceTable is
Temporary", workaround = `SourceTableTemporary = false`). Běžné `field` controly nad proměnnou se přitom aktualizují, jen cue
tiles ne.

**Vzor MS (`SO Processor Activities` 9060, `Team Member Activities` 9042):** cue tabulka **reálná** (jeden záznam s prázdným PK,
`if not Rec.Get() then begin Rec.Init(); Rec.Insert(); end` v `OnOpenPage`), `RefreshOnActivate = true`, FlowFieldy nechat
spočítat platformě (žádné ruční `CalcFields`), styly z hodnot v `OnAfterGetRecord`. Drahé KPI přes background task
**enqueue v `OnAfterGetCurrRecord`** (běží při každém návratu na Role Center), s guardem proti souběhu:

```al
trigger OnAfterGetCurrRecord()
begin
    if CalcTaskId <> 0 then
        if CurrPage.CancelBackgroundTask(CalcTaskId) then;
    CurrPage.EnqueueBackgroundTask(CalcTaskId, Codeunit::"… Calc", TaskParameters, 120000, PageBackgroundTaskErrorLevel::Warning);
end;
```

a v `OnPageBackgroundTaskCompleted` `CalcTaskId := 0` + `CurrPage.Update()`. Reálná cue tabulka = `tabledata` v permission setech
(RIM) a jeden řádek per company; `DataClassification = SystemMetadata` stačí.
(2026-10-06, cust-soitron-bc `Project Manager Cue SOI` — kostky Unprocessed buffers / Unapproved projects držely staré počty.)

---

### 4.16 Nový řádek na subformu s `DelayedInsert` má ve validacích prázdné `SystemId` — cache „per řádek" ho mine

Dokladové subformy (`Purchase Order Subform`, `Sales Order Subform`, `Req. Worksheet`…) mají `AutoSplitKey` + `DelayedInsert = true`:
řádek se vloží až při opuštění řádku, takže **všechny validace při jeho pořízení (`No.`, `Quantity`, `Variant Code`) běží nad
záznamem s `IsNullGuid(SystemId) = true`** (a `Line No. = 0` u stránek, kde ho dopočítá až `AutoSplitKey`). Odpovědi / stav
uložené pod klíčem `SystemId` (SingleInstance cache „uživatel už souhlasil") se pro takový řádek **neuloží vůbec** — první pozdější
změna uloženého řádku se zeptá znovu.

- Testy přes `LibraryXxx.CreateXxxLine` + `Rec.Validate` pracují s **už vloženým** řádkem (`SystemId` existuje) → cache funguje
  a test projde, i když na stránce se otázka zopakuje. Scénář „bez dalšího dotazu" proto testuj i z cesty, kde se odpověď
  neuložila (řádek pořízený přes UI, řádek vzniklý z jiného flow — Carry Out, Make Order z hromadné objednávky, ruční standardní
  vazba), nebo souhlas odvoď z dat (řádek už *je* navázaný na X → X je odsouhlasená) místo z cache.
- Když na `SystemId` klíčuješ, rozhodni explicitně, co platí pro `''` (neukládat / in-memory slovník instance codeunitu).

(2026-10-09, cust-sonnentor-bc code review větve BlanketOrders_66586 — převázání na řádek téže HNO po změně varianty „bez dotazu"
platilo jen v testech; odvozeno z kódu a `DelayedInsert` v base subformech w1-28, v klientu neověřeno.)

---

### 4.17 `CurrPage.Update(false)` v `OnValidate` pole stránky **zahodí právě zadanou hodnotu**

`CurrPage.Update(false)` = obnov stránku **bez uložení**: řádek se znovu načte z databáze a hodnota, kterou uživatel
právě zadal (a která prošla tabulkovým `OnValidate`), zmizí. Na kartě to vypadá jako „pole se nechce uložit"; zachytí to
TestPage (`SetValue(40000)` a hned `Value()` vrátí `0`, bez chyby a bez validační chyby). Totéž platí pro hodnotu
vrácenou z `OnLookup` přes `Text := …; exit(true)` – platforma ji validuje jako napsanou a skončí ve stejném `OnValidate`.

```al
trigger OnValidate()
begin
    // Save first - Update(false) alone re-reads the row and drops the entered value
    if Rec."Line No." <> 0 then
        CurrPage.SaveRecord();
    CurrPage.Update(false);
end;
```

Kdo po uložení něco přepočítává nad DB (strom, součty), dělá `SaveRecord()` → přepočet → `Rec.Find('=')` →
`Update(false)` (přepočet mohl změnit i aktuální řádek). `Update(false)` bez předchozího uložení patří jen tam, kde se
nic neměnilo nebo se uložilo v kódu (`Rec.Modify` před ním). (2026-10-09, prod-ess-configurator-bc 66845: vazba potomka
na kartách a v dialozích podmínek SL akcí / kusovníku / postupu se z UI neukládala nikdy – chyba z masteru, odhalil ji
až TestPage test.)
⚠️ **Opravu vzoru v produktové appce dotáhni i do zákaznických kopií té stránky.** COALU `CNC Action Cond. Card` (Alumistr,
kopie karty podmínky z COEBS) měla tentýž `OnValidate` jen s `Update(false)` a `OnLookup` s přímým přiřazením do `Rec`;
po opravě v COEBS zůstala rozbitá, dokud ji nechytil code review. Navíc stromový seznam otevřený šipkou při `OnOpenPage`
přepočítá strom (i otevřený řádek) → po `RunModal` seznamu `Rec.Find('=')`, jinak `SaveRecord` uloží zastaralou verzi.
Grep zákaznických rep na název base stránky / komentář „Mirrors …“. (2026-10-09, cust-alumistr-bc 66845, commit 0b39935.)

---

### 4.18 `ListPart` spuštěný přes `Page.RunModal` pod TestPage **není v lookup módu** – ani s `LookupMode(true)`

Strom/seznam typu `ListPart` (často zároveň part na kartě) otevřený jako výběr `Page.RunModal(Page::X, Rec) = Action::LookupOK`
(nebo přes proměnnou stránky s `LookupMode(true)` + `GetRecord`) se v testu chová jako **ne-lookup** modální stránka:
`OK().Invoke()` v `ModalPageHandler` vrátí `Action::OK` (výběr se nevrátí), `Cancel()` hlásí *„The built-in action = Cancel
is not found on the page"* a `Close()` v modálním handleru *„The RunModal procedure could not close the page … as it has
already been closed"*. V klientu výběr funguje (data zákazníka), TestPage ho nasimulovat neumí.

- Test výběru šipkou tedy **nestav na OK z handleru**: handler ověří nabídku (`GoToKey` true/false) a zavře `OK()`, hodnotu
  test zadá po lookupu `SetValue` – ověří se aspoň filtr nabídky a uložení po tom, co seznam při otevření řádek přepočítal.
  Výběr samotný proklikej ručně.
- `PageType` partu kvůli testu neměň – stránka je vložená jako `part` na kartách.

(2026-10-09, prod-ess-configurator-bc 66845, `Cond. Tree UI Tests COEBS`, BC 28.4 kontejner; v kontejneru navíc TestPage
na `Error Messages` nenašel control `Source` z pageextension 705 Base App – handler čte jen `Description`.)

---

### 4.19 Vlastní štítek zboží místo standardního `Item GTIN Label` — skrytí akce `PrintLabel`

Standardní report `Item GTIN Label` (6625, Base App) je nad dataitemem `Item`, jeden štítek na zboží, kóduje **jen pole GTIN**
(Code39 + QR, prázdný GTIN = prázdný štítek). Na `Item Card` (30) i `Item List` (31) ho spouští akce **`PrintLabel`**
v `area(reporting)` (caption *Print Label*, **nepromovaná**, na listu s `CurrPage.SetSelectionFilter(Item)`), takže
`modify(PrintLabel) { Visible = false; }` ji schová bez actionrefu. Vlastní štítek s jiným zdrojem kódu (Item Reference,
číslo zboží) a kopiemi per řádek dokladu je jednodušší jako **vlastní report nad temp bufferem** (vzor cust-alumistr-bc
`Item GTIN Label ALU` 51900 + `Barcode Label Silent Mgt. ALU`) než reportextension 6625: ten by potřeboval nový Word layout
aktivovaný per prostředí v Report Layouts a kopie per řádek stejně neumí → dva layouty téhož štítku. Akce zboží bez
pole „počet kopií" tiskne jeden štítek na vybrané zboží — globální počet kopií nedává smysl, když každé zboží chce jiný.
(2026-10-14, cust-alumistr-bc; názvy akcí ověřeny ze zdroje w1-28 `ItemCard.Page.al` / `ItemList.Page.al`, al-mcp akce nevrací.)
---

### 4.20 `Lookup` a `AssistEdit` na jednom poli — jde to, ale tlačítko „…" dostane AssistEdit

Obě property (i oba triggery `OnLookup` / `OnAssistEdit`) na jednom page fieldu koexistují — MS to potvrzuje nepřímo
v [keyboard shortcuts](https://learn.microsoft.com/en-us/dynamics365/business-central/keyboard-shortcuts): **Alt+→** = AssistEdit
„když Alt+↓ (dropdown / lookup) v témže poli slouží jinému účelu". Vzor v Base App: `Currency Code` na Sales Order
(`TableRelation = Currency` + `OnAssistEdit` → Change Exchange Rate). Ve web klientu otevře viditelné „…" **AssistEdit**,
lookup zůstane na napovídání při psaní / Alt+↓. Důsledek pro pole nad **Text proměnnou s vlastním `OnLookup`** (žádný
TableRelation, žádné type-ahead): po přidání `AssistEdit = true` se k lookupu uživatel dostane jen klávesnicí — zmiň to
v ToolTipu („Choose the AssistEdit button to …"). `OnAssistEdit` se nevolá v režimu prohlížení, `OnLookup` chce `Editable`
(4.3). Když AssistEdit otevře seznam, který mění hlavičkový záznam (tabulka s `OnInsert/OnDelete` → Modify mastera),
po `Page.RunModal` dej `CurrPage.Update(false)` (re-read), ne `Update(true)` (uložil by zastaralý Rec).
(2026-10-14, cust-soitron-bc — `CRM Business Unit SOI` na Customer/Vendor/Item/Job Card: „…" otevře
`<Entity> CRM Business Units SOI` filtrovaný na záznam; chování v klientu zatím neověřeno, jen docs + kompilace.)

---

### 4.21 Pole za cizí control na stránce **bez SourceTable** (kiosk, dialog) — `protected var` + výraz v `SourceExpr`, bez eventů

Card / dialog bez `SourceTable` (Essence kiosk *Kiosk-Qty. To Operation KIEBS*, výběrové dialogy) drží data v page
proměnných a mění je ze skenu (`usercontrol` trigger), `OnValidate`, `OnAssistEdit`, `ClearAll`. Odvozenou hodnotu
(země původu šarže za `"Lot No."`) z pageextension nenaplníš přes `OnAfterGetRecord`, protože bez zdrojové tabulky
nemáš na co navázat, a přidávat do produktové appky event na každé místo, kde se proměnná mění, je zbytečné:

- Proměnné base stránky musí být **`protected var`**. Pageextension je pak čte přímo (`LotNo`, `ItemNo`, `VariantCode`).
  Ověř to v symbolu té verze, proti které kompiluješ: `SymbolReference.json` → `Pages[].Variables[].Protected`. U EM Kiosk
  jsou protected až od 28.0.2, 28.0.1 je měl ještě v běžném `var`. Minimum dependency nastav na první verzi s `protected`.
- Pole v pageextension napiš jako **výraz s voláním procedury**:
  `field(LotCountryRegionCodeMKSON; LotOriginMgtMKSON.GetCountryRegionCode(ItemNo, VariantCode, LotNo)) { Editable = false; }`.
  alc 18 to přeloží bez warningu (CodeCop, UICop, PTE, ALCops). Výraz se vyhodnocuje při každém obnovení stránky, takže
  by měl reagovat na každou změnu proměnných bez triggeru i bez eventu. **V klientu zatím neověřeno**, ověřená je jen
  kompilace. Nepřímý důkaz z kódu, který v produkci funguje: po **každém** triggeru (i `usercontrol` event jako `Scanned`,
  `OnValidate`, `OnAssistEdit`, akce) server přepočítá všechny controly stránky včetně výrazů z pageextension a pošle je
  klientovi; `CurrPage.Update` k tomu není potřeba (EWM *Phys. Inv. Journal* nemá jediný `Update` a pole navázané na
  proměnnou se po skenu ukáže; MS page 1392 *Help And Chart Wrapper* mění `StatusText` v `AddInReady` bez `Update`).
  Base pole a výraz z pageextension se tak nikdy nerozjedou. Jediná cesta bez AL triggeru je editovatelné pole na
  proměnné bez `OnValidate` — tam to v klientu jednou ověř.
- `addafter("<control>")` uvnitř skupiny s `Visible = …` vloží pole do téže skupiny, takže se schová spolu s ní.
- Repeater nad temp tabulkou (part téže stránky) řeš klasicky: proměnná + `OnAfterGetRecord` pageextension.

**Varianta, když base proměnné protected nejsou a base appku smíš upravit: veřejný getter** místo zveřejnění stavu.
Na stránku přidej `procedure GetCurrentLotNo(var ShownItemNo: Code[20]; var ShownVariantCode: Code[10]; var ShownLotNo:
Code[50])` (bez `local`/`internal` — závislá appka nemá `internalsVisibleTo`) a pageextension si ji zavolá v lokální
proceduře použité jako `SourceExpr`. Je to čtení bez zápisu, žádný event, žádná změna chování. Jen `Boolean` pro
`Visible` dej do `protected var` (vlastnost `Visible` funkci volat neumí).
- ⚠️ **Parametry getteru nepojmenuj jako globály stránky.** `procedure Get(var ItemNo: Code[20]) begin ItemNo := ItemNo;
  end;` přeloží bez varování, parametr zastíní globál a přiřadí se sám do sebe → getter tiše vrací prázdno. Vzor
  `parItemNo` je v repu zvykem, ale ALCops LC0092 ho hlásí; neutrální `ShownItemNo` / `ShownLotNo` je čistší a stejné
  na všech stránkách.
- Getter vrací přesně to, co stránka u šarže zobrazuje: když šarži drží jako record `Lot No. Information`, vrať jeho
  klíč (`Item No.`, `Variant Code`, `Lot No.`), ne zvlášť vedené `ItemVariant.Code` — base může šarži dohledat
  s filtrem `Variant Code = ''|<varianta>` a pak by `Get` na kartu šarže nenašel nic.

(2026-10-16, cust-sonnentor-bc PBI 64732, appka `Sonnentor Whse. Mobile and Kiosk Ext.` MKSON; getter v
prod-ew-mobileBase-bc na Move Item / Item Card / Phys. Inv. Journal / Whse Rcpt Tracking / Bin Adjmt. Detail.)

---

### 4.22 Phone klient kreslí listy a ListParty jako **dlaždice** — sloupec z pageextension se na ně často nedostane

Na telefonu (`…/phone?company=…`, čtečky) se `List` i `ListPart` v repeateru standardně kreslí jako dlaždice (přepínač
*Zobrazit jako seznam*). Obsah dlaždice ([Display Data as Tiles](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-lists-as-tiles)):

1. Tabulka má fieldgroup **`Brick`** → pole z Bricku v jeho pořadí, jen ta, která jsou na stránce jako control.
2. Bez Bricku se bere **`DropDown`** („DropDown is interpreted as Brick").
3. Bez obou → **prvních pět controlů repeateru** v pořadí na stránce.

Důsledky pro pageextension:
- **Výrazové pole (bez pole tabulky) do fieldgroup dát nejde** → na dlaždici je jen v režimu 3. Tam ale `addafter` posune
  ostatní controly a **poslední údaj z dlaždice vypadne** (EWM korekce přihrádky: z dlaždice by zmizelo množství).
- Režim 1/2 vyžaduje pole tabulky: tableextension s lookup FlowFieldem + `fieldgroups { addlast(Brick; …) }`. Jde **jen
  `addlast`** (`fieldgroup(Brick…)` i `addfirst` v tableextension = AL0104), pole tedy skončí na konci Bricku.
  FlowField se na stránce spočítá i nad `TableType = Temporary` / `SourceTableTemporary`.
- ⚠️ `addlast(Brick; …)` na tabulce **bez** Bricku od BC 23 Brick **vytvoří jen z přidaných polí** → přepne dlaždice
  z režimu 3/2 na 1 a vyhodí z nich všechno ostatní, na všech stránkách té tabulky.
- Typické tabulky: *Warehouse Activity Line* má Brick, *Bin Content Buffer* nemá žádnou fieldgroup (režim 3),
  *Reservation Entry* jen DropDown (režim 2 — EWM sledování příjemky proto na dlaždici neukazuje ani šarži).

Pravidlo: u čteček dávej odvozené údaje do **hlaviček** (pole ve skupinách). Seznamy rozšiřuj jen s vědomím, co se stane
s dlaždicí, a ověř to v 600×900 (viz `ew-mobile-ui`). (2026-10-16, PBI 64732 — seznamy nakonec vynechány.)

**Doplnění 2026-10-19 (cust-sonnentor-bc Task 65223, číslo zásilky na kiosku):**
- **`modify(<akce>)` na akci uvnitř `cuegroup` (dlaždice kiosku Send / Leave) = `warning AL0611: Modifying actions in
  CueGroups is not supported`** – s Essence `failOn warning` CI fail. Hook „před / po dlaždici“ z pageextension nejde;
  ber integrační eventy stránky (`OnBeforePost`, `OnBeforeLeave`, `OnAfterFillData`, `OnAfterSetTrackingForProdOrderRoutingLine`)
  a eventy účtování (`Item Jnl.-Post.OnBeforeCode` / `OnCodeOnAfterItemJnlPostBatchRun` s guardem
  `Single Instance KIEBS.GetIsKioskCall()`).
- **Vstup uživatele na stránce bez SourceTable z pageextension = SingleInstance stav + výrazové pole + dialog.**
  Editovatelná proměnná pageextension se po `usercontrol` roundtripu (sken kiosku) neobnoví; proto hodnotu drž v
  SingleInstance codeunitu klíčovanou kontextem stránky (klíč řádku VZ z page eventu), pole piš jako výraz
  `Mgt.GetPackageNo(ProdOrderLine, LotNo, SerialNo)` nad `protected var` a ruční zadání řeš `AssistEdit = true` +
  `OnAssistEdit` / `OnDrillDown` (otevře `StandardDialog`) – `AssistEdit` na `Editable = false` výrazovém poli alc 18
  + UICop přeloží bez nálezu (v klientu neověřeno, vzor *Currency Code* na účtovaných dokladech). Sken chyť na
  `Interpret Barcode KIEBS.OnAfterInterpretBarcode` (buffer prázdný = kiosek kód nerozpoznal); kiosk s viditelným
  sledováním zboží nerozpoznaný sken tiše zahodí, takže žádná chyba, a výraz se při renderu přepočítá.
- Scanner add-in kiosku (`Scanner.Startup.js`) je globální `keypress` listener na `window.parent` (terminátor `#`,
  buffer ≥ 3 znaky, bez `preventDefault`) – skenuje se bez fokusu v poli; sken do fokusovaného pole / otevřeného
  dialogu projde zároveň do pole (i s `#`) i do `Scanned` → do dialogů se zadává ručně.
- **Výsledek 2026-10-19:** uživatel variantu „needitovatelný výraz + dialog" zamítl (pole má vypadat jako *Lot No.*,
  tj. psát přímo + „…"), a číslo zásilky šlo **do produktu EM Kiosk** (`protected var PackageNo`, pole, sken, zápis
  při účtování, setup *Package No. on Output*). Pravidlo: když má vstup uživatele na stránce bez SourceTable vypadat
  jako base pole, patří proměnná do base stránky – rozšíření to nenahradí; event navíc nepomůže, pomůže jen
  `protected var` (na tu jde navázat editovatelné pole i z pageextension). `AL0305`: název objektu max 30 znaků
  (`EM Kiosk Package No. Tests KIEBS` = 32).

---

### 4.23 Phone klient: událost control add-inu ze stránky **pod** vrchní stránkou se odloží a přehraje

Na telefonu (`…/phone`) zůstávají stránky otevřené přes `Page.Run` ve stacku (seznam → řádky → detail) a jejich control
add-iny dál běží. Když JS add-inu reaguje na něco globálního (typicky čtečka: `keypress` listener na `window.parent`), volá
`Microsoft.Dynamics.NAV.InvokeExtensibilityMethod` i add-in schované stránky. **BC takovou událost nezahodí, odloží ji a
spustí AL trigger až ve chvíli, kdy se stránka dostane nahoru** – po jedné, v pořadí, a po `Error()` v jedné pokračuje další.
Výsledek: po návratu na seznam vyskočí série hlášek, případně se otevřou stránky, které skener „našel“ dávno předtím.
Kontrola `CurrPage.ObjectId` (proti subpage) to nechytí, ruční zadání do pole netrpí (jde jen do aktivní stránky).

**Jak klient stack skrývá (BC 28, ověřeno v DOM):** každá stránka je `.spa-view`. **Phone:** dvě a víc pod vrcholem
`display:none`, **přímo pod vrcholem `display:block`** s `aria-hidden="true"` a třídou `spa-not-top-most`. **Desktop web
klient** (stejný jev, `Page.Run` = panel nad zašedlou stránkou): zakrytá stránka má jen atribut **`inert`** (+ `spa-not-top-most`),
`aria-hidden` nikde. Proto `getClientRects()`, `offsetParent`, `checkVisibility()`, `document.visibilityState` ani
`IntersectionObserver` stránku přímo pod vrchní **nepoznají**. Spolehlivě rozliší jen
`window.frameElement.closest('[aria-hidden="true"], [inert]') !== null` (zevnitř iframu add-inu, same-origin) – samotný
`aria-hidden` stačí jen na telefonu.

**Fix v JS add-inu:** před `InvokeExtensibilityMethod` zkontroluj, že stránka není zakrytá; když to nejde vyhodnotit
(`frameElement` null, výjimka), pusť událost jako dřív:

```js
function isPageCovered() {
  try {
    return window.frameElement.closest('[aria-hidden="true"], [inert]') !== null;
  } catch (err) {
    return false;
  }
}
```

- Vrchní stránka s otevřeným **dialogem** (Message, Error, Confirm) je taky zakrytá (phone `aria-hidden`, desktop
  `inert`) → událost během dialogu se **zahodí** (bez fixu by se odložila). U čtečky žádoucí, jinde zvaž. Vrchní stránka
  bez dialogu nemá ani jeden atribut (ověřeno na obou klientech).
- Zakrytá je i vrchní stránka pod **modální stránkou** (`RunModal` lookup, např. výběr přihrádky) a na **telefonu** pod
  otevřeným **menu ⋮ / menu partu** (obsah stránky dostane `aria-hidden`); desktop menu stránku neblokuje. **Sbalený
  FastTab / „Zobrazit méně“ je jen `display:none`** – bez `aria-hidden`/`inert`, takže stráž událost pustí.
- Kontrola `CurrPage.ObjectId(false) = Page::X` na začátku obsluhy skenu proti tomu **nepomůže**: v kódu stránky je
  `CurrPage` vždy ta stránka sama, i když je zakrytá (přehrané události jí prošly; build bez kontroly na 16 stránkách
  se choval stejně).
- **Control add-in ve sbalitelném FastTabu (desktop) je mina:** po sbalení a znovurozbalení FastTabu zůstane iframe
  add-inu `about:blank` bez skriptů (add-in mrtvý až do zavření stránky); stránka otevřená už se sbaleným FastTabem
  (BC si stav pamatuje) add-in nevykreslí, vznikne až po rozbalení. Add-in, který musí běžet pořád (čtečka), dávej do
  `area(Content)` nebo do `group`/`grid` bez hlavičky (`ShowCaption = false`). Phone sekci tapem na nadpis nesbalí.
- Je to interní DOM klienta, ne API – po updatu BC ověř. Když klient atributy přestane nastavovat, vrátí se odkládání;
  když by je nastavoval i na vrchní stránku, add-in přestane posílat úplně.
- Simulace skenu z DevTools: keypress na `window` phone záložky; desktop klient běží v `iframe.designer-client-frame`,
  keypress tedy na jeho `contentWindow` (na top `window` se nestane nic).
- **Startup skript add-inu je zabalený** do `function __controlAddInInitialize() {…}`: top-level funkce a `let` nejsou na
  `window` iframu (`typeof iframe.contentWindow.isPageCovered` = `undefined`, i když nový skript běží). Na `window` je
  jen to, co skript přiřadí sám (`window.X = …`, proto AL → JS metody takhle). Nasazenou verzi ověřuj přes text skriptu.

(2026-10-20, prod-ew-mobileBase-bc 66918, BC-DEV: seznam skladových pohybů po dokončení dokladu otevíral detaily cizích
dokladů, seznam vyskladnění hlásil „Naskenován špatný čárový kód“ za každý sken z karty a detailu. Build 28.0.0.9 jen
s `aria-hidden` opravil phone, na desktopu replay zůstal; 28.0.0.10 s `[inert]`: phone 21 + desktop 15 simulovaných
skenů, všechny poslala jen vrchní stránka, 4 zahozené pod dialogem.)

---

### 4.24 Kostka „moje doklady" na `SO Processor Activities` — hotový `User ID Filter`, vlastní drill-down standardních kostek, řazení

- **`Sales Cue."User ID Filter"` (FlowFilter, pole 23) nastavuje standardní `SO Processor Activities` (9060) v `OnOpenPage` na
  `UserId()`, ale žádný standardní FlowField ho nepoužívá.** Vlastní FlowField v tableextension `count("Sales Header" where(…,
  "Assigned User ID" = field("User ID Filter"), "Responsibility Center" = field("Responsibility Center Filter")))` tak dá kostku
  „moje doklady" bez jediného řádku kódu v `OnOpenPage`.
- **Drill-down:** `SalesCue.CopyFilter("User ID Filter", SalesHeader."Assigned User ID")` (seznam vždy sedí s číslem na kostce) →
  `SetTableView` + `Run` cílové list page. Filtry ve filter group 0 jsou v podokně filtrů seznamu běžné, s ×, uživatel je může
  zrušit. **`Responsibility Center Filter` drží `Sales Cue` ve filter group 2** (`SetRespCenterFilter`) → `Rec.GetFilter` ve
  skupině 0 vrátí `''`; nevadí, `Sales Quotes` / `Sales Order List` si ho v `OnOpenPage` nastaví samy (`SetSecurityFilterOnRespCenter`).
- **`modify("Sales Quotes - Open") { trigger OnDrillDown() … }`** na standardní kostce, která má jen `DrillDownPageID` (bez vlastního
  triggeru), se v pageextension přeloží (alc 18, 0 warningů — `AL0611` z 4.22 se týká jen **akcí** v cuegroup) a v klientu nahradí
  výchozí drill-down (ověřeno BC-DEV 28.5). Nová skupina kostek **před** standardními: `addfirst(content)`.
- **Řazení drill-downů od nejnovějšího:** `Page.SetTableView(SalesHeader)` přenese do otevřeného seznamu i `SetCurrentKey` +
  `Ascending(false)` (ověřeno v klientu). Standardní kostky, které otevírá `Sales Cue.ShowOrders` (Ready to Ship, Partially
  Shipped, Delayed), seřadíš subscriberem `Sales Cue.OnFilterOrdersOnAfterSalesHeaderSetFilters(var SalesHeader)`, *Completely
  Reserved from Stock* přes `OnBeforeDrillDownNoOfReservedFromStockSalesOrders(var SalesHeader)`. Podle čeho řadit → 2.10 v `bc-al-data.md`.
- **Test (vzor MS `ERMCues.Codeunit.al`, BCApps `src/Layers/W1/Tests/ERM-Finance/`):** `TestPage "SO Processor Activities".OpenView()`,
  `<List>.Trap()`, `SOProcessorActivities.<control kostky>.Drilldown()`, hodnota kostky `AssertEquals`. Background tasky stránky
  v testu doběhnou. Pořadí řádků čti `First()` / `Next()` do `List of [Code[20]]` a porovnej `IndexOf`.

(2026-10-21, cust-zlomek-bc PBI 65654 — kostky *Moje otevřené nabídky / objednávky* na roli Zpracovatel prodejních objednávek.)

---

### 4.25 `CurrPage.SaveRecord()` a hned `RunModal` = „Došlo k chybě a transakce byla zastavena" → `Commit()` mezi tím

Obálka editoru na stránce, která řádek nejdřív uloží (`CurrPage.SaveRecord()` – u `DelayedInsert` řádek teprve **vloží**,
protože editor potřebuje jeho `Line No.`) a pak otevře modální stránku (`Page.RunModal`, editor vzorce s vlastním `RunModal`),
spadne v klientu na generické **„Došlo k chybě a transakce byla zastavena. O další pomoc požádejte správce nebo partnera."**
(EN *An error occurred and the transaction is stopped*), bez textu skutečné chyby. Zápis z `SaveRecord` je otevřená zápisová
transakce a modální stránku v ní platforma neotevře (stejný mechanismus jako request page reportu po zápisech v testu,
`bc-al-autotests.md`).

- **Fix:** `Commit(); // Required before RunModal` mezi `SaveRecord()` a `RunModal` (komentář kvůli LC0002) — vzor
  konfigurátoru (karty a dialogy podmínek, karta parametru: `if Rec."Line No." = 0 then Rec.Insert(true) else
  CurrPage.SaveRecord(); Commit();`). Totéž u akce na kartě, která před otevřením editoru ukládá hlavičkový záznam.
- Kompilace ani analyzery to nechytí a TestPage test, který editor neotevírá (logika přes tabulky a codeunity), taky ne —
  ukáže se až v klientu. Novou obálku `SaveRecord` → `RunModal` vždy jednou proklikej.

(2026-10-21, prod-ess-configurator-bc PBI 67238 — editor *Filtr dle parametrů* 63198: nový řádek → „…“ u hodnoty → textový vzorec;
build 28.0.37.67238 na Alumistr BC-DEV spadl, 67239 s `Commit()` funguje.)

---

### 4.26 Phone klient: popisek pole podle hodnoty přes `CaptionClass = '3,' + výraz`; `Visible` pole nastav už v `OnOpenPage`

- **Dynamický popisek:** pole nad proměnnou stránky s `CaptionClass = '3,' + ScanUoMMgt.GetScannedQtyCaption(ScannedUoM)` (oblast 3 =
  text bez resolveru, label `Qty. in %1` → „Množství v %1") phone klient vykreslí jako „Množství v KS". `Caption` nech jako fallback
  (a kvůli XLIFF). Čtečka 600 px má v polovičním sloupci gridu na popisek jen ~14 znaků: dvojice „Množství v naskenované MJ" +
  „Naskenovaná MJ" vedle sebe se ořízla na „Množství v nas…" / „Naskenovaná…". Jedno pole s MJ v popisku je čitelné a nic nezabírá.
- **`Visible = Proměnná` na poli** (ne na gridu/skupině) se vyhodnotí po `OnOpenPage`. Proměnná nastavená až v `OnAfterGetCurrRecord`
  nechala pole skryté (dokud byla tatáž proměnná na `grid`, ukázal se). Detail otevřený přes `SetTableView` + `SetRecord` + `Run`:
  v `OnOpenPage` udělej `if Rec.Find('=') then <spočítej proměnné>`.

(2026-10-22, prod-ew-mobileBase-bc 66453 — množství v MJ naskenovaného odkazu na detailech vyskladnění, pohybů, příjemek a inventury;
BC-DEV 28.5, phone klient.)

### 4.27 Phone klient: klepnutí na řádek = náhled, karta z `CardPageId` v režimu zobrazení, chyba pole jen křížek, `InstructionalText`

Ověřeno v BC-DEV 28.5, phone klient 600 × 900 (prod-ew-mobileBase-bc, revize MobileOverallCheck, 2026-10-23):

- **Klepnutí na dlaždici listu bez `CardPageId` otevře náhled záznamu** – generický seznam polí repeateru, bez akcí, prázdné
  drill-down hodnoty jako podtržené „_“. `OnDrillDown` pole se spustí až klepnutím na hodnotu v náhledu → detail na dvě klepnutí.
  S `CardPageId` otevře klepnutí rovnou kartu.
- **Karta z `CardPageId` je v režimu zobrazení** (list je v režimu zobrazení): pole `Rec` jsou šedá, dokud uživatel neťukne na tužku
  (a tužka v phone klientu otevře novou instanci karty). Stejná karta otevřená z kódu (`Page.Run` / proměnná stránky + `Run`) je
  editovatelná. **Pole nad proměnnou stránky zůstanou editovatelná i v režimu zobrazení** → množství na mobilním detailu važ na
  proměnnou a v `OnValidate` udělej `Rec.Validate(...)` + `Rec.Modify(true)` (ne `CurrPage.SaveRecord`).
- **`Error` v `OnValidate` pole = inline chyba pole**: na telefonu jen červený křížek u pole a banner „Na stránce je chyba. Opravte
  chybu nebo zkuste zrušit změnu.“, **text chyby až po klepnutí na křížek**; hodnota zůstane v poli. Když pak kód stránku zavře
  (`CurrPage.Close`), klient se zeptá „Na stránce se vyskytly neuložené změny. Chcete zrušit tyto změny?“. `Error` z triggeru
  control add-inu (sken čtečky) se ukáže jako normální dialog. Otevřená bublina s chybou (klepnutí na křížek) stránku překryje jako
  dialog (`aria-hidden`).
- **`InstructionalText` funguje i na telefonu** – placeholder v prázdném poli (např. „Naskenujte nebo zadejte kód“ u ručního zadání).
- **Pořadí slotů dlaždice bez fieldgroup (4.22, režim 3)** v praxi: 1. control drobně nahoře, 2. nadpis (odkaz), 3. vpravo (číslo),
  4. pod nadpisem vlevo, 5. pod číslem vpravo; prázdné hodnoty se slévají. Množství + MJ dávej na 3 + 4/5, ne variantu na 2
  (prázdná varianta = prázdný nadpis). Ověř v 600 × 900.
- **List otevřený přes `Page.Run(Page, Rec)` se `SetRange` filtry a bez záznamů:** v triggerech může `Rec` nést hodnoty filtrů
  z otevření (šablona, list deníku), ne ale filtr nastavený až v `OnOpenPage` (lokace). `NewLine := Rec` pak dá řádek bez lokace →
  „Pole Kód přihrádky … nelze nalézt ve svázané tabulce“. Prázdnost testuj `Rec."Line No." = 0` / `IsEmpty`, ne filtrovaným polem;
  názvy si vezmi z filtrů (`Rec.GetFilter` + `Rec.GetRangeMin`) v `OnOpenPage`.

### 4.28 Phone klient: `\` ve zprávě nezalomí řádek; neviditelné control add-iny uprostřed stránky dělají mezeru

- **`Message` s řádky oddělenými `\`** (`'Operace zahájena pro:\Výrobní zakázka č.: %1\Číslo řádku: %2'`) vykreslí desktop jako
  víc řádků, phone klient (BC 28.5, 600 × 900) jako jeden odstavec bez zalomení. Na kiosky a čtečky piš zprávu jako jednu
  větu (`Operace %1 výrobní zakázky %2 byla zastavena a zaúčtována. Výstup: %3, zmetky: %4.`).
- **Control add-iny bez vlastního obsahu** (čtečka `Scanner`, `SetFieldFocusAndBlur`) mezi skupinou polí a dlaždicemi akcí
  zaberou na telefonu výšku svého iframu a mezi poli a dlaždicemi zůstane prázdné místo. Dej je v `area(Content)` až za
  dlaždice jako poslední controly. Pozor, ne do sbalitelného FastTabu (4.23).

(2026-10-23, prod-em-kiosk-bc 61658, Kiosk Start-Stop a dialog množství na phone klientu BC-DEV.)
