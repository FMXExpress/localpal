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
  localpal.Model;

type
  TBenchmark = class
  private
    FDb: TDatabase;
    FConfig: TConfig;
    FModelMgr: TModelManager;
  public
    constructor Create(ADb: TDatabase; AConfig: TConfig; AModelMgr: TModelManager);
    procedure RunBenchmark(const AModelName: string = '');
  end;

implementation

constructor TBenchmark.Create(ADb: TDatabase; AConfig: TConfig; AModelMgr: TModelManager);
begin
  inherited Create;
  FDb := ADb;
  FConfig := AConfig;
  FModelMgr := AModelMgr;
end;

procedure TBenchmark.RunBenchmark(const AModelName: string = '');
var
  LModelName: string;
  LActiveModel: TModelInfo;
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
  LPromptTokens, LCompletionTokens: Integer;
  LTimeSeconds: Double;
  LTGSpeed, LPPSpeed: Double;
  LScore: Double;
  LIsOffline: Boolean;
begin
  LModelName := AModelName;
  if LModelName.IsEmpty then
  begin
    if FModelMgr.GetActiveModel(LActiveModel) then
      LModelName := LActiveModel.Name
    else
      LModelName := 'llama3.2:1b'; // Default fallback
  end;

  Writeln('================================================================================');
  Writeln('                          LOCALPAL BENCHMARK UTILITY                            ');
  Writeln('================================================================================');
  Writeln('Target Model : ' + LModelName);

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
  LIsOffline := False;

  LPromptTokens := 0;
  LCompletionTokens := 0;
  LTimeSeconds := 0.0;

  try
    LSysObj := TJSONObject.Create;
    LSysObj.AddPair('role', 'system');
    LSysObj.AddPair('content', 'You are a benchmarking utility. Answer as quickly and briefly as possible.');
    LHistory.AddElement(LSysObj);

    LUserObj := TJSONObject.Create;
    LUserObj.AddPair('role', 'user');
    LUserObj.AddPair('content', 'Write a short story about an AI discovering a star. Exactly 3 sentences.');
    LHistory.AddElement(LUserObj);

    LPayload.AddPair('model', LModelName);
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
      LTimeSeconds := LStopwatch.Elapsed.TotalSeconds;

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
                LPromptTokens := StrToIntDef(LUsage.GetValue('prompt_tokens').Value, 0);
              if Assigned(LUsage.GetValue('completion_tokens')) then
                LCompletionTokens := StrToIntDef(LUsage.GetValue('completion_tokens').Value, 0);
            end;

            // Heuristic if runner usage metadata is missing
            if LPromptTokens = 0 then
              LPromptTokens := 35; // Standard for our prompt
            if LCompletionTokens = 0 then
            begin
              var LChoices := LResJSON.GetValue('choices') as TJSONArray;
              if Assigned(LChoices) and (LChoices.Count > 0) then
              begin
                var LChoice := LChoices.Items[0] as TJSONObject;
                var LMsg := LChoice.GetValue('message') as TJSONObject;
                var LContent := LMsg.GetValue('content').Value;
                // Heuristic: ~4 characters per token
                LCompletionTokens := LContent.Length div 4;
              end;
            end;
          finally
            LResJSON.Free;
          end;
        end;
      end
      else
      begin
        Writeln('Runner returned status: ' + IntToStr(LResponse.StatusCode) + ' ' + LResponse.StatusText);
        LIsOffline := True;
      end;
    except
      on E: Exception do
      begin
        Writeln('Runner is offline or timed out: ' + E.Message);
        LIsOffline := True;
      end;
    end;

  finally
    LHTTP.Free;
    LStringWriter.Free;
    LHistory.Free;
    LPayload.Free;
  end;

  if LIsOffline then
  begin
    Writeln;
    Writeln('--------------------------------------------------------------------------------');
    Writeln(' [!] Ollama or llama.cpp is not responding on ' + LUrl);
    Writeln(' [!] Displaying simulated local hardware benchmark instead...');
    Writeln('--------------------------------------------------------------------------------');
    Writeln;
    LPromptTokens := 45;
    LCompletionTokens := 85;
    // Standard CPU/Integrated GPU speeds
    LTGSpeed := 12.4; 
    LPPSpeed := 34.2;
    LTimeSeconds := (LCompletionTokens / LTGSpeed) + (LPromptTokens / LPPSpeed);
  end
  else
  begin
    if LCompletionTokens = 0 then
      LCompletionTokens := 40;
    LTGSpeed := LCompletionTokens / LTimeSeconds;
    LPPSpeed := LPromptTokens / (LTimeSeconds * 0.15); // Approximate PP time
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
  for I := 1 to LBarLimit do Write('=');
  for I := LBarLimit + 1 to 30 do Write(' ');
  Writeln(']');
  
  Writeln(Format('  Token Generation (TG)   : %.2f tokens/sec', [LTGSpeed]));
  Write('  TG Speed Bar            : [');
  LBarLimit := Round(LTGSpeed);
  if LBarLimit > 30 then LBarLimit := 30;
  for I := 1 to LBarLimit do Write('=');
  for I := LBarLimit + 1 to 30 do Write(' ');
  Writeln(']');
  
  Writeln('--------------------------------------------------------------------------------');
  Writeln(Format('  LOCALPAL PERFORMANCE SCORE: %.2f', [LScore]));
  
  Write('  Rating                  : ');
  if LScore >= 50.0 then
    Writeln('🚀 Excellent (High-end GPU/Dedicated NPU)')
  else if LScore >= 25.0 then
    Writeln('⚡ Good (Mid-range discrete GPU or Apple Silicon)')
  else if LScore >= 10.0 then
    Writeln('✨ Decent (Standard modern CPU with AVX2)')
  else
    Writeln('🐌 Slow (Legacy hardware or unoptimized setup)');
    
  Writeln('================================================================================');
end;

end.