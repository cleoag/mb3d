unit FormulaTranspiler;
// Transpiles [SOURCE] sections of .m3f formula files from Pascal to OpenCL C.
//
// Handles the MB3D Pascal subset:
//   Procedure signature: procedure Name(var x,y,z,w: Double; PIteration3D: TPIteration3D);
//   Variables: local doubles only
//   Operators: +, -, *, /
//   Math: sqrt, abs, sin, cos, tan, arctan2, arcsin, arccos, power, exp, ln,
//         sinh, cosh, tanh, hypot, min, max, floor, ceil, sqr
//   Field access: PIteration3D^.J1, .J2, .J3, .C1, .C2, .C3
//   Formula params from [OPTIONS]: referenced by name, mapped to params[index]
//   Constants from [CONSTANTS]: inlined as literals
//   Comments: curly braces and //
//   Control flow: if/then/else (single-line or with begin/end blocks)
//   No: loops, arrays, function definitions, recursion, I/O

{$mode delphi}
{$H+}

interface

uses
  SysUtils, Classes;

type
  TFormulaConstant = record
    Name: String;
    Value: Double;
  end;

  TFormulaParam = record
    Name: String;
    Index: Integer;
  end;

  TTranspilerResult = record
    Success: Boolean;
    OpenCLSource: String;
    ErrorMessage: String;
    FormulaName: String;
  end;

  TFormulaTranspiler = class
  private
    FConstants: array of TFormulaConstant;
    FParams: array of TFormulaParam;
    FConstantCount: Integer;
    FParamCount: Integer;

    function NormalizeName(const S: String): String;
    function StripComments(const Source: String): String;
    function ReplaceMathFunctions(const Line: String): String;
    function ReplaceFieldAccess(const Line: String): String;
    function ReplaceParamRefs(const Line: String): String;
    function TranspilePascalBody(const Source: String; const FormulaName: String): String;
  public
    procedure ClearConstants;
    procedure AddConstant(const Name: String; Value: Double);
    procedure ClearParams;
    procedure AddParam(const Name: String; Index: Integer);

    function Transpile(const PascalSource: String;
      const FormulaIdent: String): TTranspilerResult;

    function TranspileToKernelFunction(const PascalSource: String;
      const FormulaIdent: String; GPUFormulaId: Integer): String;
  end;

implementation

uses
  Math;

// ============================================================================
// Standalone helpers (must be before class methods that use them)
// ============================================================================

function ReplaceWordCI(const S, OldWord, NewWord: String): String;
{ Case-insensitive whole-word replacement. Only replaces when OldWord is
  bounded by non-identifier characters. }
var
  LowerS, LowerOld: String;
  Pos1, OldLen, SLen: Integer;
  Before, After: Char;
