# BC/AL poznámky — Dataverse (CDS) synchronizace

> Vyčleněno z `bc-al-integrations.md` 2026-11-24 (soubor přesáhl 1000 řádků). Číslování 11.8 je původní, ať fungují odkazy
> „viz 11.8"; ostatní sekce 11 (HttpClient, SecretText, Power Automate, API page, Jira, Dotykačka, Email) a Shopify (5.y2–5.y4)
> zůstávají v `bc-al-integrations.md`.
> Načítej, když řešíš: Dataverse / CDS sync (Integration Table Mapping, filtry obou stran, směry, field mappingy, konfigurační
> šablony, CRM proxy tabulky, Option → Choice, lookupy, reset výchozího nastavení a vlastní mapování, Man. Integration Table
> Mapping), obousměrné objednávky / faktury / ceníky do Dataverse, úlohy synchronizace ve frontě (Ready / On Hold po zapnutí),
> testy bez Dataverse (`@@test@@`).

Obsahuje:
- **11.8** Dataverse sync — filtry, Enum → Choice, testy, recreate vlastních mapování, lookup na nesynchronizovaný číselník
- **11.8c** Prodejní objednávky, faktury, ceníky, stav úhrady, Synch. Only Coupled Records (dřív body za 11.11)
- **11.8d** Zapnutí synchronizace a úlohy fronty, vyřazená mapování, filtr kontaktů podle obchodního vztahu, měna zákazníka
  a příležitosti

## 11. SaaS gotchas — Dataverse (jen 11.8; zbytek sekce 11 v `bc-al-integrations.md`)

### 11.8 Dataverse (CDS) sync — filtr integrační tabulky platí jen Dataverse → BC, Enum → Choice přes `OptionOrdinalValues`, testy bez Dataverse

Z cust-sonnentor-bc task 66405 (appka SON CDS Sync, BC 28.4, 2026-09-29; zdroje w1-28 `Integration/SynchEngine/
IntegrationRecordSynch.Codeunit.al`, `IntegrationTableMapping.Table.al`, `Integration/Dataverse/CRMIntegrationTableSynch.Codeunit.al`,
`CDSSetupDefaults.Codeunit.al`, `Integration/D365Sales/CRMAccount.Table.al`):

- **Integration Table Filter mapování se uplatní jen ve směru Dataverse → BC.** `CRM Integration Table Synch.` ho aplikuje při čtení
  CRM záznamů (`SplitIntegrationTableFilter` + `SetView`); ve směru BC → Dataverse se spárovaný CRM záznam dohledává
  `Integration Table Mapping.GetRecordRef(ID)` **bez filtru** (jen `SetFilter` na UID pole). Filtr typu „jen schválené účty"
  (`CRMAccount.SetRange(ebs_vendorapproved, true)`) tedy brání založení / aktualizaci v BC, ale spárovaný záznam se z BC do
  Dataverse aktualizuje dál; vypadnutí z filtru není smazání (Deletion-Conflict se netýká). Filtr skládej typovaně:
  `SetRange` → `GetView()` → `FilterPageBuilder.SetView/GetView(Caption, false)` → `SetIntegrationTableFilter` (vzor
  `CDSManagementSON.UpdateVendorIntegrationTableMapping`), nikdy ručně psaný text s čísly polí.
- **Standardní mapování VENDOR má BC filtr `Blocked = ' '`** (`CDS Setup Defaults.ResetVendorAccountMapping`) → blokovaní
  dodavatelé se do Dataverse neposílají vůbec. Když má Dataverse stav Blocked vidět, filtr zruš `IntegrationTableMapping.SetTableFilter('')`.
- **Enum / Option pole BC → Dataverse Choice (Picklist):** na CDS proxy tabulce (`TableType = CDS`, tableextension na `CRM Account`
  funguje stejně) pole `Option` s `ExternalType = 'Picklist'`, `OptionMembers` **ve stejném pořadí jako BC enum** a
  `OptionOrdinalValues = -1, 1, 2` (index → hodnota Choice v Dataverse, `-1` = null pro prázdnou; vzor base `CRM Account`.AccountCategoryCode).
  `Integration Record Synch.TransferFieldData` u shodných typů (enum se přes `FieldRef.Type` hlásí jako Option) přiřadí hodnotu přímo
  (`FieldRef.Value := Variant`) — přenáší se **index**, ne caption; caption-matching (`TextToOptionValue` přes OptionCaption /
  OptionMembers) nastupuje jen u rozdílných typů a u constant value. Hodnoty Choice v Dataverse proto musí sedět na
  `OptionOrdinalValues` (ne výchozí `100000000+`). Enum `Vendor Blocked` má `AssignmentCompatibility = true`. Přenos indexu
  ověřuje test `VendorBlockedValueIsTransferredToDataverseOption` (k datu zápisu jen lokální kompilace, CI běh ještě ne).
  **Proč ne Enum:** `Enum` pole s `ExternalType = 'Picklist'` se na CDS tabulce zkompiluje, ale `OptionOrdinalValues` na něm
  alc 17.0 odmítne (`AL0171: The property value '-1, 1, 2' on property 'OptionOrdinalValues' is not valid` — i pro `0, 1, 2`),
  takže nejde vyjádřit prázdná ↔ `null` ani jiné než ordinální hodnoty Choice; MS proxy tabulky i AL Table Proxy Generator
  používají výhradně Option (idea „Replace Option Fields in Tables of Table Type=CRM/CDS" je u MS ve stavu New). Hodnotu `-1`
  pro prázdnou bere generátor i base `CRM Account` (`AccountCategoryCode`), hodnoty ostatních členů musí sedět na Choice v Dataverse.
- **Field mapping jedním směrem uvnitř Bidirectional tabulkového mapování** je normální (`Direction::ToIntegrationTable` na
  řádku, vzor `No. → ebs_bcnumber`). `Integration Field Mapping.CreateRecord` vždy vkládá nový řádek (PK AutoIncrement) —
  duplicity při opakovaném „Default Synchronization Setup" řeší až `Integration Table Mapping.CreateRecord` (`Get → Delete(true)`
  smaže i field mappingy); vlastní mapování zakládej stejně — vždy recreate, viz bullet o ručním mapování níže.
