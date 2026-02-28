# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mandelbulb 3D (MB3D) is a Windows desktop application for generating 3D fractal renderings using distance estimation (DE) techniques. Written in Delphi/Object Pascal, targeting Win32 with VCL UI framework.

**Current version**: 1.9.9.37+

## Build

### Delphi (original)
- **IDE**: Open `Mandelbulb3D.dproj` in RAD Studio / Delphi, then Build (Shift+F9) or Run (F9)
- **Command line**: `msbuild Mandelbulb3D.dproj /p:Config=Release /p:Platform=Win32`

### FPC / Lazarus (migration in progress)
- **Build command**: `/c/lazarus/lazbuild.exe --cpu=i386 --os=win32 --compiler=/c/FPC/3.2.2/bin/i386-Win32/ppc386.exe --lazarusdir=/c/lazarus C:/work/mb3d/Mandelbulb3D.lpi`
- **FPC version**: 3.2.2, i386-Win32
- **Lazarus version**: 4.4
- **Project file**: `Mandelbulb3D.lpi` (Lazarus project, separate from Delphi `.dproj`)
- **Custom options**: `-Mdelphi -dPARAMS_PER_THREAD -dJIT_FORMULA_PREPROCESSING`

### Common
- **Entry point**: `Mandelbulb3D.dpr` / `Mandelbulb3D.lpr`
- **Output**: `Mandelbulb3D.exe`
- **No test suite exists** — verification is manual (screenshots, render output)

### Key compiler settings
- Stack: 16KB min / 16MB max (`-$M16384,16777216`)
- Large Address Aware flag set (`{$SetPEFlags $20}`)
- Weak RTTI / minimal RTTI reflection (`{$RTTI EXPLICIT METHODS([]) FIELDS([]) PROPERTIES([])}`)
- I/O checking OFF, range checking OFF, overflow checking OFF (performance-critical math)
- Active defines (Release): `PARAMS_PER_THREAD`, `JIT_FORMULA_PREPROCESSING`, `DEBUG_MESHEXP`
- Disabled defines: `USE_PAX_COMPILER` (commercial PAX Compiler dependency removed; all PAX code is guarded by `{$IFDEF USE_PAX_COMPILER}`)

## FPC/Lazarus Migration Status

### Completed
1. **Compilation** — builds successfully under FPC 3.2.2 / Lazarus 4.4
2. **Runtime startup** — app launches, UI loads correctly
3. **Property skip fix** — FPC's streaming skips unknown/incompatible Delphi properties gracefully
4. **fHybrid null pointer fix** — initialization of `TIteration3D.fHybrid` array to `EmptyFormula`
5. **DOF QuickSort fix** — replaced Delphi-specific generics with FPC-compatible sort
6. **SSE2 disable under FPC** — wrapped SSE2 function pointer overrides in `{$IFNDEF FPC}` in `DivUtils.pas`; Pascal fallbacks used instead (SSE2 asm uses Delphi-specific conventions: COMISD+JC infinite loop on NaN, stack param order differences, MXCSR not configured)
7. **MXCSR initialization** — added `SetSSECSR(GetSSECSR or $1F80)` for FPC to mask SSE2 FP exceptions
8. **PARAMS_PER_THREAD define** — added to `.lpi` (was missing; critical for per-thread MCTparas initialization including `nHybrid` formula counts)
9. **nHybrid[0]=0 infinite loop fix** — added safety exit in `doHybridPas` when all nHybrid values are 0

10. **`Double(integer)` cast fix** — FPC's `Double(8)` does raw bit reinterpretation (→ 3.95e-323), unlike Delphi which converts to 8.0. Fixed `Double(8)` → `8.0` and `Double(2)` → `2.0` in `CustomFormulas.pas:330`. This was the ROOT CAUSE of formulas not loading — `dSIpow` got garbage, `Round(garbage)=0`, `fHIntFunctions[0]` was out-of-bounds (array is [2..8]), so `pCodePointer` stayed nil/EmptyFormula.
11. **Formula pipeline now works** — After the Double() fix, `ParseCFfromOld` correctly sets `dSIpow=8`, loads `HybridIntP8`, and the formula executes correctly (modifies x,y,z, produces correct escape/bounded behavior).

12. **2D render fully working** — Formula iteration, RMdoColor (inline ASM), PaintThread coloring, and bitmap output all produce correct results. Verified 480×360 render of power-8 Mandelbulb 2D cross-section with smooth coloring.
13. **3D render fully working** — Full 3D ray marching pipeline works: distance estimation (CalcDE), surface normal calculation, RMdoColor ASM, PaintThread lighting/shading, bitmap output. Verified 480×360 3D Mandelbulb render with proper depth, surface normals, and lighting.
14. **Debug logging removed** — All temporary debug file I/O removed from CalcThread.pas, CalcThread2D.pas, Calc.pas, CustomFormulas.pas, formulas.pas, Mand.pas.

