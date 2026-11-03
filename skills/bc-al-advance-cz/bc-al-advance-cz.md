# BC/AL poznámky — CZZ zálohy (Advance Payments Localization for Czech)

> Vyčleněno z `bc-al-objects.md` 2026-11-03 (soubor by přesáhl 1000 řádků); číslování 5.z* je původní kvůli odkazům „viz X.Y".
> Načítej, když řešíš: CZZ zálohy — vazba záloha ↔ doklad (`Advance Letter Application CZZ`), scoped guard přes manual bind,
> generovaný řádek zálohy z reportu *Create Sales Adv. Letter CZZ*, platba zálohy (deník, výpis, propojení z položek), odpojení
> a účto skupina zákazníka / dodavatele na položkách plateb záloh.
> Testy CZZ (záloha s platbou, release, To Pay) → `bc-al-autotests-domains.md`; W1 Prepayment nemá s CZZ nic společného.

Obsahuje:
- **5.z3** vazba záloha ↔ objednávka, scoped guard
- **5.z5** `Create Sales Adv. Letter CZZ` (report 31012) — úprava generovaného řádku
- **5.z7** platba zálohy a účto skupina zákazníka / dodavatele (šablona vs. karta, propojení, odpojení)

## 5.z CZZ zálohy

### 5.z3 CZZ Advance Payments — vazba záloha↔objednávka a scoped guard přes manual bind

Poznatky z EF Advance CZ (WI 63636, 2026-08):

- **Vazbu zálohy na doklad drží `Advance Letter Application CZZ` (31007)** (PK: Letter
  Type, Letter No., Document Type, Document No.), ne pole na hlavičce zálohy. Pole
  `"Order No."` na `Sales Adv. Letter Header CZZ` je jen zrcadlo: `OnDelete` tabulky
  31007 ho **vymaže (i `"Posting Description"`) a standard ho při novém propojení
  NIKDY neobnoví** — extension logika postavená na `Order No.` po unlink+relink tiše
  přestane fungovat. Obnovu je nutné dopsat subscriberem na `OnAfterInsertEvent` 31007.
