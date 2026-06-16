unit localpal.Model;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.RegularExpressions,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetEncoding,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.Stan.Param,
  localpal.Database;

type
  TModelInfo = record
    Id: Integer;
    Name: string;
    Path: string;
    SizeBytes: Int64;
    IsActive: Boolean;
    CreatedAt: string;
  end;

  TModelTier = (mtLowEnd, mtHighEnd, mtServer);

  TCatalogItem = record
    Id: Integer;
    Key: string;
    Name: string;
    RepoId: string;
    Filename: string;
    Description: string;
    Tier: TModelTier;
    MinRamGB: Integer; // rough RAM/VRAM needed to run the Q4 quant
  end;

const
  ModelCatalog: array[0..18] of TCatalogItem = (
    // --- Low-end: run on CPU or small GPUs ---
    (
      Id: 1;
      Key: 'gemmasutra';
      Name: 'Gemmasutra Mini 2B v1';
      RepoId: 'bartowski/Gemmasutra-Mini-2B-v1-GGUF';
      Filename: 'Gemmasutra-Mini-2B-v1-Q4_K_M.gguf';
      Description: 'A creative writing specialized 2B model.';
      Tier: mtLowEnd;
      MinRamGB: 4
    ),
    (
      Id: 2;
      Key: 'qwen1.5b';
      Name: 'Qwen 2.5 1.5B Instruct';
      RepoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF';
      Filename: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf';
      Description: 'Highly capable state-of-the-art 1.5B model with great multilingual support.';
      Tier: mtLowEnd;
      MinRamGB: 3
    ),
    (
      Id: 3;
      Key: 'qwen3b';
      Name: 'Qwen 2.5 3B Instruct';
      RepoId: 'bartowski/Qwen2.5-3B-Instruct-GGUF';
      Filename: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf';
      Description: 'Excellent balance of speed and reasoning in a 3B package.';
      Tier: mtLowEnd;
      MinRamGB: 4
    ),
    (
      Id: 4;
      Key: 'gemma2';
      Name: 'Gemma 2 2B IT';
      RepoId: 'google/gemma-2-2b-it-GGUF';
      Filename: '2b_it_v2.gguf';
      Description: 'Google''s lightweight state-of-the-art 2B instruction-tuned model.';
      Tier: mtLowEnd;
      MinRamGB: 4
    ),
    (
      Id: 5;
      Key: 'phi3.5';
      Name: 'Phi 3.5 Mini Instruct';
      RepoId: 'bartowski/Phi-3.5-mini-instruct-GGUF';
      Filename: 'Phi-3.5-mini-instruct-Q4_K_M.gguf';
      Description: 'Microsoft''s 3.8B model with excellent reasoning, math, and code capabilities.';
      Tier: mtLowEnd;
      MinRamGB: 6
    ),
    (
      Id: 6;
      Key: 'llama1b';
      Name: 'Llama 3.2 1B Instruct';
      RepoId: 'unsloth/Llama-3.2-1B-Instruct-GGUF';
      Filename: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf';
      Description: 'Meta''s ultra-lightweight 1B parameter model optimized for resource-constrained environments.';
      Tier: mtLowEnd;
      MinRamGB: 2
    ),
    (
      Id: 7;
      Key: 'llama3b';
      Name: 'Llama 3.2 3B Instruct';
      RepoId: 'unsloth/Llama-3.2-3B-Instruct-GGUF';
      Filename: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf';
      Description: 'Meta''s highly versatile and popular 3B parameter conversational model.';
      Tier: mtLowEnd;
      MinRamGB: 4
    ),
    (
      Id: 8;
      Key: 'smollm';
      Name: 'SmolLM2 1.7B Instruct';
      RepoId: 'bartowski/SmolLM2-1.7B-Instruct-GGUF';
      Filename: 'SmolLM2-1.7B-Instruct-Q4_K_M.gguf';
      Description: 'Hugging Face''s compact and extremely fast 1.7B parameter model.';
      Tier: mtLowEnd;
      MinRamGB: 3
    ),
    (
      Id: 9;
      Key: 'smolvlm';
      Name: 'SmolVLM2 500M Instruct';
      RepoId: 'ggml-org/SmolVLM2-500M-Video-Instruct-GGUF';
      Filename: 'SmolVLM2-500M-Video-Instruct-Q4_K_M.gguf';
      Description: 'Hugging Face''s ultra-compact 500M multimodal model optimized for video/image understanding.';
      Tier: mtLowEnd;
      MinRamGB: 2
    ),
    // --- High-end: need a big GPU or 24GB+ of unified memory ---
    (
      Id: 10;
      Key: 'gemma26b';
      Name: 'Gemma 4 26B-A4B';
      RepoId: 'unsloth/gemma-4-26B-A4B-it-qat-GGUF';
      Filename: 'gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf';
      Description: 'MoE (4B active, QAT); fast and capable - the lightest high-end pick (~14GB file).';
      Tier: mtHighEnd;
      MinRamGB: 24
    ),
    (
      Id: 11;
      Key: 'qwen27b';
      Name: 'Qwen 3.6 27B';
      RepoId: 'unsloth/Qwen3.6-27B-GGUF';
      Filename: 'Qwen3.6-27B-Q4_K_M.gguf';
      Description: 'Dense 27B; widely cited as the best local coding model. Slower but high quality.';
      Tier: mtHighEnd;
      MinRamGB: 32
    ),
    (
      Id: 12;
      Key: 'gemma31b';
      Name: 'Gemma 4 31B';
      RepoId: 'unsloth/gemma-4-31B-it-qat-GGUF';
      Filename: 'gemma-4-31B-it-qat-UD-Q4_K_XL.gguf';
      Description: 'Dense 31B (QAT); strong general chat, translation and writing.';
      Tier: mtHighEnd;
      MinRamGB: 32
    ),
    (
      Id: 13;
      Key: 'qwen35b';
      Name: 'Qwen 3.6 35B-A3B';
      RepoId: 'unsloth/Qwen3.6-35B-A3B-MTP-GGUF';
      Filename: 'Qwen3.6-35B-A3B-UD-Q4_K_M.gguf';
      Description: 'MoE (3B active); very fast for its size - the community favorite for local agentic coding.';
      Tier: mtHighEnd;
      MinRamGB: 32
    ),
    (
      Id: 14;
      Key: 'lfm';
      Name: 'LFM2.5 1.2B Instruct';
      RepoId: 'LiquidAI/LFM2.5-1.2B-Instruct-GGUF';
      Filename: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf';
      Description: 'Liquid AI''s ultra-fast 1.2B model; great on CPU-only machines (~730MB).';
      Tier: mtLowEnd;
      MinRamGB: 2
    ),
    (
      Id: 15;
      Key: 'qwencoder';
      Name: 'Qwen 2.5 Coder 7B';
      RepoId: 'bartowski/Qwen2.5-Coder-7B-Instruct-GGUF';
      Filename: 'Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf';
      Description: 'Code-specialized 7B; strong code completion and generation for its size.';
      Tier: mtLowEnd;
      MinRamGB: 6
    ),
    (
      Id: 16;
      Key: 'qwen3coder';
      Name: 'Qwen 3 Coder 30B-A3B';
      RepoId: 'unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF';
      Filename: 'Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf';
      Description: 'MoE (3B active) coding specialist; fast 30B-class agentic coder.';
      Tier: mtHighEnd;
      MinRamGB: 32
    ),
    // --- Server-class: 64GB+ RAM / multi-GPU, large multi-shard downloads ---
    (
      Id: 17;
      Key: 'gptoss';
      Name: 'GPT-OSS 120B';
      RepoId: 'unsloth/gpt-oss-120b-GGUF';
      Filename: 'gpt-oss-120b-F16.gguf';
      Description: 'OpenAI''s 120B MoE; ~65GB single file. Very fast, not the smartest.';
      Tier: mtServer;
      MinRamGB: 80
    ),
    (
      Id: 18;
      Key: 'qwen122b';
      Name: 'Qwen 3.5 122B-A10B';
      RepoId: 'unsloth/Qwen3.5-122B-A10B-MTP-GGUF';
      Filename: 'UD-Q4_K_XL/Qwen3.5-122B-A10B-UD-Q4_K_XL-00001-of-00003.gguf';
      Description: 'MoE (10B active); ~89GB across 3 shards. Strong general model for big rigs.';
      Tier: mtServer;
      MinRamGB: 96
    ),
    (
      Id: 19;
      Key: 'glm47';
      Name: 'GLM-4.7';
      RepoId: 'unsloth/GLM-4.7-GGUF';
      Filename: 'UD-Q4_K_XL/GLM-4.7-UD-Q4_K_XL-00001-of-00005.gguf';
      Description: 'Large flagship; ~205GB across 5 shards. Tip: config set chat_format chatglm3.';
      Tier: mtServer;
      MinRamGB: 224
    )
  );