15. **Post-processing pipeline verified** — Full post-processing chain tested: NormalsOnZBuf (x=2), Hard Shadows (x=4), Ambient Occlusion (x=8) all execute correctly and complete without errors. Verified via diagnostic logging showing step-by-step progression through Timer4Timer state machine. Final rendered bitmap has rich colors with proper lighting/shading.

16. **UI display blit fix** — In FPC/LCL, `TBitmap.ScanLine` writes go to `RawImage.Data`, a separate buffer from the GDI HBITMAP used for screen painting (in Delphi VCL they share memory via DIB section). This caused the rendered fractal to be correct in memory but display as black. Fixed in `ImageProcess.pas` by: (a) setting alpha=0xFF in all 4 copy paths of `UpdateScaledImage` (LCL uses AlphaBlend for 32bpp — alpha=0 means transparent), and (b) calling `SetDIBitsToDevice` after each ScanLine copy loop (`UpdateScaledImage` and `doAA`) to push pixel data from `RawImage.Data` directly to the bitmap's `Canvas.Handle` DC.

### In Progress / Untested
- **Reflections (CalcSRT)**: Requires scene with reflective surfaces configured. Code reviewed — no FPC-specific issues found.
- **DOF (doDOF/doDOFsort)**: Requires scene with DOF settings. Code reviewed — no FPC-specific issues found.
- **JIT formulas (.m3f)**: External formula files not tested — may have calling convention issues.
- **Other formula types**: Only Integer Power 8 (HybridIntP8) tested. Other built-in formulas (quaternion, tricorn, Amazing Box, etc.) untested.

### Diagnostic Harness (feature/fpc-diag-harness branch)
Automated diagnostic tooling for pixel-level FPC vs Delphi comparison:
- **DiagHarness.pas** — Core harness unit, activated by `-dFPC_DIAG` compiler define + `--diag` CLI flag
- **DiagASMCheck.pas** — Pascal reference implementations for ASM routine spot-checks
- **tools/compare_bitmaps.ps1** — PowerShell pixel comparison (per-pixel RGB diff, stats, visual diff image)
- **tools/run_diag.bat** — Batch runner for 6 test matrix scenes

Usage: Build with `-dFPC_DIAG`, then run `Mandelbulb3D.exe --diag [scene.m3p]` to auto-render and save bitmap + parameter logs to `diag_output/`. Compare with Delphi reference renders using `compare_bitmaps.ps1`.

Test matrix scenes (in M3Parameter/): default (IntPow8), ABoxScale2Start (AmazingBox), Aexion 10bulbs (AexionC), BulboxCut (Bulbox), ApolloBalloons dIFS (dIFS), QuatP4hybridJulia (Quaternion).

### Key FPC vs Delphi Differences Found
- **`Double(integer)` cast** (CRITICAL): In FPC `{$mode delphi}`, `Double(8)` is a RAW BIT reinterpretation (zero-extends int 8 to 0x0000000000000008 ≈ 3.95e-323). In Delphi, it's a type conversion to 8.0. Always use `8.0` literal instead. Search for `Double(` followed by integer literals to find other instances.
- **`@procVar` operator**: In `{$mode delphi}`, `@procVar` returns the procedure address (the stored value), NOT the address of the variable. Use `@@procVar` for the variable's address.
- **SSE2 inline assembly**: Delphi's COMISD+JC handles NaN differently than FPC; MXCSR register not auto-configured
- **Stack parameter order**: Delphi register convention pushes remaining params LEFT-TO-RIGHT; FPC may differ
- **Defines**: Must manually add `-dPARAMS_PER_THREAD -dJIT_FORMULA_PREPROCESSING` in `.lpi` (Delphi `.dproj` has them)
- **Inline asm offsets**: FPC warns about `+offset(%ebp)` usage — assembly code using `[ebp+offset]` for stack params needs verification
- **LCL ScanLine / HBITMAP split** (CRITICAL): `TBitmap.ScanLine` in LCL writes to `RawImage.Data`, which is a **separate memory buffer** from the GDI HBITMAP used for screen painting. In Delphi VCL, `ScanLine` points directly to DIB section bits (shared memory). After writing pixels via ScanLine in LCL, you must call `SetDIBitsToDevice` on `Canvas.Handle` to push the data to the HBITMAP. Also, LCL uses `AlphaBlend` for 32bpp bitmaps, so the alpha byte must be set to `$FF` (Delphi VCL uses `BitBlt` which ignores alpha).

## Architecture

