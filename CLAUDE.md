# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mandelbulb 3D (MB3D) is a Windows desktop application for generating 3D fractal renderings using distance estimation (DE) techniques. Written in Delphi/Object Pascal, targeting Win32 with VCL UI framework.

**Current version**: 1.9.9.37+

## Build

- **IDE**: Open `Mandelbulb3D.dproj` in RAD Studio / Delphi, then Build (Shift+F9) or Run (F9)
- **Command line**: `msbuild Mandelbulb3D.dproj /p:Config=Release /p:Platform=Win32`
- **Entry point**: `Mandelbulb3D.dpr` — creates all forms and runs the VCL application loop
- **Output**: `Mandelbulb3D.exe`
- **No test suite exists** — verification is manual

### Key compiler settings
- Stack: 16KB min / 16MB max (`-$M16384,16777216`)
- Large Address Aware flag set (`{$SetPEFlags $20}`)
- Weak RTTI / minimal RTTI reflection (`{$RTTI EXPLICIT METHODS([]) FIELDS([]) PROPERTIES([])}`)
- I/O checking OFF, range checking OFF, overflow checking OFF (performance-critical math)
- Active defines (Release): `PARAMS_PER_THREAD`, `JIT_FORMULA_PREPROCESSING`, `DEBUG_MESHEXP`
- Disabled defines: `USE_PAX_COMPILER` (commercial PAX Compiler dependency removed; all PAX code is guarded by `{$IFDEF USE_PAX_COMPILER}`)

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
