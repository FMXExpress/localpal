# localpal
An offline-first LLM companion with chat sessions, configurable model management, custom persona (Pals) registry, and performance benchmarking.

## Build
dcc64 -B localpal.dpr
(or: msbuild localpal.dproj /p:Platform=Win64)

The bundled llama.cpp DLLs are x64, so the project must be built for Win64.
The vendored llama-cpp-delphi units reference RTL units by their short names
(e.g. Generics.Collections, Windows), so the build must supply unit scope
names (namespaces). For command-line dcc this lives in localpal.cfg as -NS
(System;Winapi;...) alongside the -U unit search paths; for IDE/msbuild it is
DCC_Namespace + DCC_UnitSearchPath in localpal.dproj. At runtime,
llama.dll/ggml.dll are looked up in the "lib_dir" config value, then
<exedir>\llamacpp, then next to the executable.

## Layout
- localpal.dpr: Program entry point. Launches the TApp orchestrator.
- localpal.dproj: MSBuild file compatible with the Delphi IDE.
- localpal.cfg: Unit search paths for command-line dcc builds.
- src/localpal.App.pas: Application orchestrator routing commands.
- src/localpal.CLI.pas: CLI option parser and help layout.
- src/localpal.Database.pas: FireDAC SQLite connection and schema migrations.
- src/localpal.Config.pas: Configuration key-value storage.
- src/localpal.Model.pas: Model manager with built-in catalog, HF search & download with progress.
- src/localpal.Engine.pas: In-process inference engine wrapping the vendored llama-cpp-delphi bindings (DLL discovery/loading, model lifecycle, streaming chat completions).
- src/localpal.Chat.pas: Interactive chat sessions, engine selection (builtin/runner/offline) and fallback offline mode.
- src/localpal.Pal.pas: Assistant personas ("Pals") management, export & import.
- src/localpal.Benchmark.pas: Prompt/TG performance testing tool (built-in engine or runner).
- src/llama_cpp/: Vendored llama-cpp-delphi library (Embarcadero), used for in-process GGUF inference.

## Persistence
SQLite via FireDAC, schema auto-migrated in src/localpal.Database.pas.
Justified by: "offline-first LLM companion", "save/load/history/configurations" (requires storing chat sessions, messages, configuration, model metadata, and custom Pals).

## Design notes
- Two inference engines, selected per model by the "engine" config key (auto|builtin|runner):
  - builtin: GGUF models are loaded in-process via the vendored llama-cpp-delphi bindings (src/localpal.Engine.pas). Responses stream token-by-token to the console. Chat templates are auto-detected from GGUF metadata by the library.
  - runner: System.Net.HttpClient sends OpenAI-compatible payloads to a local runner (Ollama/llama.cpp server) at runner_url.
  - auto (default): builtin when the active model path is an existing .gguf file and the llama.cpp DLLs are found; otherwise runner.
- Standard offline mode kicks in if no model is available or both engines fail, serving helpful interactive responses.
- CLI ergonomics: `localpal chat` resumes/creates a session with zero arguments; `localpal chat "<msg>"` is a one-shot question; chat subcommands accept session names as well as IDs; --model/--pal flags override per invocation; `model download` auto-activates the downloaded model.
- Pal (persona) definitions can be exported to or imported from JSON files.
- Progress monitoring for HF downloads writes directly to console without linebreaks.
- Built-in model catalog is tiered via the TCatalogItem.Tier field (mtLowEnd/mtHighEnd/mtServer): low-end (Gemma 2, Qwen 2.5, Llama 3.2, Phi 3.5, Gemmasutra, SmolLM2, SmolVLM2, LFM2.5 1.2B, Qwen 2.5 Coder 7B) runs on CPU/small GPUs and is shown by default; high-end (Qwen 3.6 27B & 35B-A3B, Gemma 4 26B-A4B & 31B, Qwen 3 Coder 30B-A3B, 24GB+) and server-class (GPT-OSS 120B, Qwen 3.5 122B-A10B, GLM-4.7; 64GB+ and 60-200GB+ downloads) are shown only with `model catalog --all`. Each item carries a MinRamGB hint.
- Downloader (TModelManager.DownloadModel) handles single-file and sharded GGUFs. If the filename matches `-NNNNN-of-MMMMM.gguf` it downloads every part (preserving any HF quant subdirectory in the URL, storing shards flat in models/ so siblings sit together) and registers the first shard; llama.cpp auto-loads the rest. DownloadOneFile is the shared per-file helper.
- Engine config keys: n_ctx (context window, default 4096), n_gpu_layers (0 = CPU only), lib_dir (explicit DLL folder), chat_format (named prompt format), engine_log (on = let llama.cpp print its native load/metadata logs; default off via a no-op llama_log_set callback). llava_shared.dll is loaded only if present (needed for multimodal models only).
- Chat format: the vendored library's Jinja2 GGUF-template formatter is an unimplemented stub and its template auto-detection is exact-match only, so localpal.Engine always sets a named ChatFormat before Init: chat_format config key (validated against the registered formatter collection) > guess from the model file name (qwen/gemma/llama-3/chatml/...) > chatml default.

