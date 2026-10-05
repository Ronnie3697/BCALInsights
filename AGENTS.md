# BCALInsights — instrukce pro AI agenty otevřené přímo v tomhle repu

Repo jsou sdílené BC/AL poznámky a skilly (viz `README.md`). Platí, když AI nástroj běží
v klonu tohoto repa:

1. **Prvotní nastavení.** Na začátku seance ověř, jestli má nástroj, ve kterém běžíš, napojené
   skilly — junction do tohoto klonu: Claude Code `~/.claude/skills/bcal-insights`, Copilot /
   Codex `~/.agents/skills`, Antigravity `~/.gemini/config/skills`. Když chybí, nebo uživatel
   napíše „setup", „nastav mi to", „první instalace", nabídni průvodce **`SETUP.md`** a po
   souhlasu ho proveď krok za krokem. Když napojení sedí, setup nezmiňuj.
2. **Údržba notes** (úprava `skills/*/*.md`, README, skillů): pravidla jsou ve
   `skills/bc-al/SKILL.md` (sekce „Pravidla hry") a v `README.md` (sekce „Pravidla údržby");
   po změně pusť `python check-skills.py`.
