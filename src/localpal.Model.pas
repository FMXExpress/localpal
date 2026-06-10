unit localpal.Model;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
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

  TCatalogItem = record
    Id: Integer;
    Key: string;
    Name: string;
    RepoId: string;
    Filename: string;
    Description: string;
  end;

const
  ModelCatalog: array[0..8] of TCatalogItem = (
    (
      Id: 1;
      Key: 'gemmasutra';
      Name: 'Gemmasutra Mini 2B v1';
      RepoId: 'bartowski/Gemmasutra-Mini-2B-v1-GGUF';
      Filename: 'Gemmasutra-Mini-2B-v1-Q4_K_M.gguf';
      Description: 'A creative writing specialized 2B model.'
    ),
    (
      Id: 2;
      Key: 'qwen1.5b';
      Name: 'Qwen 2.5 1.5B Instruct';
      RepoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF';
      Filename: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf';
      Description: 'Highly capable state-of-the-art 1.5B model with great multilingual support.'
    ),
    (
      Id: 3;
      Key: 'qwen3b';
      Name: 'Qwen 2.5 3B Instruct';
      RepoId: 'bartowski/Qwen2.5-3B-Instruct-GGUF';
      Filename: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf';
      Description: 'Excellent balance of speed and reasoning in a 3B package.'
    ),
    (
      Id: 4;
      Key: 'gemma2';
      Name: 'Gemma 2 2B IT';
      RepoId: 'google/gemma-2-2b-it-GGUF';
      Filename: '2b_it_v2.gguf';
      Description: 'Google''s lightweight state-of-the-art 2B instruction-tuned model.'
    ),
    (
      Id: 5;
      Key: 'phi3.5';
      Name: 'Phi 3.5 Mini Instruct';
      RepoId: 'bartowski/Phi-3.5-mini-instruct-GGUF';
      Filename: 'Phi-3.5-mini-instruct-Q4_K_M.gguf';
      Description: 'Microsoft''s 3.8B model with excellent reasoning, math, and code capabilities.'
    ),
    (
      Id: 6;
      Key: 'llama1b';
      Name: 'Llama 3.2 1B Instruct';
      RepoId: 'unsloth/Llama-3.2-1B-Instruct-GGUF';
      Filename: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf';
      Description: 'Meta''s ultra-lightweight 1B parameter model optimized for resource-constrained environments.'
    ),
    (
      Id: 7;
      Key: 'llama3b';
      Name: 'Llama 3.2 3B Instruct';
      RepoId: 'unsloth/Llama-3.2-3B-Instruct-GGUF';
      Filename: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf';
      Description: 'Meta''s highly versatile and popular 3B parameter conversational model.'
    ),
    (
      Id: 8;
      Key: 'smollm';
      Name: 'SmolLM2 1.7B Instruct';
      RepoId: 'bartowski/SmolLM2-1.7B-Instruct-GGUF';
      Filename: 'SmolLM2-1.7B-Instruct-Q4_K_M.gguf';
      Description: 'Hugging Face''s compact and extremely fast 1.7B parameter model.'
    ),
    (
      Id: 9;
      Key: 'smolvlm';
      Name: 'SmolVLM2 500M Instruct';
      RepoId: 'ggml-org/SmolVLM2-500M-Video-Instruct-GGUF';
      Filename: 'SmolVLM2-500M-Video-Instruct-Q4_K_M.gguf';
      Description: 'Hugging Face''s ultra-compact 500M multimodal model optimized for video/image understanding.'
    )
  );

type
  TModelManager = class
  private
    FDb: TDatabase;
    FLastPercent: Integer;
    procedure HTTPReceiveData(const Sender: TObject; AContentLength: Int64; AReadCount: Int64; var Abort: Boolean);
  public
    constructor Create(ADb: TDatabase);
    procedure ListModels;
    procedure AddModel(const AName, APath: string; ASizeBytes: Int64 = 0);
    procedure RemoveModel(const AName: string);
    procedure UseModel(const AName: string);
    function GetActiveModel(var AModel: TModelInfo): Boolean;
    procedure SearchHuggingFace(const AQuery: string);
    procedure DownloadModel(const ARepoId, AFilename: string);
    procedure ShowCatalog;
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

