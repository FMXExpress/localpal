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
  localpal.Model,
  localpal.Engine;

type
  TChatEngineKind = (ekBuiltin, ekRunner, ekOffline);

  TChatManager = class
  private
    FDb: TDatabase;
    FConfig: TConfig;
    FModelMgr: TModelManager;
    FEngine: TLlamaEngine;
    FModelOverride: string;
    FPalOverride: string;
    FLastEngineNote: string;
    function CallLocalRunner(const AHistory: TArray<TEngineMessage>; const AModelName: string): string;
    function GetOfflineResponse(const APrompt: string): string;
    function GetPalByName(const AName: string; out ARole, APrompt, AModel: string): Boolean;
    function GetSessionPal(ASessionId: Integer; out AName, ARole, APrompt, AModel: string): Boolean;
    procedure ResolveChatModel(const APalModel: string; out AModelName, AModelPath: string);
    function SelectEngine(const AModelName, AModelPath: string): TChatEngineKind;
    function BuildHistory(ASessionId: Integer; const ASystemPrompt: string): TArray<TEngineMessage>;
    function GetMostRecentSession: Integer;
  public
    constructor Create(ADb: TDatabase; AConfig: TConfig; AModelMgr: TModelManager);
    destructor Destroy; override;
    procedure ListSessions;
    function CreateSession(const AName: string): Integer;
    function ResolveSession(const AIdOrName: string): Integer;
    procedure ShowSession(ASessionId: Integer);
    procedure DeleteSession(ASessionId: Integer);
    procedure SendMessage(ASessionId: Integer; const AContent: string);
    procedure InteractiveChat(ASessionId: Integer);
    // Most recent session, or a fresh "default" one when none exists yet.
    function EnsureSession: Integer;
    procedure QuickChat;
    procedure QuickAsk(const AContent: string);

    property ModelOverride: string read FModelOverride write FModelOverride;
    property PalOverride: string read FPalOverride write FPalOverride;
  end;

implementation

constructor TChatManager.Create(ADb: TDatabase; AConfig: TConfig; AModelMgr: TModelManager);
begin
  inherited Create;
  FDb := ADb;
  FConfig := AConfig;
  FModelMgr := AModelMgr;
  FEngine := TLlamaEngine.Create(AConfig);
  FModelOverride := '';
  FPalOverride := '';
end;

destructor TChatManager.Destroy;
begin
  FEngine.Free;
  inherited Destroy;
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
      Writeln('  No chat sessions found. Just run "localpal chat" to start one!');
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

function TChatManager.ResolveSession(const AIdOrName: string): Integer;
var
  LQuery: TFDQuery;
  LId: Integer;
begin
  Result := -1;

  // Numeric input is treated as a session ID first.
  if TryStrToInt(AIdOrName, LId) then
  begin
    LQuery := FDb.Query('SELECT id FROM sessions WHERE id = :id');
    try
      LQuery.ParamByName('id').AsInteger := LId;
      LQuery.Open;
      if not LQuery.IsEmpty then
        Exit(LId);
    finally
      LQuery.Free;
    end;
  end;

  LQuery := FDb.Query('SELECT id FROM sessions WHERE name = :name');
  try
    LQuery.ParamByName('name').AsString := AIdOrName;
    LQuery.Open;
    if not LQuery.IsEmpty then
      Exit(LQuery.FieldByName('id').AsInteger);
  finally
    LQuery.Free;
  end;

  Writeln(Format('Error: No chat session with ID or name "%s". Run "localpal chat list" to see sessions.', [AIdOrName]));
end;

function TChatManager.GetMostRecentSession: Integer;
var
  LQuery: TFDQuery;
begin
  Result := 0;
  LQuery := FDb.Query('SELECT id FROM sessions ORDER BY id DESC LIMIT 1');
  try
    LQuery.Open;
    if not LQuery.IsEmpty then
      Result := LQuery.FieldByName('id').AsInteger;
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

function TChatManager.CallLocalRunner(const AHistory: TArray<TEngineMessage>;
  const AModelName: string): string;
