print("Starting search...")
import urllib.request, json
url = 'https://huggingface.co/api/models?search=SmolVLM2-500M'
try:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as r:
        raw = r.read().decode()
        print('Length of response:', len(raw))
        data = json.loads(raw)
        print('Number of models found:', len(data))
        for item in data[:15]:
            print(item.get('id'), 'likes:', item.get('likes'), 'downloads:', item.get('downloads'))
except Exception as e:
    print('Error:', e)
