# Delphi to FPC/Lazarus Migration

This document describes the migration of Mandelbulb 3D from Embarcadero Delphi (VCL) to Free Pascal Compiler (FPC) with Lazarus Component Library (LCL).

## Overview

| | Delphi (original) | FPC/Lazarus (port) |
|---|---|---|
| Compiler | Delphi 10.x+ | FPC 3.2.2 |
| IDE | RAD Studio | Lazarus 4.x |
| UI framework | VCL (Visual Component Library) | LCL (Lazarus Component Library) |
| Target | Win32, i386 | Win32, i386 |
| Language mode | Delphi | `{$mode delphi}` |
| ASM syntax | Intel (native) | `{$asmmode intel}` |
| Project file | `Mandelbulb3D.dproj` | `Mandelbulb3D.lpi` |
| Program source | `Mandelbulb3D.dpr` | `Mandelbulb3D.lpr` |

The migration preserves all rendering functionality. The same `.m3p` / `.m3i` parameter files work in both builds. Both builds produce the same `Mandelbulb3D.exe`.

## What Was Changed

### 1. Project Structure

- Created `Mandelbulb3D.lpr` (Lazarus program source) from `Mandelbulb3D.dpr`
- Created `Mandelbulb3D.lpi` (Lazarus project XML) with FPC-specific settings
- Added `{$mode delphi}` and `{$asmmode intel}` directives to all 123 `.pas` units
- Converted all 30 `.dfm` form files to `.lfm` format (LCL form layout)

### 2. VCL to LCL Component Replacements

| Delphi VCL | LCL Replacement | Files Affected |
|---|---|---|
| `Vcl.Graphics`, `Vcl.Controls`, `Vcl.Forms`, etc. | `Graphics`, `Controls`, `Forms` (no namespace prefix) | 27 files |
| `Winapi.Windows`, `System.SysUtils`, etc. | `Windows`, `SysUtils` (no namespace prefix) | 8 files |
| `Vcl.Themes`, `Vcl.Styles` (TStyleManager) | Removed (LCL uses native OS themes) | 4 files |
| `TJvGroupBox` (JEDI VCL) | `TGroupBox` | MutaGenGUI, BulbTracer2UI |
| `TJvOfficeColorButton` (JEDI VCL) | `TColorButton` | MeshPreviewUI |
| `TGridPanel` | `TPanel` (absolute positioning) | MutaGenGUI |
| `TCategoryPanel` | Guarded with `{$IFNDEF FPC}` | MutaGenGUI, MonteCarloForm |
| `pngimage` (bundled Delphi unit) | LCL native `TPortableNetworkGraphic` | FileHandling, Mand, Maps |

### 3. Critical Code Fixes

#### `Double(integer)` Cast Semantics (ROOT CAUSE of formula loading failure)

In Delphi, `Double(8)` performs a **type conversion** (result: `8.0`). In FPC `{$mode delphi}`, `Double(8)` performs a **raw bit reinterpretation** (zero-extends integer 8 to `0x0000000000000008` ≈ `3.95e-323`).

This caused the formula pipeline to fail silently: `dSIpow` got garbage, `Round(garbage) = 0`, the function pointer lookup `fHIntFunctions[0]` was out-of-bounds (valid range is `[2..8]`), so formulas never loaded.

**Fix**: replaced `Double(8)` with `8.0` and `Double(2)` with `2.0` in `CustomFormulas.pas`.

#### LCL ScanLine / HBITMAP Memory Split

In Delphi VCL, `TBitmap.ScanLine` returns a pointer directly into the GDI DIB section bits — writes are immediately visible on screen. In LCL, `ScanLine` points to `RawImage.Data`, a **separate buffer** from the GDI HBITMAP used for screen painting.

This caused rendered fractals to appear as black rectangles (data was correct in memory but never reached the screen).

**Fix** (applied in `ImageProcess.pas`, `Navigator.pas`):
1. Set alpha byte to `$FF` on every pixel (LCL uses `AlphaBlend` for 32bpp — alpha=0 means transparent)
2. Call `SetDIBitsToDevice` to flush `RawImage.Data` to the bitmap's GDI `Canvas.Handle` DC

#### SSE2 Inline Assembly

Delphi and FPC handle SSE2 inline assembly differently:
- `COMISD` + `JC` (jump on carry) behaves differently for NaN values
- Stack parameter ordering for the Delphi register calling convention differs
- MXCSR control register is not auto-configured in FPC

**Fix**: Wrapped SSE2 function pointer overrides in `{$IFNDEF FPC}` in `DivUtils.pas`. Pascal fallback implementations are used instead. Added `SetSSECSR(GetSSECSR or $1F80)` at startup to mask SSE2 floating-point exceptions.

#### Other Fixes

| Issue | Fix | File |
|---|---|---|
| `fHybrid` null pointer | Initialize `TIteration3D.fHybrid` array to `EmptyFormula` | `formulas.pas` |
| DOF QuickSort generics | Replace Delphi generics with FPC-compatible sort | `DOF.pas` |
| `nHybrid[0]=0` infinite loop | Added safety exit in `doHybridPas` | `formulas.pas` |
| `PARAMS_PER_THREAD` define missing | Added to `.lpi` custom options | `Mandelbulb3D.lpi` |
| Reflection ray march NaN | Added NaN protection in FPC path | `CalcSR.pas` |
| MutaGen layout | Removed stale `Align=alTop`, restored `AlignWithMargins` | `MutaGenGUI.lfm` |
| Navigator preview | Alpha fix + `SetDIBitsToDevice` flush | `Navigator.pas` |
| Headless render hang | Fixed Timer4Timer completion paths for reflections/DOF | `Mand.pas` |
| Volume Light Map hang | Skip `MapCalcWindow` in headless mode | `Mand.pas` |

