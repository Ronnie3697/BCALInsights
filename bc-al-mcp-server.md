# BC/AL poznámky — Oficiální Business Central MCP server (DRAFT)

> **Stav: draft „bokem", 2026-09-04.** Zatím **není v Routeru** ani ve skillech — až se ověří,
> co všechno přes MCP server jde, přesune se jako sekce 7.20 do `bc-al-tools.md` (nebo zůstane
> samostatný skill). Zdroj: test na `cust-sonnentor-bc`, prostředí **BC-DEV2**, konfigurace
> `ClaudeDNEM`, Claude Code 2.1.260, Windows 11.

Obsahuje:
- **M1.** Co to je a jak se konfiguruje v BC (stránky, pole, systémové tooly)
- **M2.** Autentizace — oficiální cesta (Entra app registrace) a proč je nutná
- **M3.** Claude Code mechanika — `--mcp-config`, žádný hot-reload, `/mcp`, `headersHelper` kontrakt
- **M4.** Oklika bez app registrace — first-party client + device login + headersHelper (ověřeno)
- **M5.** Gotchas z testu (PSModulePath, DPAPI, heredoc, BC web client v Chrome)
- **M6.** Kde leží testovací soubory a jak se to spouští
- **M7.** Otevřené otázky

## M1. Co to je a konfigurace v BC

Oficiální Microsoft MCP server pro BC online: **`https://mcp.businesscentral.dynamics.com`**,
transport `http` (Streamable HTTP, protokol `2025-06-18`). Jeden endpoint pro všechny tenanty,
cíl se určuje **HTTP hlavičkami**:

| Hlavička | Hodnota |
|---|---|
| `TenantId` | Entra tenant GUID prostředí |
| `EnvironmentName` | název BC prostředí (`BC-DEV2`) |
| `Company` | název company (`Sonnentor s.r.o.`) |
| `ConfigurationName` | (volitelně) název MCP konfigurace v BC; prázdné = read-only ke všem API pages |

Non-ASCII hodnoty (`ø`, `å`, `č`…) v `Company` / `ConfigurationName` kódovat jako
`=?base64?<utf8-base64>?=`.

