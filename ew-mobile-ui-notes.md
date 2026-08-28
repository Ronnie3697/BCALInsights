# EW Mobile — UI / Control AddIn / JavaScript poznatky

Poznatky z praxe specificky pro mobilní warehouse čtečky (Business Central AL). Doplněk k `bc-al-notes.md` — tam patří obecné BC/AL gotchas, sem patří všechno kolem rendering na mobilu, dotykového UI, Control AddInů, JS/HTML customizace a integrace s scannery.

Repo kde se to používá: `C:\WorkTasks\prod-ew-mobileBase-bc` (Essence Warehouse Mobile Base + CZ extension).

---

## Proč tento soubor existuje

Standardní BC page renderování vypadá na mobilu/dedikované čtečce dost špatně — příliš malé fonty, špatný layout, labely ukusují prostor, repeater je těžkopádný, cuegroup tlačítka mají nekonzistentní velikosti. Tenhle soubor sbírá konkrétní workaroundy, patterny a funkční recepty.

---

## Jak to BC renderuje na mobilu — základ

- Mobile BC klient (nebo webová verze na tabletu) dostává ten samý metadata stream jako desktop.
- Page layout (group, field, repeater, cuegroup) se mapuje na responsive HTML. Malé obrazovky dostanou jinou layout logiku, ale nedá se do toho moc mluvit.
- Dedikované čtečky (Zebra TC-series, Honeywell, apod.) mají typicky browser/webview s malou obrazovkou (480×640 až 720×1280), dotykem a HW scannerem. Renderuje se webová verze BC.
- `Scanner Control Add-in EXEBS` a `SetFieldFocusAndBlurEXEBS` v repu řeší přijímání skenů a focus management.

---

## Known limitations standardního BC page renderingu na mobilu

*(doplňuj jak narazíš)*

- TODO: popsat co konkrétně vypadá špatně na Pre-Receipt Detail page
- TODO: popsat co vypadá špatně na Whse Receipt Lines
- TODO: popsat co vypadá špatně na Move Item

---

## Pattern: Custom Control AddIn jako celá "page"

Když standardní field/group/repeater layout nestačí, udělej Control AddIn který renderuje **celou obrazovku** a umísti ho jako jediný usercontrol na page.

### Kostra Control AddInu

```al
controladdin "My Custom UI EXEBS"
{
    RequestedWidth = 100;
    RequestedHeight = 100;
    MinimumWidth = 100;
    MinimumHeight = 100;
    HorizontalStretch = true;
    VerticalStretch = true;
    HorizontalShrink = true;
    VerticalShrink = true;

    StartupScript = 'src/Scanner/MyCustomUI.ControlAddIn/startup.js';
    Scripts = 'src/Scanner/MyCustomUI.ControlAddIn/app.js';
    StyleSheets = 'src/Scanner/MyCustomUI.ControlAddIn/app.css';

    event OnReady();
    event OnAction(actionName: Text; payload: JsonObject);

    procedure RenderData(data: JsonObject);
    procedure ShowToast(msg: Text; level: Text);
    procedure SetFocus(fieldName: Text);
}
```

### Kostra hostující page

```al
page 62240 "My Custom Scanner EXEBS"
{
    PageType = Card;
    ApplicationArea = All;
    SourceTable = "Some Record";
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            usercontrol(UI; "My Custom UI EXEBS")
            {
                trigger OnReady()
                begin
                    CurrPage.UI.RenderData(BuildJson(Rec));
                end;

                trigger OnAction(actionName: Text; payload: JsonObject)
                begin
                    case actionName of
                        'add':
                            HandleAdd(payload);
                        'delete':
                            HandleDelete(payload);
                        'back':
                            CurrPage.Close();
                    end;
                end;
            }
        }
    }

    local procedure BuildJson(Rec: Record "Some Record"): JsonObject
    var
        Json: JsonObject;
    begin
        Json.Add('itemNo', Rec."Item No.");
        Json.Add('qty', Rec.Quantity);
        exit(Json);
    end;
}
```

### Komunikace AL ↔ JS

- **JS → AL**: `Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnAction', ['add', {bin:'A1', qty:5}])`
- **AL → JS**: AL procedura (`RenderData`) volá globální JS funkci stejného jména definovanou ve `startup.js` nebo `app.js`:
  ```js
  window.RenderData = function (data) {
      // data = JsonObject z AL jako plain JS object
      document.getElementById('qty').textContent = data.qty;
  };
  ```
  Musí to být **`window.XYZ`** (global scope), ne lokální funkce uvnitř IIFE — BC call loader hledá funkci přes `window[name]`.

