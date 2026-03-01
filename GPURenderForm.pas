unit GPURenderForm;
{ GPU Render form — OpenCL-accelerated fractal rendering.
  Pattern follows MonteCarloForm.pas:
    - Own copy of parameters (GPUparas: TMandHeader10)
    - Timer-driven progress polling
    - Import/export params from/to main form
    - Start/Stop toggle via button caption }

{$mode delphi}
{$H+}

interface

uses
  SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ComCtrls, ExtCtrls,
  TypeDefinitions, OpenCLUtil, dglOpenCL;

type
  TGPURenderFrm = class(TForm)
    ToolbarPnl: TPanel;
    LabelDevice: TLabel;
    LabelStatus: TLabel;
    LabelTime: TLabel;
    ComboBoxDevice: TComboBox;
    ButtonImport: TButton;
    ButtonStartStop: TButton;
    ButtonSave: TButton;
    ButtonSendToMain: TButton;
    ProgressBar1: TProgressBar;
    ScrollBox1: TScrollBox;
    Image1: TImage;
    Timer1: TTimer;
    SaveDialog1: TSaveDialog;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure ComboBoxDeviceChange(Sender: TObject);
    procedure ButtonImportClick(Sender: TObject);
    procedure ButtonStartStopClick(Sender: TObject);
    procedure ButtonSaveClick(Sender: TObject);
    procedure ButtonSendToMainClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    FGPU: TOpenCLManager;
    FDeviceNames: TStringList;
    FRendering: Boolean;
    FRenderStartTime: Cardinal;
    FKernelSource: String;
    FProgram: cl_program;
    FKernel: cl_kernel;
    FParamsBuf: cl_mem;
    FFormulaBuf: cl_mem;
    FOutputBuf: cl_mem;
    FPixelData: array of Cardinal;

    function LoadKernelSource: String;
    function BuildKernelWithTranspiledFormulas: String;
    procedure CompileKernels;
    procedure InitOpenCL;
    procedure UpdateDeviceList;
    procedure SetStatus(const S: String);
    procedure StartRendering;
    procedure StopRendering;
    procedure DoRender;
    procedure DisplayResult;
  public
    GPUparas: TMandHeader10;
    GPUCalcStop: LongBool;
    GPUHybridCustoms: array[0..5] of TCustomFormula;
    GPUHAddOn: THeaderCustomAddon;
    GPUAvailable: Boolean;
  end;

var
  GPURenderFrm: TGPURenderFrm;
  GPURenderFormCreated: LongBool = False;

implementation

{$R *.lfm}

uses
  Windows, Mand, HeaderTrafos, CustomFormulas, Math, Math3D,
  FormulaTranspiler;

// ============================================================================
// GPU-side packed struct — must match RayMarchParams in common.cl
// ============================================================================

type
  TGPURayMarchParams = packed record
    width, height: Integer;
    Ystart: array[0..2] of Double;
    Vgrads: array[0..2, 0..2] of Double;
    FOVy: Double;
    StepWidth: Double;
    CAFX_start: Double;
    FOVXmul: Double;
    CameraOptic: Integer;
    _pad0: Integer;
    dZstart: Double;
    dZend: Double;
    DEstop: Double;
    sZstepDiv: Double;
    mctDEstopFactor: Double;
    mctDEoffset: Double;
    mctMH04ZSD: Double;
    dDEscale: Double;
    iMaxIts: Integer;
    iMinIt: Integer;
    MaxItsResult: Integer;
    iDEAddSteps: Integer;
    iSmNormals: Integer;
    formulaCount: Integer;
    nHybrid: array[0..5] of Integer;
    formulaType: array[0..5] of Integer;
    isCustomDE: Integer;
    DEcombMode: Integer;
    iRepeatFrom: Integer;
    iStartFrom: Integer;
    isJulia: Integer;
    _pad1: Integer;
    Jx, Jy, Jz, Jw: Double;
    lightDir: array[0..2] of Double;
    ambient: Double;
    diffuse: Double;
    specular: Double;
    specPower: Double;
    fogDist: Double;
    dColPlus: Double;
    colorOption: Integer;
    _pad2: Integer;
  end;

  TGPUFormulaParams = packed record
    params: array[0..5, 0..15] of Double;
  end;

