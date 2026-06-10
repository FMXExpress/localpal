unit localpal.Chat;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.Stan.Param,
  localpal.Database,
  localpal.Config,
  localpal.Model;

type
  TChatManager = class
  private
    FDb: TDatabase;
    FConfig: TConfig;
    FModelMgr: TModelManager;
    function CallLocalRunner(const APrompt: string; const AHistory: TJSONArray; const AModelName: string): string;
    function GetOfflineResponse(const APrompt: string): string;
  public
    constructor Create(ADb: TDatabase; AConfig: TConfig; AModelMgr: TModelManager);
    procedure ListSessions;
    function CreateSession(const AName: string): Integer;
    procedure ShowSession(ASessionId: Integer);
    procedure DeleteSession(ASessionId: Integer);
    procedure SendMessage(ASessionId: Integer; const AContent: string);
    procedure InteractiveChat(ASessionId: Integer);
  end;

implementation

constructor TChatManager.Create(ADb: TDatabase; AConfig: TConfig; AModelMgr: TModelManager);
begin
  inherited Create;
  FDb := ADb;
  FConfig := AConfig;
  FModelMgr := AModelMgr;
end;

procedure TChatManager.ListSessions;
var
  LQuery: TFDQuery;
  LCount: Integer;
begin
  LQuery := FDb.Query('SELECT id, name, pal_name, created_at FROM sessions ORDER BY id DESC');
  try
    LQuery.Open;
    Writeln('================================================================================');
    Writeln('                                 CHAT SESSIONS                                  ');
    Writeln('================================================================================');
    Writeln(Format('  %-10s | %-30s | %-15s | %s', ['ID', 'Session Name', 'Active Pal', 'Created At']));
    Writeln('--------------------------------------------------------------------------------');
    LCount := 0;
    while not LQuery.Eof do
    begin
      Inc(LCount);
      var LPalName := LQuery.FieldByName('pal_name').AsString;
      if LPalName.IsEmpty then
        LPalName := '(None)';

      Writeln(Format('  %-10d | %-30s | %-15s | %s', [
        LQuery.FieldByName('id').AsInteger,
        LQuery.FieldByName('name').AsString,
        LPalName,
        LQuery.FieldByName('created_at').AsString
      ]));
      LQuery.Next;
    end;
    if LCount = 0 then
      Writeln('  No chat sessions found. Start one using: localpal chat new "<name>"');
    Writeln('================================================================================');
  finally
    LQuery.Free;
  end;
end;

function TChatManager.CreateSession(const AName: string): Integer;
var
  LQuery: TFDQuery;
begin
  LQuery := FDb.Query('INSERT INTO sessions (name) VALUES (:name)');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.ExecSQL;
    
    // Get last insert ID
    Result := FDb.Conn.GetLastAutoGenValue('');
    Writeln(Format('Created new chat session "%s" (ID: %d)!', [AName, Result]));
  finally
    LQuery.Free;
  end;
end;

procedure TChatManager.ShowSession(ASessionId: Integer);
var
  LQuery: TFDQuery;
  LRole: string;
  LContent: string;
begin
  LQuery := FDb.Query('SELECT role, content, created_at FROM messages WHERE session_id = :session_id ORDER BY id ASC');
  try
    LQuery.ParamByName('session_id').AsInteger := ASessionId;
    LQuery.Open;
    
    Writeln(Format('========================= CHAT SESSION ID: %d =========================', [ASessionId]));
    if LQuery.IsEmpty then
      Writeln('  (No messages in this chat yet. Type a message or start interactive mode!)');
      
    while not LQuery.Eof do
    begin
      LRole := LQuery.FieldByName('role').AsString.ToUpper;
      LContent := LQuery.FieldByName('content').AsString;
      
      Writeln(Format('[%s]', [LRole]));
      Writeln(LContent);
      Writeln('--------------------------------------------------------------------------------');
      LQuery.Next;
    end;
    Writeln('================================================================================');
  finally
    LQuery.Free;
  end;
end;

procedure TChatManager.DeleteSession(ASessionId: Integer);
var
  LQuery: TFDQuery;
begin
  LQuery := FDb.Query('DELETE FROM sessions WHERE id = :id');
  try
    LQuery.ParamByName('id').AsInteger := ASessionId;
    LQuery.ExecSQL;
    Writeln(Format('Deleted session %d and its messages.', [ASessionId]));
  finally
    LQuery.Free;
  end;
