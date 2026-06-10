import urllib.request, json
repos = [
    'bartowski/Gemmasutra-Mini-2B-v1-GGUF',
    'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
    'bartowski/Qwen2.5-3B-Instruct-GGUF',
    'google/gemma-2-2b-it-GGUF',
    'bartowski/Phi-3.5-mini-instruct-GGUF',
    'unsloth/Llama-3.2-1B-Instruct-GGUF',
    'unsloth/Llama-3.2-3B-Instruct-GGUF',
    'bartowski/SmolLM2-1.7B-Instruct-GGUF',
    'HuggingFaceTB/SmolVLM2-500M-Instruct-GGUF'
]
for repo in repos:
    try:
        url = f'https://huggingface.co/api/models/{repo}'
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            siblings = data.get('siblings', [])
            if siblings:
                print(f'=== {repo} ===')
                ggufs = [f['rfilename'] for f in siblings if 'rfilename' in f and f['rfilename'].endswith('.gguf')]
                for g in sorted(ggufs):
                    if 'Q4_K_M' in g or 'Q8_0' in g or 'Q5_K_M' in g or len(ggufs) < 5 or '2b_it' in g:
                        print('  ', g)
    except Exception as e:
        print(f'=== {repo} (Error: {e}) ===')
