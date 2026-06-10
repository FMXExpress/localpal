unit localpal.Pal;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  localpal.Database;

type
  TPalInfo = record
    Name: string;
    Role: string;
    SystemPrompt: string;
    Model: string;
    CreatedAt: string;
  end;

  TPalManager = class
  private
    FDb: TDatabase;
  public
    constructor Create(ADb: TDatabase);
    procedure ListPals;
    procedure AddPal(const AName, ARole, ASystemPrompt: string; const AModel: string = '');
    procedure RemovePal(const AName: string);
    procedure UsePal(const AName: string; ASessionId: Integer);
    procedure ExportPal(const AName, AFilename: string);
    procedure ImportPal(const AFilename: string);
    function GetPal(const AName: string; var APal: TPalInfo): Boolean;
  end;

implementation

constructor TPalManager.Create(ADb: TDatabase);
begin
  inherited Create;
  FDb := ADb;
end;

procedure TPalManager.ListPals;
var
  LQuery: TFDQuery;
  LCount: Integer;
begin
  LQuery := FDb.Query('SELECT name, role, system_prompt, model, created_at FROM pals ORDER BY name');
  try
    LQuery.Open;
    Writeln('================================================================================');
    Writeln('                               REGISTERED PALS (AI ASSISTANTS)                  ');
    Writeln('================================================================================');
    Writeln(Format('  %-15s | %-20s | %-12s | %s', ['Pal Name', 'Role', 'Model Limit', 'System Prompt']));
    Writeln('--------------------------------------------------------------------------------');
    LCount := 0;
    while not LQuery.Eof do
    begin
      Inc(LCount);
      var LModelLimit := LQuery.FieldByName('model').AsString;
      if LModelLimit.IsEmpty then
        LModelLimit := '(Any Model)';

      var LPrompt := LQuery.FieldByName('system_prompt').AsString;
      if LPrompt.Length > 40 then
        LPrompt := LPrompt.Substring(0, 37) + '...';

      Writeln(Format('  %-15s | %-20s | %-12s | %s', [
        LQuery.FieldByName('name').AsString,
        LQuery.FieldByName('role').AsString,
        LModelLimit,
        LPrompt
      ]));
      LQuery.Next;
    end;
    if LCount = 0 then
      Writeln('  No Pals found. Use "pal add" to register a new custom companion!');
    Writeln('================================================================================');
  finally
    LQuery.Free;
  end;
end;

procedure TPalManager.AddPal(const AName, ARole, ASystemPrompt: string; const AModel: string = '');
var
  LQuery: TFDQuery;
begin
  if AName.IsEmpty then
    raise Exception.Create('Error: Pal name cannot be empty.');
  if ARole.IsEmpty then
    raise Exception.Create('Error: Pal role cannot be empty.');
  if ASystemPrompt.IsEmpty then
    raise Exception.Create('Error: Pal system prompt cannot be empty.');

  LQuery := FDb.Query('INSERT OR REPLACE INTO pals (name, role, system_prompt, model) VALUES (:name, :role, :system_prompt, :model)');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.ParamByName('role').AsString := ARole;
    LQuery.ParamByName('system_prompt').AsString := ASystemPrompt;
    LQuery.ParamByName('model').AsString := AModel;
    LQuery.ExecSQL;
    Writeln(Format('Successfully registered Pal "%s" (%s)!', [AName, ARole]));
  finally
    LQuery.Free;
  end;
end;

procedure TPalManager.RemovePal(const AName: string);
var
  LQuery: TFDQuery;
begin
  // Check if it's one of the default pals
  if SameText(AName, 'Shakespeare') or SameText(AName, 'Sun Tzu') or SameText(AName, 'Code Buddy') then
    Writeln('Warning: You are removing a default Pal.');

  LQuery := FDb.Query('DELETE FROM pals WHERE name = :name');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.ExecSQL;
    Writeln(Format('Pal "%s" has been removed from your local database.', [AName]));
  finally
    LQuery.Free;
  end;
end;

procedure TPalManager.UsePal(const AName: string; ASessionId: Integer);
var
  LQuery: TFDQuery;
  LPal: TPalInfo;