end;

function TChatManager.CallLocalRunner(const APrompt: string; const AHistory: TJSONArray; const AModelName: string): string;
var
  LHTTP: THTTPClient;
  LResponse: IHTTPResponse;
  LPayload: TJSONObject;
  LStringWriter: TStringList;
  LUrl: string;
  LTemp: string;
  LMaxTokens: string;
begin
  LUrl := FConfig.GetVal('runner_url', 'http://localhost:11434/v1');
  if not LUrl.EndsWith('/') then
    LUrl := LUrl + '/';
  LUrl := LUrl + 'chat/completions';

  LPayload := TJSONObject.Create;
  try
    LPayload.AddPair('model', AModelName);
    LPayload.AddPair('messages', AHistory.Clone as TJSONArray);
    LPayload.AddPair('temperature', TJSONNumber.Create(StrToFloatDef(FConfig.GetVal('temperature', '0.7'), 0.7)));
    LMaxTokens := FConfig.GetVal('max_tokens', '512');
    LPayload.AddPair('max_tokens', TJSONNumber.Create(StrToIntDef(LMaxTokens, 512)));
    LPayload.AddPair('stream', TJSONBool.Create(False));

    LHTTP := THTTPClient.Create;
    try
      LHTTP.ContentType := 'application/json';
      LStringWriter := TStringList.Create;
      try
        LStringWriter.Text := LPayload.ToJSON;
        
        // Timeout configuration
        LHTTP.ConnectionTimeout := 5000;
        LHTTP.ResponseTimeout := 60000;

        // HuggingFace or custom headers (such as authorization) can be configured
        var LHFToken := FConfig.GetVal('hf_token');
        if not LHFToken.IsEmpty then
          LHTTP.CustomHeaders['Authorization'] := 'Bearer ' + LHFToken;

        LResponse := LHTTP.Post(LUrl, LStringWriter);
        if LResponse.StatusCode = 200 then
        begin
          LTemp := LResponse.ContentAsString;
          // Parse JSON response to get Choices[0].message.content
          var LResJSON := TJSONObject.ParseJSONValue(LTemp) as TJSONObject;
          if Assigned(LResJSON) then
          begin
            try
              var LChoices := LResJSON.GetValue('choices') as TJSONArray;
              if Assigned(LChoices) and (LChoices.Count > 0) then
              begin
                var LChoice := LChoices.Items[0] as TJSONObject;
                var LMsg := LChoice.GetValue('message') as TJSONObject;
                Result := LMsg.GetValue('content').Value;
              end
              else
                Result := 'Error: Empty choices returned by runner.';
            finally
              LResJSON.Free;
            end;
          end
          else
            Result := 'Error: Failed to parse runner response as JSON.';
        end
        else
        begin
          Result := Format('Error: Local runner returned HTTP %d - %s', [LResponse.StatusCode, LResponse.StatusText]);
        end;
      finally
        LStringWriter.Free;
      end;
    finally
      LHTTP.Free;
    end;
  finally
    LPayload.Free;
  end;
end;

function TChatManager.GetOfflineResponse(const APrompt: string): string;
var
  LQueryLower: string;
