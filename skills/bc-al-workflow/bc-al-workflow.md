# BC/AL poznámky — Lokalizace, dokumentace & verifikace

> Část rozděleného `bc-al-notes.md` (rozsekáno 2026-06-23; archiv: `bc-al-notes.archived-2026-06-23.md`).
> Načítej, když řešíš: XLIFF/překlady (NAB AL Tools), dokumentaci requirementů, co číst před editem AL objektu, analyzery (AA/CA/PTE/LC).
>
> Původní číslování sekcí zachováno kvůli cross-referencím „viz X.Y".
> Pozn.: sekci 6 byl v původním souboru chybějící `## 6` nadpis (jen v Obsahu) — zde doplněn.
> **Sekce 7 žije mimo tento soubor:** 7.1–7.10 (nástroje, git/PR, Azure DevOps) od 2026-08-03 v `bc-al-tools.md`,
> 7.11–7.19 (NuGet dependencies, CI build, deploy) od 2026-09-01 v `bc-al-build.md` — odkazy „viz 7.x" hledej tam.

Obsahuje:
- **6.** Lokalizace a CZ↔EN
- **8.** Dokumentace requirements (PBI/Task → MD)
- **9.** Před úpravou AL objektu — co si přečíst
- **12.** Verifikace a analyzery (AA / CA / PTE / LC)

## 6. Lokalizace a CZ↔EN

### 6.1 NAB AL Tools — workflow překladu XLIFF

V hodně AL repech sedí na překladech extension **NAB AL Tools** (VS Code).
Po `Refresh XLIFF` ti tool označí všechny chybějící nebo nejisté překlady
zvláštním prefixem v `<target>`. Pojmenování:

- **`[NAB: NOT TRANSLATED]`** — pro string nemá tool žádný kandidát z base
  appky / paměti překladů. Musíš dopsat ručně.
- **`[NAB: SUGGESTION]<návrh>`** — tool našel jeden nebo víc kandidátů
  (typicky z base appky, kde už existuje stejný source string). Trans-unit
  pak může mít **víc `<target>` řádků pod sebou**, každý s vlastním návrhem.

```xml
<trans-unit id="...">
  <source>Specifies the Item No. of the warehouse receipt line.</source>
  <target>[NAB: SUGGESTION]Určuje číslo zboží řádku skladové příjemky.</target>
  <target>[NAB: SUGGESTION]Určuje číslo položky řádku skladové příjemky.</target>
  <note from="Developer" annotates="general" priority="2"></note>
  <note from="NAB AL Tool Refresh Xlf" annotates="general" priority="3">Suggested translation inserted.</note>
  <note from="Xliff Generator" annotates="general" priority="3">...</note>
</trans-unit>
```

**Pravidla úpravy po `Refresh XLIFF`:**

1. **Vždy nech jen jeden `<target>`** — i když měl tool víc návrhů. XLIFF
   spec sice víc target tagů povoluje, ale BC kompilátor + runtime používají
   jen první a víc tagů jen mate. Vyber nejvhodnější návrh, nebo si vlož
   svůj překlad.
2. **Smaž prefix `[NAB: NOT TRANSLATED]` / `[NAB: SUGGESTION]`** úplně.
   Cokoliv co začíná `[NAB:` je pro tool flag "tohle ještě není hotovo" —
   po tvém zásahu tam patří jen čistý překlad.
3. **Note `NAB AL Tool Refresh Xlf`** můžeš nechat (tool si ho při příštím
   refreshi přepíše), ale klidně i smazat — nemá vliv na build.
4. **Note `Xliff Generator`** **nikdy nemaž** — drží kontext (object/field/
   property), který je důležitý pro jiné překladatele.

**Hromadné překlady (desítky+ míst):** Ručně editovat unit po unit je
zdlouhavé. Praktická cesta — Python skript s mapou `source_text →
překlad`, který:

- pro každou `<trans-unit>` najde `<source>`,
- pokud target obsahuje `[NAB:`, vyhodí všechny `<target>` řádky a vloží
  jeden s překladem ze source mapy,
- duplicitní source stringy v různých kontextech pokrývá jednou položkou
  v mapě (caption "Quantity" je vždy "Množství", ať je na poli nebo na
  page kontrolu).

Po skriptu **zkompiluj** (`alc.exe`, viz 7.1) — chytíš tím poškozenou
strukturu (escape `&` → `&amp;`, neuzavřený tag, špatná entita) hned, ne
až při deploy.

**Při překladu drž BC CZ konvence z tabulky CZ ↔ EN** (sekce 5.z4
v `bc-al-objects.md`) — zejména `Bin =
Přihrádka` (ne "Koš"), `Item = Zboží` (ne "Položka"), `Lot = Šarže`. Tool
sice nabídne `[NAB: SUGGESTION]Sériové č.` jako kratší variantu, ale base
app cs-CZ používá `Sériové číslo` v plném tvaru — drž to.

**⚠️ Výpis `<target>` z `.cs-CZ.xlf` přes `print()` v Bash toolu rozbije diakritiku.** Stdout Git Bash
konzole na Windows jede v cp1250/cp852, takže `python -c "... print(target)"` vrátí `Nastaven� Essence
Kiosku` — text vypadá poškozeně, i když soubor je v pořádku (ověř `open(p, encoding='utf-8-sig')`).
Nesnaž se to opravit reencodingem výstupu: extrahované dvojice **zapiš do souboru v UTF-8**
(`open(out,'w',encoding='utf-8')`, klidně do scratchpadu) a přečti ho **Read toolem** — ten UTF-8 zvládá.
Platí pro jakýkoli český text tažený z repa přes Bash (Labely, `Description`, MD dokumentace).
Hodí se při psaní uživatelské příručky, kde se terminologie bere z XLIFF (8.1). (2026-09-21, prod-em-kiosk-bc)

### 6.2 XLIFF trans-unit ID — hash algoritmus (ruční doplnění unitů bez rebuildu)

