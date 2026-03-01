unit DiagASMCheck;

{$mode delphi}

{ ASM Block Spot-Check Unit
  =========================
  Pascal reference implementations of critical ASM routines.
  Used to verify that the ASM versions produce identical results
  under FPC by comparing outputs for sample inputs.

  Called from DiagHarness when --diag mode is active.
}

interface

procedure RunASMSpotChecks(const OutputDir: String);

implementation

uses SysUtils, Math, TypeDefinitions, Math3D, DivUtils;

{ Pascal reference for mAddVecWeight }
procedure PascalAddVecWeight(V1, V2: TPVec3D; W: Double);
begin
  V1^[0] := V1^[0] + W * V2^[0];
  V1^[1] := V1^[1] + W * V2^[1];
  V1^[2] := V1^[2] + W * V2^[2];
end;

{ Pascal reference for mCopyAddVecWeight }
procedure PascalCopyAddVecWeight(V1, V2, V3: TPVec3D; W: Double);
begin
  V1^[0] := V2^[0] + W * V3^[0];
  V1^[1] := V2^[1] + W * V3^[1];
  V1^[2] := V2^[2] + W * V3^[2];
end;

{ Pascal reference for FastMove }
procedure PascalFastMove(const Source; var Dest; Count: Integer);
begin
  Move(Source, Dest, Count);
end;

{ Compare two doubles with tolerance }
function DoublesMatch(A, B: Double; Tol: Double = 1e-12): Boolean;
begin
  if IsNaN(A) or IsNaN(B) then
    Result := IsNaN(A) and IsNaN(B)
  else if IsInfinite(A) or IsInfinite(B) then
    Result := A = B
  else
    Result := Abs(A - B) <= Tol * Max(1.0, Max(Abs(A), Abs(B)));
end;