begin
  LQueryLower := APrompt.ToLower;
  
  if LQueryLower.Contains('pascal') or LQueryLower.Contains('delphi') then
  begin
    Result := 'Ah, Object Pascal! A truly magnificent and lightning-fast compiled language. ' + sLineBreak +
              'Here is a quick tip: Always remember that in Delphi, you can statically link SQLite ' + sLineBreak +
              'by using the FireDAC SQLite driver. For example:' + sLineBreak + sLineBreak +
              '```pascal' + sLineBreak +
              'uses FireDAC.Phys.SQLite;' + sLineBreak +
              '// This links the engine statically on Windows so no external sqlite3.dll is required!' + sLineBreak +
              '```' + sLineBreak +
              'What else would you like to build in Object Pascal?';
  end
  else if LQueryLower.Contains('hello') or LQueryLower.Contains('hi') or LQueryLower.Contains('hey') then
  begin
    Result := 'Hello there! I am your LocalPal Offline AI fallback. ' + sLineBreak +
              'I run entirely offline without needing an active GGUF or LLM server. ' + sLineBreak +
              'To start chatting with a real 7B/8B model, register a model file, download GGUF from ' + sLineBreak +
              'Hugging Face using "localpal model download", and fire up Ollama or llama.cpp!';
  end
  else if LQueryLower.Contains('who are you') or LQueryLower.Contains('your name') then
  begin
    Result := 'I am LocalPal''s built-in offline core helper! ' + sLineBreak +
              'Since your Ollama or llama.cpp runner is currently unreachable, I am standing in to help. ' + sLineBreak +
              'To connect a real local LLM, make sure you configure "runner_url" using: ' + sLineBreak +
              '  localpal config set runner_url <url>';
  end
  else if LQueryLower.Contains('joke') then
  begin
    Result := 'Why do programmers prefer dark mode?' + sLineBreak +
              'Because light attracts bugs!';
  end
  else if LQueryLower.Contains('localpal') then
  begin
    Result :=  'LocalPal is a fantastic mobile offline LLM companion.' + sLineBreak +
              'Offline-first and open-source models are the future!';
  end
  else if LQueryLower.Contains('help') then
  begin
    Result := 'LocalPal CLI quick reference:' + sLineBreak +
              '  - model list              : show registered models' + sLineBreak +
              '  - model search <query>    : search GGUF models on Hugging Face' + sLineBreak +
              '  - model download <r> <f>  : download model file from Hugging Face' + sLineBreak +
              '  - chat interactive <id>   : enter interactive loop for session' + sLineBreak +
              '  - config set runner_url <u: configure endpoint (e.g., http://localhost:11434)';
  end
  else
  begin
    Result := 'That is a very interesting thought!' + sLineBreak + sLineBreak +
              '--------------------------------------------------------------------------------' + sLineBreak +
              ' [LocalPal Offline Mode Info]' + sLineBreak +
              ' Ollama or llama.cpp is not responding on your configured "runner_url".' + sLineBreak +
              ' To chat with a real AI, please:' + sLineBreak +
              '   1. Install and start Ollama (https://ollama.com)' + sLineBreak +
              '   2. Pull a model (e.g. "ollama pull llama3.2:1b")' + sLineBreak +
              '   3. Activate the model here: "localpal model use llama3.2:1b"' + sLineBreak +
              '   4. Restart interactive mode!';
  end;
end;

procedure TChatManager.SendMessage(ASessionId: Integer; const AContent: string);
var
  LActiveModel: TModelInfo;
  LModelName: string;
  LQuery: TFDQuery;
  LHistory: TJSONArray;
  LSystemPrompt: string;
  LResponse: string;
  LHasRealModel: Boolean;
  LPalName: string;
  LPalRole: string;
  LPalPrompt: string;
  LPalModel: string;
  LHasPal: Boolean;