## Change log
- 2026-06-09: Integrated the built-in model catalog into the CLI and app orchestrator. Enabled `localpal model catalog` to list the catalog, and allowed `localpal model download <id|key>` to download directly by ID/key from the catalog. Verified with clean compile using dcc32.
- 2026-06-09: Fixed syntax bug in `localpal.Pal.pas` where a `try` block in `GetPal` was missing its `finally` block, causing build failure. Verified with clean compile using dcc32.
- 2026-06-09: Investigated model loading mechanism and documented that the project uses an external OpenAI-compatible local runner (defaulting to Ollama on http://localhost:11434/v1) rather than loading model files directly.
- 2026-06-10: Integrated in-process GGUF inference via the vendored llama-cpp-delphi library (new src/localpal.Engine.pas; engine selection in chat and benchmark with runner/Ollama kept as fallback; streaming token output). Overhauled chat CLI ergonomics: `localpal chat` / `chat "<msg>"` with no IDs, session names accepted everywhere, --model/--pal per-invocation overrides, downloads auto-activate. Build moved to Win64 (dcc64/msbuild) because the bundled llama.cpp DLLs are x64. NOT yet compile-verified (no Delphi compiler in the authoring environment).
- 2026-06-10: Fixed F2613 "Unit 'Generics.Collections' not found" on command-line dcc builds: the vendored library uses short RTL unit names, so added the -NS unit scope names (System;Winapi;...) to localpal.cfg and made the dproj DCC_Namespace explicit about System;Winapi.
- 2026-06-10: Fixed runtime error 'Please, set the "ChatFormat" option in your settings' from the built-in engine: the vendored Jinja2 formatter is an unimplemented stub, so localpal.Engine now always sets a named ChatFormat before model load (new chat_format config key > model file-name guess > chatml default), validated against the registered formatter names. Added chat_format to config defaults and help.
- 2026-06-10: Benchmark accuracy & console output fixes. The library's non-streaming response leaves Usage as uninitialized garbage (PP showed 8.4M tokens), so the built-in benchmark now measures for real: prompt tokens via the model tokenizer (CountTokens), completion tokens counted from streamed chunks, and the PP/TG split timed by time-to-first-token. llama.cpp's native metadata dump on model load is silenced via llama_log_set (re-enable with engine_log=on). Replaced emoji rating labels with ASCII and set the Windows console to UTF-8 (SetConsoleOutputCP) so streamed model output renders correctly.
- 2026-06-10: Pal fixes. "pal use" was silently broken for case-mismatched names (lookup is NOCASE but it stored the typed name and the session join is case-sensitive) - it now stores the canonical pal name; the --pal lookup is NOCASE too. The session argument of "pal use" is now optional (defaults to the latest session, creating one if needed). "pal remove" detaches the pal from sessions, plus a startup hygiene migration clears dangling session->pal references. Replaced the "Sun Tzu" default pal with "Marketing Guru" (Marketing Strategist), including a migration that removes only the pristine Sun Tzu default row from existing databases.
- 2026-06-10: Tiered the model catalog into low-end (default) and high-end. Added a TModelTier field + MinRamGB to TCatalogItem; `model catalog` shows low-end only with a footer hint, `model catalog --all` (or `high`) reveals the high-end section with a RAM column. Added four verified single-file Q4 GGUF high-end models (keys gemma26b, qwen27b, gemma31b, qwen35b) pulled from a mid-2026 HN local-LLM thread; repos and exact filenames confirmed on Hugging Face before adding. Server-class 100B+ models were intentionally excluded (sharded multi-part GGUFs the single-file downloader can't assemble). Also added LFM2.5 1.2B and Qwen 2.5 Coder 7B (low-end) and Qwen 3 Coder 30B-A3B (high-end), repos/filenames likewise verified on Hugging Face.
- 2026-06-10: Added a server-class catalog tier (mtServer) plus sharded-download support. TModelManager.DownloadModel now detects multi-part GGUF filenames (-NNNNN-of-MMMMM.gguf), downloads all parts (keeping the HF quant subdirectory in the URL, storing shards flat in models/), and registers the first shard for llama.cpp to auto-assemble; single-file downloads are unchanged via the shared DownloadOneFile helper. `model catalog --all` now also lists server-class models. Added GPT-OSS 120B (single 65GB file), Qwen 3.5 122B-A10B (3 shards, ~89GB) and GLM-4.7 (5 shards, ~205GB), all verified on Hugging Face. GLM-4.7 needs chat_format=chatglm3 since the engine's name-based guess falls back to chatml.