// ============================================================================
// Formula mapping helpers (local to unit)
// ============================================================================

const
  // Must match #defines in common.cl
  GPU_FORMULA_NONE         = 0;
  GPU_FORMULA_INTPOW2      = 1;
  GPU_FORMULA_INTPOW3      = 2;
  GPU_FORMULA_INTPOW4      = 3;
  GPU_FORMULA_INTPOW5      = 4;
  GPU_FORMULA_INTPOW6      = 5;
  GPU_FORMULA_INTPOW7      = 6;
  GPU_FORMULA_INTPOW8      = 7;
  GPU_FORMULA_FLOATPOW     = 8;
  GPU_FORMULA_AMAZINGBOX   = 9;
  GPU_FORMULA_AMAZINGSURF  = 10;
  GPU_FORMULA_QUATERNION   = 11;
  GPU_FORMULA_MENGERSPONGE = 12;
  GPU_FORMULA_BULBOX       = 13;
  GPU_FORMULA_CUSTOM_BASE  = 100;

function ExternalNameToGPU(const Name: String): Integer;
var
  LName: String;
begin
  LName := LowerCase(Name);
  if Pos('mengersponge', LName) > 0 then Result := GPU_FORMULA_MENGERSPONGE
  else if Pos('amazingsurf', LName) > 0 then Result := GPU_FORMULA_AMAZINGSURF
  else if Pos('amazingbox', LName) > 0 then Result := GPU_FORMULA_AMAZINGBOX
  else if Pos('abox', LName) > 0 then Result := GPU_FORMULA_AMAZINGBOX
  else if Pos('quaternion', LName) > 0 then Result := GPU_FORMULA_QUATERNION
  else if Pos('bulbox', LName) > 0 then Result := GPU_FORMULA_BULBOX
  else Result := GPU_FORMULA_NONE;  // unsupported — will be skipped by kernel
end;

function DoMapFormulaToGPU(SlotIndex: Integer; Header: TPMandHeader10): Integer;
var
  pAddon: PTHeaderCustomAddon;
  iFnr: Integer;
  Power: Integer;
  FName: String;
  i: Integer;
begin
  Result := GPU_FORMULA_INTPOW2;  // safe default

  pAddon := PTHeaderCustomAddon(Header^.PCFAddon);
  if pAddon = nil then Exit;
  if SlotIndex > Integer(pAddon^.iFCount) then
  begin
    Result := GPU_FORMULA_NONE;
    Exit;
  end;

  iFnr := pAddon^.Formulas[SlotIndex].iFnr;

  if iFnr < 20 then
  begin
    // Internal formula
    case iFnr of
      0: begin  // Integer Power — power from dOptionValue[0]
           Power := Round(pAddon^.Formulas[SlotIndex].dOptionValue[0]);
           if Power < 2 then Power := 2;
           if Power > 8 then Power := 8;
           Result := GPU_FORMULA_INTPOW2 + (Power - 2);  // 2→1, 3→2, ..., 8→7
         end;
      1: Result := GPU_FORMULA_FLOATPOW;
      2: Result := GPU_FORMULA_QUATERNION;
      3: Result := GPU_FORMULA_INTPOW2;  // Tricorn — no GPU impl, fallback to IntPow2
      4: Result := GPU_FORMULA_AMAZINGBOX;
      5: Result := GPU_FORMULA_BULBOX;
      6: Result := GPU_FORMULA_INTPOW2;  // Folding Int Pow — no GPU impl yet
      7: Result := GPU_FORMULA_INTPOW2;  // test — no GPU impl
      8: Result := GPU_FORMULA_MENGERSPONGE; // testIFS → Menger
      9: Result := GPU_FORMULA_INTPOW2;  // Aexion C — no GPU impl
    else
      Result := GPU_FORMULA_INTPOW2;
    end;
  end
  else
  begin
    // External formula (iFnr >= 20) — try built-in GPU match first
    FName := '';
    for i := 0 to 31 do
    begin
      if pAddon^.Formulas[SlotIndex].CustomFname[i] = 0 then Break;
      FName := FName + Chr(pAddon^.Formulas[SlotIndex].CustomFname[i]);
    end;
    Result := ExternalNameToGPU(FName);
    // If no built-in match, check if it was transpiled (custom ID = 100 + slot)
    if Result = GPU_FORMULA_NONE then
      Result := GPU_FORMULA_CUSTOM_BASE + SlotIndex;
  end;