begin
  // Save user message to database
  LQuery := FDb.Query('INSERT INTO messages (session_id, role, content) VALUES (:session_id, ''user'', :content)');
  try
    LQuery.ParamByName('session_id').AsInteger := ASessionId;
    LQuery.ParamByName('content').AsString := AContent;
    LQuery.ExecSQL;
  finally
    LQuery.Free;
  end;

  // Check if session has a Pal
  LHasPal := False;
  LPalName := '';
  LPalRole := '';
  LPalPrompt := '';
  LPalModel := '';

  LQuery := FDb.Query(
    'SELECT s.pal_name, p.role, p.system_prompt, p.model ' +
    'FROM sessions s ' +
    'LEFT JOIN pals p ON s.pal_name = p.name ' +
    'WHERE s.id = :session_id'
  );
  try
    LQuery.ParamByName('session_id').AsInteger := ASessionId;
    LQuery.Open;
    if not LQuery.IsEmpty and not LQuery.FieldByName('pal_name').IsNull then
    begin
      LPalName := LQuery.FieldByName('pal_name').AsString;
      if not LPalName.IsEmpty then
      begin
        LPalRole := LQuery.FieldByName('role').AsString;
        LPalPrompt := LQuery.FieldByName('system_prompt').AsString;
        LPalModel := LQuery.FieldByName('model').AsString;
        LHasPal := True;
      end;
    end;
  finally
    LQuery.Free;
  end;

  // Set system prompt
  if LHasPal and not LPalPrompt.IsEmpty then
    LSystemPrompt := LPalPrompt
  else
    LSystemPrompt := FConfig.GetVal('system_prompt', 'You are a helpful local AI assistant.');

  // Retrieve active model or Pal-specific model
  if LHasPal and not LPalModel.IsEmpty then
  begin
    LModelName := LPalModel;
  end
  else
  begin
    LHasRealModel := FModelMgr.GetActiveModel(LActiveModel);
    if LHasRealModel then
      LModelName := LActiveModel.Name
    else
      LModelName := 'localpal-offline';
  end;

  // Build message history
  LHistory := TJSONArray.Create;
  try
    // Add system message
    var LSysObj := TJSONObject.Create;
    LSysObj.AddPair('role', 'system');
    LSysObj.AddPair('content', LSystemPrompt);
    LHistory.AddElement(LSysObj);

    // Retrieve previous messages
    LQuery := FDb.Query('SELECT role, content FROM messages WHERE session_id = :session_id ORDER BY id ASC');
    try
      LQuery.ParamByName('session_id').AsInteger := ASessionId;
      LQuery.Open;
      while not LQuery.Eof do
      begin
        var LMsgObj := TJSONObject.Create;
        LMsgObj.AddPair('role', LQuery.FieldByName('role').AsString);
        LMsgObj.AddPair('content', LQuery.FieldByName('content').AsString);
        LHistory.AddElement(LMsgObj);
        LQuery.Next;
      end;
    finally
      LQuery.Free;
    end;

    // Contact local runner or fallback
    try
      Writeln('Thinking...');
      LResponse := CallLocalRunner(AContent, LHistory, LModelName);
    except
      on E: Exception do
      begin
        Writeln('[Local runner offline or timed out. Falling back to offline core...]');
        LResponse := GetOfflineResponse(AContent);
      end;
    end;
  finally
    LHistory.Free;
  end;

  // Print response
  if LHasPal then
    Writeln(Format('[%s (%s)]', [LPalName.ToUpper, LPalRole.ToUpper]))
  else
    Writeln('[ASSISTANT]');
    
  Writeln(LResponse);
  Writeln;

  // Save assistant message to database
  LQuery := FDb.Query('INSERT INTO messages (session_id, role, content) VALUES (:session_id, ''assistant'', :content)');
  try
    LQuery.ParamByName('session_id').AsInteger := ASessionId;
    LQuery.ParamByName('content').AsString := LResponse;
    LQuery.ExecSQL;
  finally
    LQuery.Free;
  end;
end;

procedure TChatManager.InteractiveChat(ASessionId: Integer);
var
  LInput: string;
  LActiveModel: TModelInfo;
  LQuery: TFDQuery;
  LPalName: string;
  LPalRole: string;
  LHasPal: Boolean;
begin
  LHasPal := False;
  LPalName := '';
  LPalRole := '';

  LQuery := FDb.Query('SELECT s.pal_name, p.role FROM sessions s LEFT JOIN pals p ON s.pal_name = p.name WHERE s.id = :session_id');
  try
    LQuery.ParamByName('session_id').AsInteger := ASessionId;
    LQuery.Open;
    if not LQuery.IsEmpty and not LQuery.FieldByName('pal_name').IsNull then
    begin
      LPalName := LQuery.FieldByName('pal_name').AsString;
      LPalRole := LQuery.FieldByName('role').AsString;
      LHasPal := not LPalName.IsEmpty;
    end;
  finally
    LQuery.Free;
  end;

  Writeln('================================================================================');
  Writeln(Format('             Entering Interactive Chat Session (ID: %d)', [ASessionId]));
  
  if LHasPal then
    Writeln(Format('             Hosted by Pal: %s (%s)', [LPalName, LPalRole]))
  else
    Writeln('             Hosted by: (No Pal Selected - Default Assistant)');

  if FModelMgr.GetActiveModel(LActiveModel) then
    Writeln('             Active Model: ' + LActiveModel.Name)
  else
    Writeln('             Active Model: NONE (Fallback Offline Helper)');
  Writeln('             Type /exit or /quit to exit.');
  Writeln('================================================================================');
  Writeln;

  while True do
  begin
    Write('[USER]> ');
    Readln(LInput);
    LInput := LInput.Trim;
    
    if LInput.IsEmpty then
      Continue;
      
    if (LInput = '/exit') or (LInput = '/quit') then
    begin
      Writeln('Exiting interactive mode.');
      Break;
    end;

    SendMessage(ASessionId, LInput);
  end;
end;

end.