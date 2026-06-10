unit localpal.App;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  localpal.CLI,
  localpal.Database,
  localpal.Config,
  localpal.Model,
  localpal.Chat,
  localpal.Pal,
  localpal.Benchmark;

type
  TApp = class
  private
    FDb: TDatabase;
    FConfig: TConfig;
    FModelMgr: TModelManager;
    FChatMgr: TChatManager;
    FPalMgr: TPalManager;
    FBenchmark: TBenchmark;
    FOpts: TCLIOptions;
    procedure InitDatabase;
  public
    constructor Create;
    destructor Destroy; override;
    function Run: Integer;
  end;

implementation

constructor TApp.Create;
begin
  inherited Create;
  FDb := nil;
  FConfig := nil;
  FModelMgr := nil;
  FChatMgr := nil;
  FPalMgr := nil;
  FBenchmark := nil;
end;

destructor TApp.Destroy;
begin
  FBenchmark.Free;
  FPalMgr.Free;
  FChatMgr.Free;
  FModelMgr.Free;
  FConfig.Free;
  FDb.Free;
  inherited Destroy;
end;

procedure TApp.InitDatabase;
var
  LDbPath: string;
begin
  if not FOpts.DbPath.IsEmpty then
    LDbPath := FOpts.DbPath
  else
    LDbPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'localpal.sqlite';

  FDb := TDatabase.Create(LDbPath);
  FConfig := TConfig.Create(FDb);
  FModelMgr := TModelManager.Create(FDb);
  FChatMgr := TChatManager.Create(FDb, FConfig, FModelMgr);
  FPalMgr := TPalManager.Create(FDb);
  FBenchmark := TBenchmark.Create(FDb, FConfig, FModelMgr);
end;

function TApp.Run: Integer;
begin
  Result := 0;
  try
    try
      FOpts := ParseCLI;
    except
      on E: Exception do
      begin
        Writeln(E.Message);
        Writeln;
        PrintHelp;
        Result := 1;
        Exit;
      end;
    end;

    // Handle commands that don't need database initialization first
    if FOpts.Command = cmdHelp then
    begin
      PrintHelp;
      Exit;
    end;

    if FOpts.Command = cmdVersion then
    begin
      PrintVersion;
      Exit;
    end;

    // Initialize Database & Dependencies
    try
      InitDatabase;
    except
      on E: Exception do
      begin
        Writeln('Error: Failed to initialize SQLite database. ' + E.Message);
        Result := 1;
        Exit;
      end;
    end;

    // Apply per-invocation chat overrides from --model / --pal flags
    FChatMgr.ModelOverride := FOpts.ModelOverride;
    FChatMgr.PalOverride := FOpts.PalOverride;

    // Dispatch Command
    try
      case FOpts.Command of
        cmdConfigShow:
          FConfig.ShowAll;
          
        cmdConfigGet:
          begin
            var LVal := FConfig.GetVal(FOpts.Arg1);
            if LVal.IsEmpty then
              Writeln(Format('Config key "%s" is not set or empty.', [FOpts.Arg1]))
            else
              Writeln(Format('%s = %s', [FOpts.Arg1, LVal]));
          end;
          
        cmdConfigSet:
          begin
            FConfig.SetVal(FOpts.Arg1, FOpts.Arg2);
            Writeln(Format('Updated config: %s = %s', [FOpts.Arg1, FOpts.Arg2]));
          end;
          
        cmdModelList:
          FModelMgr.ListModels;
          
        cmdModelCatalog:
          FModelMgr.ShowCatalog;
          
        cmdModelAdd:
          FModelMgr.AddModel(FOpts.Arg1, FOpts.Arg2);
          
        cmdModelUse:
          FModelMgr.UseModel(FOpts.Arg1);
          
        cmdModelRemove:
          FModelMgr.RemoveModel(FOpts.Arg1);
          
        cmdModelSearch:
          FModelMgr.SearchHuggingFace(FOpts.Arg1);
          
        cmdModelDownload:
          begin
            if FOpts.Arg2.IsEmpty then
            begin
              if not FModelMgr.DownloadCatalogItem(FOpts.Arg1) then
                Writeln(Format('Error: "%s" is not a valid catalog ID or Key. Run "localpal model catalog" to view options, or provide both <repo_id> and <filename>.', [FOpts.Arg1]));
            end
            else
            begin
              FModelMgr.DownloadModel(FOpts.Arg1, FOpts.Arg2);
            end;
          end;
          
        cmdPalList:
          FPalMgr.ListPals;
          
        cmdPalAdd:
          FPalMgr.AddPal(FOpts.Arg1, FOpts.Arg2, FOpts.Arg3, FOpts.Arg4);
          
        cmdPalRemove:
          FPalMgr.RemovePal(FOpts.Arg1);
          
        cmdPalUse:
          begin
            var LPalSession := FChatMgr.ResolveSession(FOpts.Arg2);
            if LPalSession > 0 then
              FPalMgr.UsePal(FOpts.Arg1, LPalSession)
            else
              Result := 1;
          end;
          
        cmdPalExport:
          FPalMgr.ExportPal(FOpts.Arg1, FOpts.Arg2);
          
        cmdPalImport:
          FPalMgr.ImportPal(FOpts.Arg1);
          
        cmdChatList:
          FChatMgr.ListSessions;

        cmdChatNew:
          begin
            var LNewSession := FChatMgr.CreateSession(FOpts.Arg1);
            FChatMgr.InteractiveChat(LNewSession);
          end;

        cmdChatShow:
          begin
            var LSession := FChatMgr.ResolveSession(FOpts.Arg1);
            if LSession > 0 then
              FChatMgr.ShowSession(LSession)
            else
              Result := 1;
          end;

        cmdChatDelete:
          begin
            var LSession := FChatMgr.ResolveSession(FOpts.Arg1);
            if LSession > 0 then
              FChatMgr.DeleteSession(LSession)
            else
              Result := 1;
          end;

        cmdChatSend:
          begin
            var LSession := FChatMgr.ResolveSession(FOpts.Arg1);
            if LSession > 0 then
              FChatMgr.SendMessage(LSession, FOpts.Arg2)
            else
              Result := 1;
          end;

        cmdChatInteractive:
          begin
            var LSession := FChatMgr.ResolveSession(FOpts.Arg1);
            if LSession > 0 then
              FChatMgr.InteractiveChat(LSession)
            else
              Result := 1;
          end;

        cmdChatQuick:
          FChatMgr.QuickChat;

        cmdChatAsk:
          FChatMgr.QuickAsk(FOpts.Arg1);

        cmdBenchmark:
          begin
            if FOpts.Arg1.IsEmpty then
              FBenchmark.RunBenchmark(FOpts.ModelOverride)
            else
              FBenchmark.RunBenchmark(FOpts.Arg1);
          end;
          
        else
          begin
            PrintHelp;
            Result := 1;
          end;
      end;
    except
      on E: Exception do
      begin
        Writeln('Error executing command: ' + E.Message);
        Result := 1;
      end;
    end;

  except
    on E: Exception do
    begin
      Writeln('Fatal Error: ' + E.Message);
      Result := 1;
    end;
  end;
end;

end.
