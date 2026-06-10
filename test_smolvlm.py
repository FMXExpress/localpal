import urllib.request, json
repos = [
    'ggml-org/SmolVLM2-500M-Video-Instruct-GGUF',
    'second-state/SmolVLM2-500M-Video-Instruct-GGUF'
]
for repo in repos:
    try:
        url = f'https://huggingface.co/api/models/{repo}'
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            siblings = data.get('siblings', [])
            print(f'=== {repo} ===')
            for f in siblings:
                if f['rfilename'].endswith('.gguf'):
                    print('  ', f['rfilename'])
    except Exception as e:
        print(f'=== {repo} (Error: {e}) ===')
