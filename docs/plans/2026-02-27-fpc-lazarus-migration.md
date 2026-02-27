# Delphi → FPC/Lazarus Migration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate Mandelbulb 3D from Delphi to Free Pascal + Lazarus so the entire project builds with free tools (Win32 only).

**Architecture:** Incremental migration — each task produces a compilable (or closer-to-compilable) state. VCL → LCL, JEDI VCL → standard LCL components, PAX Compiler disabled, ASM blocks adapted for FPC Intel syntax. No functional changes to rendering or formulas.

**Tech Stack:** Free Pascal Compiler (FPC) 3.2+, Lazarus 3.x, Win32 target, `{$mode delphi}`, `{$asmmode intel}`

**Design doc:** `docs/plans/2026-02-27-fpc-lazarus-migration-design.md`

---

## Task 1: Create Lazarus project files

**Files:**
- Create: `Mandelbulb3D.lpr`
- Create: `Mandelbulb3D.lpi`
- Modify: `Mandelbulb3D.dpr` (reference only — do not delete)

**Step 1: Create `Mandelbulb3D.lpr`**

Copy `Mandelbulb3D.dpr` to `Mandelbulb3D.lpr` and adapt:

```pascal
program Mandelbulb3D;

{$mode delphi}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // LCL widgetset
  Forms,
  Mand in 'Mand.pas' {Mand3DForm},
  LightAdjust in 'LightAdjust.pas' {LightAdjustForm},
  // ... (all other units from .dpr, unchanged)
  ;

{$R *.res}

begin
  Application.Initialize;
  Application.Title := 'Mandelbulb 3D';
  Application.CreateForm(TMand3DForm, Mand3DForm);
  // ... (all other CreateForm calls, unchanged)
  Application.Run;
end.
```

Key changes from .dpr:
- Add `{$mode delphi}` at top
- Add `Interfaces` to uses (required by LCL)
- Remove `{$RTTI EXPLICIT METHODS([]) FIELDS([]) PROPERTIES([])}` (Delphi-specific)
- Remove `{$WeakLinkRTTI ON}` (Delphi-specific)
- Remove `{$SetPEFlags $20}` (Delphi-specific; for FPC use `-WB` linker flag or `{$APPTYPE GUI}`)
- Remove `SetMinimumBlockAlignment(mba16Byte)` (not available in FPC)
- Remove `Vcl.Themes` and `Vcl.Styles` from uses (no LCL equivalent needed)

**Step 2: Create initial `.lpi` project file**

Use Lazarus IDE: File → New Project → Application, then manually add all units. Or use the Lazarus Delphi converter: Tools → Convert Delphi Project → select `Mandelbulb3D.dpr`.

The converter will auto-generate the `.lpi` XML.

**Step 3: Commit**

```bash
git add Mandelbulb3D.lpr Mandelbulb3D.lpi
git commit -m "feat: add Lazarus project files for FPC migration"
```

---

## Task 2: Add `{$mode delphi}` and `{$asmmode intel}` to all units

**Files:** All 123 `.pas` files in the project

**Step 1: Add `{$mode delphi}` after `unit` / `interface` line in every `.pas` file**

Every unit must start with:
```pascal
unit SomeUnit;

{$mode delphi}

interface
```

For units with inline assembly, also add:
```pascal
{$asmmode intel}
```

**ASM files (27 files) needing `{$asmmode intel}`:**
- `AmbHiQ.pas`
- `AmbShadowCalcThread.pas`
- `AmbShadowCalcThreadN.pas`
- `Calc.pas`
- `CalcAmbShadowDE.pas`
- `CalcHardShadow.pas`
- `CalcMonteCarlo.pas`
- `CalcPart.pas`
- `CalcThread.pas`
- `CalcThread2D.pas`
- `CalcVoxelSliceThread.pas`
- `ColorSSAO.pas`
- `DivUtils.pas`
- `DOF.pas`
- `FFT.pas`
- `formulas.pas`
- `ImageProcess.pas`
- `LightAdjust.pas`
- `Mand.pas`
- `Math3D.pas`
- `Monitor.pas`
- `NaviCalcThread.pas`
- `PaintThread.pas`
- `Paint.pas`
- `calcBlocky.pas`
- `CalcSR.pas`
- `attic/FastMM4.pas` (if included)

**Step 2: Remove Delphi-specific directives**

