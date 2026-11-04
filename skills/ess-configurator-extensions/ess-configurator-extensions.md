# Essence Configurator — napojení zákaznických rozšíření (COALU, COZLK)

> Vyčleněno z `ess-configurator-notes.md` 2026-11-04 (soubor přesáhl 1000 řádků). Číslování sekcí C7–C10 je původní,
> aby fungovaly odkazy „viz Cx" z ostatních souborů. Systémové parametry, vzorce, strom podmínek a diagnostika
> (C1–C4, C6, C12, C15, C17) zůstávají v `ess-configurator-notes.md`, varianty, dialog, engine a API (C5, C11, C13,
> C14, C16) jsou v `ess-configurator-variants.md`.
> Načítej, když řešíš: kusovník konfigurované varianty a pořizovací / jednotkovou cenu prodejního řádku (`Alternative
> Prod. BOM ATEBS`, `Price Variant Code PMALU`, `Cost Mgt. ALU`), pole EM Cutting Plan na řádku kusovníku a komponentě
> VZ (pořadí validace, slučování komponent přes `Length`, jednotka délky, plocha), Parametr A/B z akčního řádku → EPB
> Pricing Matrix (MJ řádku, osy jako Code[50]), eventy kopie konfigurace pro zákaznická data řádků akcí
> (`OnAfterCopyBOMActionLine`, `OnAfterCopySLActionLine`, `OnAfterCopyConfiguration`).
>
> **Obecná AL pravidla platí dál** — `bc-al-style`, `bc-al-data`, `bc-al-ui`, u netriviální funkčnosti `bc-al-autotests`.

## Obsah

