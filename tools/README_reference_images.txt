FPC vs Delphi Pixel Comparison - Reference Image Generation
============================================================

To generate reference images from the Delphi build:

1. Open Delphi-built Mandelbulb3D.exe

2. For EACH scene below, do:
   a) File > Open Parameter > select the .m3p file
   b) Click "Calculate 3D"
   c) Wait for full render + all post-processing to complete
   d) Click save BMP button > save as indicated filename

3. Test Matrix:

   # | Scene File                  | Save As              | Formula Type
   --+-----------------------------+----------------------+-------------
   1 | (default - just startup)    | ref_default.bmp      | IntPow8
   2 | ABoxScale2Start.m3p         | ref_ABoxScale2Start.bmp | AmazingBox
   3 | Aexion 10bulbs.m3p          | ref_Aexion_10bulbs.bmp  | AexionC
   4 | BulboxCut.m3p               | ref_BulboxCut.bmp       | Bulbox
   5 | ApolloBalloons dIFS.m3p     | ref_ApolloBalloons_dIFS.bmp | dIFS
   6 | QuatP4hybridJulia.m3p       | ref_QuatP4hybridJulia.bmp   | Quaternion

4. Place all ref_*.bmp files in the diag_output/ directory

5. Run comparison:
   powershell -File tools\compare_bitmaps.ps1 ^
     -RefBmp "diag_output\ref_*.bmp" ^
     -TestBmp "diag_output\fpc_*.bmp" ^
     -Threshold 5

   The script will match ref_XXX.bmp with fpc_XXX.bmp by scene name
   and produce a comparison report + visual diff images.

Acceptance Criteria:
- Mean pixel difference < 2% (roughly 5 on 0-255 scale)
- All scenes render without crashes
- No hangs or exceptions during post-processing