var
  LHTTP: THTTPClient;
  LResponse: IHTTPResponse;
  LPayload: TJSONObject;
  LMessages: TJSONArray;
  LStringWriter: TStringList;
  LUrl: string;
  LTemp: string;
  LMaxTokens: string;
begin
  LUrl := FConfig.GetVal('runner_url', 'http://localhost:11434/v1');
  if not LUrl.EndsWith('/') then
    LUrl := LUrl + '/';
  LUrl := LUrl + 'chat/completions';

  LMessages := TJSONArray.Create;
  for var LMsg in AHistory do
  begin
    var LMsgObj := TJSONObject.Create;
    LMsgObj.AddPair('role', LMsg.Role);
    LMsgObj.AddPair('content', LMsg.Content);
    LMessages.AddElement(LMsgObj);
  end;

  LPayload := TJSONObject.Create;
  try
    LPayload.AddPair('model', AModelName);
    LPayload.AddPair('messages', LMessages); // payload owns the array now
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
              'I run entirely offline without needing a model loaded. ' + sLineBreak +
              'To chat with a real local model, download one from the built-in catalog: ' + sLineBreak +
              '  localpal model download smollm' + sLineBreak +
              'and then simply run "localpal chat" again!';
  end
  else if LQueryLower.Contains('who are you') or LQueryLower.Contains('your name') then
  begin
    Result := 'I am LocalPal''s built-in offline core helper! ' + sLineBreak +
              'No local model is loaded right now, so I am standing in to help. ' + sLineBreak +
              'Download a model with "localpal model download <key>" (see "localpal model catalog"), ' + sLineBreak +
              'or configure an external runner with: ' + sLineBreak +
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
              '  - chat                     : jump straight into an interactive chat' + sLineBreak +
              '  - chat "<message>"         : ask a single question' + sLineBreak +
              '  - model catalog            : show built-in models available for download' + sLineBreak +
              '  - model download <key>     : download a model and make it active' + sLineBreak +
              '  - model search <query>     : search GGUF models on Hugging Face';
  end
  else
  begin
    Result := 'That is a very interesting thought!' + sLineBreak + sLineBreak +
              '--------------------------------------------------------------------------------' + sLineBreak +
              ' [LocalPal Offline Mode Info]' + sLineBreak +
              ' No local model is available yet. To chat with a real AI, please:' + sLineBreak +
              '   1. Run "localpal model catalog" to see the built-in model catalog' + sLineBreak +
              '   2. Download one, e.g. "localpal model download smollm"' + sLineBreak +
              '   3. Run "localpal chat" - the model loads in-process via llama.cpp!' + sLineBreak +
              ' (Alternatively, start Ollama and run "localpal model add <name> <tag>".)';
  end;
end;

function TChatManager.GetPalByName(const AName: string;
  out ARole, APrompt, AModel: string): Boolean;
var
  LQuery: TFDQuery;
begin
  Result := False;
  ARole := '';
  APrompt := '';
  AModel := '';

  LQuery := FDb.Query('SELECT role, system_prompt, model FROM pals WHERE name = :name COLLATE NOCASE LIMIT 1');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.Open;
    if not LQuery.IsEmpty then
    begin
      ARole := LQuery.FieldByName('role').AsString;
      APrompt := LQuery.FieldByName('system_prompt').AsString;
      AModel := LQuery.FieldByName('model').AsString;
      Result := True;
    end;
  finally
    LQuery.Free;
  end;
end;

function TChatManager.GetSessionPal(ASessionId: Integer;
  out AName, ARole, APrompt, AModel: string): Boolean;
var
  LQuery: TFDQuery;
begin
  Result := False;
  AName := '';
  ARole := '';
  APrompt := '';
  AModel := '';

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
      AName := LQuery.FieldByName('pal_name').AsString;
      if not AName.IsEmpty then
      begin
        ARole := LQuery.FieldByName('role').AsString;
        APrompt := LQuery.FieldByName('system_prompt').AsString;
        AModel := LQuery.FieldByName('model').AsString;
        Result := True;
      end;
    end;
  finally
    LQuery.Free;
  end;
end;

procedure TChatManager.ResolveChatModel(const APalModel: string;
  out AModelName, AModelPath: string);