type
  TModelManager = class
  private
    FDb: TDatabase;
    FLastPercent: Integer;
    procedure HTTPReceiveData(const Sender: TObject; AContentLength: Int64; AReadCount: Int64; var Abort: Boolean);
    function DownloadOneFile(const AUrl, ADestPath: string; out ASizeBytes: Int64): Boolean;
  public
    constructor Create(ADb: TDatabase);
    procedure ListModels;
    procedure AddModel(const AName, APath: string; ASizeBytes: Int64 = 0; AActivate: Boolean = False);
    procedure RemoveModel(const AName: string);
    procedure UseModel(const AName: string);
    function GetActiveModel(var AModel: TModelInfo): Boolean;
    function GetModelByName(const AName: string; var AModel: TModelInfo): Boolean;
    function ResolveModel(const ASelector: string; var AModel: TModelInfo): Boolean;
    function EnsureActiveModel(var AModel: TModelInfo): Boolean;
    procedure SearchHuggingFace(const AQuery: string);
    procedure DownloadModel(const ARepoId, AFilename: string);
    procedure ShowCatalog(AShowHighEnd: Boolean = False);
    function DownloadCatalogItem(const ASelector: string): Boolean;
  end;

implementation

constructor TModelManager.Create(ADb: TDatabase);
begin
  inherited Create;
  FDb := ADb;
