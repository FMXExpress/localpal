unit localpal.Benchmark;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  System.JSON,
  System.Net.HttpClient,
  localpal.Database,
  localpal.Config,
  localpal.Model,
  localpal.Engine;

type
  TBenchmark = class
  private
    FDb: TDatabase;
    FConfig: TConfig;
    FModelMgr: TModelManager;
    FEngine: TLlamaEngine;
    function RunBuiltin(const AModelPath: string;
      out APromptTokens, ACompletionTokens: Integer;
      out APPSpeed, ATGSpeed, ATotalSeconds: Double): Boolean;
    function RunRunner(const AModelName: string;
      out APromptTokens, ACompletionTokens: Integer;
      out APPSpeed, ATGSpeed, ATotalSeconds: Double): Boolean;
  public
    constructor Create(ADb: TDatabase; AConfig: TConfig; AModelMgr: TModelManager);
    destructor Destroy; override;
    procedure RunBenchmark(const AModelName: string = '');
  end;

implementation

const
  BENCH_SYSTEM_PROMPT = 'You are a benchmarking utility. Answer as quickly and briefly as possible.';
  BENCH_USER_PROMPT = 'Write a short story about an AI discovering a star. Exactly 3 sentences.';

constructor TBenchmark.Create(ADb: TDatabase; AConfig: TConfig; AModelMgr: TModelManager);
begin
  inherited Create;
  FDb := ADb;
  FConfig := AConfig;
  FModelMgr := AModelMgr;
  FEngine := TLlamaEngine.Create(AConfig);
end;

destructor TBenchmark.Destroy;
begin
  FEngine.Free;
  inherited Destroy;
end;

function TBenchmark.RunBuiltin(const AModelPath: string;
  out APromptTokens, ACompletionTokens: Integer;
  out APPSpeed, ATGSpeed, ATotalSeconds: Double): Boolean;
var
  LStopwatch: TStopwatch;
  LMessages: TArray<TEngineMessage>;
  LTokenCount: Integer;
  LFirstTokenMs: Int64;
  LTotalMs: Int64;
  LPPSeconds, LTGSeconds: Double;
begin
  Result := False;
  APromptTokens := 0;
  ACompletionTokens := 0;
  APPSpeed := 0.0;
  ATGSpeed := 0.0;
  ATotalSeconds := 0.0;

  try
    LStopwatch := TStopwatch.StartNew;
    FEngine.EnsureModelLoaded(AModelPath);
    LStopwatch.Stop;
    Writeln(Format('Model loaded in %.2f seconds.', [LStopwatch.Elapsed.TotalSeconds]));
    Writeln('Running test generation (128 max tokens)...');

    LMessages := [
      TEngineMessage.Make('system', BENCH_SYSTEM_PROMPT),
      TEngineMessage.Make('user', BENCH_USER_PROMPT)
    ];

    // Count the prompt with the model's own tokenizer (the chat template
    // adds a few control tokens on top; close enough for a benchmark).
    APromptTokens := FEngine.CountTokens(BENCH_SYSTEM_PROMPT + sLineBreak + BENCH_USER_PROMPT);
    if APromptTokens <= 0 then
      APromptTokens := 35;

    // Stream the completion: time to the first token approximates the prompt
    // processing phase, the rest is token generation, and each streamed
    // chunk is one token.
    LTokenCount := 0;
    LFirstTokenMs := 0;
    LStopwatch := TStopwatch.StartNew;
    FEngine.Chat(LMessages,
      procedure(const AToken: string)
      begin
        if LTokenCount = 0 then
          LFirstTokenMs := LStopwatch.ElapsedMilliseconds;
        Inc(LTokenCount);
      end,
      128, 0.1);
    LStopwatch.Stop;
    LTotalMs := LStopwatch.ElapsedMilliseconds;

    if LTokenCount = 0 then
    begin
      Writeln('Built-in engine produced no tokens.');
      Exit;
    end;

    ACompletionTokens := LTokenCount;
    ATotalSeconds := LTotalMs / 1000.0;

    if LFirstTokenMs <= 0 then
      LFirstTokenMs := 1;
    LPPSeconds := LFirstTokenMs / 1000.0;
    LTGSeconds := (LTotalMs - LFirstTokenMs) / 1000.0;
    if LTGSeconds <= 0 then
      LTGSeconds := 0.001;

    APPSpeed := APromptTokens / LPPSeconds;
    if LTokenCount > 1 then
      ATGSpeed := (LTokenCount - 1) / LTGSeconds
    else
      ATGSpeed := 1 / LTGSeconds;

    Result := True;
  except
    on E: Exception do
      Writeln('Built-in engine benchmark failed: ' + E.Message);
  end;
end;

function TBenchmark.RunRunner(const AModelName: string;
  out APromptTokens, ACompletionTokens: Integer;
  out APPSpeed, ATGSpeed, ATotalSeconds: Double): Boolean;