### Ready race — AL může chtít renderovat dřív, než je iframe připravený

Control AddIn iframe se loaduje asynchronně. AL `OnOpenPage` často proběhne **předtím**, než JS stihne `InvokeExtensibilityMethod('Ready', [])`. Pokud v `OnOpenPage` rovnou voláš `CurrPage.UI.RenderData(...)`, data se ztratí.

Pattern:

```al
var UIReady: Boolean;
    HasPendingData: Boolean;

trigger Ready()  // event z Control AddInu
begin
    UIReady := true;
    if HasPendingData then
        PushDataToUI();
end;

local procedure PushDataToUI()
begin
    if not UIReady then begin
        HasPendingData := true;
        exit;
    end;
    CurrPage.UI.RenderData(BuildPayload());
    HasPendingData := false;
end;
```

Platí i naopak — když má page **part** s vlastním Control AddInem, `SetData` na part musí buďto počkat na Ready jeho vnitřního addinu, nebo mít analogický `UIReady` flag uvnitř té part page.

### Soubor layout konvence (dle bc-al-notes.md)

- `MyCustomUI.ControlAddIn.al` ↔ `MyCustomUI.ControlAddIn/` složka
- Uvnitř `startup.js`, `app.js`, `app.css`, případně `template.html`
- Control AddIn property `Scripts` / `StyleSheets` cesty jsou **relativní k root projektu**, nikoli k `.al` souboru

**Konkrétní zavedený split v tomto repu** (ew-mobile-base):
- AL deklarace (page, controladdin) → `app/src/<Feature>/`
- JS/CSS implementace → `app/src/controlAddIns/<Feature>/`

Oddělené složky, ale stejný `<Feature>` segment, aby šlo oba páry najít. Viz existující `Scanner/` + `controlAddIns/Scanner/js/`.

### Velikost AddInu — default 100×100 je past

`RequestedHeight = 100; MinimumHeight = 100;` (default) znamená, že BC renderuje iframe na 100 fyzických px a `VerticalStretch = true` to jen málokdy přehlasuje. Výsledek: addin vypadá jak plochý proužek, obsah se zalamuje.

Pro fullscreen-style UI použij rozumně velké hodnoty:

```al
RequestedHeight = 560;
MinimumHeight = 320;
VerticalStretch = true;
VerticalShrink = true;
```

`RequestedHeight` je preferovaná výška; `MinimumHeight` je tvrdá spodní hranice. Na úzké čtečce se addin může smrštit jen k MinimumHeight, proto ho drž dost velký, aby obsah vůbec dával smysl.

Kombinuj s CSS:

```css
html, body { height: 100%; overflow: hidden; margin: 0; }
#controlAddIn { width: 100%; height: 100%; box-sizing: border-box; }
.shell { height: 100%; display: flex; flex-direction: column; }
.scrollable-list { flex: 1 1 auto; min-height: 0; overflow-y: auto; }
```

Bez `html, body { height: 100% }` se body stáhne na obsah a BC addin vizuálně "propadne". `min-height: 0` na flex-child je nutnost, jinak flexbox nerespektuje `overflow-y: auto`.

**BC nemá veřejné API pro auto-resize zevnitř iframu.** Výšku řeš výhradně AL properties + CSS height chainem.

### part() s Control AddInem — ListPart vs CardPart

Když part page obsahuje **jen** usercontrol (bez repeatru), použij `PageType = CardPart`. `ListPart` bez repeatru BC nevadí zkompilovat, ale chová se neočekávaně (renderuje prázdný list container kolem addinu). CardPart dá addinu čistou plochu.

Hosting page volá `CurrPage.Bins.Page.SetData(...)` úplně stejně u obou typů.

---

## Touch / mobile UX pravidla

- Minimální hit target **48×48px** (Material Design baseline). Tlačítka menší než to jsou na čtečce nepoužitelná v rukavici.
- Font minimálně **16px** pro labely, **20px+** pro hlavní data. Menší fonty se na 720p čtečce blbě čtou.
- Žádné hover-only interakce. Všechno musí fungovat jen na tap.
- Kontrast: warehouse je často špatně osvětlený sklad → výrazné barvy, ne jemné šedé.
- Layout **jednosloupcový** na šířkách < 600px. Grid na širších zařízeních (tablet).
- Vždycky viditelný **back/zpět** button — mobilní uživatel nemá klávesu Escape.