### Directory layout
```
/                    Root — main application units (.pas/.dfm)
/formula/            Formula GUI, compiler, JIT, parameter editing
/maps/               Texture map handling and map sequence UI
/render/             Preview rendering
/bulbtracer2/        2.5D mesh generation (voxel tracing, mesh I/O, OpenGL preview)
/opengl/             OpenGL bindings and mesh preview (dglOpenGL, shaders)
/heightmapgen/       Height map generation and PNM read/write
/zbuf16bit/          16-bit Z-buffer generation + Java PNG converter
/mutagen/            Mutation/random parameter generation
/script/             PAX-compiler-based scripting system
/facade/             MB3DFacade.pas — public API for external access
/prefs/              Preferences, INI directories, visual themes
/M3Formulas/         ~200+ external formula files (.m3f — binary machine code + metadata)
/M3Parameter/        Parameter templates
/M3Maps/             Texture/map resources
/shaders/            GLSL shader files
/attic/              Archived code (FastMM4 memory manager)
```

### Core rendering pipeline
1. **Parameter loading** — `FileHandling.pas` loads `.m3i`/`.m3p` files
2. **Formula setup** — `CustomFormulas.pas` + `formula/FormulaCompiler.pas` compile/load formulas; hybrid chains of up to 6 formulas
3. **Thread pool** — `ThreadUtils.pas` manages up to 64 worker threads (`TCalcThreadStats` records for coordination)
4. **Ray marching** — `Calc.pas` (`RayMarch()`, `CalcDEfull()`, `CalcDEanalytic()`) performs distance-estimation ray marching
5. **Worker threads** — `CalcThread.pas` (`TMandCalcThread`) runs per-thread iterations using `TIteration3Dext` structures
6. **Post-processing** — Hard shadows (`CalcHardShadow.pas`), ambient shadows (`AmbShadowCalcThreadN.pas`, `CalcAmbShadowDE.pas`, `AmbHiQ.pas`), DOF (`DOF.pas`), reflections
7. **Image output** — `ImageProcess.pas` for bitmap manipulation; output as BMP/PNG/JPEG

### Alternative renderers
- **Monte Carlo renderer** — `CalcMonteCarlo.pas` + `MonteCarloForm.pas`: physically-based path tracing (slower, photorealistic), supports network/batch rendering
- **BulbTracer2** — `bulbtracer2/`: voxel-based 2.5D mesh generation with OpenGL preview, mesh export

### Key data structures (in `TypeDefinitions.pas` and `Calc.pas`)
- `TIteration3Dext` — packed record (~408 bytes) holding iteration state: position (x,y,z,w), Julia constants, hybrid chain pointers, smooth iteration data, DE values, orbit trap data
- `TMCTparameter` — large record bundling ray march settings, DE thresholds, lighting, color mapping, post-processing flags
- `TCalcThreadStats` — packed record for thread pool coordination: processing type, thread count, per-thread stats array (64 slots), handle array
- `TCTrecord` — per-thread calculation counters (iteration count, DE steps, position, active status)

### Formula system
- **Internal formulas** — `formulas.pas` (integer powers 2-8, real power, quaternion, tricorn, Amazing Box, etc.)
- **External formulas** — `.m3f` files in `M3Formulas/` containing binary machine code + metadata
- **JIT compilation** — `formula/JITFormulas.pas` + PAX compiler for dynamic formula execution
- **Hybrid system** — chains up to 6 formulas with interpolation, DE combination (union/intersection), mix modes
- **Formula dispatch** uses procedure/function pointer types: `ThybridIteration2 = procedure(var x,y,z,w: Double; ...)`

### File formats
| Extension | Content |
|-----------|---------|
| `.m3i` | Full image + parameters (compressed) |
| `.m3p` | Parameters only (compressed) |
| `.m3f` | Formula file (machine code + metadata) |
| `.m3a` | Animation settings (compressed) |
| `.m3l` | Lighting presets (compressed) |
| `.m3c` | M.C. render settings |

## Conventions

### Naming
- `T*` — types/classes (e.g., `TMandCalcThread`)
- `P*` / `TP*` — pointer types (e.g., `TPVec3D`, `TPCalcThreadStats`)
- `S*` / `TS*` — single-precision variants (e.g., `TSVec`)
- `do*` — action procedures
- `F*` — form/UI component references

### Patterns
- **Packed records** for binary I/O, memory layout, and performance — alignment matters
- **Manual memory management** — `New()`/`Dispose()` for record types, dynamic arrays (`array of Type`)
- **Extensive pointer arithmetic** and type casting in the math/rendering hot paths
- **Thread synchronization** via `TCalcThreadStats` shared records and Windows messages for UI updates
- **Math3D.pas** provides SSE2-optimized vector/matrix/quaternion operations; single-precision variants prefixed with `S`
- **16-byte memory alignment** enforced at startup: `SetMinimumBlockAlignment(mba16Byte)`
