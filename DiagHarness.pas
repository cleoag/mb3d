unit DiagHarness;

{$mode delphi}

{ FPC Rendering Pipeline Diagnostic Harness
  ==========================================
  Activated by -dFPC_DIAG compiler define.
  Provides automated rendering + parameter logging for pixel-level
  comparison between FPC and Delphi builds.

  Usage: Launch MB3D with command line:
    Mandelbulb3D.exe --diag [scene.m3p]

  If no scene specified, renders the default scene.
  Output goes to diag_output/ directory next to the executable.
}

interface

uses SysUtils, Classes, TypeDefinitions;

{ Call from LoadStartupParas to check for --diag mode }
procedure DiagCheckStartup;

{ Call from Timer4Timer when all processing completes (c=0, no more steps) }
procedure DiagOnRenderComplete;

{ Dump MCTparas to file }
procedure DiagLogMCTparasRecord(const MCT: TMCTparameter; const SceneName: String);

{ Log a post-processing step }
procedure DiagLogPostProc(const StepName: String; StepCode: Integer);

{ Sample siLight5 buffer at key points }
procedure DiagLogSiLight5Sample(pSiLight: Pointer; Width, Height: Integer; const SceneName: String);

{ Record render start time }
procedure DiagSetRenderStartTick;

{ Save fullSizeImage buffer directly as 24-bit BMP }
procedure DiagSaveFullSizeImageBMP(const FilePath: String; pData: Pointer; Width, Height, Stride: Integer);

{ General log message }
procedure DiagLog(const S: String);

{ Check if diagnostic mode is active }
function DiagIsActive: Boolean;

{ Get the current scene file being tested }
function DiagCurrentScene: String;

var
  DiagOutputDir: String = '';

implementation

uses Windows, Graphics, Forms, Types, DiagASMCheck;

var
  gDiagActive: Boolean = False;
  gDiagScene: String = '';
  gDiagLogFile: TextFile;
  gDiagLogOpen: Boolean = False;
  gDiagStartTick: Cardinal = 0;
  gDiagRenderStartTick: Cardinal = 0;

procedure DiagOpenLog;
var LogPath: String;
begin
  if gDiagLogOpen then Exit;
  try
    LogPath := DiagOutputDir + 'diag_log.txt';
    AssignFile(gDiagLogFile, LogPath);
    if FileExists(LogPath) then
      Append(gDiagLogFile)
    else
      Rewrite(gDiagLogFile);
    gDiagLogOpen := True;
  except
    gDiagLogOpen := False;
  end;
end;

procedure DiagLog(const S: String);
begin
  if not gDiagLogOpen then DiagOpenLog;
  WriteLn(gDiagLogFile, Format('[%8d] %s', [GetTickCount - gDiagStartTick, S]));
  Flush(gDiagLogFile);
end;

procedure DiagCloseLog;
begin
  if gDiagLogOpen then
  begin
    CloseFile(gDiagLogFile);
    gDiagLogOpen := False;
  end;
end;

function DiagIsActive: Boolean;
begin
  Result := gDiagActive;
end;

function DiagCurrentScene: String;
begin
  Result := gDiagScene;
end;

procedure DiagCheckStartup;
var
  i: Integer;
  AppDir: String;
begin
  gDiagActive := False;

  for i := 1 to ParamCount do
  begin
    if LowerCase(ParamStr(i)) = '--diag' then
    begin
      gDiagActive := True;
      if (i < ParamCount) and (Copy(ParamStr(i + 1), 1, 1) <> '-') then
        gDiagScene := ParamStr(i + 1)
      else
        gDiagScene := '';
      Break;
    end;
  end;

  if not gDiagActive then Exit;

  AppDir := ExtractFilePath(Application.ExeName);
  DiagOutputDir := AppDir + 'diag_output' + PathDelim;
  if not DirectoryExists(DiagOutputDir) then
    ForceDirectories(DiagOutputDir);

  gDiagStartTick := GetTickCount;
  DiagOpenLog;
  DiagLog('=== FPC Diagnostic Harness Started ===');
  {$IFDEF FPC}
  DiagLog('FPC Version: ' + {$I %FPCVERSION%});
  DiagLog('Target: ' + {$I %FPCTARGET%} + '-' + {$I %FPCTARGETOS%});
  {$ELSE}
  DiagLog('Compiler: Delphi');
  {$ENDIF}
  DiagLog('Output dir: ' + DiagOutputDir);

  if gDiagScene <> '' then
    DiagLog('Single scene mode: ' + gDiagScene)
  else
    DiagLog('Default scene mode');

  // Run ASM spot-checks before rendering
  DiagLog('Running ASM spot-checks...');
  DiagASMCheck.RunASMSpotChecks(DiagOutputDir);
  DiagLog('ASM spot-checks complete.');
