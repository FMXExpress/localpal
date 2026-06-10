unit localpal.CLI;

{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes;

type
  TCommandType = (
    cmdNone, cmdHelp, cmdVersion,
    cmdConfigShow, cmdConfigGet, cmdConfigSet,
    cmdModelList, cmdModelAdd, cmdModelUse, cmdModelRemove, cmdModelSearch, cmdModelDownload,
    cmdModelCatalog,
    cmdChatList, cmdChatNew, cmdChatShow, cmdChatSend, cmdChatDelete, cmdChatInteractive,
    cmdPalList, cmdPalAdd, cmdPalRemove, cmdPalUse, cmdPalExport, cmdPalImport,
    cmdBenchmark
  );

  TCLIOptions = record
    Command: TCommandType;
    Arg1: string;
    Arg2: string;
    Arg3: string;
    Arg4: string;
    DbPath: string;
  end;

procedure PrintHelp;
procedure PrintVersion;
function ParseCLI: TCLIOptions;

implementation

procedure PrintHelp;
begin
  Writeln('================================================================================');
  Writeln('             LOCALPAL CLI - Your Offline-First LLM Companion                    ');
  Writeln('================================================================================');
  Writeln('Usage: localpal [options] <command> [args]');
  Writeln;
  Writeln('Options:');
  Writeln('  --db <path>           Specify a custom SQLite database path.');
  Writeln('  -h, --help, help      Show this help menu.');
  Writeln('  -v, --version, version Show version information.');
  Writeln;
  Writeln('Configuration Commands:');
  Writeln('  config show           List all configuration variables.');
  Writeln('  config get <key>      Get a configuration value.');
  Writeln('  config set <key> <v>  Set a configuration value.');
  Writeln('                        Available keys: runner_url, system_prompt,');
  Writeln('                                        temperature, max_tokens, hf_token.');
  Writeln;
  Writeln('Model Inventory Commands:');
  Writeln('  model list            List registered models.');
  Writeln('  model catalog         List the catalog of built-in models available for download.');
  Writeln('  model add <name> <p>  Register a GGUF model path or Ollama model tag.');
  Writeln('  model use <name>      Set a model as the active/selected model.');
  Writeln('  model remove <name>   Remove a model from inventory.');
  Writeln('  model search <query>  Search GGUF model repos on Hugging Face.');
  Writeln('  model download <id|key> Download a model from the built-in catalog.');
  Writeln('  model download <r> <f> Download GGUF from custom Hugging Face repo <r> with filename <f>.');
  Writeln('                        (Set hf_token to download from gated repositories).');
  Writeln;
  Writeln('Pal (AI Companion) Commands:');
  Writeln('  pal list              List all registered AI Pals.');
  Writeln('  pal add <n> <r> <p> [m] Register a new Pal with name <n>, role <r>, system prompt <p>,');
  Writeln('                        and optional preferred model constraint [m].');
  Writeln('  pal remove <name>     Remove a Pal from database.');
  Writeln('  pal use <name> <id>   Assign a Pal to chat session <id>.');
  Writeln('  pal export <name> <f> Export a Pal to JSON file <f>.');
  Writeln('  pal import <f>        Import a Pal from JSON file <f>.');
  Writeln;
  Writeln('Chat Session Commands:');
  Writeln('  chat list             List all chat sessions.');
  Writeln('  chat new <name>       Create a new chat session.');
  Writeln('  chat show <id>        Show messages in chat session <id>.');
  Writeln('  chat delete <id>      Delete chat session <id>.');
  Writeln('  chat send <id> "<m>"  Send message "<m>" to session <id> and get response.');
  Writeln('  chat interactive <id> Start interactive chat loop with session <id>.');
  Writeln;
  Writeln('Benchmarking Commands:');
  Writeln('  benchmark [model]     Run standard prompt & token generation speed test on the');
  Writeln('                        active model or specified [model].');
  Writeln('================================================================================');
end;

procedure PrintVersion;
begin
  Writeln('localpal 0.1.0-dev (Delphi win/x86_64)');
end;

function ParseCLI: TCLIOptions;
var
  I: Integer;
  LArgs: TStringList;
begin
  Result.Command := cmdNone;
  Result.Arg1 := '';
  Result.Arg2 := '';
  Result.Arg3 := '';
  Result.Arg4 := '';
  Result.DbPath := '';

  LArgs := TStringList.Create;
  try
    // Pre-parse args to strip out --db
    I := 1;
    while I <= ParamCount do
    begin
      if SameText(ParamStr(I), '--db') then
      begin
        if I + 1 <= ParamCount then
        begin
          Result.DbPath := ParamStr(I + 1);
          Inc(I, 2);
        end
        else
        begin
          raise Exception.Create('Error: --db option requires a file path argument.');
        end;
      end
      else
      begin
        LArgs.Add(ParamStr(I));
        Inc(I);
      end;
    end;

    if LArgs.Count = 0 then
    begin
      Result.Command := cmdHelp;
      Exit;
    end;

    // First positional argument is the main command/subcommand
    var LFirst := LArgs[0];

    if SameText(LFirst, '-h') or SameText(LFirst, '--help') or SameText(LFirst, 'help') then
    begin
      Result.Command := cmdHelp;
      Exit;
    end;

    if SameText(LFirst, '-v') or SameText(LFirst, '--version') or SameText(LFirst, 'version') then
    begin
      Result.Command := cmdVersion;
      Exit;
    end;

    if SameText(LFirst, 'config') then
    begin
      if LArgs.Count < 2 then
      begin
        raise Exception.Create('Error: config subcommand requires an action (show, get, set).');
      end;

      var LAction := LArgs[1];
      if SameText(LAction, 'show') then
      begin
        Result.Command := cmdConfigShow;
      end
      else if SameText(LAction, 'get') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: config get requires a <key> argument.');
        Result.Command := cmdConfigGet;
        Result.Arg1 := LArgs[2];
      end
      else if SameText(LAction, 'set') then
      begin
        if LArgs.Count < 4 then
          raise Exception.Create('Error: config set requires a <key> and <value> argument.');
        Result.Command := cmdConfigSet;
        Result.Arg1 := LArgs[2];
        Result.Arg2 := LArgs[3];
      end
      else
      begin
        raise Exception.Create('Error: Unknown config action: ' + LAction);
      end;
    end
    else if SameText(LFirst, 'model') then
    begin
      if LArgs.Count < 2 then
      begin
        raise Exception.Create('Error: model subcommand requires an action (list, catalog, add, use, remove, search, download).');
      end;

      var LAction := LArgs[1];
      if SameText(LAction, 'list') then
      begin
        Result.Command := cmdModelList;
      end
      else if SameText(LAction, 'catalog') then
      begin
        Result.Command := cmdModelCatalog;
      end
      else if SameText(LAction, 'add') then
      begin
        if LArgs.Count < 4 then
          raise Exception.Create('Error: model add requires <name> and <path> arguments.');
        Result.Command := cmdModelAdd;
        Result.Arg1 := LArgs[2];
        Result.Arg2 := LArgs[3];
      end
      else if SameText(LAction, 'use') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: model use requires <name> argument.');
        Result.Command := cmdModelUse;
        Result.Arg1 := LArgs[2];
      end
      else if SameText(LAction, 'remove') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: model remove requires <name> argument.');
        Result.Command := cmdModelRemove;
        Result.Arg1 := LArgs[2];
      end
      else if SameText(LAction, 'search') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: model search requires a <query> argument.');
        Result.Command := cmdModelSearch;
        Result.Arg1 := LArgs[2];
      end
      else if SameText(LAction, 'download') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: model download requires <id|key> or <repository_id> <filename> arguments.');
        Result.Command := cmdModelDownload;
        Result.Arg1 := LArgs[2];
        if LArgs.Count >= 4 then
          Result.Arg2 := LArgs[3]
        else
          Result.Arg2 := '';
      end
      else
      begin
        raise Exception.Create('Error: Unknown model action: ' + LAction);
      end;
    end
    else if SameText(LFirst, 'pal') then
    begin
      if LArgs.Count < 2 then
      begin
        raise Exception.Create('Error: pal subcommand requires an action (list, add, remove, use, export, import).');
      end;

      var LAction := LArgs[1];
      if SameText(LAction, 'list') then
      begin
        Result.Command := cmdPalList;
      end
      else if SameText(LAction, 'add') then
      begin
        if LArgs.Count < 5 then
          raise Exception.Create('Error: pal add requires <name>, <role>, and <system_prompt> arguments.');
        Result.Command := cmdPalAdd;
        Result.Arg1 := LArgs[2];
        Result.Arg2 := LArgs[3];
        Result.Arg3 := LArgs[4];
        if LArgs.Count >= 6 then
          Result.Arg4 := LArgs[5];
      end
      else if SameText(LAction, 'remove') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: pal remove requires a <name> argument.');
        Result.Command := cmdPalRemove;
        Result.Arg1 := LArgs[2];
      end
      else if SameText(LAction, 'use') then
      begin
        if LArgs.Count < 4 then
          raise Exception.Create('Error: pal use requires <pal_name> and <chat_session_id> arguments.');
        Result.Command := cmdPalUse;
        Result.Arg1 := LArgs[2];
        Result.Arg2 := LArgs[3];
      end
      else if SameText(LAction, 'export') then
      begin
        if LArgs.Count < 4 then
          raise Exception.Create('Error: pal export requires <pal_name> and <filename> arguments.');
        Result.Command := cmdPalExport;
        Result.Arg1 := LArgs[2];
        Result.Arg2 := LArgs[3];
      end
      else if SameText(LAction, 'import') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: pal import requires a <filename> argument.');
        Result.Command := cmdPalImport;
        Result.Arg1 := LArgs[2];
      end
      else
      begin
        raise Exception.Create('Error: Unknown pal action: ' + LAction);
      end;
    end
    else if SameText(LFirst, 'chat') then
    begin
      if LArgs.Count < 2 then
      begin
        raise Exception.Create('Error: chat subcommand requires an action (list, new, show, delete, send, interactive).');
      end;

      var LAction := LArgs[1];
      if SameText(LAction, 'list') then
      begin
        Result.Command := cmdChatList;
      end
      else if SameText(LAction, 'new') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: chat new requires <name> argument.');
        Result.Command := cmdChatNew;
        Result.Arg1 := LArgs[2];
      end
      else if SameText(LAction, 'show') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: chat show requires <session_id> argument.');
        Result.Command := cmdChatShow;
        Result.Arg1 := LArgs[2];
      end
      else if SameText(LAction, 'delete') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: chat delete requires <session_id> argument.');
        Result.Command := cmdChatDelete;
        Result.Arg1 := LArgs[2];
      end
      else if SameText(LAction, 'send') then
      begin
        if LArgs.Count < 4 then
          raise Exception.Create('Error: chat send requires <session_id> and <message> arguments.');
        Result.Command := cmdChatSend;
        Result.Arg1 := LArgs[2];
        Result.Arg2 := LArgs[3];
      end
      else if SameText(LAction, 'interactive') then
      begin
        if LArgs.Count < 3 then
          raise Exception.Create('Error: chat interactive requires <session_id> argument.');
        Result.Command := cmdChatInteractive;
        Result.Arg1 := LArgs[2];
      end
      else
      begin
        raise Exception.Create('Error: Unknown chat action: ' + LAction);
      end;
    end
    else if SameText(LFirst, 'benchmark') then
    begin
      Result.Command := cmdBenchmark;
      if LArgs.Count >= 2 then
        Result.Arg1 := LArgs[1];
    end
    else
    begin
      raise Exception.Create('Error: Unknown command: ' + LFirst);
    end;

  finally
    LArgs.Free;
  end;
end;

end.
