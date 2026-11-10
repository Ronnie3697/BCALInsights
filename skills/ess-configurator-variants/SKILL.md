---
name: ess-configurator-variants
description: >-
  Essence Configurator (COEBS, prod-ess-configurator-bc) — varianty (BC/AL): identita varianty = množina hodnot
  parametrů (FindExistingVariantWithSameValues, CompareParameterValues), dialog Variant Configuration 63143 a ListPart
  63147 (OK chce všechny parametry, RefreshAfterExternalValueChange, výrobní akce u varianty založené mimo dialog),
  rozdělení řádku a sleva (Sales Line Split Mgt., OnAfterProcessSplitLine), kontrola hodnoty Table Lookup a filter
  groups (ValidateTableLookupValue, GetConditionTableFilter, Item Attr. Filter Mgt.), API konfigurace varianty 66387
  (configurationSessions, applyConfiguration) a Variant Config. Engine COEBS (FindOrCreateVariant, CreateVariant,
  RefreshReusedVariant), Effective Hidden persistovaný, find-or-create local v dialogu do 28.0.29, Kopírovat hodnotu
  z mezi typy (převod polyká chyby), filtr Vyhledání v tabulce dle parametrů (67238, FilterPageBuilder nejde
  rozšířit). Načti u dialogu konfigurace, variant, API konfigurátoru a lookupů parametrů.
user-invocable: true
---

# Essence Configurator — varianty, dialog konfigurace, engine a API

**Zdroj pravdy:** `ess-configurator-variants.md` ve stejném adresáři jako tenhle `SKILL.md`
(adresář skillu = „Base directory" hlášený při načtení; cestu skládej odtud, ne přes `..`).
Tenhle skill je jen wrapper — níže je výcuc stabilních pravidel, detaily, signatury
a diagnostické postupy jsou v souboru. Vyčleněno z `ess-configurator-notes.md` 2026-11-04,
číslování C5, C11, C13, C14, C16 je původní.

## Co udělat

1. **Přečti `ess-configurator-variants.md` z adresáře tohoto skillu celý.**
   Když se Read ořízne, dočti přes `offset` — částečně přečtený soubor
   = nepřečtený.
2. Sesterské skilly: **`ess-configurator`** (systémové parametry, vzorce, strom podmínek,
   diagnostika — C1–C4, C6, C12, C15, C17, C18; úkol přes hodnoty parametrů a vzorce ho
   potřebuje skoro vždy) a `ess-configurator-extensions` (napojení COALU / COZLK — C7–C10).
3. Obecná AL pravidla platí dál: `bc-al-style`, `bc-al-data` (2.6c filter groups),
   `bc-al-ui`, `bc-al-blanket` (5.x21 sleva po změně množství), u netriviální funkčnosti
   `bc-al-autotests`.
4. Změna v produktové appce → release + bump dependency minima v zákaznickém repu.
5. Nový poznatek → do `ess-configurator-variants.md` + commit + push do všech remotů
   (viz skill `bc-al`).

## TL;DR

- **Identita varianty = množina vyplněných hodnot parametrů**
  (`FindExistingVariantWithSameValues` + `CompareParameterValues`). Parametr závislý
  na kontextu prodejního řádku (množství, datum, zákazník) do konfigurace **nepatří** —
  množil by varianty zboží a při změně na řádku by se stejně nepřepočítal. Takové
  veličiny patří do vzorců **akce prodejního řádku**.
- **Dialog kontext prodejního řádku zná** (`SetSalesLineContext` z
  `SalesLineConfigMgt.HandleVariantCodeLookup`) — chybějící hodnota ve slovníku
  parametrů není o nedostupnosti kontextu, ale o tom, že ji tam nikdo nedává.
- ⚠️ **OK v dialogu 63143 chce vyplněné všechny aktivní parametry** — bez eventu
  i `IsHandled`. Featuru, která část parametrů plní mimo dialog, neveď přes OK dialogu.
- **Hodnota zapsaná rozšířením do bufferu 63147** → zavolej
  `RefreshAfterExternalValueChange()`, jinak se dialog na dalším parametru zasekne.
- **Variantu z kódu nezakládej vlastní kopií logiky** — od COEBS 28.0.30 je public
  `Variant Config. Engine COEBS` (`FindOrCreateVariant` / `CreateVariant`), který udělá
  i kusovník a postup (od větve `VariantConfigEngineUnify` i `Effective Hidden`). Kopie
  bez výrobních akcí dá řádku variantu bez kusovníku.
- **`Effective Hidden` je persistovaný** (uložení přes `TransferFields` z bufferu) —
  read-only zobrazení stačí filtrovat, vedle něj nech `Parameter Hidden` kvůli starým
  variantám.
- ⚠️ **Filtry Table Lookup dávej každý do vlastní filter group** (view parametru,
  atributy, hledaná hodnota) — `SetRange` na totéž pole ve stejné skupině filtr
  parametru tiše přepíše.