ID v `trans-unit` (`Table 66836948 - Field 922357686 - Property 2879900210`)
jsou hashe **jmen** elementů (ne textů). Algoritmus (ověřeno reverse-engineeringem
proti reálným .g.xlf hodnotám, zdroj: github.com/microsoft/AL issue #4361):
**FNV-1a 32-bit přes UTF-16LE bajty jména + offset 2147483647 (mod 2^32)**.

```python
def alhash(name: str) -> int:
    h = 0x811c9dc5
    for b in name.encode("utf-16-le"):
        h = ((h ^ b) * 16777619) % 2**32
    return (h + 2147483647) % 2**32
```

- Vstup je čisté jméno elementu: `alhash("Caption")` = 2879900210,
  `alhash("ToolTip")` = 1295455071, `alhash("CNC Macro COALU")` = 66836948.
- ID se skládá z `<Typ> <hash(jméno)>` po cestě od objektu k labelu:
  `Table X - Field Y - Property Z`. Source text se nehashuje — změna
  ToolTip textu ID nemění, **rename pole/objektu ano** (starý unit osiří).
- Use case: přidáváš pole a chceš rovnou doplnit překlad do `.cs-CZ.xlf`
  bez čekání na build + NAB Refresh — spočítej hash jména pole a napiš
  trans-unit ručně se správným ID. Refresh ho pak už jen potvrdí.

> **⚠️ Výjimka — víc extensionů na stejný target objekt.** Algoritmus výše
> platí pro jména elementů, ALE když **víc tableextension (nebo víc
> pageextension) cílí na STEJNOU base tabulku/page**, kompilátor pro 2.+
> extension **NEgeneruje** top-level objektový hash jako čistý
> `alhash(jméno)` — disambiguuje ho na jinou hodnotu (Field/Property/Control
> hashe sedí dál). Historicky to byl MS bug
> [microsoft/AL#7790](https://github.com/microsoft/AL/issues/7790)
> (na BC 24.3 se za běhu přeložil jen první extension); **MS to opravil
> server-side v platformě `26.0.33212.0`**, takže na **BC 26+ runtime
> překlady fungují** a kolizní ID správně spáruje.
>
> **Dopad na linter:** **`LC0091`** ("ToolTip/Caption missing a translation")
> si ID rekonstruuje jako `alhash(jméno)` a o disambiguaci neví → na 2.+
> extension dělá **false positive**, i když překlad v `.cs-CZ.xlf` je a runtime
> ho používá (`info` severity → Essence build neblokuje). **NESAHAT na ID v
> `.cs-CZ.xlf`** kvůli linteru — přepis na alhash hodnotu rozbije runtime
> párování (čeština zmizí). Správná hodnota = ta, co `alc` generuje do
> `Translations/*.g.xlf`; ověřuj proti němu, ne přepočtem hashe.

### 6.3 Přeložený `Error`/`Message`/`Label` + `%n` placeholder — musíš updatnout i XLF

Když u **přeloženého** labelu (objekt s `TranslationFile` featurou + locale `.xlf`)
změníš **zdrojový text** — typicky přidáš `%1`/`%2` pro víc kontextu (status, ID,
detail) — **nestačí změnit jen `.al`**. V cílové lokalizaci runtime bere **`<target>`
z `.xlf`**, párovaný přes **trans-unit ID** (hash *jmen* objektu/labelu, viz 6.2).
Změna zdrojového textu **ID nemění** → starý `<target>` (bez placeholderů) **zůstane**
a runtime ho použije. Výsledek: appka dál ukazuje **starou hlášku bez doplněných
argumentů**, i když `Error(NewLabel, arg1, arg2)` ty argumenty předává (chybějící
`%n` v targetu se prostě nevyplní, extra argumenty se zahodí).

**Příznak:** error/message vypadá jako „nezměněný" po rebuildu, ačkoli jsi label v kódu
upravil — a jen v lokalizovaném klientu (CZ), v EN by se nová verze ukázala.

**Fix:** uprav v `.cs-CZ.xlf` (a každé další locale) jak `<source>`, tak `<target>`
daného trans-unitu, ať nesou stejné `%n`:

```xml
<!-- .al: CreateErr: Label 'Category could not be created (HTTP %1). Response: %2'; -->
<source>Category could not be created (HTTP %1). Response: %2</source>
<target>Kategorii se nepodařilo vytvořit (HTTP %1). Odpověď: %2</target>
```

- `<source>` srovnej se zdrojovým labelem — jinak build/NAB hlásí source-mismatch.
- Pak **rebuild** (label resolving je compile-time). Historické záznamy (např. řádky
  v audit logu) drží text z doby zápisu — rich verze naskočí až u nových.
- Stejná past platí pro `Message`, `Confirm`, `FieldError`, `StrSubstNo` nad Labelem.
- Zachyceno: prod-ess-dotykackaConnector-bc (červen 2026) — obohacení chybové hlášky
  o HTTP status z API se v CZ klientu neprojevilo, dokud se neupravil `<target>` v XLF.

### 6.4 Merge XLF souboru → tiché duplicitní trans-unity (`AL0479`)

Když se `.cs-CZ.xlf` mění na **obou stranách merge** (typicky obě větve přidaly překlady
pro nová pole), git slučuje čistě textově a **nemá ponětí o XML sémantice**. Když obě
strany přidaly **ten samý trans-unit**, ale na **jiné místo v souboru**, git je vesele
vloží **oba** — bez konfliktu, bez varování. `git status` je čistý, XML je well-formed,
diff vypadá nevinně.

Odhalí to až kompilace:

```
warning AL0479: There must be only one translation item for each ID.
```

- **Fix:** najdi duplicitní `trans-unit id="…"` a nech **jeden** výskyt (obsahově bývají
  identické; ponech ten na pozici masteru, ať se soubor dál nerozjíždí).
- **Pravidlo:** po **každém** mergi, který sáhl na `.xlf`, **zkompiluj** — konflikty
  vyřešené „ručně a správně" nic negarantují, tahle škoda vzniká *mimo* konfliktní bloky.
- Rychlá detekce bez buildu:

  ```bash
  grep -o 'trans-unit id="[^"]*"' <soubor>.xlf | sort | uniq -d
  ```

- `AL0479` je jen **warning**, ale Essence build má `failOn = 'warning'` (viz 12.4) →
  **shodí CI**.

Zachyceno: cust-sonnentor-bc 2026-08-03 — merge masteru do feature větve zdvojil
trans-unit `PageExtension 2228984703 - NamedType 3852263291` (`OnlyProdOrderComponentErr`);
obě strany ho přidaly, každá na jinou pozici v souboru, git to spojil tiše.

---

## 8. Dokumentace requirements (PBI/Task → MD)

Pro každý dodělaný PBI / Task v Azure DevOps se v zákaznickém repu vede
Markdown s popisem requirementu a technickou dokumentací implementace.
**Platí i pro rychlou opravu / hotfix** — MD patří do **stejného PR** jako kód, ne „až potom"
(2026-09-24, cust-alumistr-bc PBI 66358: PR 9567 odešel bez `docs/66358_…md`, dopisovalo se
dodatečně). Když repo drží vlastní konvenci názvu (`docs/<ID>_<Nazev-s-pomlckami>.md` v
cust-alumistr-bc), drž ji místo vzoru níž. Oprava produktové appky, která navazuje na zákaznický
ticket, dostane MD i v produktovém repu (vzor `prod-epb-pricingMatrix-bc/docs/66358 - …md`).

**Kam to patří:**

```
<repo-root>/docs/<PBI-ID> - <feature-kód> - <krátký popis>.md
```

Příklad: `docs/63103 - FIN_039 - Kontrola EU zák. plátce DPH.md`.
Pokud `docs/` ještě neexistuje, vytvoř ji. **Žádná podsložka
`requirements/`** — všechny ticketové MD jdou rovnou do `docs/`.

**Co MD obsahuje (v tomhle pořadí):**

1. **Meta info** — PBI/Task ID, parent, customer, area, iterace, stav,
   assigned to, vytvořeno (kdo + datum), effort, priorita, External ID,
   sourozenecké tickety pokud sdílí implementaci.
2. **Upravené appky** — tabulka `Appka | Repo | Typ změny`. Zachyť
   **každou appku, kterou tahle implementace mění** (nová appka, úpravy
   stávající extension, úpravy base / dependency appky). Závislosti, ze
   kterých jen čteš, sem nepatří — ty jdou do "Technické dokumentace".
   Použij customer affix v závorce, ať čtenář hned ví, čí extension to je.
3. **Description** — popis řešení z PBI (obvykle z parent PBI, pokud je
   zdrojem Task, který má description prázdný).
4. **Acceptance Criteria** — pokud existují (často nejsou explicitní →
   sekci pak vynech).
5. **Odkazy v popisu** — přepiš odkazy z HTML descriptionu (Dataverse
   incident, BC Job Planning Line, BC Job, …) jako Markdown linky.
6. **Příklad využití v reálu** — co uživatel reálně udělá, krok po kroku
   (golden path + případné edge case scénáře).
7. **Technická dokumentace** — **jen pokud se reálně dělaly** nové objekty
   nebo nová pole:
   - Tabulka nových objektů (typ, ID, název, krátký popis funkčnosti)
   - Tabulka nových polí (tabulka, ID, jméno, typ, popis)
   - Datový tok / event flow (textově nebo ASCII diagram pro neintuitivní
     propagaci přes víc tabulek/codeunit)
   - Codeunits a reporty — krátký odstavec o roli (jaké eventy odběrá,
     co dělá, kdy se spouští)

   **Pokud žádný nový objekt nebo pole, sekci úplně vynech.**

**Konvence obsahu:**

- Identifikátory (názvy objektů, polí) drž **anglicky** — stejně jako kód
  (viz 1.1). Popisy a kontext česky.
- Technická dokumentace cílí na vývojáře, který se k ticketu vrátí za půl
  roku — ne na koncového uživatele. Stručné, věcné, bez marketingových
  obratů.
- Když implementace pokrývá víc PBI (např. FIN_039 EU + FIN_041 CZ sdílí
  jeden codeunit), zmiň to v meta info v sekci „Sourozenecké PBI" a
  technickou dokumentaci napiš jen jednou (do MD toho hlavního PBI).
- Odkazy na DevOps work itemy: `https://dev.azure.com/essencebs/Projects/_workitems/edit/<ID>`.
- Aktuální **verzi appky nezmiňuj** jako součást scope ticketu — verze se
  mění nezávisle na obsahu (viz 7.8 v `bc-al-tools.md`).

**Proč:**

- Repo má jeden zdroj pravdy o tom, **co bylo dodáno a jak** — bez nutnosti
  mít otevřenou DevOps a hrabat se v komentářích.
- Při code review / regresi za půl roku má vývojář kontext po ruce.
- Pomáhá při handoveru projektu jinému týmu / customer success.

**Workflow tip:** MD piš až po dokončení implementace, ne při startu —
ujistí se, že popis odpovídá tomu, co je opravdu nasazené, a že
technická dokumentace nezakonzervuje původní (pravděpodobně neaktuální)
představu z PBI descriptionu.

### 8.1 Uživatelská příručka větší featury — HTML se screenshoty vedle MD dokumentu

U větších funkcionalit (nový business proces, ne jednotlivé pole) se kromě technického
`docs/<PBI-ID> - … .md` dělá **netechnická příručka pro uživatele a testery**:

```
docs/<PBI-ID>_<Nazev-featury>-uzivatelska-prirucka.html
```

**Vždy jako soubor v `docs/` daného repa, nikdy jen jako publikovaný artefakt** — příručka
patří k verzované dokumentaci (přání uživatele, 2026-09-15). Obrázky **embeduj jako base64
`data:` URI**, ať je HTML soběstačné a otevře se dvojklikem; pracuj přes šablonu s placeholdery
(`@@IMG:jmeno@@`) a malý skript, který je nahradí, aby šlo znovu vygenerovat. Soubor dopiš
o plnou HTML kostru (`<!DOCTYPE>`, `<head>`, `<body>`). Do MD dokumentu ticketu přidej odkaz.

**Obsah** (řazení podle toho, co uživatel dělá, ne podle objektů): princip v jedné větě +
propočítaný příklad → nastavení (tabulka kde / pole / co s ním) → co vyplňuje uživatel a co
systém → akce krok za krokem → co se děje při účtování a archivaci → co proces **záměrně
nedělá** (otevřené business otázky z RFC, ať to testeři hlídají) → testovací scénář
k odškrtání. Terminologii ber **z `Translations/*.cs-CZ.xlf`** (captiony polí a akcí), ne
z hlavy — uživatel musí najít přesně ten popisek, který vidí na obrazovce.

**Screenshoty z reálného prostředí** (Claude in Chrome, detail a pasti v 12.3): nafoť
nastavení, kartu s klíčovým polem, hlavičku dokladu s akcí a řádky; k obrázku vždy popisek
„kde to v BC je". Obrazovky, které se do okna nevejdou (tělo e-mailu), radši **přečti z DOM
a vykresli jako tabulku** přímo v příručce.

---

## 9. Před úpravou AL objektu — co si přečíst

Než sáhneš na objekt, projdi si pár věcí — ušetří ti to zmatky typu "stejně se
jmenující procedura znamená v jiném scope něco jiného" a "tahle API vůbec na
Cloudu neexistuje".

### 9.1 Hlavička objektu

Přečti si **prvních pár řádek objektu**: `id`, `namespace` (pokud je),
deklarace (`tableextension X extends Y` vs `table X`). Stejný název procedury
může v jiném scope znamenat něco úplně jiného. U extension navíc rozlišuj,
**zda rozšiřuješ base app, jinou MS appku, nebo 3rd-party** — určuje to, kde
hledat eventy a jaké patterny použít.

### 9.2 `app.json` — vždycky před netriviální změnou

Než navrhneš řešení, kouni do `app.json` a zaznamenej:

- **`idRanges`** — kam smíš dávat nová ID
- **`dependencies`** — co máš dostupné, jakou verzi
- **`target`** — `Cloud` vs `OnPrem` (rozhoduje o tom, co můžeš použít —
  viz sekce 10 a 11)
- **`runtime`** a **`platform`** — určují, které moderní featury jsou
  dostupné (namespaces od runtime 11.0, atd.)
- **`application`** — verze BC, na kterou stavíš

Bez toho návrh často sjede do "ano použijeme namespaces" v repu, který je
na runtime 9.0, nebo do `DotNet` callu v Cloud extensionu.

### 9.3 `.alpackages/` je **binární ZIP** — nečíst přes Read/cat/grep

Velký pozor: `.alpackages/*.app` soubory jsou **podepsané ZIPy se symboly a IL**.
Když je zkusíš otevřít přes `Read`, `cat`, `head`, `Grep`, dostaneš odpadky
nebo error a může to vypadat jako že symbol neexistuje — což není pravda.

Pro lookup symbolů ze závislostí použij (v pořadí preference):

1. **`al-mcp-server`** (viz 7.2) — strukturovaný symbol lookup ze `.alpackages`.
   Funguje na MS base/system app, CZ lokalizaci, ForNAV, Continia, vlastní
   per-tenant extensions atd. **Tohle je primární nástroj.**
2. **VS Code AL extension** — Go to Definition (F12), Find All References,
   AL Object Browser. Vyžaduje, aby uživatel byl ve VS Code — pokud asistuješ
   přes CLI, nech si to udělat uživatelem.
3. **Microsoft Learn MCP** — pro **standardní** BC objekty (base app tables,
   codeunits, pages od Microsoftu). Aktuální dokumentace, čistý markdown.
4. **GitHub `StefanMaron/MSDyn365BC.Code.History`** (viz 7.3) — pro hluboký
   kontext, historii změn, nebo pokud potřebuješ vidět víc souborů najednou.
5. Vygenerované `.dal` text artefakty (pokud projekt produkuje) — fallback.

**Pokud jméno procedury "zní správně", ale nedokážeš ho potvrdit přes některý
z výše uvedených zdrojů, ber to jako že neexistuje.** Lepší se zeptat /
ověřit než vygenerovat call na neexistující signature.

### 9.4 Permission set kontrola

Když měníš permission-relevantní objekt (tabulka, codeunit se sensitivní
logikou, nový report obsahující změnu dat), **ověř nebo aktualizuj příslušný
`permissionset`**. Repa typicky mají per-app permission set objekt
(`<App> Permission Set XXXX.PermissionSet.al`) — drž ho v synchronizaci.

---


## 12. Verifikace a analyzery (AA / CA / PTE / LC)

### 12.1 Po každém AL editu — build a čti diagnostiku

Po každé netriviální změně AL kódu spusť **build** (přes VS Code AL
extension `AL: Package`, přes `alc.exe`, viz 7.1, nebo přes CI při pushi).
Diagnostika přijde ve čtyřech rodinách rulů — všechny mají svůj smysl:

- **AA-series** — Microsoft AL analyzer (oficiální AL rules)
- **CA-series** — CodeCop (style + best practices od MS)
- **PTE-series** — Per-Tenant Extension rules (specifické pro PTE distribution)
- **ALCops** (`arthurvdv.alcops`, od 2026-09 **náhrada samostatného LinterCopu**, DLL přímo
  v `<al-ext>/bin/ALCops.*.dll`): `AC` ApplicationCop, `DC` DocumentationCop, `FC` FormattingCop,
  **`LC` LinterCop** (převzatá community sada), `PC` PlatformCop, `TC` TestAutomationCop

Některá pravidla jsou informational (`LC0082` info-level "Count > 1"), jiná
warning, jiná error. Default behavior závisí na `ruleset.json` v repu —
zákaznická repa typicky mají vlastní ruleset, který upravuje severities.

**⚠️ Lokální verifikace před commitem/pushem = VŠECHNY dotčené appky + analyzery
jako CI.** Holý `alc` bez `/analyzer:` neodhalí ŽÁDNÝ AA/CA/PTE/LC nález — a
Essence CI má `failOn = 'warning'`, takže jediný warning shodí build. Než ohlásíš
„kompilace čistá" nebo pushneš:

1. Zkompiluj **každou appku, které ses dotkl** — hlavní app I test app. Test
   appka se často zapomene; symboly test frameworku si půjč ze sibling repa
   (`.alpackages` např. prod-ess-configurator-bc) nebo z MS feedu (viz 7.12 v `bc-al-build.md`) a
   poskládej temp package cache.
2. Přidej **stejnou sadu analyzerů, jakou má repo ve workspace** — od 2026-09 to jsou
   MS `CodeCop`, `PerTenantExtensionCop`, `UICop` **plus všech šest ALCops**
   (`ALCops.ApplicationCop/DocumentationCop/FormattingCop/LinterCop/PlatformCop/TestAutomationCop`)
   **a povinně `ALCops.Common.dll`** — bez něj každé ALCops pravidlo spadne na `AD0001` a build
   vypadá falešně čistý. **Samostatný `BusinessCentral.LinterCop.dll` už nepoužívej**, v AL 18
   extensionu není a jeho pravidla (LC*) dodávají ALCops. `Analyzers.Common.dll` (Microsoft) se
   naopak **nepředává** (AL1003, viz 7.1) — nezaměň ty dvě „Common" knihovny. Test projekty jedou
   bez rulesetu (7.12 v `bc-al-build.md`), u hlavních appek CI přidává ruleset per konvence 12.4.
   V Git Bash prefix `MSYS2_ARG_CONV_EXCL="*"` a plné Windows cesty (viz 7.1).
   **Když repo ruleset dědí remote `essence-default.ruleset.json` (`includedRuleSets` s `https://…`),
   musíš `alc` předat i přepínač `/enableexternalrulesets`** — jinak `error AL1033: … because external
   rulesets are not allowed` a build spadne dřív, než se vůbec dostane ke kódu. V CI to netrápí
   (`externalRulesets` má v `CompileALApps2.yml` default `True`, viz 12.1b), takže se to objeví až
   při lokální verifikaci. Druhá povinná drobnost ze stejné dvojice: **`ALCops.Common.dll` se předává
   jako `/analyzer:`** — bez něj každé ALCops pravidlo spadne na `AD0001` a `alc` skončí
   `System.AggregateException` (ne tichým „0 warningů"). (2026-09-17, cust-zlomek-bc 65364.)
3. `info` nálezy build neshodí (dlouhodobý šum typu AA0247 klidně odfiltruj),
   **každý warning oprav před pushem**.
4. `LC0072` (info) „documentation comment does not match the procedure syntax": `///` XML doc
   komentář musí mít `<returns>` u procedury s návratovou hodnotou a `<param name="X">` pro
   každý parametr — samotné `<summary>` nestačí. (2026-09-02, cust-zlomek-bc)
5. **`&` v `///` XML doc komentáři = `warning AL0640: XML comment has badly formed XML`** (a s
   `failOn warning` CI fail) — v `<summary>` piš `Sales &amp; Receivables Setup`, ne `Sales & Receivables
   Setup`. Stejně `<` / `>`. Obyčejné `//` komentáře a `Description`/`ToolTip` property se to netýká.
   (2026-09-04, cust-alumistr-bc)
6. **`AA0214` „The record X should be modified before saving to the database" (CodeCop warning → CI fail) je falešný,
   když záznam mění procedura tabulky** (`Customer.SetBusinessUnitSOI(No, Id)` → `Customer.Modify(true)`): analyzátor
   vidí jen přímá přiřazení do polí mezi `Get`/`Find` a `Modify`. Fix `#pragma warning disable/restore AA0214` kolem
   toho jednoho `Modify` s jednořádkovým komentářem proč; nevracej se k přímým přiřazením jen kvůli pravidlu. Hlásí to
   i v testech (helper `Setup.ValidateXxx(...); Setup.Modify(true)`). Pozor při čtení logu: `head -60` na seznam warningů
   ho odřízl a build vypadal čistý — u dlouhých seznamů grepni konkrétní ID zvlášť. (2026-09-22, cust-soitron-bc.)

(Zachyceno 2026-08-05, cust-alumistr-bc build 27693: `AA0137` unused variable
v test codeunitě — lokálně se před pushem kompilovala jen hlavní appka bez
analyzerů, warning odhalil až CI. S krokem 1+2 by se chytil lokálně.)

### 12.1b ALCops v CI NEJSOU — nálezy jsou lokální; zavedení na existující repo

**Essence CI ALCops nespouští.** `CompileALApps2.ps1` (template repo `tools-devops-essence-bc-yaml-lib`,
větev `v2-0`) volá `Compile-AppWithBcCompilerFolder` jen se switchi `-EnableCodeCop`,
`-EnableUICop`, `-EnablePerTenantExtensionCop`, `-EnableAppSourceCop`; analyzery bere z compiler
folderu BcContainerHelperu, kde žádné ALCops DLL nejsou. Takže **ALCops warning CI nikdy neshodí** —
je to čistě kvalita kódu ve VS Code / lokálním `alc`. Praktický dopad: úklid ALCops nálezů na velkém
repu je bezpečný (nehrozí, že rozbiješ zelený build), ale taky se sám neudrží — nový nález nikdo
nezachytí, dokud se někdo nepodívá do VS Code.

**Ruleset hledá CI jen UVNITŘ app folderu** (`Get-ChildItem -Path $appFolder -Recurse -Filter '*Ruleset*.json'`,
první nalezený). Repo ruleset v rootu (`<repo>.ruleset.json`) se tedy do CI **nepředá**, jak už říká 12.4.
Naopak jakmile `*Ruleset*.json` do app folderu přidáš, CI ho začne používat — a `externalRulesets`
má v `CompileALApps2.yml` **default `'True'`**, takže remote `includedRuleSets` (essence-default)
nespadne na `AL1033`. Remote `essence-default.ruleset.json` jen skrývá, nic nezvyšuje — dědit ho je
bezpečné. **Jeho obsah se ale v čase mění, takže si ho před rozhodováním stáhni**
(`curl -s https://essencefiles.blob.core.windows.net/bc-pipelines/essence-default.ruleset.json`),
nespoléhej na seznam v notes: k 2026-09-18 skrývá **`AC0030`, `AC0031`, `LC0010`, `PC0037`, `AS0081`,
`AA0247`** (dřív tu stálo `LC0010`/`LC0068`/`LC0084`/`AS0081`/`AA0247` — `PC0037` a obě `AC*` přibyly,
`LC0068`/`LC0084` tam dnes nejsou).

**Ověřeno v logu (cust-sonnentor-bc, build 28359, 2026-09-21):** `base/app` se kompilovala **bez**
`/ruleset:` (repo ruleset ležel v rootu), zatímco `base/test` dostala `/ruleset:.../base/test/sonnentor-bc-test.ruleset.json`,
a protože test ruleset přes `includedRuleSets` s relativní cestou `..` dědil rootový soubor, měla
**paradoxně jen test appka** hlavní pravidla i remote default. Oprava = přesunout hlavní ruleset do
`base/app/` (vzor cust-alumistr-bc: `base/app/<repo>.ruleset.json`), v test rulesetu změnit include na
`..` + `app` + soubor a ve `.code-workspace` `al.ruleSetPath` na `../../base/app/<repo>.ruleset.json`
(je relativní ke každé workspace složce). Relativní include se řeší vůči souboru rulesetu, ne vůči projektu.
Rychlá kontrola po pushi: v logu kroku Compile AL Apps hledej `/ruleset:` u každého `alc.exe` řádku.

⚠️ **Test ruleset, který nedědí hlavní, si tím remote skrývání zapíná zpátky** — kontroluje tedy
**víc** než hlavní appka, ne míň, což je přesný opak toho, co od test rulesetu čekáš. Na
prod-ess-configurator-bc to dělalo 201× `AC0030` + 24× `AC0031` + 22× `AA0247` + všechna `PC0037`
v testech, zatímco hlavní appka je měla skryté; po doplnění `includedRuleSets` na hlavní ruleset
spadl počet nálezů test appky z 388 na 141 a `LC0090`/`PC0037` šly z test rulesetu pryč jako
duplicitní. Dnes to nebolí (samé `info`), ale jakmile remote skryje nějaký **warning**, hlavní appka
projde a testy shodí build. (2026-09-18, prod-ess-configurator-bc.)

**Čísla z praxe (cust-sonnentor-bc, 2026-09-15, první zapnutí ALCops na repo s ~165 soubory):**
hlavní appka 1176 diagnostik, z toho **313 warning/error**; test appka 217 / **97**. Zbytek je `info`
(AC0031 chybějící tabledata permissions, PC0030 SetLoadFields, LC0098/LC0099 naming subscriberů,
DC0004/DC0007 XML docs) — ty jde nechat. Rozpad warningů a co s nimi:

| Pravidlo | Počet | Řešení |
| --- | --- | --- |
| `PC0037` Use Validate() instead of direct field assignment | 188 + 75 | původně pragma per procedura (74 párů disable/restore) — 2026-09-22 vyhozeno, **explicitní Hidden v hlavním rulesetu** (remote default ho sice od 2026-09-18 skrývá taky, ale explicitní zápis nezávisí na změnách remote souboru); viz 12.1c |
| `LC0092` Field name should not contain special characters (`%`, `&`, `!`, `?`) | 71 | **ruleset Hidden** — nasazené pole `Content % SON` je business termín, přejmenování by rozbilo data |
| `LC0090` Cognitive Complexity (threshold 15) | 18 | ruleset Hidden (konzistentní s `LC0010`), nebo zvednout `CognitiveComplexityThreshold` v `alcops.json` |
| `LC0040` explicitní RunTrigger | 14 + 6 | opravit v kódu (`DeleteAll(false)`, `Modify(false)`, …) |
| `LC0028` identifier syntax subscriberů | 9 + 1 | opravit (regex `, '(On[A-Za-z0-9_]+)', ''` → `, \1, ''`) |
| `FC0005` metoda místo přiřazení | 4 | `Notification.Id(x)` / `.Scope(x)` / `.Message(x)`, `Rec.FilterGroup(40)` |
| `FC0003` chybějící závorky | 2 + 2 | `RecordId()`, `Count()` |
| `AA0021` řazení deklarací | 0 + 7 | pořadí Record → Report → **Codeunit** → XmlPort → Page → … → zbytek (Enum patří až za Codeunit) |
| `AA0181` `Find()` jen s `Next()` | 0 + 1 | znovunačtení jednoho záznamu piš `Find('=')` (chování identické, default byl `'='`) |
| `PC0035` CalcFields v cyklu | 1 | `SetAutoCalcFields(pole)` před `FindSet` |
| `PC0034` počet placeholderů ≠ argumentů | 1 | **reálný bug** — `Error(MoreLotErr)` u labelu s `%1 %2`; ALCops tyhle chyby najde spolehlivě |
| `PC0022` možný overflow | 1 | `CopyStr(Rec.GetFilter(pole), 1, MaxStrLen(cíl))` |
| `LC0095` nepoužitý parametr | 1 | pragma, když je parametr součástí publikovaného podpisu |
| `AC0010` objekt bez permission setu | 6 | v **test** rulesetu Hidden (test appka permissionset záměrně nemá, viz bc-al-autotests) |

⚠️ **Starý `lintercop.json` ALCops NEČTOU — konfigurace v něm je mrtvá.** Repa, která ještě vozí
`lintercop.json` po samostatném LinterCopu (camelCase klíče `cognitiveComplexityThreshold`,
`enableRule0011ForTableFields`…), po přechodu na ALCops tiše jedou na **defaultech**: `LC0090` hlásí
`threshold ≥ 15`, i když soubor říká 20. Poznáš to přesně podle toho čísla v hlášce — sedí-li default
místo tvého, soubor se nečte. Fix: přejmenovat na **`alcops.json`** (vedle `app.json`) a klíče přepsat
na **PascalCase** dle schématu níže; pravidla, která v novém schématu nejsou (`enableRule0011…`,
`enableRule0016…`), zahoď. (2026-09-22, prod-ef-advanceCZ-bc.)

**`alcops.json`** (JSON schéma `raw.githubusercontent.com/ALCops/Analyzers/main/src/ALCops.Common/Settings/alcops.schema.json`,
soubor vedle `app.json`) umí **jen thresholdy a patterny** — `CognitiveComplexityThreshold`,
`CyclomaticComplexityThreshold`, `MaintainabilityIndexThreshold`, `SubscriberNamingPattern`,
`NamingPatterns`, `ToolTipAllowedPunctuations`, `KnownAcronyms`, `LanguagesToTranslate`,
`StatementBlockSpacing`, `Extends`. **Vypnout pravidlo se tam nedá** — to je pořád jen ruleset
nebo `#pragma`.

**Log `alc.exe` z AL 18 je UTF-8, z AL 17 UTF-16.** Dekóduj podle BOM (`raw[:2] in (b'\xff\xfe', b'\xfe\xff')`
→ utf-16, jinak utf-8), ne natvrdo — `iconv -f UTF-16` na UTF-8 logu vyrobí CJK „čínštinu" a
vypadá to jako rozbitý build (7.1 mluví o UTF-16 logu, od AL 18 to tak být nemusí).

### 12.1c `PC0037` (Validate místo přiřazení) — pragma per procedura, ne globální vypnutí

`PC0037` je nejhlasitější ALCops pravidlo na běžném BC kódu, protože direct assignment je
v hromadě situací **správný** pattern: plnění temporary bufferu, nastavení polí primárního klíče
před `Insert`, propagace hodnot v event subscriberu, stamp pole bez `OnValidate`. Přesto ho
nevypínej globálně — hodí se tam, kde `Validate` opravdu chybí.

**Zavedený postup (cust-sonnentor-bc, 263 výskytů):**

- **hlavní appka** → `#pragma warning disable PC0037` **hned za `begin` procedury** a `restore`
  před jejím koncovým `end;`, s krátkým důvodem v komentáři. Scope procedury je kompromis:
  ztiší vědomý blok přiřazení, ale nové chybějící `Validate` v jiné proceduré pořád vidíš.
  74 procedur ve 22 souborech; skriptovatelné — hranice procedury poznáš podle indentace
  deklarace (`^(\s*)(local |internal |protected )?(procedure|trigger)\s`), jejího `begin`
  a prvního `end;` na téže indentaci. **Pragma dávej mezi příkazy, nikdy mezi `if ... then`
  a jeho příkaz.**
- **test appka** → `PC0037` rovnou `Hidden` v test rulesetu; testy staví data přímo záměrně
  a `Validate` by rozjel business logiku, kterou test izoluje.

**Test ruleset** (doplnění k 12.4 a k bc-al-autotests): `base/test/<repo>-test.ruleset.json`
dědí hlavní ruleset přes `includedRuleSets` a skrývá `AC0010` + `LC0015` (permission set coverage),
`PC0037`, `DC0004` + `DC0007` (XML docs na testech). **CI si ho najde sám** (konvence výše),
ale **VS Code ne** — workspace `al.ruleSetPath` (`..\..\<repo>.ruleset.json`) se z test folderu
resolvuje zpátky na hlavní ruleset, takže je potřeba folder-level `base/test/.vscode/settings.json`
s `al.ruleSetPath` na test ruleset. Pozor: `.vscode` bývá v `.gitignore` (tak je to v cust-sonnentor-bc),
takže ten soubor zůstane lokální a kolegům se nerozdistribuuje — buď výjimka v `.gitignore`,
nebo to každý má u sebe.

### 12.1d Další ALCops pravidla, na která narazíš při úklidu repa

Doplněk k 12.1c (tam je jen `PC0037`). Čísla z druhého úklidu — **cust-zlomek-bc, 2026-09-15**,
4 projekty: hlavní appka `Zlomek Extension` **89 warningů**, její testy **10**, zákaznická
`configuratorExtension` **11 + 55**. Po úklidu 0/0/0/0.

- **`AC0010` „object is not covered by any PermissionSet"** (nástupce `LC0015`) u **tabulky**
  nezmizí, když máš jen `tabledata "X" = RIMD` — ⚠️ chce **`table "X" = X`**, tedy execute
  permission na objekt tabulky. Vzor `prod-ess-configurator-bc` má obojí vedle sebe
  (`table "Action Formula Line COEBS" = X,` + `tabledata "Action Formula Line COEBS" = RMID,`).
  Rozdělení práv přes `IncludedPermissionSets` (READ = R ⊂ EDIT = IMD) pravidlo neřeší,
  ani zvýšení na `RIMD` — chybí mu ten `table` řádek. V test appce se `AC0010` naopak skrývá
  rulesetem (12.1c).
- **`AA0181` nehlásí jen `FindSet()` bez `Next()`, ale i holé `Find()`** („must be used only in
  connection with the Next() method"). Typický výskyt: refresh záznamu v testu
  (`SalesLine.Find();` po akci, pak assert). Fix je jednořádkový a sémanticky identický:
  **`Find('=')`** (holé `Find()` = `Find('=')`), nebo `Get(...)`.
- **`PC0020` „incompatible field type between TransferFields-coupled tables"** hlídá, že vlastní
  pole se stejným ID má stejný typ/délku na **Sales Header ↔ Archive / Invoice / Cr.Memo /
  Shipment / Return Receipt** (a obdobně u nákupu). Je to **reálný nález, ne kosmetika** —
  `TransferFields` delší text tiše ořízne. Fix = dorovnat délku na všech tabulkách sady
  (rozšíření je nedestruktivní, sync mode Add projde; zmenšení dat NE). Souvisí s pravidlem
  „posted/archive sady drží stejné field ID" (3.6 v `bc-al-data.md`).
  ⚠️ Než začneš dorovnávat, ověř `git diff`, jestli tu nerovnost nezavedla **něčí rozpracovaná
  změna** ve working tree — u Zlomka pocházelo všech 10 hlášení z necommitnutého prototypu,
  který zvedl `Comment 1 ZLK` na `Text[2048]` jen na hlavičce. Dorovnání zbylých pěti tabulek
  bylo správné, ale zbytečné: prototyp šel nakonec pryč a s ním i nález, takže se v repu nic
  měnit nemuselo. **Pořadí práce: nejdřív se zeptej, co z working tree zůstane, pak uklízej** —
  jinak uklidíš cizí rozdělanou práci a pak to revertuješ.
- **`LC0092`** hlásí i **název pole se speciálním znakem** (`Advance % ZLK`, `Value %`).
  Přejmenovat pole s daty v produkci nejde → `#pragma warning disable/restore LC0092` kolem
  deklarace pole s důvodem. Pravidlo hlásí i **parametry** (`parItemNo` → `ItemNo`); ty
  přejmenuj, jsou lokální a volající se nemění (v AL se parametry při volání nepojmenovávají).
- **`LC0090` Cognitive Complexity** (threshold z `lintercop.json`, u Zlomka 15) se u běžného
  kódu spraví vytažením vnitřní smyčky / vnořených `if` do samostatné procedury; bývá to
  i čitelnější než pragma. `LC0010` (cyclomatic) má essence-default na `Hidden`, `LC0090` ne.

### 12.1e Doménová appka — PC0037 a LC0090 do rulesetu, zbytek fixni/pragmuj

Třetí úklid (**prod-ess-configurator-bc, 2026-09-16**, ALCops v AL 18.0.2732683): hlavní appka
**839 warningů** (1339 info), test appka **840** (365 info), 0 errorů. Rozpad hlavní appky:
`PC0037` 747, `LC0090` 57, `FC0005` 24, `LC0092` 5, `LC0096` 3, `AC0018`/`PC0027`/`LC0040` po 1;
test appka `PC0037` 837, `AC0010` 2, `FC0005` 1.

**Dvě pravidla dávají u doménové appky smysl vypnout rulesetem, ne pragmou:**

- **`PC0037`** dělá **94 % všech nálezů** (1584 z 1679). U appky, která staví temporary buffery,
  kopíruje konfigurace pole po poli a plní lookup dialogy, je direct assignment **správný pattern** —
  74 pragem po procedurách (vzor 12.1c u sonnentoru) je tam jen šum. Rozhodnutí je majitele repa:
  hodně vlastních tabulek + málo base-app validací = ruleset; extension nad standardními doklady
  = pragma per procedura, ať nová chybějící `Validate` nezapadnou.
- **`LC0090`** (Cognitive Complexity) u vyhodnocování stromů podmínek a formulí: rozsekat
  velkou rozhodovací proceduru kvůli metrice **přidá riziko regrese** bez čitelnostního zisku.
  Pozor, `LC0010` (cyclomatic) má essence-default na Hidden, `LC0090` ne — musíš ho dopsat sám.

Zbylých ~95 nálezů se uklidí za večer:

- **`FC0005` hlásí i `ReadIsolation :=`**, nejen `LookupMode :=` (`Rec.ReadIsolation := IsolationLevel::UpdLock;`
  → `Rec.ReadIsolation(IsolationLevel::UpdLock);`). Oboje je čistě mechanické a **skriptovatelné**
  jedním regexem `^(\s*)([\w."]*\.)?(LookupMode|ReadIsolation)\s*:=\s*(.+?);$`. ⚠️ Soubory jsou CRLF —
  python otevírej s `newline=''` a stejně zapisuj (a `encoding='utf-8-sig'`, když má soubor BOM), jinak
  přepíšeš konce řádků v celém souboru (stejná past jako `sed -i`, viz 7.1).
- **`LC0096`** („record variable is passed to a method already invoked on the same record") vzniká
  u **lokálního helperu na page, který bere record vlastní SourceTable**: `local procedure HasValue(var X: Record Y)`
  volaný jak s `Rec`, tak s temporary buffery. Pragma funguje (pozor: když volání sedí za `if … then`, musí
  obalit **celý `if`**, ne se vklínit mezi podmínku a příkaz), ale **lepší je proceduru přesunout na tabulku**
  jako `internal procedure` a volat `Rec.HasValue()` / `TempBuf.HasValue()` — pravidlo zmizí bez pragmy
  a typicky se tím zruší i duplicita, protože stejný helper bývá zkopírovaný na sesterské page.
  `internal` (ne `public`), ať se z toho nestane API appky, které pak nejde odebrat.
  ⚠️ **Proceduru maž Edit toolem, ne regexem** — `(?:.*?\r?\n)*?[ \t]*end;` s `re.S` ukousne blok
  na prvním dřívějším `end;` a rozbije soubor (39 syntax errorů, 2026-09-16).
- **⚠️ `AC0018` u prázdného captionu — `Locked = true` může smazat existující překlad.** Pravidlo radí
  `Caption = ' ', Locked = true;`, jenže **prázdná hodnota enumu bývá v lokalizaci přeložená**: hodnota
  `0; " "` zrcadlící standardní `Sales Line Type` má v `cs-CZ` target **„Poznámka"**, stejně jako řádek
  prodejní objednávky. `Locked` ji vyřadí z generovaného XLIFF → při příštím NAB Refreshi překlad
  **vypadne z `.cs-CZ.xlf`** a český uživatel uvidí v rozbalovacím seznamu prázdno. **Ověř před fixem:**
  `grep -A2 '<trans-unit id="Enum <hash> - EnumValue <hash>' Translations/*.cs-CZ.xlf` — když tam `<target>`
  s textem je, dej `#pragma warning disable AC0018` a `Caption` nech odemčený. Kontrola dopadu: po kompilaci
  musí být trans-unit pořád v `Translations/*.g.xlf` (`Locked` = 0 výskytů). `Locked = true` platí jen pro
  captiony, které se opravdu nepřekládají (technické kódy, oddělovače). (2026-09-16, prod-ess-configurator-bc)
- **`PC0027`** („do not execute table triggers on temporary record variables") u `TempBuf.Insert(true)`:
  na temporary tabulce se **table triggery stejně nespouštějí**, takže `Insert(false)` je sémanticky
  identický a warning zmizí — žádné riziko změny chování.
- **`LC0092`** u polí zrcadlících standardní BC názvy (`Line Discount %`, `Scrap Factor %`,
  `Indirect Cost %`, `Scrap %`) → pragma kolem deklarace pole, `restore` **až za** uzavírací `}`.
- **Test ruleset: `LC0015` už nestačí** — nástupce `AC0010` je vlastní ID, musíš ho do test rulesetu
  dopsat zvlášť (u konfigurátoru prosákly 2 nálezy, dokud tam byl jen `LC0015`).

**Lokální ověření test appky** šlo přesně podle 7.12: MS test symboly z `prod-ess-dotykackaConnector-bc/.alpackages`
(řada 28.1 pod 28.3 Base App bez problémů), **AI Test Toolkit** z MSSymbols feedu
(`microsoft.aitesttoolkit.symbols.2156302a-…`, verze 28.3.52162.52273) a hlavní appku zkompilovanou
do téže temp cache pod jménem s aktuální verzí. Po úklidu **0/0 warningů** v obou projektech.

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

### 12.2 Když nevíš, co pravidlo znamená — vyhledej

Neopravuj warning naslepo přepsáním kódu. **Najdi popis pravidla:**

- **AA / CA / PTE** — Microsoft Learn MCP server (`microsoft_docs_search` s
  kódem pravidla, např. `AA0233`)
- **LC / AC / DC / FC / PC / TC** — Microsoft Learn nepokrývá; dokumentace ALCops
  (`arthurvdv/ALCops`), u LC* pravidel dál platí i původní wiki
  `StefanMaron/BusinessCentral.LinterCop` (ALCops sadu převzaly).

Některá pravidla jsou v rozporu (typický příklad: `LC0082` říká "nahraď
`Count() > 1` smyslem `FindFirst() + Next()`", ale tím triggeruješ `AA0233`
+ `AA0181`). U malých filtrovaných setů (např. po `SetSelectionFilter`) je
`Count() > 1` v pohodě a `LC0082` se dá ignorovat. Vždycky si ověř, **co je
v daném kontextu nejmenší zlo**.

### 12.3 Runtime errory — žádné spekulační smyčky

Když ti při běhu BC vyletí error, **nedělej dva tři pokusy "co kdyby" v
kódu na základě domněnek o tom, jak vypadá data.** Stack + error message
typicky ukazují na konkrétní field / record / operaci.

Workflow:

1. Z chyby vyčti **co konkrétně se rozbilo** (table, field, codeunit, řádek).
2. Udělej **nejpravděpodobnější fix** podle textu chyby a stacku.
3. **Build, publish, předej uživateli k re-runu na jeho datech.**
4. Iteruj na **výsledcích reálného běhu**, ne na hypotézách "data asi vypadají
   takhle".

Loop "fix → guess data → fix → guess data" bez skutečného běhu utopí hodinu
za nic.

**Ověření setupu / dat u zákazníka v prohlížeči (Claude in Chrome):** BC web client bere v URL přímo
`?company=<Company>&page=<ID>&filter='<Field>' IS '<value>'` (URL-encoded: `%27No.%27%20IS%20%270058%27`) — otevře
kartu i list rovnou na záznamu, bez klikání přes Tell me. Funguje pro vlastní stránky (`page=63141` karta definice
konfigurace) i standardní (`page=42` prodejní objednávka, `page=30` karta zboží). Pak `zoom` na region místo
celého screenshotu, ať se dají přečíst zkrácené buňky. (2026-09-08, Alumistr BC-TEST2, kontrola Table Lookup
parametru pro textovou formuli.)

**Focení BC do dokumentace — co zdržuje** (2026-09-15, BC-TEST2, příručka SK pobočky, viz 8.1):

- **Celé BC běží v `<iframe>`.** `document.body.innerText` hlavního dokumentu je prázdný a `find` nic nenajde;
  pracuj přes `document.querySelector('iframe').contentDocument`. Skupiny na kartě hledej podle
  `.ms-nav-group-caption` a `scrollIntoView({block:'center'})` — pole ve spodních záložkách jinak nenafotíš.
- **Rozepsaná editace hodí „Leave site?" a navigace se neprovede** (nástroj vrátí chybu, stránka zůstane).
  Před odchodem `window.onbeforeunload = null` i na `contentWindow` iframu; zavřít a otevřít novou záložku
  je pomalejší a tab ID z předchozí skupiny už neplatí.
- **Sloupce řádků dokladu jsou daleko vpravo** (u vlastních polí za standardními). Kolečko s nimi nehne,
  funguje **tažení vodorovného posuvníku** (`left_click_drag` po ose x) po malých krocích a mezitím screenshot.
  Jména všech sloupců si nejdřív vypiš přes `[role="columnheader"]`, ať víš, kam táhnout.
- **Modální okna (editor e-mailu) mají malý viewport.** Maximalizační ikona pomůže jen částečně; obsah delší
  tabulky **vyparsuj z DOM** (`[...doc.querySelectorAll('table')]` → řádky) a vykresli ho v dokumentaci sám.
  `javascript_tool` vrací `[BLOCKED: Cookie/query string data]`, když výsledek obsahuje celé `innerHTML`
  s URL a tokeny — vracej jen extrahovaná data (texty buněk), ne HTML.
- **Kontrola hotového HTML v Claude in Chrome: `file://` URL nástroj odmítne** (*Can't interact with browser-internal or unparseable URLs*) –
  spusť `python -m http.server <port> --bind 127.0.0.1` ve složce souboru (na pozadí, pak `TaskStop`) a otevři `http://127.0.0.1:<port>/…`.
  Screenshot do dokumentace: `computer` akce `zoom` s `region` + `save_to_disk: true` uloží výřez v plném rozlišení (PNG) – lepší než
  celé okno. Malý viewport (boční panel, `innerWidth` ~600 px) schová akce partů; nový tab/okno mívá plnou šířku. (2026-09-24,
  prod-ess-configurator-bc `docs/api/MCP_BC` prezentace.)
- **Zápis do prostředí zákazníka (vyplnění setupu, založení zákazníka a dokladu, naklikání testovacího
  scénáře) smíš dělat — ale JEN s výslovným svolením uživatele** pro dané prostředí a seanci. Bez něj
  jen čti a foť; data připraví uživatel. Svolení si vyžádej **dopředu**, než začneš fotit, ať nevzniknou
  screenshoty prázdných obrazovek a nemusí se kolo opakovat (2026-09-15, BC-TEST2: nejdřív nafoceno
  prázdné nastavení a nabídka s nulovými cenami, pak se muselo znovu).
  Technicky to bez povolení stopne **permission classifier** hláškou „Modify Shared Resources" (čtení,
  navigace a screenshoty projdou, takže to vypadá jako částečné právo v BC — přitom práva v BC jsou,
  `altool`/prohlížeč sdílí přihlášení s VS Code). Trvalé povolení = allow pravidlo na
  `mcp__claude-in-chrome__computer` / `form_input` v `settings.json`; **nenastavuj ho sám**, nech to
  na uživateli. Po nafocení po sobě testovací data ukliď, pokud se uživatel nedomluví jinak.

### 12.4 Essence build — ruleset per projekt konvencí

Essence BC build (`azure-pipelines.yml` → template `ALBuildPipeline2.yml` →
`CompileALApps2.yml` → `scripts/CompileALApps2.ps1`, repo
**tools-devops-essence-bc-yaml-lib@v2-0** v ADO org essencebs) aplikuje ruleset
**per projekt konvencí** — pro každou složku s `app.json` najde **první
`*Ruleset*.json` rekurzivně v té složce** a předá ho kompilátoru:

```powershell
$useRulesetFile = (Get-ChildItem -Path $appFolder -Recurse -Filter '*Ruleset*.json').FullName | Select-Object -First 1
```

`-Filter` je case-insensitive → matchuje i `*.ruleset.json`. `externalRulesets`
default **true** (HTTP `includedRuleSets` jako essence-default povolené).
`failOn = 'warning'` → **jakýkoli warning failuje build**.

**Co NEfunguje:**

- **`app.json` `"ruleSetPath"`** → `error AL0124` (není podporovaná property
  pro app.json v AL 17 / runtime 16). Build breaker.
- **`.vscode/settings.json`** je gitignored (`**/.vscode` v `.gitignore`) →
  `al.ruleSetPath` tam je jen lokální, do buildu se nedostane.
- **`.code-workspace` `al.ruleSetPath`** řídí jen VS Code editor, **ne** build.

**Správně = `*Ruleset*.json` přímo ve složce projektu** (vedle `app.json`).
Build ho najde sám. Tak to dělá prod-ess-configurator-bc
(`app/ess-configurator.ruleset.json`, `test/ess-configurator-test.ruleset.json`).
Test ruleset typicky dědí root přes `includedRuleSets`
(`..\..\<repo>.ruleset.json`) a přidá výjimky (např. `LC0015` Hidden —
permission set coverage netřeba pro test codeunity).