end;

procedure DiagSetRenderStartTick;
begin
  gDiagRenderStartTick := GetTickCount;
end;

procedure DiagLogMCTparasRecord(const MCT: TMCTparameter; const SceneName: String);
var
  F: TextFile;
  FPath: String;
  i: Integer;
  SafeName: String;
begin
  if not gDiagActive then Exit;

  SafeName := StringReplace(SceneName, ' ', '_', [rfReplaceAll]);
  SafeName := StringReplace(SafeName, '.m3p', '', [rfReplaceAll, rfIgnoreCase]);
  if SafeName = '' then SafeName := 'default';
  FPath := DiagOutputDir + 'mctparas_' + SafeName + '.txt';

  AssignFile(F, FPath);
  Rewrite(F);
  try
    WriteLn(F, '=== MCTparas dump for: ' + SceneName + ' ===');
    WriteLn(F, '');
    WriteLn(F, '--- Core iteration parameters ---');
    WriteLn(F, 'iMaxIt        = ', MCT.iMaxIt);
    WriteLn(F, 'iMinIt        = ', MCT.iMinIt);
    WriteLn(F, 'iMaxitF2      = ', MCT.iMaxitF2);
    WriteLn(F, 'msDEstop      = ', MCT.msDEstop:12:8);
    WriteLn(F, 'DEstop        = ', MCT.DEstop:12:8);
    WriteLn(F, 'sZstepDiv     = ', MCT.sZstepDiv:12:8);
    WriteLn(F, 'iDEAddSteps   = ', MCT.iDEAddSteps);
    WriteLn(F, 'dRstop        = ', MCT.dRstop:12:8);
    WriteLn(F, 'Rstop3D       = ', MCT.Rstop3D:12:8);

    WriteLn(F, '');
    WriteLn(F, '--- View parameters ---');
    WriteLn(F, 'FOVy          = ', MCT.FOVy:12:8);
    WriteLn(F, 'iMandWidth    = ', MCT.iMandWidth);
    WriteLn(F, 'iMandHeight   = ', MCT.iMandHeight);
    WriteLn(F, 'FOVXoff       = ', MCT.FOVXoff:12:8);
    WriteLn(F, 'FOVXmul       = ', MCT.FOVXmul:12:8);
    WriteLn(F, 'MCTCameraOptic= ', MCT.MCTCameraOptic);
    WriteLn(F, 'mctPlOpticZ   = ', MCT.mctPlOpticZ:12:8);

    WriteLn(F, '');
    WriteLn(F, '--- Formula ---');
    WriteLn(F, 'calc3D        = ', MCT.calc3D);
    WriteLn(F, 'bMCTisValid   = ', MCT.bMCTisValid);
    WriteLn(F, 'dDEscale      = ', MCT.dDEscale:12:8);
    WriteLn(F, 'dDEscale2     = ', MCT.dDEscale2:12:8);
    WriteLn(F, 'DEoption      = ', MCT.DEoption);
    WriteLn(F, 'DEoption2     = ', MCT.DEoption2);
    WriteLn(F, 'FormulaType   = ', MCT.FormulaType);
    WriteLn(F, 'IsCustomDE    = ', MCT.IsCustomDE);
    WriteLn(F, 'IsCustomDE2   = ', MCT.IsCustomDE2);
    WriteLn(F, 'bDoJulia      = ', MCT.bDoJulia);
    WriteLn(F, 'iCutOptions   = ', MCT.iCutOptions);
    WriteLn(F, 'bInsideRendering = ', MCT.bInsideRendering);
    WriteLn(F, 'bCalcInside   = ', MCT.bCalcInside);
    WriteLn(F, 'bInAndOutside = ', MCT.bInAndOutside);

    WriteLn(F, '');
    WriteLn(F, '--- Coloring ---');
    WriteLn(F, 'ColorOption   = ', MCT.ColorOption);
    WriteLn(F, 'ColorOnIt     = ', MCT.ColorOnIt);
    WriteLn(F, 'DEmixCol      = ', MCT.DEmixCol);
    WriteLn(F, 'FmixPow       = ', MCT.FmixPow:12:8);
    WriteLn(F, 'dColPlus      = ', MCT.dColPlus:12:8);

    WriteLn(F, '');
    WriteLn(F, '--- Rendering ---');
    WriteLn(F, 'iSmNormals    = ', MCT.iSmNormals);
    WriteLn(F, 'StepWidth     = ', MCT.StepWidth:16:12);
    WriteLn(F, 'Zend          = ', MCT.Zend:16:12);
    WriteLn(F, 'calcHardShadow= ', MCT.calcHardShadow);
    WriteLn(F, 'bCalcAmbShadow= ', MCT.bCalcAmbShadow);
    WriteLn(F, 'bVaryDEstop   = ', MCT.bVaryDEstop);
    WriteLn(F, 'DEAOmaxL      = ', MCT.DEAOmaxL:12:8);
    WriteLn(F, 'SoftShadowRadius = ', MCT.SoftShadowRadius:12:8);
    WriteLn(F, 'sHSmaxLengthMultiplier = ', MCT.sHSmaxLengthMultiplier:12:8);

    WriteLn(F, '');
    WriteLn(F, '--- Hybrid ---');
    WriteLn(F, 'wEndTo        = ', MCT.wEndTo);
    WriteLn(F, 'RepeatFrom1   = ', MCT.RepeatFrom1);
    WriteLn(F, 'StartFrom2    = ', MCT.StartFrom2);
    WriteLn(F, 'RepeatFrom2   = ', MCT.RepeatFrom2);
    WriteLn(F, 'iEnd2         = ', MCT.iEnd2);
    for i := 0 to 5 do
      WriteLn(F, '  nHybrid[', i, '] = ', MCT.nHybrid[i]);

    WriteLn(F, '');
    WriteLn(F, '--- fHybrid procedure addresses ---');
    for i := 0 to 5 do
      // In {$mode delphi}, @procVar returns the stored procedure address directly
      // (NOT the address of the variable — that would be @@procVar)
      WriteLn(F, '  fHybrid[', i, '] = $', IntToHex(PtrUInt(@MCT.fHybrid[i]), 8));

    WriteLn(F, '');
    WriteLn(F, '--- fHPVar constant pointers ---');
    for i := 0 to 5 do
      WriteLn(F, '  fHPVar[', i, '] = $', IntToHex(PtrUInt(MCT.fHPVar[i]), 8));

    WriteLn(F, '');
    WriteLn(F, '--- fHln (log scaling) ---');
    for i := 0 to 5 do
      WriteLn(F, '  fHln[', i, '] = ', MCT.fHln[i]:12:8);

    WriteLn(F, '');
    WriteLn(F, '--- Camera position ---');
    WriteLn(F, '  Xmit = ', MCT.Xmit:16:12);
    WriteLn(F, '  Ymit = ', MCT.Ymit:16:12);
    WriteLn(F, '  Zmit = ', MCT.Zmit:16:12);

    WriteLn(F, '');
    WriteLn(F, '--- Julia constants ---');
    WriteLn(F, '  dJUx = ', MCT.dJUx:16:12);
    WriteLn(F, '  dJUy = ', MCT.dJUy:16:12);
    WriteLn(F, '  dJUz = ', MCT.dJUz:16:12);
    WriteLn(F, '  dJUw = ', MCT.dJUw:16:12);

    WriteLn(F, '');
    WriteLn(F, '--- Cut planes ---');
    WriteLn(F, '  dCOX = ', MCT.dCOX:16:12);
    WriteLn(F, '  dCOY = ', MCT.dCOY:16:12);
    WriteLn(F, '  dCOZ = ', MCT.dCOZ:16:12);

    WriteLn(F, '');
    WriteLn(F, '--- CalcRect ---');
    WriteLn(F, '  Left   = ', MCT.CalcRect.Left);
    WriteLn(F, '  Top    = ', MCT.CalcRect.Top);
    WriteLn(F, '  Right  = ', MCT.CalcRect.Right);
    WriteLn(F, '  Bottom = ', MCT.CalcRect.Bottom);

    WriteLn(F, '');
    WriteLn(F, '--- Vgrads matrix ---');
    WriteLn(F, '  [0] = (', MCT.Vgrads[0, 0]:12:8, ', ', MCT.Vgrads[0, 1]:12:8, ', ', MCT.Vgrads[0, 2]:12:8, ')');
    WriteLn(F, '  [1] = (', MCT.Vgrads[1, 0]:12:8, ', ', MCT.Vgrads[1, 1]:12:8, ', ', MCT.Vgrads[1, 2]:12:8, ')');
    WriteLn(F, '  [2] = (', MCT.Vgrads[2, 0]:12:8, ', ', MCT.Vgrads[2, 1]:12:8, ', ', MCT.Vgrads[2, 2]:12:8, ')');
  finally
    CloseFile(F);
  end;

  DiagLog('MCTparas dumped to: ' + FPath);