- **Testy bez Dataverse:** `RegisterTableConnection(TableConnectionType::CRM, 'TEST', '@@test@@')` + `SetDefaultTableConnection`
  (platformové test připojení, používá MS `Library - Mock CRM Connection`) → CRM proxy tabulky jedou z lokální DB, i `FilterPageBuilder`
  nad nimi. Filtr mapování ověř `TempCRMAccount.SetView(IntegrationTableMapping.GetIntegrationTableFilter())` + `SetRange(AccountId)`
  + `IsEmpty`; přenos hodnot přímo enginem: `Temp Integration Field Mapping` (No., Source/Destination Field No.) →
  `IntegrationRecordSynch.SetFieldMapping(Temp)`, `SetParameters(SourceRecRef, DestRecRef, false)`, `Run()`, `DestRecRef.SetTable(TempCRMAccount)`.
  Tělo subscriberu na `OnAfterResetVendorAccountMapping` vyčleň do `internal procedure` (app má `internalsVisibleTo` na test app) —
  lokální `IntegrationEvent` publisher standardu z testu nevyvoláš a `CDS Setup Defaults.ResetVendorAccountMapping` táhne job queue.
  Reset konfiguračních šablon hlásí chybějící `Config. Template Header` přes `Message` → v testu šablony založ (helper
  `EnsureConfigTemplatesExist`), nebo `MessageHandler`.
  Test připojení registruj v `Initialize()` **každého** testu, který se CRM proxy tabulky jen dotkne — padá už
  `IntegrationTableMapping.CreateRecord(..., Database::"CRM Account", ...)` bez jediného čtení záznamu („Table connection for table
  type CRM must be registered using RegisterTableConnection" — cust-soitron-bc build 28646, `Tax Reg. No. Sync Test CCSOI`, 2026-10-05).
  ⚠️ **`CRM Integration Management` je SingleInstance a `IsCRMIntegrationEnabled()` si výsledek cachuje na celou session**
  (`CRMIntegrationEnabledState`, w1-28 `Integration/Dataverse/CRMIntegrationManagement.Codeunit.al`). Test, který zapíná
  `CRM Connection Setup."Is Enabled"` přes `Insert(false)` / `Modify(false)` (triggery `ClearState` nevolají), proto po
  **každém** zapnutí zavolá `CRMIntegrationManagement.ClearState()`. Bez toho: jakmile dřívější test téhož běhu (i v jiném
  codeunitu — runner jede po ID) otevře Customer / Vendor / Item / Job Card s `IsIntegrationEnabled()` v `OnOpenPage`,
  cache drží „Not Enabled" a vlastní validace padá *„The Dataverse integration is not enabled…"*, ačkoli setup už enabled je.
  Lokálně ani na masteru to nevyskočí — projeví se až přidáním testu s TestPage karty do codeunitu s nižším ID
  (cust-soitron-bc build 28826, 11 testů `CRM Business Unit Test SOI` + `Business Unit Assign. Test SOI` po přidání
  `CustomerCardShowsCreatedVendorNo` do 54430, 2026-10-13). `IsCDSIntegrationEnabled()` se necachuje.
- **Vlastní mapování při „Default Synchronization Setup" vždy založ znovu (`Integration Table Mapping.CreateRecord` =
  `Get → Delete(true)` + Insert), ne „když existuje, přeskoč".** Na stejný event `CDS Setup Defaults.OnAfterResetConfiguration`
  je subscribnutý i standardní `Manual Int. Mapping Events` (BaseApp `Integration/SynchEngine/ManualIntMappingEvents.Codeunit.al`):
  pro každý záznam **Man. Integration Table Mapping** (5380, stránka Manual Integration Table Mappings) založí `Integration Table
  Mapping` téhož jména, **pokud ještě neexistuje**, a přidá jen ruční řádky `Man. Int. Field Mapping`. Pořadí subscriberů není
  zaručené → když standard běží první, vlastní kód s guardem `if not Get then CreateRecord` mapování přeskočí a v něm zůstane
  jediné ruční pole (cust-sonnentor-bc TEST: SHIPTOADDRESS jen s Contact ↔ ebs_contacttxt — i po smazání mapování a novém
  resetu, ruční záznam přežívá, `Integration Table Mapping.OnDelete` ho nemaže; DEV bez ručního záznamu fungoval). Fix: recreate
  + smazat `Man. Integration Table Mapping` téhož jména (`Delete(true)` uklidí i jeho field mappingy), ať kódem řízené mapování
  vyhraje v obou pořadích; dedupe řádků polí pak není potřeba. Standard dělá totéž (`CDS Setup Defaults.InsertIntegrationTableMapping`
  volá `CreateRecord` bez guardu). Test: existující mapování s jedním řádkem + ruční záznam → po resetu plná sada přesně 1× a ruční
  záznam pryč (`Ship-to Sync Setup Test SON`; ruční záznam v testu `Init` + přímé přiřazení + `Insert(true)`, `CreateRecord` je internal).
  (2026-10-14, cust-sonnentor-bc, SON CDS Sync.)

- **Lookup (Code → GUID) na Dataverse tabulku, která se NEsynchronizuje (číselník udržovaný ručně v PA) = NE řádek field
  mappingu, ale `Integration Rec. Synch. Invoke.OnAfterTransferRecordFields`.** Standard (`CRM Int. Table. Subscriber.
  OnTransferFieldData` → `CRM Synch. Helper.AreFieldsRelatedToMappedTables`, w1-28 `Integration/D365Sales/`) u mapovaného
  páru polí, kde mají obě strany `TableRelation` a cíl je Guid, **vyžaduje `Integration Table Mapping` mezi oběma
  tabulkami, jinak `Error` „Table X must be mapped to table Y to transfer value between fields…“** — a protože pořadí
  subscriberů téhož eventu není zaručené, vlastní subscriber na `OnTransferFieldData` s `IsValueFound` to neobejde (ověřeno
  v DEV: řádek synchronizace spadl přesně na tuhle hlášku). Bez `TableRelation` na cílovém poli zase platforma nezná
  cílovou entitu lookupu. Funkční vzor: CRM proxy tabulka číselníku (`TableType = CRM`, `ExternalName` entity, PK + sloupec
  s kódem — u ručně založené PA tabulky bývá jen primární `ebs_name`, žádný `ebs_code` — sekundární klíč na ten sloupec,
  **bez mapování**), pole na `CRM Account` jako `Guid` + `ExternalType = 'Lookup'` + `TableRelation` na proxy, **žádný
  řádek field mappingu** a subscriber `OnAfterTransferRecordFields(SourceRecordRef, var DestinationRecordRef, var
  AdditionalFieldsWereModified, DestinationIsInserted)` (hook Base App pro doplňková pole, stejný používá standard): guard
  na zdroj Customer / cíl CRM Account, GUID dohledat podle kódu, zapsat `FieldRef.Value(...)` jen při změně a nastavit
  `AdditionalFieldsWereModified := true` (jinak engine Modify neudělá). Prázdný kód / bez shody = prázdný GUID, záznam
  nepadá. Test: `internal` procedura nad `RecordRef` temp Customer / temp CRM Account +
  `RegisterTableConnection(... '@@test@@')`, proxy záznam číselníku `Insert(false)` jde do lokální DB.
  ⚠️ **`statecode` na vlastní proxy tabulce jako `Option " ",Active,Inactive` s `OptionOrdinalValues = -1, 0, 1`** (vzor
  Picklist) shodil celý synchronizační job na *Object reference not set to an instance of an object* (job bez Finish
  Date/Time, fronta úloh opakuje 10×); po odstranění pole hned čitelná AL chyba. V cust-jps-bc mají starší proxy tabulky
  přesně tenhle blok zakomentovaný. Generátor (altpgen) dává `OptionMembers = Active,Inactive; InitValue = Active` bez
  ordinálů — když stav potřebuješ, drž generovanou podobu. Textový sloupec místo lookupu není zkratka: do lookup atributu
  string neprojde (*Unable to cast object of type 'System.String' to type 'Microsoft.Xrm.Sdk.EntityReference'*) a lookup
  sloupec v Dataverse nejde přetypovat. **Nová custom tabulka v Dataverse = přidat `Read` (Organization) aplikačnímu
  uživateli BC** (*Business Central Integration*, ApplicationId `88c57617-…`, type=8 Non-interactive) v jeho security roli,
  jinak dotaz z proxy skončí *Principal user … is missing prvRead<entity> privilege*; v BC je celý text jen v poli *Error
  Message* (2048) tabulky *Integration Synch. Job Errors*, pole *Message* (250) i seznam ho uříznou. **Výsledek u JPS:** po
  třech kolech (lookup → text → lookup) zákazník v PA lookup zrušil a založil textový sloupec `ebs_vatbusinesspostinggroup`;
  v BC zbylo pole `Text[20]` + `ExternalType = 'String'` a jeden řádek field mappingu, bez proxy tabulky a bez kódu. Než
  stavíš lookup na nesynchronizovaný číselník, zeptej se, jestli PA relaci opravdu potřebuje — text je o tři objekty, jeden
  subscriber, testy a oprávnění v Dataverse levnější. (2026-10-19/21,
  cust-jps-bc DEV, Customer `VAT Bus. Posting Group` →
  `CRM Account.ebs_vatbusinesspostinggroupid`, `CDSManagementJPS`.)

