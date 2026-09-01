---
name: ew-mobile-ui
description: >-
  Essence Warehouse Mobile (repo prod-ew-mobileBase-bc) — UI pro dedikované
  čtečky čárových kódů v Business Central (AL): Scanner Control Add-in EXEBS
  (trigger Scanned, JSON outScannedString), SetFieldFocusAndBlur, Manual Input
  pole (i ExtendedDatatype = Barcode), Interpret Barcode řetězec přes
  Name/Value Buffer (Item Reference → Item → Variant → Bin → Lot → Serial,
  isHandled), ObjectId check pro subpage, cuegroup Tile akce,
  SourceTableTemporary + SetData, SingleInstance session state,
  OnBeforeInterpretScannedBarcode; custom Control AddIn jako celá page
  (kostra AL + JS, window.* globály, Ready race, RequestedHeight 100 past,
  CSS height chain, CardPart), touch UX pravidla, scanner integrace, gotchas
  (iframe, async CurrPage.UI, CSP BC27+), strategie migrace page do JS
  kabátku. Načti při práci s mobilními stránkami, control addiny, JS/CSS,
  skenováním, čtečkami, warehouse mobile UI.
user-invocable: true
---

# EW Mobile — UI / Control AddIn / JavaScript

**Zdroj pravdy:** `C:\WorkTasks\BCALInsights\ew-mobile-ui-notes.md`
(v repu `../../ew-mobile-ui-notes.md` relativně k tomuto skillu). Tenhle skill je jen
wrapper — pravidla níže jsou výcuc; kostry AL/JS, CSS a strategie migrace
jsou v souboru (sekce „Zavedené AL vzory v base appce" je ověřená přímo
z repa, ostatní jsou poznámky z praxe). Repo, kde se to používá: `C:\WorkTasks\prod-ew-mobileBase-bc`
(Essence Warehouse Mobile Base + CZ extension); JS/HTML/CSS experimenty (Item
Card JS, Bin Content Card JS) žijí necommitnuté v druhém klonu téhož repa
`C:\WorkTasks\prod-ew-mobileBase-bc-JavaScript`.

## Co udělat

1. **Přečti `C:\WorkTasks\BCALInsights\ew-mobile-ui-notes.md` celý.** Vejde se do jednoho Read;
   když se výstup ořízne, dočti přes `offset`. Před jakýmkoliv UI/JS tuningem
   v tom repu.
2. Obecná AL pravidla platí dál: `bc-al-style` (naming doprovodných souborů
   1.3, UI patterny 4), `bc-al-data`, u netriviální logiky `bc-al-autotests`.
3. Nový poznatek (rendering problém, JS trik, gotcha) → do souboru (living
   document) + commit + push (viz skill `bc-al`).

## Zavedené AL vzory v mobilní appce

- **Scanner control addin** — vlastní JS control addin `Scanner Control Add-in
  EXEBS` pro příjem skenů z dedikované čtečky; trigger `Scanned(content:
  JsonObject)` vrací JSON s klíčem `outScannedString`. JS poslouchá `keypress`
  na `window.parent`, sken končí suffixem **`#`** (ne Enter), ≥ 3 znaky, 200 ms okno.
- **SetFieldFocusAndBlurEXEBS** — control addin, který po zpracování skenu /
  akce vrátí focus na pole `Manual Input` a hned blur
  (`CurrPage.SetFocusAndBlur.SetFocusOnFieldAndBlur('Manual Input')`); scanner
  sám focus nepotřebuje.
- **Manual Input pole** — textové pole jako fallback pro ruční zadání kódu;
  některé stránky mají variantu s `ExtendedDatatype = Barcode` (kamera).
- **Interpret Barcode** — codeunit `EWM Interpret Barcode EXEBS` (62201)
  interpretuje barcode přes Name/Value Buffer; zkouší postupně Item Reference →
  Item → Variant → Bin → Lot → Serial → Whse Pick → Sales Order → Whse Shipment →
  Whse Receipt → Resource → Prod. Order Rtng Line → Batch Name → Prod. Order →
  Machine/Work Center → Phys. Invt. Order. První match nastaví `isHandled` a
  přeruší řetězec; hooky `OnBeforeInterpretBarcode(Barcode, NameValueBuffer,
  isHandled)` / `OnAfterInterpretBarcode`.
