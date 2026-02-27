# MB3D Migration: Delphi → Free Pascal / Lazarus

## Goal

Migrate Mandelbulb 3D from proprietary Delphi IDE to Free Pascal (FPC) + Lazarus so the project builds entirely with free tools. Windows-only, Win32, preserve all functionality including inline assembly.

## Decisions

- **Target**: Windows 32-bit (Win32) only
- **Compiler**: Free Pascal Compiler (FPC) with Lazarus IDE
- **ASM**: Keep all 314 inline assembly blocks, adapt syntax for FPC (`{$asmmode intel}`)
- **PAX Compiler**: Disable now (remove `USE_PAX_COMPILER` define), replace with PascalScript later
- **Approach**: Incremental migration (Approach 1) — compile at each step

## Dependencies Inventory

### Paid / Must Replace

| Dependency | Action |
|---|---|
| Delphi VCL framework | Replace with LCL (Lazarus Component Library) |
| PAX Compiler (commercial) | Disable via conditional compile; replace with PascalScript later |

### Open-Source / Adapt

| Dependency | Action |
|---|---|
| JEDI VCL (5 files) | Replace with standard LCL components |
| pngimage.pas (bundled) | Remove, use native LCL PNG support |
| GifImage.pas (bundled) | Keep or replace with fcl-image |
| dglOpenGL.pas (bundled) | Keep (FPC-compatible) or replace with `gl, glu, glext` |
| FastMM4 (in attic/) | Remove, use FPC default heap manager |

### No Changes Needed

| Item | Reason |
|---|---|
| Windows API (84 units) | FPC supports Windows unit natively (Win32 target) |
| Packed records (119 decls) | Compatible in `{$mode delphi}` |
| Generics (TDictionary) | FPC supports generics |
| TThread descendants | FPC TThread is compatible |
| OpenGL bindings | FPC has native OpenGL support |

## Migration Stages

### Stage 1: Project Structure

- Create `Mandelbulb3D.lpi` + `Mandelbulb3D.lpr` from `.dproj` / `.dpr`
- Remove Delphi-specific directives: `{$RTTI}`, `{$WeakLinkRTTI}`, `{$SetPEFlags}`
- Replace `SetMinimumBlockAlignment(mba16Byte)` — not available in FPC
- Convert 30 `.dfm` → `.lfm` using Lazarus converter

### Stage 2: Compiler Compatibility

- Add `{$mode delphi}` to all units
- Add `{$asmmode intel}` to all units containing inline assembly (27 files)
- Remove/replace `Vcl.*` namespace prefixes (27 files)
- Remove `Vcl.Themes` and `Vcl.Styles` references
- Replace `Vcl.ExtDlgs` with LCL equivalents

### Stage 3: JEDI VCL Replacement

Files: `MutaGenGUI.pas`, `MeshPreviewUI.pas`, `HeightMapGenUI.pas`, `ZBuf16BitGenUI.pas`, `BulbTracer2UI.pas`

| JEDI Component | LCL Replacement |
|---|---|
| TJvGroupBox | TGroupBox |
| TJvOfficeColorButton | TColorButton |
| TJvColorBox | TColorBox |
| TJvColorButton | TColorButton |
| TJvProgressBar | TProgressBar |
| TJvSlider | TTrackBar |
| TJvOutlookBar | TPageControl + TTabSheet |
| TJvNavigationPane | TPageControl |
| TJvClipboardMonitor | Manual clipboard API |
| TJvPageList | TNotebook |
| TJvCaptionPanel | TPanel with TLabel |

### Stage 4: PAX Compiler Disable

- Remove `USE_PAX_COMPILER` from project defines
- Verify `FormulaCompiler.pas` and `ScriptCompiler.pas` compile without PAX
- JIT and scripting features become unavailable (external formulas via .m3f still work)

### Stage 5: ASM Adaptation

27 files, 314 blocks. Key syntax differences FPC vs Delphi:
- FPC uses `qword ptr` instead of Delphi's `Int64 ptr`
- Local variable access syntax may differ
- `{$CODEALIGN}` → verify FPC support, may need `{$ALIGN}`
- MMX/SSE/SSE2 instructions supported with `{$asmmode intel}`

Priority order (by block count):
1. Math3D.pas (97 blocks)
2. formulas.pas (41 blocks)
3. ImageProcess.pas (15 blocks)
4. AmbShadowCalcThreadN.pas (14 blocks)
5. AmbHiQ.pas (12 blocks)
6. PaintThread.pas (6 blocks)
7. Remaining files (1-6 blocks each)

### Stage 6: Image Format Units

- Remove `pngimage.pas` / `pnglang.pas` / `pngzlib.pas` — use LCL native `TPortableNetworkGraphic`
- Update `FileHandling.pas` to use LCL PNG API
- Keep `GifImage.pas` if it compiles, otherwise replace with fcl-image

### Stage 7: Build & Test

- Compile with FPC Win32 target
- Fix remaining compilation errors iteratively
- Test rendering output against Delphi-compiled version
- Verify all formula types work
- Test post-processing (shadows, DOF, reflections)
- Test BulbTracer2 mesh generation
- Test Monte Carlo renderer

## String Strategy

Use `{$mode delphi}` where String = AnsiString. The codebase explicitly uses `AnsiString` in key places (TypeDefinitions.pas), suggesting pre-Unicode Delphi origin or explicit ANSI usage. If issues arise, add `{$modeswitch unicodestrings}` selectively.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ASM syntax incompatibilities | HIGH | HIGH | Test each block individually, have Pascal fallbacks ready |
| LCL visual differences | MEDIUM | LOW | Cosmetic only, functionality preserved |
| String encoding bugs | LOW | MEDIUM | Use `{$mode delphi}`, test file I/O thoroughly |
| Missing LCL equivalents for JEDI | LOW | MEDIUM | Simplify UI where needed |
| Performance regression | LOW | LOW | ASM preserved, only UI layer changes |
