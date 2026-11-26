---
name: bc-al-dataverse
description: >-
  BC/AL Dataverse / CDS sync (BC, sekce 11.8–11.8e): Integration Table Mapping (Filtr tabulky BC → Dataverse,
  Integration Table Filter jen Dataverse → BC, směry, field mapping jedním směrem, Synch. Only Coupled Records, šablony
  Table Config Template), reset defaultů a vlastní mapování (recreate, Man. Integration Table Mapping), CRM proxy
  tabulky (Option Picklist + OptionOrdinalValues, lookup na nesynchronizovaný číselník, statecode), úlohy sync po zapnutí /
  resetu (Ready → On Hold, SALESPEOPLE z OnEnableIntegration, úlohy smaz. mapování), filtr kontaktů dle Contact Business
  Relation, měna (LCY ↔ Dataverse, příležitost bez měny), obousměrné objednávky (stavy, číslo a název z Power Apps, Bill-to),
  faktury (write-in produkt, Relationship Type, stav úhrady, CRM Statistics Job), ceníky, testy bez Dataverse (@@test@@ jen
  v testovací relaci, ClearState), filtr seznamu dle GUID pole bez relace (obchodní jednotka: lookup Vybrat více, cache
  názvů). Načti u Dataverse / CDS / CRM / Power Apps sync a jejích úloh fronty.
user-invocable: true
---

# BC/AL — Dataverse (CDS) synchronizace (sekce 11.8)

**Zdroj pravdy:** `bc-al-dataverse.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`). Tenhle skill je jen wrapper —
pravidla níže jsou výcuc; detail, zdroje standardu, testovací recepty a příklady jsou v souboru.
Vyčleněno z `bc-al-integrations.md` 2026-11-24, číslování 11.8 je původní.

## Co udělat

1. **Přečti `bc-al-dataverse.md` z adresáře tohoto skillu celý.** Vejde se do jednoho Read; když se výstup ořízne,
   okamžitě dočti přes `offset`. Bez přečtení nejednej.
2. Pravidla ber jako závazná; rozpor s tvou expertizou → řekni uživateli,
   nepřepisuj potichu. Nový poznatek → do souboru + commit + push (viz skill
   `bc-al`).
3. Sousední témata: HttpClient, SecretText, Power Automate, API page, Shopify, Jira, Dotykačka → `bc-al-integrations`
   (5.y2–5.y4, 11); Job Queue obecně (Inactivity Timeout, Enqueue, testy s `Library - Job Queue`) → `bc-al-objects` (5.x14)
   a `bc-al-autotests-domains`; event subscribery a `xRec` → `bc-al-data` (3.9).

## TL;DR — nejtvrdší pravidla (čísla = sekce v souboru)

- **11.8** Integration Table Filter platí **jen Dataverse → BC** (BC → Dataverse dohledává spárovaný záznam bez filtru),
  Filtr tabulky jen BC → Dataverse; filtr skládej typovaně přes `SetView` + `SetRange` + `FilterPageBuilder` round-trip.
  Enum → Choice = Option `Picklist` se stejným pořadím členů + `OptionOrdinalValues`. Vlastní mapování při resetu **vždy
  založ znovu** a smaž `Man. Integration Table Mapping` téhož jména. Testy bez Dataverse přes `@@test@@` a `ClearState()`.
- **11.8c** Obousměrné objednávky: konflikt „vyhrává BC" = `Send Update to Integration` v eventech `OnReset…MappingOnAfterInsert
  FieldsMapping`; stav objednávky řídí jen `OnChangeSalesOrderStatusOnBeforeCompareStatus`; faktura bez spárovaného produktu
  = tichý write-in.
- **11.8d** Po zapnutí synchronizace / *Použít výchozí nastavení synchronizace* jsou úlohy **Ready**; na On Hold je dej
  v `OnAfterResetConfiguration` **i** v `CDS Connection Setup.OnAfterModifyEvent` (SALESPEOPLE vzniká až po resetu). Mazání
  mapování úlohy fronty nemaže → `DeleteTasks` předem. LM ↔ měna Dataverse řeší standard podle relace na `Currency`;
  BC příležitost měnu nemá.