procedure RunASMSpotChecks(const OutputDir: String);
var
  F: TextFile;
  FPath: String;
  PassCount, FailCount: Integer;

  procedure Log(const S: String);
  begin
    WriteLn(F, S);
  end;

  procedure CheckResult(const TestName: String; Pass: Boolean; const Details: String);
  begin
    if Pass then
    begin
      Inc(PassCount);
      Log('  [PASS] ' + TestName);
    end
    else
    begin
      Inc(FailCount);
      Log('  [FAIL] ' + TestName + ' -- ' + Details);
    end;
  end;

  procedure TestAddVecWeight;
  var
    V1_asm, V1_pas, V2: TVec3D;
    W: Double;
    i: Integer;
    Pass: Boolean;
    TestCases: array[0..3] of record
      V1, V2: TVec3D;
      W: Double;
      Name: String;
    end;
  begin
    Log('');
    Log('=== mAddVecWeight ===');

    TestCases[0].V1[0] := 1.0;  TestCases[0].V1[1] := 2.0;  TestCases[0].V1[2] := 3.0;
    TestCases[0].V2[0] := 4.0;  TestCases[0].V2[1] := 5.0;  TestCases[0].V2[2] := 6.0;
    TestCases[0].W := 2.0;
    TestCases[0].Name := 'Simple multiply-add';

    TestCases[1].V1[0] := 0.0;  TestCases[1].V1[1] := 0.0;  TestCases[1].V1[2] := 0.0;
    TestCases[1].V2[0] := 1e10; TestCases[1].V2[1] := -1e10; TestCases[1].V2[2] := 1e-10;
    TestCases[1].W := 1.0;
    TestCases[1].Name := 'Zero base, extreme values';

    TestCases[2].V1[0] := -1.5;  TestCases[2].V1[1] := 2.7;     TestCases[2].V1[2] := -3.14159;
    TestCases[2].V2[0] := 0.001; TestCases[2].V2[1] := -999.9;   TestCases[2].V2[2] := 42.0;
    TestCases[2].W := 0.5;
    TestCases[2].Name := 'Mixed signs, fractional weight';

    TestCases[3].V1[0] := 1e-300; TestCases[3].V1[1] := 1e300;   TestCases[3].V1[2] := -1e150;
    TestCases[3].V2[0] := 1e-300; TestCases[3].V2[1] := 1e-300;  TestCases[3].V2[2] := 1e150;
    TestCases[3].W := 1e-150;
    TestCases[3].Name := 'Extreme magnitudes';

    for i := 0 to 3 do
    begin
      V1_asm := TestCases[i].V1;
      V1_pas := TestCases[i].V1;
      V2 := TestCases[i].V2;
      W := TestCases[i].W;

      mAddVecWeight(@V1_asm, @V2, W);
      PascalAddVecWeight(@V1_pas, @V2, W);

      Pass := DoublesMatch(V1_asm[0], V1_pas[0]) and
              DoublesMatch(V1_asm[1], V1_pas[1]) and
              DoublesMatch(V1_asm[2], V1_pas[2]);

      CheckResult(TestCases[i].Name, Pass,
        Format('ASM=(%.15g, %.15g, %.15g) PAS=(%.15g, %.15g, %.15g)',
        [V1_asm[0], V1_asm[1], V1_asm[2], V1_pas[0], V1_pas[1], V1_pas[2]]));
    end;
  end;

  procedure TestCopyAddVecWeight;
  var
    V1_asm, V1_pas, V2, V3: TVec3D;
    W: Double;
    i: Integer;
    Pass: Boolean;
    TestCases: array[0..2] of record
      V2, V3: TVec3D;
      W: Double;
      Name: String;
    end;
  begin
    Log('');
    Log('=== mCopyAddVecWeight ===');

    TestCases[0].V2[0] := 1.0;  TestCases[0].V2[1] := 2.0;  TestCases[0].V2[2] := 3.0;
    TestCases[0].V3[0] := 10.0; TestCases[0].V3[1] := 20.0; TestCases[0].V3[2] := 30.0;
    TestCases[0].W := 0.1;
    TestCases[0].Name := 'Simple copy+add';

    TestCases[1].V2[0] := 0.0;  TestCases[1].V2[1] := 0.0;  TestCases[1].V2[2] := 0.0;
    TestCases[1].V3[0] := 1.0;  TestCases[1].V3[1] := 1.0;  TestCases[1].V3[2] := 1.0;
    TestCases[1].W := 0.0;
    TestCases[1].Name := 'Zero weight';

    TestCases[2].V2[0] := -5.5; TestCases[2].V2[1] := 3.3;  TestCases[2].V2[2] := 0.0;
    TestCases[2].V3[0] := 2.0;  TestCases[2].V3[1] := -4.0; TestCases[2].V3[2] := 8.0;
    TestCases[2].W := -1.5;
    TestCases[2].Name := 'Negative weight';

    for i := 0 to 2 do
    begin
      V2 := TestCases[i].V2;
      V3 := TestCases[i].V3;
      W := TestCases[i].W;

      FillChar(V1_asm, SizeOf(V1_asm), 0);
      FillChar(V1_pas, SizeOf(V1_pas), 0);

      mCopyAddVecWeight(@V1_asm, @V2, @V3, W);
      PascalCopyAddVecWeight(@V1_pas, @V2, @V3, W);

      Pass := DoublesMatch(V1_asm[0], V1_pas[0]) and
              DoublesMatch(V1_asm[1], V1_pas[1]) and
              DoublesMatch(V1_asm[2], V1_pas[2]);

      CheckResult(TestCases[i].Name, Pass,
        Format('ASM=(%.15g, %.15g, %.15g) PAS=(%.15g, %.15g, %.15g)',
        [V1_asm[0], V1_asm[1], V1_asm[2], V1_pas[0], V1_pas[1], V1_pas[2]]));
    end;
  end;

  procedure TestFastMove;
  var
    Src, Dst1, Dst2: array[0..255] of Byte;
    i, sz: Integer;
    Pass: Boolean;
    TestSizes: array[0..5] of Integer;
  begin
    Log('');
    Log('=== FastMove ===');

    TestSizes[0] := 0;
    TestSizes[1] := 1;
    TestSizes[2] := 8;
    TestSizes[3] := 24;
    TestSizes[4] := 64;
    TestSizes[5] := 256;

    for i := 0 to 255 do
      Src[i] := Byte((i * 137 + 43) and $FF);  // pseudo-random pattern

    for i := 0 to 5 do
    begin
      sz := TestSizes[i];
      FillChar(Dst1, 256, $AA);
      FillChar(Dst2, 256, $AA);

      FastMove(Src, Dst1, sz);
      PascalFastMove(Src, Dst2, sz);

      Pass := CompareMem(@Dst1[0], @Dst2[0], 256);

      CheckResult(Format('Size=%d bytes', [sz]), Pass,
        Format('Buffers differ at some offset', []));
    end;
  end;

begin
  FPath := OutputDir + 'asm_spotcheck.txt';
  AssignFile(F, FPath);
  Rewrite(F);
  PassCount := 0;
  FailCount := 0;

  try
    Log('FPC ASM Block Spot-Check Report');
    Log('================================');
    Log('Generated: ' + DateTimeToStr(Now));
    Log('Compiler: FPC ' + {$I %FPCVERSION%});
    Log('');

    TestAddVecWeight;
    TestCopyAddVecWeight;
    TestFastMove;

    Log('');
    Log('================================');
    Log(Format('Total: %d tests, %d passed, %d failed', [PassCount + FailCount, PassCount, FailCount]));
    if FailCount = 0 then
      Log('ALL TESTS PASSED')
    else
      Log('*** FAILURES DETECTED ***');
  finally
    CloseFile(F);
  end;
end;

end.
