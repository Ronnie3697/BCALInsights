---
name: ess-configurator-extensions
description: >-
  Essence Configurator — napojení zákaznických rozšíření Alumistr COALU / Zlomek COZLK na další moduly (BC/AL):
  kusovník konfigurované varianty v Alternative Prod. BOM ATEBS a pořizovací / jednotková cena prodejního řádku
  (Variant Code vs Price Variant Code PMALU, Cost Mgt. ALU, OnAfterGetUnitCost, OnAfterUpdateUnitPrice vs cenový
  vzorec akce, práce z TNG: Alternative Routing ATEBS, TimeFactor, Ceny subdodavatele), pole EM Cutting Plan na řádku kusovníku a komponentě VZ (Qty. of Pcs. validuj poslední, slučování
  komponent přes Length, Length v jednotce optimalizace, plocha započtená dvakrát), Parametr A/B akčního řádku →
  EPB Pricing Matrix (ValidateAndUpdateUoM přepíše MJ, HasMatrixUnitOfMeasure, osy jako Code[50] Parameter A/B
  Value PMEBS, FormatAxisValue / TryGetAxisNumber), eventy kopie konfigurace pro zákaznická data řádků akcí
  (OnAfterCopyBOMActionLine, OnAfterCopySLActionLine, OnAfterCopyConfiguration). Načti u COALU / COZLK,
  kusovníku z konfigurátoru, EM Cutting Plan a Pricing Matrix.
user-invocable: true
---

# Essence Configurator — napojení zákaznických rozšíření (COALU, COZLK)

**Zdroj pravdy:** `ess-configurator-extensions.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`).
Tenhle skill je jen wrapper — níže je výcuc stabilních pravidel, detaily, signatury
a diagnostické postupy jsou v souboru. Vyčleněno z `ess-configurator-notes.md` 2026-11-04,
číslování C7–C10 je původní.

Repa: `cust-alumistr-bc` (`configuratorExtension` = **COALU**, `pricingMatrixExtension` = **PMALU**),
`cust-zlomek-bc` (**COZLK**); moduly `prod-em-cuttingPlan-bc` (CUEBS), `prod-epb-pricingMatrix-bc` (PMEBS),
EM Alternative BOM and Routing (ATEBS).

## Co udělat

1. **Přečti `ess-configurator-extensions.md` z adresáře tohoto skillu celý.**
   Když se Read ořízne, dočti přes `offset` — částečně přečtený soubor
   = nepřečtený.
2. Sesterské skilly: **`ess-configurator`** (systémové parametry, vzorce, strom podmínek,
   odkazy na parametry — C1–C4, C6, C12, C15, C17) a `ess-configurator-variants`
   (varianty, dialog, engine, API — C5, C11, C13, C14, C16).
3. Obecná AL pravidla platí dál: `bc-al-style`, `bc-al-posting` (3.6b `Validate("No.")` →
   `Init()`, pořizovací cena přes `OnAfterGetUnitCost`), `bc-al-objects` (pole kusovníku →
   komponenta VZ), `bc-al-build` (7.11 minima dependency), u netriviální funkčnosti
   `bc-al-autotests`.
4. Nový poznatek → do `ess-configurator-extensions.md` + commit + push do všech remotů
   (viz skill `bc-al`).

## TL;DR

- **Kusovník konfigurované varianty je v `Alternative Prod. BOM ATEBS`** (Item + `Variant Code`,
  Default), ne na kartě zboží. Tatáž tabulka nese i cenovou variantu `Price Variant Code PMALU`
  → lookup „kusovník podle varianty" musí říct, kterou osu myslí.
- **Vlastní cena řádku vs. cenový vzorec konfigurátoru:** `Sales Line.OnAfterUpdateUnitPrice`
  přežije přepočty base i Pricing Matrix, ale vzorec akce validuje `Unit Price` přímo — bez
  pravidla přednosti se ceny „přetahují".
- **EM Cutting Plan: `Qty. of Pcs.` validuj jako poslední** (po `Qty. per Piece`), nulu
  nevaliduj — jinak `Quantity per` zůstane na mezivýsledku.
- ⚠️ **Parametr A/B na prodejním řádku jde přes EPB Pricing Matrix a může přepsat MJ řádku**
  (`ValidateAndUpdateUoM`); od PMEBS 28.0.6 jen u zboží s maticovou MJ.
- **Kopie konfigurace dává rozšířením jen tři eventy** (`OnAfterCopyBOMActionLine`,
  `OnAfterCopySLActionLine`, `OnAfterCopyConfiguration` s mapou parametrů); vzorce nového
  řádku při kopii celé konfigurace v eventu ještě nejsou. Odkazy na parametry v datech
  rozšíření remapuj jako base `TryRemapParamLineNo` (0 a záporná čísla beze změny;
  detail C15 v `ess-configurator-notes.md`).