end;

procedure DoFillFormulaParams(SlotIndex: Integer; Header: TPMandHeader10;
  var OutParams: array of Double);
var
  i: Integer;
  pAddon: PTHeaderCustomAddon;
begin
  for i := 0 to High(OutParams) do
    OutParams[i] := 0.0;
  OutParams[0] := 1.0; // default Zmul = 1.0

  // Try to read dOptionValues from the header addon
  pAddon := Header^.PCFAddon;
  if pAddon = nil then Exit;
  if SlotIndex > Integer(pAddon^.iFCount) then Exit;

  // Copy option values from the addon (up to 16 doubles per formula)
  for i := 0 to Min(15, High(OutParams)) do
    OutParams[i] := pAddon^.Formulas[SlotIndex].dOptionValue[i];
end;

// ============================================================================
// .m3f SOURCE extraction (for transpilation)
// ============================================================================

function ExtractM3fSource(const FileName: String;
  out Source: String; out ParamNames: TStringList): Boolean;
{ Read a .m3f file and extract the [SOURCE] section and [OPTIONS] param names. }
var
  SL: TStringList;
  i: Integer;
  Line, TrimLine, LowerLine: String;
  InSource, InOptions: Boolean;
  ParamIndex: Integer;
  EqPos: Integer;
  PName: String;
begin
  Result := False;
  Source := '';
  ParamNames := TStringList.Create;

  if not FileExists(FileName) then Exit;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(FileName);
    InSource := False;
    InOptions := False;
    ParamIndex := 0;

    for i := 0 to SL.Count - 1 do
    begin
      Line := SL[i];
      TrimLine := Trim(Line);
      LowerLine := LowerCase(TrimLine);

      if LowerLine = '[source]' then
      begin
        InSource := True;
        InOptions := False;
        Continue;
      end;
      if LowerLine = '[options]' then
      begin
        InOptions := True;
        InSource := False;
        Continue;
      end;
      if (Length(TrimLine) > 0) and (TrimLine[1] = '[') and
         (TrimLine[Length(TrimLine)] = ']') then
      begin
        InSource := False;
        InOptions := False;
        Continue;
      end;

      if InSource then
        Source := Source + Line + #10
      else if InOptions then
      begin
        // Extract parameter names from lines like ".Double Power_ = 8"
        if (Pos('.double ', LowerLine) = 1) or
           (Pos('.single ', LowerLine) = 1) or
           (Pos('.integer ', LowerLine) = 1) then
        begin
          // Extract name: skip type prefix, take word before '='
          EqPos := Pos('=', TrimLine);
          if EqPos > 0 then
            PName := Trim(Copy(TrimLine, Pos(' ', TrimLine) + 1, EqPos - Pos(' ', TrimLine) - 1))
          else
            PName := Trim(Copy(TrimLine, Pos(' ', TrimLine) + 1, Length(TrimLine)));
          PName := Trim(PName);
          if PName <> '' then
          begin
            ParamNames.AddObject(PName, TObject(PtrInt(ParamIndex)));
            Inc(ParamIndex);
          end;
        end;
      end;
    end;

    Result := Source <> '';
  finally
    SL.Free;
  end;
end;

function ExtractM3fConstants(const FileName: String): TStringList;
{ Read [CONSTANTS] section. Returns name=value pairs. }
var
  SL: TStringList;
  i: Integer;
  Line, TrimLine, LowerLine: String;
  InConstants: Boolean;
  SpPos, EqPos: Integer;
  CName, CVal: String;
