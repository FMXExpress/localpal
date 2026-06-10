with open(r'C:\GitHub\SweetConsole\localpal\src\llama_cpp\Common\Chat\LlamaCpp.Common.Chat.Types.pas', 'r', encoding='utf-8') as f:
    lines = f.readlines()
    for idx, line in enumerate(lines):
        if 'TChatCompletionRequestMessage = ' in line or 'TChatCompletionRequestMessage = record' in line:
            for j in range(idx, idx + 40):
                print(f'{j+1}: {lines[j]}', end='')
            break