### 11.8c Prodejní objednávky, faktury, ceníky, stav úhrady, Synch. Only Coupled Records (dřív body za 11.11 v `bc-al-integrations.md`)

- **Obousměrná synchronizace prodejních objednávek (SALESORDER-ORDER / SOLINE-ORDERDETAIL): „při kolizi vyhrává BC“ =
  `Update-Conflict Resolution := "Send Update to Integration"` v subscriberu na `CRM Setup Defaults.
  OnResetBidirectionalSalesOrderMappingOnAfterInsertFieldsMapping` / `…SalesOrderLineMappingOnAfterInsertFieldsMapping`**
  (w1-28 `Integration/D365Sales/CRMSetupDefaults.Codeunit.al`; obyčejné `[IntegrationEvent(false, false)]`, z Cloud appky jdou
  odebírat, i když `ResetBidirectionalSalesOrderMapping` sama má `[Scope('OnPrem')]`). Standard nechává u hlavičky update
  i deletion konflikt `None` (= záznam změněný na obou stranách skončí chybou synchronizace), u řádku jen
  `Deletion-Conflict = Remove Coupling`; směr nech `Bidirectional`, aby šly obě větve. Eventy pálí z `ResetSalesOrderMappingConfiguration`
  (zapnutí *Bidirectional Sales Order Int. Enabled* na CRM Connection Setup) i z „Use Default Synchronization Setup“ — **existující
  mapování se nezmění**, dokud se setup znovu neresetuje nebo se pole nepřepíše ručně na Integration Table Mappings. Guard na dvojici
  tabulek (`Sales Header`/`CRM Salesorder`, `Sales Line`/`CRM Salesorderdetail`), testy s `RegisterTableConnection('@@test@@')`
  + `Integration Table Mapping.CreateRecord` nad proxy tabulkami bez Dataverse. (cust-soitron-bc CDS.W1
  `CDS Management CWSOI.SetSalesOrderMappingToPreferBCOnUpdateConflict`, 2RING DEV, 2026-10-22.)
- **Objednávka z Power Apps má v BC dostat číslo Power Apps (`ordernumber`) a název objednávky (`name`) do vlastního pole.**
  Standard SALESORDER-ORDER (w1-28 `ResetBidirectionalSalesOrderMapping`) mapuje `"Your Reference" ← OrderNumber`
  (FromIntegrationTable) a `"No." → BusinessCentralOrderNumber` (ToIntegrationTable; po insertu v BC ho dopíše i
  `CRM Int. Table. Subscriber.SetOrderNumberAndDocOccurenceNumber`), `Name` nemapuje vůbec — BC → PA ho plní
  `SetCRMOrderName` v `OnBeforeInsertRecord` jménem zákazníka. **Field mapping `"No." ← OrderNumber` nedávej:** na už
  spárované objednávce (založené v BC, číslo z řady ≠ `ordernumber`) by engine měnil PK při `Modify`. Správně subscriber
  `Integration Rec. Synch. Invoke.OnBeforeInsertRecord(IntegrationTableMapping, SourceRecordRef, var DestinationRecordRef,
  var InsertWithSystemId)` s guardem CRM Salesorder → Sales Header: `DestinationRecordRef.SetTable(SalesHeader)` →
  `"No." := OrderNumber` → `GetTable` (vzor standardu `UpdateSalesOrderQuoteNo`). `Sales Header.OnInsert` (`InitInsert`) sáhne
  na číselnou řadu jen při prázdném `"No."` (`NoSeries.TestManual` je až v OnValidate), řádky si hlavičku dohledají přes
  spárování (`AddDocumentNoToSalesOrderLine`), engine spáruje přes `SystemId`. `OrderNumber` je Text[100] → při délce > 20
  radši `Error` (padá jen ten záznam, hláška je v Integration Synch. Job Errors) než tiché `CopyStr`. Název: field mapping
  `<vlastní Text[100]> ← Name` FromIntegrationTable stačí — delší text engine zkrátí sám (`Integration Record
  Synch.TransferFieldData` → `Outlook Synch. Type Conv.EvaluateTextToFieldRef`, `PadStr` na délku pole; zdroj w1-28
  `CRM/Outlook/OutlookSynchTypeConv.Codeunit.al`, ne `SynchEngine/`). Testy bez Dataverse: neinsertované recordy přes
  `RecordRef.GetTable` + volání `internal` procedury, zkrácení přes engine jako v 11.8 (`Temp Integration Field Mapping`).
  (cust-soitron-bc CDS.W1 `CDS Sync Logic CWSOI.SetSalesOrderNoFromPowerApps`, `CDS Management CWSOI.AddOrderNameFieldMapping`,
  2RING DEV, 2026-10-29.)
- **Víc konfiguračních šablon na jednom mapování (sloupec *Table Config Templates* na Integration Table Mappings) =
  tabulka `Table Config Template` (5325; pro Dataverse stranu `Int. Table Config Template` 5326), ne pole
  `Table Config Template Code` mapování.** Engine (`Integration Rec. Synch. Invoke.FindTableConfigTemplate`, w1-28) čte
  záznamy mapování (`Parent Name`, jinak `Name`) podle `Priority` vzestupně, uložený *Integration Table Filter* aplikuje
  `SetView` na RecordRef integrační tabulky + `SetRange` na UID pole (`AccountId`) a první neprázdný výsledek dá kód;
  prázdný filtr vyhrává hned, bez shody se šablona nepoužije (žádný fallback na pole mapování). Chybějící `Config.
  Template Header` = `SynchAction::Fail` daného záznamu; pole `Table Config Template Code` šablony **nemá OnValidate**,
  takže přímé přiřazení existenci hlavičky nekontroluje. `Integration Table Mapping.OnDelete` šablony mapování maže
  (pokud není ruční `Man. Integration Table Mapping` téhož jména) → při „Use Default Synchronization Setup“
  (`CreateRecord` = Get → Delete) zmizí a musí se v subscriberu `OnAfterReset…Mapping` založit znovu: `DeleteAll` podle
  jména mapování + `Init`, `Table ID` / `Integration Table ID` z mapování, `Priority` 1..n, filtr přes
  `SetIntegrationTableFilter(GetTableFilterFromView(...))` (stejný `FilterPageBuilder` round-trip jako u filtru
  mapování; `GetView` z typovaného `CRMAccount.SetFilter`), `Insert(false)` (`No.` AutoIncrement). Priority nastav
  explicitně — všechny 0 = nedefinované pořadí. Test bez Dataverse: temp `CRM Account` s `AccountId` + stejná smyčka
  SetCurrentKey(Priority) / SetView / SetRange / IsEmpty nad šablonami. Vzor: cust-soitron-bc CDS.W1
  `CDS Management CWSOI.ResetCustomerConfigTemplates` (CUST_DOM SK / CUST_EU / CUST_EXP podle `ebs_countrycode`;
  task 67287, 2026-10-22).
