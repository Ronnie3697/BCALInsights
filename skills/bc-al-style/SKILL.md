---
name: bc-al-style
description: >-
  BC/AL konvence kódu a stylu z praxe (Business Central, AL; sekce 1, 10):
  jazyk identifikátorů (EN), struktura src/ podle typu objektu, permission
  sety (limit 20 znaků, PTE0018, vrstvení rolí Read/Oper/Admin), naming
  doprovodných souborů, Description a ToolTip (kam a jak), pořadí
  IntegrationEvent/actionref, Temp prefix, StyleExpr, Access = Internal,
  formát page fieldů, ApplicationArea/DataClassification,
  AllowInCustomizations (LC0035, AL0667), typed Record vs RecordRef, array
  parametry, přidělování object/field ID per typ (test objekty od konce
  range), Format(enum) = caption, Evaluate/Format locale pasti (formát 9,
  Excel Buffer čísla), moderní AL patterny podle app.json (namespaces,
  interfaces, Isolated Storage, SecretText, LC0083, LC0088, telemetrie,
  Cloud target zakázaná API, ověřování API). Načti při psaní nebo review AL
  kódu, naming, ToolTipů, permission setů, přidělování ID, výběru patternu.
  (Chování page/pageextension — RunModal, ConfirmManagement, factbox,
  Visible → skill bc-al-ui.)
user-invocable: true
---

# BC/AL — Styl & psaní kódu (sekce 1, 10)

**Zdroj pravdy:** `C:\WorkTasks\BCALInsights\bc-al-style.md`
(v repu `../../bc-al-style.md` relativně k tomuto skillu). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, příklady kódu a odůvodnění jsou v souboru.

## Co udělat

1. **Přečti `C:\WorkTasks\BCALInsights\bc-al-style.md` celý.** Vejde se do jednoho Read; když se
   výstup ořízne, okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: UI patterny stránek (RunModal, ConfirmManagement, factbox,
   Visible, MultiLine…) → `bc-al-ui` (sekce 4, vyčleněno 2026-09-08); DB operace
   a subscribery → `bc-al-data`; analyzery,
   ruleset, co číst před editem → `bc-al-workflow`; nová appka, affixy,
   permission sety per appka → `bc-al-tools` (7.5).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **1.1** Kód i UI texty **anglicky**; čeština jen v `.xlf`.
- **1.2** `src/<typ objektu>/`, jeden objekt = jeden soubor. `permissionset`
  a `permissionsetextension` = dvě složky; extension pojmenuj podle base setu
  (`D365BASIC.PermissionSetExt.al`). Název permissionsetu **≤ 20 znaků**
  (AL0305), plný název do `Caption`. Base-app granty nesmí být přímo v setu,
  který jde do `permissionsetextension` (PTE0018) → neassignable „stavební
  blok" + `IncludedPermissionSets`. Víc rolí = vrstvení **Read ⊂ Oper ⊂ Admin**
  (`D365 READ` → Read, `D365 BASIC` → Oper, `D365 SETUP` → Admin); při
  refactoru **nepřejmenovávej** existující admin set (Access Control váže na
  Role ID). Ruleset patří vedle `app.json` (12.4 v `bc-al-workflow`).
- **1.3** Doprovodný soubor = stejný název vč. sufixu typu (`X.Report.docx`,
  `Y.ControlAddIn.js`).
- **1.4** `Description` (EN, 1–2 věty) na codeunit / report / tableextension /
  pageextension; `reportextension` ji nemá (AL0124) → `//` komentář.
- **1.5** ToolTip pole → **na tableextension** (propaguje se na page), ne na
  pageextension; akce → na page. Uživatelsky, `'Specifies …'` / sloveso,
  ≤ ~200 znaků, žádný technický žargon.
- **1.6 / 1.7** `[IntegrationEvent]` publishery na konec objektu; `actionref`
  na konec `actions {}`.
- **1.8** Prefix `Temp` jen pro `Record X temporary` (CodeCop AA0073 / AA0237).
- **1.9** `StyleExpr` = Text/Boolean/Code proměnná plněná `Format(PageStyle::X)`;
  string literal `'Favorable'` = LC0086, enum přímo = compile error.
- **1.10** `Access = Internal` → **nepřepínat** na Public bez schválení;
  zvaž `internalsVisibleTo`.
- **1.11** Page fieldy víceřádkově, žádné one-linery. `ApplicationArea` na
  page (pageextension fieldy ji ale potřebují), `DataClassification` na
  tabulce. LC0035 → pole radši doplň na page než `AllowInCustomizations = Never`;
  `AllowInCustomizations = Always` je deprecated (AL0667) → `AsReadOnly` /
  `AsReadWrite`.
- **1.11b / 1.11c** Typed `Record` místo `RecordRef`, když tabulku znáš.
  Velikost array v signaturách kompilátor nehlídá — drž ji všude stejnou.
- **1.12** **ID per typ objektu od začátku range** (samostatný namespace per
  typ); test objekty (všechny typy, ne jen codeunity) od konce range.
- **1.13** `Format(enum)` = caption → nikdy jako strojově parsovaný token;
  explicitní mapovací procedura.
- **1.14** Text ↔ Decimal v datové pipeline vždy `Format(x, 0, 9)` /
  `Evaluate(..., 9)`; user input normalizuj (nbsp, `,` → `.`). Testy drž ve
  tvaru produkčních dat. Excel Buffer `Cell Value as Text` je locale formát
  bez tisíců → napřed locale `Evaluate`, až při neúspěchu normalizace + 9.
- **10** Pattern vyber podle `app.json` (application / platform / target /
  runtime), nedowngraduj repo, které moderní patterny už má. Cloud target: žádný
  DotNet, File, Automation, WindowsLanguage. `DT.Date()` / `DT.Time()` místo
  `DT2Date` / `DT2Time` (LC0083). API si **ověř** (MS Learn MCP, LinterCop
  wiki), nehádej z paměti — zvlášť BC22+ věci.
