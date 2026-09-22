# BC/AL – autotesty: SaaS-only fallback bez `Tests-TestLibraries`

> **Referenční příloha `bc-al-autotests.md`** (vyčleněno 2026-09-22, soubor přesáhl 1000 řádků). Platí **jen pro čistý SaaS-only deploy test appky bez OnPrem CI** — pro Essence prod moduly je default MS `Tests-TestLibraries` (kanonická sekce v `bc-al-autotests.md`). Čti jen, když tenhle okrajový scénář řešíš.

### SaaS Cloud target = vlastní helpery (Tests-TestLibraries je onprem-only)

> ⚠️ **FALLBACK, ne default.** Tahle a následující dvě sekce („Minimal vlastní
> Assert ZLK", „Vlastní helpery bez Library-*") platí **jen pro čistý SaaS-only
> deploy test appky bez OnPrem CI**. **Pro Essence prod moduly to NEpoužívej** —
> máme OnPrem build (testovací BC DB se po PR vytvoří na serveru), takže jedeme MS
> `Tests-TestLibraries`. Viz kanonická sekce nahoře. Tohle nech jen jako referenci.

`Tests-TestLibraries` (publisher Microsoft, ID `5d86850b-0d76-4eca-bd7b-951ad998e997`) **není v Cloud SaaS targetu dostupná**. Je publikována jako onprem-only. `System Application Test Library` (ID `9856ae4f-...`) sice jde nainstalovat v SaaS, ale obsahuje hlavně mocky pro System modules (Email, AI, Permissions) — **nemá** business helpery (`Library - Sales/Inventory/ERM/...`) ani univerzální `Assert` codeunit.

Pro AL test app s `"target": "Cloud"`:

1. V `app.json` **nesmí** být dependency na `Tests-TestLibraries`. Pak ji nelze deployovat ani lokálně do SaaS sandboxu.
2. Pokud chceš sdílet kompilační target s produkčním Cloud appem, **napiš si vlastní minimal helpery** (Assert + LibraryX wrapper).
3. Test app fyzicky publikujete jen do dev kontejneru / sandbox / CI — produkční tenant ji nikdy neuvidí. Ale i kompilace musí být Cloud-compatible (žádné `DotNet`, `File`, `Assembly`, …).

Alternativa: nechat test app `"target": "OnPrem"` + závislost `Tests-TestLibraries`. Test app pak ale jde jen do container/CI/dev sandboxu, do SaaS produkce nikdy.

### Minimal vlastní `Assert ZLK` codeunit

Stačí na 90 % testovacích scénářů. `Format(Variant)` zajistí porovnání i pro Decimal/Date/Enum/Code:

```al
codeunit 52329 "Assert ZLK"
{
    procedure AreEqual(Expected: Variant; Actual: Variant; Msg: Text)
    begin
        if Format(Expected) <> Format(Actual) then
            Error('Assert.AreEqual failed: %1\n  Expected: <%2>\n  Actual:   <%3>', Msg, Format(Expected), Format(Actual));
    end;

    procedure IsTrue(Cond: Boolean; Msg: Text) begin if not Cond then Error('IsTrue failed: %1', Msg) end;

    procedure ExpectedError(Expected: Text)
    var
        Actual: Text;
    begin
        Actual := GetLastErrorText();
        if Actual = '' then Error('ExpectedError: no error (expected <%1>)', Expected);
        if StrPos(Actual, Expected) = 0 then Error('ExpectedError: expected <%1>, got <%2>', Expected, Actual);
    end;
}
```

**Pozn.** locale rozdíl pro Decimal — `Format(132.5)` vrací `132.5` v en-US a `132,5` v cs-CZ. Jelikož se však `Format(Expected)` i `Format(Actual)` volá ve stejném testu/locale, vyjde to stejně a porovnání projde.

### Vlastní helpery bez `Library - *` — vzor

Pro Cloud testy nahrazujeme MS Library helpery vlastní implementací. Klíčové triky:

- **Unique kódy** přes GUID:

  ```al
  procedure GenerateUniqueCode20(): Code[20]
  begin
      exit(CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20));
  end;
  ```

  GUID po `DelChr` má 32 znaků hex → zaručeně se vejdou na 10/20/50, žádný retry/sequence.

- **`Sales Header` bez No. Series**: ručně přiřaď `"No."` před `Insert(true)`. `OnInsert` pak nezavolá NoSeriesMgt, pokud je `"No."` neprázdné:

  ```al
  procedure CreateSalesHeader(var SH: Record "Sales Header"; DocType: Enum "Sales Document Type"; CustNo: Code[20])
  begin
      SH.Init();
      SH."Document Type" := DocType;
      SH."No." := GenerateUniqueCode20();
      SH.Insert(true);
      SH.Validate("Sell-to Customer No.", CustNo);
      SH.Modify(true);
  end;
  ```

- **`Sales Line` ručně inkrementovaný `Line No.`** po existujícím `FindLast` na filtru `Document Type` + `Document No.`. Insert(true) PŘED Validate Type/No./Quantity, jinak Validate na neuložené řádce může selhat.

- **Customer/Item/G/L Account**: minimal `Init + "No." := GenerateUniqueCode20() + Insert(true)` funguje pokud máte CRONUS/standard demo data se setupy (Inventory Setup, Sales & Receivables Setup s defaultními posting groups).

- **Release Sales Document**: `Codeunit "Release Sales Document".PerformManualRelease(SH)` — žádný handler nepotřebuje.

### Co vlastní helpery NEZvládnou bez setupu

- **Post Shipment / Post Invoice** — vyžaduje plný posting setup (Customer Posting Group, Gen. Posting Setup, VAT Posting Setup, Inventory Posting Setup, Locations…). Pro tyhle scénáře buď generujte plný setup, nebo nechte E2E v rovině "Release" a posting nezahrnujte.
- **Worksheet Lines (Requisition, Item Journal)**: `"Worksheet Template Name"` musí buď existovat v setupu nebo si ho vyrobte přes ručně přiřazené kódy přes `Insert(false)` (viz Req. Line Mgt. test pattern).