begin
  Result := TStringList.Create;
  if not FileExists(FileName) then Exit;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(FileName);
    InConstants := False;

    for i := 0 to SL.Count - 1 do
    begin
      Line := SL[i];
      TrimLine := Trim(Line);
      LowerLine := LowerCase(TrimLine);

      if LowerLine = '[constants]' then
      begin
        InConstants := True;
        Continue;
      end;
      if (Length(TrimLine) > 0) and (TrimLine[1] = '[') then
      begin
        InConstants := False;
        Continue;
      end;

      if InConstants and (Pos('.', TrimLine) = 1) then
      begin
        // ".Double name = value"
        EqPos := Pos('=', TrimLine);
        if EqPos > 0 then
        begin
          // Find name between type keyword and =
          SpPos := Pos(' ', TrimLine);
          if SpPos > 0 then
          begin
            CName := Trim(Copy(TrimLine, SpPos + 1, EqPos - SpPos - 1));
            CVal := Trim(Copy(TrimLine, EqPos + 1, Length(TrimLine)));
            if (CName <> '') and (CVal <> '') then
              Result.Values[CName] := CVal;
          end;
        end;
      end;
    end;
  finally
    SL.Free;
  end;
end;

// ============================================================================
// Build kernel with transpiled custom formulas
// ============================================================================

function TGPURenderFrm.BuildKernelWithTranspiledFormulas: String;
var
  BaseSource: String;
  TranspiledCode: String;
  DispatchCases: String;
  pAddon: PTHeaderCustomAddon;
  i, j, iFnr: Integer;
  FName, FullPath: String;
  Source: String;
  ParamNames, Constants: TStringList;
  Transpiler: TFormulaTranspiler;
  TR: TTranspilerResult;
  GPUId: Integer;
  FormulaDir: String;
begin
  BaseSource := LoadKernelSource;
  TranspiledCode := '';
  DispatchCases := '';

  pAddon := PTHeaderCustomAddon(GPUparas.PCFAddon);
  FormulaDir := ExtractFilePath(Application.ExeName) + 'M3Formulas' + PathDelim;

  if pAddon <> nil then
  begin
    Transpiler := TFormulaTranspiler.Create;
    try
      for i := 0 to Min(5, Integer(pAddon^.iFCount)) do
      begin
        iFnr := pAddon^.Formulas[i].iFnr;
        if iFnr < 20 then Continue;  // internal formulas handled by built-in kernels

        // Get filename from CustomFname
        FName := '';
        for j := 0 to 31 do
        begin
          if pAddon^.Formulas[i].CustomFname[j] = 0 then Break;
          FName := FName + Chr(pAddon^.Formulas[i].CustomFname[j]);
        end;
        if FName = '' then Continue;

        // Check if we already have a built-in GPU kernel for this formula
        if ExternalNameToGPU(FName) <> GPU_FORMULA_NONE then Continue;

        // Try to extract and transpile SOURCE
        FullPath := FormulaDir + FName;
        if not FileExists(FullPath) then
          FullPath := FormulaDir + FName + '.m3f';

        ParamNames := nil;
        Constants := nil;
        try
          if not ExtractM3fSource(FullPath, Source, ParamNames) then Continue;
          Constants := ExtractM3fConstants(FullPath);

          Transpiler.ClearParams;
          Transpiler.ClearConstants;

          // Register parameters
          for j := 0 to ParamNames.Count - 1 do
            Transpiler.AddParam(ParamNames[j], Integer(PtrInt(ParamNames.Objects[j])));

          // Register constants
          for j := 0 to Constants.Count - 1 do
          begin
            try
              Transpiler.AddConstant(Constants.Names[j],
                StrToFloat(Constants.ValueFromIndex[j]));
            except
            end;
          end;

          // Transpile
          GPUId := GPU_FORMULA_CUSTOM_BASE + i;
          TR := Transpiler.Transpile(Source, ChangeFileExt(ExtractFileName(FName), ''));

          if TR.Success then
          begin
            TranspiledCode := TranspiledCode + TR.OpenCLSource + #10;
            DispatchCases := DispatchCases +
              Format('        case %d: formula_%s(it, fp->params[slot]); break;' + #10,
                [GPUId, LowerCase(ChangeFileExt(ExtractFileName(FName), ''))]);
          end;
        finally
          ParamNames.Free;
          Constants.Free;
        end;
      end;
    finally
      Transpiler.Free;
    end;
  end;

  if TranspiledCode <> '' then
  begin
    // Strategy: inject transpiled functions before dispatch_formula,
    // and add custom case statements into the switch.
    // We find the dispatch_formula switch's "default:" and insert before it.

    // 1. Insert transpiled function bodies before dispatch_formula
    j := Pos('void dispatch_formula(', BaseSource);
    if j > 0 then
    begin
      BaseSource := Copy(BaseSource, 1, j - 1) +
        '// ====== Transpiled custom formulas ======' + #10 +
        TranspiledCode + #10 +
        Copy(BaseSource, j, Length(BaseSource));
    end;

    // 2. Insert dispatch cases before "default: break;"
    j := Pos('default: break;  // unknown formula', BaseSource);
    if j > 0 then
    begin
      BaseSource := Copy(BaseSource, 1, j - 1) +
        DispatchCases +
        '        ' +
        Copy(BaseSource, j, Length(BaseSource));
    end;
  end;

  Result := BaseSource;