- **Uživatelské odpojení** jde přes dialog `LinkAdvanceLetter` (page 31175 „Advance
  Letter Appl. Edit CZZ", volá `SalesAdvLetterManagementCZZ.LinkAdvanceLetter`) —
  chybějící řádky po LookupOK se mažou `Delete(true)` **bez IsHandled eventu**.
  Tatáž tabulka se ale maže i systémově (`SalesPostHandlerCZZ` po vyfakturování,
  `SalesAdvLetterPostCZZ` při Close, ApplyChanges při usage) — plošný subscriber na
  `OnBeforeDeleteEvent` by rozbil účtování.
- **Pattern „scoped guard": codeunit s `EventSubscriberInstance = Manual`** a
  subscriberem na `OnBeforeDeleteEvent` + na page nahradit standardní akci vlastní,
  která udělá `BindSubscription(Guard)` → volání standardní logiky → `Unbind`.
  Kontrola tak platí přesně pro interaktivní dialog a systémové cesty nevidí.
  Lokální codeunit proměnná v OnAction drží subscription po dobu volání. V guardu
  nezapomenout `IsTemporary()` exit (dialog pracuje s temp buffery téže tabulky).

### 5.z5 CZZ `Create Sales Adv. Letter CZZ` (report 31012) — kde upravit generovaný řádek zálohy

- **`OnCreateAdvanceLetterLineOnBeforeInsert(var SalesAdvLetterLineCZZ; SalesAdvLetterHeaderCZZ)`** běží těsně před `Insert(true)`
  každého generovaného řádku, v obou režimech (seskupení podle DPH i *Navrhnout podle řádku*). Správné místo pro úpravu řádku (např.
  `Description` podle DPH skupiny); subscriber na `OnInsert` tabulky by přepsal i ručně pořízené řádky na kartě zálohy.
- `UpdateAmounts` dělá před eventem `TestField("VAT Prod. Posting Group")` → generovaný řádek **nikdy nemá prázdnou** DPH skupinu
  zboží (větev „prázdná skupina" testuj přímo na proceduře, report ji nevyrobí).
- `Sales Adv. Letter Line CZZ.Description` je **Text[100]** → delší text ze setupu `CopyStr(…, 1, MaxStrLen(Description))`.
- Report na konci položí Confirm *„Chcete otevřít vytvořenou zálohu?"* → v testu `[ConfirmHandler]` (Reply false). Z prodejní
  objednávky: *Akce → Záloha → Vytvořit zálohovou fakturu…* (request page *Vytvořit prodejní zálohu*: Kód zálohy, Záloha %,
  Částka zálohy, Navrhnout podle řádku; to poslední jde zapnout jen na request page → test s `RequestPageHandler`, viz
  „Report s request page v testu po zápisech" v `bc-al-autotests.md`).

(2026-10-21, cust-zlomek-bc PBI 65149, zdroj cz-28, ověřeno v BC-DEV 28.5.)

### 5.z7 CZZ platba zálohy a účto skupina zákazníka / dodavatele — kde ji standard bere a kde ji přepsat ze šablony

Ověřeno ve zdroji CZZ 27.4 (`GenJournalLineCZZ.TableExt.al`, `PurchAdvLetterPostCZZ` / `SalesAdvLetterPostCZZ`,
`GenJnlPostLineHandlerCZZ`, `VendorLedgEntryHandlerCZZ`) při cust-smartwings-bc 2026-11-03 — šablona zálohy tam má vlastní
pole *Cust./Vend. Posting Group CSW* a zákazník chtěl, aby položky plateb záloh nesly skupinu ze šablony (účet 378), ne z karty (321):

- **Výběr zálohy na řádku fin. deníku (`Advance Letter No. CZZ` OnValidate) účto skupinu nemění** — doplní částku (`To Pay`),
  dimenze a `Adv. Letter Template Code CZZ`; `Posting Group` zůstává z karty (dal ji `Validate("Account No.")`). Účet záloh
  nejde z účto skupiny, ale z pole šablony *Advance Letter G/L Account*: řádek položky zálohy má `Use Advance G/L Account CZZ`
  a subscriber `Gen. Jnl.-Post Line.OnBeforeCreateGLEntriesForTotalAmountsV19` přesměruje účet pohledávek / závazků
  (`GenJournalLine.GetAdvanceGLAccountNoCZZ`). Proto G/L sedí na 378, i když položka zálohy má skupinu z karty.
- **`PostAdvancePayment` (deník, bankovní výpis, pokladna i *Propojit zálohovou fakturu* z položek) účtuje dva řádky** přes
  `InitGenJournalLine(VendorLedgerEntry)` → `CopyFromVendorLedgerEntryCZZ` (`"Posting Group" := VLE."Vendor Posting Group"`;
  prodej `CopyFromCustLedgerEntryCZZ`): (1) vyrovnání platby (`Correction`, `Applies-to ID` z `SetApplication`), (2) položku
  zálohy (`Adv. Letter No. (Entry) CZZ`, `Use Advance G/L Account CZZ`). Skupinu ze šablony dosaď v
  **`OnPostAdvancePaymentOnBeforePostAdvancePayment(var PurchAdvLetterHeaderCZZ / SalesAdvLetterHeaderCZZ, PostedGenJournalLine,
  AdvancePostingParameters / AdvancePostingParametersCZZ, var GenJnlPostLine, var GenJournalLine)`** — běží pro všechny cesty vzniku
  položky zálohy. Vyrovnání (1) nech být, musí uzavřít platbu na jejím vlastním účtu.
- **Odpojení (`PostAdvancePaymentUnlinking`) znovu otevře platbu „balance" řádkem inicializovaným z položky zálohy**
  (`InitGenJournalLine(VendorLedgerEntryAdv)`, bez `Use Advance G/L Account`) → jakmile položka zálohy nese skupinu ze šablony,
  vrácená platba by skončila na účtu záloh. V `OnPostAdvancePaymentUnlinkingOnBeforePostPaymentApplication(…, var GenJournalLine)`
  vrať skupinu původní platby: `GenJournalLine."Applies-to ID"` = `Applies-to ID` platební položky (`SetApplication` =
  `Document No.` + `Entry No.`), dohledej `Vendor / Cust. Ledger Entry` podle `Account No.` + `Applies-to ID` (klíč
  `"Vendor No.","Applies-to ID"` existuje). Čerpání zálohy fakturou (`ReverseAdvancePayment`) bere skupinu z faktury a účet ze
  šablony — nesahat.
- **Přiřazuj přímo** (`"Posting Group" := …`, jako CZZ), ne `Validate` — `CheckPostingGroupChange` vyžaduje *Allow Multiple
  Posting Groups* v setupu i na kartě. Base při účtování (`PostVend` / `PostCust`) pustí jinou skupinu než na kartě, dokud je
  *Allow Multiple Posting Groups* v setupu vypnuté; se zapnutým setupem chce příznak i na kartě
  (`Vend.CheckAllowMultiplePostingGroups`). Účet pohledávek / závazků skupiny ze šablony musí odpovídat *Advance Letter G/L
  Account* šablony, jinak vyrovnání a položka zálohy skončí na různých účtech.
- Subscriber na `OnAfterValidateEvent` pole `Advance Letter No. CZZ` z jiné appky funguje (pole tableextension CZZ) a `xRec` je
  tam stav před `Validate` i z kódu → „záloha z řádku odebrána" (`xRec <> ''`, `Rec = ''`) = skupina zpět z karty; CZZ to volá i
  z `Account No.` / `Currency Code` OnAfterValidate. Vzor: cust-smartwings-bc `Adv. Payments Mgt. CSW` (53744).
- Stará data to neopraví — položky zaúčtované před nasazením je nutné přepsat skriptem (vzor `UpdateVendorLedgerEntry`
  v `UpgradeAdvancePayments.CZ`: VLE + `Detailed Vendor Ledg. Entry."Posting Group"` podle šablony).
