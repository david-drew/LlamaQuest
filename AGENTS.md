# AGENTS.md

Implementation guidance for AI coding agents working in this repository.

## Project context

`llama-quest` is a Godot prototype that embeds a local LLM (`llama-server`) for:
- NPC dialogue
- quest generation
- world event generation
- lightweight memory summarization

The current implementation is a playable vertical slice centered on:
- a single `Main` scene UI loop
- system nodes under `Main/Systems`
- a generated town layout in `scenes/town.tscn`

Do not rewrite this project around an unimplemented overland/spec architecture unless the task explicitly asks for it.

## Critical directory rules (non-negotiable)

Never modify these directories:
- `bin/` (local `llama.cpp` / `llama-server` runtime files)
- `models/` (GGUF model files)

Treat both as external runtime assets, not source code.

## Engine and language rules

- Follow current Godot usage in this repo (project currently targets Godot 4.6 features).
- Use GDScript.
- Do not use ternary operators.
- Prefer readable, maintainable code over clever compression.
- Keep changes minimal and local to the relevant system.

## Current architecture (as implemented)

### Entry and scene wiring

- Main scene: `scenes/main.tscn`
- Town scene instance: `scenes/town.tscn` -> `scripts/world/town_generator.gd`
- Player scene: `scenes/player.tscn` -> `scripts/player.gd`

### Autoload singletons

- `LlmManager` (`scripts/autoloads/llm_manager.gd`)
- `QuestTracker` (`scripts/autoloads/quest_tracker.gd`)

### Systems under `Main/Systems`

- `LoreManager`: loads and serves lore from `data/lore/world_facts.json`
- `EventLogger`: stores short-term raw event memory
- `HistorySummarizer`: compresses recent events via LLM
- `QuestGenerator`: generates JSON quest payloads via LLM
- `EventGenerator`: generates JSON world events via LLM
- `WorldManager`: applies generated events to game state stubs
- `CombatManager`: currently lightweight/stubbed manager

### UI/action scripts

- `scripts/ui/btn_chat.gd`
- `scripts/ui/btn_work.gd`
- `scripts/sleep.gd`
- `scripts/ui/btn_exit.gd`
- `scripts/ui/btn_quit.gd`

These drive most player-facing prototype behavior.

## LLM pipeline contract

`LlmManager.query_llm()` is the transport boundary. It:
- boots local `llama-server` process
- sends OpenAI-style `/v1/chat/completions` requests
- expects JSON-only content from prompts
- parses and returns a `Dictionary`

When building features on top of LLM output:
- enforce required keys with validation helpers
- keep retry logic bounded
- return explicit error dictionaries on failure

Do not bypass `LlmManager` with custom HTTP logic unless a task requires transport-level changes.

## Data and schema notes

- Lore data source: `data/lore/world_facts.json`
- Schema reference: `data/data_schema.json` (if extending structured data, keep it aligned)

When adding new LLM JSON formats:
- update prompt examples
- add/extend validator checks
- keep keys stable across caller/callee boundaries

## Procgen status (important)

Town generation in `scripts/world/town_generator.gd` is currently the primary implemented map generator.

Dungeon generation in `scripts/world/dungeon_generator.gd` is partial/stubbed and should be treated as in-progress unless the task is specifically about expanding it.

Do not document or implement speculative systems as if already live.

## Change boundaries and expectations

When implementing a task:
1. Identify the existing layer first (`UI`, `Systems`, `Autoload`, `World Generator`, `Data`).
2. Modify the smallest correct surface area.
3. Preserve existing node paths used by `get_node(...)` and `%UniqueName` lookups.
4. Keep prompt contracts and downstream parsers in sync.

Avoid broad rewrites that break the prototype loop.

## Testing and verification

For meaningful logic changes, prefer quick manual validation with:
- run main scene
- test `Chat`
- test `Get Work`
- test `Sleep` day transition and event application
- verify no regressions in autoload startup/shutdown

If changing LLM responses or validators, test both success and failure paths.

## Safe default behavior for agents

Good:
- small, targeted fixes
- explicit validation and error handling
- preserving current scene wiring and node paths
- adding TODO stubs only when functionality is intentionally deferred

Bad:
- changing `bin/` or `models/`
- replacing stable prompt/JSON contracts without updating all consumers
- introducing architecture that does not match the current codebase
- large refactors without task-driven need