end;

procedure TModelManager.ListModels;
var
  LQuery: TFDQuery;
  LActiveStr: string;
  LCount: Integer;
begin
  LQuery := FDb.Query('SELECT id, name, path, size_bytes, is_active, created_at FROM models ORDER BY name');
  try
    LQuery.Open;
    Writeln('================================================================================');
    Writeln('                                REGISTERED MODELS                               ');
    Writeln('================================================================================');
    Writeln(Format('  %-20s | %-6s | %-10s | %s', ['Model Name', 'Active', 'Size (MB)', 'Path/Tag']));
    Writeln('--------------------------------------------------------------------------------');
    LCount := 0;
    while not LQuery.Eof do
    begin
      Inc(LCount);
      if LQuery.FieldByName('is_active').AsInteger = 1 then
        LActiveStr := ' YES '
      else
        LActiveStr := '  -  ';
      
      Writeln(Format('  %-20s | %-6s | %-10.1f | %s', [
        LQuery.FieldByName('name').AsString,
        LActiveStr,
        LQuery.FieldByName('size_bytes').AsLargeInt / (1024 * 1024),
        LQuery.FieldByName('path').AsString
      ]));
      LQuery.Next;
    end;
    if LCount = 0 then
      Writeln('  No models registered. Use "model add" or "model download" to get started!');
    Writeln('================================================================================');
  finally
    LQuery.Free;
  end;
end;

procedure TModelManager.AddModel(const AName, APath: string; ASizeBytes: Int64 = 0; AActivate: Boolean = False);
var
  LQuery: TFDQuery;
  LIsFirst: Boolean;
begin
  // Check if first model to auto-activate
  LQuery := FDb.Query('SELECT COUNT(*) FROM models');
  try
    LQuery.Open;
    LIsFirst := LQuery.Fields[0].AsInteger = 0;
  finally
    LQuery.Free;
  end;

  if AActivate then
    FDb.Exec('UPDATE models SET is_active = 0');

  LQuery := FDb.Query('INSERT OR REPLACE INTO models (name, path, size_bytes, is_active) VALUES (:name, :path, :size_bytes, :is_active)');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.ParamByName('path').AsString := APath;
    LQuery.ParamByName('size_bytes').AsLargeInt := ASizeBytes;
    if LIsFirst or AActivate then
      LQuery.ParamByName('is_active').AsInteger := 1
    else
      LQuery.ParamByName('is_active').AsInteger := 0;
    LQuery.ExecSQL;
    Writeln(Format('Successfully registered model "%s"!', [AName]));
    if LIsFirst or AActivate then
      Writeln(Format('Model "%s" is now set as the active model.', [AName]));
  finally
    LQuery.Free;
  end;
