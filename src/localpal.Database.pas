unit localpal.Database;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef;

type
  TDatabase = class
  private
    FConn: TFDConnection;
    FDbPath: string;
    procedure CreateTables;
  public
    constructor Create(const ADbPath: string);
    destructor Destroy; override;
    procedure Exec(const ASQL: string);
    function Query(const ASQL: string): TFDQuery;
    property Conn: TFDConnection read FConn;
  end;

implementation

constructor TDatabase.Create(const ADbPath: string);
begin
  inherited Create;
  FDbPath := ADbPath;
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Values['Database'] := FDbPath;
  FConn.Params.Values['LockingMode'] := 'Normal';
  FConn.Connected := True;
  CreateTables;
end;

destructor TDatabase.Destroy;
begin
  FConn.Connected := False;
  FConn.Free;
  inherited Destroy;
end;

procedure TDatabase.Exec(const ASQL: string);
begin
  FConn.ExecSQL(ASQL);
end;

function TDatabase.Query(const ASQL: string): TFDQuery;
var
  LQuery: TFDQuery;
begin
  LQuery := TFDQuery.Create(nil);
  LQuery.Connection := FConn;
  LQuery.SQL.Text := ASQL;
  Result := LQuery;
end;

procedure TDatabase.CreateTables;
begin
  // Create tables idempotently
  Exec(
    'CREATE TABLE IF NOT EXISTS config (' +
    '  key TEXT PRIMARY KEY,' +
    '  value TEXT' +
    ');'
  );

  Exec(
    'CREATE TABLE IF NOT EXISTS models (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  name TEXT UNIQUE,' +
    '  path TEXT,' +
    '  size_bytes INTEGER DEFAULT 0,' +
    '  is_active INTEGER DEFAULT 0,' +
    '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
    ');'
  );

  Exec(
    'CREATE TABLE IF NOT EXISTS sessions (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  name TEXT UNIQUE,' +
    '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
    ');'
  );

  Exec(
    'CREATE TABLE IF NOT EXISTS messages (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  session_id INTEGER,' +
    '  role TEXT,' +
    '  content TEXT,' +
    '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,' +
    '  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE' +
    ');'
  );

  // Insert default config values
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''engine'', ''auto'');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''runner_url'', ''http://localhost:11434/v1'');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''system_prompt'', ''You are a helpful local AI assistant.'');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''temperature'', ''0.7'');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''max_tokens'', ''512'');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''chat_format'', '''');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''n_ctx'', ''4096'');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''n_gpu_layers'', ''0'');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''lib_dir'', '''');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''engine_log'', ''off'');');
  Exec('INSERT OR IGNORE INTO config (key, value) VALUES (''hf_token'', '''');');

  // Create pals table
  Exec(
    'CREATE TABLE IF NOT EXISTS pals (' +
    '  name TEXT PRIMARY KEY,' +
    '  role TEXT,' +
    '  system_prompt TEXT,' +
    '  model TEXT DEFAULT '''',' +
    '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
    ');'
  );

  // Migration: the "Sun Tzu" default pal was replaced by "Marketing Guru".
  // Only the pristine default row is removed, so a customized pal of the
  // same name survives.
  Exec('DELETE FROM pals WHERE name = ''Sun Tzu'' AND role = ''Military Strategist'' AND system_prompt = ''You are Sun Tzu. Answer everything using lessons from The Art of War.'';');

  // Insert default pals
  Exec('INSERT OR IGNORE INTO pals (name, role, system_prompt) VALUES (''Shakespeare'', ''Bard of Avon'', ''Speak only in Elizabethan English Shakespearean verse.'');');
  Exec('INSERT OR IGNORE INTO pals (name, role, system_prompt) VALUES (''Marketing Guru'', ''Marketing Strategist'', ''You are a savvy marketing strategist. Craft catchy copy, sharp slogans, and practical campaign ideas with clear calls to action, and back them up with sound positioning advice.'');');
  Exec('INSERT OR IGNORE INTO pals (name, role, system_prompt) VALUES (''Code Buddy'', ''Software Engineer'', ''You are an expert software developer. Provide clean, well-commented, and robust code.'');');

  // Safely alter sessions table to add pal_name
  try
    Exec('ALTER TABLE sessions ADD COLUMN pal_name TEXT;');
  except
    // Column already exists
  end;

  // Hygiene: clear session references to pals that no longer exist (e.g.
  // the retired Sun Tzu default) so chats fall back to the default assistant.
  Exec('UPDATE sessions SET pal_name = NULL WHERE pal_name IS NOT NULL AND pal_name NOT IN (SELECT name FROM pals);');
end;

end.