begin
  Result := S;
  LowerOld := LowerCase(OldWord);
  OldLen := Length(OldWord);
  Pos1 := 1;

  while Pos1 <= Length(Result) - OldLen + 1 do
  begin
    LowerS := LowerCase(Result);
    SLen := Length(Result);

    if Copy(LowerS, Pos1, OldLen) = LowerOld then
    begin
      if Pos1 > 1 then Before := Result[Pos1 - 1] else Before := ' ';
      if Pos1 + OldLen <= SLen then After := Result[Pos1 + OldLen] else After := ' ';

      if not (Before in ['A'..'Z', 'a'..'z', '0'..'9', '_']) and
         not (After in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      begin
        Result := Copy(Result, 1, Pos1 - 1) + NewWord +
                  Copy(Result, Pos1 + OldLen, SLen);
        Inc(Pos1, Length(NewWord));
        Continue;
      end;
    end;
    Inc(Pos1);
  end;
end;

function ConvertIfStatement(const Line: String): String;
{ Convert Pascal if/then to C if().
  "if cond then stmt"  → "if (cond) stmt"
  "if cond then"       → "if (cond) {"      }
var
  LLine: String;
  ThenPos: Integer;
  Condition, ThenPart: String;
begin
  LLine := LowerCase(Line);

  // Try "if condition then statement" (then followed by more text)
  ThenPos := Pos(' then ', LLine);
  if ThenPos > 0 then
  begin
    Condition := Trim(Copy(Line, 4, ThenPos - 4));
    ThenPart := Trim(Copy(Line, ThenPos + 6, Length(Line)));
    Result := 'if (' + Condition + ') ' + ThenPart;
    Exit;
  end;

  // Try "if condition then" (then at end of line)
  if (Length(LLine) >= 8) and (Copy(LLine, Length(LLine) - 3, 4) = 'then') then
  begin
    Condition := Trim(Copy(Line, 4, Length(Line) - 7));
    Result := 'if (' + Condition + ') {';
    Exit;
  end;

  Result := Line;  // Can't parse, pass through
end;

// ============================================================================
// Class methods
// ============================================================================

function TFormulaTranspiler.NormalizeName(const S: String): String;
begin
  Result := LowerCase(Trim(S));
end;

function TFormulaTranspiler.StripComments(const Source: String): String;
var
  i, Len: Integer;
  InBrace: Boolean;
begin
  Result := '';
  Len := Length(Source);
  i := 1;
  InBrace := False;

  while i <= Len do
  begin
    if InBrace then
    begin
      if Source[i] = '}' then
        InBrace := False;
      Inc(i);
    end
    else if Source[i] = '{' then
    begin
      InBrace := True;
      Inc(i);
    end
    else if (i < Len) and (Source[i] = '/') and (Source[i+1] = '/') then
    begin
      while (i <= Len) and (Source[i] <> #10) do
        Inc(i);
    end
    else
    begin
      Result := Result + Source[i];
      Inc(i);
    end;
  end;
end;

function TFormulaTranspiler.ReplaceMathFunctions(const Line: String): String;
begin
  Result := Line;
  Result := ReplaceWordCI(Result, 'abs',     'fabs');
  Result := ReplaceWordCI(Result, 'arctan2', 'atan2');
  Result := ReplaceWordCI(Result, 'arctan',  'atan');
  Result := ReplaceWordCI(Result, 'arcsin',  'asin');
  Result := ReplaceWordCI(Result, 'arccos',  'acos');
  Result := ReplaceWordCI(Result, 'power',   'pow');
  Result := ReplaceWordCI(Result, 'ln',      'log');
  Result := ReplaceWordCI(Result, 'pi',      '3.14159265358979323846');
  // sqr(x) handled by #define in generated header
end;

function TFormulaTranspiler.ReplaceFieldAccess(const Line: String): String;
var
  LLine: String;
  Pos1: Integer;
  Prefix: String;
begin
  Result := Line;
  Prefix := 'piteration3d^.';

  LLine := LowerCase(Result);
  Pos1 := Pos(Prefix, LLine);
  while Pos1 > 0 do
  begin
    Result := Copy(Result, 1, Pos1 - 1) + 'it->' +
              Copy(Result, Pos1 + Length(Prefix), Length(Result));
    LLine := LowerCase(Result);
    Pos1 := Pos(Prefix, LLine);
  end;
end;

function TFormulaTranspiler.ReplaceParamRefs(const Line: String): String;
var
  i: Integer;
  LName: String;
  Replacement: String;
begin
  Result := Line;

  // Replace parameter names with params[index]
  for i := 0 to FParamCount - 1 do
  begin
    LName := FParams[i].Name;
    Replacement := Format('params[%d]', [FParams[i].Index]);
    Result := ReplaceWordCI(Result, LName, Replacement);
  end;

  // Replace constants with literal values
  for i := 0 to FConstantCount - 1 do
  begin
    LName := FConstants[i].Name;
    Replacement := FloatToStrF(FConstants[i].Value, ffGeneral, 18, 0);
    Result := ReplaceWordCI(Result, LName, Replacement);
  end;
end;

function TFormulaTranspiler.TranspilePascalBody(const Source: String;
  const FormulaName: String): String;
var
  Lines: TStringList;
  i: Integer;
  Line, TrimLine, LowerLine: String;
  InVarSection, InBody: Boolean;
  VarLines, BodyLines: TStringList;
  ProcHeaderSeen: Boolean;
begin
  Lines := TStringList.Create;
  VarLines := TStringList.Create;
  BodyLines := TStringList.Create;
  try
    Lines.Text := StripComments(Source);

    InVarSection := False;
    InBody := False;
    ProcHeaderSeen := False;

    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      TrimLine := Trim(Line);
      LowerLine := LowerCase(TrimLine);

      if TrimLine = '' then Continue;

      // Skip procedure/function header line
      if (not ProcHeaderSeen) and
         ((Pos('procedure ', LowerLine) = 1) or (Pos('function ', LowerLine) = 1)) then
      begin
        ProcHeaderSeen := True;
        Continue;
      end;

      if (not InBody) and (LowerLine = 'var') then
      begin
        InVarSection := True;
        Continue;
      end;

      if LowerLine = 'begin' then
      begin
        InVarSection := False;
        InBody := True;
        Continue;
      end;

      if (LowerLine = 'end;') or (LowerLine = 'end.') or (LowerLine = 'end') then
      begin
        InBody := False;
        Continue;
      end;

      if InVarSection then
        VarLines.Add(TrimLine)
      else if InBody then
        BodyLines.Add(TrimLine);
    end;

    // --- Generate OpenCL C function ---
    Result := '';
    Result := Result + Format('void formula_%s(Iteration3D* it, __constant double* params) {' + #10,
      [LowerCase(FormulaName)]);
    Result := Result + '    double x = it->x, y = it->y, z = it->z, w = it->w;' + #10;

    // Variable declarations
    for i := 0 to VarLines.Count - 1 do
    begin
      Line := VarLines[i];
      // Remove trailing semicolon
      if (Length(Line) > 0) and (Line[Length(Line)] = ';') then
        Line := Copy(Line, 1, Length(Line) - 1);
      LowerLine := LowerCase(Line);
      if Pos(': double', LowerLine) > 0 then
      begin
        Line := Trim(Copy(Line, 1, Pos(': double', LowerLine) - 1));
        Line := StringReplace(Line, ';', '', [rfReplaceAll]);
        Result := Result + Format('    double %s;' + #10, [Line]);
      end;
    end;
    Result := Result + #10;

    // Body statements
    for i := 0 to BodyLines.Count - 1 do
    begin
      Line := BodyLines[i];

      // Pascal := to C =
      Line := StringReplace(Line, ':=', '=', [rfReplaceAll]);

      // Replace math functions, field access, parameter references
      Line := ReplaceMathFunctions(Line);
      Line := ReplaceFieldAccess(Line);
      Line := ReplaceParamRefs(Line);

      LowerLine := LowerCase(Trim(Line));

      // Handle control flow
      if Pos('if ', LowerLine) = 1 then
        Line := ConvertIfStatement(Line)
      else if LowerLine = 'else' then
        Line := '} else {'
      else if Pos('else ', LowerLine) = 1 then
        Line := '} else ' + Trim(Copy(Trim(Line), 6, Length(Trim(Line))))
      else if LowerLine = 'begin' then
        Line := '{'
      else if (LowerLine = 'end;') or (LowerLine = 'end') then
        Line := '}';

      Result := Result + '    ' + Line + #10;
    end;

    // Write locals back to iteration state
    Result := Result + '    it->x = x;' + #10;
    Result := Result + '    it->y = y;' + #10;
    Result := Result + '    it->z = z;' + #10;
    Result := Result + '    it->w = w;' + #10;
    Result := Result + '    it->Rout = x*x + y*y + z*z;' + #10;
    Result := Result + '}' + #10;
  finally
    Lines.Free;
    VarLines.Free;
    BodyLines.Free;
  end;
end;

// ============================================================================
// Public API
// ============================================================================

procedure TFormulaTranspiler.ClearConstants;
begin
  SetLength(FConstants, 0);
  FConstantCount := 0;
end;

procedure TFormulaTranspiler.AddConstant(const Name: String; Value: Double);
begin
  Inc(FConstantCount);
  SetLength(FConstants, FConstantCount);
  FConstants[FConstantCount - 1].Name := Name;
  FConstants[FConstantCount - 1].Value := Value;
end;

procedure TFormulaTranspiler.ClearParams;
begin
  SetLength(FParams, 0);
  FParamCount := 0;
end;

procedure TFormulaTranspiler.AddParam(const Name: String; Index: Integer);
begin
  Inc(FParamCount);
  SetLength(FParams, FParamCount);
  FParams[FParamCount - 1].Name := Name;
  FParams[FParamCount - 1].Index := Index;
end;

function TFormulaTranspiler.Transpile(const PascalSource: String;
  const FormulaIdent: String): TTranspilerResult;
begin
  Result.Success := False;
  Result.OpenCLSource := '';
  Result.ErrorMessage := '';
  Result.FormulaName := FormulaIdent;

  if Trim(PascalSource) = '' then
  begin
    Result.ErrorMessage := 'Empty source code';
    Exit;
  end;

  try
    Result.OpenCLSource :=
      '// Transpiled from ' + FormulaIdent + '.m3f [SOURCE]' + #10 +
      '#define sqr(x) ((x)*(x))' + #10 +
      #10 +
      TranspilePascalBody(PascalSource, FormulaIdent);
    Result.Success := True;
  except
    on E: Exception do
      Result.ErrorMessage := 'Transpilation error: ' + E.Message;
  end;
end;

function TFormulaTranspiler.TranspileToKernelFunction(const PascalSource: String;
  const FormulaIdent: String; GPUFormulaId: Integer): String;
var
  TR: TTranspilerResult;
begin
  TR := Transpile(PascalSource, FormulaIdent);
  if not TR.Success then
  begin
    Result := Format('// ERROR transpiling %s: %s' + #10, [FormulaIdent, TR.ErrorMessage]);
    Exit;
  end;

  Result := TR.OpenCLSource + #10;
end;

end.