end;

// ============================================================================
// Kernel compilation
// ============================================================================

procedure TGPURenderFrm.CompileKernels;
var
  Source: String;
begin
  Source := BuildKernelWithTranspiledFormulas;
  FProgram := FGPU.CompileSource(Source, '-cl-mad-enable');
  FKernel := FGPU.CreateKernel(FProgram, 'ray_march');
end;

// ============================================================================
// Kernel source loading
// ============================================================================

function TGPURenderFrm.LoadKernelSource: String;

  function ReadTextFile(const FileName: String): String;
  var
    SL: TStringList;
    FullPath: String;
  begin
    FullPath := ExtractFilePath(Application.ExeName) + FileName;
    SL := TStringList.Create;
    try
      if FileExists(FullPath) then
        SL.LoadFromFile(FullPath)
      else
        raise Exception.CreateFmt('Kernel file not found: %s', [FullPath]);
      Result := SL.Text;
    finally
      SL.Free;
    end;
  end;

begin
  Result := ReadTextFile('shaders' + PathDelim + 'kernels' + PathDelim + 'common.cl') + #10 +
            ReadTextFile('shaders' + PathDelim + 'kernels' + PathDelim + 'formulas.cl') + #10 +
            ReadTextFile('shaders' + PathDelim + 'kernels' + PathDelim + 'raymarch.cl');
end;

// ============================================================================
// Form events
// ============================================================================

procedure TGPURenderFrm.FormCreate(Sender: TObject);
begin
  FGPU := TOpenCLManager.Create;
  FDeviceNames := nil;
  FRendering := False;
  FProgram := nil;
  FKernel := nil;
  FParamsBuf := nil;
  FFormulaBuf := nil;
  FOutputBuf := nil;
  GPUAvailable := False;
  GPURenderFormCreated := True;

  Image1.Picture.Bitmap.PixelFormat := pf32bit;
  Image1.Picture.Bitmap.SetSize(400, 300);

  InitOpenCL;
end;

procedure TGPURenderFrm.FormDestroy(Sender: TObject);
begin
  StopRendering;
  FDeviceNames.Free;
  FGPU.Free;
  GPURenderFormCreated := False;
end;

procedure TGPURenderFrm.FormShow(Sender: TObject);
begin
  if not GPUAvailable then
    SetStatus('OpenCL not available — no GPU driver found')
  else if ComboBoxDevice.ItemIndex < 0 then
    SetStatus('Select a GPU device to begin')
  else
    SetStatus('Ready — import parameters and start rendering');
end;

// ============================================================================
// OpenCL initialization
// ============================================================================