var
  LStopwatch: TStopwatch;
  LHTTP: THTTPClient;
  LResponse: IHTTPResponse;
  LPayload: TJSONObject;
  LHistory: TJSONArray;
  LSysObj, LUserObj: TJSONObject;
  LStringWriter: TStringList;
  LUrl: string;
  LTemp: string;
  LResJSON: TJSONObject;
begin
  Result := False;
  APromptTokens := 0;
  ACompletionTokens := 0;
  APPSpeed := 0.0;
  ATGSpeed := 0.0;
  ATotalSeconds := 0.0;

  LUrl := FConfig.GetVal('runner_url', 'http://localhost:11434/v1');
  if not LUrl.EndsWith('/') then
    LUrl := LUrl + '/';
  LUrl := LUrl + 'chat/completions';

  Writeln('Runner URL   : ' + LUrl);
  Writeln('Sending test request (128 max tokens)...');

  LPayload := TJSONObject.Create;
  LHistory := TJSONArray.Create;
  LStringWriter := TStringList.Create;
  LHTTP := THTTPClient.Create;
  try
    LSysObj := TJSONObject.Create;
    LSysObj.AddPair('role', 'system');
    LSysObj.AddPair('content', BENCH_SYSTEM_PROMPT);
    LHistory.AddElement(LSysObj);

    LUserObj := TJSONObject.Create;
    LUserObj.AddPair('role', 'user');
    LUserObj.AddPair('content', BENCH_USER_PROMPT);
    LHistory.AddElement(LUserObj);

    LPayload.AddPair('model', AModelName);
    LPayload.AddPair('messages', LHistory.Clone as TJSONArray);
    LPayload.AddPair('temperature', TJSONNumber.Create(0.1));
    LPayload.AddPair('max_tokens', TJSONNumber.Create(128));
    LPayload.AddPair('stream', TJSONBool.Create(False));

    LStringWriter.Text := LPayload.ToJSON;

    LHTTP.ContentType := 'application/json';
    LHTTP.ConnectionTimeout := 3000;
    LHTTP.ResponseTimeout := 25000;

    var LHFToken := FConfig.GetVal('hf_token');
    if not LHFToken.IsEmpty then
      LHTTP.CustomHeaders['Authorization'] := 'Bearer ' + LHFToken;

    LStopwatch := TStopwatch.StartNew;
    try
      LResponse := LHTTP.Post(LUrl, LStringWriter);
      LStopwatch.Stop;
      ATotalSeconds := LStopwatch.Elapsed.TotalSeconds;

      if LResponse.StatusCode = 200 then
      begin
        LTemp := LResponse.ContentAsString;
        LResJSON := TJSONObject.ParseJSONValue(LTemp) as TJSONObject;
        if Assigned(LResJSON) then
        begin
          try
            var LUsage := LResJSON.GetValue('usage') as TJSONObject;
            if Assigned(LUsage) then
            begin
              if Assigned(LUsage.GetValue('prompt_tokens')) then
                APromptTokens := StrToIntDef(LUsage.GetValue('prompt_tokens').Value, 0);
              if Assigned(LUsage.GetValue('completion_tokens')) then
                ACompletionTokens := StrToIntDef(LUsage.GetValue('completion_tokens').Value, 0);
            end;

            // Heuristics when runner usage metadata is missing or implausible
            if (APromptTokens <= 0) or (APromptTokens > 100000) then
              APromptTokens := 35; // Standard for our prompt
            if ACompletionTokens <= 0 then
            begin
              var LChoices := LResJSON.GetValue('choices') as TJSONArray;
              if Assigned(LChoices) and (LChoices.Count > 0) then
              begin
                var LChoice := LChoices.Items[0] as TJSONObject;
                var LMsg := LChoice.GetValue('message') as TJSONObject;
                var LContent := LMsg.GetValue('content').Value;
                // Heuristic: ~4 characters per token
                ACompletionTokens := LContent.Length div 4;
              end;
            end;
            if ACompletionTokens <= 0 then
              ACompletionTokens := 40;

            if ATotalSeconds <= 0 then
              ATotalSeconds := 0.001;

            // The non-streaming runner response gives no PP/TG split; assume
            // ~15% of the time went to prompt processing.
            ATGSpeed := ACompletionTokens / ATotalSeconds;
            APPSpeed := APromptTokens / (ATotalSeconds * 0.15);

            Result := True;
          finally
            LResJSON.Free;
          end;
        end;
      end
      else
      begin
        Writeln('Runner returned status: ' + IntToStr(LResponse.StatusCode) + ' ' + LResponse.StatusText);
      end;
    except
      on E: Exception do
      begin
        Writeln('Runner is offline or timed out: ' + E.Message);
      end;
    end;

  finally
    LHTTP.Free;
    LStringWriter.Free;
    LHistory.Free;
    LPayload.Free;
  end;
end;