begin
  if not GetPal(AName, LPal) then
  begin
    Writeln(Format('Error: Pal "%s" is not registered. Register it first using "pal add".', [AName]));
    Exit;
  end;

  // Check if session exists
  LQuery := FDb.Query('SELECT name FROM sessions WHERE id = :id');
  try
    LQuery.ParamByName('id').AsInteger := ASessionId;
    LQuery.Open;
    if LQuery.IsEmpty then
    begin
      Writeln(Format('Error: Chat session ID %d does not exist.', [ASessionId]));
      Exit;
    end;
  finally
    LQuery.Free;
  end;

  // Associate pal
  LQuery := FDb.Query('UPDATE sessions SET pal_name = :pal_name WHERE id = :id');
  try
    LQuery.ParamByName('pal_name').AsString := AName;
    LQuery.ParamByName('id').AsInteger := ASessionId;
    LQuery.ExecSQL;
    Writeln(Format('Chat session ID %d is now hosted by Pal "%s" (%s)!', [ASessionId, AName, LPal.Role]));
    if not LPal.Model.IsEmpty then
      Writeln(Format('Note: This Pal prefers to run on the "%s" model.', [LPal.Model]));
  finally
    LQuery.Free;
  end;
end;

procedure TPalManager.ExportPal(const AName, AFilename: string);
var
  LPal: TPalInfo;
  LJSON: TJSONObject;
  LFileStream: TStringList;
begin
  if not GetPal(AName, LPal) then
  begin
    Writeln(Format('Error: Pal "%s" does not exist.', [AName]));
    Exit;
  end;

  LJSON := TJSONObject.Create;
  try
    LJSON.AddPair('name', LPal.Name);
    LJSON.AddPair('role', LPal.Role);
    LJSON.AddPair('system_prompt', LPal.SystemPrompt);
    LJSON.AddPair('model', LPal.Model);

    LFileStream := TStringList.Create;
    try
      LFileStream.Text := LJSON.Format(2);
      LFileStream.SaveToFile(AFilename);
      Writeln(Format('Successfully exported Pal "%s" to "%s"!', [AName, AFilename]));
    finally
      LFileStream.Free;
    end;
  finally
    LJSON.Free;
  end;
end;

procedure TPalManager.ImportPal(const AFilename: string);
var
  LFileStream: TStringList;
  LJSON: TJSONObject;
  LName, LRole, LPrompt, LModel: string;
begin
  if not FileExists(AFilename) then
  begin
    Writeln(Format('Error: File "%s" does not exist.', [AFilename]));
    Exit;
  end;

  LFileStream := TStringList.Create;
  try
    LFileStream.LoadFromFile(AFilename);
    LJSON := TJSONObject.ParseJSONValue(LFileStream.Text) as TJSONObject;
    if not Assigned(LJSON) then
    begin
      Writeln('Error: Failed to parse Pal export file as JSON.');
      Exit;
    end;

    try
      if not Assigned(LJSON.GetValue('name')) or not Assigned(LJSON.GetValue('role')) or not Assigned(LJSON.GetValue('system_prompt')) then
      begin
        Writeln('Error: Invalid Pal JSON structure. "name", "role", and "system_prompt" are required.');
        Exit;
      end;

      LName := LJSON.GetValue('name').Value;
      LRole := LJSON.GetValue('role').Value;
      LPrompt := LJSON.GetValue('system_prompt').Value;
      LModel := '';
      if Assigned(LJSON.GetValue('model')) then
        LModel := LJSON.GetValue('model').Value;

      AddPal(LName, LRole, LPrompt, LModel);
    finally
      LJSON.Free;
    end;
  finally
    LFileStream.Free;
  end;
end;

function TPalManager.GetPal(const AName: string; var APal: TPalInfo): Boolean;
var
  LQuery: TFDQuery;
begin
  Result := False;
  LQuery := FDb.Query('SELECT name, role, system_prompt, model, created_at FROM pals WHERE name = :name COLLATE NOCASE LIMIT 1');
  try
    LQuery.ParamByName('name').AsString := AName;
    LQuery.Open;
    if not LQuery.IsEmpty then
    begin
      APal.Name := LQuery.FieldByName('name').AsString;
      APal.Role := LQuery.FieldByName('role').AsString;
      APal.SystemPrompt := LQuery.FieldByName('system_prompt').AsString;
      APal.Model := LQuery.FieldByName('model').AsString;
      APal.CreatedAt := LQuery.FieldByName('created_at').AsString;
      Result := True;
    end;
  finally
    LQuery.Free;
  end;
end;

end.