end;

procedure TModelManager.RemoveModel(const AName: string);
var
  LQuery: TFDQuery;
begin
  LQuery := FDb.Query('DELETE FROM models WHERE name = :name');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.ExecSQL;
    Writeln(Format('Removed model "%s" from local database. (The file on disk, if any, was not deleted).', [AName]));
  finally
    LQuery.Free;
  end;
end;

procedure TModelManager.UseModel(const AName: string);
var
  LQuery: TFDQuery;
begin
  // Verify model exists
  LQuery := FDb.Query('SELECT id FROM models WHERE name = :name');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.Open;
    if LQuery.IsEmpty then
    begin
      Writeln(Format('Error: Model "%s" is not registered. Register it first using "model add" or download it.', [AName]));
      Exit;
    end;
  finally
    LQuery.Free;
  end;

  // Deactivate all
  FDb.Exec('UPDATE models SET is_active = 0');
  
  // Activate selected
  LQuery := FDb.Query('UPDATE models SET is_active = 1 WHERE name = :name');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.ExecSQL;
    Writeln(Format('Model "%s" is now the active model.', [AName]));
  finally
    LQuery.Free;
  end;
end;

function TModelManager.GetActiveModel(var AModel: TModelInfo): Boolean;
var
  LQuery: TFDQuery;
begin
  Result := False;
  LQuery := FDb.Query('SELECT id, name, path, size_bytes, is_active, created_at FROM models WHERE is_active = 1 LIMIT 1');
  try
    LQuery.Open;
    if not LQuery.IsEmpty then
    begin
      AModel.Id := LQuery.FieldByName('id').AsInteger;
      AModel.Name := LQuery.FieldByName('name').AsString;
      AModel.Path := LQuery.FieldByName('path').AsString;
      AModel.SizeBytes := LQuery.FieldByName('size_bytes').AsLargeInt;
      AModel.IsActive := True;
      AModel.CreatedAt := LQuery.FieldByName('created_at').AsString;
      Result := True;
    end;
  finally
    LQuery.Free;
  end;
end;

function TModelManager.GetModelByName(const AName: string; var AModel: TModelInfo): Boolean;
var
  LQuery: TFDQuery;
begin
  Result := False;
  LQuery := FDb.Query('SELECT id, name, path, size_bytes, is_active, created_at FROM models WHERE name = :name LIMIT 1');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.Open;
    if not LQuery.IsEmpty then
    begin
      AModel.Id := LQuery.FieldByName('id').AsInteger;
      AModel.Name := LQuery.FieldByName('name').AsString;
      AModel.Path := LQuery.FieldByName('path').AsString;
      AModel.SizeBytes := LQuery.FieldByName('size_bytes').AsLargeInt;
      AModel.IsActive := LQuery.FieldByName('is_active').AsInteger = 1;
      AModel.CreatedAt := LQuery.FieldByName('created_at').AsString;
      Result := True;
    end;
  finally
    LQuery.Free;
  end;
end;

function TModelManager.ResolveModel(const ASelector: string; var AModel: TModelInfo): Boolean;
var
  I: Integer;
begin
  Result := GetModelByName(ASelector, AModel);
  if Result then
    Exit;

  // Allow catalog keys (e.g. "smollm") to refer to already-downloaded models.
  for I := Low(ModelCatalog) to High(ModelCatalog) do
    if SameText(ModelCatalog[I].Key, ASelector) then
      Exit(GetModelByName(ModelCatalog[I].Filename, AModel));
end;

function TModelManager.EnsureActiveModel(var AModel: TModelInfo): Boolean;
var
  LQuery: TFDQuery;
  LName: string;
begin
  Result := GetActiveModel(AModel);
  if Result then
    Exit;

  // No active model - fall back to the most recently registered one.
  LName := '';
  LQuery := FDb.Query('SELECT name FROM models ORDER BY id DESC LIMIT 1');
  try
    LQuery.Open;
    if not LQuery.IsEmpty then
      LName := LQuery.Fields[0].AsString;
  finally
    LQuery.Free;
  end;

  if LName.IsEmpty then
    Exit(False);

  Writeln(Format('[No active model set; auto-selecting "%s".]', [LName]));
  UseModel(LName);
  Result := GetActiveModel(AModel);
