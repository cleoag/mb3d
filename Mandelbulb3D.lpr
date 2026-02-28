program Mandelbulb3D;

{$mode delphi}

uses
  SysUtils, Classes, LResources,
  Interfaces, // LCL widgetset
  Forms,
  HeadlessRender,
  Mand in 'Mand.pas' {Mand3DForm},
  LightAdjust in 'LightAdjust.pas' {LightAdjustForm},
  CalcThread in 'CalcThread.pas',
  AmbShadowCalcThreadN in 'AmbShadowCalcThreadN.pas',
  DivUtils in 'DivUtils.pas',
  formulas in 'formulas.pas',
  PaintThread in 'PaintThread.pas',
  FileHandling in 'FileHandling.pas',
  ImageProcess in 'ImageProcess.pas',
  Navigator in 'Navigator.pas' {FNavigator},
  NaviCalcThread in 'NaviCalcThread.pas',
  Math3D in 'Math3D.pas',
  CalcThread2D in 'CalcThread2D.pas',
  CustomFormulas in 'CustomFormulas.pas',
  Animation in 'Animation.pas' {AnimationForm},
  Calc in 'Calc.pas',
  AniPreviewWindow in 'AniPreviewWindow.pas' {AniPreviewForm},
  HeaderTrafos in 'HeaderTrafos.pas',
  TypeDefinitions in 'TypeDefinitions.pas',
  AniProcess in 'AniProcess.pas' {AniProcessForm},
  MapSequencesGUI in 'maps\MapSequencesGUI.pas' {MapSequencesFrm},
  FormulaGUI in 'formula\FormulaGUI.pas' {FormulaGUIForm},
  DOF in 'DOF.pas',
  ColorPick in 'ColorPick.pas' {ColorForm},
  Paint in 'Paint.pas',
  CalcAmbShadowDE in 'CalcAmbShadowDE.pas',
  Interpolation in 'Interpolation.pas',
  CalcHardShadow in 'CalcHardShadow.pas',
  AmbHiQ in 'AmbHiQ.pas',
  BatchForm in 'BatchForm.pas' {BatchForm1},
  Undo in 'Undo.pas',
  CalcSR in 'CalcSR.pas',
  CalcPart in 'CalcPart.pas',
  BulbTracer2UI in 'bulbtracer2\BulbTracer2UI.pas' {BulbTracer2Frm},
  CalcVoxelSliceThread in 'CalcVoxelSliceThread.pas',
  calcBlocky in 'calcBlocky.pas',
  FormulaParser in 'FormulaParser.pas' {FormulaEditor},
  CalcMonteCarlo in 'CalcMonteCarlo.pas',
  Tiling in 'Tiling.pas' {TilingForm},
  MonteCarloForm in 'MonteCarloForm.pas' {MCForm},
  TextBox in 'TextBox.pas' {FTextBox},
  BRInfoWindow in 'BRInfoWindow.pas' {BRInfoForm},
  FFT in 'FFT.pas',
  RegisterM3Pgraphic in 'RegisterM3Pgraphic.pas',
  ColorSSAO in 'ColorSSAO.pas',
  ThreadUtils in 'ThreadUtils.pas',
  MB3DMaps in 'maps\MB3DMaps.pas',
  ScriptUI in 'script\ScriptUI.pas' {ScriptEditorForm},
  ColorOptionForm in 'ColorOptionForm.pas' {FColorOptions},
  uMapCalcWindow in 'uMapCalcWindow.pas' {MapCalcWindow},
  ScriptCompiler in 'script\ScriptCompiler.pas',
  PreviewRenderer in 'render\PreviewRenderer.pas',
  MB3DFacade in 'facade\MB3DFacade.pas',
  MutaGenGUI in 'mutagen\MutaGenGUI.pas' {MutaGenFrm},
  MutaGen in 'mutagen\MutaGen.pas',
  FormulaNames in 'formula\FormulaNames.pas',
  MapSequences in 'maps\MapSequences.pas',
  IniDirsForm in 'prefs\IniDirsForm.pas' {IniDirForm},
  VisualThemesGUI in 'prefs\VisualThemesGUI.pas' {VisualThemesFrm},
  JITFormulaEditGUI in 'formula\JITFormulaEditGUI.pas' {JITFormulaEditorForm},
  JITFormulas in 'formula\JITFormulas.pas',
  ParamValueEditGUI in 'formula\ParamValueEditGUI.pas' {ParamValueEditFrm},
  VoxelExport in 'VoxelExport.pas' {FVoxelExport},
  VectorMath in 'bulbtracer2\VectorMath.pas',
  BulbTracer2 in 'bulbtracer2\BulbTracer2.pas',
  ObjectScanner2 in 'bulbtracer2\ObjectScanner2.pas',
  BulbTracer2Config in 'bulbtracer2\BulbTracer2Config.pas',
  MeshPreview in 'opengl\MeshPreview.pas',
  BulbTracerUITools in 'bulbtracer2\BulbTracerUITools.pas',
  MeshReader in 'bulbtracer2\MeshReader.pas',
  MeshIOUtil in 'bulbtracer2\MeshIOUtil.pas',
  ShaderUtil in 'opengl\ShaderUtil.pas',
  dglOpenGL in 'opengl\dglOpenGL.pas',
  MeshPreviewUI in 'opengl\MeshPreviewUI.pas' {MeshPreviewFrm},
  OpenGLPreviewUtil in 'opengl\OpenGLPreviewUtil.pas',
  HeightMapGenPreview in 'heightmapgen\HeightMapGenPreview.pas',
  HeightMapGenUI in 'heightmapgen\HeightMapGenUI.pas' {HeightMapGenFrm},
  PNMWriter in 'heightmapgen\PNMWriter.pas',
  PostProcessForm in 'PostProcessForm.pas' {PostProForm},
  PNMReader in 'heightmapgen\PNMReader.pas',
  CompilerUtil in 'script\CompilerUtil.pas',
  FormulaCompiler in 'formula\FormulaCompiler.pas',
  VertexList in 'bulbtracer2\VertexList.pas',
  MeshWriter in 'bulbtracer2\MeshWriter.pas',
  ZBuf16BitGenUI in 'zbuf16bit\ZBuf16BitGenUI.pas' {ZBuf16BitGenFrm},
  ZBuf16BitGen in 'zbuf16bit\ZBuf16BitGen.pas';

