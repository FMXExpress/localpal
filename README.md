# localpal

**Your offline-first LLM companion, written in Delphi.**

localpal is a Windows command-line app that chats with GGUF language models **in-process** — no server, no cloud, no Python. Point it at a model file (or download one from the built-in catalog) and talk to it, with streaming token output, persistent chat sessions, custom personas ("Pals"), and a hardware benchmark. An Ollama/llama.cpp-server fallback is built in for models you already run elsewhere.

```
localpal model download smollm
localpal chat "Why is the sky blue?"
localpal chat
```

## Features

- **In-process inference** — GGUF models load directly via [llama-cpp-delphi](https://github.com/Embarcadero/llama-cpp-delphi) bindings (vendored in `src/llama_cpp`). Responses stream token-by-token to the console.
- **Model catalog & downloads** — one-command download of curated small models (Qwen 2.5, Llama 3.2, Gemma 2, Phi 3.5, SmolLM2, ...) from Hugging Face, with progress display and automatic activation. Or search Hugging Face and register any GGUF.
- **Chat sessions** — conversations persist in SQLite (FireDAC). `localpal chat` resumes where you left off; sessions can be named, listed, shown, and deleted.
- **Pals** — reusable personas (name, role, system prompt, optional preferred model) you can assign to sessions, export, and import as JSON. Ships with Shakespeare, Marketing Guru, and Code Buddy.
- **Benchmarking** — measures real prompt-processing and token-generation speeds (time-to-first-token split) and prints a hardware score.
- **Runner fallback** — models that aren't local GGUF files (e.g. Ollama tags) are sent to an OpenAI-compatible local runner at `runner_url`.

## Requirements

- Windows x64 (the build targets Win64).
- Delphi (tested with recent versions; FireDAC with the SQLite driver is part of standard editions).
- **The llama.cpp native libraries from [llama-cpp-delphi](https://github.com/Embarcadero/llama-cpp-delphi)** — see below.

### Getting the llama.cpp DLLs

localpal does not bundle a complete native library set. Download a Windows bundle from the
[llama-cpp-delphi releases](https://github.com/Embarcadero/llama-cpp-delphi/releases) and place the DLLs
(`llama.dll`, `ggml.dll`, `ggml-base.dll`, `ggml-cpu.dll`, and optionally `llava_shared.dll` for multimodal models)
in one of the locations localpal searches, in this order:

1. the folder set in the `lib_dir` config key (`localpal config set lib_dir C:\path\to\dlls`),
2. a `llamacpp` subfolder next to `localpal.exe`,
3. next to `localpal.exe`,
4. the current working directory (and its `llamacpp` subfolder).

Pick the right bundle for your hardware:

| Bundle | When to use it |
|---|---|
| AVX2 | Most modern CPUs (Intel Haswell+ / AMD Zen+). Recommended default. |
| AVX | Older CPUs without AVX2. |
| AVX512 | Recent CPUs with AVX-512 support. |
| CUDA 11.7 / 12.4 | NVIDIA GPUs (also grab the matching CUDA runtime asset). Set `n_gpu_layers` > 0 to offload. |

GPU notes: the released GPU bundles are NVIDIA CUDA only. AMD/Intel GPU users can run a Vulkan build of
[llama.cpp server](https://github.com/ggml-org/llama.cpp) separately and point localpal at it via the runner engine.

## Building

```bat
dcc64 -B localpal.dpr
```

or with MSBuild / the Delphi IDE:

```bat
msbuild localpal.dproj /p:Platform=Win64
```

Must be built for **Win64** (the DLLs are x64). Unit search paths and the required unit scope
names (`System;Winapi;...` — the vendored library uses short RTL unit names) are already configured
in `localpal.cfg` for command-line builds and in `localpal.dproj` for the IDE/MSBuild.

## Usage

### Chat

```
localpal chat                       Resume the latest session (or start one) interactively.
localpal chat "<message>"           One-shot question in the latest session.
localpal chat new <name>            Create a named session and enter interactive mode.
localpal chat list                  List sessions.
localpal chat show <id|name>        Print a session's messages.
localpal chat send <id|name> "<m>"  Send one message to a specific session.
localpal chat delete <id|name>      Delete a session.
```

`--model <name|catalog-key>` and `--pal <name>` override the model/persona for a single invocation.

### Models

```
localpal model catalog              Show the built-in model catalog.
localpal model download <id|key>    Download a catalog model (becomes the active model).
localpal model download <repo> <f>  Download any GGUF from a Hugging Face repo.
localpal model search <query>       Search GGUF repos on Hugging Face.
localpal model list                 List registered models.
localpal model use <name>           Set the active model.
localpal model add <name> <path>    Register an existing GGUF path or an Ollama tag.
localpal model remove <name>        Remove a model from the registry.
```

### Pals (personas)

```
localpal pal list                   List Pals.
localpal pal use <name> [session]   Assign a Pal (defaults to the latest session).
localpal pal add <n> <role> <prompt> [model]
localpal pal export <name> <file>   Export a Pal to JSON.
localpal pal import <file>          Import a Pal from JSON.
localpal pal remove <name>
```

### Benchmark

```
localpal benchmark [model]
```

Loads the model (timed), generates 128 tokens, and reports prompt-processing and token-generation
speeds plus an overall score.

## Configuration

`localpal config show` lists everything; `localpal config set <key> <value>` changes a value.

| Key | Default | Meaning |
|---|---|---|
| `engine` | `auto` | `builtin` (in-process llama.cpp), `runner` (HTTP), or `auto`: builtin when the active model is a local `.gguf` and the DLLs are found, otherwise runner. |
| `chat_format` | *(empty)* | Prompt template (`chatml`, `llama-3`, `qwen`, `gemma`, `mistral-instruct`, `zephyr`, ...). Empty = guessed from the model file name, falling back to `chatml`. |
| `n_ctx` | `4096` | Context window size. |
| `n_gpu_layers` | `0` | Layers to offload to GPU (needs a CUDA DLL bundle; 0 = CPU). |
| `lib_dir` | *(empty)* | Explicit folder containing the llama.cpp DLLs. |
| `engine_log` | `off` | `on` shows llama.cpp's native model-load logs. |
| `system_prompt` | helpful assistant | Default system prompt when no Pal is assigned. |
| `temperature` | `0.7` | Sampling temperature. |
| `max_tokens` | `512` | Response length limit. |
| `runner_url` | `http://localhost:11434/v1` | OpenAI-compatible endpoint for the runner engine (Ollama default). |
| `hf_token` | *(empty)* | Hugging Face token for gated model downloads. |

## Using Ollama (or any OpenAI-compatible server) instead

```
localpal model add llama3.2 llama3.2:1b
localpal model use llama3.2
localpal chat
```

Anything that isn't a local `.gguf` path is sent to `runner_url`. To force one engine or the
other, set `engine` to `builtin` or `runner`. If no model and no runner are available, localpal
falls back to a small built-in offline helper.

## License

[MIT](LICENSE)