- **Produkt na řádku účtované faktury (POSTEDSALESLINE-INV) není field mapping, řeší ho kód — a tiše spadne na write-in.**
  Mapování `Sales Invoice Line` → `CRM Invoicedetail` má jen Quantity / slevu / cenu / částky (`CRM Setup Defaults.
  ResetSalesInvoiceLineInvoiceMapping`). `ProductId` dosadí `CRM Int. Table. Subscriber.UpdateCRMInvoiceDetailsBeforeInsertRecord`
  → `InitializeCRMInvoiceLineWithProductDetails` → `FindCRMProductId`, a jen jednou při založení řádku (řádky faktury se posílají
  synchronně z `UpdateCRMInvoiceAfterInsertRecord` hlavičky; modify cesta přepočítává jen částky, produkt už nikdy). Prázdný
  GUID = řádek jako **write-in product** (`IsProductOverridden = true`, `ProductDescription = 'No. Description.'`), bez chyby:
  (a) `Type` není Item ani Resource (G/L účet, poplatek, komentář), (b) `Sales & Receivables Setup."Write-in Product No."` =
  číslo řádku, (c) zboží nespárované a **mimo BC filtr ITEM-PRODUCT** (standard `Blocked = false`), (d) žádné mapování
  Item ↔ CRM Product (`FindMapping`). Nespárované zboží **uvnitř** filtru se naopak spáruje za běhu (`SynchRecordIfMappingExists`)
  nebo shodí celou fakturu chybou. Řádek objednávky (SOLINE-ORDERDETAIL) má oproti tomu field mapping `No. → ProductId` přes
  spárování při každé synchronizaci, proto tam produkt je a na faktuře ne. Dodatečné spárování zboží existující řádky faktury
  v Dataverse nespraví — vazbu faktury zrušit a poslat znovu. (w1-28, cust-soitron-bc 2RING DEV, 2026-10-23.)
- **Účtovaná faktura (POSTEDSALESINV-INV) kontroluje *Relationship Type* účtu, i když obousměrná synchronizace objednávek
  ne.** `CRM Int. Table. Subscriber.UpdateCRMInvoiceBeforeInsertRecord` najde objednávku Power Apps podle `"Your Reference"`
  (= `ordernumber`) a volá `CRM Sales Order to Sales Order.GetCoupledCustomer` → `GetCRMAccountOfCRMSalesOrder`, která
  při `CustomerTypeCode <> Customer` hodí *„The sales order cannot be created. The selected type of the <název účtu>
  Dataverse account is not customer.“* (název účtu je v hlášce na místě %2, i když zní jako typ). Mapování SALESORDER-ORDER
  přenáší zákazníka field mappingem a typ nehlídá, takže objednávka se synchronizuje a padá až faktura po účtování.
  Když integrace Relationship Type nepoužívá: subscriber `OnBeforeGetCRMAccountOfCRMSalesOrder(CRMSalesorder, var CRMAccount,
  var Result, var IsHandled)` pro `CustomerIdType = account` → `Result := CRMAccount.Get(CustomerId)`, `IsHandled := true`
  (kontakt nech standardu). Jinak opravit data: nastavit účtu v Power Apps *Relationship Type = Customer*. (cust-soitron-bc
  CDS.W1 `CDS Sync Logic CWSOI.GetAccountOfPowerAppsOrder`, 2RING, 2026-11-02.)