end;

procedure DiagLogPostProc(const StepName: String; StepCode: Integer);
begin
  if not gDiagActive then Exit;
  DiagLog('PostProc step: ' + StepName + ' (code=' + IntToStr(StepCode) + ')');
end;

procedure DiagLogSiLight5Sample(pSiLight: Pointer; Width, Height: Integer; const SceneName: String);
var
  F: TextFile;
  FPath, SafeName: String;
  pSL: TPsiLight5;
  x, y, idx: Integer;
  n: Integer;
  SX, SY: array[0..8] of Integer;
begin
  if not gDiagActive then Exit;
  if (pSiLight = nil) or (Width <= 0) or (Height <= 0) then Exit;

  SafeName := StringReplace(SceneName, ' ', '_', [rfReplaceAll]);
  SafeName := StringReplace(SafeName, '.m3p', '', [rfReplaceAll, rfIgnoreCase]);
  if SafeName = '' then SafeName := 'default';
  FPath := DiagOutputDir + 'silight5_' + SafeName + '.txt';

  // 9 sample points: corners + edge midpoints + center
  SX[0] := 0;               SY[0] := 0;
  SX[1] := Width div 2;     SY[1] := 0;
  SX[2] := Width - 1;       SY[2] := 0;
  SX[3] := 0;               SY[3] := Height div 2;
  SX[4] := Width div 2;     SY[4] := Height div 2;
  SX[5] := Width - 1;       SY[5] := Height div 2;
  SX[6] := 0;               SY[6] := Height - 1;
  SX[7] := Width div 2;     SY[7] := Height - 1;
  SX[8] := Width - 1;       SY[8] := Height - 1;

  AssignFile(F, FPath);
  Rewrite(F);
  try
    WriteLn(F, '=== siLight5 samples for: ' + SceneName + ' ===');
    WriteLn(F, 'Image size: ', Width, 'x', Height);
    WriteLn(F, 'SizeOf(TsiLight5) = ', SizeOf(TsiLight5));
    WriteLn(F, '');

    for n := 0 to 8 do
    begin
      x := SX[n];
      y := SY[n];
      if (x >= 0) and (x < Width) and (y >= 0) and (y < Height) then
      begin
        idx := y * Width + x;
        pSL := TPsiLight5(PByte(pSiLight) + idx * SizeOf(TsiLight5));
        WriteLn(F, Format('--- Point (%d, %d) [idx=%d] ---', [x, y, idx]));
        WriteLn(F, '  NormalX      = ', pSL^.NormalX);
        WriteLn(F, '  NormalY      = ', pSL^.NormalY);
        WriteLn(F, '  NormalZ      = ', pSL^.NormalZ);
        WriteLn(F, '  RoughZposFine= ', pSL^.RoughZposFine);
        WriteLn(F, '  Zpos         = ', pSL^.Zpos);
        WriteLn(F, '  Shadow       = ', pSL^.Shadow);
        WriteLn(F, '  AmbShadow    = ', pSL^.AmbShadow);
        WriteLn(F, '  SIgradient   = ', pSL^.SIgradient);
        WriteLn(F, '  OTrap        = ', pSL^.OTrap);
        WriteLn(F, '');
      end;
    end;
  finally
    CloseFile(F);
  end;

  DiagLog('siLight5 samples saved to: ' + FPath);