- [C7. Kusovník konfigurované varianty a pořizovací cena prodejního řádku (Alumistr)](#c7-kusovník-konfigurované-varianty-a-pořizovací-cena-prodejního-řádku-alumistr)
- [C8. Řádek kusovníku z konfigurátoru a pole EM Cutting Plan (Alumistr)](#c8-řádek-kusovníku-z-konfigurátoru-a-pole-em-cutting-plan-alumistr)
- [C9. MJ z akčního řádku přepíše Pricing Matrix přes Parametr A/B (Alumistr)](#c9-mj-z-akčního-řádku-přepíše-pricing-matrix-přes-parametr-ab-alumistr)
- [C10. Kopie konfigurace — eventy pro zákaznická data řádků akcí](#c10-kopie-konfigurace--eventy-pro-zákaznická-data-řádků-akcí)

---

## C7. Kusovník konfigurované varianty a pořizovací cena prodejního řádku (Alumistr)

Konfigurátor po vytvoření varianty registruje její kusovník do **`Alternative Prod. BOM ATEBS`** (EM Alternative
BOM and Routing) přes `BOM Action Cond. Mgt. COEBS.RegisterAlternativeBOM`: `Item No.` + **`Variant Code`** +
`Location Code` prázdný + `Production BOM No.` + `Default = true`. Na kartě zboží tedy `Production BOM No.` typicky
zůstává prázdné — kdo hledá kusovník varianty jen přes kartu zboží, nenajde nic.

⚠️ **Táž tabulka nese u Alumistra dvě nezávislé osy:** base `Variant Code` (konfigurátor, varianta zboží) a vlastní pole
**`Price Variant Code PMALU`** (Pricing Matrix, cenová varianta ze `Sales Price Var. Code PMEBS` / `Price Worksheet Line`).
Záznam konfigurátoru má `Price Variant Code PMALU` prázdný a naopak. Pozor: EPB Pricing Matrix při výběru cenové varianty
(`Sales Price Var. Code PMEBS` OnValidate) zapíše tentýž kód i do **`Variant Code`** — cenová varianta je technicky `Item Variant`
s příznakem `Price Variant PMEBS`. Lookup „kusovník podle varianty" musí říct, kterou osu myslí — `Calc Cost Mgt. PMALU` původně
bral každý neprázdný kód jako cenovou variantu a hodil chybu *An alternative BOM for item %1 and price variant %2 was not found*
(padal tak i strom kusovníku / výpočet u vyráběné komponenty s obyčejnou variantou — COEBS umí `Variant Code` na řádku kusovníku).
Od PBI 66389 reaguje jen na variantu s příznakem `Price Variant PMEBS` **nebo** s kusovníkem pod `Price Variant Code PMALU`
(obojí, aby se chování cenové varianty nezměnilo ani u neoznačených kódů).

**Pořizovací cena na prodejním řádku (cust-alumistr-bc, PBI 66389, 2026-09-25, docs `66389_…md`):** `Cost Mgt. ALU` u výrobku
hledá nejdřív alternativní kusovník podle `Variant Code` (Default přednost, jen Certified); když ho nenajde, pokračuje beze změny
kusovníkem z karty + eventem `OnAfterSetProdBOMHeaderFilters…` (PMALU cenová varianta, jen při kusovníku na kartě). Na řádek zapisuje
base subscriber **`Sales Line.OnAfterGetUnitCost`** (ne triggery polí — `GetUnitCost` volá i `Location Code`, `Quantity`, `Return Reason
Code`, detail 3.6b v `bc-al-posting.md`) a **jen pro řádek, jehož varianta má vlastní kusovník** — `FixedCost × "Qty. per Unit of Measure"`,
nula nepřepisuje. Cenová varianta a řádek bez varianty zůstaly v PMALU (`Sales Line PMALU`: po `No.` a `Sales Price Var. Code`, zapisuje
i nulu, nenásobí MJ) — uživatel chtěl řešit jen výrobní variantu; sjednocení je otevřený bod v `docs/open-issues/59877_…md`.
Base čte `Alternative Prod. BOM ATEBS` na každém řádku s variantou → `tabledata … = R` v `Alumistr-READ ALU` + závislost base na ATEBS.
⚠️ **Stav kusovníku varianty určuje konfigurace:** `BOM Action Cond. Mgt.` bere status z podmínky kusovníku (`BOM Status`) nebo z
`Configuration Definition."Def. BOM Status"` a **výchozí je *Nový*** — necertifikovaný kusovník výpočet (ani výroba) nevezme, náklad pak
zůstane z karty. Registrace alternativního kusovníku proběhne v `SaveVariantConfiguration` dřív, než lookup vrátí variantu na řádek, takže
hook při `Validate("Variant Code")` kusovník už vidí. Historie: hook žil v PMALU (PR 8371, 2026-03) jen proto, že jediná appka se
závislostí na ATEBS byla Pricing Matrix — ne proto, že by náklad byl cenotvorba.

**Jednotková cena z kusovníku (Alumistr, 2026-09-25):** vlastní `Unit Price` pověšená na **`Sales Line.OnAfterUpdateUnitPrice`** přežije
všechny přepočty base i EPB Pricing Matrix (PMEBS po `UpdateUnitPrice` jen znovu validuje aktuální hodnotu `Validate("Unit Price")` bez
parametru). ⚠️ Konfigurátor ale na akcích prodejního řádku s vzorcem na *Jednotkovou cenu* volá `Validate("Unit Price", vzorec)` **přímo**
(`SL Action Cond. Mgt. COEBS` — `InitNewSalesLineFromAction` pro nové řádky, `ApplyCurrentLineOverrides` pro zdrojový řádek), mimo
`UpdateUnitPrice` → vyhraje, kdo byl poslední: vzorec při vytvoření/přepočtu akcí, vlastní cena po další změně množství / MJ. Když obojí
koexistuje, rozhodni pravidlo (vzorec má přednost = subscriber musí poznat řádek s cenovým vzorcem) — jinak se ceny „přetahují".

## C8. Řádek kusovníku z konfigurátoru a pole EM Cutting Plan (Alumistr)

`Configurator Events COALU.OnBeforeInsertProdBOMLine` přenáší z akčního řádku kusovníku `Qty. of Pcs.` a `Qty. per Piece`
do polí EM Cutting Plan na `Production BOM Line` (tableext `Production BOM Line CUEBS`, repo `prod-em-cuttingPlan-bc`).
Oba jejich `OnValidate` přepočítávají `Quantity per`, **každý jinak**:

- `Qty. of Pcs. CUEBS` → prostý součin: při `Qty. per Unit of Measure = 1` `Quantity per := Qty. per Piece × Qty. of Pcs.`,
  jinak `Quantity per := Qty. of Pcs.`; prázdné `Qty. per Piece` nejdřív nastaví na 1.
- `Qty. per Piece CUEBS` → přes délku: `Quantity per := Length / GetLengthTypeConstant(...)`. Od **EM Cutting Plan 28.0.4**
  (PR 9512, 2026-09-16) vrací `GetLengthTypeConstant(…, false)` u MJ **bez *Length Type*** (m², ks) nulu a trigger se
  **celý přeskočí** — dřív to u takové MJ spadlo na chybě.

⇒ **`Qty. of Pcs.` validuj jako poslední.** V opačném pořadí zůstane `Quantity per` na mezivýsledku prvního triggeru
(`1 × Qty. of Pcs.`), ne na součinu — Qty. per Piece 2,5 × 4 ks dá 4 místo 10. U MJ s typem délky vyjdou obě pořadí stejně.
Nulu nevaliduj (smazala by `Quantity per` místo výchozí 1). Dependency minimum `EM Cutting Plan 28.0.4.0` v app i test
`app.json`, test `QtyOfPcsAndQtyPerPieceGiveQuantityPerWithoutLengthType` (`Config. Ext. Tests ALU`; testovací zboží je
v PCS bez typu délky, takže starý kód spolehlivě chytí). Zdroj: cust-alumistr-bc, větev `ConfiguratorFormulaCancel`
(2026-09-22); úprava vznikla 2026-09-16 při analýze na BC-TEST2, kde běžel lokální build Cutting Planu (C6 v `ess-configurator-notes.md`).

⚠️ **„Někdy se komponenty VZ sloučí, někdy ne" = `Length` z CUEBS ve filtru slučování.** Base `Calculate Prod. Order.TransferBOMProcessItem`
hledá existující komponentu přes `Prod. Order Component.SetFilterFromProdBOMLine` (Item, Variant, Routing Link, Position 1–3,
**Length**, Width, Weight, Depth, MJ, Calc. Formula) a při shodě jen `Validate("Quantity per", stará + BOMLine."Quantity per")`.
Cutting Plan ale vložené komponentě přepíše `Length := Qty. per Piece × c`, `Quantity per := Qty. of Pcs.` (kusy), zatímco řádek
kusovníku s MJ qty-per 1 má `Length = Qty. per Piece × Qty. of Pcs. × c` a `Quantity per` v metrech (`c` = `GetLengthTypeConstant`:
`Unit of Measure."Length Type CUEBS"` × `Manufacturing Setup."Optimaliz. Length Type CUEBS"`). Sloučí se tedy jen řádek s 1 ks a stejnou
délkou jako první — a **špatně**: 1 ks + 4 (m) = `Quantity per` 5 „kusů", `Qty. of Pcs.` zůstane 1, `Note/Color ALU` z druhého řádku se
ztratí (subscribery jen v Insert větvi). Kusovník vzniklý s jiným `c` než VZ (změna typu délky MJ mezi tím) má Length v jiných jednotkách,
filtr nesedne a nesloučí se nic — proto „jednou ano, jednou ne". NMEBS / konfigurátor / COALU nic neslučují, subscriber na
`OnAfterSetFilterFromProdBOMLine` / `OnAfterProdOrderCompFilter` / `OnBeforeProdOrderCompModify` nemá nikdo. Diagnostika: page inspector
`Length` na řádku kusovníku vs. na komponentě + `SystemModifiedAt` MJ. (2026-10-07, Alumistr BC-TEST: MJ M přepnutá m → mm 30. 9.,
kusovník 0106 z rána 30. 9. má Length 3 500, 0107/0116 mají 4 → VZ 25-0000538 nesloučená, 544/548 sloučené na 5.)
Alumistr (větev `ProdOrderCompMergeNoteColor`): `Event Subscribers ALU` na `OnAfterSetFilterFromProdBOMLine` přidá `SetRange` na
`Note ALU` a **efektivní** `Color ALU` (barva kusovníku, jinak řádku VZ — stejná `GetComponentColor` jako při vzniku komponenty);
řádek VZ čte přes `GetRangeMin` filtrů Status / Prod. Order No. / Prod. Order Line No., které base nastaví před voláním. Holý filtr
na barvu kusovníku by shodné řádky bez barvy na barevné VZ nikdy nesloučil. Sčítání kusů při sloučení opravuje EM Cutting Plan.

⚠️ **`Length` komponenty VZ = délka jednoho kusu v jednotce optimalizace z *Nastavení výroby*, a jen k okamžiku naplnění.**
`Prod. Order Component CUEBS` (tableext ř. ~117) dává `Validate(Length, "Qty. per Piece CUEBS" × GetLengthTypeConstant(ItemUoM."Length
Type CUEBS"))`; konstanta převádí typ délky MJ zboží na `Manufacturing Setup."Optimaliz. Length Type CUEBS"` (m→m 1, m→mm 1000,
mm→m 0,001). Kdo chce délku v mm (CNC soubor), musí počítat s tím, že jednotku určuje setup, ne MJ. **Změna setupu stávající
komponenty nepřepočítá** — přepočet běží jen s `Qty. per Piece`, takže VZ vzniklé před změnou drží starou jednotku, dokud se
neaktualizují. Ověřeno čtením Alumistr BC-TEST 2026-10-27: setup `mm` od 2026-10-22 08:35 (`SystemModifiedAt`), MJ `M` profilu `m`,
komponenty VZ z 2026-10-07 mají `Length` 3,5 / 4 (metry). Diagnostika: page inspector na komponentě (`Length (40)`, `SystemCreatedAt`)
a na *Nastavení výroby* (`Optimaliz. Length Type CUEBS`, `SystemModifiedAt`) — sloupec *Délka* je v gridu komponent skrytý. Tisk CNC
datové věty (COALU, 62959) bere od 2026-10-27 délku právě odsud (komponenta s `Note ALU` = pozice).

⚠️ **EM Cutting Plan od PR 9737 (#66996, master 2026-10-14, 28.0.6.1) počítá plochu na komponentě VZ dvakrát.**
`Prod. Order Component CUEBS.CalcQtyFieldsCUEBS` dřív nastavoval `Quantity per := Qty. of Pcs.` (kusy) a `Qty. per Unit of Measure :=
Qty. per Piece` (m² na kus). Nově dává `Quantity per := Qty. of Pcs. × Qty. per Piece` (m² celkem), ale `Qty. per Unit of Measure` nechal
na m² na kus, takže `Expected Qty. (Base)` = m² × m²/kus. K tomu `Item."Rounding Precision" = 1` (sklo v M2) zaokrouhlí `Expected
Quantity` **nahoru na celé m²** (`RoundExpectedQuantity`) → 2 ks × 1,455 m²: `Quantity per` 2,91 → `Expected Quantity` 3 → báze
3 × 1,455 = **4,365 m²** místo 2,91. U 1 ks pod 1 m² to vyjde náhodou správně (ceil(0,982) = 1 → 0,982), proto se to schová; 1 ks nad
1 m² už ne (`Quantity per` 1,486 → `Expected Quantity` 2 → báze 2,972). Špatná báze teče
do dostupnosti, MRP, spotřeby, nákladu i do sešitu požadavků: EM MRP Replenishment (OREBS) bere `Remaining Qty. (Base)` komponenty
(`min(nedostatek, Remaining Qty. (Base))`) a zapíše ho do `Quantity` řádku sešitu v základní MJ. Starší VZ (model „kusy") mají
`Quantity per` = `Qty. of Pcs.` a bázi správnou. Diagnostika: inspektor na komponentě (`Quantity per`, `Qty. per Unit of Measure`,
`Expected Quantity`, `Expected Qty. (Base)`, `Qty. of Pcs. / Qty. per Piece CUEBS`) proti řádku kusovníku a `Rounding Precision` na
kartě zboží. Vodítko: na tomtéž řádku komponenty si oba „základní" sloupce odporují — `Quantity (Base)` = `Quantity per` (správně;
zřejmě spočítané s faktorem 1, protože `CalcQtyFieldsCUEBS` validuje `Quantity per` dřív než `Qty. per Unit of Measure`), `Expected` / `Remaining Qty. (Base)` = zaokrouhlené
`Expected Quantity` × m²/kus. Do sešitu jde to druhé. Oprava patří do prod-em-cuttingPlan-bc. (2026-11-02, Alumistr BC-TEST2 VZ
25-0000619 s EM Cutting Plan Dev 28.0.6.1; potvrzeno na BC-TEST VZ 25-0000630 s PTE 28.0.8.0: 1 / 1 / 2 ks à 1,686 / 1,486 / 1,486 m²
→ sešit 3,372 / 2,972 / 4,458 místo 1,686 / 1,486 / 2,972.)

## C9. MJ z akčního řádku přepíše Pricing Matrix přes Parametr A/B (Alumistr)

Base `InitNewSalesLineFromAction` MJ z `SL Action Line."Unit of Measure Code"` validuje správně (`ApplyItemSpecificFields`,
až po `Validate("No.")`). Když na podřízeném řádku skončí jiná MJ, hledej v **`OnBeforeModifyNewSalesLineFromAction`**:
`Configurator Events COALU` (od PR 9480, 2026-09-14) přenáší na **každý** vytvořený řádek `Parameter A/B COALU` akčního
řádku (statika nebo vzorec) přes `Validate("Parameter A/B PMEBS")` → `Sales Line PMEBS.ValidateParametersPMEBS` →
`Pricing Matrix Mgt. PMEBS.ValidateAndUpdateUoM` → **`Validate("Unit of Measure Code", <matricová MJ>)`**.

⚠️ **Pricing Matrix nezná „nematicové" zboží.** S `Module Enabled PMEBS` projde enginem každé zboží s oběma parametry ≠ 0.
Rounding **Up** (`FindUoMForRoundingUp`) po neúspěchu „≥ A a ≥ B" padá do větve „největší pod požadavkem" (`< A`, `< B`) — a tu
splní **každá MJ bez os (0/0)**. Při shodě vyhraje první podle PK (`Item No., Code`) → abecedně první MJ zboží. Alumistr BC-TEST2
(konfigurace 0066, PO2500209): sklo `GL-12040000-04-TR` má základní/prodejní MJ `M2`, MJ `KS` i `M2` s nulovou šířkou/výškou
(osy = `Width`/`Height`, pole 7301/7302), vzorce Parametr A/B = rozměr skla → řádek skončil `KS` s A = 1000, B = 750.
Kdyby žádná MJ nevyhověla, `ValidateAndUpdateUoM` by zboží **založil rastrovou MJ** `B/A` (`CreateRasterUOM`).

**Oprava v COALU (větev `SLActionLineUoM_66358`, 2026-09-23):** `ValidateParametersKeepingTexts` (sdílí ji akční i aktuální
řádek) validuje A/B jen u zboží, které má aspoň jednu MJ s oběma osami ≠ 0 (`HasMatrixUnitOfMeasure` přes veřejné
`Features PMEBS.GetParameterA/BFieldNo` + `Pricing Matrix Mgt. PMEBS.AxisValue`); ostatnímu zboží A/B jen přiřadí a MJ nechá.
Pravidlo „akční řádek má vyplněnou MJ" nejde použít — `SL Action Line."No."` OnValidate MJ doplňuje sám z karty zboží.

**Systémová oprava v PMEBS (PR 9573, release **28.0.6** = build 28454, 2026-09-24):** `ValidateAndUpdateUoM`
zboží bez maticové MJ hned vrátí `false` (žádná náhradní MJ, žádná `CreateRasterUOM`) a `FindMatrixUoM` hledá jen mezi MJ
s oběma osami ≠ 0 (filtr ve vlastní filter group — 2.6c v `bc-al-data.md`), takže fallback `< A, < B` už MJ 0/0 nesebere;
fallback na `Sales UoM` zůstal. Nová **public `Pricing Matrix Mgt. PMEBS.HasMatrixUnitOfMeasure(ItemNo)`** = stejná logika
jako lokální kopie v COALU. V cust-alumistr-bc (větev `PricingMatrixDependency_66358`) minimum EPB Pricing Matrix `28.0.6.0`
ve **všech čtyřech** `app.json` (COALU + PMALU, app + test) a zkratka z PR 9567 + lokální `HasMatrixUnitOfMeasure` v COALU
**odstraněny** — `Validate("Parameter A/B PMEBS")` u zboží bez maticové MJ teď v matici nic nedělá, výsledek stejný; COALU testy
z PR 9567 zůstaly a ověřují chování matice přes konfigurátor. Vedlejší efekt: první rastrovou MJ nového zboží už nezaloží
řádek dokladu (dřív u zboží bez `Sales UoM`), jen import matice / ruční Item UoM. A nový rastr z řádku (`CreateRasterUOM`
po prázdném výsledku hledání = maticové zboží bez `Sales UoM`) jen při zaokrouhlení **Equal** — bez toho by po vyřazení MJ 0/0
zaokrouhlení Dolů pod všemi rastry zakládalo rastry přesně pro zadaný rozměr (bez ceny); Up/Down bez nálezu MJ řádku nechají.
Pozor na obrácenou logiku testu: `…RoundingDownDoesNotCreateRaster` na původním masteru **projde** (vyhrála základní MJ 0/0 =
MJ řádku), padá až na mezistavu bez omezení na Equal — test proti regresi opravy, ne proti původní chybě. Dokumentace `prod-epb-pricingMatrix-bc/docs/66358 - …md`,
`cust-alumistr-bc/docs/66358_MJ-akcniho-radku-mimo-cenovou-matici.md`.

**Od PMEBS PBI 67458 (větev `67458_ParametersCode50`, 2026-11-03, zatím nevydáno) jsou osy kódy:** nová pole
`Parameter A/B Value PMEBS` (Code[50], 65505/65506), stará Decimal `Parameter A/B PMEBS` jsou `ObsoleteState = Pending` a na
prodejním řádku jen přeposílají hodnotu do nových polí (`FormatAxisValue`) — starý COALU tedy s novým PMEBS funguje, opačně ne.
Napojení v COALU / PMALU (cust-alumistr-bc, stejnojmenná větev): číslo z konfigurátoru → `Validate("Parameter A/B Value PMEBS",
PricingMatrixMgt.FormatAxisValue(x))` (invariantně, `0` → `''`); OnValidate hodnotu převede do tvaru pole osy
(`CheckAndNormalizeParameterA/BValue` → `CanonicalAxisValue`: číslo invariantně, Option/Enum **názvem i z čísla**, záporné číslo =
Error). Přímé přiřazení (`:=`, např. komponenta → řádek sešitu) kanonizaci obchází — u číselných os (Width/Height) to vyjde stejně,
u Option/Enum osy by `'1'` nesedělo s MJ. Zpět kód → číslo (číselná pole `Parameter A/B PMALU` na nákupním řádku) přes
`TryGetAxisNumber` (vrací `false` a `Number = 0` u kategorie, tolerantní k mezerám / NBSP / čárce). Minimum `EPB Pricing Matrix`
v obou appkách + testech až na **první publikovanou** verzi s 67458 (lokální `28.0.7.x` v `.alpackages` jsou dev buildy, 7.11
v `bc-al-build.md`); nasazovat spolu. (Code review 2026-11-04, cust-alumistr-bc 2f136c0 nad PMEBS ff04061.)

Diagnostika: page inspector na řádku prodeje (filtr „Parameter") — nenulové `Parameter A/B PMEBS` na řádku, kde čekáš jinou MJ,
= tahle cesta. Setup matice je na `Sales & Receivables Setup` (`UoM Rounding PMEBS`, `Parameter A/B Field No. PMEBS`,
`Use UoM Parameter Fields PMEBS`). (2026-09-23, PBI 66358 analýza; zdroje cust-alumistr-bc master aa320d2, prod-epb-pricingMatrix-bc
master, nasazeno COALU 28.0.20.3 / PMEBS 28.0.5.0 / COEBS 28.0.22.2.)

## C10. Kopie konfigurace — eventy pro zákaznická data řádků akcí

`Configuration Copy Mgt. COEBS` (63141) dává rozšířením k 28.0.26 jen dva eventy:

- **`OnAfterCopyBOMActionLine(var NewLine; var SourceLine)`** — po každém řádku akce kusovníku, v **obou** cestách
  (kopie celé konfigurace `CopyBOMActionLines` i kopie jedné akce v rámci konfigurace `CopyBOMActionLinesForCondition`),
  bez mapy parametrů. Vzor `Configurator Events COALU`.
- **`OnAfterCopyConfiguration(SourceConfigNo; NewConfigNo; var ParamLineNoMapping)`** — jen na konci kopie **celé**
  konfigurace; mapa parametrů ano, mapa podmínek a řádků akcí **ne** (`SLCondLineNoMapping` / `SLLineNoMapping` jsou
  lokální proměnné). Vzor `CNC Action Mgt. COALU`.
- ⚠️ **Řádky akcí prodejního řádku a postupu event nemají** a kopie jedné SL akce (`CopySLAction`) nevolá žádný.
  Zákaznická tabulka klíčovaná řádkem SL akce (`Configuration No.`, `Condition Line No.`, `Line No.` — COZLK
  `SL Act. Taken Param COZLK`, task 65364) se kopií tiše nepřenese. Rekonstruovat mapu řádků v `OnAfterCopyConfiguration`
  z pořadí (podmínky 10000, 20000… podle PK zdroje, řádky 10000… per podmínka) by šlo, ale opisuje interní číslování COEBS
  a na `CopySLAction` nepomůže → správně nový event v COEBS hned za `NewLine.Insert(true)` v `CopySLActionLines`
  i `CopySLActionLinesForCondition` (návrh `OnAfterCopySLActionLine(var NewLine; var SourceLine; var ParamLineNoMapping)`).
  Subscriber pozná kopii v rámci téže konfigurace podle `NewLine."Configuration No." = SourceLine."Configuration No."`
  (parametry beze změny), ne podle prázdné mapy.
- **Stav od větve `65364_SLActionLineCopyEvent`** (commit 599429a, čeká na PR): `OnAfterCopySLActionLine(var NewLine;
  SourceLine; var ParamLineNoMapping)` přidán, v obou cestách **před** kopií vzorců a textových vzorců řádku. `SourceLine`
  po review **bez `var`** — je to kurzor kopírovací smyčky (`SetRange` + `FindSet`/`Next`), subscriber by ho `SetRange`/`Find`
  rozbil; `OnAfterCopyBOMActionLine` ho má s `var` (starší, nechán kvůli kompatibilitě). ⚠️ **Vzorce nejsou u eventu zkopírované ani
  u `OnAfterCopyBOMActionLine` při kopii celé konfigurace** — `CopyBOMActionLines` ho volá hned po `Insert`, vzorce
  (`CopyBOMQtyFormulaLines`, `CopyActionTextFormulaLines`) jdou až dalším průchodem; jen `CopyBOMActionLinesForCondition`
  (kopie jedné BOM akce) ho volá až po vzorcích. Subscriber, který čte vzorce nového řádku, tedy v kopii celé konfigurace
  nic nenajde. (Code review 2026-09-29 — dokumentace větve tvrdila „už i s jeho vzorci".)
- **TODO v COZLK (cust-zlomek-bc) po vydání COEBS s větví `65364_SLActionLineCopyEvent`** — plný postup je v
  `prod-ess-configurator-bc/docs/65364 - Configurator - Event po kopii řádku SL akce a kontrola kódu Vyhledávání.md`,
  sekce *Navazující úpravy v COZLK*. Ve zkratce: (1) minimum `Essence Configurator` podle verze **na feedu** v
  `configuratorExtension/app` i `/test`; (2) subscriber `OnAfterCopySLActionLine` (`SourceLine` bez `var`) kopíruje
  `SL Act. Taken Param COZLK` — všechna 4 pole PK z `NewLine`, `Main Parameter Line No.` přes mapu jen při jiné
  `Configuration No.` (chybí v mapě → přeskočit), `Nested *` beze změny; (3) smazat `Nested Cfg Runtime
  COZLK.TableLookupValueExists` + její volání v `TryValidateParameterValue` (base to umí; rozdíl: neplatný filtr
  base vynechá); (4) testy kopie celé konfigurace (přečíslovaný parametr) a `CopySLAction`; (5) aktualizovat
  `docs/65364 - VYR_24 …(COZLK).md` (⚠️ o kopii a o nefunkční kontrole v 28.0.26).
  **Event i oprava kontroly Vyhledávání jsou v COEBS 28.0.28** (build 28533, master c45bcc2); 28.0.27 (build 28532) spadl
  a na feedu není → minimum `28.0.28.0`. Body (1)–(5) udělané na větvi `65364_CopyTakenParams` (review 2026-09-29).
- Mazání je v pořádku: `Configuration Definition.OnDelete` maže podmínky přes `DeleteAll(true)`, takže `OnAfterDeleteEvent`
  na `SL Action Condition/Line COEBS` běží per záznam a kaskáda v rozšíření (COZLK `Configurator Events`) data uklidí.
- ⚠️ **Smazání parametru odkazy v rozšířeních neuklidí a jeho `Line No.` se recykluje.** `Configuration Parameter COEBS.OnDelete`
  maže jen hodnoty, podmínky a vzorce parametru; `OnInsert` čísluje `FindLast + 10000` → nový parametr na konci konfigurace
  dostane `Line No.` smazaného posledního. Zákaznická tabulka s odkazem na `Parameter Line No.` (COZLK `SL Act. Taken Param` —
  hlavní i vnořený parametr) po smazání drží osiřelý odkaz, který se **tiše chytí nového parametru**. Kopie celé konfigurace
  ho zahodí sama (mapa parametrů ho nezná), kopie SL akce v rámci konfigurace ho zkopíruje. Úklid patří do subscriberu
  `OnAfterDeleteEvent` na `Configuration Parameter COEBS` (obě strany odkazu). (Code review 2026-09-29, cust-zlomek-bc.)
  → **Řešeno v tasku 66711** jinak než úklidem: `Line No.` se nerecykluje (čítač) a použitý parametr nejde smazat, rozšíření
  hlásí své odkazy eventem `OnCollectParameterReferences` — detail C15 v `ess-configurator-notes.md`.

(2026-09-24, analýza plánu 65364 nad prod-ess-configurator-bc master 79fc306.)