- **Vlastní lookup na Account (`ebs_contractedcustomerid`) ↔ `Bill-to Customer No.` objednávky = obyčejný řádek field
  mappingu jako standardní `Sell-to Customer No.` ↔ `CustomerId` (Bidirectional, Validate Field), ale prázdný lookup
  z Power Apps shodí objednávku.** Pole na tableextension `CRM Salesorder` potřebuje `TableRelation = "CRM Account".AccountId`
  (podle ní `CRM Synch. Helper.AreFieldsRelatedToMappedTables` najde mapování CUSTOMER a GUID ↔ číslo přeloží přes spárování).
  Pasti (w1-28 `Integration/SynchEngine/IntegrationRecordSynch.Codeunit.al`, `D365Sales/CRMIntTableSubscriber.Codeunit.al`):
  - `FindNewValueForCoupledRecordPK` ve směru FromIntegrationTable vrátí pro prázdný GUID **`NewValue := ''` (Text)** a
    `Validate("Bill-to Customer No.", '')` na objednávce padá (`GetCust('')` → „The Customer does not exist"). **`Not Null`
    na field mappingu tu nepomůže:** engine (`TransferFieldData`, `SkipNullGUID`) přeskakuje jen hodnotu, kterou subscriber
    vrátil **jako Guid**; Text `''` projde. Řešení = vlastní subscriber `Integration Record Synch.OnTransferFieldData`, který
    pro pár (prázdný `ebs_contractedcustomerid` → Bill-to) vrátí `NewValue := DestinationFieldRef.Value()` (aktuální Bill-to,
    u nové objednávky už dosazený validací Sell-to, protože vlastní řádky mapování jdou po standardních) a nastaví
    `IsValueFound` **bez ohledu na** dřívější `IsValueFound` — pořadí subscriberů není zaručené a standard by jinak vrátil `''`.
    Dej ho do **samostatného** subscriberu, ne do existujícího, který začíná `if IsValueFound then exit`.
  - Standardní `CRM Int. Table. Subscriber.OnTransferFieldData` končí hned, když **není zapnutá CDS ani CRM integrace**
    (`IsCDSIntegrationEnabled() or IsCRMIntegrationEnabled()`), takže test přes `Integration Record Synch.` s temp field
    mappingem (vzor 11.8) ověří jen vlastní subscriber; bez něj by engine prázdný GUID vyhodnotil `Format('')` → `''` do Code
    pole. Vyplněný GUID přes engine v testu nepřeložíš (36 znaků do Code[20] = `Evaluate` false, hodnota zůstane) — testuj
    `internal` proceduru s `FieldRef` napřímo.
  - AppSourceCop na CDS.W1 hlásí AS0013 / AS0011 na všechna pole proxy extensionů (ID 5435x mimo idRanges, názvy
    `ebs_*` bez affixu) — záměr (ExternalName = název sloupce), CI AppSourceCop nepouští; držet stejný vzor.
  (cust-soitron-bc CDS.W1 `CRM Salesorder CWSOI`, `CDS Sync Logic CWSOI.KeepBillToCustomerOfSalesOrder`, task 66193, 2026-11-04;
  kompilace alc 17 + testy jen lokálně přeložené.)
- **Subscriber „po změně záznamu v BC hned probuď sync“ přes `Dataverse Entity Change` je bez mapování mrtvý kód, který
  jen plní tabulku.** `Dataverse Entity Change.OnInsert` (w1-28 `Integration/Dataverse/DataverseEntityChange.Table.al`)
  najde CRM proxy tabulky s `ExternalName` = `"Entity Name"` a pro každé `Integration Table Mapping` typu Dataverse nad nimi
  s `Direction <> ToIntegrationTable` zavolá `CRM Integration Management.ReactivateJobForTable`; žádné mapování = žádná akce,
  řádek ale zůstane. Když mapování entity (CONTACT…) odebíráš podle typu firmy, odeber / guardni i subscribery
  `OnAfterInsertEvent` / `OnAfterModifyEvent`, které pro ni entity change vkládají (vzor guard `SynchronizesProjects()` u
  Job v cust-soitron-bc `CDS Management CWSOI`). (2026-10-30, cust-soitron-bc CDS.W1, CONTACT odebrán i ve 2Ring.)
- **Odebrání mapování option setů PAYMENT TERMS / SHIPMENT METHOD / SHIPPING AGENT = odebrat i řádky field mappingu
  těch kódů na CUSTOMER, SALESORDER-ORDER a POSTEDSALESINV-INV.** Standard (w1-28 `CRM Int. Table. Subscriber.
  OnTransferFieldData` → `CRM Synch. Helper.ConvertTableToOption` / `ConvertOptionToTable`) překládá Code ↔ Option přes
  `CRM Option Mapping` jen když `IsTableMappedToCRMOption` najde **jakékoli** `Integration Table Mapping` s `Table ID` =
  tabulka relace BC pole (Payment Terms…); bez něj spadne do obecného `Integration Record Synch.TransferFieldData`:
  BC → PA `TextToOptionValue(kód, OptionCaption)` = −1 → pole se tiše nepřenese, PA → BC `Format(option)` → `Validate("Payment
  Terms Code", 'Net 30')` = **chyba synchronizace objednávky**, kdykoli má PA objednávka option vyplněný. Řádky field mappingu
  odstraň v subscriberech `OnResetBidirectionalSalesOrderMappingOnAfterInsertFieldsMapping` (+ legacy `OnResetSalesOrderMapping…`)
  a `OnResetSalesInvoiceHeaderInvoiceMappingOnAfterInsertFieldsMapping` (faktura mapuje jen Payment Terms + Shipping Agent, bez
  Shipment Method; ten jde na fakturu jako text `Description` z `UpdateCRMInvoiceBeforeInsertRecord`, mapování nepotřebuje).
  `Dependency Filter` mapování CUSTOMER (`…|PAYMENT TERMS|SHIPMENT METHOD|SHIPPING AGENT`) čte jen stránka *Run Full
  Synchronization* (`CRM Full Synch. Review Line.AreAllParentalJobsFinished` — chybějící mapování = splněno), plánovaný sync
  ho ignoruje. (2026-11-05, cust-soitron-bc CDS.W1 `CDS Management CWSOI.RemoveOptionSetFieldMappings`, 2Ring: všechna čtyři
  mapování vč. CONTACT odebrána v každé firmě; alc 18 + testy lokálně přeložené, běh v Dataverse neověřen.)
- **Standardní synchronizace ceníků do Dataverse (w1-28 `CRM Setup Defaults.ResetConfiguration`) je jednosměrná BC → Dataverse a
  pro „ceníky v různých měnách" stačí ji nechat zapnutou, žádný vlastní kód.** S *Extended Price Calculation* vznikají mapování
  `PLHEADER-PRICE` (`Price List Header` → `CRM Pricelevel`, filtr `Price Type = Sale`, `Amount Type = Price`, `Dependency Filter`
  `CURRENCY|ITEM-PRODUCT`) a `PLLINE-PRODPRICE` (`Price List Line` → `CRM Productpricelevel`, filtr Sale + Price + `Asset Type`
  Item|Resource + `Minimum Quantity = 0`, závislost `PLHEADER-PRICE|ITEM-PRODUCT`), bez feature `CUSTPRCGRP-PRICE` /
  `SALESPRC-PRODPRICE`; obě jen `ToIntegrationTable`, `Currency Code → TransactionCurrencyId` (prázdný kód = LCY přes
  `CRM Int. Table. Subscriber.OnTransferFieldData`), `Unit of Measure Code → UoMId` při Unit Group mappingu, konstantní
  `PricingMethodCode = CurrencyAmount`, `Status Active → StateCode Active`. Pasti: (a) filtr hlavičky
  **`Allow Updating Defaults`** = `true` jen když `Sales & Receivables Setup."Default Price List Code"` je vyplněný, jinak `false`
  → s nastaveným výchozím ceníkem se synchronizuje **jen** ten (ostatní ceníky mají `Allow Updating Defaults = false`); (b)
  `CheckPriceListHeaderForSync` bere měnu z **prvního řádku** ceníku a při modify `TestField(TransactionCurrencyId)` → jeden ceník
  = jedna měna, řádky s jinou měnou než hlavička synchronizaci shodí; (c) `Status` se nefiltruje, návrhy (Draft) jdou do
  Dataverse jako Inactive pricelevel; (d) řádek potřebuje spárované zboží uvnitř filtru `ITEM-PRODUCT` (`Blocked = false`).
  Ve zákaznické vrstvě, která standardní mapování maže podle typu firmy, stačí `PLHEADER-PRICE` / `PLLINE-PRODPRICE` ze seznamu
  k odstranění vyjmout (cust-soitron-bc CDS.W1 `CDS Management CWSOI.ApplySalesMappingCustomizations`, 2Ring, 2026-11-04;
  kompilace alc 17 + testy lokálně přeložené, běh v Dataverse neověřen).
- **„Synch. Only Coupled Records" standard zapíná u ITEM-PRODUCT, ITEM UOM, UNIT GROUP i SALESORDER-ORDER (bidirectional
  i legacy), SOLINE-ORDERDETAIL má `false`** (w1-28 `CRM Setup Defaults`, parametr `SynchOnlyCoupledRecords` v
  `InsertIntegrationTableMapping`). Příznak platí pro **oba směry** (viz PROJECT výše): nové zboží z BC se v Dataverse
  nezaloží a nová objednávka z Power Apps se nezaloží v BC, dokud se nespáruje ručně. Jediný hook pro ITEM UOM / UNIT GROUP je
  **`CRM Setup Defaults.OnBeforeInsertIntegrationTableMapping(…, var SynchOnlyCoupledRecords, var IsHandled)`** — po-insert
  eventy `OnReset…OnAfterInsertFieldsMapping` mají jen ITEM-PRODUCT, RESOURCE-PRODUCT, objednávky, faktury, ceníky a
  příležitost; `ResetItemUnitOfMeasureUoMMapping` / `ResetUnitGroupUoMScheduleMapping` mají jen `OnBefore…` s `IsHandled`.
  Event nese `TableNo` / `IntegrationTableNo` (guard na dvojici tabulek, ne na jméno) a nenese směr, takže zasáhne i legacy
  SALESORDER-ORDER. Pálí uvnitř `ResetConfiguration`, tedy před `OnAfterResetConfiguration`, kde zákaznická vrstva nepotřebná
  mapování maže — guard na typ firmy není potřeba. Testovat jde přímo `internal` proceduru nad trojicí parametrů bez
  `RegisterTableConnection`. (cust-soitron-bc CDS.W1 `CDS Management CWSOI.SynchronizeUncoupledRecords`, 2Ring, 2026-11-04;
  kompilace alc 17 + testy lokálně přeložené, běh v Dataverse neověřen.)
  Stejně (`InsertIntegrationTableMapping(..., true)` → týž event) vzniká i **PLHEADER-PRICE** (`ResetPriceListHeaderPricelevelMapping`)
  a **POSTEDSALESINV-INV** (`ResetSalesInvoiceHeaderInvoiceMapping`); guard na `Price List Header`/`CRM Pricelevel` a
  `Sales Invoice Header`/`CRM Invoice`. ⚠️ Faktura nemá BC filtr tabulky → první sync po resetu (prázdný `Synch. Modified On
  Filter`) pošle do Dataverse **všechny historické** účtované faktury; před nasazením domluvit / nastavit filtr. (cust-soitron-bc
  CDS.W1, 2026-11-09, ověřeno ve zdroji w1-28.)