var
  LSelector: string;
  LInfo: TModelInfo;
begin
  AModelName := '';
  AModelPath := '';

  // Priority: --model flag > Pal's preferred model > active model.
  LSelector := FModelOverride;
  if LSelector.IsEmpty then
    LSelector := APalModel;

  if not LSelector.IsEmpty then
  begin
    if FModelMgr.ResolveModel(LSelector, LInfo) then
    begin
      AModelName := LInfo.Name;
      AModelPath := LInfo.Path;
    end
    else
      AModelName := LSelector; // raw runner tag (e.g. an Ollama model)
    Exit;
  end;

  if FModelMgr.EnsureActiveModel(LInfo) then
  begin
    AModelName := LInfo.Name;
    AModelPath := LInfo.Path;
  end;
end;

function TChatManager.SelectEngine(const AModelName, AModelPath: string): TChatEngineKind;
var
  LMode: string;
begin
  FLastEngineNote := '';

  if AModelName.IsEmpty then
    Exit(ekOffline);

  LMode := FConfig.GetVal('engine', 'auto');

  if SameText(LMode, 'builtin') then
    Exit(ekBuiltin);

  if SameText(LMode, 'runner') then
    Exit(ekRunner);

  // auto: chat in-process when the model is a local GGUF file and the
  // llama.cpp libraries are present; otherwise defer to the runner and
  // remember why so callers can explain the fallback.
  FLastEngineNote := FEngine.BuiltinUnavailableReason(AModelPath);
  if FLastEngineNote.IsEmpty then
    Result := ekBuiltin
  else
    Result := ekRunner;
end;

function TChatManager.BuildHistory(ASessionId: Integer;
  const ASystemPrompt: string): TArray<TEngineMessage>;
var
  LQuery: TFDQuery;
begin
  Result := [TEngineMessage.Make('system', ASystemPrompt)];

  LQuery := FDb.Query('SELECT role, content FROM messages WHERE session_id = :session_id ORDER BY id ASC');
  try
    LQuery.ParamByName('session_id').AsInteger := ASessionId;
    LQuery.Open;
    while not LQuery.Eof do
    begin
      Result := Result + [TEngineMessage.Make(
        LQuery.FieldByName('role').AsString,
        LQuery.FieldByName('content').AsString)];
      LQuery.Next;
    end;
  finally
    LQuery.Free;
  end;
end;

procedure TChatManager.SendMessage(ASessionId: Integer; const AContent: string);
var
  LQuery: TFDQuery;
  LHistory: TArray<TEngineMessage>;
  LSystemPrompt: string;
  LResponse: string;
  LPalName: string;
  LPalRole: string;
  LPalPrompt: string;
  LPalModel: string;
  LHasPal: Boolean;
  LModelName: string;
  LModelPath: string;
  LHeader: string;
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

  // Pal selection: --pal flag wins over the session-assigned Pal
  LHasPal := False;
  LPalName := '';
  LPalRole := '';
  LPalPrompt := '';
  LPalModel := '';

  if not FPalOverride.IsEmpty then
  begin
    LHasPal := GetPalByName(FPalOverride, LPalRole, LPalPrompt, LPalModel);
    if LHasPal then
      LPalName := FPalOverride
    else
      Writeln(Format('[Warning: Pal "%s" not found; using the default assistant.]', [FPalOverride]));
  end;
  if not LHasPal then
    LHasPal := GetSessionPal(ASessionId, LPalName, LPalRole, LPalPrompt, LPalModel);

  // Set system prompt
  if LHasPal and not LPalPrompt.IsEmpty then
    LSystemPrompt := LPalPrompt
  else
    LSystemPrompt := FConfig.GetVal('system_prompt', 'You are a helpful local AI assistant.');

  if not LHasPal then
    LPalModel := '';

  ResolveChatModel(LPalModel, LModelName, LModelPath);

  // Build message history (includes the user message saved above)
  LHistory := BuildHistory(ASessionId, LSystemPrompt);

  if LHasPal then
    LHeader := Format('[%s (%s)]', [LPalName.ToUpper, LPalRole.ToUpper])
  else
    LHeader := '[ASSISTANT]';

  case SelectEngine(LModelName, LModelPath) of
    ekBuiltin:
      begin
        try
          FEngine.EnsureModelLoaded(LModelPath);
          Writeln(LHeader);
          LResponse := FEngine.Chat(LHistory,
            procedure(const AToken: string)
            begin
              Write(AToken);
            end);
          Writeln;
        except
          on E: Exception do
          begin
            Writeln(Format('[Built-in llama.cpp engine failed: %s]', [E.Message]));
            Writeln('[Falling back to offline core...]');
            LResponse := GetOfflineResponse(AContent);
            Writeln(LHeader);
            Writeln(LResponse);
          end;
        end;
      end;

    ekRunner:
      begin
        try
          Writeln('Thinking...');
          LResponse := CallLocalRunner(LHistory, LModelName);
        except
          on E: Exception do
          begin
            Writeln('[Local runner offline or timed out. Falling back to offline core...]');
            if not FLastEngineNote.IsEmpty then
              Writeln('[Built-in engine was skipped: ' + FLastEngineNote + ']');
            LResponse := GetOfflineResponse(AContent);
          end;
        end;
        Writeln(LHeader);
        Writeln(LResponse);
      end;

  else // ekOffline
    begin
      LResponse := GetOfflineResponse(AContent);
      Writeln(LHeader);
      Writeln(LResponse);
    end;
  end;

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
  LPalName: string;
  LPalRole: string;
  LPalPrompt: string;
  LPalModel: string;
  LHasPal: Boolean;
  LModelName: string;
  LModelPath: string;
  LEngineKind: TChatEngineKind;
