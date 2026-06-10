unit localpal.Engine;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Variants,
  LlamaCpp.Llama,
  LlamaCpp.Common.Settings,
  LlamaCpp.Common.Chat.Types,
  localpal.Config;

type
  TTokenCallback = reference to procedure(const AToken: string);

  TEngineMessage = record
    Role: string;
    Content: string;
    class function Make(const ARole, AContent: string): TEngineMessage; static;
  end;

  TEngineUsage = record
    PromptTokens: Integer;
    CompletionTokens: Integer;
    TotalTokens: Integer;
  end;

  // In-process inference engine backed by the bundled llama-cpp-delphi
  // bindings. Loads GGUF model files directly instead of talking to an
  // external runner.
  TLlamaEngine = class
  private
    class var FLibsLoaded: Boolean;
    class procedure LoadLibraries(const ALibDir: string);
  private
    FConfig: TConfig;
    FLlama: TLlama;
    FModelPath: string;
    function BuildSettings(const AMessages: TArray<TEngineMessage>;
      const AStream: Boolean): TLlamaChatCompletionSettings;
  public
    constructor Create(AConfig: TConfig);
    destructor Destroy; override;

    function FindLibDir: string;
    function LibrariesAvailable: Boolean;

    procedure EnsureModelLoaded(const AModelPath: string);
    procedure UnloadModel;

    // Streams tokens through AOnToken as they are generated and returns the
    // full response text.
    function Chat(const AMessages: TArray<TEngineMessage>;
      const AOnToken: TTokenCallback): string;
    // Non-streaming variant that reports token usage (used by benchmarking).
    function ChatComplete(const AMessages: TArray<TEngineMessage>;
      out AUsage: TEngineUsage;
      const AMaxTokens: Integer = 0;
      const ATemperature: Single = -1.0): string;

    property ModelPath: string read FModelPath;
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF MSWINDOWS}
  LlamaCpp.Api.Llama,
  LlamaCpp.Api.Ggml,
  LlamaCpp.Api.Llava;

const
{$IFDEF MSWINDOWS}
  LIB_LLAMA = 'llama.dll';
  LIB_GGML = 'ggml.dll';
  LIB_LLAVA = 'llava_shared.dll';
{$ELSEIF DEFINED(OSX64)}
  LIB_LLAMA = 'libllama.dylib';
  LIB_GGML = 'libggml.dylib';
  LIB_LLAVA = 'libllava_shared.dylib';
{$ELSE}
  LIB_LLAMA = 'libllama.so';
  LIB_GGML = 'libggml.so';
  LIB_LLAVA = 'libllava_shared.so';
{$ENDIF MSWINDOWS}

{ TEngineMessage }

class function TEngineMessage.Make(const ARole, AContent: string): TEngineMessage;
begin
  Result.Role := ARole;
  Result.Content := AContent;
end;

{ TLlamaEngine }