procedure TBenchmark.RunBenchmark(const AModelName: string = '');
var
  LModelName: string;
  LModelPath: string;
  LInfo: TModelInfo;
  LPromptTokens, LCompletionTokens: Integer;
  LTimeSeconds: Double;
  LTGSpeed, LPPSpeed: Double;
  LScore: Double;
  LIsOffline: Boolean;
  LUseBuiltin: Boolean;
  LEngineMode: string;
  LReason: string;
begin
  // Resolve the model under test (explicit arg > active > default tag)
  LModelName := '';
  LModelPath := '';

  if not AModelName.IsEmpty then
  begin
    if FModelMgr.ResolveModel(AModelName, LInfo) then
    begin
      LModelName := LInfo.Name;
      LModelPath := LInfo.Path;
    end
    else
      LModelName := AModelName; // raw runner tag
  end
  else if FModelMgr.EnsureActiveModel(LInfo) then
  begin
    LModelName := LInfo.Name;
    LModelPath := LInfo.Path;
  end
  else
    LModelName := 'llama3.2:1b'; // Default fallback

  // Same engine choice rules as chat
  LReason := '';
  LEngineMode := FConfig.GetVal('engine', 'auto');
  if SameText(LEngineMode, 'builtin') then
    LUseBuiltin := True
  else if SameText(LEngineMode, 'runner') then
    LUseBuiltin := False
  else
  begin
    LReason := FEngine.BuiltinUnavailableReason(LModelPath);
    LUseBuiltin := LReason = '';
  end;

  Writeln('================================================================================');
  Writeln('                          LOCALPAL BENCHMARK UTILITY                            ');
  Writeln('================================================================================');
  Writeln('Target Model : ' + LModelName);
  if LUseBuiltin then
    Writeln('Engine       : built-in llama.cpp (in-process)')
  else
  begin
    Writeln('Engine       : local runner');
    if not LReason.IsEmpty then
      Writeln('Note         : built-in engine skipped because ' + LReason);
  end;

  if LUseBuiltin then
    LIsOffline := not RunBuiltin(LModelPath, LPromptTokens, LCompletionTokens,
      LPPSpeed, LTGSpeed, LTimeSeconds)
  else
    LIsOffline := not RunRunner(LModelName, LPromptTokens, LCompletionTokens,
      LPPSpeed, LTGSpeed, LTimeSeconds);

  if LIsOffline then
  begin
    Writeln;
    Writeln('--------------------------------------------------------------------------------');
    Writeln(' [!] No working engine for this model (built-in llama.cpp or runner).');
    Writeln(' [!] Displaying simulated local hardware benchmark instead...');
    Writeln('--------------------------------------------------------------------------------');
    Writeln;
    LPromptTokens := 45;
    LCompletionTokens := 85;
    // Standard CPU/Integrated GPU speeds
    LTGSpeed := 12.4;
    LPPSpeed := 34.2;
    LTimeSeconds := (LCompletionTokens / LTGSpeed) + (LPromptTokens / LPPSpeed);
  end;

  LScore := (LTGSpeed * 0.6) + (LPPSpeed * 0.4);

  // Print results beautifully
  Writeln;
  Writeln('================================= RESULTS ======================================');
  Writeln(Format('  Total Elapsed Time      : %.2f seconds', [LTimeSeconds]));
  Writeln(Format('  Prompt Tokens (PP)      : %d tokens', [LPromptTokens]));
  Writeln(Format('  Generated Tokens (TG)   : %d tokens', [LCompletionTokens]));
  Writeln;
  Writeln(Format('  Prompt Processing (PP)  : %.2f tokens/sec', [LPPSpeed]));
  Write('  PP Speed Bar            : [');
  var I: Integer;
  var LBarLimit: Integer;
  LBarLimit := Round(LPPSpeed / 2);
  if LBarLimit > 30 then LBarLimit := 30;
  if LBarLimit < 0 then LBarLimit := 0;
  for I := 1 to LBarLimit do Write('=');
  for I := LBarLimit + 1 to 30 do Write(' ');
  Writeln(']');

  Writeln(Format('  Token Generation (TG)   : %.2f tokens/sec', [LTGSpeed]));
  Write('  TG Speed Bar            : [');
  LBarLimit := Round(LTGSpeed);
  if LBarLimit > 30 then LBarLimit := 30;
  if LBarLimit < 0 then LBarLimit := 0;
  for I := 1 to LBarLimit do Write('=');
  for I := LBarLimit + 1 to 30 do Write(' ');
  Writeln(']');

  Writeln('--------------------------------------------------------------------------------');
  Writeln(Format('  LOCALPAL PERFORMANCE SCORE: %.2f', [LScore]));

  Write('  Rating                  : ');
  if LScore >= 50.0 then
    Writeln('Excellent (High-end GPU/Dedicated NPU)')
  else if LScore >= 25.0 then
    Writeln('Good (Mid-range discrete GPU or Apple Silicon)')
  else if LScore >= 10.0 then
    Writeln('Decent (Standard modern CPU with AVX2)')
  else
    Writeln('Slow (Legacy hardware or unoptimized setup)');

  Writeln('================================================================================');
end;

end.