- **Page ObjectId check** — každá stránka v InterpretScan kontroluje
  `CopyStr(CurrPage.ObjectId(false), 6) = Format(Page::...)`, aby sken
  nezpracovala, když běží jako subpage.
- **Cuegroup akce** — `cuegroup` s `Image = TileXxx` (TileNew, TileRed,
  TileCyan…) místo klasických action buttonů — větší hit target; pozor,
  velikosti tiles nejsou konzistentní (known limitation).
- **SourceTableTemporary** — zobrazovací stránky používají temporary tabulky
  s procedurou `SetData`.
- **SingleInstance codeunit** — `Single Instance EXEBS`: session state mezi
  stránkami (`Set/GetSelectedLocation`, `Set/GetHHTPosting`).
- **Integration events** — `OnBeforeInterpretScannedBarcode(parNameValueBuffer:
  Record "Name/Value Buffer"; var IsHandled: Boolean)` na všech 13 skenovacích
  pages (z 27) pro extensibilitu.

## TL;DR — Control AddIn a mobilní UX

- Standardní page rendering na čtečce (480×640 až 720×1280) vypadá špatně →
  když nestačí field/group/repeater, **Control AddIn jako celá obrazovka**,
  jediný `usercontrol` na page (fieldy mimo něj rozbijí layout).
- Repo je členěné **podle typu objektu** (`page/`, `codeunit/`…); base addiny
  mají AL v `src/Scanner/` a JS v `src/controlAddins/Scanner/js/` (pozor na
  case vs. `Scripts` property). Návrh pro nové addiny: `src/<Feature>/` +
  `src/controlAddins/<Feature>/`. `Scripts`/`StyleSheets` cesty jsou relativní
  k rootu projektu; soubory pojmenované jako `.al` (1.3).
- **JS → AL:** `Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnAction',
  [...])`. **AL → JS:** procedura volá globální `window.RenderData = …`
  (ne funkce uvnitř IIFE).
- **Ready race:** AL `OnOpenPage` běží dřív, než iframe pošle `Ready` →
  `UIReady` + `HasPendingData` flagy, render až po Ready; každý addin (i v
  partu) má vlastní Ready lifecycle a vlastní flag.
- **`RequestedHeight = 100` default je past** — stretch nepomůže; nastav
  realistickou výšku (`RequestedHeight = 560; MinimumHeight = 320;`) + CSS
  `html, body { height: 100% }`, `.shell { display: flex }`, `min-height: 0`
  na scrollovatelném flex-child. Žádné auto-resize API.
- Part jen s usercontrolem → `PageType = CardPart`, ne ListPart.
- `CurrPage.UI.Method(...)` je **asynchronní** — nezavírej page hned po volání.
- Iframe je same-origin → `window.parent` **jde** (base addiny ho používají), ale
  je to hack nad interním BC DOM — nový kód drž v iframu. sessionStorage OK;
  BC27+ strict CSP → žádné inline skripty / `eval`.
- Touch: hit target ≥ 48×48 px, font ≥ 16 px (data 20 px+), žádný hover-only,
  jednosloupcový layout < 600 px, vždy viditelné **zpět**, vysoký kontrast.
- Scanner posílá keyboard burst + suffix **`#`** (ne Enter; `Scanner.Startup.js`:
  ≥ 3 znaky, 200 ms okno). Base addin poslouchá na `window.parent` a může
  custom inputu v iframu ukrást znaky; `Scanner Control Add-in EXEBS` jde
  kombinovat s custom addinem (dva usercontrols); vlastní input v iframu má
  handler na terminátor.
- Migrace všech page do JS: nejdřív společná `_common/common.{js,css}`
  (v `Scripts` **před** feature.js), `_template/` skeleton, navigační model
  (doporučeno flat + Home button), pořadí podle frekvence/bolesti/komplexity;
  testovat na reálné čtečce — web i nativní klient renderují různě. Item Card
  JS / Bin Content Card JS demo žije necommitnuté v JS klonu
  `C:\WorkTasks\prod-ew-mobileBase-bc-JavaScript`.
