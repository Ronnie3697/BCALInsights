---
name: bc-al
description: >-
  Povinný startup pro každou práci s AL / Microsoft Dynamics 365 Business Central
  (BC): psaní či úprava .al kódu, review, návrh řešení, build, testy, ticket k BC
  repu (cust-*-bc, prod-*-bc), app.json, tableextension / pageextension /
  codeunit, XLIFF, Essence pipeline. Načti jako PRVNÍ akci v AL/BC seanci — i
  když jde jen o otázku. Drží Router „typ úkolu → notes skill", startup
  checklist (al-mcp load, bc-code-intelligence Sam Coder), pravidlo triviální
  vs. netriviální úkol a pravidla údržby notes (doplnit + commit + push).
  Ručně: /bc-al.
user-invocable: true
---

# BC/AL startup — povinný kontext před AL prací

Poznámky z praxe žijí v tomhle repu (GitHub `essencebs/BCALInsights`, firemní;
klon může být kdekoli) jako soubory `bc-al-*.md`, každý **vedle svého
skill-wrapperu ve `skills/<název>/`** — podpůrný soubor skillu podle Agent Skills
spec, proto se na něj odkazuje jen jménem, relativně k adresáři skillu (žádné
absolutní cesty, žádné `../..` — přes junction jen na `skills/` by `..` nesedělo).
Kořen repa (README, `mcp-setup.md`, `check-skills.py`) najdeš přes
`git -C <adresář skillu> rev-parse --show-toplevel` (funguje i přes junction).
Tenhle skill je rozcestník — **jediné místo, kde žije Router.** Tentýž adresář `skills/` čtou Claude Code (plugin `bcal-insights`),
Copilot a Codex (junction `~/.agents/skills`) i Antigravity (junction
`~/.gemini/config/skills`); always-on soubory těch nástrojů (CLAUDE.md,
`bc-al-notes.instructions.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`) na
tenhle skill jen odkazují.

**Platí pro:** cokoliv kolem AL / Business Central. **Neplatí pro:** PowerShell
a jiné skripty, plánovací dokumenty, obecné dotazy, jiné jazyky — tam startup
přeskoč (zbytečná ceremonie, plýtvá kontextem). Nejsi si jistý → ber to jako
AL a jeď. Jazyk a tón komunikace se řídí always-on souborem uživatele (osobní
preference, ne součást notes).

## Postup — jako první akce, bez pobídnutí, paralelně v jednom bloku

0. **Merge masteru do aktuální větve** (jen pracovní repa `cust-*` / `prod-*`,
   ne notes repo): `git fetch origin` a `git merge origin/master` do větve, na
   které stojíš (na masteru `git pull --ff-only`). Konflikty **vyřeš sám** a
   oznam, které soubory a jak; merge commit je tady v pořádku. Když merge
   odmítne kvůli necommitnutým změnám v dotčených souborech, nestashuj —
   řekni to uživateli. Stejný krok opakuj **před každým `commitni` / `pushni`**
   (detail 7.7b v `bc-al-tools.md`); u `pushni` **nejdřív push, pak autotesty celého repa
   v lokálním kontejneru** (`<PRACOVNÍ-REPA>\bc-test-container\Test-Repo.ps1`; větev je online,
   i kdyby počítač odešel; fail = opravit dalším commitem + push) — jen kdo kontejner má
   (always-on `Lokální testovací kontejner: ano`; `… ne` = autotesty nikdy, ani se neptej).
   Uživatel na to nechce myslet.