**BC stránky (BC 28, CZ UI „Konfigurace serveru protokolu kontextu modelu (MCP)"):**

| Page | Co |
|---|---|
| 8350 | seznam konfigurací (akce Rozšířené → Připojovací řetězec / Aplikace Entra / Export / Import) |
| 8351 | karta konfigurace (docs odkazují `?page=8351`, otevře přímo kartu; na kartě je pod Rozšířené jen Připojovací řetězec) |
| 8357 | **MCP Server Entra Applications** — evidence client ID app registrací (jen poznámka, nic nevynucuje) |
| 8359 | MCP Configuration Warnings |

Pole konfigurace: **Active**, **Default**, **Dynamic Tool Mode**, **Discover Additional Objects**
(read-only k API pages mimo seznam; funguje jen s Dynamic Tool Mode), **Unblock Edit Tools**
(bez něj jsou všechny tooly read-only), **Available Tools** = API pages (jen top-level, ne
ListPart/CardPart) s Allow Read/Create/Modify/Delete/Bound Actions. Akce „Přidat nástroje podle
skupiny API" / „Add All Standard APIs as Tools". Konfigurace jde exportovat/importovat jako JSON.
Permission set **MCP - ADMIN**.

**Tooly:**
- Dynamic Tool Mode **off** → per API page: `List<obj>_PAG<ID>`, `Create<obj>_PAG<ID>`,
  `ListUpdate<obj>_PAG<ID>`, `Delete<obj>_PAG<ID>`, `<boundAction>_PAG<ID>`.
- Dynamic Tool Mode **on** → jen 3 systémové tooly **`bc_actions_search`** (`SearchText`,
  `SearchMode` = `keyword` | `semantic`, `ActionType` enum, např. `List`), **`bc_actions_describe`**
  (`ActionName`), **`bc_actions_invoke`** (`ActionName`, `RequestParameters` = JSON string, např.
  `{"filter": "status eq 'Active'"}`). Názvy akcí z search: `List_CustomerLedgerEntries_QRY30302`,
  `List_AgedAccountsReceivableOfCustomer_PAG30031`… (i query objekty `QRY`).
- **Pozor:** i s prázdným Available Tools a Discover Additional Objects = off vrátil
  `bc_actions_search` (keyword `customer`, `ActionType=List`) 15 standardních akcí. Co z nich
  `invoke` reálně pustí, je otevřené (M7).

„Připojovací řetězec" z BC (`Advanced → Connection String`) je jen fragment
`"businesscentral": { url, type, headers }` — **bez `mcpServers` wrapperu a bez OAuth bloku**, do
Claude Code se musí doplnit (M2/M3).

Docs: [Configure MCP Server](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/ai/configure-mcp-server),
[Non-Microsoft hosts (Claude, Copilot CLI, ChatGPT)](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/ai/use-mcp-server-non-microsoft),
[VS Code](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/ai/use-mcp-server-in-vscode).

## M2. Autentizace — oficiální cesta

Server bez tokenu vrací `401` s `WWW-Authenticate: Bearer resource_metadata=
https://mcp.businesscentral.dynamics.com/.well-known/oauth-protected-resource`; metadata:
`authorization_servers: ["https://login.microsoftonline.com/common/v2.0"]`,
`scopes_supported: ["https://mcp.businesscentral.dynamics.com/Financials.ReadWrite.All"]`, PKCE S256.
Žádný API key / basic auth režim neexistuje.

**Entra ID neumí Dynamic Client Registration** (v `/.well-known/openid-configuration` chybí
`registration_endpoint`), takže MCP host potřebuje **client ID vlastní app registrace**:

1. Entra admin center → App registrations → New (role Application Developer), Supported account
   types = **Multiple Entra ID tenants**.
2. Authentication → platforma **Mobile and desktop applications** → redirect URI hosta; Claude Code
   = `http://localhost:<port>/callback` (docs příklad port **33418**).
3. API permissions → **Dynamics 365 Business Central → Delegated → Financials.ReadWrite.All** →
   **Grant admin consent** (v tenantu zákazníka).
4. (Volitelně) zapsat client ID do BC page 8357.

Claude Code config (docs příklad):

```json
{
  "mcpServers": {
    "businesscentral": {
      "type": "http",
      "url": "https://mcp.businesscentral.dynamics.com",
      "headers": { "TenantId": "…", "EnvironmentName": "…", "Company": "…", "ConfigurationName": "…" },
      "oauth": { "clientId": "<app-client-id>", "callbackPort": 33418 }
    }
  }
}
```

CLI ekvivalent: `claude mcp add --transport http businesscentral <url> -H "TenantId: …" …
--client-id <id> --callback-port 33418` (a `--client-secret` pro confidential klienty).
V seanci pak `/mcp → businesscentral → Authenticate` (browser), pro `-p` režim předem
`claude mcp login businesscentral`.

## M3. Claude Code mechanika (ověřeno 2.1.260)

- **Běžící seance MCP servery nehot-loaduje.** `claude mcp add`, editace `.mcp.json` /
  `~/.claude.json` se projeví až po restartu; `/mcp` umí jen reconnect/authenticate existujících.
- **`claude --mcp-config <soubor|json>`** načte servery jen pro tu seanci, **nic nepersistuje**;
  JSON **musí mít wrapper `mcpServers`**; lze víc souborů; **`--strict-mcp-config`** vypne všechny
  ostatní nakonfigurované servery (izolace testu). Funguje i v `-p`.
- **`headersHelper`** (vedle `type`/`url`): cesta k exe/skriptu nebo shell příkaz; **stdout = JSON
  objekt string→string** (nic jiného); **timeout 10 s**; spouští se **při připojení a po 401/403**
  (žádné cachování, cachuj si sám); dynamické hlavičky **přepíší** statické `headers` stejného
  jména; když vrátí **`Authorization`, Claude Code vlastní OAuth přeskočí** (client ID netřeba);
  env: `CLAUDE_CODE_MCP_SERVER_NAME`, `CLAUDE_CODE_MCP_SERVER_URL`, (`CLAUDE_PLUGIN_ROOT`).
  Na Windows spolehlivě: absolutní cesta na `.cmd` wrapper, který volá
  `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <ps1>`.
- Test bez UI: `claude -p --model haiku --strict-mcp-config --mcp-config <json>
  --allowedTools "mcp__businesscentral__*" --output-format json "<prompt>"` — 3 tahy s haiku
  trvaly ~190 s (většina je MCP connect + model), výsledek v `.result`.

## M4. Oklika bez app registrace (ověřeno 2026-09-04, BC-DEV2)

**Princip:** token si obstarám sám a předám ho přes `headersHelper` v `Authorization`, Claude Code
pak OAuth neřeší. Token vydá Entra **Microsoft first-party public clientovi „Microsoft Azure
PowerShell" `1950a258-227b-4e31-a9cf-717495945fc2`** — to je default `$clientID` v
`New-BcAuthContext` (BcContainerHelper, `Auth\New-BcAuthContext.ps1`, help: „well known
PowerShell AAD App ID"), na kterém stojí device login BcContainerHelperu proti BC API. MCP
resource sdílí Entra app „Dynamics 365 Business Central" (stejná delegated permission
`Financials.ReadWrite.All`), takže first-party pre-consent platí i pro
`https://mcp.businesscentral.dynamics.com`. Ověřeno: device login vrátil token s
`aud=https://mcp.businesscentral.dynamics.com`, `scp=Financials.ReadWrite.All`,
`appid=1950a258-…`, bez consent chyby.

**Flow:**
1. **Device code login** (jednorázově, přímý REST, bez modulů):
   `POST https://login.microsoftonline.com/<tenant>/oauth2/v2.0/devicecode`
   (`client_id`, `scope = https://mcp.businesscentral.dynamics.com/Financials.ReadWrite.All offline_access`)
   → uživatel zadá `user_code` na `https://login.microsoft.com/device` → polling
   `POST …/oauth2/v2.0/token` s `grant_type=urn:ietf:params:oauth:grant-type:device_code`
   (`authorization_pending` → čekat, `slow_down` → +5 s). Refresh token uložit **DPAPI**
   (`[Security.Cryptography.ProtectedData]::Protect(..., 'CurrentUser')` → base64 soubor).
2. **headersHelper**: DPAPI unprotect → `POST …/oauth2/v2.0/token` `grant_type=refresh_token`
   (client_id, refresh_token, scope) → uložit rotovaný refresh token → vypsat JSON hlaviček
   `Authorization: Bearer …` + TenantId/EnvironmentName/Company/ConfigurationName. Běh ~1,3 s.
3. `claude --mcp-config <json s headersHelper>` → server connected, `tools/list` = 3 systémové tooly.

**Bezpečnost / caveaty:** neoficiální trik (client ID patří Microsoftu, ne nám), na produkci
udělat vlastní app registraci (M2). Refresh token leží na disku (DPAPI per Windows user), životnost
~90 dní neaktivity → pak znovu device login. Nikdy nevypisovat tokeny do logu/konzole; skripty
vypisují jen `aud/scp/appid/exp` dekódované z JWT. Přihlášení dělá **uživatel sám** v prohlížeči
(device code je veřejný, heslo Claude nikdy nevidí).

## M5. Gotchas z testu

- **Claude Code Bash tool → `powershell.exe` (5.1) má PSModulePath s cestami PowerShellu 7 napřed**
  (`C:\Program Files\PowerShell\Modules`, WindowsApps `microsoft.powershell_7.x`). Autoload pak
  sáhne po PS7 verzi `Microsoft.PowerShell.Security` a 5.1 ji **nenačte**: `Import-Module
  BcContainerHelper` padá na `Get-Acl` (`Check-BcContainerHelperPermissions.ps1`),
  `ConvertTo-SecureString` hlásí „module could not be loaded". Řešení: nepoužívat cmdlety z
  Security modulu — .NET `ProtectedData` (`Add-Type -AssemblyName System.Security` v 5.1), nebo
  spouštět `pwsh`. Jeden pokus o login tím propadl (token přišel, uložení spadlo → login znovu).
- **Bash heredoc sráží `\\` na `\`** → JSON s Windows cestou (`"C:\\Users\\…"`) je po heredocu
  nevalidní (`Invalid \escape`). JSON s backslashy zapisovat **Write toolem** (viz 7.1).
- **`sleep` ve foreground Bashi je blokovaný**, ale `until`/`for` smyčka se `sleep 1` v
  `run_in_background` funguje — použito na čekání na device code v logu (jedna notifikace).
- **BC web client v Chrome (claude-in-chrome):** `find` / `read_page` / `get_page_text` **nevidí obsah
  BC stránky** (jen shell), ovládá se jen screenshot + souřadnice. Okno se během seance
  přeškálovalo (1288×952 → 1309×924) → souřadnice z předchozího screenshotu minou; před klikem
  nový screenshot. `Escape` zavře i celou list page (skočí na Role Center). `?page=8351` otevře
  rovnou kartu jediné konfigurace, seznam je `?page=8350`.
- `az` CLI, Az PowerShell ani MSAL.PS na stroji nejsou; `@demiliani/d365bc-admin-mcp` je
  zkompilované .NET exe (client ID z něj nevytáhneš stringy) a jeho `get_microsoft_entra_id_token`
  má fixní scope admin API — pro MCP resource nepoužitelné.
- Subagent `claude-code-guide` tvrdil, že statické `headers` a OAuth nejdou kombinovat — **MS docs
  i CLI (`--header` + `--client-id`) říkají opak**; docs agenta brát s rezervou u detailů.

## M6. Testovací soubory a spuštění

Vše mimo `~/.claude.json` / `.mcp.json` (záměr: nic nepersistovat), složka
**`%LOCALAPPDATA%\bc-mcp-test\`** (smazáním zmizí i refresh token):

| Soubor | Účel |
|---|---|
| `bc-mcp-dev2.json` | `--mcp-config` (wrapper `mcpServers`, statické hlavičky + `headersHelper`) |
| `bc-mcp-headers.cmd` / `.ps1` | headersHelper (refresh flow, DPAPI, JSON na stdout, chyby na stderr, exit 1) |
| `bc-mcp-login.ps1` | jednorázový device login, uloží `refresh.dpapi` |
| `refresh.dpapi` | DPAPI-šifrovaný refresh token (neverzovat, nesdílet) |

```
claude --mcp-config "C:\Users\dnem\AppData\Local\bc-mcp-test\bc-mcp-dev2.json"
```

(`--strict-mcp-config` pro izolaci; `-p` varianta viz M3.) Ruční probe bez Claude:
python skript = helper → `initialize` → `notifications/initialized` (s `Mcp-Session-Id`) →
`tools/list` / `tools/call`; odpovědi chodí jako JSON nebo SSE (`data:` řádky).

## M7. Otevřené otázky

- Co `bc_actions_invoke` pustí, když Available Tools je prázdný a Discover Additional Objects off
  (search vrací akce, invoke možná ne). Otestovat + zkusit zapnout Discover / přidat API group.
- `semantic` vs `keyword` search kvalita, hodnoty enumu `ActionType`.
- Vlastní API pages (customer extensions, `APIPublisher`) — objeví se v search? Bound actions?
- Životnost `Mcp-Session-Id`, chování po 401 (helper se má znovu spustit) — ověřit v dlouhé seanci.
- Copilot Studio limit 70 toolů vs Dynamic Tool Mode — relevantní jen pro Copilot Studio agenty.
