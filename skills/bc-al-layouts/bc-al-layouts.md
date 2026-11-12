# BC/AL poznámky — Layouty reportů (Word, RDLC, štítky)

> Vyčleněno 2026-11-12 z `bc-al-workflow.md` (soubor přesáhl 1000 řádků). Původní číslování (12.1f–12.1i, 12.5) zůstalo
> kvůli odkazům „viz 12.x"; zbytek sekce 12 (build, analyzery, ruleset, runtime errory) je dál v `bc-al-workflow.md`.
> Načítej, když řešíš: Word layout reportu (ručně i přes MCP `bc-word-layout`), RDLC layout reportu nebo reportextension,
> štítky s čárovými kódy (barcode fonty, GS1-128).

Obsahuje:
- **12.1f** Word layout: opakovací sekce potřebuje `w15:dataBinding`
- **12.1g** RDLC tablix (Excel export): přidání sloupců skriptem místo Report Builderu
- **12.1h** RDLC layout reportextension: `alc` při kompilaci přegeneruje `<DataSets>` podle symbolů
- **12.1i** Word layouty přes MCP `bc-word-layout` + skilly `al-word-layout*`, ne ručním OOXML
- **12.5** Word layout štítků generovaný skriptem + barcode fonty / GS1-128 (BC online)

---

### 12.1f Word layout: opakovací sekce potřebuje `w15:dataBinding`

U ručně generovaného DOCX musí `w:sdtPr` s `w15:repeatingSection` obsahovat
**`w15:dataBinding`**, namespace `http://schemas.microsoft.com/office/word/2012/wordml`.
Běžná textová pole dál používají **`w:dataBinding`**; atributy `xpath`,
`prefixMappings` a `storeItemID` zůstávají v namespace `w` v obou případech.

**Build + platné XPath + Word `XMLMapping.IsMapped = true` nestačí.** Word chybný
zápis s `w:dataBinding` u repeateru načte, ale při `SaveAs2` jej přepíše na
`w15:dataBinding`. Při diagnostice porovnej pracovní kopii uloženou Wordem,
neměň naslepo AL dataset. Regresní kontrola musí ověřit namespace vazby,
nejen existenci uzlu nebo počet tabulek. Finální tisk ověř v BC.

(2026-09-17, test-mnecSkoleni-bc, report 99103: po ručním přidání vnějšího
repeateru uživatel hlásil zmizení obou tabulek. Rozdíl potvrzen Word SaveAs2;
opraveny dvě vazby, regresní test selhal před opravou a prošel po ní i po buildu.
Runtime potvrzení opravy v BC v době zápisu ještě chybí.)

### 12.1g RDLC tablix (Excel export): přidání sloupců skriptem místo Report Builderu

Velký RDLC layout (1,3 MB, 58 sloupců × 12 řádků, `ExportSalesQuote.Report.rdl` v cust-jiri-bc) se dá rozšířit o nové
sloupce PowerShell skriptem nad `System.Xml.XmlDocument` (`PreserveWhitespace = $true`, uložit přes `XmlWriter` s
`UTF8Encoding($true)` + `NewLineHandling None`, ať zůstane BOM i CRLF). Co o struktuře platí (ověřeno 2026-10-22):

- **Jeden `<TablixColumn>` = jeden `<TablixMember>` v `TablixColumnHierarchy` = jedna `<TablixCell>` v KAŽDÉM
  `<TablixRow>`.** Buňky překryté `<ColSpan>` předchozí buňky **v řádku zůstávají** jako prázdné `<TablixCell />` —
  `grep -c '<TablixCell>'` je proto nepočítá a svádí k domněnce, že spanované buňky chybí. Počítej elementy XPathem.