end;

procedure DiagSaveFullSizeImageBMP(const FilePath: String; pData: Pointer; Width, Height, Stride: Integer);
{ Write fullSizeImage (array of Cardinal = BGRA, 4 bytes/pixel) as 24-bit BMP.
  BMP format is bottom-up, so row 0 in file = last row of image.
  Stride is bytes per row in the source (typically Width * 4). }
var
  F: file;
  BmpFileHdr: packed record
    bfType: Word;
    bfSize: Cardinal;
    bfReserved: Cardinal;
    bfOffBits: Cardinal;
  end;
  BmpInfoHdr: packed record
    biSize: Cardinal;
    biWidth: Integer;
    biHeight: Integer;
    biPlanes: Word;
    biBitCount: Word;
    biCompression: Cardinal;
    biSizeImage: Cardinal;
    biXPelsPerMeter: Integer;
    biYPelsPerMeter: Integer;
    biClrUsed: Cardinal;
    biClrImportant: Cardinal;
  end;
  RowBytes, PadBytes, y, x: Integer;
  RowBuf: array of Byte;
  pSrc: PByte;
  pDst: PByte;
begin
  RowBytes := Width * 3;
  PadBytes := (4 - (RowBytes mod 4)) mod 4;

  BmpFileHdr.bfType := $4D42; // 'BM'
  BmpFileHdr.bfOffBits := SizeOf(BmpFileHdr) + SizeOf(BmpInfoHdr);
  BmpFileHdr.bfSize := BmpFileHdr.bfOffBits + Cardinal((RowBytes + PadBytes) * Height);
  BmpFileHdr.bfReserved := 0;

  BmpInfoHdr.biSize := SizeOf(BmpInfoHdr);
  BmpInfoHdr.biWidth := Width;
  BmpInfoHdr.biHeight := Height; // positive = bottom-up
  BmpInfoHdr.biPlanes := 1;
  BmpInfoHdr.biBitCount := 24;
  BmpInfoHdr.biCompression := 0; // BI_RGB
  BmpInfoHdr.biSizeImage := Cardinal((RowBytes + PadBytes) * Height);
  BmpInfoHdr.biXPelsPerMeter := 0;
  BmpInfoHdr.biYPelsPerMeter := 0;
  BmpInfoHdr.biClrUsed := 0;
  BmpInfoHdr.biClrImportant := 0;

  SetLength(RowBuf, RowBytes + PadBytes);
  FillChar(RowBuf[0], Length(RowBuf), 0);

  AssignFile(F, FilePath);
  Rewrite(F, 1);
  try
    BlockWrite(F, BmpFileHdr, SizeOf(BmpFileHdr));
    BlockWrite(F, BmpInfoHdr, SizeOf(BmpInfoHdr));

    // Write rows bottom-up: BMP row 0 = image row (Height-1)
    for y := Height - 1 downto 0 do
    begin
      pSrc := PByte(pData) + y * Stride;
      pDst := @RowBuf[0];
      for x := 0 to Width - 1 do
      begin
        // Source is BGRA (Cardinal), destination is BGR (24-bit BMP)
        pDst^ := pSrc^;           Inc(pDst); Inc(pSrc); // B
        pDst^ := pSrc^;           Inc(pDst); Inc(pSrc); // G
        pDst^ := pSrc^;           Inc(pDst); Inc(pSrc); // R
        Inc(pSrc);                                        // skip A
      end;
      // Pad bytes are already 0 from FillChar
      BlockWrite(F, RowBuf[0], RowBytes + PadBytes);
    end;
  finally
    CloseFile(F);
  end;
end;

procedure DiagOnRenderComplete;
begin
  if not gDiagActive then Exit;

  DiagLog('Render complete for scene: ' + gDiagScene);
  DiagLog('Render time: ' + IntToStr(GetTickCount - gDiagRenderStartTick) + ' ms');
end;

initialization
  gDiagActive := False;
  gDiagLogOpen := False;

finalization
  DiagCloseLog;

end.