In `Mandelbulb3D.dpr` (or wherever found):
- Remove `{$CODEALIGN 8}` from `Calc.pas` line 49 (FPC may not support this; use `{$ALIGN 8}` if needed)
- Remove `{$CODEALIGN 16}` from `DivUtils.pas` line 130 (replace with `{$ALIGN 16}` if FPC supports it)

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add {mode delphi} and {asmmode intel} to all units"
```

---

## Task 3: Replace `Vcl.*` namespace prefixes (27 files)

All `Vcl.*` namespaced unit references must become plain unit names (LCL uses non-namespaced names identical to pre-2010 Delphi).

**Step 1: Replace `Winapi.*` and `System.*` prefixes**

8 files use the modern Delphi namespaced form. Replace:

| Old | New |
|-----|-----|
| `Winapi.Windows` | `Windows` |
| `Winapi.Messages` | `Messages` |
| `System.SysUtils` | `SysUtils` |
| `System.Variants` | `Variants` |
| `System.Classes` | `Classes` |

Files: `ColorOptionForm.pas`, `JITFormulaEditGUI.pas`, `ParamValueEditGUI.pas`, `HeightMapGenUI.pas`, `MutaGenGUI.pas`, `MeshPreviewUI.pas`, `uMapCalcWindow.pas`, `ZBuf16BitGenUI.pas`

**Step 2: Replace `Vcl.*` prefixes**

Global search-and-replace across all `.pas` files:

| Old | New |
|-----|-----|
| `Vcl.Graphics` | `Graphics` |
| `Vcl.Controls` | `Controls` |
| `Vcl.Forms` | `Forms` |
| `Vcl.Dialogs` | `Dialogs` |
| `Vcl.StdCtrls` | `StdCtrls` |
| `Vcl.ExtCtrls` | `ExtCtrls` |
| `Vcl.ComCtrls` | `ComCtrls` |
| `Vcl.Buttons` | `Buttons` |
| `Vcl.ImgList` | `ImgList` |
| `Vcl.Grids` | `Grids` |
| `Vcl.Menus` | `Menus` |
| `Vcl.Tabs` | `Tabs` |

**Step 3: Remove `Vcl.Themes` and `Vcl.Styles`**

These have no LCL equivalent. Remove from:
- `Mandelbulb3D.lpr` (was in .dpr lines 65-66)
- `Mand.pas` line 552 — remove `Vcl.Themes,` from implementation uses
- `FileHandling.pas` line 94 — remove `Vcl.Themes,` from implementation uses
- `prefs/VisualStylesGUI.pas` line 33 — remove `Vcl.Themes;`
- `prefs/VisualThemesGUI.pas` line 35 — remove `Vcl.Themes,`

**Step 4: Handle `Vcl.ExtDlgs`**

`Vcl.ExtDlgs` provides `TOpenPictureDialog` and `TSavePictureDialog`. In LCL these are in the `ExtDlgs` unit.

Replace `Vcl.ExtDlgs` → `ExtDlgs` in:
- `Mand.pas` line 9
- `FileHandling.pas` line 6 (`vcl.ExtDlgs`)
- `LightAdjust.pas` line 8
- `maps/MapSequencesGUI.pas` line 7
- `MonteCarloForm.pas` line 7

**Step 5: Handle `TCategoryPanel` override in `MutaGenGUI.pas`**

Line 30: `TCategoryPanel = class(Vcl.ExtCtrls.TCategoryPanel)` → change to `TCategoryPanel = class(ExtCtrls.TCategoryPanel)`.

Note: `TCategoryPanelGroup` and `TCategoryPanel` exist in LCL's ExtCtrls since Lazarus 2.0+. Verify availability. If not available, replace with `TPanel` + manual expand/collapse logic.

Also used in `MonteCarloForm.pas` and `MonteCarloForm.dfm`.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: replace Vcl/Winapi/System namespace prefixes with LCL equivalents"
```

---

## Task 4: Replace JEDI VCL components (5 files)

### 4a: `MutaGenGUI.pas` — heaviest JEDI usage

**Files:**
- Modify: `mutagen/MutaGenGUI.pas` (lines 22-27 uses clause, lines 72-80 component declarations)
- Modify: `mutagen/MutaGenGUI.dfm` → `.lfm`

**Step 1: Replace uses clause (lines 22-27)**