---

## Scanner integration

- Dedikovaná čtečka posílá scan jako **keyboard input** do focusovaného `<input>` elementu + `Enter`.
- Pattern: mít v DOMu skrytý (nebo viditelný pro ruční fallback) `<input type="text">` s autofocusem; listener na `keydown Enter` → vezmi value → pošli do AL přes `InvokeExtensibilityMethod`.
- V AL existuje `Scanner Control Add-in EXEBS` který to už dělá — dá se **kombinovat** s custom Control AddInem (oba usercontrols na page).
- **SetFieldFocusAndBlurEXEBS** — pomocný control addin co drží focus na Manual Input field. Na custom UI Control AddInu se řeší focusem uvnitř iframe (ne hosting page field).

---

## Známé gotchas

*(doplňuj jak narazíš)*

- Control AddIn běží v **iframu** → žádný přístup k parentovi, žádné localStorage cross-page, sessionStorage OK.
- `CurrPage.UI.Method(...)` volání z AL je **asynchronní** — JS metoda se nespustí okamžitě, ale v dalším render tiku. Pokud hned po volání zavřeš page, metoda se nemusí stihnout zavolat.
- V BC 27+ bude usercontrol v režimu strict CSP → inline scripty / `eval` nefungují. Všechno v externích JS souborech.
- Když page má ještě i `field` mimo usercontrol, layout se rozpadne — custom AddIn chce **celou obrazovku**.
- **Mobilní web klient vs. dedikovaná čtečka s nativním klientem** se renderují různě. Testuj na obou.
- **`RequestedHeight = 100` + `VerticalStretch = true` ≠ full-height.** Stretch zabere jen prostor nad Requested, ne místo Requested. Nastav Requested na realistickou preferovanou výšku.
- **Dva Control AddIny na jedné Card page** fungují v pohodě (jeden přímo na Card, druhý uvnitř part). Každý má vlastní iframe, vlastní Ready lifecycle — oba potřebují svůj `UIReady` flag, nesdílejí nic.
- **`Scanner Control Add-in EXEBS` posílá keypress přes `window.parent`.** Když máš custom UI addin s vlastním input fieldem, může mu scanner "ukrást" znaky (scanner je keypress listener na parent window, custom input je v iframu). Na čtečce v praxi funguje dobře, protože scan přijde jako burst a dostane ho scanner addin. Ruční psaní do JS inputu funguje nezávisle přes Enter handler.

---

## Aktuální problémy k vyřešení / tuning

*(living list — jak budeme poznávat konkrétní issues, zapisujeme sem, a jakmile najdeme řešení, přesuneme nahoru do patternů)*

- [ ] Pre-Receipt Detail page — co konkrétně vypadá špatně na čtečce?
- [ ] Whse Receipt Lines — rozmístění tlačítek, velikost fontů
- [x] Universal — vizuální feedback po skenu → vyřešeno toast + flash animací v Item Card JS demu, pattern lze replikovat
- [x] Dlouhé Bin/Lot kódy — v custom AddInu řešíme `word-break: break-all` na bin code a chip komponentami pro meta; v native repeateru zůstává problém

---

## Reference

- BC docs — Control AddIn: https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-control-addin-object
- Control AddIn JS API (`Microsoft.Dynamics.NAV.InvokeExtensibilityMethod`): https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-control-add-in-methods-js
- Existující v repu: `base/app/src/Scanner/ScannerControlAddIn.ControlAddin.al`, `base/app/src/Scanner/SetFieldFocusAndBlur.ControlAddin.al`
- **Živý příklad custom UI AddInu v tomto repu** (mobile JS demo Item Card):
  - AL: `base/app/src/ItemCardJS/ItemCardEWMJS.Page.al` (62250), `ItemCardSubformEWMJS.Page.al` (62251), `ItemCardUIJS.ControlAddin.al`, `ItemCardBinsUIJS.ControlAddin.al`
  - JS/CSS: `base/app/src/controlAddIns/ItemCardJS/itemCard.{js,css}`, `itemCardBins.{js,css}`
  - Demo pokrývá: dva AddIny na jedné Card page (hlavní + part), Ready race handling, fullscreen height pattern, bin cards s chipy, toast, flash animace. Akce na RoleCenter: `EWMActivities.Page.al` → "Item Detail (JS)" (červená dlaždice).

---

## Jak pokračovat

Tenhle soubor je **living document**. Cokoliv co:

- vyřešíme (rendering problém, JS trick, BC gotcha) → zapíšeme jako pattern
- narazíme na (špatné chování, bug, workaround) → zapíšeme jako známou limitaci
- plánujeme udělat → do "Aktuální problémy"

Před jakýmkoliv UI/JS tuningem v tomto repu nejdřív přečti tenhle soubor.

---

## Budoucí migrace všech page do JS kabátku — strategie

Až bude zelená od šéfa na předělání všech mobilních page do Control AddIn stylu (jako je teď Item Card JS + Bin Content Card JS demo), nejdřív si zvědoměle rozhodnout tyhle tři věci, **než** začneme klonovat patterny do 20 page:

### 1. Společná JS/CSS knihovna

Nedělat každou page s vlastní kopií `escapeHtml`, `formatQty`, toast logiky, scan handleru, chipů, kartiček. Místo toho:

- `app/src/controlAddIns/_common/common.js` — utility (escapeHtml, formatQty, toast mount, scan input handler, Ready boot)
- `app/src/controlAddIns/_common/common.css` — design tokens (CSS variables — barvy, radius, fonty), `.chip`, `.btn`, `.card`, `.shell`, `.hero`
- Každý Control AddIn v `Scripts` property přidá `common.js` **před** svým `feature.js`
- StyleSheets analogicky — `common.css` první

Důvod: až budeme chtít změnit akcent z azure na zelenou, ať se to udělá na jednom místě, ne na dvaceti. Taky konzistence UX.

### 2. Skeleton template page + Control AddIn

Mít v repu `_template/` složku s:
- `TemplatePageJS.Page.al` — prázdná Card page s `usercontrol(UI; "Template UI JS EXEBS")`, Scanner, Manual Input, Ready race flagy
- `TemplateUIJS.ControlAddin.al` — rozumné default RequestedHeight/MinimumHeight, standardní události (Ready, ManualScan, Action)
- `template.js` / `template.css` — shell s hero + akcemi + scan inputem

Každá nová page je potom copy-paste skeletonu + specifická logika. Čas na novou page klesne z "celý den" na "hodinu".

### 3. Navigační model — **rozhodnout předem**

Jakmile je 3+ mobilních page propojených kliky (Item Card → Bin Content → Bin Adjust → zpět), kupí se zásobník otevřených page. Uživatel pak mačká back 10× místo jednou. V demu jsme to řešili ad-hoc přes `CurrPage.Close(); Page.Run(...)`, ale u 20 page to nebude stačit. Možnosti:

**A) Flat navigation — každý klik `CurrPage.Close()` + `Page.Run()`**
- Jednoduché, nevzniká stack
- Ztráta "zpět na předchozí page" — uživatel se vrací rovnou na RoleCenter
- Funguje pro úzká workflow (sken → detail → akce → hotovo)

**B) Navigační codeunit se zásobníkem**
- SingleInstance codeunit drží list navštívených page + parametrů
- Custom "Back" button v UI volá `NavStack.GoBack()` který `CurrPage.Close() + Page.Run(previousPage, previousArgs)`
- Víc práce, ale dá explicitní kontrolu nad tím, co "back" dělá

**C) Hybrid — "home" button všude**
- Vedle back buttonu ještě "🏠 Home" co zavře všechno a skočí na RoleCenter
- Uživatel nikdy není zaseknutý hluboko ve stacku
- Doplněk k A i B

Doporučení: začít s **A + C** (flat + home button). Jednoduché, rychlé, UX příjemný. B přijde až kdyby se ukázalo, že uživatelé chtějí vracet mezi page s drženým kontextem.

### 4. Pořadí migrace

Ne všechno najednou. Seřadit page podle:
- **Frekvence použití** (nejčastější workflow první — většinou Warehouse Pick + Put-away + Move Item)
- **Bolest na čtečce** (kde si uživatelé stěžujou nejvíc)
- **Komplexita** (jednodušší page jako proof of concept, složité na konec)

Každá migrovaná page v repu žije vedle staré (jako teď Item Card JS vedle Item Card) — uživatel si nejdřív vyzkouší, až potvrdí, že JS verze je OK, stará se může odstranit. Nebo radši nechat jako fallback.

### 5. Testování

Každá migrovaná page musí projít:
- Rendering na skutečné čtečce (ne jen web klient na desktopu)
- Scan + manuální input + různé typy čárových kódů
- Navigace zpět i dopředu ve workflow
- Edge cases — prázdná data, dlouhé kódy, chyby

---
