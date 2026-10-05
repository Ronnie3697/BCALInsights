# MCP servery pro BC/AL práci — jednorázová instalace (nový stroj / kolega)

> **Kdy číst:** jen když v `claude mcp list` chybí některý ze serverů níže, nebo stavíš
> nový stroj. Skilly `bc-al*` tenhle soubor **nenačítají** — startup checklist v
> `skills/bc-al/SKILL.md` na něj jen odkazuje pro případ „MCP není nakonfigurovaný".
> Celé prvotní nastavení (junctiony, always-on, MCP, PAT) s tebou interaktivně projde AI podle
> **`SETUP.md`** — tenhle soubor je k němu reference.
> Stav ověřen 2026-09-08, Claude Code 2.1.263, Windows 11; Azure DevOps launcher 2026-10-05.

| Server (název v Claude Code) | npm balíček | K čemu | Auth |
|---|---|---|---|
| `al-mcp-server` | [`al-mcp-server`](https://github.com/StefanMaron/AL-Dependency-MCP-Server) (Stefan Maroň) | symboly z `.alpackages` — objekty, členy, signatury, reference (7.2 v `bc-al-tools.md`) | žádná |
| `bc-code-intelligence` | [`bc-code-intelligence-mcp`](https://github.com/JeremyVyska/bc-code-intelligence-mcp) (Jeremy Vyska) | BC knowledge base + specialisté („Sam Coder"), workflow (krok 4 startup checklistu) | žádná |
| `azure-devops` | [`@azure-devops/mcp`](https://github.com/microsoft/azure-devops-mcp) (Microsoft) | tickety, PR, pipelines, wiki, search v org `essencebs` (7.9 v `bc-al-tools.md`) | PAT **read-only** v `MCP_PAT\DevOpsPAT.txt`, spouští launcher (krok 3) |
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
- Notes repo naklonované kamkoli (GitHub `essencebs/BCALInsights`, firemní —
  přístup dá DNEM) + junction skillů podle `README.md`.
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
shim je `.cmd`, ne exe. Příkazy pouštěj z **PowerShellu / cmd**, ne z Git Bash — MSYS přepíše
`/c` na `C:/` a server se nepřipojí (7.2b v `bc-al-tools.md`).

```
claude mcp add -s user al-mcp-server -- cmd /c al-mcp-server
claude mcp add -s user bc-code-intelligence -- cmd /c bc-code-intelligence-mcp
claude mcp add -s user d365bc-admin -- cmd /c d365bc-admin-mcp
claude mcp add -s user azure-devops -- node "<MCP_PAT>\ado-mcp.mjs"
```

`<MCP_PAT>` = složka s launcherem a PATem (krok 3). Volitelně:
`claude mcp add -s user playwright -- npx @playwright/mcp@latest`.

Výsledek v `~/.claude.json` (sekce `mcpServers`, pro kontrolu / ruční editaci):

```json
{
  "mcpServers": {
    "al-mcp-server":        { "type": "stdio", "command": "cmd", "args": ["/c", "al-mcp-server"], "env": {} },
    "bc-code-intelligence": { "type": "stdio", "command": "cmd", "args": ["/c", "bc-code-intelligence-mcp"], "env": {} },
    "d365bc-admin":         { "type": "stdio", "command": "cmd", "args": ["/c", "d365bc-admin-mcp"], "env": {} },
    "azure-devops":         { "type": "stdio", "command": "node", "args": ["<MCP_PAT>\\ado-mcp.mjs"], "env": {} }
  }
}
```

(Místo `node` jde i plná cesta `C:\\Program Files\\nodejs\\node.exe`; v JSON zdvojuj
backslashe, nebo piš cestu s `/`.)

Běžící seance MCP servery **nehot-loaduje** — po `claude mcp add` nebo editaci
`~/.claude.json` seanci restartuj (`/mcp` umí jen reconnect už zaregistrovaných).

## 3. Azure DevOps PAT (read-only, záměrně) — složka `MCP_PAT` + launcher

Token **není v žádném konfigu**. Leží jako surový text v `<MCP_PAT>\DevOpsPAT.txt` a MCP server
`azure-devops` se spouští přes launcher `<MCP_PAT>\ado-mcp.mjs` (šablona v repu:
`setup/ado-mcp.mjs`). Všechny AI nástroje volají stejný launcher → jeden soubor s PATem.

1. **Složka:** `<MCP_PAT>` = typicky `<složka s pracovními repy>\MCP_PAT` (např.
   `C:\WorkTasks\MCP_PAT`). Musí být **mimo git repo** a mimo OneDrive / sdílené složky. Zkopíruj
   do ní `setup/ado-mcp.mjs` z tohoto repa.
2. **PAT:** `https://dev.azure.com/essencebs/_usersSettings/tokens` → **New Token**, organizace
   `essencebs`, expirace max. 90 dní (firemní policy), scopes **jen Read**: Work Items (Read),
   Code (Read), Build (Read), Wiki (Read), Project and Team (Read), Identity (Read).
   **Žádný Write** — PR a zápisy do ADO dělá člověk, agent na 401 nemá nic obcházet
   (pravidlo 7.9 v `bc-al-tools.md`; tohle je zábrana, ne bug).
3. Ulož ho do **`<MCP_PAT>\DevOpsPAT.txt`** — jen surový PAT na jednom řádku, **bez e-mailu a bez
   base64** (launcher si ho zakóduje sám jako base64 `:PAT`, prázdný username ADO bere).
4. **Co launcher dělá při startu seance:** přečte `DevOpsPAT.txt` vedle sebe, nastaví
   `PERSONAL_ACCESS_TOKEN` a výchozí projekt `ado_mcp_project=Projects` (tooly bez parametru
   `project` se pak neptají formulářem na výběr projektu), zapne `ipv4first` (`aex.dev.azure.com` resolvuje na IPv6 a corp síť
   spojení resetuje — `fetch failed` / „Failed to fetch tenant") a spustí globálně nainstalovaný
   `@azure-devops/mcp` **ve stejném procesu** (start pod 1 s, po ukončení seance nezůstane
   sirotek). Bez globální instalace spadne na `npx -y @azure-devops/mcp` (pomalejší, riziko
   timeoutu). Další argumenty předá dál (např. `-d core work-items` omezí domény toolů).
5. **Po expiraci:** nový PAT → přepsat `<MCP_PAT>\DevOpsPAT.txt` → restart seance (nebo `/mcp` →
   reconnect `azure-devops`). Konfig se nemění.
6. **Starý způsob** (base64 `email:PAT` přímo v `env.PERSONAL_ACCESS_TOKEN` konfigu) funguje dál,
   ale token je pak v každém konfigu zvlášť a rotace = editace všech. Při přechodu záznam
   `azure-devops` nahraď voláním launcheru a `env` s tokenem smaž.

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
  správně. Server se nepřipojí a v logu je `Azure DevOps PAT file … is missing or empty` =
  chybí / prázdný `DevOpsPAT.txt` vedle launcheru; 401 už na čtení = PAT vypršel (krok 3.5).
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
pravidla pro každý nástroj. `azure-devops` je ve všech stejný: `node` + `<MCP_PAT>\ado-mcp.mjs`,
bez `env` (krok 3).

- **Codex CLI:** stejný 30s limit na handshake (`startup_timeout_sec`, default 30). Neřeš to
  `npx` — v Codexu volej `node.exe` + entry JS globálního balíčku
  (`%APPDATA%\npm\node_modules\al-mcp-server\dist\cli\install.js`) a nastav
  `startup_timeout_sec = 60`; detail a proč v `README.md` (sekce Codex). Ověření: `/mcp` v TUI,
  nebo v `~/.codex/logs_2.sqlite` tabulka `logs`, target `codex_rmcp_client::stdio_server_launcher`
  — úspěšný start má řádek „AL MCP Server started successfully".

## 8. Oficiální BC MCP server (data z BC)

Zatím **draft** — `bc-al-mcp-server.md`: M1 konfigurace v BC (page 8350/8351), M2 oficiální
auth přes Entra app registraci, M4 ověřená oklika s device loginem + `headersHelper`,
M6 spuštění přes `claude --mcp-config <json>` (nic se nepersistuje). Do `~/.claude.json`
ho zatím nedávej.
