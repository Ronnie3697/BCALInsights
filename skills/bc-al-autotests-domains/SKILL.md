---
name: bc-al-autotests-domains
description: >-
  BC/AL autotesty – doménové recepty (Business Central, Essence CI): sešit požadavků a plánování
  (Carry Out Action Message bere celý list → vlastní batch per test, Calculate Plan report 699 do vlastního
  batche, poptávka na WorkDate = „There is nothing to create", SL Action Cond. Mgt. Message handler),
  nákupní záloha CZZ s navázanou platbou (řádek + release, Advance Letter G/L Account, To Pay, Transaction No.
  přes Vendor Ledger Entry), párování bankovních plateb Match Bank Payment CZB z kódu (Search Rule, Variable S.
  to Variable S., směr částky, Issue Payment Order Message, defaultní řádky podle verze BC). Načti při psaní
  testů plánování/nákupu z plánu, CZZ záloh a bankovního párování; obecná pravidla testů jsou ve skillu
  bc-al-autotests.
user-invocable: true
---

# BC/AL — Autotesty: doménové recepty

**Zdroj pravdy:** `bc-al-autotests-domains.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen
wrapper. Vyčleněno z `bc-al-autotests.md` 2026-10-01 (překročil 1000 řádků).

## Co udělat

1. **Přečti `bc-al-autotests-domains.md` z adresáře tohoto skillu celý** (vejde se do jednoho Read).
   Bez přečtení nejednej.
2. Obecná pravidla testů (handlery, Setup Storage, asserterror rollback, TestPage, kompilace test appky)
   jsou ve skillu `bc-al-autotests` — načti ho vždy spolu s tímhle.
3. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli, nepřepisuj potichu.
   Nový poznatek → do souboru + commit + push (viz skill `bc-al`).

## TL;DR

- Každý carry-out test má **vlastní batch** sešitu (`CreateRequisitionWkshName`); Calculate Plan přes report 699
  s `SetTemplAndWorksheet`; poptávku datuj do budoucna, jinak „There is nothing to create".
- CZZ záloha pro platbu: hlavička bez ručního Status + řádek + `Rel. Purch.Adv.Letter Doc. CZZ`; šablona s
  Advance Letter G/L Account; Transaction No. přes `Vendor Ledger Entry No.`.
- `Match Bank Payment CZB`: `Codeunit.Run` jako statement, `Variable S. to Variable S. CZB := true`,
  vlastní Search Rule s jediným řádkem, výsledek čti po `Get`; Issue Payment Order potřebuje MessageHandler.
