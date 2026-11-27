# BC/AL poznámky — UI na phone klientu a čtečkách

> Vyčleněno z `bc-al-ui.md` 2026-11-27 (soubor měl 1027 řádků); číslování 4.22, 4.23, 4.26–4.29, 4.33 je původní kvůli
> odkazům „viz X.Y“. Ostatní UI patterny (4.1–4.21, 4.24, 4.25, 4.30–4.35) zůstávají v `bc-al-ui.md`; odkaz na číslo
> bez jména souboru hledej nejdřív tady, pak tam.
> Načítej, když řešíš: stránky pro phone klient (`…/phone`), čtečky a kiosky — dlaždice listů a ListPartů (Brick / DropDown /
> prvních 5 controlů), událost control add-inu ze zakryté stránky (`aria-hidden` / `inert`), popisek podle hodnoty
> (`CaptionClass '3,'`) a `Visible` na phone klientu, klepnutí na řádek = náhled, kartu z `CardPageId`, chybu pole jen jako
> křížek, `\` v `Message`, mezeru po control add-inu, navigaci seznam → řádky → detail, čtečkovou obdobu akce cizí appky
> (AC Parcels), barvy kostek a výběr jedním klepnutím.
> Vzory Essence Warehouse Mobile a Control add-in / JS drží osobní skill `ew-mobile-ui` (mimo tohle repo, kdo ho má).

Obsahuje:
- **4.22** phone klient kreslí listy a ListParty jako dlaždice — co se na dlaždici dostane z pageextension
- **4.23** událost control add-inu ze stránky pod vrchní stránkou se odloží a přehraje
- **4.26** popisek pole podle hodnoty (`CaptionClass = '3,' + výraz`), `Visible` pole vs. skupiny
- **4.27** klepnutí na řádek = náhled, karta z `CardPageId` v režimu zobrazení, chyba pole jen křížek, `InstructionalText`
- **4.28** `\` ve zprávě nezalomí řádek; neviditelné control add-iny dělají mezeru
- **4.29** seznam dokladů → řádky → detail bez náhledu; detail z partu dědí `SubPageView`
- **4.33** čtečková obdoba stránky cizí appky (AC Parcels / Balíkobot), barvy kostek, výběr jedním klepnutím, „Zpět až na úvodní stránku“

## 4. UI patterny — phone klient a čtečky

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

**Údaj na dlaždici bez nového sloupce = přidat ho do textu, který dlaždice už ukazuje** (2026-10-23, PBI 64732 fáze 2, ověřeno
BC-DEV 28.5 phone klient):
- **Textové pole z Bricku, které base stránka plní v `OnAfterGetRecord`** (EWM `Item Nos. EXEBS` = varianta; šarže; SČ na
  *Warehouse Activity Line*, jen pro zobrazení, bez `Modify`): pageextension má vlastní `OnAfterGetRecord`, který běží **po** base
  triggeru, a pole přepíše (`Rec."X" := CopyStr(…, 1, MaxStrLen(Rec."X"))`). Slot na dlaždici zůstane, žádná závislost na eventu base.
  Část textu nahrazuj po oddělovači (`Text.Split('; ')` + porovnání s číslem šarže), ne `Replace` (šarže může být podřetězcem varianty).
  `PC0037` na přiřazení je tu namístě (zobrazovací hodnota).
- **Výraz přímo na stránce** (`field("Item No."; Mgt.GetItemNumbers(...))` nad *Bin Content Buffer*, režim 3) pageextension nepřebije
  (`modify` mění jen properties, 4.6c v `bc-al-ui.md`) → do base appky **formátovací procedura s integračním eventem** (EWM `GetLotNoText` →
  `OnAfterGetLotNoText(ItemNo, VariantCode, LotNo, var LotNoText)`), subscriber v zákaznické appce. Jeden event pokryje všechny stránky,
  které proceduru volají, i budoucí. Samostatný control nad polem `Rec` (EWM *Bin Adj Subform* `"Lot No."`) převeď na výraz s touž
  procedurou: **název controlu i `OnDrillDown` nech** (4.6b v `bc-al-ui.md`), doplň `Caption` (dřív šel z tabulky → nový trans-unit, překlad do `.cs-CZ.xlf`).
  `Rec` se nemění, drill-down a výběr dostanou čistou hodnotu (ověřeno BC-DEV 2026-10-25). Výrazový control pojmenovaný jako pole tabulky
  hlásí ALCops `PC0033` (duplicitní OData EntityName, jen *Upravit v Excelu*).
  Pozor na volající, kteří do procedury posílají prázdnou variantu (EWM *Item Card Subform*, *Bin Content Buffer*) — subscriber pak hledá
  kartu šarže bez ohledu na variantu.
- **`Tracking Specification` má Brick** (`Lot No.`, `Serial No.`, `Quantity (Base)`, `Package No.`, `Expiration Date`) → sloupec z
  pageextension na partu nad ní (kiosk *Exp. Tracking Specif. KIEBS*) je vidět jen na desktopu, na telefonu ne. Šarži v temp záznamu
  sledování přepisovat nejde (nese skutečné sledování) — řešení jen úpravou base stránky. Fieldgroupy ověř ze `SymbolReference.json`
  Base App (`Tables[].FieldGroups`): *Item Journal Line* Brick (Item No., Description, Quantity, Document No., Document Date), *Reservation
  Entry* DropDown, *Bin Content Buffer* žádný.

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

### 4.26 Phone klient: popisek pole podle hodnoty přes `CaptionClass = '3,' + výraz`; `Visible` pole platí jen z otevření, `Visible` skupiny se přepočítá

- **Dynamický popisek:** pole nad proměnnou stránky s `CaptionClass = '3,' + ScanUoMMgt.GetScannedQtyCaption(ScannedUoM)` (oblast 3 =
  text bez resolveru, label `Qty. in %1` → „Množství v %1") phone klient vykreslí jako „Množství v KS". `Caption` nech jako fallback
  (a kvůli XLIFF). Na 600 px má popisek v polovičním sloupci gridu ~14 znaků („Množství v nas…") → jedno pole s MJ v popisku.
- **`Visible = Proměnná` na poli** platí jen z otevření (po `OnOpenPage`; detail přes `SetTableView` + `SetRecord` + `Run` → v `OnOpenPage`
  `if Rec.Find('=') then <spočítej proměnné>`), pozdější změnu + `CurrPage.Update` nepromítne ani jedním směrem. **`Visible` na skupině**
  bez popisku (`group(X) { ShowCaption = false; Visible = Proměnná; field(…) }`) se přepočítá oběma směry a pole zůstane v toku rodiče →
  pole ukazované podle skenu na už otevřené stránce dej do takové skupiny. `TestPage` skupinu nezpřístupní a `<pole>.Visible()` se skupinou
  je v kontejneru neověřené → „skryto" assertuj jinak (např. `StrPos(<pole>.Caption(), <kód>) = 0`, také zatím neověřeno).

(2026-10-22 a 2026-11-26, prod-ew-mobileBase-bc 66453 — množství v MJ naskenovaného odkazu na detailech vyskladnění, pohybů, příjemek,
dodávek a inventury; BC-DEV, phone klient; s `Visible` na poli se pole po skenu na detailu otevřeném bez MJ neukázalo, se skupinou ano.)

---

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

---

### 4.28 Phone klient: `\` ve zprávě nezalomí řádek; neviditelné control add-iny uprostřed stránky dělají mezeru

- **`Message` s řádky oddělenými `\`** (`'Operace zahájena pro:\Výrobní zakázka č.: %1\Číslo řádku: %2'`) vykreslí desktop jako
  víc řádků, phone klient (BC 28.5, 600 × 900) jako jeden odstavec bez zalomení. Na kiosky a čtečky piš zprávu jako jednu
  větu (`Operace %1 výrobní zakázky %2 byla zastavena a zaúčtována. Výstup: %3, zmetky: %4.`).
- **Control add-iny bez vlastního obsahu** (čtečka `Scanner`, `SetFieldFocusAndBlur`) mezi skupinou polí a dlaždicemi akcí
  zaberou na telefonu výšku svého iframu a mezi poli a dlaždicemi zůstane prázdné místo. Dej je v `area(Content)` až za
  dlaždice jako poslední controly. Pozor, ne do sbalitelného FastTabu (4.23).

(2026-10-23, prod-em-kiosk-bc 61658, Kiosk Start-Stop a dialog množství na phone klientu BC-DEV.)

---

### 4.29 Phone klient: seznam dokladů → řádky → detail bez náhledu (karta hlavičky + ListPart s `CardPageId`); detail z partu dědí `SubPageView`

Ověřeno v BC-DEV 28.5, phone klient (prod-ew-mobileBase-bc, pilot na vyskladnění, 2026-10-23):

- `CardPageId` seznamu hlaviček (vyskladnění) musí vést na stránku nad **hlavičkou** – řádky jako `List` nad tabulkou řádků
  tam nejdou. Řešení: řádky jako **ListPart na kartě hlavičky** (`SubPageLink` doklad, `SubPageView` např. `Action Type =
  Place`) a ListPart má vlastní **`CardPageId` na detail řádku**. Ťuk na doklad → karta s řádky, ťuk na řádek partu → rovnou
  detail, náhled záznamu (4.27) nikde.
- Karta z `CardPageId` je v režimu zobrazení, ale `usercontrol` čtečky dál posílá `Scanned`, dlaždice (cuegroup akce) fungují a
  pole na proměnných stránky jdou psát (4.27). Po akci, která mění řádky, `CurrPage.Update(false)` obnoví i part;
  `RefreshOnActivate = true` obnoví kartu po návratu z detailu.
- **Detail otevřený z ListPartu přes `CardPageId` dědí filtry partu včetně `SubPageView`** (v jiné filter group než 0).
  Kód, který z `Rec` udělá `Copy(Rec)` a pak `SetRange(pole)` maže ve filter group 0, ten filtr neodstraní. Registrace skladové
  aktivity z takového detailu viděla jen řádky Vložit: *„Celkové základní množství k výběru 0 musí být rovno celkovému
  základnímu množství k vložení 1.“* Pro zpracování dokladu ber z `Rec` jen hodnoty (`Line := Rec;` + vlastní `SetRange` na
  doklad), ne jeho filtry.
- Detail otevřený ťuknutím leží **nad** kartou – po zápisu jen `CurrPage.Close()`. Znovu otevírat kartu (`Page.Run`) jen když ji
  předtím zavřel kód (sken: zavřít řádky → detail), jinak je ve stacku dvakrát (příznak nastavený volajícím, např.
  `SetReopenPickOnRegister(true)`). Když zápis smaže hlavičku (celý doklad zapsán), karta pod detailem se po návratu sama
  zavře a uživatel skončí na seznamu – bez chyby.
- Navigaci (stack stránek) testuj v čisté záložce `/phone?company=…`, ne v overlay iframu (`top.history`).
- **Karta z `CardPageId`, která nejde editovat (`Editable = false` nebo `ModifyAllowed = false` na stránce), phone klient
  neotevře** – ukáže místo ní náhled záznamu, i když na desktopu karta funguje. Needitovatelnost dej na pole (`Editable = false`).
- **Přepínací karta** (když stávající stránku nechceš přestavět, nebo detail záleží na situaci): `CardPageId` seznamu = malá
  karta nad stejnou tabulkou, v `OnAfterGetCurrRecord` (s příznakem jen jednou) `CurrPage.Close()` + `Page.Run` cílové stránky
  (řádky dokladu, deník listu, detail řádku podle sledování / nastavení). Cíl otevřený z kódu je v **režimu úprav** (bez tužky)
  a zůstává původní stránka včetně pageextension a eventů zákazníků. V DOM po přepínací kartě zůstane schovaný `.spa-view`,
  Zpět ale vede rovnou na seznam. (prod-ew-mobileBase-bc: pohyby, příjemky, řádky příjemky, listy inventury.)

---

### 4.33 Čtečková obdoba stránky cizí appky, jejíž akci nejde zavolat — veřejné API + srovnání se standardem (AC Parcels / Balíkobot)

Akci jiné stránky z AL nespustíš (ani z vlastní stránky, ani z pageextension — ta vidí jen veřejné procedury a `protected var`).
Když má čtečka umět „totéž co akce *Vytvořit zásilku a vytisknout štítek*", poskládej akci z veřejných procedur appky a
**výsledek porovnej se záznamem, který vytvořila standardní stránka** (hlavička, řádky, přiřazení, parametry, obsah, stav).

- **Parcels (Aricoma Systems, dřív AUTOCONT AC Parcels) nemá zdroják nikde**: v prostředí ani na `BCNugetPackages` (jen
  `…_runtime.app`, NAVX bez ZIPu; feed 2026-11 končí na 27.6.48260, prostředí má 28.4) — `SymbolReference.json` ze symbolu
  z dev endpointu (7.26 v `bc-al-deploy.md`), `DocComments.xml` prázdný, labely bez textů. Vzor složení akce: Kalas
  `CreateParcel_PAKAL` (cust-kalas-bc `ACParcelsExtension`), typy dokladů: Essence `EW Parcels Base Mgt. PAEBS`
  (prod-essence-warehouse-parcels-bc).
- **Postup, který dal stejnou zásilku jako stránka `CreateParcel_aci` (BC-TEST Sonnentor, 2026-11-14):** temp hlavička přes
  `ParcelMgt_aci.FillTempParcelFromSalesInvoice` / `FillTempParcelFromWhseShipment(DocNo, TempHeader)` (vloží záznam) →
  `FillTempParcelLines(Header, Lines, NoOfPackages)` (řádek = balík) → `FillTempParcelAssignment(Header, Assign, DocType, DocNo)`
  → **parametry `FillTempParcelParametersFromSetup(Database::ParcelHeader_aci, 0, Header."No.", agent, služba, Params)`**
  (stránka ukládá parametry zásilky pod *Table ID* 52068433; `FillTempParcelParameters(Header, <tabulka dokladu>, …)` vrátil 0
  řádků a zásilka byla bez 11 parametrů šablony) → `AddTempParcelContentFromSourceDoc(TableId, DocNo, Header."No.", Content)` →
  `AddTempParcelAttachmentsFromSourceDoc` → `CheckParcel` → `CreateParcel2(…, NewParcelHeader)` (už **odešle do Balíkobotu**:
  stav *Ke svozu*, čísla balíků na řádcích; chyby API jako „Nedorazila adresa příjemce“ vyhodí `Error`, nic se neuloží) →
  `Commit` → `Report.Run(Report::PrintParcelLabels_aci, false, false, NewParcelHeader)` (bez PrintNode otevře PDF z `pdf.balikobot.cz`).
- `ParcelDocumentType_aci::"Whse Ship. Header"` = **účtovaná** dodávka ze skladu (ne `"Warehouse Shipment"`). Stránka hlásí chybu,
  když doklad už je v `ParcelDocumentAssigment_aci` („Doklad %1 %2 je již na zásilce %3“) — zkopíruj kontrolu, jinak vznikne druhá zásilka.
- Parametry z prodejní objednávky přenáší Parcels při účtování na prodejní dodávku (*Table ID* 110) a fakturu (112), typ 0.
- **„Faktura objednávky" u dodávek po částech:** faktura se stejným *Číslem objednávky* nemusí fakturovat zboží skenované dodávky
  (BC-TEST: objednávka se dvěma dodávkami, faktura jen k jedné). Vazbu dodávka → faktura ber přes položky ocenění (`Item Ledger
  Entry` dodávky → `Value Entry` typu *Sales Invoice*), ne jen přes `Order No.`.

**Phone klient – drobnosti ze stejné práce:**
- Barvy kostek (`Image` na akci v `cuegroup`): kromě Yellow / Blue / Green / Cyan / Red / Orange / Violet projdou jen **`TileTeal`**
  a **`TileLightGreen`**; `TileGray`, `TilePink`, `TilePurple`, `TileMagenta`… = `warning AL0482` (s `failOn warning` CI fail).
  `TileBrickNew` má velké „+“. Akci do cizí `cuegroup` z pageextension nepřidáš — vlastní `cuegroup` `addafter(<cuegroup>)`.
- Výběr z více záznamů: `List` přes proměnnou stránky s `LookupMode(true)` + `RunModal` z karty čtečky → na telefonu **jedno klepnutí
  na dlaždici vybere** (bez náhledu), `GetRecord` vrátí řádek. Dlaždice bere fieldgroup `DropDown` (4.22) — `SystemCreatedAt` tam není.
- „Zpět až na úvodní stránku" ze druhé úrovně: první stránka otevře druhou `RunModal()` a po návratu se zavře, když druhá nastavila
  příznak (getter `ReturnsToStartPage()`); modální karta na telefonu nemá šipku zpět, kostka *Zpět* je nutná.

(2026-11-14, cust-sonnentor-bc PBI 65206, MKSON 28.0.181.3 na BC-TEST: zásilky ZAS26_00018 / 00019 proti ZAS26_00013 ze standardu.)