constructor TLlamaEngine.Create(AConfig: TConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FLlama := nil;
  FModelPath := '';
end;

destructor TLlamaEngine.Destroy;
begin
  UnloadModel;
  inherited Destroy;
end;

function TLlamaEngine.FindLibDir: string;

  function HasLibs(const ADir: string): Boolean;
  begin
    Result := (not ADir.IsEmpty) and
      TFile.Exists(TPath.Combine(ADir, LIB_LLAMA)) and
      TFile.Exists(TPath.Combine(ADir, LIB_GGML));
  end;

var
  LExeDir: string;
  LConfigured: string;
begin
  LConfigured := FConfig.GetVal('lib_dir');
  if HasLibs(LConfigured) then
    Exit(LConfigured);

  LExeDir := TPath.GetDirectoryName(ParamStr(0));
  if HasLibs(TPath.Combine(LExeDir, 'llamacpp')) then
    Exit(TPath.Combine(LExeDir, 'llamacpp'));

  if HasLibs(LExeDir) then
    Exit(LExeDir);

  Result := '';
end;

function TLlamaEngine.LibrariesAvailable: Boolean;
begin
  Result := not FindLibDir.IsEmpty;
end;

class procedure TLlamaEngine.LoadLibraries(const ALibDir: string);
begin
  if FLibsLoaded then
    Exit;

{$IFDEF MSWINDOWS}
  // Lets llama.dll resolve its dependent DLLs from the same folder.
  SetDllDirectory(PChar(ALibDir));
{$ENDIF MSWINDOWS}

  TLlamaApi.Instance.Load(TPath.Combine(ALibDir, LIB_LLAMA));
  TGgmlApi.Instance.Load(TPath.Combine(ALibDir, LIB_GGML));

  // llava is only needed for multimodal models and is not part of the
  // minimal library set shipped with localpal.
  if TFile.Exists(TPath.Combine(ALibDir, LIB_LLAVA)) then
    TLlavaApi.Instance.Load(TPath.Combine(ALibDir, LIB_LLAVA));

  FLibsLoaded := True;
end;

procedure TLlamaEngine.EnsureModelLoaded(const AModelPath: string);
var
  LLibDir: string;
begin
  if Assigned(FLlama) and SameFileName(FModelPath, AModelPath) then
    Exit;

  if not TFile.Exists(AModelPath) then
    raise Exception.CreateFmt('Model file not found: %s', [AModelPath]);

  LLibDir := FindLibDir;
  if LLibDir.IsEmpty then
    raise Exception.Create(
      'llama.cpp libraries not found. Place ' + LIB_LLAMA + ' and ' + LIB_GGML +
      ' next to the localpal executable (or in a "llamacpp" subfolder), ' +
      'or point the "lib_dir" config key at them.');

  LoadLibraries(LLibDir);
  UnloadModel;

  Writeln(Format('[Loading model "%s" with built-in llama.cpp. This may take a moment...]',
    [TPath.GetFileName(AModelPath)]));

  FLlama := TLlama.Create(nil);
  try
    FLlama.ModelPath := AModelPath;
    FLlama.Settings.NCtx := StrToIntDef(FConfig.GetVal('n_ctx', '4096'), 4096);
    FLlama.Settings.NGpuLayers := StrToIntDef(FConfig.GetVal('n_gpu_layers', '0'), 0);
    FLlama.Settings.Verbose := False;
    FLlama.Init;
  except
    FreeAndNil(FLlama);
    raise;
  end;
  FModelPath := AModelPath;
end;

procedure TLlamaEngine.UnloadModel;
begin
  FreeAndNil(FLlama);
  FModelPath := '';
end;

function TLlamaEngine.BuildSettings(const AMessages: TArray<TEngineMessage>;
  const AStream: Boolean): TLlamaChatCompletionSettings;
var
  LMessages: TArray<TChatCompletionRequestMessage>;
  I: Integer;
begin
  SetLength(LMessages, Length(AMessages));
  for I := 0 to High(AMessages) do
  begin
    if SameText(AMessages[I].Role, 'system') then
      LMessages[I] := TChatCompletionRequestMessage.System(AMessages[I].Content)
    else if SameText(AMessages[I].Role, 'assistant') then
      LMessages[I] := TChatCompletionRequestMessage.Assistant(AMessages[I].Content)
    else
      LMessages[I] := TChatCompletionRequestMessage.User(AMessages[I].Content);
  end;

  Result := TLlamaChatCompletionSettings.Create(LMessages);
  Result.Temperature := StrToFloatDef(FConfig.GetVal('temperature', '0.7'), 0.7);
  Result.MaxTokens := StrToIntDef(FConfig.GetVal('max_tokens', '512'), 512);
  Result.Stream := AStream;
end;

function TLlamaEngine.Chat(const AMessages: TArray<TEngineMessage>;
  const AOnToken: TTokenCallback): string;
var
  LSettings: TLlamaChatCompletionSettings;
  LResponse: TCreateChatCompletionResponse;
  LBuffer: TStringBuilder;
begin
  if not Assigned(FLlama) then
    raise Exception.Create('No model loaded in the built-in engine.');

  if not Assigned(AOnToken) then
  begin
    LSettings := BuildSettings(AMessages, False);
    LResponse := FLlama.CreateChatCompletion(LSettings);
    if Length(LResponse.Choices) > 0 then
      Exit(VarToStrDef(LResponse.Choices[0].Message.Content, ''));
    Exit('');
  end;

  LSettings := BuildSettings(AMessages, True);
  LBuffer := TStringBuilder.Create;
  try
    FLlama.CreateChatCompletion(
      LSettings,
      procedure(const AResponse: TChatCompletionStreamResponse;
        var AContinue: Boolean)
      var
        LChunk: string;
      begin
        if Length(AResponse.Choices) = 0 then
          Exit;
        LChunk := VarToStrDef(AResponse.Choices[0].Delta.Content, '');
        if LChunk.IsEmpty then
          Exit;
        LBuffer.Append(LChunk);
        AOnToken(LChunk);
      end);
    Result := LBuffer.ToString;
  finally
    LBuffer.Free;
  end;
end;

function TLlamaEngine.ChatComplete(const AMessages: TArray<TEngineMessage>;
  out AUsage: TEngineUsage; const AMaxTokens: Integer;
  const ATemperature: Single): string;
var
  LSettings: TLlamaChatCompletionSettings;
  LResponse: TCreateChatCompletionResponse;
begin
  if not Assigned(FLlama) then
    raise Exception.Create('No model loaded in the built-in engine.');

  LSettings := BuildSettings(AMessages, False);
  if AMaxTokens > 0 then
    LSettings.MaxTokens := AMaxTokens;
  if ATemperature >= 0 then
    LSettings.Temperature := ATemperature;

  LResponse := FLlama.CreateChatCompletion(LSettings);

  AUsage.PromptTokens := LResponse.Usage.PromptTokens;
  AUsage.CompletionTokens := LResponse.Usage.CompletionTokens;
  AUsage.TotalTokens := LResponse.Usage.TotalTokens;

  if Length(LResponse.Choices) > 0 then
    Result := VarToStrDef(LResponse.Choices[0].Message.Content, '')
  else
    Result := '';
end;

end.