- **Počítané pole do Dataverse (odkaz na doklad v BC, příznak „Open in BC" ze stavu objednávky) = žádný řádek field
  mappingu, ale `Integration Rec. Synch. Invoke.OnAfterTransferRecordFields` + zápis zpět při insertu z PA.**
  Hook běží v `TransferFields` při insertu i modify cílového záznamu (standard ho používá pro `Customer.Blocked`,
  UoM, ceníky): guard na pár tabulek (`Sales Header` → `CRM Salesorder`, `Sales Invoice Header` → `CRM Invoice`),
  `DestinationRecordRef.SetTable` → nastav pole → `GetTable` a `AdditionalFieldsWereModified := true` **jen při změně**
  (engine pak zapíše i záznam bez změny mapovaných polí). Subscriber může deklarovat jen potřebné parametry (podmnožina
  podle jmen, `SourceRecordRef` s `var`, jinak PC0010). Směr PA → BC hook nepokryje (nová objednávka z Power Apps se
  BC → PA sama nesynchronizuje, engine jí po insertu nastaví časová razítka) → v `OnAfterInsertRecord` pár
  `CRM Salesorder` → `Sales Header` zapsat přímo do CRM záznamu (`CRMSalesorder.Get(SalesOrderId)` + `Modify(false)`),
  stejně jako standardní `SetOrderNumberAndDocOccurenceNumber` dopisuje `BusinessCentralOrderNumber`. ⚠️ Standard v
  témže `OnAfterInsertRecord` (w1-28 `CRM Int. Table. Subscriber`) objednávku z PA **vydává** (`SetSalesOrderStatus` →
  `Released`, Open jen u zálohy; `OnBeforeTransferRecordFields` ji napřed staví na Open) a pořadí subscriberů není
  zaručené → stav pro příznak číst z DB (`SalesHeader.Get`), ne z předaného `DestinationRecordRef`; při opačném pořadí
  zůstane příznak starý do další synchronizace BC → PA. URL: `GetUrl(ClientType::Web, CompanyName(), ObjectType::Page,
  Page::"Sales Order" / "Posted Sales Invoice", Rec)` funguje i v sync jobu, pole Text[250] + `CopyStr`. Testy bez
  Dataverse: `internal` procedury nad `RecordRef` z `Init` záznamů (`GetUrl` jde i na neuložený záznam), zápis zpět
  přes `CRM Salesorder.Insert(false)` v test připojení `@@test@@`. (cust-soitron-bc CDS.W1 `CDS Sync Logic
  CWSOI.SetBCLinkOfPowerAppsOrder` / `WriteBCLinkToPowerAppsOrder`, task 67561, 2026-11-04; alc 17 + testy jen
  lokálně přeložené.)
- **Stavy obousměrné synchronizace objednávek (BC 28): status objednávky v BC řídí z vlastního kódu jedině hook
  `CRM Int. Table. Subscriber.OnChangeSalesOrderStatusOnBeforeCompareStatus(var SalesHeader, var NewStatus)`, stav `Invoiced`
  standard v obousměrném režimu nikdy nenastaví a otevřené objednávky do PA vůbec neposílá.**
  - Standard po insertu i modify z PA objednávku **vydá** (`SetSalesOrderStatus` → Released, Open jen u záloh); u nezměněné PA
    objednávky (`OnAfterUnchangedRecordHandled` / `OnBeforeIgnoreUnchangedRecordHandled`, typicky echo vlastního zápisu BC → PA)
    ji nejdřív `ChangeSalesOrderStatus(Open)` plain `Modify` otevře a pak znovu vydá; před přenosem polí z PA dá do bufferu
    `Status := Open` (`OnBeforeTransferRecordFields`). Obě místa volají hook → `NewStatus := SalesHeader.Status` (DB stav přes
    `GetBySystemId`) = sync z PA stav **nikdy nemění**: nová objednávka zůstane Open, echo vydanou neotevře. Jen skutečná
    změna mapovaného pole v PA nechá vydanou objednávku Open (engine ji přepsal), uživatel vydá znovu.
  - **BC filtr mapování SALESORDER-ORDER je `Document Type = Order, Status = Released`** → otevřená objednávka se do PA
    neposílá, dokud ji nevydáš (Reopen tam nedojde, vlastní pole z `OnAfterTransferRecordFields` taky ne). Úprava
    v subscriberu `OnResetBidirectionalSalesOrderMappingOnAfterInsertFieldsMapping`: `SalesHeader.SetView(GetTableFilter())`
    → `SetRange(Status)` → `SetTableFilter(GetTableFilterFromView(...))`; existující mapování se změní až po *Use Default
    Synchronization Setup*. Důsledek: každá změna otevřené objednávky jde do PA (BC wins), nová BC objednávka vznikne v PA
    hned (se `Synch. Only Coupled Records` = false).
  - **Zámek vydané objednávky i na straně BC = filtr integrační tabulky** (`CRMSalesorder.SetView(GetIntegrationTableFilter())`
    → `SetRange(ebs_openinbc, true)` → `SetIntegrationTableFilter(GetTableFilterFromView(...))`, Boolean filtr na CRM proxy
    je v pořádku — standard filtruje `CRM Systemuser.IsDisabled/IsLicensed` stejně): platí jen pro čtení z Dataverse, takže
    vydaná objednávka (příznak Ne) se z PA nečte a nemůže objednávku v BC otevřít, ale BC → PA ji dál aktualizuje (dohledání
    podle ID bez filtru) a po Reopen se do filtru vrátí. Bez něj hlídá vydanou objednávku jen UI zámek v PA. Pozor: PA
    záznamy s prázdným (Ne) příznakem z doby před přidáním sloupce filtr nepustí → před nasazením hromadně nastavit Ano.
    Test: dva `CRM Salesorder.Insert(false)` (Ano / Ne) + `SetView(filtr)` + `SetRange(SalesOrderId)` + `RecordIsEmpty`.
  - **`statecode = Invoiced`:** `CRM Sales Document Posting Mgt.PostCRMSalesDocumentOnAfterPostSalesDoc` při
    `IsBidirectionalSalesOrderIntEnabled` hned končí a plně vyfakturovanou objednávku účtování smaže (vazba zůstane jen
    s `Archived Sales Order`, sync ji ignoruje) → vlastní pár subscriberů: `Sales-Post.OnBeforeDeleteAfterPosting`
    (`EverythingInvoiced`; `CRM Integration Record.FindIDFromRecordID` funguje jen dokud záznam existuje → `SystemId` + CRM ID
    do globálů codeunity, statické subscribery sdílejí instanci per session, stejný vzor jako standard) +
    `Sales-Post.OnAfterPostSalesDoc` (běží **po** `Commit`; `PreviewMode` skip, shoda `SystemId` proti náhledu, pak
    `Codeunit.Run(Codeunit::"CRM Integration Management")` zaregistruje CRM spojení v session uživatele,
    `StateCode`/`StatusCode := Invoiced`, `Modify(false)` — hodnoty jako standard v jednosměrném režimu). Chyba Dataverse
    přijde uživateli až po zaúčtování; `TryFunction` kolem zápisu nejde (DB zápis). Částečná faktura objednávku nemaže → nic.
  - Okamžitý sync po Release / Reopen: `Dataverse Entity Change."Entity Name" := 'salesorder'` + `Insert(true)` z
    `Release Sales Document.OnAfterReleaseSalesDoc` / `OnAfterReopenSalesDoc` (`OnInsert` reaktivuje job jen při
    `CDS Connection Setup."Is Enabled"` a mapování `Type = Dataverse`; bez mapování řádky jen přibývají → guard
    `IsBidirectionalSalesOrderIntEnabled`).
  - Testy bez Dataverse: vazba přes `CRM Integration Record.InsertRecord(CRMID, SystemId, TableId)` (`CoupleRecordIdToCRMID`
    navíc hlídá duplicitní vazbu), `CRM Salesorder.Insert(false)` v `@@test@@`, `Sales Header.Delete(false)` simuluje smazání
    účtováním. CodeCop **AA0214** („should be modified before saving") na `Get` → `SetTableFilter` → `Modify(false)` vyskočí
    v test appce (v hlavní appce stejný vzor ne) → `#pragma warning disable AA0214` s komentářem kolem `Modify`.
    alc 17 bere **opakovaný `/packagecachepath:`** (dva parametry místo seznamu s čárkou); test cache = MS 28.5 sada
    (`Microsoft_Tests-TestLibraries_28.5.54151.54365` a spol. z dřívějšího soitron scratchpadu `testcache/`) + build hlavní
    appky s verzí **vyšší** než stará kopie v `.alpackages` (kopie `app/` ve scratchpadu s `"version": "28.0.999.0"`), jinak
    alc vezme starou.
  (cust-soitron-bc CDS.W1 `CDS Sync Logic CWSOI.KeepSalesOrderStatus` / `RememberInvoicedSalesOrder` /
  `SetPowerAppsOrderInvoiced`, `CDS Management CWSOI.IncludeOpenSalesOrdersInMapping` / `ReadOnlyPowerAppsOrdersOpenInBC` /
  `WakeUpSalesOrderSynchronization`, task 67561, 2026-11-04; alc 17 + testy jen lokálně přeložené.)
- **Stav úhrady účtované faktury v Dataverse (`CRM Invoice.StateCode/StatusCode` Active/Billed → Paid/Partial → Paid/Complete)
  řeší standard sám, žádný vlastní report do fronty.** Výpočet je `CRM Synch. Helper.CalculateActualStatusCode` nad `Cust. Ledger
  Entry` faktury (`Document Type = Invoice`, `Document No.`): `CalcFields(Amount, "Remaining Amount")` → `Remaining = 0` = Paid/Complete,
  `Remaining <> Amount` = Paid/Partial, jinak Active/Billed (hook `OnBeforeCalculateActualStatusCode` s `IsHandled`). Volá se (a) při
  založení CRM faktury (`CRM Int. Table. Subscriber.UpdateCRMInvoiceAfterInsertRecord` → `UpdateCRMInvoiceStatus`), (b) opakovaně
  z **codeunit 5350 `CRM Statistics Job`** (`UpdateStatusOfPaidInvoices('')`): projde `Detailed Cust. Ledg. Entry` s `Entry No.` >
  `CRM Synch Status."Last Update Invoice Entry No."` (vodoznak, posune se jen bez chyb Dataverse), per CLE faktury dohledá spárovanou
  CRM fakturu a `UpdateCRMInvoiceStatusFromEntry` (`ActivateInvoiceForFurtherUpdate` nejdřív přepne Paid → Active, protože neaktivní
  faktura je v Dataverse read-only; stornovaná faktura → Canceled). Pokrývá i odúčtování (unapply = nové DCLE) a aplikaci dobropisu.
  Úlohu fronty zakládá *Use Default Synchronization Setup* (`CRM Setup Defaults.RecreateStatisticsJobQueueEntry`, 30 min) a
  `Job Queue Entry.OnFindingIfJobNeedsToBeRun` ji pustí jen při novém DCLE nad vodoznakem. Pasti: (1) běží jen s `CRM Connection
  Setup."Is Enabled"`; (2) před fakturami nejdřív `UpdateAccountStatistics` zapisuje entitu `nav_accountstatistics` (BC integrační
  solution v Dataverse) — bez ní úloha spadne dřív, než dojde na faktury, ověřit v Job Queue Log; (3) nespárovaná faktura v době běhu
  se přeskočí a vodoznak jede dál (dožene to insert sync přes `UpdateCRMInvoiceStatus`); (4) `Modify` účtované faktury v BC (vlastní
  pole stavu úhrady) změní `SystemModifiedAt` → POSTEDSALESINV-INV ji znovu pošle, u `StateCode <> Active` ji
  `IgnoreReadOnlyInvoiceOnQueryPostFilterIgnoreRecord` přeskočí. Vlastní BC pole stavu úhrady plň synchronně ze subscriberu na
  `Detailed Cust. Ledg. Entry.OnAfterInsertEvent` (CLE Invoice + `Sales Invoice Header.Get`, stejný výpočet, `Modify(false)` jen při
  změně), nebo z `OnUpdateCRMInvoiceStatusFromEntryOnBeforeModify` (jen spárované faktury). (w1-28, cust-soitron-bc 2Ring task
  67562 analýza, 2026-11-05.)
  ⚠️ **Vlastní sloupce faktury PA (zůstatek, datum platby) NEdávej do téhož `Modify`, kterým standard mění stav.** První verze je
  dosazovala v `OnUpdateCRMInvoiceStatusFromEntryOnBeforeModify` do záznamu, který standard vzápětí `Modify()` s novým
  `StateCode`/`StatusCode`: v 2RING DEV se status faktury změnil (Paid / Partial), sloupce zůstaly prázdné. Nejpravděpodobnější
  vysvětlení: proxy změnu stavu posílá jako změnu stavu a ostatní změněné atributy s ní do Dataverse nejdou (neověřeno ve zdroji
  platformy, jen chování). Oprava: v hooku zapsat sloupce **vlastním `Modify` se stavem, který faktura v Dataverse právě má**
  (`Get` uložené faktury; po `ActivateInvoiceForFurtherUpdate` je Active), pak v záznamu vrátit nový stav pro `Modify` standardu;
  fakturu, která v Dataverse není Active, samostatně nezapisovat (read-only). Druhá, nezávislá cesta: řádky *Integration Field
  Mapping* `Sales Invoice Header` → `CRM Invoice` (ToIntegrationTable) z BC polí stavu úhrady, přidané v subscriberu
  `OnResetSalesInvoiceHeaderInvoiceMappingOnAfterInsertFieldsMapping` — pokryjí insert nové faktury a modify faktury, která je v PA
  ještě Active (zákazník chtěl mapování kvůli přehlednosti místo kódu v `OnAfterTransferRecordFields`, funkčně totéž; Paid faktury
  sync přeskakuje, ty dál jen hook statistické úlohy). Ověření opravy v DEV k datu zápisu chybí. (cust-soitron-bc CDS.W1
  `CDS Sync Logic CWSOI.WritePaymentFieldsToPowerAppsInvoice`, `CDS Management CWSOI.AddPaymentStateFieldMappings`, 2026-11-06.)
  **Dorovnání uhrazených faktur, jejichž položky se už nemění** (statistická úloha je znovu nenavštíví, sync je přeskakuje):
  veřejná `CRM Synch. Helper.UpdateCRMInvoiceStatusFromEntry(var CRMInvoice, CustLedgerEntry): Integer` (1 = zapsáno) dělá
  přesně krok úlohy včetně reaktivace Paid faktury a hooků → report přes faktury: `CRM Integration Record.FindIDFromRecordID` +
  `CRMInvoice.Get` + volání, předtím `Codeunit.Run(Codeunit::"CRM Integration Management")` kvůli spojení. Test bez Dataverse:
  `CRM Integration Record.InsertRecord(CRMID, SystemId, TableId)` + `CRMInvoice.Insert(false)` v `@@test@@` projde celým řetězcem
  (`Send Inv. Payment State CWSOI`, 2026-11-06).

### 11.8d Zapnutí synchronizace a úlohy fronty, vyřazená mapování, filtr kontaktů podle obchodního vztahu, měna

Z cust-alumistr-bc task 68073 (Alumistr CDS Sync, BC 29, 2026-11-24; zdroje w1-28 `Integration/Dataverse/CDSConnectionSetup.Table.al`,
`CDSSetupDefaults.Codeunit.al`, `CDSConnectionSetupWizard.Page.al`, `Modules/System/JobQueue/JobQueueEntry.Table.al`,
`Integration/D365Sales/CRMSynchHelper.Codeunit.al`, `CRM/Contact/Contact.Table.al`):

- **Pořadí při zapnutí *Povolit synchronizaci dat* na stránce *Nastavení připojení Dataverse*:** `CDS Connection Setup.OnModify`
  → `EnableConnection` → `EnableIntegrationTables` (`Modify(); Commit();` → `CDS Setup Defaults.ResetConfiguration`: standardní
  mapování přes `RecreateJobQueueEntryFromIntTableMapping` dostanou úlohu **Ready** + naplánovaný task → `OnAfterResetConfiguration`)
  → `CDS Integration Mgt.OnEnableIntegration` (standard `HandleOnEnableIntegration`: model vlastnictví *Osoba* → úlohu SALESPEOPLE
  založí **znovu Ready**, *Tým* → mapování SALESPEOPLE smaže) → teprve pak `OnAfterModifyEvent` tabulky. Akce *Použít výchozí
  nastavení synchronizace* volá jen `ResetConfiguration`; průvodce volá `EnableIntegrationTables` přímo (`OnEnableIntegration`
  nevyvolá). Vypnutí → `UpdateCDSJobQueueEntriesStatus` dá úlohy na On Hold (už standard).
- **„Po zapnutí nechat úlohy Vyčkávat":** `JobQueueEntry.SetStatus("On Hold")` (zruší i task) pro úlohy `Integration Synch. Job
  Runner` s `Record ID to Process` = mapování `Type = Dataverse`, `Delete After Synchronization = false` (vzor standardu
  `UpdateCDSJobQueueEntriesStatus`). Volat v subscriberu `OnAfterResetConfiguration` **a** v `CDS Connection Setup.OnAfterModifyEvent`
  při `RunTrigger and Rec."Is Enabled" and not xRec."Is Enabled"` (xRec spolehlivý jen pro Modify ze stránky) — jinak úloha
  SALESPEOPLE z `OnEnableIntegration` zůstane Ready; subscriber na `OnEnableIntegration` to nevyřeší (pořadí vůči standardu není
  zaručené). Na On Hold i úlohy `On Hold with Inactivity Timeout` (běžící opakovaná úloha, 5.x14 v `bc-al-objects.md`). Zákaznické
  kopie `RecreateJobQueueEntry…` ze standardu s `Commit(); SetStatus(Ready)` na konci (Alumistr `CreateJobQueueEntryFromIntTableMapping`)
  při tom nech bez `SetStatus` — `Commit` tam byl jen kvůli `Codeunit.Run` v `EnqueueTask`.
- **`Integration Table Mapping.OnDelete` maže field mappingy a konfigurační šablony, úlohy fronty NE.** Zákaznická vrstva, která po
  resetu nepoužívaná standardní mapování maže (VENDOR, PAYMENT TERMS, SHIPMENT METHOD, SHIPPING AGENT), nechává ve frontě Ready úlohy
  s `Record ID to Process` na neexistující mapování. Před `Delete(true)`: `JobQueueEntry.SetRange("Object ID to Run", Codeunit::
  "Integration Synch. Job Runner")` + `SetRange("Record ID to Process", Mapping.RecordId())` + `DeleteTasks()` (stejně standard
  maže SALESPEOPLE u modelu *Tým*).
- **Testy bez Dataverse:** úlohy fronty vkládej přímo (`Init`, `ID := CreateGuid()`, Object Type/ID, `Record ID to Process`, `Status`,
  `Insert(false)` — žádný task, `SetStatus` pak jen `CancelTask` s prázdným `System Task ID`), mapování `CreateRecord` nad `@@test@@`
  (11.8). Zapnutí připojení (`CDS Connection Setup.Modify(true)` se změnou `Is Enabled`) v testu nejde, `EnableConnection` volá
  Dataverse → subscriber tabulky drž tenký a logiku testuj přes `internal` proceduru.
- **Filtr kontaktů BC → Dataverse podle obchodního vztahu:** pole `Contact."Contact Business Relation"` (cs-CZ tabulka *Obchodní vztah
  kontaktu*, na kartě kontaktu *Obchodní vztah*; hodnoty *Zákazník*, *Dodavatel*, *Vícenásobné*…). Osoba přebírá vztah své společnosti
  (`Contact Business Relation.UpdateContactBusinessRelation` přepočítá společnost i osoby s jejím `Company No.`); společnost, která je
  zákazník i dodavatel, má *Vícenásobné* → `SetRange(…, Customer)` ji vyřadí. Do *Filtru tabulky* (`GetTableFilter` / `SetTableFilter`,
  platí jen BC → Dataverse) přidej podmínku přes `Contact.SetView(Mapping.GetTableFilter())` + `SetRange` + `FilterPageBuilder`
  round-trip, ať zůstanou standardní podmínky (*Osoba*, `Company No.` <> ''). Spárovaný kontakt mimo filtr se z BC přestane aktualizovat,
  v Dataverse zůstane a směr Dataverse → BC běží dál. Test: temp `Contact` (`Contact Business Relation` jde přiřadit přímo, pole je
  jen `Editable = false`) + `SetView(GetTableFilter())` + `RecordCount`.
- **Měna:** standardní CUSTOMER mapuje `Currency Code ↔ TransactionCurrencyId` obousměrně (Validate Field ano, Validate Integration
  Table Field ne); zákaznické vrstvy ho často po resetu mažou (`DeleteIntegrationFieldMapping`). Prázdný kód (LM) ↔ měna LM v Dataverse
  řeší `CRM Synch. Helper.FindNewValueForSpecialMapping` **podle relace pole na tabulku `Currency`** (ne podle jména pole), volané z
  `CDS Int. Table. Subscriber.FindNewValueForCoupledRecordPK` → platí pro jakékoli BC pole s `TableRelation = Currency`. Speciální
  větev podle jména `Currency Code` v `OnTransferFieldData` je jen pro případ, kdy se LM liší od základní měny Dataverse. Nespárovaná
  měna = chyba „must be coupled", úloha CURRENCY musí proběhnout dřív.
- **BC příležitost (`Opportunity`) pole měny nemá** (částky jsou LM: *Estimated Value (LCY)*, *Calcd. Current Value (LCY)*), standardní
  mapování OPPORTUNITY (`CRM Setup Defaults.ResetOpportunityMapping`) měnu nemapuje a nabídka z příležitosti (`Opportunity.CreateQuote`)
  bere měnu ze zákazníka. Požadavek „měna příležitosti obousměrně" znamená nové pole, které v BC nic neřídí — u Alumistra se proto
  nedělalo (rozhodnutí vývojáře, zadání k doplnění). Když by měna v Dataverse měla sedět k částce nabídky (`ActualValue` z částky
  nabídky v měně zákazníka), posílala by se jednosměrně BC → Dataverse z nabídky přes `OnAfterTransferRecordFields`, ne field mappingem.
