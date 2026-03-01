# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mandelbulb 3D (MB3D) is a Windows desktop application for generating 3D fractal renderings using distance estimation (DE) techniques. Written in Object Pascal, targeting Win32. Builds with Free Pascal/Lazarus (LCL).

**Current version**: 1.9.9.37+

## Build

- **Build command**: `/c/lazarus/lazbuild.exe --cpu=i386 --os=win32 --compiler=/c/FPC/3.2.2/bin/i386-Win32/ppc386.exe --lazarusdir=/c/lazarus C:/work/mb3d/Mandelbulb3D.lpi`
- **FPC version**: 3.2.2, i386-Win32
- **Lazarus version**: 4.4
- **Project file**: `Mandelbulb3D.lpi`
- **Entry point**: `Mandelbulb3D.lpr`
- **Output**: `Mandelbulb3D.exe`
- **Custom options**: `-Mdelphi -dPARAMS_PER_THREAD -dJIT_FORMULA_PREPROCESSING`

### Key compiler settings
- Stack: 16KB min / 16MB max (`-$M16384,16777216`)
- Large Address Aware flag set (`{$SetPEFlags $20}`)
- I/O checking OFF, range checking OFF, overflow checking OFF (performance-critical math)
- Active defines: `PARAMS_PER_THREAD`, `JIT_FORMULA_PREPROCESSING`, `DEBUG_MESHEXP`
- Disabled defines: `USE_PAX_COMPILER` (commercial PAX Compiler removed; all PAX code guarded by `{$IFDEF USE_PAX_COMPILER}`)

### Testing
- **Formula regression**: `bash tools/run_formula_tests.sh` — 21 tests covering IntPow, AmazingBox, dIFS, hybrid chains, post-processing. Expect 21/21 pass.
- **Headless render suite**: `bash tools/run_headless_tests.sh` — 80 .m3p scenes at 200x150. Expect 79/80 pass (1 skip: incompatible format).
- **Diagnostic harness**: Build with `-dFPC_DIAG`, run with `--diag` flag for pixel-level diagnostic comparison.

### Headless CLI Rendering
Headless mode for scripting and automation:
- **HeadlessRender.pas** — CLI argument parsing, console allocation, output saving
- Usage: `Mandelbulb3D.exe --render input.m3p --output result.png [--format png|jpg|bmp] [--width N] [--height N] [--threads N]`

### Historical
- Originally built with Delphi (VCL), fully ported to FPC/Lazarus (LCL). Delphi support removed.
- Migration details: [`docs/FPC-MIGRATION.md`](docs/FPC-MIGRATION.md)

## Architecture

### Directory layout
```
/                    Main application units (.pas/.lfm)
/formula/            Formula GUI, compiler, JIT, parameter editing
/maps/               Texture map handling and map sequence UI
/render/             Preview rendering
/bulbtracer2/        2.5D mesh generation (voxel tracing, mesh I/O, OpenGL preview)
/opengl/             OpenGL bindings and mesh preview (dglOpenGL, shaders)
/heightmapgen/       Height map generation and PNM read/write
/zbuf16bit/          16-bit Z-buffer generation
/mutagen/            Mutation/random parameter generation
/script/             PAX-compiler-based scripting system (disabled)
/facade/             MB3DFacade.pas — public API for external access
/prefs/              Preferences, INI directories, visual themes
/M3Formulas/         ~200+ external formula files (.m3f — binary machine code + metadata)
/M3Parameter/        Parameter templates and test scenes
/M3Maps/             Texture/map resources
/shaders/            GLSL shader files
/docs/               Documentation (FPC-MIGRATION.md, migration plans)
/tools/              Build scripts, test runners, screenshot automation
```

### Core rendering pipeline
1. **Parameter loading** — `FileHandling.pas` loads `.m3i`/`.m3p` files
2. **Formula setup** — `CustomFormulas.pas` + `formula/FormulaCompiler.pas` compile/load formulas; hybrid chains of up to 6 formulas
3. **Thread pool** — `ThreadUtils.pas` manages up to 64 worker threads (`TCalcThreadStats` records for coordination)
4. **Ray marching** — `Calc.pas` (`RayMarch()`, `CalcDEfull()`, `CalcDEanalytic()`) performs distance-estimation ray marching
5. **Worker threads** — `CalcThread.pas` (`TMandCalcThread`) runs per-thread iterations using `TIteration3Dext` structures
6. **Post-processing** — Hard shadows (`CalcHardShadow.pas`), ambient shadows (`AmbShadowCalcThreadN.pas`, `CalcAmbShadowDE.pas`, `AmbHiQ.pas`), DOF (`DOF.pas`), reflections (`CalcSR.pas`)
7. **Image output** — `ImageProcess.pas` for bitmap manipulation; output as BMP/PNG/JPEG

### Alternative renderers
- **Monte Carlo renderer** — `CalcMonteCarlo.pas` + `MonteCarloForm.pas`: physically-based path tracing
- **BulbTracer2** — `bulbtracer2/`: voxel-based mesh generation with OpenGL preview, export to PLY/OBJ/STL

### Key data structures (in `TypeDefinitions.pas` and `Calc.pas`)
- `TIteration3Dext` — packed record (~408 bytes): iteration state (position, Julia constants, hybrid chain, DE values, orbit traps)
- `TMCTparameter` — large record: ray march settings, DE thresholds, lighting, color mapping, post-processing flags
- `TCalcThreadStats` — packed record: thread pool coordination (type, count, per-thread stats array of 64 slots)

### Formula system
- **Internal formulas** — `formulas.pas` (integer powers 2-8, real power, quaternion, Amazing Box, etc.)
- **External formulas** — `.m3f` files in `M3Formulas/` containing binary machine code + metadata
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
- **Manual memory management** — `New()`/`Dispose()` for record types, dynamic arrays
- **Extensive pointer arithmetic** and type casting in math/rendering hot paths
- **Thread synchronization** via `TCalcThreadStats` shared records and Windows messages for UI updates
- **Math3D.pas** provides SSE2-optimized vector/matrix/quaternion operations; single-precision variants prefixed with `S`
- **16-byte memory alignment** enforced at startup: `SetMinimumBlockAlignment(mba16Byte)`