1. **Router → notes.** Podle typu úkolu vyber řádky z tabulky níže a načti
   příslušné skilly (Claude Code: `Skill` tool; Copilot `/název`, Codex
   `$název`, Antigravity zmínkou jménem) **nebo rovnou soubory** — každý skill
   jen říká „přečti `<soubor>.md` z adresáře skillu celý" + TL;DR. Nevíš rozsah → načti všech
   čtrnáct hlavních `bc-al-*.md` (~100–750 řádků / ≤ 45 KB, každý se vejde do
   jednoho Read; kdyby se výstup přece ořízl, dočti přes `offset`).
   ⚠️ **Každý soubor dočti DO KONCE.** Když Read vrátí oříznutý výstup
   („showing lines X–Y of Z"), okamžitě navaž dalším Read s `offset`.
   Částečně přečtený soubor = nepřečtený soubor.
2. **Autotesty.** Načti `bc-al-autotests` (soubor `bc-al-autotests.md`), pokud
   úkol zahrnuje testy NEBO implementuješ netriviální funkčnost — autotesty jsou
   u netriviální funkčnosti **povinná součást úkolu** (u banalit typu přidání
   pole bez logiky ne). Zakládání / kompilace / běh test appky a CI faily →
   navíc `bc-al-autotests-infra`; testy projektů, dokladů, Job Queue, výroby,
   plánování, CZZ a CZB → navíc `bc-al-autotests-domains`.
3. **al-mcp-server studený start** (pokud je MCP v daném nástroji
   nakonfigurovaný; když chybí — v `claude mcp list` není — jednorázová
   instalace všech MCP serverů je v `mcp-setup.md` v kořeni notes repa —
   `git -C <adresář skillu> rev-parse --show-toplevel` — jinak ho nečti). Index je po startu seance prázdný →
   `al_packages` s `action: "load"` a `path` = **root repa** (sdílená
   `.alpackages`; cesta na podsložku appky selže). Detail 7.2 v `bc-al-tools.md`.
4. **bc-code-intelligence (Sam Coder)** — jen u netriviálních úkolů (viz níže)
   a jen tam, kde je ten MCP nakonfigurovaný (jinak krok přeskoč a řekni to):
   `set_workspace_info` s aktuálním workspace rootem, pak `ask_bc_expert`
   s `preferred_specialist: "sam-coder"`. Bez `set_workspace_info` vrací
   všechny jeho tooly „Server Not Yet Initialized".
5. **Oznam uživateli checklist** (✅ / ❌ u každého kroku): načtené notes
   (které), autotests ano/ne, al-mcp load, Sam Coder ano/ne/přeskočeno.
   Bez toho uživatel neví, že kontext máš. Když něco selhalo (chybí soubor,
   MCP not initialized, CONNECT_TIMEOUT), řekni to — nepředstírej úspěch.

Tohle má prioritu nad „buď stručný, šetři toolcally". Setup je levný, kontext
je drahý.

## Router — typ úkolu → skill / soubor

| Děláš… | Skill | Soubor (v adresáři skillu) |
|---|---|---|
| Konvence, naming, prefixy/affixy, Description/ToolTipy, formát page fieldů, permission sety, přidělování ID, přetěžování procedur, locale pasti (Format/Evaluate, Excel Buffer), výběr moderního patternu (namespaces, interfaces, SecretText, Cloud target) | `bc-al-style` | `bc-al-style.md` (sekce 1, 10) |
| Chování page/pageextension: RunModal a výběr na RoleCenter, ConfirmManagement default, factbox SubPageLink, CaptionClass cache, názvy controlů / expression pole, modify cizí pageextension, smyčka aktualizace v OnAfterGet*Record, Visible přes page proměnnou, MultiLine/RichContent/control add-in, page procedura se jménem metody `Rec` (AL0604), výběrový dialog v LookupMode (jen pro čtení), filtr partu nastavený z hostitelova `OnOpenPage`, nový řádek subformu s `DelayedInsert` (prázdné `SystemId` ve validacích → cache per řádek se neuloží), `CurrPage.Update(false)` v `OnValidate` pole bez `SaveRecord` (zahodí zadanou hodnotu), `ListPart` jako výběr přes `RunModal` (pod TestPage bez lookup módu), pole za cizí control na stránce bez `SourceTable` (`protected var` nebo veřejný getter + výraz v `SourceExpr`, bez eventů; stínění parametrů getteru), vlastní výběr v cizím modálním dialogu, který po OK zapisuje (getter + event před zápisem + manuálně bindovaná instance z pageextension), dlaždice listů na phone klientu (Brick / DropDown / prvních 5 controlů, výrazové pole na dlaždici, `addlast(Brick)`), popisek pole podle hodnoty na phone klientu (`CaptionClass = '3,' + výraz`) a `Visible` pole nastavené až po `OnOpenPage`, událost control add-inu (sken čtečky) ze stránky schované pod vrchní stránkou phone klientu se odloží a přehraje (`aria-hidden` test v JS), klepnutí na řádek phone klientu = náhled záznamu, karta z `CardPageId` v režimu zobrazení (množství na proměnné stránky), seznam dokladů → řádky → detail bez náhledu (karta hlavičky + ListPart s `CardPageId`; detail z partu dědí `SubPageView` filtr), chyba z `OnValidate` na telefonu jen červený křížek, `InstructionalText` jako placeholder, `\` ve zprávě phone klient nezalomí a neviditelné control add-iny uprostřed stránky dělají mezeru, `Rec` prázdného listu nese hodnoty filtrů z otevření, nevyplněné pole typu výčet ukazuje caption první hodnoty (např. „Nabídka" u `Sales Document Type` → `HideValue` podle čísla dokladu), kostka „moje doklady" na `SO Processor Activities` (`Sales Cue."User ID Filter"`), vlastní `OnDrillDown` standardní kostky přes `modify` a řazení drill-downů kostek, víc souborů ke stažení z jedné akce (víc `DownloadFromStream` = jen poslední soubor, ZIP přes `Data Compression`) | `bc-al-ui` | `bc-al-ui.md` (sekce 4) |
| FindSet/locking, Insert/Modify/Delete, TempBlob, SetLoadFields, SetFilter, TransferFields, Mark/Copy, FilterGroup (trvalý filtr vedle dočasných), SetView / TrySetView (neznámé pole bez chyby), TableRelation mimo PK, event subscribery (IsTemporary, SkipOnMissing…, identifier syntax, AL0432), tableextension triggery / klíče / modify() / xRec, `CurrFieldNo` z codeunity (getter v tableextension, kopie recordu = 0), příznak v SingleInstance po `Error` (`SystemRowVersion`), řazení podle pole mimo klíč (`SetCurrentKey(SystemCreatedAt)`, „od nejnovějšího"), `var` record z eventu nepřepisovat při hledání jiného záznamu (lokální proměnná), libovolné pole přes `RecordRef` jako text (kanonický tvar Option / Boolean / GUID přes dočasný záznam, zmizelé pole, `Field.Len` v nabídce) | `bc-al-data` | `bc-al-data.md` (sekce 2, 3.1–3.4, 3.7–3.11) |
| Vlastní pole na Sales/Purchase Header/Line a jejich cesta do archivu, účtovaných dokladů a kopií: stejné field ID na celé sadě tabulek, Sales Line → ILE / Whse. Shipment, total při částečném účtování a undo, AutoFormatExpression, `Validate("No.")` → `Init()` (archive restore, Copy Document, Recreate), Blob pole hlavičky (CalcFields + eventy Sales-Post / archiv / obnova / Quote → Order / Copy Document), kontrola dokladu před účtováním, Job No. dodávka vs. faktura, dvojí archivace nabídky / objednávky při odeslání emailem (tělo emailu z reportu bez `BindSubscription(Mail Management)`), zúčtovací datum přepsané na WorkDate cizím subscriberem při programovém účtování (Essence Distribution), platba / refundace zákazníka z kódu přes `Gen. Journal Line` (Confirm vlastního plátce → `SetHideValidation`), výstup a kapacita výroby účtované z kódu (deník výstupu: `Validate(Type)` maže `No.`, zmetky `Scrap Quantity` / `Scrap Code`, tiché atomické účtování přes manuální bind `Item Jnl.-Post.OnBeforeCode`, `Increment Batch Name`), *Kód způsobu platby* na dokladu, jehož platby účtuje integrace (přiřazením bez `Validate` — protiúčet způsobu platby by fakturu uhradil podruhé, Cash Desk CZP by založil pokladní doklad; CZL QR dotaz při vydání), vlastní podmínka schvalovacího workflow nákupního dokladu (pole hlavičky jako event condition — workflow čte doklad z DB, stav uložit v `Approvals Mgmt.OnBeforeIsPurchaseApprovalsWorkflowEnabled`, převzetí schválených hodnot v `OnBeforeReleasePurchaseDoc` se stavem Pending Approval) | `bc-al-posting` | `bc-al-posting.md` (sekce 3.5–3.6o) |
| No. Series, Upgrade Tag, All Profile, Unix timestamp, atributy zboží, DateFormula, CaptionClass/Translation Helper, CZ↔EN terminologie, Attached to Line No. / parent↔child řádky, VerifyOnInventory, Auto Format / částky v textu, Item Charge Assignment z kódu, Job Queue z účtování / recurring entry, Data Exchange Definition / import camt.053 (merge sloupců, Regex Match, ID polí 274), Retention Policy pro vlastní log tabulky (registrace přes `OnRefreshAllowedTables` bez install kódu, zamčené filtry „Never Delete“), skladový přesun / vyskladnění z kódu (`Validate("Bin Code")` na Take řádku bez kontrol při `CurrFieldNo = 0`, MJ obsahu přihrádky, registrace jednoho páru Take/Place filtrem `Line No.`, `Split Line` rozbije párování, detail se `SetRecFilter` zapíše jen Place), nový řádek deníku zboží z kódu v prázdném listu (`SetUpNewLine`, lokace před `Validate("Item No.")`), jiná MJ ve skladu bez řízeného zaskladnění (skladový deník registrovat v základní MJ, množství přepočítat do MJ řádku dokladu, MJ řádku neměnit), duplicita IČ/DIČ zákazníka a dodavatele (standard jen Message, tvrdý blok `OnBeforeValidateEvent`), vlastní pole řádku kusovníku → komponenta VZ (refresh `Calculate Prod. Order.OnAfterProdOrderCompInsert` vs. plánovací sešit `Planning Component` + `Carry Out Action.OnAfterTransferPlanningComp`, `CopyFromPlanningComp` bez `TransferFields`) | `bc-al-objects` | `bc-al-objects.md` (sekce 5) |
| CZZ zálohy (Advance Payments Localization for Czech): vazba záloha ↔ doklad (`Advance Letter Application CZZ`, `Order No.` hlavičky jen zrcadlo), odpojení v dialogu Advance Letter Appl. Edit a scoped guard (`EventSubscriberInstance = Manual` + `BindSubscription`), generovaný řádek zálohy z reportu *Create Sales Adv. Letter CZZ* (`OnCreateAdvanceLetterLineOnBeforeInsert`, `Description` Text[100]), platba zálohy a účto skupina zákazníka / dodavatele (výběr zálohy v deníku skupinu nemění, účet záloh z *Advance Letter G/L Account* přes `Use Advance G/L Account CZZ`, `PostAdvancePayment` = vyrovnání + položka zálohy → `OnPostAdvancePaymentOnBeforePostAdvancePayment`, odpojení vrací platbu balance řádkem → `OnPostAdvancePaymentUnlinkingOnBeforePostPaymentApplication` + `Applies-to ID`, *Allow Multiple Posting Groups*, přímé přiřazení `Posting Group`) | `bc-al-advance-cz` | `bc-al-advance-cz.md` (sekce 5.z3, 5.z5, 5.z7) |
| Hromadné objednávky HNO/HPO (vazba řádků NO/PO/sešitu přes `Blanket Order No./Line No.`, převzetí ceny a slevy, ruční navázání = vnořený `Validate(Quantity)`, změna varianty navázaného řádku, Recreate lines = `TestField` vazby před přegenerováním, změny z hlavičky jen ze stránky — `CurrFieldNo` / `GuiAllowed`, *Link Doc. Date To Posting Date* při účtování), Requisition Line (`OnAfterGetDirectCost`, Req. Wksh.-Make Order / Carry Out — dvojí započtení, `CopyOrderDateFromPurchHeader` na kopii, Calculate Plan bez dotazů přes manual bind), přepočet ceny z Množství bez ceníku (`IsPriceUpdateNeeded`, ruční sleva změnu Množství nepřežije), poptávka → Requisition Line → Purchase Line a přenos vlastních polí (i EM MRP Replenishment OREBS *Suggest Replenishment* — vlastní Insert řádku sešitu) | `bc-al-blanket` | `bc-al-blanket.md` (sekce 5.x5, 5.x9, 5.x21) |
| Item Tracking — šarže / sériová čísla: stránka Item Tracking Lines (6510) a její eventy (ruční řádek `OnBeforeOnInsertRecord` / `OnBeforeOnModifyRecord`, Assign Serial No. / Create Customized SN `OnAfterAssignNewTrackingNo`), předvyplnění šarže (šarže = číslo projektu, SN zboží bez automatického řádku, zadání SN šarži maže), vlastní výběr šarže z akce na 6510, Reservation Entry (337) vs Tracking Specification (336), source pole u Prod. Order Line, tracking na Sales Quote (Prospect vs Surplus, `IsOrderNetworkEntity`), tracking na fakturačním řádku z Get Shipment Lines, TestPage handlery Enter Quantity to Create / Enter Customized SN, FEFO z kódu a prošlé šarže při Strict Expiration Posting, vlastní insert Reservation Entry (`Entry No.` je AutoIncrement → `:= 0`, nikdy `FindLast + 1`), prodej šarže do mínusu vs. *Lot Specific Tracking* (Text018), dobropis / storno s `Appl.-from Item Entry` z kódu (SQNR se mění až při účtování, účtování slučuje šarže), převodka se sledováním: `Order No.` na Item Journal Line nevyprázdnit / nepřepsat (chyba New Expiration Date, in-transit párování), tracking filtry `SetTrackingFilterFrom…` v base jen SN + Lot (Package přes event), `Item Tracking Setup` temp (AA0073), hromadný výběr SN akcí v *Vybrat položky* (Item Tracking Summary 6500, `MaxQuantity` přes `OnSelectMultipleTrackingNoOnBeforeSetSources`, `addfirst(Processing)` na stránce bez akcí), import SN z Excelu na nákupní objednávku / skladovou příjemku (tracking příjemky na řádku NO, `Whse. Outstanding Qty. (Base)`), přejmenování Warranty Date (tableextension `modify` Caption) a Package No. (`Inventory Setup."Package Caption"`), zápis / odebrání SN na řádku dokladu z kódu standardní cestou (`Item Tracking Lines.RegisterItemTrackingLines` s delty, `SetBlockCommit`, seznam problémů přes temp `Error Message`), fyzická inventura se šaržemi (`Exp. Invt. Order Tracking` v lokaci s přihrádkami bez skladového sledování nevzniká a dokončení objednávky ho nečte, `InsertLine` = holý `Insert()`, `Order Line No.` v `Phys. Invt. Rec.-Finish.OnAfterCode`, dělení řádků záznamu podle šarží a přebytek, Essence Warehouse `Expected Quantity (Base) EBS`) | `bc-al-tracking` | `bc-al-tracking.md` (sekce 5.x, 5.x2, 5.x2b, 5.x15, 5.x17–5.x26) |
| Projekty — Job Planning Line (účto skupina do deníku projektů, Location Code z Job/Job Task jen pro nové řádky, vazba budget↔billable `Purch. Job Cont.Entry No.IMEBS`, dimenze řádku plánování do Job Journal Line — `UpdateDimensions` až po `OnAfterCreateDim`, Usage Link, TSEBS placeholder), návazné doklady projektu (`Job Planning Line Invoice`, `Job No. EPEBS`, nákupní objednávka / příjemka), mazání / přegenerování plánovacích řádků a guardy `OnDelete`, undo nákupní příjemky s projektem (`ReapplyJobConsumption`, Skip Purchase Consumption IMEBS), spotřeba projektu z prodejní dodávky per šarže / SN / položka příjmu (`CreateJobLedgerEntryFromSalesLine` z `OnAfterInsertShipmentLine` podle položek zboží dodávky; `Qty. to Handle (Base)` trackingu řádku není dodávané množství), nákupní dobropis / vratka dodavateli u Skip projektu (`OnPostItemJnlLineJobConsumption` běží i pro vratky, kontrola spotřebovaného množství per tracking, Posting Preview položky projektu zobrazuje), prodejní dobropis = vratka od zákazníka (Získat účtované řádky pro stornování u nákupu job pole kopíruje, u prodeje maže → `OnCopySalesDocLineOnBeforeCopySalesJobFields`; storno spotřeby z `OnAfterReturnRcptLineInsert` per položka vratky, záporná Usage přes `Job Link Usage`; dodáno = kontrakt mínus vratky; JPLI Posted Credit Memo −Qty; `InitFromJobPlanningLine` kopíruje vlastní pole), spotřeba projektu z deníku zboží (list „Spotřeba projektů" IMEBS: `Item Jnl.-Check Line.OnAfterCheckItemJnlLine` + `Item Jnl.-Post Line.OnAfterPostItemJnlLine`, Výdej = Usage +, Příjem = Usage −, `Item Journal Line."Job No."` bez OnValidate / TableRelation, nový rozpočtový řádek místo `MatchUsageUnspecified`, W1 místo CZ šablony pohybu zásob), kontrola množství z řádků plánování / přespotřeba navázaného řádku (standard `Job Link Usage` + `Job Planning Line.Use` zvedá `Quantity` sám a `Validate(Quantity)` z kódu přeceňuje; hooky `OnHandleMatchUsageSpecifiedJobPlanningLineOnBeforeUpdateQuantity` + `OnBeforeUpdateRemainingQuantityFromUse`, setup Never / Confirm / Always / Keep Original, Σ nákupu / prodeje při `OnBeforeReleasePurchaseDoc` / `OnBeforeReleaseSalesDoc`, `Sales Line.TestJobPlanningLine` blokuje změnu množství z UI) | `bc-al-projects` | `bc-al-projects.md` (sekce 5.x17–5.x28) |
| Shopify Connector (varianty, sync vs Add Item, sync zásob a nulová zásoba přes `OnAfterCalculationStock`, cena varianty přes dočasnou nabídku (`OnBeforeCalculateUnitPrice`), vazba Shopify objednávka ↔ prodejní doklad a dělení řádků, eventy, userErrors, Internal komunikační vrstva → vlastní HttpClient + custom app, BC 29: expirující tokeny, GraphQL resource soubory, test mocking), HttpClient na SaaS, Isolated Storage, SecretText, OAuth/secrets na Cloud targetu, Cloud-only gotchas, notifikace do Power Automate / Business Events, vlastní API page pro zápis (POST validace polí, temporary API s filtry, relace přes víc volání), Dataverse/CDS sync (Integration Table Mapping filtry a směry, CRM proxy tabulky, Option Picklist + OptionOrdinalValues, reset vlastního mapování vs. ruční Man. Integration Table Mapping, testy bez Dataverse), Jira / Tempo (user lookup e-mailem, worklog bez issue key → parent / projekt z Jiry, mock HTTP eventem), Dotykačka / Dotypos API (stav skladu `stockQuantityStatus`, skrytí produktu `display`, ceny s DPH `priceWithVat`, mapování ceník → hladina, EANy zúžené eventem filtru odkazů na zboží, volba v administraci ↔ pole API — `discountPermitted` obráceně, `stockOverdraft`, poznámka `note` na účtence) | `bc-al-integrations` | `bc-al-integrations.md` (5.y2–5.y4, sekce 11) |
| Dokumentace requirementů (`docs/*.md`), uživatelská příručka featury (HTML se screenshoty v `docs/`), co číst před editem (app.json, .alpackages), Word layouty (MCP `bc-word-layout` + skilly `al-word-layout*` (12.1i), repeater `w15:dataBinding`), RDLC tablix sloupce skriptem (12.1g), analyzery AA/CA/PTE/LC, XML doc komentáře, build diagnostika, ruleset, Claude in Chrome pasti (timeout screenshotu → nová záložka, souřadnice z DOM iframu, inline chyba pole, role/jazyk přes Moje nastavení) | `bc-al-workflow` | `bc-al-workflow.md` (sekce 8, 9, 12) |
| Překlady / XLIFF: NAB AL Tools (`Refresh XLIFF`, prefixy `[NAB: …]`, jeden `<target>`, hromadný překlad skriptem, BC CZ konvence), trans-unit ID (hash FNV-1a, ruční doplnění unitů, doplnění z `.g.xlf` skriptem, rename / přesun labelu mění ID, víc extensionů na stejný objekt — LC0091 false positive), změna textu přeloženého labelu s `%n` (update `<source>` i `<target>`), duplicitní trans-unity po merge (AL0479), výpis diakritiky z `.xlf` přes Bash, `.cs-CZ.xlf` změněný pod rukama NAB Refreshem | `bc-al-xliff` | `bc-al-xliff.md` (sekce 6) |
| Kompilace z CLI (alc, analyzery, UTF-16 logy, dočasná package cache, BOM-aware ID), Bash/heredoc pasti Claude Code, symboly (.alpackages, al-mcp), AL Object ID Ninja (ručně založená ID do backendu), BC source na GitHubu, AL-Go, nová appka v repu (GUID, idRanges, affixy, permission sety), source závislé appky, git/commit/PR pravidla, texty do ADO (popis PR, zadání / AC PBI a Tasků, komentáře) jako Markdown blok bez zalamování, verzování app.json, Azure DevOps MCP/PAT, case-only rename | `bc-al-tools` | `bc-al-tools.md` (sekce 7.1–7.10) |
| NuGet dependencies a minima (MajorMinor/LatestMatching, dedupe per GUID), symboly test frameworku z MSSymbols feedu (lokalizační appky s `.cz.` infixem od BC 28), kolize object ID po merge, major version bump, Essence build faily (testy, squash merge, Subcontracting ≥ 28.3, BC_ARTIFACT, Compile AL Apps bez `##[error]` / PTE0012), Deploy Staging sync mode/ForceSync/obsolete, změna typu pole u appky v ostrém provozu bez ztráty dat (nová pole + obsolete + `DataTransfer` upgrade), smíchané verze MS symbolů, release deploy SaaS (altool .NET 10, 409 Conflict = souběžný deploy), ruční nasazení PTE z NuGetu přes Automation API (AVS0109 = dev build téže appky), závislosti z NuGetu jako Dev appky do sdíleného kontejneru `containers.essencebs.com` (dev endpoint, Basic auth, okno na přihlášení), lokální testovací kontejner (Docker + BcContainerHelper bez admina, testy před merge), dev publish do SaaS sandboxu přes `altool` (osiřelá data staré verze, duplicate package ID, `ForceSync`, EM závislosti z dependency-cache) | `bc-al-build` | `bc-al-build.md` (sekce 7.11–7.26) |
| Cokoliv kolem automatizovaných testů (povinnost, kanonický vzor, libraries, handlery, Setup Storage, TestPage vs Rec.Validate, `asserterror` rollback, modální Worksheet bez Cancel, seed `Library - Random`, obecné gotchas) — a implementace netriviální funkčnosti, report s request page v testu po zápisech (`Commit` před `RunModal`) | `bc-al-autotests` | `bc-al-autotests.md` (+ příloha `bc-al-autotests-saas-fallback.md` jen pro SaaS-only) |
| Test appka jako projekt: `app.json` a explicitní závislosti (BC 28: `Assert` a `Library - *` v `Application Test Library` → AL0185 bez AL1022), `internalsVisibleTo` hlavní appky (PTE0012, AL0161), test app bez permissionsetu, struktura a název souborů, test ruleset (`al.ruleSetPath` folder-level), symboly test frameworku (MSSymbols 28.4 sada vč. Any a BF Test Libraries), lokální kompilace test appky (sibling `.alpackages`, temp cache, jedna minor řada MS knihoven, `#IF TESTS`, alc z BcContainerHelper `alLanguageExtension`), spouštění testů z CLI / Dockeru / AL Test Runneru, čtení chyb spadlých testů z CI | `bc-al-autotests-infra` | `bc-al-autotests-infra.md` (spolu s `bc-al-autotests`, když testy i píšeš) |
| Testy konkrétních oblastí BC: projekty (Job Status / zákazník / default dimenze = Confirm, `UseJobPlanningLine` účtuje, Copy Document maže Job No.), prodejní a nákupní doklady (částečné účtování vydá doklad, `TestStatusOpen` na nové instanci, undo dodávky, Quote → Order, jen záporný řádek), Job Queue (`Library - Job Queue`, `CanCreateTask` v CI), výroba (Low-Level Code, cyklický BOM), cust-soitron-bc konvence, plánování / sešit požadavků (Calculate Plan, Carry Out vlastní batch), nákupní zálohy CZZ s platbou, párování bankovních plateb `Match Bank Payment CZB` | `bc-al-autotests-domains` | `bc-al-autotests-domains.md` (spolu s `bc-al-autotests`) |
| Essence Configurator (prod-ess-configurator-bc, COEBS; rozšíření COALU/COZLK) — jádro: systémové parametry (QUANTITY, UNIT_PRICE, CNC X1/X/Y/Z) a tiché nuly, číselné vzorce (Action Formula Line, PK bez Field Type) i textové vzorce (konkatenace + řádek Formula s vloženým výrazem), Zrušit editorů vzorců (`WasCancelled` / `EditFormula`), strom podmínek parametru (zastaralé `Root Condition No.`, kořen ze struktury 66845, report 63140 *Config. Data Repair*, `OnAfterRepairConfiguration`), nerecyklovaná čísla parametrů a odkazy na parametr (`Param. Reference Mgt.`, `OnCollectParameterReferences`), *Číslo z parametru* na řádku akce prodejního řádku (67541), diagnostika přes service stránky, konfigurační balíček (RapidStart) pro přenos definic mezi prostředími (`Skip Table Triggers` vs. `Validate Field`, co do balíčku nepatří) | `ess-configurator` | `ess-configurator-notes.md` (C1–C4, C6, C12, C15, C17, C18) |
| Essence Configurator — varianty: identita varianty (find-or-create, `FindExistingVariantWithSameValues`), dialog konfigurace 63143 / ListPart 63147 (OK chce všechny parametry, `RefreshAfterExternalValueChange`, výrobní akce u varianty mimo dialog), rozdělení řádku a sleva, kontrola hodnoty Table Lookup a filter groups, API konfigurace varianty (66387) a `Variant Config. Engine COEBS`, `Effective Hidden` persistovaný, find-or-create `local` v dialogu 63143 (bývalé 5.x10 / 5.x12), *Kopírovat hodnotu z* mezi typy (převod polyká chyby) a filtr Vyhledání hodnotou jiného parametru (`GetConditionTableFilter`, `FilterPageBuilder` nejde rozšířit) | `ess-configurator-variants` | `ess-configurator-variants.md` (C5, C11, C13, C14, C16) |
| Essence Configurator — napojení zákaznických rozšíření COALU / COZLK: kusovník konfigurované varianty (`Alternative Prod. BOM ATEBS`, `Price Variant Code PMALU`) a pořizovací / jednotková cena řádku, pole EM Cutting Plan na kusovníku a komponentě VZ (model V2 od 28.0.10, dřívější pořadí validace, slučování přes `Length`, plocha), MJ podřízeného řádku přepsaná Pricing Matrix přes Parametr A/B (osy jako Code[50] od PMEBS 67458), eventy kopie konfigurace pro zákaznická data (řádky SL akcí, `OnAfterCopySLActionLine`) | `ess-configurator-extensions` | `ess-configurator-extensions.md` (C7–C10) |
| Oficiální BC MCP server (`mcp.businesscentral.dynamics.com`): konfigurace v BC (page 8350/8351, Dynamic Tool Mode), Entra app registrace vs. device login, Claude Code `--mcp-config` + `headersHelper` | — (draft, bez skill-wrapperu) | `bc-al-mcp-server.md` v adresáři skillu `bc-al` |
| Nejsi si jistý rozsahem | všech 14 hlavních `bc-al-*` | `bc-al-style/ui/data/posting/objects/advance-cz/blanket/projects/tracking/integrations/workflow/xliff/tools/build.md` |

Číslování sekcí (1–12) je napříč soubory původní, ať fungují odkazy „viz X.Y".
Archiv monolitu `bc-al-notes.archived-2026-06-23.md` — **needituj, jen reference.**

## Sam Coder mode vs. notes — kdy co

- **Triviální AL úkol** (skeleton objektu, jednoduchý Insert/Modify, drobná
  oprava, přejmenování, Description/ToolTip, snippet podle známého patternu)
  → přeskoč Sam Coder checklist (`set_workspace_info` / `ask_bc_expert` /
  `workflow_list`), jeď podle notes. al-mcp load (krok 3) klidně udělej,
  je levný.
- **Netriviální AL úkol** (návrh nové featury, větší refactor, integrace,
  performance, nový business flow přes víc objektů, nejasný requirement)
  → projeď Sam Coder checklist, načti workspace knowledge layers, zvaž
  `workflow_start`. MCP může nabídnout patterny, které notes nepokrývají.
- Nejistota triviální/netriviální → ber jako netriviální (pět vteřin overhead
  je levnější než přehlédnutý workflow).

## Pravidla hry

- **Notes jsou závazné** pro daný projekt (FindSet/ReadIsolation, explicitní
  Insert/Modify/Delete, IsTemporary v subscriberech, ToolTipy uživatelsky, EN
  identifikátory…). Nehraj si na vlastní styl. Rozpor mezi notes a tvou
  expertizou → **upozorni uživatele** a navrhni úpravu notes; nepřepisuj
  pravidla potichu.
- **Jazyk kódu a UI textů:** vždy anglicky (1.1 v `bc-al-style.md`); čeština
  jen do XLIFF. **Jazyk komunikace:** podle always-on souboru uživatele.
- **Git v pracovních repech:** commit / push / PR **nikdy sám** (7.7 v
  `bc-al-tools.md`). Na startu seance a před každým vyžádaným commitem/pushem
  **mergni `origin/master`** a vyřeš konflikty (7.7b); **po každém vyžádaném pushi pusť autotesty
  v lokálním kontejneru** — jen v rámci push (nejdřív push, pak testy), ne po každé změně, a jen kdo
  kontejner v setupu přijal (7.7b, 7.23 v `bc-al-build.md`). Verzi `app.json`
  nepovyšuj (7.8). ADO PAT je read-only záměrně — 401 na zápis neobcházet (7.9).
- **Nový poznatek → zapiš.** Když během práce zjistíš něco užitečného pro
  BC/AL, doplň to do příslušného `bc-al-*.md` (nebo to nabídni) a **rovnou
  commitni + pushni** v notes repu — jeho kořen je
  `git -C <adresář skillu> rev-parse --show-toplevel` (přes junction funguje) —
  krátká zpráva co + odkud (repo/PR/build/datum). Notes repo je **výjimka**
  z pravidla 7.7. **Každá** změna tady (notes, skilly, README) jde do **všech**
  remotů, které `git remote` vypíše (typicky jen `origin` =
  `essencebs/BCALInsights`; kdo má navíc vlastní fork, pushne i tam —
  `for r in $(git remote); do git push $r master; done`), ať se repa nerozejdou.
  Po doplnění `wc -l`: soubor **> 1000 řádků → rozděl** (vyčleň ucelené sekce do nového
  `bc-al-*.md`, zachovej číslování, mechanicky přes sed/skript, ne přepisem),
  aktualizuj Router tady, `README.md` a přidej nový skill-wrapper do `skills/<název>/`
  (notes soubor leží vedle jeho `SKILL.md`)
  (vzory: 7.11–7.19 → `bc-al-build.md` 2026-09-01; sekce 4 → `bc-al-ui.md`
  a 5.y2 + 11 → `bc-al-integrations.md` 2026-09-08; sekce 6 → `bc-al-xliff.md` 2026-10-22; C5/C11/C13/C14/C16 → `ess-configurator-variants.md` a C7–C10 → `ess-configurator-extensions.md` 2026-11-04). Always-on soubory ostatních
  nástrojů Router nedrží, jen odkazují sem — ty netřeba měnit; jen seznam skillů
  v `~/.claude/CLAUDE.md`, pokud ho tam uživatel drží. Důvod: soubory přes ~750 řádků / ~50 KB
  se nevejdou do jednoho readu (limit je ~25k tokenů ≈ 50 KB, ne řádky).
- **TL;DR ve skillech needituj kvůli novým gotchas** — tam patří jen stabilní
  pravidla; poznatky jdou do `bc-al-*.md`. Skill TL;DR uprav, jen když se
  mění pravidlo samo (a bumpni `version` v `.claude-plugin/plugin.json`).
- **Nové téma v notes = nové klíčové slovo ve skillu.** Když poznatek otevírá
  novou sekci / nový objekt / nový nástroj (ne jen další odstavec k existující
  sekci), doplň ho i do `description` příslušného skillu (to je trigger, podle
  kterého si agent skill načte — bez klíčového slova se nenačte) a do Routeru
  tady. `description` má limit **1024 znaků** → `python check-skills.py`
  v kořeni repa hlídá délky; při přetečení zhusti, nemaž. Klidně to dělej
  hromadně (audit 2026-09-07 dohnal 30 commitů notes najednou).
- **Fallback bez skillů:** přečti přímo `skills/bc-al/SKILL.md` (tenhle soubor)
  v klonu notes repa — cestu ke klonu má uživatel v always-on souboru — a notes
  ve `skills/<název>/<název>.md`. Ostatní nástroje:
  Copilot `~/.agents/skills` + `.instructions.md` (applyTo `*.al`), Codex
  `~/.agents/skills` + `~/.codex/AGENTS.md`, Antigravity `~/.gemini/config/skills`
  + `~/.gemini/GEMINI.md` — všechno junctiony na `skills/` v tomhle repu.