end;

procedure TModelManager.SearchHuggingFace(const AQuery: string);
var
  LHTTP: THTTPClient;
  LResponse: IHTTPResponse;
  LUrl: string;
  LJSON: TJSONArray;
  LItem: TJSONObject;
  I: Integer;
  LRepoId: string;
  LDownloads: Integer;
  LLikes: Integer;
begin
  LUrl := 'https://huggingface.co/api/models?search=' + TNetEncoding.URL.Encode(AQuery) + '&filter=gguf&sort=downloads&direction=-1&limit=8';
  Writeln('Searching Hugging Face for GGUF models...');
  
  LHTTP := THTTPClient.Create;
  try
    LResponse := LHTTP.Get(LUrl);
    if LResponse.StatusCode <> 200 then
    begin
      Writeln(Format('Error searching Hugging Face: HTTP %d %s', [LResponse.StatusCode, LResponse.StatusText]));
      Exit;
    end;

    LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONArray;
    if not Assigned(LJSON) then
    begin
      Writeln('Error: Failed to parse search results from Hugging Face.');
      Exit;
    end;

    try
      Writeln('================================================================================');
      Writeln('                             HUGGING FACE GGUF RESULTS                          ');
      Writeln('================================================================================');
      Writeln(Format('  %-50s | %-12s | %-8s', ['Repository ID', 'Downloads', 'Likes']));
      Writeln('--------------------------------------------------------------------------------');
      for I := 0 to LJSON.Count - 1 do
      begin
        LItem := LJSON.Items[I] as TJSONObject;
        LRepoId := LItem.GetValue('id').Value;
        
        LDownloads := 0;
        if Assigned(LItem.GetValue('downloads')) then
          LDownloads := StrToIntDef(LItem.GetValue('downloads').Value, 0);

        LLikes := 0;
        if Assigned(LItem.GetValue('likes')) then
          LLikes := StrToIntDef(LItem.GetValue('likes').Value, 0);

        Writeln(Format('  %-50s | %-12d | %-8d', [LRepoId, LDownloads, LLikes]));
      end;
      if LJSON.Count = 0 then
        Writeln('  No GGUF models found matching your query.');
      Writeln('================================================================================');
      Writeln('To download, run: localpal model download <RepoID> <Filename.gguf>');
    finally
      LJSON.Free;
    end;
  finally
    LHTTP.Free;
  end;
end;

procedure TModelManager.HTTPReceiveData(const Sender: TObject; AContentLength: Int64; AReadCount: Int64; var Abort: Boolean);
var
  LPercent: Integer;