Remove all `Jv*` units:
```
JvExForms, JvCustomItemViewer, JvImagesViewer, JvComponentBase,
JvFormAnimatedIcon, JvExComCtrls, JvProgressBar, JvComCtrls,
JvxSlider, JvExControls, JvSlider, JvExStdCtrls, JvGroupBox,
JvOutlookBar, JvExExtCtrls, JvExtComponent, JvCaptionPanel,
JvPageList, JvNavigationPane, JvClipboardMonitor
```

Replace with standard units already imported (`StdCtrls`, `ComCtrls`, `ExtCtrls`, `Buttons`).

**Step 2: Replace component types**

In `.pas` (field declarations) and `.dfm`/`.lfm` (component objects):

| Old | New | Instances |
|-----|-----|-----------|
| `TJvGroupBox` | `TGroupBox` | `GenerationsGrp`, `MutateGrp`, `OptionsGrp` |

Remove the `PropagateEnable = True` property from each (TGroupBox doesn't have this). These are non-critical UI enhancements.

**Step 3: Commit**

```bash
git add mutagen/MutaGenGUI.pas mutagen/MutaGenGUI.lfm
git commit -m "feat: replace JEDI VCL with standard LCL in MutaGenGUI"
```

### 4b: `MeshPreviewUI.pas` — 9 TJvOfficeColorButton instances

**Files:**
- Modify: `opengl/MeshPreviewUI.pas` (lines 23-24, 36-55)
- Modify: `opengl/MeshPreviewUI.dfm` → `.lfm`

**Step 1: Replace uses clause (lines 23-24)**

Remove: `JvExExtCtrls, JvExtComponent, JvOfficeColorButton, JvExControls, JvColorBox, JvColorButton`

Add (if not present): `Dialogs` (for TColorDialog)

**Step 2: Replace `TJvOfficeColorButton` → `TColorButton`**

9 instances: `SurfaceColorBtn`, `EdgesColorBtn`, `WireframeColorBtn`, `PointsColorBtn`, `MatAmbientColorBtn`, `MatDiffuseColorBtn`, `MatSpecularColorBtn`, `LightAmbientBtn`, `LightDiffuseBtn`

In `.pas`: change type declarations from `TJvOfficeColorButton` to `TColorButton`.

In `.dfm`/`.lfm`: replace `TJvOfficeColorButton` with `TColorButton`. Remove all JEDI-specific properties (`HotTrackFont.*`, `Properties.*` sub-object). Map:
- `SelectedColor` → `ButtonColor`
- `OnColorChange` → `OnColorChanged`

**Step 3: Verify event handlers**

The `OnColorChange` event handlers (e.g., `SurfaceColorBtnColorChange`) need their parameter signatures checked. TColorButton's `OnColorChanged` uses `Sender: TObject` — should be compatible.

**Step 4: Commit**

```bash
git add opengl/MeshPreviewUI.pas opengl/MeshPreviewUI.lfm
git commit -m "feat: replace JEDI VCL with standard LCL in MeshPreviewUI"
```

### 4c: `HeightMapGenUI.pas` and `ZBuf16BitGenUI.pas`

Same pattern as 4b — these files use the same JEDI units (`JvOfficeColorButton`, `JvColorBox`, `JvColorButton`). Apply identical replacements.

### 4d: `BulbTracer2UI.pas`

Uses only `JvExStdCtrls`, `JvGroupBox`. Replace `TJvGroupBox` → `TGroupBox` (same as 4a pattern).

**Commit each file separately for easy review.**

---

## Task 5: Disable PAX Compiler

**Files:**
- Modify: `Mandelbulb3D.lpi` (project defines)
- Verify: `formula/FormulaCompiler.pas`
- Verify: `script/ScriptCompiler.pas`
- Verify: `script/CompilerUtil.pas`

**Step 1: Remove `USE_PAX_COMPILER` from project defines**

In `.lpi` custom options / defines section, ensure `USE_PAX_COMPILER` is NOT listed.

Also remove from project defines:
- `JIT_FORMULA_PREPROCESSING` (depends on PAX)

Keep:
- `PARAMS_PER_THREAD` (independent feature)

**Step 2: Verify conditional compilation**

`FormulaCompiler.pas` should have `{$IFDEF USE_PAX_COMPILER}` guards around all PAX imports and classes. With the define removed, these sections are excluded.

Check that `ScriptCompiler.pas` and `CompilerUtil.pas` also have proper `{$IFDEF}` guards. If not, add them or stub out the PAX-dependent code.

**Step 3: Remove PAX search paths**

Remove from project configuration:
```
D:\DEV\Delphi_Workspace\PaxCompiler\mb3d\Sources
D:\DEV\Delphi_Workspace\PaxCompiler\mb3d\
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: disable PAX Compiler - remove USE_PAX_COMPILER define"
```

---

## Task 6: Convert form files (.dfm → .lfm)

**Files:** All 30 `.dfm` files

**Step 1: Ensure all .dfm files are in text format**

Check each `.dfm` — if it starts with `object` (text) or binary bytes. Modern Delphi uses text format by default.

```bash
# Check if files are text (first bytes should be readable ASCII)
file *.dfm bulbtracer2/*.dfm opengl/*.dfm mutagen/*.dfm heightmapgen/*.dfm zbuf16bit/*.dfm maps/*.dfm prefs/*.dfm formula/*.dfm script/*.dfm
```

**Step 2: Convert using Lazarus converter**

Use Lazarus IDE: Tools → Convert Delphi Project. Or manually:
1. Copy each `.dfm` to `.lfm`
2. Replace `{$R *.dfm}` with `{$R *.lfm}` in corresponding `.pas` files
3. Remove Delphi-specific properties that LCL doesn't support

**Step 3: Remove unsupported properties**

Common Delphi properties to remove from `.lfm`:
- `ExplicitWidth`, `ExplicitHeight`, `ExplicitLeft`, `ExplicitTop`
- `DesignSize`
- `Margins.*` (LCL uses `BorderSpacing` instead)
- `ParentDoubleBuffered`
- `Touch.*` (touch/gesture support)
- `GlassFrame.*`
- Properties of replaced JEDI components (already handled in Task 4)

**Step 4: Handle `TCategoryPanelGroup` in `MonteCarloForm.dfm`**

Check if LCL supports `TCategoryPanelGroup`. If not, replace with `TPanel` containers + `TGroupBox` for each category.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: convert all .dfm form files to .lfm format"
```

---

## Task 7: Replace bundled PNG unit with LCL native

**Files:**
- Modify: `FileHandling.pas` (lines 5, 1178-1255)
- Modify: `Mand.pas` (line 551 — remove `pngimage` from uses)
- Modify: `maps/Maps.pas` (line 7 — remove `pngimage` from uses)
- Delete: `pngimage.pas`, `pnglang.pas`, `pngzlib.pas`
- Delete: `GifImage.pas` (unused — confirmed no imports)

**Step 1: Update `FileHandling.pas` uses clause**

Line 5: Remove `pngimage` from uses. LCL's `Graphics` unit already provides PNG support via `TPortableNetworkGraphic`.

**Step 2: Rewrite `SavePNG` (lines 1178-1199)**

```pascal
procedure SavePNG(FileName: String; bmp: TBitmap; SaveTXTparas: Boolean);
var
  png: TPortableNetworkGraphic;
  s: AnsiString;
begin
  png := TPortableNetworkGraphic.Create;
  try
    png.Assign(bmp);
    // Note: TPortableNetworkGraphic does not support AddtEXt metadata.
    // If SaveTXTparas is needed, we'll need to write raw PNG chunks manually
    // or use a third-party FPC PNG library. For now, skip metadata.
    png.SaveToFile(ChangeFileExtSave(FileName, '.png'));
  finally
    png.Free;
  end;
end;
```

**Important caveat:** The original code uses `TPNGObject.AddtEXt('Comment', s)` to embed Mandelbulb3D parameters as PNG metadata. `TPortableNetworkGraphic` does NOT support this. Options:
- Accept loss of embedded metadata (simplest)
- Use `fcl-image` `TFPWriterPNG` which supports custom chunks
- Write a small helper to append tEXt chunks to the PNG file after saving

**Step 3: Rewrite `SavePNG2FStream` (lines 1201-1214)**

```pascal
procedure SavePNG2FStream(FileName: String; bmp: TBitmap; FS: TFileStream);
var
  png: TPortableNetworkGraphic;
begin
  png := TPortableNetworkGraphic.Create;
  try
    png.Assign(bmp);
    png.SaveToStream(FS);
  finally
    png.Free;
  end;
end;
```

**Step 4: Rewrite `Save1bitPNG` (lines 1216-1255)**

Similar pattern — create `TPortableNetworkGraphic`, assign the 1-bit bitmap, save. The palette creation logic (CreatePalette, pf1bit) is Windows API and should work with FPC.

**Step 5: Remove unused files**

```bash
git rm pngimage.pas pnglang.pas pngzlib.pas GifImage.pas
```

**Step 6: Commit**

```bash
git add FileHandling.pas Mand.pas maps/Maps.pas
git commit -m "feat: replace bundled pngimage with LCL native PNG support"
```

---

## Task 8: Handle custom components (SpeedButtonEx, TrackBarEx, ListBoxEx)

**Files:**
- Modify: `SpeedButtonEx.pas`
- Modify: `TrackBarEx.pas`
- Modify: `ListBoxEx.pas`

**Step 1: Add `{$mode delphi}` (already done in Task 2)**

**Step 2: Check parent class references**

These custom components extend standard VCL classes:
- `TSpeedButtonEx` extends `TSpeedButton` — exists in LCL
- `TTrackBarEx` extends `TTrackBar` — exists in LCL
- `TListBoxEx` extends `TListBox` — exists in LCL

Check for any Delphi-specific method overrides or Windows message handling that may differ in LCL. Likely issues:
- `CM_MOUSEENTER` / `CM_MOUSELEAVE` messages — LCL uses different message IDs
- Canvas drawing methods — may differ slightly

**Step 3: Fix LCL message constant differences**

If custom components handle Windows messages directly, replace:
- `CM_MOUSEENTER` → `CM_MOUSEENTER` (same in LCL)
- `WM_PAINT`, `WM_ERASEBKGND` etc. — same in LCL for Win32 widgetset

**Step 4: Commit**

```bash
git add SpeedButtonEx.pas TrackBarEx.pas ListBoxEx.pas
git commit -m "fix: adapt custom components for LCL compatibility"
```

---

## Task 9: Adapt inline assembly for FPC (27 files, 314 blocks)

This is the largest task. Work file-by-file, starting with the most critical.

### General FPC ASM rules (reference for all files):

1. **`{$asmmode intel}`** must be present (done in Task 2)
2. **Local variable access**: FPC may require explicit `[ebp-offset]` vs Delphi's implicit. Usually works the same in `{$mode delphi}`.
3. **Size specifiers**: FPC may be stricter about operand sizes. E.g., `mov word [edx], $8000` may need `mov word ptr [edx], $8000`.
4. **`{$CODEALIGN}`**: Replace with `{$ALIGN}` or remove if FPC doesn't support it.
5. **MMX cleanup**: `emms` instruction required after MMX — already present in the code.

### 9a: Math3D.pas (97 blocks — vector/matrix math)

Most blocks are SSE optimizations for vector operations. Pattern:
```pascal
if SupportSSE then
asm
  movss xmm0, [eax]
  // ...
end
else begin
  // Pascal fallback
end;
```

FPC should handle these with `{$asmmode intel}`. Test compilation, fix syntax issues one at a time.

### 9b: formulas.pas (41 blocks — fractal formulas)

Critical for correctness. Each formula has assembly for performance. Compile and verify each formula produces identical output.

### 9c–9g: Remaining files

Apply same pattern: compile, fix FPC assembler syntax errors, test.

**Commit after each file is fixed:**

```bash
git add Math3D.pas
git commit -m "fix: adapt Math3D.pas inline assembly for FPC"
```

---

## Task 10: Handle Vcl.Themes integration points

**Files:**
- Modify: `prefs/VisualThemesGUI.pas`
- Modify: `prefs/VisualStylesGUI.pas`
- Modify: `Mand.pas` (theme-related code)
- Modify: `FileHandling.pas` (theme-related code)

**Step 1: Stub out or replace theme code**

Delphi `Vcl.Themes` provides `TStyleManager` for VCL Styles. LCL doesn't have an equivalent — it uses native OS themes.

In `VisualThemesGUI.pas` and `VisualStylesGUI.pas`:
- Remove/comment out `TStyleManager` calls
- Replace theme enumeration with a simple "Default" option
- The visual themes feature will be limited but the UI remains functional

In `Mand.pas` and `FileHandling.pas`:
- Remove theme-related imports and calls that reference `Vcl.Themes`

**Step 2: Commit**

```bash
git add prefs/VisualThemesGUI.pas prefs/VisualStylesGUI.pas Mand.pas FileHandling.pas
git commit -m "feat: stub out Vcl.Themes - use native OS theme in LCL"
```

---

## Task 11: OpenGL bindings

**Files:**
- Check: `opengl/dglOpenGL.pas` (37,000+ lines)
- Check: `opengl/opengl12.pas`
- Check: `opengl/ShaderUtil.pas`, `MeshPreview.pas`, `MeshPreviewUI.pas`, `OpenGLPreviewUtil.pas`

**Step 1: Verify dglOpenGL.pas compiles with FPC**

The dglOpenGL header translation claims FPC compatibility. Add `{$mode delphi}` and attempt compilation. If it fails, replace with FPC's native `gl`, `glu`, `glext` units.

**Step 2: If replacing, update imports**

Change `uses dglOpenGL` to `uses gl, glu, glext` in:
- `opengl/MeshPreview.pas`
- `opengl/MeshPreviewUI.pas`
- `opengl/ShaderUtil.pas`
- `opengl/OpenGLPreviewUtil.pas`
- `heightmapgen/HeightMapGenPreview.pas`

Function names are identical (they're all OpenGL API), only the unit names change.

**Step 3: Commit**

```bash
git add opengl/
git commit -m "fix: adapt OpenGL bindings for FPC"
```

---

## Task 12: First compilation attempt and iterative fixes

**Step 1: Open project in Lazarus IDE**

Open `Mandelbulb3D.lpi`, set target to Win32, attempt Build (Ctrl+F9).

**Step 2: Fix errors iteratively**

Expect errors in categories:
1. **Missing units** — find LCL equivalents or add FPC-specific units
2. **Syntax differences** — FPC is stricter about some constructs
3. **Assembly errors** — fix one block at a time
4. **Type mismatches** — especially around string types and pointer casts
5. **Missing properties** — LCL components may lack some Delphi-specific properties

**Step 3: Common FPC fixes to expect**

| Delphi | FPC Fix |
|--------|---------|
| `Cardinal(Pointer)` | `PtrUInt(Pointer)` |
| `Integer(Pointer)` | `PtrInt(Pointer)` |
| `NativeInt` | `PtrInt` |
| `NativeUInt` | `PtrUInt` |
| `SHFolder` unit | `ShlObj` or Windows API directly |
| `FileCtrl` unit | `FileUtil` (LCL) or `LazFileUtils` |
| `AnsiStrings` unit functions | Often in `SysUtils` in FPC |

**Step 4: Commit working compilable state**

```bash
git add -A
git commit -m "feat: first successful FPC compilation"
```

---

## Task 13: Smoke test

**Step 1: Launch application**

Run the compiled `Mandelbulb3D.exe`. Verify:
- Main window opens
- Menu and toolbar are functional
- Can load a default parameter set

**Step 2: Test basic rendering**

- Click Calculate — verify a fractal renders
- Test a few built-in formulas (Integer Power 2, Amazing Box)
- Save as PNG — verify file is created and valid

**Step 3: Test post-processing**

- Apply ambient shadows
- Apply hard shadows
- Test DOF
- Save result

**Step 4: Test sub-windows**

- Open 3D Navigator
- Open Animation window
- Open BulbTracer2
- Open Monte Carlo renderer
- Open Height Map Generator
- Open MutaGen

**Step 5: Document any regressions**

Create issues or notes for each regression found. Prioritize by severity.

**Step 6: Final commit**

```bash
git add -A
git commit -m "milestone: MB3D builds and runs on FPC/Lazarus"
```

---

## Summary: Task Dependency Graph

```
Task 1 (project files)
  └─→ Task 2 ({$mode delphi})
       ├─→ Task 3 (Vcl.* prefixes)
       │    ├─→ Task 4 (JEDI VCL)
       │    ├─→ Task 6 (.dfm → .lfm)
       │    └─→ Task 10 (Vcl.Themes)
       ├─→ Task 5 (PAX disable)
       ├─→ Task 7 (PNG replacement)
       ├─→ Task 8 (custom components)
       ├─→ Task 9 (ASM adaptation)
       └─→ Task 11 (OpenGL)
            └─→ Task 12 (compile & fix)
                 └─→ Task 13 (smoke test)
```

Tasks 3-11 can be done in parallel after Task 2. Task 12 requires all prior tasks. Task 13 requires Task 12.