{$R *.res}

var
  LogFile: TextFile;
  StartupLogFilePtr: ^TextFile;

type
  TStartupExceptionHandler = class
    class procedure HandleException(Sender: TObject; E: Exception);
  end;

class procedure TStartupExceptionHandler.HandleException(Sender: TObject; E: Exception);
begin
  if StartupLogFilePtr <> nil then
  begin
    WriteLn(StartupLogFilePtr^, '  IGNORED: ' + E.ClassName + ': ' + E.Message);
    Flush(StartupLogFilePtr^);
  end;
end;

begin
  { Skip Delphi VCL properties that don't exist in LCL.
    RegisterPropertyToSkip only affects components where the property
    is NOT published — components that DO have it still read normally. }
  RegisterPropertyToSkip(TPersistent, 'BevelKind', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'BevelOuter', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'BevelInner', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'DoubleBuffered', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ParentDoubleBuffered', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'AlignWithMargins', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Margins', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Margins.Left', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Margins.Top', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Margins.Right', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Margins.Bottom', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Padding', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Padding.Left', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Padding.Top', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Padding.Right', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Padding.Bottom', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'HotTrack', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Highlighted', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ShowWorkAreas', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'TabWidth', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'MultiLine', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ExplicitLeft', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ExplicitTop', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ExplicitWidth', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ExplicitHeight', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'StyleElements', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Ctl3D', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ParentCtl3D', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Touch.InteractiveGestures', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Touch.InteractiveGestureOptions', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'GlassFrame.Enabled', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Zoom', 'TRichEdit-specific', '');
  RegisterPropertyToSkip(TPersistent, 'HideSelection', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'OldCreateOrder', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'TextHeight', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'DesignSize', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'AutoComplete', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'AutoCompleteDelay', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'NumbersOnly', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ParentBackground', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ImeMode', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ImeName', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'OEMConvert', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'FlatScrollBars', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'FullDrag', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'HideScrollBars', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'BevelEdges', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'CharCase', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'PositionToolTip', 'Delphi TTrackBar', '');
  RegisterPropertyToSkip(TPersistent, 'ThumbLength', 'Delphi TTrackBar', '');
  RegisterPropertyToSkip(TPersistent, 'SelEnd', 'Delphi TTrackBar', '');
  RegisterPropertyToSkip(TPersistent, 'SelStart', 'Delphi TTrackBar', '');
  RegisterPropertyToSkip(TPersistent, 'SliderVisible', 'Delphi TTrackBar', '');
  RegisterPropertyToSkip(TPersistent, 'ItemHeight', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Smooth', 'Delphi TProgressBar', '');
  RegisterPropertyToSkip(TPersistent, 'SmoothReverse', 'Delphi TProgressBar', '');
  RegisterPropertyToSkip(TPersistent, 'WordWrap', 'Delphi TButton', '');
  RegisterPropertyToSkip(TPersistent, 'BorderWidth', 'Delphi TRichEdit', '');
  RegisterPropertyToSkip(TPersistent, 'BiDiMode', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'ParentBiDiMode', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'Pen.Mode', 'Delphi-specific', '');
  RegisterPropertyToSkip(TPersistent, 'TabOrder', 'TGraphicControl has no TabOrder', '');

  try
    Application.Initialize;
    Application.Title := 'Mandelbulb 3D';
    {$IFDEF FPC}
    HeadlessParseArgs;
    if HeadlessMode then
      Application.ShowMainForm := False;
    {$ENDIF}
    {$I+}
    Assign(LogFile, 'mb3d_startup.log');
    Rewrite(LogFile);
    StartupLogFilePtr := @LogFile;
    Application.OnException := TStartupExceptionHandler.HandleException;
    WriteLn(LogFile, 'Creating Mand3DForm...'); Flush(LogFile);
    Application.CreateForm(TMand3DForm, Mand3DForm);
    WriteLn(LogFile, 'Creating LightAdjustForm...'); Flush(LogFile);
    Application.CreateForm(TLightAdjustForm, LightAdjustForm);
    WriteLn(LogFile, 'Creating FNavigator...'); Flush(LogFile);
    Application.CreateForm(TFNavigator, FNavigator);
    WriteLn(LogFile, 'Creating AnimationForm...'); Flush(LogFile);
    Application.CreateForm(TAnimationForm, AnimationForm);
    WriteLn(LogFile, 'Creating AniPreviewForm...'); Flush(LogFile);
    Application.CreateForm(TAniPreviewForm, AniPreviewForm);
    WriteLn(LogFile, 'Creating AniProcessForm...'); Flush(LogFile);
    Application.CreateForm(TAniProcessForm, AniProcessForm);
    WriteLn(LogFile, 'Creating MapSequencesFrm...'); Flush(LogFile);
    Application.CreateForm(TMapSequencesFrm, MapSequencesFrm);
    WriteLn(LogFile, 'Creating FormulaGUIForm...'); Flush(LogFile);
    Application.CreateForm(TFormulaGUIForm, FormulaGUIForm);
    WriteLn(LogFile, 'Creating ColorForm...'); Flush(LogFile);
    Application.CreateForm(TColorForm, ColorForm);
    WriteLn(LogFile, 'Creating BatchForm1...'); Flush(LogFile);
    Application.CreateForm(TBatchForm1, BatchForm1);
    WriteLn(LogFile, 'Creating BulbTracer2Frm...'); Flush(LogFile);
    Application.CreateForm(TBulbTracer2Frm, BulbTracer2Frm);
    WriteLn(LogFile, 'Creating FormulaEditor...'); Flush(LogFile);
    Application.CreateForm(TFormulaEditor, FormulaEditor);
    WriteLn(LogFile, 'Creating TilingForm...'); Flush(LogFile);
    Application.CreateForm(TTilingForm, TilingForm);
    WriteLn(LogFile, 'Creating MCForm...'); Flush(LogFile);
    Application.CreateForm(TMCForm, MCForm);
    WriteLn(LogFile, 'Creating FTextBox...'); Flush(LogFile);
    Application.CreateForm(TFTextBox, FTextBox);
    WriteLn(LogFile, 'Creating BRInfoForm...'); Flush(LogFile);
    Application.CreateForm(TBRInfoForm, BRInfoForm);
    WriteLn(LogFile, 'Creating ScriptEditorForm...'); Flush(LogFile);
    Application.CreateForm(TScriptEditorForm, ScriptEditorForm);
    WriteLn(LogFile, 'Creating FColorOptions...'); Flush(LogFile);
    Application.CreateForm(TFColorOptions, FColorOptions);
    WriteLn(LogFile, 'Creating MapCalcWindow...'); Flush(LogFile);
    Application.CreateForm(TMapCalcWindow, MapCalcWindow);
    WriteLn(LogFile, 'Creating MutaGenFrm...'); Flush(LogFile);
    Application.CreateForm(TMutaGenFrm, MutaGenFrm);
    WriteLn(LogFile, 'Creating IniDirForm...'); Flush(LogFile);
    Application.CreateForm(TIniDirForm, IniDirForm);
    WriteLn(LogFile, 'Creating VisualThemesFrm...'); Flush(LogFile);
    Application.CreateForm(TVisualThemesFrm, VisualThemesFrm);
    WriteLn(LogFile, 'Creating JITFormulaEditorForm...'); Flush(LogFile);
    Application.CreateForm(TJITFormulaEditorForm, JITFormulaEditorForm);
    WriteLn(LogFile, 'Creating ParamValueEditFrm...'); Flush(LogFile);
    Application.CreateForm(TParamValueEditFrm, ParamValueEditFrm);
    WriteLn(LogFile, 'Creating FVoxelExport...'); Flush(LogFile);
    Application.CreateForm(TFVoxelExport, FVoxelExport);
    WriteLn(LogFile, 'Creating MeshPreviewFrm...'); Flush(LogFile);
    Application.CreateForm(TMeshPreviewFrm, MeshPreviewFrm);
    WriteLn(LogFile, 'Creating HeightMapGenFrm...'); Flush(LogFile);
    Application.CreateForm(THeightMapGenFrm, HeightMapGenFrm);
    WriteLn(LogFile, 'Creating PostProForm...'); Flush(LogFile);
    Application.CreateForm(TPostProForm, PostProForm);
    WriteLn(LogFile, 'Creating ZBuf16BitGenFrm...'); Flush(LogFile);
    Application.CreateForm(TZBuf16BitGenFrm, ZBuf16BitGenFrm);
    WriteLn(LogFile, 'All forms created. Starting Application.Run...'); Flush(LogFile);
    CloseFile(LogFile);
    StartupLogFilePtr := nil;
    Application.OnException := nil;
    Application.Run;
  except
    on E: Exception do
    begin
      Application.ShowException(E);
      Halt(1);
    end;
  end;
end.
