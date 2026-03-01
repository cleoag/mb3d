unit HeadlessRender;

{$mode delphi}

{ Headless CLI rendering for MB3D (FPC-only).
  Usage: Mandelbulb3D.exe --render input.m3p --output result.png [options]
  Forms are created in memory (controls hold valid values from LoadParameter/SetEditsFromHeader)
  but Application.ShowMainForm := False keeps them invisible. The timer-driven pipeline
  (Timer4Timer -> Timer8Timer) runs via Application.Run and HeadlessOnRenderComplete
  saves output + calls Halt(0). }

interface

uses Graphics;

var
  HeadlessMode: Boolean;
  HeadlessInputFile: String;
  HeadlessOutputFile: String;
  HeadlessFormat: Integer;    // 0=PNG(default), 1=JPG, 2=BMP
  HeadlessWidth: Integer;     // 0 = use .m3p value
  HeadlessHeight: Integer;    // 0 = use .m3p value
  HeadlessThreads: Integer;   // 0 = use default

procedure HeadlessParseArgs;
procedure HeadlessStart;
procedure HeadlessOnRenderComplete(bmp: TBitmap);
procedure HeadlessLog(const S: String);

implementation

uses
  Windows, SysUtils, Forms,
  FileHandling;

procedure EnsureConsole;
const
  ATTACH_PARENT_PROCESS = DWORD(-1);
begin
  { Try to attach to parent process console (e.g., cmd.exe).
    If that fails (no parent console), allocate a new one. }
  if not AttachConsole(ATTACH_PARENT_PROCESS) then
    AllocConsole;
  { Tell FPC RTL this is now a console app, then reinitialize
    Input/Output/ErrOutput from the new Windows std handles. }
  IsConsole := True;
  SysInitStdIO;
end;

function FormatFromExtension(const FileName: String): Integer;
var Ext: String;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  if Ext = '.jpg' then Result := 1
  else if Ext = '.jpeg' then Result := 1
  else if Ext = '.bmp' then Result := 2
  else Result := 0; // default PNG
end;

procedure HeadlessLog(const S: String);
begin
  WriteLn('[MB3D] ' + S);
end;

function HasHeadlessArgs: Boolean;
var I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if (ParamStr(I) = '--render') or (ParamStr(I) = '--help') then
    begin
      Result := True;
      Exit;
    end;
end;

procedure HeadlessParseArgs;
var
  I: Integer;
  Arg, Val: String;
  HasRender, HasOutput: Boolean;