procedure TGPURenderFrm.InitOpenCL;
begin
  GPUAvailable := FGPU.Init;
  UpdateDeviceList;

  if not GPUAvailable then
  begin
    ButtonStartStop.Enabled := False;
    ButtonImport.Enabled := False;
    SetStatus('OpenCL not available');
    Exit;
  end;

  if ComboBoxDevice.Items.Count > 0 then
  begin
    ComboBoxDevice.ItemIndex := 0;
    ComboBoxDeviceChange(nil);
  end;
end;

procedure TGPURenderFrm.UpdateDeviceList;
var
  i: Integer;
begin
  FDeviceNames.Free;
  FDeviceNames := FGPU.GetDeviceNames;
  ComboBoxDevice.Items.Clear;
  for i := 0 to FDeviceNames.Count - 1 do
    ComboBoxDevice.Items.Add(FDeviceNames[i]);
end;

procedure TGPURenderFrm.ComboBoxDeviceChange(Sender: TObject);
var
  DevInfo: TOpenCLDeviceInfo;
begin
  if ComboBoxDevice.ItemIndex < 0 then Exit;

  try
    FGPU.SelectDevice(ComboBoxDevice.ItemIndex);
    DevInfo := FGPU.GetDevice(ComboBoxDevice.ItemIndex);

    if not DevInfo.HasDouble then
      SetStatus('WARNING: Device lacks fp64 — results may differ from CPU.')
    else
      SetStatus(Format('Device ready: %s (%d CU, %dMB)',
        [DevInfo.DeviceName, DevInfo.MaxComputeUnits,
         DevInfo.GlobalMemSize div (1024*1024)]));

    CompileKernels;

    SetStatus(Format('Ready — %s (kernels compiled)',
      [DevInfo.DeviceName]));
  except
    on E: Exception do
      SetStatus('Error: ' + E.Message);
  end;
end;

// ============================================================================
// Parameter import/export
// ============================================================================

procedure TGPURenderFrm.ButtonImportClick(Sender: TObject);
begin
  if FRendering then Exit;

  Mand3DForm.MakeHeader;
  AssignHeader(@GPUparas, @Mand3DForm.MHeader);
  IniCFsFromHAddon(GPUparas.PCFAddon, GPUparas.PHCustomF);

  Image1.Picture.Bitmap.SetSize(GPUparas.Width, GPUparas.Height);
  SetLength(FPixelData, GPUparas.Width * GPUparas.Height);

  // Recompile kernels with any transpiled custom formulas
  if FGPU.HasContext then
  begin
    try
      CompileKernels;
      SetStatus(Format('Parameters imported: %dx%d, %d iterations (kernels recompiled)',
        [GPUparas.Width, GPUparas.Height, GPUparas.Iterations]));
    except
      on E: Exception do
        SetStatus(Format('Parameters imported: %dx%d — kernel error: %s',
          [GPUparas.Width, GPUparas.Height, E.Message]));
    end;
  end
  else
    SetStatus(Format('Parameters imported: %dx%d, %d iterations',
      [GPUparas.Width, GPUparas.Height, GPUparas.Iterations]));
  ButtonSave.Enabled := False;
  ButtonSendToMain.Enabled := False;
end;

procedure TGPURenderFrm.ButtonSendToMainClick(Sender: TObject);
begin
  AssignHeader(@Mand3DForm.MHeader, @GPUparas);
  Mand3DForm.SetEditsFromHeader;
  Mand3DForm.ParasChanged;
  SetFocus;
end;

// ============================================================================
// Start / Stop rendering
// ============================================================================

procedure TGPURenderFrm.ButtonStartStopClick(Sender: TObject);
begin
  if FRendering then
    StopRendering
  else
    StartRendering;
end;