- Nový sloupec za sloupcem X: `TablixColumn` (šířka) + `TablixMember` (tady patří `<Visibility><Hidden>=Fields!Flag.Value
  = "False"</Hidden>`, stejně jako u existujících přepínačů request page) + do každého řádku buňka za buňkou X. Když X
  leží **uvnitř spanu** (hlavička skupiny „Jednotková cena" `ColSpan=4`), zvedni `ColSpan` vlastníka o 1 a vlož prázdnou
  `<TablixCell />`; jinak klonuj sousední buňku (detail: buňku s podobným stylem, přejmenuj `Textbox Name` +
  `rd:DefaultName` + `<Value>=Fields!Col.Value`; hlavička: `=Fields!Lbl.Value`; horní řádky firmy: klon s prázdnou
  hodnotou). Názvy textboxů musí být unikátní v celém RDL (suffix `_R<řádek>`).
- Skrytí starých sloupců při zapnutém přepínači = `Hidden` s `= "True"` na jejich `TablixMember`; Excel renderer skryté
  sloupce vynechá úplně.
- `<DataSets>` doplň o nové `Field` ručně (+ `XFormat` k Decimal sloupcům) — alc to při kompilaci stejně dopíše a
  přeformátuje (7.1 v `bc-al-tools.md`), takže po kompilaci porovnej a nech verzi z alc.
- Kontrola po skriptu: počet sloupců = členů hierarchie = buněk v každém řádku (u řádku se spany navíc součet spanů),
  žádné duplicitní `Textbox Name`, soubor začíná BOM a má stejný počet CR jako LF. Pak zkompilovat.
- PowerShell pasti: `"Row $r: …"` ve stringu je `$r:` = drive-qualified proměnná → ParserError, piš `${r}`; `[xml]`
  cast přes `New-Object System.Xml.XmlDocument` + `.Load()` je nutný kvůli `PreserveWhitespace`.
- Výhoda proti Report Builderu: diff je čitelný, změna je reprodukovatelná na identickém layoutu v sesterském repu
  (CZ i W1 kopie byly binárně shodné → skript jednou, soubor zkopírovat).

### 12.1h RDLC layout reportextension: `alc` při kompilaci přegeneruje `<DataSets>` podle symbolů — CI s jinou verzí vendora vyrobí rozbitý layout

**Symptom:** tisk padá na *„Rendering output for the report failed … The Value expression for the text box 'Textbox62'
refers to the field 'Prepaymen_Vat_Date'. Report item expressions can only refer to fields within the current dataset
scope…"* — jen u layoutu z `rendering { layout(...) }` našeho reportextension. Built-in layout vendora funguje
a **tentýž rdlc z repa nahraný jako uživatelský layout funguje taky**; export layoutu rozšíření ze serveru se od repa liší
jen v `<DataSets>` (pole chybí / přibyla). Nová verze appky ani změna bajtů rdlc nepomůže. (cust-smartwings-bc PL Core,
*ITI Sales - Invoice PSW* na PL Test, 2026-11-03.)

**Mechanismus (ověřeno experimentem i logem CI):**
- **`alc` při kompilaci přepíše `<DataSets>` RDLC layoutu reportextension** (stejně jako u `report`, 7.1 v `bc-al-tools.md`)
  podle datasetu base reportu **ze symbolů v package cache** + sloupců rozšíření: chybějící `Field` doplní, neexistující
  smaže, výrazy v textboxech nechá. Přepíše **i zdrojový soubor v `src/`** (sonda: bogus `Field` zmizel, odebraný se vrátil,
  307 → 290 polí; alc 17.0.2273547). Když symboly odpovídají layoutu, soubor zůstane bajt po bajtu stejný — proto lokální
  build „nic nemění" a vypadá to, že alc layout nesahá.
- Export z *Report Layouts* je přesně obsah `.app`; server nic nepřegenerovává. Uživatelský layout (nahraný soubor) nikdo
  nepřepisuje, a pole definované v RDL, které v datech není, se tiskne prázdné bez chyby — proto „ITI layout funguje"
  nic neříká o datasetu.
- **CI (Essence v2-0, Download Dependencies from NuGet)** stáhlo pro `Polish Localization 10.8.0.0` verzi 10.8.3.3, ale
  tranzitivní závislost **Electronic Banking Extension PL 7.6.0.1** (SuggestPayments.PL) přitáhla do `.dependencies`
  i **Polish Localization 10.16.0.5** (+ Electronic Banking Base App 6.0.2.6). V package cache leží obě verze, alc bere
  nejvyšší → Core PL se kompiluje proti 10.16, kde ITI sloupec `Prepaymen_Vat_Date` (dataitem `PreviousPrepmt`) zrušilo
  a nahradilo `Prepayment_NSeI_No` (+ labely `NSeIDocumentNoLbl`, `Prepayment_NSeI_Document_NoLbl`). Na serveru je ITI
  10.13.0.5, které sloupec má → build z CI padá, lokální build (symboly 10.13) by fungoval.

**Diagnostický postup:**
1. Layout z `.app`: 40 B hlavička `NAVX` + ZIP (`grep -obUa -F $'PK\x03\x04'` s `LC_ALL=C`, `tail -c +N`, `unzip`;
   nebo PowerShell `ZipArchive`), sha256 proti repu; export ze serveru → `diff` po `tr -d '\r'`, `comm` nad `<Field Name=…>`.
2. Log kroku *Download Dependencies from NuGet*: řádky `requesting '[x,y)'` a `Copying … to .dependencies` — hledej
   **dvě verze téže appky**; `Compile AL Apps` ukáže `AL Compiler version` (CI 16.4 ≠ lokální 17/18).
3. Který sloupec v které verzi vendora existuje: NuGet `.app` bývá šifrovaný (`NAVX.NEA`, bez ZIP, al-mcp ho nenačte) →
   **sonda kompilací** `add(<dataitem>) { column(<jméno>; 1) { } }` proti symbolům: `AL0155 … already defined … by the
   extension 'X (verze)'` = existuje, neznámé jméno projde. Sonda přes label je neprůkazná (vendor nechá proměnnou, změní
   sloupec; `AL0161` = existuje/protected, `AL0118` = neexistuje). Datasety jiných verzí jsou vidět v layoutech jiných
   zákaznických rep v ADO (`search_code` na jméno sloupce; cust-trafinOil-bc `app_pl` = ITI 10.16).
4. MCP `pipelines_artifact download` vrací prázdný soubor — artefakt stáhni ručně z ADO, nebo zkompiluj lokálně
   se stejnými symboly.

**Oprava:** (a) layout nesmí referencovat sloupec, který v jedné z verzí vendora chybí → vlastní column v reportextension
(`add(PreviousPrepmt) { column(PrepaymentVatDatePSW; …) }` z vlastního temp `Sales Line` naplněného veřejnou
`ITI Sales Prepayment Mgt.CollectPrevPrepmts`, signatura v 10.13 ověřena) a textbox na něj; (b) nebo sjednotit verzi
vendora v CI s nasazenou (pin závislosti, která tahá novější verzi; `.dependencies` nesmí obsahovat dvě verze) — křehké,
každý další bump to rozbije. Po (a) se přegenerovaný `<DataSets>` liší jen o pole, na která layout neukazuje = neškodné.

### 12.1i Word layouty editovat přes MCP `bc-word-layout` + skilly `al-word-layout*`, ne ručním OOXML

Od 2026-11-04 je v Claude Code (scope user) MCP server **`bc-word-layout`**
([TKapitan/bc-word-layout-mcp](https://github.com/TKapitan/bc-word-layout-mcp), instalace a proč ne
`dnx` / marketplace plugin → `mcp-setup.md` krok 1b) a čtyři uživatelské skilly v `~/.claude/skills/`:
`al-word-layout` (workflow inspect → edit → validate → preview + přesný tool surface),
`al-word-layout-design` (jak má nový layout vypadat), `al-word-layout-from-design` (hotový Word návrh
→ vázaný layout), `al-word-layout-composite` (tělo + hlavička/patička + téma `.dotx`).

- **Pořadí:** u Word layoutu nejdřív načti `al-word-layout` (a `-design` u nového layoutu) a jeď přes
  tooly (`get_layout_info`, `list_dataset_fields`, `insert_field` / `insert_label` / `insert_repeater_table`
  / `wrap_in_repeater`, `validate_layout`, `preview_layout`). Každý zápis server validuje a chybný edit
  odmítne — proto přes tooly a ne přes vlastní skript nad `document.xml`. Dataset bere z `.al` reportu
  + `app.json` vedle layoutu (BC verze).
- **Co server neumí → ruční OOXML podle 12.1f / 12.5 zůstává:** hide-if-empty / hide-if-zero, repeater
  v hlavičce či patičce, komentáře layoutu, svislé merge, okraje / page setup, RDL a Excel layouty,
  XLF překlady, upload do tenantu. Štítky s barcode fonty (12.5) tedy dál skriptem.
- **Preview je offline aproximace** (PDF přes Word COM, když je Word nainstalovaný). Finální kontrola
  = tisk v BC sandboxu; validace serveru je ověřená na BC 28, jiné verze neověřené.
- Když tool chybí v nabídce, server nestartoval (`CONNECT_TIMEOUT`, 7.2 v `bc-al-tools.md`) → restart
  seance / `/mcp` reconnect; `claude mcp list` musí ukázat `bc-word-layout … Connected`.

### 12.5 Word layout štítků generovaný skriptem + barcode fonty / GS1-128 (BC online)

Štítky 100×100 / 100×50 mm s EAN a GS1-128 pro Sonnentor (PBI 65662, 2026-10-02) — Word layout
psaný skriptem (node generuje `document.xml` + customXml, PowerShell zipuje), bez Wordu. Co platí:

- **Namespace vazeb:** `urn:microsoft-dynamics-nav/reports/<Token>/<ID>/`, kde `<Token>` = název
  reportu, v němž **každá skupina ne-alfanumerických znaků = jedno `_`** (`"Prod.Order Commercial Lbl. SON"`
  → `Prod_Order_Commercial_Lbl_SON`; `". "` je jedno `_`, ne dvě). **Token i ID ber z `.al` souboru
  skriptem**, ne z hlavy — report přečíslovaný kolegou (54804 → 54807) = kompilátor part nahradí vlastním
  `item2.xml` a štítek se vytiskne **prázdný bez chyby** (2026-10-08). Kontrola po kompilaci: když `alc`
  nechal tvůj `customXml/item1.xml` + `itemProps1.xml`, vazby sedí; když tam je jen jeho `item2.xml`
  (UTF-16), nesedí namespace. Element dataitemu = **jméno dataitemu** (`ProductionOrder`, ne tabulka),
  vnořený dataitem = vnořený element (`/ns0:ProductionOrder[1]/ns0:LabelCopy`).
- **Struktura jako MS layouty** (ověřeno proti `Standard Sales - Invoice` a `Item GTIN Label` z Base App
  `.app`, složka `layout/…/*.docx`; původní verze s repeaterem i pro hlavní dataitem a aliasy = názvy sloupců
  se vykreslila prázdná): hlavní dataitem s `WordMergeDataItem` se **neobaluje** repeating section — renderer
  dělá dokument per záznam sám; repeater (`w15:dataBinding` + `w15:repeatingSection`, alias
  `#Nav: /ProductionOrder/LabelCopy`) jen pro vnořený dataitem; **každý** content control má alias
  `#Nav: /<cesta dataitemů>/<sloupec>`, tag `#Nav: <Token>/<ID>` a `w:dataBinding` s absolutním xpath
  `/ns0:NavWordReportXmlPart[1]/ns0:ProductionOrder[1]/ns0:LabelCopy[1]/ns0:ItemNo[1]`. Obrázek =
  `w:picture` control se stejným aliasem (`…/CompanyPicture`). Soubor vazeb v `.rels` piš absolutně
  (`/customXml/item1.xml`), relativní `../customXml/item1.xml` vedlo k nahrazení partu.
- **Zip musí mít v názvech položek lomítka.** PS 5.1 `[IO.Compression.ZipFile]::CreateFromDirectory`
  píše `customXml\item1.xml` (backslash) → Word/alc balíček nemusí přijmout. Zipuj přes `ZipArchive`
  + `CreateEntry(rel.Replace('\','/'))`, `[Content_Types].xml` první.
- **Jeden štítek na stránku bez zalomení:** vnější tabulka 1×1 s `w:trHeight w:hRule="exact"` o výšce
  těla stránky minus ~40 twips + `w:cantSplit`; za tabulkou povinný prázdný odstavec s `w:line="20"
  w:lineRule="exact"`, aby nevyrobil prázdnou stranu. Kopie = vnořený `Integer` dataitem (`LabelCopy`,
  `SetRange(Number, 1, NoOfCopies)`) a **všechny sloupce na vnitřním dataitemu** — vazba uvnitř
  vnitřního repeateru na sloupce vnějšího není jistá.
- **Obrázek (logo):** `w:picture` content control s `w:dataBinding` na Blob sloupec
  (`column(CompanyPicture; CompanyInformation.Picture)` po `CalcFields`) + placeholder PNG v
  `word/media` a `r:embed`; vzor `DisposalProtocol.Report.docx` (header).
  ⚠️ **„The image stream does not contain valid image or bitmap data" (CZ „Datový proud obrazu neobsahuje platná data
  pro obraz nebo bitmapu") = platformní hláška, renderer dostal bajty, které nejsou obrázek.** Než podezíráš JPEG nebo
  typ sloupce, zkontroluj, **odkud obrázek bereš**: u zákazníků s **Essence Document Attachments W1/CZ** (ABEBS, SharePoint
  služba zapnutá v *Doc. Attachment Service*) jde každá příloha do SharePointu a do Media `"Document Reference ID"` appka
  uloží **jen text s Drive Item ID** (`OutStream.WriteText(DriveItemId)` + `ImportStream`). `HasContent()` je true, `File Type`
  = Image, ale `GetAsTempBlob` vrátí ten text → Word i RDLC spadnou na téhle hlášce. Logo firmy (`Company Information.Picture`)
  přílohou nejde, proto tiskne. Poznáš to podle `"Sharepoint File ABEBS"` / vyplněného *Folder Name* na detailu přílohy.
  Řešení: stáhnout obsah přes `Online Drive API ABEBS.DownloadFile(GetAccessToken('AZUREAD'), OnlineDriveItem."Site ID",
  "Drive Id", Id, InStream)` (záznam `Online Drive Item ABEBS` podle `"Drive Item ID ABEBS"`) — ideálně v produktové appce
  subscriberem na `Document Attachment.OnBeforeGetAsTempBlob` (Base App má i `OnBeforeHasContent`, `OnBeforeExportToStream`),
  jinak v zákaznické appce se závislostí na W1. Base64 `Text` vs. Blob sloupec rozdíl nedělal (obě varianty padly stejně;
  Blob = vzor Base App, nech ho). (2026-10-16/19, cust-sonnentor-bc 65436 Product Information, BC-TEST.)
- **Barcode fonty BC online** (MS Learn `devenv-report-barcode-fonts`, IDAutomation): Code 128 =
  `IDAutomationC128XS/S/M/L/XL/XXL`, UPC/EAN = `IDAutomationUPCEANXXS/XS/S/M/L`. **Přípona = výška čar,
  šířku kódu řídí jen velikost písma** (XS není „úzký“ — ověřeno 2026-10-09: GS1-128 s 38 symboly při 11 pt
  ≈ 103 mm, tj. X ≈ 0,25 mm; při 8 pt ≈ 75 mm). Chceš-li úzký a zároveň vysoký kód, dej malé písmo a vyšší
  variantu (`C128M` 8 pt). Text pro font: `Barcode Font Provider` (`Enum::"Barcode Font
  Provider"::IDAutomation1D`, `ValidateInput` + `EncodeFont(Text, Enum::"Barcode Symbology"::"EAN-13")`).
- **GS1-128 přes System App NEJDE:** `IDA 1D Code128 Encoder` volá DotNet `FontEncoder.Code128(Text)`
  bez `ApplyTilde` → FNC1 (`~202`) ani závorková metoda IDAutomation se neuplatní. Vlastní encoder
  (vzor `GS1 Barcode Mgt. SON`, cust-sonnentor-bc): hodnoty Code 128 (subset C pro páry číslic, B jinak,
  `FNC1 = 102`, `Start C = 105`, `Code B = 100`, `Code C = 99`, `Stop = 106`), checksum
  `(start + Σ i·v_i) mod 103`, mapování na IDAutomation font: 0 → chr 194 (mezera), 1–94 → chr(v+32),
  95–106 → chr(v+100) (FNC1 = Ê 202, Start C = Í 205, Stop = Î 206). GS1: FNC1 za startem a za každým
  prvkem proměnné délky (AI 10, 30), AI 02 = GTIN-14 (EAN zleva nulami), AI 15 = `<Year,2><Month,2><Day,2>`.
  Ručně ověřitelné vektory do testu: `FNC1 0201` → check 8, `FNC1 10AB` → check 5.
- **Kontrolní číslici EAN font dopočítá sám** — `IDAutomationUPCEAN*` vytiskl `…22561`, zatímco Item Reference
  držel `…22560`; čárový kód a tištěný text se rozešly bez chyby. Před tiskem ověř GS1 mod 10 (váhy 3,1,3,1…
  zprava, `(10 − Σ mod 10) mod 10`) a špatný EAN zastav chybou s očekávanou číslicí (`ValidateEANCheckDigit`).
  Testovací EANy musí mít platnou kontrolní číslici (`8591234567893`, `18591234567890`, `12345670`).
- **Rozměry na štítku 100×50 mm:** EAN-13 ve fontu M při 13 pt ≈ 40 mm → ve sloupci 31 mm se zalomí (zbytek
  čar na dalším řádku) a vytlačí zbytek obsahu za `hRule="exact"` výšku (GS1 řádek zmizí). EAN 10 pt + sloupec
  ≥ 37 mm, GS1-128 `C128S`/`C128M` 8 pt (~75 mm pro 38 symbolů), Arial 7–11 pt. Přetečený čárový kód poznáš
  podle „zbytku čar“ na dalším řádku pod kódem.
- **Prázdný prvek GS1 je neplatný** — AI (10) bez šarže vytiskne `(10)(30)…`, což čtečka odmítne. Prvky bez
  hodnoty vynechej (lot, množství 0, datum 0D) a FNC1 oddělovač dávej jen za prvek proměnné délky, po kterém
  ještě něco následuje.
- **Název objektu max 30 znaků** (`Prod. Order Transport Label SON` = 31 → `Prod.Order …`), AA0215 pak
  chce soubor podle zkráceného názvu (`ProdOrderCommercialLbl.Report.al`).
- `Library - Item Tracking.CreateProdOrderItemTracking` je od 27.0 deprecated (AL0432) → stejná signatura
  v `Library - Manufacturing`.