begin
  HeadlessMode := False;
  HeadlessInputFile := '';
  HeadlessOutputFile := '';
  HeadlessFormat := -1;  // -1 = auto-detect from extension
  HeadlessWidth := 0;
  HeadlessHeight := 0;
  HeadlessThreads := 0;
  HasRender := False;
  HasOutput := False;

  { Only allocate a console if headless args are present.
    This avoids flashing a console window for normal GUI launches. }
  if HasHeadlessArgs then
    EnsureConsole;

  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);

    if (Arg = '--render') and (I < ParamCount) then
    begin
      Inc(I);
      HeadlessInputFile := ParamStr(I);
      HasRender := True;
    end
    else if (Arg = '--output') and (I < ParamCount) then
    begin
      Inc(I);
      HeadlessOutputFile := ParamStr(I);
      HasOutput := True;
    end
    else if (Arg = '--format') and (I < ParamCount) then
    begin
      Inc(I);
      Val := LowerCase(ParamStr(I));
      if Val = 'png' then HeadlessFormat := 0
      else if Val = 'jpg' then HeadlessFormat := 1
      else if Val = 'jpeg' then HeadlessFormat := 1
      else if Val = 'bmp' then HeadlessFormat := 2
      else begin
        WriteLn(StdErr, 'Error: unknown format "' + ParamStr(I) + '". Use png, jpg, or bmp.');
        Halt(1);
      end;
    end
    else if (Arg = '--width') and (I < ParamCount) then
    begin
      Inc(I);
      HeadlessWidth := StrToIntDef(ParamStr(I), 0);
      if HeadlessWidth <= 0 then
      begin
        WriteLn(StdErr, 'Error: invalid width "' + ParamStr(I) + '"');
        Halt(1);
      end;
    end
    else if (Arg = '--height') and (I < ParamCount) then
    begin
      Inc(I);
      HeadlessHeight := StrToIntDef(ParamStr(I), 0);
      if HeadlessHeight <= 0 then
      begin
        WriteLn(StdErr, 'Error: invalid height "' + ParamStr(I) + '"');
        Halt(1);
      end;
    end
    else if (Arg = '--threads') and (I < ParamCount) then
    begin
      Inc(I);
      HeadlessThreads := StrToIntDef(ParamStr(I), 0);
      if HeadlessThreads <= 0 then
      begin
        WriteLn(StdErr, 'Error: invalid thread count "' + ParamStr(I) + '"');
        Halt(1);
      end;
    end
    else if Arg = '--help' then
    begin
      WriteLn('Mandelbulb 3D - Headless Rendering');
      WriteLn('Usage: Mandelbulb3D.exe --render input.m3p --output result.png [options]');
      WriteLn('');
      WriteLn('Options:');
      WriteLn('  --render FILE    Input .m3p parameter file (required)');
      WriteLn('  --output FILE    Output image path (required)');
      WriteLn('  --format FMT     Output format: png (default), jpg, bmp');
      WriteLn('  --width N        Override image width');
      WriteLn('  --height N       Override image height');
      WriteLn('  --threads N      Number of render threads');
      WriteLn('  --help           Show this help');
      Halt(0);
    end;

    Inc(I);
  end;

  if not HasRender then
    Exit;  // not headless mode -- normal GUI launch

  if not HasOutput then
  begin
    WriteLn(StdErr, 'Error: --render requires --output');
    Halt(1);
  end;

  if not FileExists(HeadlessInputFile) then
  begin
    WriteLn(StdErr, 'Error: input file not found: ' + HeadlessInputFile);
    Halt(1);
  end;

  // Auto-detect format from extension if not explicitly set
  if HeadlessFormat < 0 then
    HeadlessFormat := FormatFromExtension(HeadlessOutputFile);

  HeadlessMode := True;
  HeadlessLog('Headless render mode');
  HeadlessLog('  Input:   ' + HeadlessInputFile);
  HeadlessLog('  Output:  ' + HeadlessOutputFile);
  case HeadlessFormat of
    0: HeadlessLog('  Format:  PNG');
    1: HeadlessLog('  Format:  JPG');
    2: HeadlessLog('  Format:  BMP');
  end;
  if HeadlessWidth > 0 then
    HeadlessLog('  Width:   ' + IntToStr(HeadlessWidth));
  if HeadlessHeight > 0 then
    HeadlessLog('  Height:  ' + IntToStr(HeadlessHeight));
  if HeadlessThreads > 0 then
    HeadlessLog('  Threads: ' + IntToStr(HeadlessThreads));
end;

procedure HeadlessStart;
begin
  { HeadlessStart is called from TMand3DForm.LoadStartupParas in Mand.pas.
    The actual load/render logic is in LoadStartupParas because it needs
    access to form-internal members (bUserChange, Edit controls).
    This procedure is kept as a hook point — Mand.pas calls it to
    signal the start, then does the work itself. }
  HeadlessLog('Headless render starting...');
end;

procedure HeadlessOnRenderComplete(bmp: Graphics.TBitmap);
var OutputDir: String;
begin
  HeadlessLog('Render complete. Saving output...');

  { Ensure output directory exists }
  OutputDir := ExtractFilePath(ExpandFileName(HeadlessOutputFile));
  if (OutputDir <> '') and not DirectoryExists(OutputDir) then
    ForceDirectories(OutputDir);

  { bmp is Image1.Picture.Bitmap, already AA-downscaled by the
    caller (SdoAA in Mand.pas before calling us). Save it. }
  case HeadlessFormat of
    0: SavePNG(HeadlessOutputFile, bmp, False);
    1: SaveJPEGfromBMP(HeadlessOutputFile, bmp, 95);
    2: SaveBMP(HeadlessOutputFile, bmp, Graphics.pf24bit);
  end;

  HeadlessLog('Saved: ' + HeadlessOutputFile);
  HeadlessLog('Done.');
  Halt(0);
end;

end.