procedure TGPURenderFrm.StartRendering;
begin
  if not FGPU.HasContext then
  begin
    SetStatus('No OpenCL device selected');
    Exit;
  end;
  if FKernel = nil then
  begin
    SetStatus('Kernels not compiled');
    Exit;
  end;
  if GPUparas.Width = 0 then
  begin
    SetStatus('Import parameters first');
    Exit;
  end;

  FRendering := True;
  GPUCalcStop := False;
  ButtonStartStop.Caption := 'Stop render';
  ButtonImport.Enabled := False;
  ButtonSave.Enabled := False;
  ButtonSendToMain.Enabled := False;
  ComboBoxDevice.Enabled := False;
  FRenderStartTime := GetTickCount64;

  ProgressBar1.Max := 100;
  ProgressBar1.Position := 0;
  Timer1.Enabled := True;

  SetStatus('Rendering...');

  try
    DoRender;
  except
    on E: Exception do
    begin
      SetStatus('Render error: ' + E.Message);
      StopRendering;
    end;
  end;
end;

procedure TGPURenderFrm.StopRendering;
begin
  GPUCalcStop := True;
  FRendering := False;
  Timer1.Enabled := False;
  ButtonStartStop.Caption := 'Start render';
  ButtonImport.Enabled := True;
  ComboBoxDevice.Enabled := True;
end;

// ============================================================================
// GPU render execution
// ============================================================================

procedure TGPURenderFrm.DoRender;
var
  MCTp: TMCTparameter;
  RMP: TGPURayMarchParams;
  FP: TGPUFormulaParams;
  W, H: Integer;
  i, j: Integer;
  ElapsedMs: Cardinal;
begin
  W := GPUparas.Width;
  H := GPUparas.Height;
  if (W <= 0) or (H <= 0) then Exit;

  // Convert header to internal calc parameters
  MCTp := GetMCTparasFromHeader(GPUparas, False);

  // Fill GPU ray march params
  FillChar(RMP, SizeOf(RMP), 0);
  RMP.width := W;
  RMP.height := H;

  // Camera (TVec3D = array[0..2] of Double)
  for i := 0 to 2 do
    RMP.Ystart[i] := MCTp.Ystart[i];
  for i := 0 to 2 do
    for j := 0 to 2 do
      RMP.Vgrads[i][j] := MCTp.Vgrads[i][j];

  RMP.FOVy := MCTp.FOVy;
  RMP.StepWidth := MCTp.StepWidth;
  RMP.CAFX_start := MCTp.FOVXoff;
  RMP.FOVXmul := MCTp.FOVXmul;
  RMP.CameraOptic := 0;

  // Ray marching (note: some TMCTparameter fields are Single, widen to Double)
  RMP.dZstart := MCTp.StepWidth;
  RMP.dZend := MCTp.Zend;
  RMP.DEstop := MCTp.DEstop;
  RMP.sZstepDiv := MCTp.sZstepDiv;
  RMP.mctDEstopFactor := MCTp.mctDEstopFactor;
  RMP.mctDEoffset := MCTp.mctDEoffset;
  RMP.mctMH04ZSD := MCTp.mctMH04ZSD;
  RMP.dDEscale := MCTp.dDEscale;
  RMP.iMaxIts := MCTp.iMaxIt;
  RMP.iMinIt := MCTp.iMinIt;
  RMP.MaxItsResult := MCTp.MaxItsResult;
  RMP.iDEAddSteps := MCTp.iDEAddSteps;
  RMP.iSmNormals := MCTp.iSmNormals;

  // Formula chain
  RMP.formulaCount := MCTp.wEndTo + 1;
  RMP.isCustomDE := Ord(MCTp.IsCustomDE);
  RMP.DEcombMode := MCTp.FormulaType;
  RMP.iRepeatFrom := MCTp.RepeatFrom1;
  RMP.iStartFrom := MCTp.StartFrom1;

  for i := 0 to 5 do
  begin
    RMP.nHybrid[i] := MCTp.nHybrid[i];
    RMP.formulaType[i] := DoMapFormulaToGPU(i, @GPUparas);
  end;

  // Julia mode
  RMP.isJulia := Ord(GPUparas.bIsJulia <> 0);
  RMP.Jx := GPUparas.dJx;
  RMP.Jy := GPUparas.dJy;
  RMP.Jz := GPUparas.dJz;
  RMP.Jw := GPUparas.dJw;

  // Basic lighting defaults
  RMP.lightDir[0] := 0.577;
  RMP.lightDir[1] := 0.577;
  RMP.lightDir[2] := 0.577;
  RMP.ambient := 0.2;
  RMP.diffuse := 0.8;
  RMP.specular := 0.3;
  RMP.specPower := 32.0;
  RMP.fogDist := 0.0;

  RMP.dColPlus := MCTp.dColPlus;
  RMP.colorOption := MCTp.ColorOption;

  // Fill formula parameters
  FillChar(FP, SizeOf(FP), 0);
  for i := 0 to Min(RMP.formulaCount - 1, 5) do
    DoFillFormulaParams(i, @GPUparas, FP.params[i]);

  // Upload to GPU
  FParamsBuf := FGPU.CreateBuffer(SizeOf(RMP), CL_MEM_READ_ONLY or CL_MEM_COPY_HOST_PTR, @RMP);
  FFormulaBuf := FGPU.CreateBuffer(SizeOf(FP), CL_MEM_READ_ONLY or CL_MEM_COPY_HOST_PTR, @FP);
  FOutputBuf := FGPU.CreateBuffer(W * H * SizeOf(Cardinal), CL_MEM_WRITE_ONLY);

  // Set kernel arguments
  FGPU.SetKernelArgMem(FKernel, 0, FParamsBuf);
  FGPU.SetKernelArgMem(FKernel, 1, FFormulaBuf);
  FGPU.SetKernelArgMem(FKernel, 2, FOutputBuf);
  FGPU.SetKernelArgInt(FKernel, 3, W);
  FGPU.SetKernelArgInt(FKernel, 4, H);

  // Execute kernel
  SetStatus(Format('GPU rendering %dx%d...', [W, H]));
  Application.ProcessMessages;

  FGPU.Execute2D(FKernel, W, H);
  FGPU.Finish;

  // Read back results
  SetLength(FPixelData, W * H);
  FGPU.ReadBuffer(FOutputBuf, FPixelData[0], W * H * SizeOf(Cardinal));

  // Release GPU buffers
  FGPU.ReleaseBuffer(FParamsBuf);
  FGPU.ReleaseBuffer(FFormulaBuf);
  FGPU.ReleaseBuffer(FOutputBuf);

  // Display result
  DisplayResult;

  // Done
  ElapsedMs := GetTickCount64 - FRenderStartTime;
  StopRendering;
  ButtonSave.Enabled := True;
  ButtonSendToMain.Enabled := True;
  SetStatus(Format('Render complete: %dx%d in %.1fs',
    [W, H, ElapsedMs / 1000.0]));
