# localpal
An offline-first LLM companion with chat sessions, configurable model management, custom persona (Pals) registry, and performance benchmarking.

## Build
dcc32 -B localpal.dpr

## Layout
- localpal.dpr: Program entry point. Launches the TApp orchestrator.
- localpal.dproj: MSBuild file compatible with the Delphi IDE.
- src/localpal.App.pas: Application orchestrator routing commands.
- src/localpal.CLI.pas: CLI option parser and help layout.
- src/localpal.Database.pas: FireDAC SQLite connection and schema migrations.
- src/localpal.Config.pas: Configuration key-value storage.
- src/localpal.Model.pas: Model manager with built-in catalog, HF search & download with progress.
- src/localpal.Chat.pas: Interactive chat sessions and fallback offline mode.
- src/localpal.Pal.pas: Assistant personas ("Pals") management, export & import.
- src/localpal.Benchmark.pas: Prompt/TG performance testing tool.

## Persistence
SQLite via FireDAC, schema auto-migrated in src/localpal.Database.pas.
Justified by: "offline-first LLM companion", "save/load/history/configurations" (requires storing chat sessions, messages, configuration, model metadata, and custom Pals).

## Design notes
- Runner communication uses System.Net.HttpClient to send OpenAI-compatible payloads to local runner (Ollama/llama.cpp).
- Standard offline mode kicks in if the local runner is unreachable, serving helpful interactive responses.
- Pal (persona) definitions can be exported to or imported from JSON files.
- Progress monitoring for HF downloads writes directly to console without linebreaks.
- Built-in model catalog includes state-of-the-art small models (Gemma 2, Qwen 2.5, Llama 3.2, Phi 3.5, Gemmasutra, SmolLM2, SmolVLM2) selectable via ID or alphanumeric key.
- Models are loaded and run externally. Localpal does not load model weights directly; it acts as a client that directs an external OpenAI-compatible runner (like Ollama or llama.cpp) via its API.

## Change log
- 2026-06-09: Integrated the built-in model catalog into the CLI and app orchestrator. Enabled `localpal model catalog` to list the catalog, and allowed `localpal model download <id|key>` to download directly by ID/key from the catalog. Verified with clean compile using dcc32.
- 2026-06-09: Fixed syntax bug in `localpal.Pal.pas` where a `try` block in `GetPal` was missing its `finally` block, causing build failure. Verified with clean compile using dcc32.
- 2026-06-09: Investigated model loading mechanism and documented that the project uses an external OpenAI-compatible local runner (defaulting to Ollama on http://localhost:11434/v1) rather than loading model files directly.