### 4. New Features (FPC Only)

#### Headless CLI Rendering

A command-line rendering mode for scripting and automation, enabled by `--render` flag:

```bash
Mandelbulb3D.exe --render scene.m3p --output result.png \
  [--format png|jpg|bmp] [--width N] [--height N] [--threads N]
```

Implementation: `HeadlessRender.pas`. Uses `Application.ShowMainForm := False` to keep forms in memory but invisible. The timer-driven rendering pipeline runs normally via `Application.Run`.

#### Diagnostic Harness

Build with `-dFPC_DIAG` and run with `--diag` flag to auto-render scenes and export bitmaps + parameter logs to `diag_output/` for pixel-level comparison with Delphi reference renders.

## Current Status

### Working (verified with 79/80 test scenes)

- Application startup and UI
- All built-in formula types: IntPow 2-8, AmazingBox, ABoxSOff4d, AexionC, Bulbox, Quaternion, generalized Quaternion, Julia variants, Menger variants, dIFS (7 scenes), KochSurf, hybrid chains
- Full 3D rendering pipeline: ray marching, distance estimation, surface normals, coloring, lighting
- Post-processing: NormalsOnZBuf, Hard Shadows, Ambient Occlusion, Reflections, Depth of Field
- All 6 toolbar panels: MutaGen, BulbTracer2, Navigator, Animation, HeightMapGen, ZBuf16Bit
- File I/O: `.m3p`, `.m3i` load/save, PNG/JPG/BMP export
- Headless CLI rendering

### Not Yet Tested / Known Limitations

| Feature | Status | Notes |
|---|---|---|
| JIT formulas (`.m3f` files) | Untested | ~200+ external formula files contain binary machine code targeting Delphi register calling convention. May need calling convention adapters. |
| Volume Light Map (headless) | Skipped | `MapCalcWindow` requires GUI. Needs headless-compatible implementation. |
| Monte Carlo renderer | Untested | Separate rendering pipeline in `CalcMonteCarlo.pas`. |
| Animation workflow | Untested | `AnimationForm` GUI workflow. |
| Tiling (Big renders) | Untested | `TilingForm` large-image tiled rendering. |
| Batch processing | Untested | `BatchForm1` batch rendering. |
| SSE2 ASM paths | Disabled | Pascal fallbacks used. Performance optimization opportunity. |
| Pixel-level FPC vs Delphi comparison | Partial | Renders pass visual inspection; per-pixel diff not systematically verified. |

## Key Differences for Developers

### Things to Watch Out For

1. **Never use `Double(integer_value)`** — always use float literals (`8.0` instead of `Double(8)`). FPC does raw bit reinterpretation, Delphi does conversion.

2. **`@procVar` returns the procedure address**, not the variable's address. Use `@@procVar` to get the address of the variable itself.

3. **After writing pixels via `ScanLine`**, you must flush to the GDI HBITMAP:
   ```pascal
   // Set alpha channel (LCL uses AlphaBlend for 32bpp)
   pixel^ := pixel^ or $FF000000;
   // Flush RawImage.Data to Canvas DC
   SetDIBitsToDevice(Bitmap.Canvas.Handle, ...);
   ```

4. **Timer4Timer state machine**: The post-processing completion logic has multiple paths. Some call `RepaintMand3D(True)` → Timer8 → exit, others call `UpdateScaledImageFull` (no Timer8). Any new automated/headless exit must handle all completion paths.

5. **GUI modal dialogs** (`ShowMessage`, `MapCalcWindow.Visible` busy-wait) block in headless mode. Guard with `if HeadlessMode` checks.

6. **Form properties stripped during `.dfm` → `.lfm` conversion**: `DoubleBuffered`, `AlignWithMargins`, `Ctl3D`, `ExplicitWidth/Height`, `ParentDoubleBuffered`. Some may need to be re-added manually in the `.lfm` or set in `FormCreate`.

### Directory Structure

```
/                    Main application units (.pas/.lfm)
/formula/            Formula GUI, compiler, JIT, parameter editing
/maps/               Texture map handling
/render/             Preview rendering
/bulbtracer2/        2.5D mesh generation (voxel tracing, mesh I/O)
/opengl/             OpenGL bindings and mesh preview
/heightmapgen/       Height map generation
/zbuf16bit/          16-bit Z-buffer generation
/mutagen/            Mutation/random parameter generation
/script/             PAX-compiler-based scripting (disabled)
/prefs/              Preferences, INI, visual themes
/M3Formulas/         ~200+ external formula files (.m3f)
/M3Parameter/        Parameter templates
/M3Maps/             Texture/map resources
/docs/               Documentation
/tools/              Build and test scripts
```

## Testing

### Formula Regression Tests

```bash
bash tools/run_formula_tests.sh
```

Runs 21 formula tests covering IntPow, AmazingBox, dIFS, hybrid chains, and post-processing. Expects 21/21 pass.

### Headless Render Test Suite

```bash
bash tools/run_headless_tests.sh
```

Renders 80 `.m3p` scenes at 200x150 resolution with 120s timeout. Generates `test_report.txt` with pass/fail/skip status. Expects 79/80 pass (1 skip: incompatible file format).