end;

// ============================================================================
// Display helpers
// ============================================================================

procedure TGPURenderFrm.DisplayResult;
var
  y, W, H: Integer;
  SL: PCardinal;
begin
  W := GPUparas.Width;
  H := GPUparas.Height;

  Image1.Picture.Bitmap.SetSize(W, H);
  Image1.Picture.Bitmap.PixelFormat := pf32bit;

  for y := 0 to H - 1 do
  begin
    SL := PCardinal(Image1.Picture.Bitmap.ScanLine[y]);
    Move(FPixelData[y * W], SL^, W * SizeOf(Cardinal));
  end;

  Image1.Width := W;
  Image1.Height := H;
  Image1.Invalidate;
end;

procedure TGPURenderFrm.SetStatus(const S: String);
begin
  LabelStatus.Caption := S;
end;

// ============================================================================
// Timer — progress polling
// ============================================================================

procedure TGPURenderFrm.Timer1Timer(Sender: TObject);
begin
  if FRendering then
    LabelTime.Caption := Format('%.1fs',
      [(GetTickCount64 - FRenderStartTime) / 1000.0]);
end;

// ============================================================================
// Save image
// ============================================================================

procedure TGPURenderFrm.ButtonSaveClick(Sender: TObject);
begin
  if SaveDialog1.Execute then
  begin
    Image1.Picture.Bitmap.SaveToFile(SaveDialog1.FileName);
    SetStatus('Image saved: ' + ExtractFileName(SaveDialog1.FileName));
  end;
end;

end.