procedure TModelManager.AddModel(const AName, APath: string; ASizeBytes: Int64 = 0);
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

  LQuery := FDb.Query('INSERT OR REPLACE INTO models (name, path, size_bytes, is_active) VALUES (:name, :path, :size_bytes, :is_active)');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.ParamByName('path').AsString := APath;
    LQuery.ParamByName('size_bytes').AsLargeInt := ASizeBytes;
    if LIsFirst then
      LQuery.ParamByName('is_active').AsInteger := 1
    else
      LQuery.ParamByName('is_active').AsInteger := 0;
    LQuery.ExecSQL;
    Writeln(Format('Successfully registered model "%s"!', [AName]));
    if LIsFirst then
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

procedure TModelManager.DownloadModel(const ARepoId, AFilename: string);
var
  LHTTP: THTTPClient;
  LResponse: IHTTPResponse;
  LUrl: string;
  LModelsDir: string;
  LDestPath: string;
  LFileStream: TFileStream;
  LSizeBytes: Int64;
begin
  LUrl := Format('https://huggingface.co/%s/resolve/main/%s', [ARepoId, AFilename]);
  LModelsDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'models' + PathDelim;
  
  if not ForceDirectories(LModelsDir) then
  begin
    Writeln('Error: Could not create models directory: ' + LModelsDir);
    Exit;
  end;

  LDestPath := LModelsDir + AFilename;
  Writeln('Connecting to Hugging Face...');
  Writeln('Source: ' + LUrl);
  Writeln('Target: ' + LDestPath);

  LHTTP := THTTPClient.Create;
  try
    LHTTP.OnReceiveData := HTTPReceiveData;
    FLastPercent := -1;

    LFileStream := TFileStream.Create(LDestPath, fmCreate);
    try
      try
        LResponse := LHTTP.Get(LUrl, LFileStream);
        Writeln; // Move to next line after progress output

        if LResponse.StatusCode <> 200 then
        begin
          Writeln(Format('Error downloading model: HTTP %d %s', [LResponse.StatusCode, LResponse.StatusText]));
          LFileStream.Free; // Free first so we can delete the failed file
          DeleteFile(LDestPath);
          Exit;
        end;

        LSizeBytes := LFileStream.Size;
      except
        on E: Exception do
        begin
          Writeln;
          Writeln('Exception during download: ' + E.Message);
          LFileStream.Free;
          DeleteFile(LDestPath);
          Exit;
        end;
      end;
    finally
      if Assigned(LFileStream) and (LFileStream.Handle <> THandle(-1)) then
        LFileStream.Free;
    end;

    Writeln('Download complete! Registering model...');
    AddModel(AFilename, LDestPath, LSizeBytes);
  finally
    LHTTP.Free;
  end;
end;

procedure TModelManager.ShowCatalog;
var
  I: Integer;
begin
  Writeln('================================================================================');
  Writeln('                                 MODEL CATALOG                                  ');
  Writeln('================================================================================');
  Writeln(Format('  %-3s | %-12s | %-25s | %s', ['ID', 'Key', 'Model Name', 'Description']));
  Writeln('--------------------------------------------------------------------------------');
  for I := Low(ModelCatalog) to High(ModelCatalog) do
  begin
    Writeln(Format('  %-3d | %-12s | %-25s | %s', [
      ModelCatalog[I].Id,
      ModelCatalog[I].Key,
      ModelCatalog[I].Name,
      ModelCatalog[I].Description
    ]));
  end;
  Writeln('================================================================================');
  Writeln('To download a catalog model, run:');
  Writeln('  localpal model download <ID or Key>');
  Writeln('  Example: localpal model download 8   (or: localpal model download smollm)');
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