begin
  LHasPal := False;
  LPalName := '';

  if not FPalOverride.IsEmpty then
  begin
    LHasPal := GetPalByName(FPalOverride, LPalRole, LPalPrompt, LPalModel);
    if LHasPal then
      LPalName := FPalOverride;
  end;
  if not LHasPal then
    LHasPal := GetSessionPal(ASessionId, LPalName, LPalRole, LPalPrompt, LPalModel);

  if not LHasPal then
    LPalModel := '';

  ResolveChatModel(LPalModel, LModelName, LModelPath);
  LEngineKind := SelectEngine(LModelName, LModelPath);

  Writeln('================================================================================');
  Writeln(Format('             Entering Interactive Chat Session (ID: %d)', [ASessionId]));

  if LHasPal then
    Writeln(Format('             Hosted by Pal: %s (%s)', [LPalName, LPalRole]))
  else
    Writeln('             Hosted by: (No Pal Selected - Default Assistant)');

  case LEngineKind of
    ekBuiltin:
      begin
        Writeln('             Active Model: ' + LModelName);
        Writeln('             Engine: built-in llama.cpp (in-process)');
      end;
    ekRunner:
      begin
        Writeln('             Active Model: ' + LModelName);
        Writeln('             Engine: local runner @ ' + FConfig.GetVal('runner_url', 'http://localhost:11434/v1'));
        if not FLastEngineNote.IsEmpty then
          Writeln('             (built-in engine skipped: ' + FLastEngineNote + ')');
      end;
  else
    begin
      Writeln('             Active Model: NONE (Fallback Offline Helper)');
      Writeln('             Tip: download one with "localpal model download smollm"');
    end;
  end;

  Writeln('             Type /exit or /quit to exit.');
  Writeln('================================================================================');
  Writeln;

  // Load the model once up front so the first reply doesn't pay the cost.
  if LEngineKind = ekBuiltin then
  begin
    try
      FEngine.EnsureModelLoaded(LModelPath);
    except
      on E: Exception do
        Writeln(Format('[Built-in engine failed to load model: %s]', [E.Message]));
    end;
  end;

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

function TChatManager.EnsureSession: Integer;
begin
  Result := GetMostRecentSession;
  if Result <= 0 then
    Result := CreateSession('default');
end;

procedure TChatManager.QuickChat;
begin
  InteractiveChat(EnsureSession);
end;

procedure TChatManager.QuickAsk(const AContent: string);
begin
  SendMessage(EnsureSession, AContent);
end;

end.
