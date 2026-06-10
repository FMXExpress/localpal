program localpal;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  localpal.App in 'src\localpal.App.pas',
  localpal.CLI in 'src\localpal.CLI.pas',
  localpal.Database in 'src\localpal.Database.pas',
  localpal.Config in 'src\localpal.Config.pas',
  localpal.Model in 'src\localpal.Model.pas',
  localpal.Engine in 'src\localpal.Engine.pas',
  localpal.Chat in 'src\localpal.Chat.pas',
  localpal.Pal in 'src\localpal.Pal.pas',
  localpal.Benchmark in 'src\localpal.Benchmark.pas';

var
  LApp: TApp;
  LExitCode: Integer;
begin
{$IFDEF MSWINDOWS}
  // Model output is Unicode; render it as UTF-8 instead of the OEM codepage.
  SetConsoleOutputCP(CP_UTF8);
{$ENDIF}
  try
    LApp := TApp.Create;
    try
      LExitCode := LApp.Run;
    finally
      LApp.Free;
    end;
    ExitCode := LExitCode;
  except
    on E: Exception do
    begin
      Writeln('Unhandled Exception: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.