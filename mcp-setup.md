# MCP servery pro BC/AL práci — jednorázová instalace (nový stroj / kolega)

> **Kdy číst:** jen když v `claude mcp list` chybí některý ze serverů níže, nebo stavíš
> nový stroj. Skilly `bc-al*` tenhle soubor **nenačítají** — startup checklist v
> `skills/bc-al/SKILL.md` na něj jen odkazuje pro případ „MCP není nakonfigurovaný".
> Stav ověřen 2026-09-08, Claude Code 2.1.263, Windows 11.

| Server (název v Claude Code) | npm balíček | K čemu | Auth |
|---|---|---|---|
| `al-mcp-server` | [`al-mcp-server`](https://github.com/StefanMaron/AL-Dependency-MCP-Server) (Stefan Maroň) | symboly z `.alpackages` — objekty, členy, signatury, reference (7.2 v `bc-al-tools.md`) | žádná |
| `bc-code-intelligence` | [`bc-code-intelligence-mcp`](https://github.com/JeremyVyska/bc-code-intelligence-mcp) (Jeremy Vyska) | BC knowledge base + specialisté („Sam Coder"), workflow (krok 4 startup checklistu) | žádná |
| `azure-devops` | [`@azure-devops/mcp`](https://github.com/microsoft/azure-devops-mcp) (Microsoft) | tickety, PR, pipelines, wiki, search v org `essencebs` (7.9 v `bc-al-tools.md`) | PAT **read-only** |
| `d365bc-admin` | [`@demiliani/d365bc-admin-mcp`](https://github.com/demiliani/D365BCAdminMCP) | BC Admin Center API — prostředí, nainstalované appky, sessions, storage, update window | Entra login při prvním volání |
| `playwright` (volitelné) | `@playwright/mcp` | browser automatizace (BC web klient, dokumentace) | žádná |
| `businesscentral` (draft) | oficiální MS MCP server `mcp.businesscentral.dynamics.com` | data z BC přes API pages | Entra OAuth → viz `bc-al-mcp-server.md` |

Vedle toho je plugin **`bcal-insights`** (tenhle repo jako skilly) — instalace v `README.md`,
sekce „Claude Code skilly". Bez skillů nemá MCP kdo používat, bez MCP skilly fungují, ale
agent hádá signatury z paměti.

## 0. Prerekvizity

- **Node.js 18+** (LTS) a npm; `npm prefix -g` → `%APPDATA%\npm` musí být v `PATH`
  (tam žijí globální shimy `*.cmd`, které Claude Code volá).
- **.NET SDK 8+** (potřebuje `al-mcp-server`).
- **Claude Code** nainstalované (`claude --version`).
- Notes repo naklonované do `C:\WorkTasks\BCALInsights` (privátní GitHub
  `Ronnie3697/BCALInsights` — přístup dá DNEM) + junction skillů podle `README.md`.
- Účet v Azure DevOps org `essencebs` (pro PAT) a Entra účet s admin rolí v BC tenantech
  zákazníků (pro `d365bc-admin`; bez toho ten server prostě přeskoč).

## 1. Globální npm instalace

```
npm i -g al-mcp-server bc-code-intelligence-mcp @azure-devops/mcp @demiliani/d365bc-admin-mcp
```

**Proč globálně a ne `npx -y <balíček>` (jak radí README těch projektů):** Claude Code dává
každému MCP serveru 30 s na handshake. `npx` sahá při každém startu na npm registry (i s
cachovaným balíčkem) a při pomalé síti / AV skenu to nestihne → server pro celou seanci
tiše zmizí (`CONNECT_TIMEOUT`, detail v 7.2 `bc-al-tools.md`). Globální shim startuje pod
1 s. Daň: verze se samy neaktualizují (viz 6).

## 2. Registrace v Claude Code

Scope **`user`** = `~/.claude.json` → platí pro všechna repa. Bez `-s user` se server zapíše
jen pro aktuální složku (scope `local`) a v jiném repu chybí. `cmd /c` je na Windows nutné —
shim je `.cmd`, ne exe.

```
claude mcp add -s user al-mcp-server -- cmd /c al-mcp-server
claude mcp add -s user bc-code-intelligence -- cmd /c bc-code-intelligence-mcp
claude mcp add -s user d365bc-admin -- cmd /c d365bc-admin-mcp
claude mcp add -s user azure-devops -e PERSONAL_ACCESS_TOKEN=<base64, viz 3> -e NODE_OPTIONS=--dns-result-order=ipv4first -- cmd /c mcp-server-azuredevops essencebs --authentication pat
```

Volitelně: `claude mcp add -s user playwright -- npx @playwright/mcp@latest`.

Výsledek v `~/.claude.json` (sekce `mcpServers`, pro kontrolu / ruční editaci):

```json
{
  "mcpServers": {
    "al-mcp-server":        { "type": "stdio", "command": "cmd", "args": ["/c", "al-mcp-server"], "env": {} },
    "bc-code-intelligence": { "type": "stdio", "command": "cmd", "args": ["/c", "bc-code-intelligence-mcp"], "env": {} },
    "d365bc-admin":         { "type": "stdio", "command": "cmd", "args": ["/c", "d365bc-admin-mcp"], "env": {} },
    "azure-devops": {
      "type": "stdio", "command": "cmd",
      "args": ["/c", "mcp-server-azuredevops", "essencebs", "--authentication", "pat"],
      "env": { "NODE_OPTIONS": "--dns-result-order=ipv4first", "PERSONAL_ACCESS_TOKEN": "<base64>" }
    }
  }
}
```

Běžící seance MCP servery **nehot-loaduje** — po `claude mcp add` nebo editaci
`~/.claude.json` seanci restartuj (`/mcp` umí jen reconnect už zaregistrovaných).

## 3. Azure DevOps PAT (read-only, záměrně)

1. `https://dev.azure.com/essencebs/_usersSettings/tokens` → **New Token**, organizace
   `essencebs`, expirace max. 90 dní (firemní policy), scopes **jen Read**: Work Items (Read),
   Code (Read), Build (Read), Wiki (Read), Project and Team (Read), Identity (Read).
   **Žádný Write** — PR a zápisy do ADO dělá člověk, agent na 401 nemá nic obcházet
   (pravidlo 7.9 v `bc-al-tools.md`; tohle je zábrana, ne bug).
2. Hodnota do `PERSONAL_ACCESS_TOKEN` = base64 z `email:PAT` (PowerShell):

   ```powershell
   [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("jmeno.prijmeni@essencebs.com:<PAT>"))
   ```

3. Po expiraci: nový PAT → přepsat `env.PERSONAL_ACCESS_TOKEN` u serveru `azure-devops`
   v `~/.claude.json` → restart seance.
4. `NODE_OPTIONS=--dns-result-order=ipv4first` je jen u tohoto serveru: `aex.dev.azure.com`
   resolvuje na IPv6 a corp síť spojení resetuje (`fetch failed` / „Failed to fetch tenant").
   Stejný trik platí pro jakýkoli Node MCP server volající MS API.

## 4. Pojistka proti timeoutu

`~/.claude/settings.json`:

```json
{ "env": { "MCP_TIMEOUT": "90000" } }
```

(90 s místo 30 s na handshake; s globálními shimy se to normálně nevyužije, ale zachrání
seanci při prvním startu po restartu Windows.)

## 5. Ověření

- `claude mcp list` → u všech čtyř `✔ Connected` (postman „Needs authentication" je jiný
  plugin, ignoruj).
- V seanci `/mcp` → seznam + reconnect / authenticate.
- `al-mcp-server`: index je po startu **prázdný** → `al_packages` s `action: "load"` a
  `path` = root repa (sdílená `.alpackages`); pak `al_search_objects`. Detail 7.2.
- `bc-code-intelligence`: nejdřív `set_workspace_info` s rootem workspace, jinak všechny
  tooly vrací „Server Not Yet Initialized"; pak `ask_bc_expert`
  (`preferred_specialist: "sam-coder"`).
- `azure-devops`: `wit_work_item` (get) na libovolné ID ticketu. Zápisový tool → 401 =
  správně.
- `d365bc-admin`: `get_microsoft_entra_id_token` spustí Entra přihlášení (browser / device
  code) účtem s admin rolí v tenantu zákazníka; token se cachuje
  (`get_token_cache_status`, `clear_cached_token` při změně účtu). Potom např.
  `get_environment_informations`. Tenant GUID z názvu: `get_tenant_id_from_tenant_name`.

## 6. Údržba a diagnostika

- Globální balíčky se samy neaktualizují: občas `npm update -g`; stav `npm ls -g --depth=0`.
- Server „není v nabídce" = skoro vždy `CONNECT_TIMEOUT` při startu, ne rozbitý balíček.
  Log: `%LOCALAPPDATA%\claude-cli-nodejs\Cache\<projekt>\mcp-logs-<server>\<timestamp>.jsonl`.
  Ruční test: spusť shim v terminálu a pošli JSON-RPC `initialize` na stdin.
- `al-mcp-server` vrací u base app **jen signatury**, ne těla procedur → GitHub
  `StefanMaron/MSDyn365BC.Code.History` (7.2/7.3). `ByReference` u event parametrů mu nevěř
  (5.y v `bc-al-objects.md`).

## 7. Jiné klienty (Copilot CLI, Codex, VS Code, Antigravity)

Stejné npm balíčky (krok 1), jiný formát konfigu. Hotové snippety per nástroj — VS Code
`mcp.json` (klíč `servers`), Copilot CLI `~/.copilot/mcp-config.json`, Codex
`~/.codex/config.toml`, Antigravity `~/.gemini/config/mcp_config.json` — jsou v `README.md`,
sekce „Nový stroj / kolega — jak si to přidat", spolu s junctiony skillů a šablonou startup
pravidla pro každý nástroj.

## 8. Oficiální BC MCP server (data z BC)

Zatím **draft** — `bc-al-mcp-server.md`: M1 konfigurace v BC (page 8350/8351), M2 oficiální
auth přes Entra app registraci, M4 ověřená oklika s device loginem + `headersHelper`,
M6 spuštění přes `claude --mcp-config <json>` (nic se nepersistuje). Do `~/.claude.json`
ho zatím nedávej.
