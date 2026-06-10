unit localpal.Config;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  localpal.Database;

type
  TConfig = class
  private
    FDb: TDatabase;
  public
    constructor Create(ADb: TDatabase);
    function GetVal(const AKey: string; const ADefault: string = ''): string;
    procedure SetVal(const AKey, AValue: string);
    procedure ShowAll;
  end;

implementation

constructor TConfig.Create(ADb: TDatabase);
begin
  inherited Create;
  FDb := ADb;
end;

function TConfig.GetVal(const AKey: string; const ADefault: string = ''): string;
var
  LQuery: TFDQuery;
begin
  Result := ADefault;
  LQuery := FDb.Query('SELECT value FROM config WHERE key = :key');
  try
    LQuery.ParamByName('key').AsString := AKey;
    LQuery.Open;
    if not LQuery.IsEmpty then
      Result := LQuery.FieldByName('value').AsString;
  finally
    LQuery.Free;
  end;
end;

procedure TConfig.SetVal(const AKey, AValue: string);
var
  LQuery: TFDQuery;
begin
  LQuery := FDb.Query('INSERT OR REPLACE INTO config (key, value) VALUES (:key, :value)');
  try
    LQuery.ParamByName('key').AsString := AKey;
    LQuery.ParamByName('value').AsString := AValue;
    LQuery.ExecSQL;
  finally
    LQuery.Free;
  end;
end;

procedure TConfig.ShowAll;
var
  LQuery: TFDQuery;
begin
  LQuery := FDb.Query('SELECT key, value FROM config ORDER BY key');
  try
    LQuery.Open;
    Writeln('========================================');
    Writeln('         LOCALPAL CONFIGURATION         ');
    Writeln('========================================');
    while not LQuery.Eof do
    begin
      Writeln(Format('  %-20s : %s', [
        LQuery.FieldByName('key').AsString,
        LQuery.FieldByName('value').AsString
      ]));
      LQuery.Next;
    end;
    Writeln('========================================');
  finally
    LQuery.Free;
  end;
end;

end.
