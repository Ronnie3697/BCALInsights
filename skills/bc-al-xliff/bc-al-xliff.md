# BC/AL poznámky — Lokalizace a překlady (XLIFF)

> Vyčleněno z `bc-al-workflow.md` 2026-10-22 (soubor přesáhl 1000 řádků). Číslování sekcí 6.1–6.4 je původní,
> aby fungovaly odkazy „viz X.Y" z ostatních souborů.
> Pozn.: sekci 6 byl v původním `bc-al-notes.md` chybějící `## 6` nadpis (jen v Obsahu) — doplněn při rozsekání 2026-06-23.
> Načítej, když řešíš: XLIFF / překlady (NAB AL Tools, prefixy `[NAB: …]`, jeden `<target>`), trans-unit ID (hash FNV-1a,
> ruční doplnění unitů, doplnění z `.g.xlf`, víc extensionů na stejný objekt — LC0091), změnu textu přeloženého labelu
> s `%n`, duplicitní trans-unity po merge (AL0479), výpis diakritiky z `.xlf` přes Bash.

Obsahuje:
- **6.1** NAB AL Tools — workflow překladu XLIFF (jeden `<target>`, prefixy `[NAB: …]`, hromadný překlad skriptem,
  diakritika z Bash do souboru, `.cs-CZ.xlf` změněný pod rukama)
- **6.2** trans-unit ID — hash FNV-1a (ruční doplnění unitů, refaktor labelu mění ID, doplnění z `.g.xlf`, víc extensionů
  na stejný target objekt / LC0091)
- **6.3** přeložený `Error`/`Message`/`Label` + `%n` — update `<source>` i `<target>`
- **6.4** merge XLF souboru → tiché duplicitní trans-unity (`AL0479`)

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

Po skriptu **zkompiluj** (`alc.exe`, viz 7.1 v `bc-al-tools.md`) — chytíš tím poškozenou
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
Hodí se při psaní uživatelské příručky, kde se terminologie bere z XLIFF (8.1 v `bc-al-workflow.md`). (2026-09-21, prod-em-kiosk-bc)

**⚠️ `.cs-CZ.xlf` se může změnit pod rukama.** Uživatel má vedle Claude Code otevřený VS Code s NAB AL Tools: když mezitím
upraví nebo smaže Label v `.al`, NAB Refresh přepíše `.cs-CZ.xlf` (osiřelý trans-unit zmizí, prefixy se přegenerují). Skript,
který hledá blok načtený před pár minutami, pak hlásí „0 matches" i při správném textu a konce řádků s tím nemají nic společného.
Před skriptovaným editem XLIFF zkontroluj `ls -la` (mtime) a `grep` na dané `NamedType` ID — a když je unit pryč, oprava už
není potřeba. (2026-10-22, cust-sonnentor-bc 65436, `WeightVolumeWithBagsLbl`.)

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
- **V node (bez pythonu v Bash toolu) počítej přes `BigInt`**, jinak `(h ^ b) * 16777619` přeteče přesnost `Number`
  (2^53) a hash je tiše špatně (`Caption` vyjde 3710425303 místo 2879900210):
  `h=0x811c9dc5n; for (const b of Buffer.from(name,"utf16le")) h=((h^BigInt(b))*16777619n)%4294967296n; return (h+2147483647n)%4294967296n`.
  Vždy si ověř `alhash("Caption")` = 2879900210, než ID zapíšeš. (2026-10-05, cust-soitron-bc, `CRM Project CWSOI.ebs_synchronizetobc`.)
- ID se skládá z `<Typ> <hash(jméno)>` po cestě od objektu k labelu:
  `Table X - Field Y - Property Z`. Source text se nehashuje — změna
  ToolTip textu ID nemění, **rename pole/objektu ano** (starý unit osiří).
  **Totéž refaktor:** lokální Label je `Codeunit X - Method <hash(procedura)> - NamedType <hash(label)>`,
  takže **přesun labelu do jiné procedury** (vytažení těla do helperu) nebo do globálních `var` objektu
  (`Codeunit X - NamedType Y`, bez Method) změní ID → v `.cs-CZ.xlf` osiří starý unit a LC0091 hlásí
  *Missing translation*, i když se text nezměnil. Oprava bez nového překladu: po kompilaci porovnej `.g.xlf`
  s `.cs-CZ.xlf` (MISSING × ORPHAN se shodným `NamedType` hashem) a v osiřelém unitu přepiš `id` + poznámku
  `Xliff Generator`, `<target>` nech. (2026-10-13, cust-alumistr-bc 63339 — `PrintCNCSentence` → `AppendCNCSentence`.)
- Use case: přidáváš pole a chceš rovnou doplnit překlad do `.cs-CZ.xlf`
  bez čekání na build + NAB Refresh — spočítej hash jména pole a napiš
  trans-unit ručně se správným ID. Refresh ho pak už jen potvrdí.
- **Skriptované doplnění unitů z `.g.xlf` do `.cs-CZ.xlf` — hlídej konce řádků.** `.g.xlf` generuje alc s **CRLF**, ručně
  vedené `.cs-CZ.xlf` / `.sk-SK.xlf` bývají **LF bez BOM**; když do nich zkopíruješ `<trans-unit>` blok z `.g.xlf` (node/python
  regex), vznikne soubor se smíšenými konci (`tr -cd '\r' < f | wc -c` > 0) a git hlásí „LF will be replaced by CRLF". Po vložení
  normalizuj (`sed -i 's/\r$//'` na LF souboru je tu správně) a zkontroluj duplicity ID (`grep -o 'trans-unit id="[^"]*"' | sort |
  uniq -d`). Postup, který seděl: node skript 1 = diff `.g.xlf` vs. překlady (MISSING / CHANGED source) → soubor pro Read tool
  (diakritika), skript 2 = mapa id → [cs, sk], MISSING vloží blok z `.g.xlf` + `<target>` před `</group>`, CHANGED přepíše
  `<source>` i `<target>` (6.3). Bez pythonu v Bash toolu (Store stub) jede node bez problémů. (2026-10-01, cust-soitron-bc 66504.)

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
- **Změna pořadí argumentů se starým `<target>` nespadne, jen prohodí hodnoty.** Label přepsaný z `'Operation started for:\Prod.
  Order No.: %1\Line No.: %2\Operation No.: %3'` na `'Operation %1 of production order %2 (line %3) has been started.'` a volání
  `Message(Lbl, OperationNo, ProdOrderNo, LineNo)` ukázalo v CZ klientu se starým targetem *Výrobní zakázka č.: 10, Číslo řádku:
  101006, Číslo operace: 10000*. Pořadí kroků: upravit label → zkompilovat (vznikne `.g.xlf`) → synchronizovat `.cs-CZ.xlf` →
  **zkompilovat znovu** a publikovat až tenhle build. Build z druhého kroku nese starý překlad, i když repo už je v pořádku.
  (2026-10-23, prod-em-kiosk-bc, hláška START kiosku v BC-DEV.)
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

- `AL0479` je jen **warning**, ale Essence build má `failOn = 'warning'` (viz 12.4 v `bc-al-workflow.md`) →
  **shodí CI**.

Zachyceno: cust-sonnentor-bc 2026-08-03 — merge masteru do feature větve zdvojil
trans-unit `PageExtension 2228984703 - NamedType 3852263291` (`OnlyProdOrderComponentErr`);
obě strany ho přidaly, každá na jinou pozici v souboru, git to spojil tiše.