begin
  if AContentLength > 0 then
  begin
    LPercent := Integer((AReadCount * 100) div AContentLength);
    if LPercent <> FLastPercent then
    begin
      FLastPercent := LPercent;
      Write(Format(#13'  Downloading: %d%% (%d/%d MB)...', [
        LPercent,
        AReadCount div (1024 * 1024),
        AContentLength div (1024 * 1024)
      ]));
    end;
  end
  else
  begin
    Write(Format(#13'  Downloading: %d MB received...', [AReadCount div (1024 * 1024)]));
  end;
end;

function TModelManager.DownloadOneFile(const AUrl, ADestPath: string; out ASizeBytes: Int64): Boolean;
var
  LHTTP: THTTPClient;
  LResponse: IHTTPResponse;
  LFileStream: TFileStream;
begin
  Result := False;
  ASizeBytes := 0;

  LHTTP := THTTPClient.Create;
  try
    LHTTP.OnReceiveData := HTTPReceiveData;
    FLastPercent := -1;

    LFileStream := TFileStream.Create(ADestPath, fmCreate);
    try
      try
        LResponse := LHTTP.Get(AUrl, LFileStream);
        Writeln; // Move to next line after progress output
        if LResponse.StatusCode = 200 then
        begin
          ASizeBytes := LFileStream.Size;
          Result := True;
        end
        else
          Writeln(Format('Error downloading: HTTP %d %s', [LResponse.StatusCode, LResponse.StatusText]));
      except
        on E: Exception do
        begin
          Writeln;
          Writeln('Exception during download: ' + E.Message);
        end;
      end;
    finally
      LFileStream.Free;
    end;
  finally
    LHTTP.Free;
  end;

  if not Result then
    DeleteFile(ADestPath);
end;

procedure TModelManager.DownloadModel(const ARepoId, AFilename: string);
var
  LModelsDir: string;
  LMatch: TMatch;
  LDir, LBaseFirst, LPrefix, LTotStr: string;
  LIdxWidth, LTotal, I, LSlash: Integer;
  LPartRepo, LPartBase, LPartLocal, LNum, LUrl, LFirstLocal: string;
  LSize, LTotalSize: Int64;
  LParts: TArray<string>;
  LPart: string;
  LFailed: Boolean;
begin
  LModelsDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'models' + PathDelim;
  if not ForceDirectories(LModelsDir) then
  begin
    Writeln('Error: Could not create models directory: ' + LModelsDir);
    Exit;
  end;

  // Hugging Face paths use '/'. Split any quant subdirectory from the base name.
  LSlash := LastDelimiter('/', AFilename);
  if LSlash > 0 then
  begin
    LDir := Copy(AFilename, 1, LSlash);                 // e.g. 'UD-Q4_K_XL/'
    LBaseFirst := Copy(AFilename, LSlash + 1, MaxInt);  // first-part base name
  end
  else
  begin
    LDir := '';
    LBaseFirst := AFilename;
  end;

  LMatch := TRegEx.Match(LBaseFirst, '^(.*-)(\d+)-of-(\d+)\.gguf$');

  // -------- Single-file model (unchanged behavior) --------
  if not LMatch.Success then
  begin
    LUrl := Format('https://huggingface.co/%s/resolve/main/%s', [ARepoId, AFilename]);
    LFirstLocal := LModelsDir + LBaseFirst;
    Writeln('Connecting to Hugging Face...');
    Writeln('Source: ' + LUrl);
    Writeln('Target: ' + LFirstLocal);
    if DownloadOneFile(LUrl, LFirstLocal, LSize) then
    begin
      Writeln('Download complete! Registering model...');
      AddModel(LBaseFirst, LFirstLocal, LSize, True);
      Writeln('You can start chatting right away: localpal chat');
    end;
    Exit;
  end;

  // -------- Sharded model: download every part, register the first --------
  LPrefix := LMatch.Groups[1].Value;            // name up to the index dash
  LIdxWidth := Length(LMatch.Groups[2].Value);  // zero-pad width (e.g. 5)
  LTotStr := LMatch.Groups[3].Value;            // total, as written (e.g. '00003')
  LTotal := StrToIntDef(LTotStr, 0);
  if LTotal <= 0 then
  begin
    Writeln('Error: could not parse the shard count from "' + AFilename + '".');
    Exit;
  end;

  Writeln(Format('Connecting to Hugging Face (%d-part model)...', [LTotal]));
  Writeln('Note: server-class models are large - this can be tens to hundreds of GB.');
  LTotalSize := 0;
  LParts := [];
  LFailed := False;

  for I := 1 to LTotal do
  begin
    LNum := IntToStr(I);
    while Length(LNum) < LIdxWidth do
      LNum := '0' + LNum;

    LPartBase := LPrefix + LNum + '-of-' + LTotStr + '.gguf';
    LPartRepo := LDir + LPartBase;          // repo-relative path (keeps subdir)
    LPartLocal := LModelsDir + LPartBase;   // stored flat so siblings sit together
    LUrl := Format('https://huggingface.co/%s/resolve/main/%s', [ARepoId, LPartRepo]);

    Writeln(Format('Part %d of %d: %s', [I, LTotal, LPartBase]));
    if not DownloadOneFile(LUrl, LPartLocal, LSize) then
    begin
      LFailed := True;
      Break;
    end;
    LParts := LParts + [LPartLocal];
    LTotalSize := LTotalSize + LSize;
  end;

  if LFailed then
  begin
    Writeln('Download failed; removing the partial shards.');
    for LPart in LParts do
      DeleteFile(LPart);
    Exit;
  end;

  Writeln('All parts downloaded! Registering model...');
  // Register the first shard; llama.cpp auto-loads the rest from the same folder.
  AddModel(LBaseFirst, LModelsDir + LBaseFirst, LTotalSize, True);
  Writeln('You can start chatting right away: localpal chat');
end;

procedure TModelManager.ShowCatalog(AShowHighEnd: Boolean = False);
var
  I: Integer;
begin
  Writeln('================================================================================');
  Writeln('                                 MODEL CATALOG                                  ');
  Writeln('================================================================================');
  Writeln('  Low-end models - run on a CPU or a small GPU (good for an offline laptop):');
  Writeln(Format('  %-3s | %-12s | %-25s | %s', ['ID', 'Key', 'Model Name', 'Description']));
  Writeln('--------------------------------------------------------------------------------');
  for I := Low(ModelCatalog) to High(ModelCatalog) do
    if ModelCatalog[I].Tier = mtLowEnd then
      Writeln(Format('  %-3d | %-12s | %-25s | %s', [
        ModelCatalog[I].Id,
        ModelCatalog[I].Key,
        ModelCatalog[I].Name,
        ModelCatalog[I].Description
      ]));

  if AShowHighEnd then
  begin
    Writeln;
    Writeln('  High-end models - need a big GPU or 24GB+ of unified memory (CPU = very slow):');
    Writeln(Format('  %-3s | %-12s | %-18s | %-6s | %s', ['ID', 'Key', 'Model Name', 'RAM', 'Description']));
    Writeln('--------------------------------------------------------------------------------');
    for I := Low(ModelCatalog) to High(ModelCatalog) do
      if ModelCatalog[I].Tier = mtHighEnd then
        Writeln(Format('  %-3d | %-12s | %-18s | %-6s | %s', [
          ModelCatalog[I].Id,
          ModelCatalog[I].Key,
          ModelCatalog[I].Name,
          IntToStr(ModelCatalog[I].MinRamGB) + 'GB',
          ModelCatalog[I].Description
        ]));

    Writeln;
    Writeln('  Server-class models - 64GB+ RAM / multi-GPU, big multi-shard downloads (60-200GB+):');
    Writeln(Format('  %-3s | %-12s | %-20s | %-6s | %s', ['ID', 'Key', 'Model Name', 'RAM', 'Description']));
    Writeln('--------------------------------------------------------------------------------');
    for I := Low(ModelCatalog) to High(ModelCatalog) do
      if ModelCatalog[I].Tier = mtServer then
        Writeln(Format('  %-3d | %-12s | %-20s | %-6s | %s', [
          ModelCatalog[I].Id,
          ModelCatalog[I].Key,
          ModelCatalog[I].Name,
          IntToStr(ModelCatalog[I].MinRamGB) + 'GB',
          ModelCatalog[I].Description
        ]));
  end
  else
  begin
    Writeln;
    Writeln('  + high-end and server-class models available (Qwen 3.6/3.5, Gemma 4, GLM, GPT-OSS).');
    Writeln('    Run "localpal model catalog --all" to see them.');
  end;

  Writeln('================================================================================');
  Writeln('To download a catalog model, run:');
  Writeln('  localpal model download <ID or Key>');
  Writeln('  Example: localpal model download smollm   (or: localpal model download 8)');
  Writeln('================================================================================');
end;

function TModelManager.DownloadCatalogItem(const ASelector: string): Boolean;
var
  I: Integer;
  LMatched: Boolean;
  LIndex: Integer;
begin
  Result := False;
  LMatched := False;
  LIndex := -1;

  // Try to match by ID
  if TryStrToInt(ASelector, LIndex) then
  begin
    for I := Low(ModelCatalog) to High(ModelCatalog) do
    begin
      if ModelCatalog[I].Id = LIndex then
      begin
        LMatched := True;
        LIndex := I;
        Break;
      end;
    end;
  end;

  // Try to match by Key
  if not LMatched then
  begin
    for I := Low(ModelCatalog) to High(ModelCatalog) do
    begin
      if SameText(ModelCatalog[I].Key, ASelector) then
      begin
        LMatched := True;
        LIndex := I;
        Break;
      end;
    end;
  end;

  if LMatched then
  begin
    Writeln(Format('Selected Catalog Model: %s', [ModelCatalog[LIndex].Name]));
    DownloadModel(ModelCatalog[LIndex].RepoId, ModelCatalog[LIndex].Filename);
    Result := True;
  end;
end;

end.
