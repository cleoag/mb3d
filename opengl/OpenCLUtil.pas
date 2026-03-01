unit OpenCLUtil;
{ High-level OpenCL wrapper for MB3D GPU rendering.
  Follows ShaderUtil.pas pattern: OOP class, error-to-exception, cleanup.

  Usage:
    GPU := TOpenCLManager.Create;
    try
      if not GPU.Init then Exit; // no OpenCL
      Devices := GPU.GetDeviceNames;
      GPU.SelectDevice(0);
      Prog := GPU.CompileSource(KernelSource, '-cl-fast-relaxed-math');
      K := GPU.CreateKernel(Prog, 'ray_march');
      Buf := GPU.CreateBuffer(Width * Height * 4, CL_MEM_WRITE_ONLY);
      GPU.SetKernelArg(K, 0, Buf);
      GPU.Execute2D(K, Width, Height);
      GPU.ReadBuffer(Buf, @Pixels[0], Width * Height * 4);
    finally
      GPU.Free;
    end; }

{$mode delphi}
{$H+}

interface

uses
  Windows, SysUtils, Classes, dglOpenCL;

type
  { Device info record for UI display }
  TOpenCLDeviceInfo = record
    PlatformId: cl_platform_id;
    DeviceId:   cl_device_id;
    PlatformName: String;
    DeviceName:   String;
    DeviceVendor: String;
    DriverVersion: String;
    MaxComputeUnits: cl_uint;
    MaxWorkGroupSize: size_t;
    GlobalMemSize:    cl_ulong;
    LocalMemSize:     cl_ulong;
    HasDouble:        Boolean;   // cl_khr_fp64 support
    DeviceType:       cl_device_type;
  end;

  { Main OpenCL manager — one per GPU render session }
  TOpenCLManager = class
  private
    FInitialized: Boolean;
    FDevices: array of TOpenCLDeviceInfo;
    FSelectedDevice: Integer;
    FContext: cl_context;
    FQueue: cl_command_queue;
    FPrograms: TList;   // list of cl_program handles to release
    FKernels: TList;    // list of cl_kernel handles to release
    FBuffers: TList;    // list of cl_mem handles to release
    procedure CheckCL(Err: cl_int; const Where: String);
    function QueryDeviceString(Device: cl_device_id; Param: cl_device_info): String;
    function QueryDeviceUInt(Device: cl_device_id; Param: cl_device_info): cl_uint;
    function QueryDeviceULong(Device: cl_device_id; Param: cl_device_info): cl_ulong;
    function QueryDeviceSizeT(Device: cl_device_id; Param: cl_device_info): size_t;
    function QueryPlatformString(Platform: cl_platform_id; Param: cl_platform_info): String;
    procedure ReleaseAll;
  public
    constructor Create;
    destructor Destroy; override;

    { Initialize OpenCL — load DLL + enumerate devices.
      Returns False if OpenCL is not available (no DLL or no devices). }
    function Init: Boolean;

    { Number of available devices }
    function DeviceCount: Integer;

    { Get device info by index }
    function GetDevice(Index: Integer): TOpenCLDeviceInfo;

    { Get device names as a string list (for combo box) }
    function GetDeviceNames: TStringList;

    { Select a device and create context + command queue.
      Must be called before any GPU operations. }
    procedure SelectDevice(Index: Integer);

    { Returns True if a device is selected and context is active }
    function HasContext: Boolean;

    { Build log from last compilation (for error display) }
    function GetBuildLog(Prog: cl_program): String;

    { Compile OpenCL C source code into a program.
      Raises exception on build failure with full build log. }
    function CompileSource(const Source: String;
      const Options: String = ''): cl_program;

    { Create a kernel from a compiled program.
      Raises exception if kernel name not found. }
    function CreateKernel(Prog: cl_program;
      const KernelName: String): cl_kernel;

    { Create a device buffer.
      Flags: CL_MEM_READ_ONLY, CL_MEM_WRITE_ONLY, CL_MEM_READ_WRITE, etc. }
    function CreateBuffer(Size: size_t; Flags: cl_mem_flags;
      HostPtr: Pointer = nil): cl_mem;

    { Write host memory to device buffer (blocking) }
    procedure WriteBuffer(Buf: cl_mem; const Data; Size: size_t);

    { Read device buffer to host memory (blocking) }
    procedure ReadBuffer(Buf: cl_mem; out Data; Size: size_t);

    { Set kernel arguments }
    procedure SetKernelArgMem(K: cl_kernel; Index: cl_uint; Buf: cl_mem);
    procedure SetKernelArgInt(K: cl_kernel; Index: cl_uint; Value: cl_int);
    procedure SetKernelArgFloat(K: cl_kernel; Index: cl_uint; Value: cl_float);
    procedure SetKernelArgDouble(K: cl_kernel; Index: cl_uint; Value: cl_double);
    procedure SetKernelArgRaw(K: cl_kernel; Index: cl_uint; Size: size_t; Value: Pointer);

    { Execute a 2D kernel (Width x Height work items).
      LocalW/LocalH = 0 means let OpenCL choose work group size. }
    procedure Execute2D(K: cl_kernel; GlobalW, GlobalH: size_t;
      LocalW: size_t = 0; LocalH: size_t = 0);

    { Execute a 1D kernel }
    procedure Execute1D(K: cl_kernel; GlobalSize: size_t;
      LocalSize: size_t = 0);

    { Wait for all queued commands to complete }
    procedure Finish;

    { Release a specific buffer (also removes from tracked list) }
    procedure ReleaseBuffer(var Buf: cl_mem);

    { Release a specific kernel }
    procedure ReleaseKernel(var K: cl_kernel);

    { Release a specific program }
    procedure ReleaseProgram(var Prog: cl_program);

    { Selected device index (-1 if none) }
    property SelectedDeviceIndex: Integer read FSelectedDevice;

    { Direct access to context and queue for advanced usage }
    property Context: cl_context read FContext;
    property Queue: cl_command_queue read FQueue;
  end;

implementation

{ TOpenCLManager }

constructor TOpenCLManager.Create;
begin
  inherited Create;
  FInitialized := False;
  FSelectedDevice := -1;
  FContext := nil;
  FQueue := nil;
  FPrograms := TList.Create;
  FKernels := TList.Create;
  FBuffers := TList.Create;
end;

destructor TOpenCLManager.Destroy;
begin
  ReleaseAll;
  FPrograms.Free;
  FKernels.Free;
  FBuffers.Free;
  inherited Destroy;
end;

procedure TOpenCLManager.CheckCL(Err: cl_int; const Where: String);
begin
  if Err <> CL_SUCCESS then
    raise Exception.CreateFmt('OpenCL error in %s: %s (%d)',
      [Where, CLErrorString(Err), Err]);
end;

function TOpenCLManager.QueryPlatformString(Platform: cl_platform_id;
  Param: cl_platform_info): String;
var
  Len: size_t;
  Buf: array of AnsiChar;
begin
  Result := '';
  if clGetPlatformInfo(Platform, Param, 0, nil, @Len) <> CL_SUCCESS then Exit;
  if Len = 0 then Exit;
  SetLength(Buf, Len);
  if clGetPlatformInfo(Platform, Param, Len, @Buf[0], nil) = CL_SUCCESS then
    Result := Trim(String(PAnsiChar(@Buf[0])));
end;

function TOpenCLManager.QueryDeviceString(Device: cl_device_id;
  Param: cl_device_info): String;
var
  Len: size_t;
  Buf: array of AnsiChar;
begin
  Result := '';
  if clGetDeviceInfo(Device, Param, 0, nil, @Len) <> CL_SUCCESS then Exit;
  if Len = 0 then Exit;
  SetLength(Buf, Len);
  if clGetDeviceInfo(Device, Param, Len, @Buf[0], nil) = CL_SUCCESS then
    Result := Trim(String(PAnsiChar(@Buf[0])));
end;

function TOpenCLManager.QueryDeviceUInt(Device: cl_device_id;
  Param: cl_device_info): cl_uint;
begin
  Result := 0;
  clGetDeviceInfo(Device, Param, SizeOf(Result), @Result, nil);
end;

function TOpenCLManager.QueryDeviceULong(Device: cl_device_id;
  Param: cl_device_info): cl_ulong;
begin
  Result := 0;
  clGetDeviceInfo(Device, Param, SizeOf(Result), @Result, nil);
end;

function TOpenCLManager.QueryDeviceSizeT(Device: cl_device_id;
  Param: cl_device_info): size_t;
begin
  Result := 0;
  clGetDeviceInfo(Device, Param, SizeOf(Result), @Result, nil);
end;

// ---------------------------------------------------------------------------
// Init — load DLL + enumerate all platforms and devices
// ---------------------------------------------------------------------------

function TOpenCLManager.Init: Boolean;
var
  NumPlatforms, NumDevices: cl_uint;
  Platforms: array of cl_platform_id;
  Devices: array of cl_device_id;
  i, j, DevIdx: Integer;
  Extensions: String;
begin
  Result := False;
  SetLength(FDevices, 0);

  // Load the DLL
  if not InitOpenCL then Exit;
  if not OpenCLAvailable then Exit;

  // Enumerate platforms
  if clGetPlatformIDs(0, nil, @NumPlatforms) <> CL_SUCCESS then Exit;
  if NumPlatforms = 0 then Exit;
  SetLength(Platforms, NumPlatforms);
  if clGetPlatformIDs(NumPlatforms, @Platforms[0], nil) <> CL_SUCCESS then Exit;

  // Enumerate devices across all platforms
  DevIdx := 0;
  for i := 0 to NumPlatforms - 1 do
  begin
    NumDevices := 0;
    if clGetDeviceIDs(Platforms[i], CL_DEVICE_TYPE_ALL, 0, nil, @NumDevices) <> CL_SUCCESS then
      Continue;
    if NumDevices = 0 then Continue;
    SetLength(Devices, NumDevices);
    if clGetDeviceIDs(Platforms[i], CL_DEVICE_TYPE_ALL, NumDevices, @Devices[0], nil) <> CL_SUCCESS then
      Continue;

    for j := 0 to NumDevices - 1 do
    begin
      SetLength(FDevices, DevIdx + 1);
      with FDevices[DevIdx] do
      begin
        PlatformId := Platforms[i];
        DeviceId := Devices[j];
        PlatformName := QueryPlatformString(Platforms[i], CL_PLATFORM_NAME);
        DeviceName := QueryDeviceString(Devices[j], CL_DEVICE_NAME);
        DeviceVendor := QueryDeviceString(Devices[j], CL_DEVICE_VENDOR);
        DriverVersion := QueryDeviceString(Devices[j], CL_DRIVER_VERSION);
        MaxComputeUnits := QueryDeviceUInt(Devices[j], CL_DEVICE_MAX_COMPUTE_UNITS);
        MaxWorkGroupSize := QueryDeviceSizeT(Devices[j], CL_DEVICE_MAX_WORK_GROUP_SIZE);
        GlobalMemSize := QueryDeviceULong(Devices[j], CL_DEVICE_GLOBAL_MEM_SIZE);
        LocalMemSize := QueryDeviceULong(Devices[j], CL_DEVICE_LOCAL_MEM_SIZE);

        // Check for double precision support
        Extensions := QueryDeviceString(Devices[j], CL_DEVICE_EXTENSIONS);
        HasDouble := (Pos('cl_khr_fp64', Extensions) > 0) or
                     (Pos('cl_amd_fp64', Extensions) > 0);

        // Device type
        clGetDeviceInfo(Devices[j], CL_DEVICE_TYPE_INFO, SizeOf(DeviceType),
          @DeviceType, nil);
      end;
      Inc(DevIdx);
    end;
  end;

  FInitialized := Length(FDevices) > 0;
  Result := FInitialized;
end;

// ---------------------------------------------------------------------------
// Device queries
// ---------------------------------------------------------------------------

function TOpenCLManager.DeviceCount: Integer;
begin
  Result := Length(FDevices);
end;

function TOpenCLManager.GetDevice(Index: Integer): TOpenCLDeviceInfo;
begin
  if (Index < 0) or (Index >= Length(FDevices)) then
    raise Exception.CreateFmt('Device index %d out of range (0..%d)',
      [Index, Length(FDevices) - 1]);
  Result := FDevices[Index];
end;

function TOpenCLManager.GetDeviceNames: TStringList;
var
  i: Integer;
  TypeStr: String;
begin
  Result := TStringList.Create;
  for i := 0 to Length(FDevices) - 1 do
  begin
    if (FDevices[i].DeviceType and CL_DEVICE_TYPE_GPU) <> 0 then
      TypeStr := 'GPU'
    else if (FDevices[i].DeviceType and CL_DEVICE_TYPE_CPU) <> 0 then
      TypeStr := 'CPU'
    else
      TypeStr := 'Other';
    Result.Add(Format('[%s] %s (%d CU, %dMB)',
      [TypeStr,
       FDevices[i].DeviceName,
       FDevices[i].MaxComputeUnits,
       FDevices[i].GlobalMemSize div (1024 * 1024)]));
  end;
end;

// ---------------------------------------------------------------------------
// SelectDevice — create context + command queue
// ---------------------------------------------------------------------------

procedure TOpenCLManager.SelectDevice(Index: Integer);
var
  Err: cl_int;
  Props: array[0..2] of cl_context_properties;
begin
  if (Index < 0) or (Index >= Length(FDevices)) then
    raise Exception.CreateFmt('Device index %d out of range', [Index]);

  // Release previous context if any
  ReleaseAll;

  FSelectedDevice := Index;

  // Create context with platform property
  Props[0] := CL_CONTEXT_PLATFORM;
  Props[1] := cl_context_properties(FDevices[Index].PlatformId);
  Props[2] := 0;  // terminator

  FContext := clCreateContext(@Props[0], 1, @FDevices[Index].DeviceId,
    nil, nil, @Err);
  CheckCL(Err, 'clCreateContext');

  // Create command queue (no profiling, in-order)
  FQueue := clCreateCommandQueue(FContext, FDevices[Index].DeviceId,
    0, @Err);
  CheckCL(Err, 'clCreateCommandQueue');
end;

function TOpenCLManager.HasContext: Boolean;
begin
  Result := (FContext <> nil) and (FQueue <> nil);
end;

// ---------------------------------------------------------------------------
// Program compilation
// ---------------------------------------------------------------------------

function TOpenCLManager.GetBuildLog(Prog: cl_program): String;
var
  LogLen: size_t;
  Log: array of AnsiChar;
begin
  Result := '';
  if (Prog = nil) or (FSelectedDevice < 0) then Exit;
  clGetProgramBuildInfo(Prog, FDevices[FSelectedDevice].DeviceId,
    CL_PROGRAM_BUILD_LOG, 0, nil, @LogLen);
  if LogLen <= 1 then Exit;
  SetLength(Log, LogLen);
  clGetProgramBuildInfo(Prog, FDevices[FSelectedDevice].DeviceId,
    CL_PROGRAM_BUILD_LOG, LogLen, @Log[0], nil);
  Result := String(PAnsiChar(@Log[0]));
end;

function TOpenCLManager.CompileSource(const Source: String;
  const Options: String): cl_program;
var
  Err: cl_int;
  SrcAnsi: AnsiString;
  SrcPtr: PAnsiChar;
  SrcLen: size_t;
  OptAnsi: AnsiString;
  OptPtr: PAnsiChar;
  BuildLog: String;
begin
  if not HasContext then
    raise Exception.Create('No OpenCL context — call SelectDevice first');

  SrcAnsi := AnsiString(Source);
  SrcPtr := PAnsiChar(SrcAnsi);
  SrcLen := Length(SrcAnsi);

  Result := clCreateProgramWithSource(FContext, 1, @SrcPtr, @SrcLen, @Err);
  CheckCL(Err, 'clCreateProgramWithSource');

  // Track for cleanup
  FPrograms.Add(Result);

  // Build
  if Options <> '' then
  begin
    OptAnsi := AnsiString(Options);
    OptPtr := PAnsiChar(OptAnsi);
  end
  else
    OptPtr := nil;

  Err := clBuildProgram(Result, 1, @FDevices[FSelectedDevice].DeviceId,
    OptPtr, nil, nil);

  if Err <> CL_SUCCESS then
  begin
    BuildLog := GetBuildLog(Result);
    raise Exception.CreateFmt(
      'OpenCL kernel build failed: %s'#13#10'Build log:'#13#10'%s',
      [CLErrorString(Err), BuildLog]);
  end;
end;

// ---------------------------------------------------------------------------
// Kernel
// ---------------------------------------------------------------------------

function TOpenCLManager.CreateKernel(Prog: cl_program;
  const KernelName: String): cl_kernel;
var
  Err: cl_int;
  NameAnsi: AnsiString;
begin
  NameAnsi := AnsiString(KernelName);
  Result := clCreateKernel(Prog, PAnsiChar(NameAnsi), @Err);
  CheckCL(Err, 'clCreateKernel(' + KernelName + ')');
  FKernels.Add(Result);
end;

// ---------------------------------------------------------------------------
// Buffers
// ---------------------------------------------------------------------------

function TOpenCLManager.CreateBuffer(Size: size_t; Flags: cl_mem_flags;
  HostPtr: Pointer): cl_mem;
var
  Err: cl_int;
begin
  Result := clCreateBuffer(FContext, Flags, Size, HostPtr, @Err);
  CheckCL(Err, 'clCreateBuffer');
  FBuffers.Add(Result);
end;

procedure TOpenCLManager.WriteBuffer(Buf: cl_mem; const Data; Size: size_t);
begin
  CheckCL(
    clEnqueueWriteBuffer(FQueue, Buf, CL_TRUE, 0, Size, @Data, 0, nil, nil),
    'clEnqueueWriteBuffer');
end;

procedure TOpenCLManager.ReadBuffer(Buf: cl_mem; out Data; Size: size_t);
begin
  CheckCL(
    clEnqueueReadBuffer(FQueue, Buf, CL_TRUE, 0, Size, @Data, 0, nil, nil),
    'clEnqueueReadBuffer');
end;

// ---------------------------------------------------------------------------
// Kernel arguments
// ---------------------------------------------------------------------------

procedure TOpenCLManager.SetKernelArgMem(K: cl_kernel; Index: cl_uint; Buf: cl_mem);
begin
  CheckCL(clSetKernelArg(K, Index, SizeOf(cl_mem), @Buf),
    'clSetKernelArg(mem,' + IntToStr(Index) + ')');
end;

procedure TOpenCLManager.SetKernelArgInt(K: cl_kernel; Index: cl_uint; Value: cl_int);
begin
  CheckCL(clSetKernelArg(K, Index, SizeOf(cl_int), @Value),
    'clSetKernelArg(int,' + IntToStr(Index) + ')');
end;

procedure TOpenCLManager.SetKernelArgFloat(K: cl_kernel; Index: cl_uint; Value: cl_float);
begin
  CheckCL(clSetKernelArg(K, Index, SizeOf(cl_float), @Value),
    'clSetKernelArg(float,' + IntToStr(Index) + ')');
end;

procedure TOpenCLManager.SetKernelArgDouble(K: cl_kernel; Index: cl_uint; Value: cl_double);
begin
  CheckCL(clSetKernelArg(K, Index, SizeOf(cl_double), @Value),
    'clSetKernelArg(double,' + IntToStr(Index) + ')');
end;

procedure TOpenCLManager.SetKernelArgRaw(K: cl_kernel; Index: cl_uint;
  Size: size_t; Value: Pointer);
begin
  CheckCL(clSetKernelArg(K, Index, Size, Value),
    'clSetKernelArg(raw,' + IntToStr(Index) + ')');
end;

// ---------------------------------------------------------------------------
// Execution
// ---------------------------------------------------------------------------

procedure TOpenCLManager.Execute2D(K: cl_kernel; GlobalW, GlobalH: size_t;
  LocalW: size_t; LocalH: size_t);
var
  GWS, LWS: array[0..1] of size_t;
  PLWS: Psize_t;
begin
  GWS[0] := GlobalW;
  GWS[1] := GlobalH;
  if (LocalW > 0) and (LocalH > 0) then
  begin
    LWS[0] := LocalW;
    LWS[1] := LocalH;
    PLWS := @LWS[0];
  end
  else
    PLWS := nil;  // let OpenCL choose

  CheckCL(
    clEnqueueNDRangeKernel(FQueue, K, 2, nil, @GWS[0], PLWS, 0, nil, nil),
    'clEnqueueNDRangeKernel(2D)');
end;

procedure TOpenCLManager.Execute1D(K: cl_kernel; GlobalSize: size_t;
  LocalSize: size_t);
var
  LS: size_t;
  PLS: Psize_t;
begin
  if LocalSize > 0 then
  begin
    LS := LocalSize;
    PLS := @LS;
  end
  else
    PLS := nil;

  CheckCL(
    clEnqueueNDRangeKernel(FQueue, K, 1, nil, @GlobalSize, PLS, 0, nil, nil),
    'clEnqueueNDRangeKernel(1D)');
end;

procedure TOpenCLManager.Finish;
begin
  if FQueue <> nil then
    CheckCL(clFinish(FQueue), 'clFinish');
end;

// ---------------------------------------------------------------------------
// Individual release
// ---------------------------------------------------------------------------

procedure TOpenCLManager.ReleaseBuffer(var Buf: cl_mem);
var
  Idx: Integer;
begin
  if Buf = nil then Exit;
  Idx := FBuffers.IndexOf(Buf);
  if Idx >= 0 then FBuffers.Delete(Idx);
  clReleaseMemObject(Buf);
  Buf := nil;
end;

procedure TOpenCLManager.ReleaseKernel(var K: cl_kernel);
var
  Idx: Integer;
begin
  if K = nil then Exit;
  Idx := FKernels.IndexOf(K);
  if Idx >= 0 then FKernels.Delete(Idx);
  clReleaseKernel(K);
  K := nil;
end;

procedure TOpenCLManager.ReleaseProgram(var Prog: cl_program);
var
  Idx: Integer;
begin
  if Prog = nil then Exit;
  Idx := FPrograms.IndexOf(Prog);
  if Idx >= 0 then FPrograms.Delete(Idx);
  clReleaseProgram(Prog);
  Prog := nil;
end;

// ---------------------------------------------------------------------------
// ReleaseAll — clean up everything in reverse order
// ---------------------------------------------------------------------------

procedure TOpenCLManager.ReleaseAll;
var
  i: Integer;
begin
  // Release kernels first (depend on programs)
  for i := FKernels.Count - 1 downto 0 do
    if FKernels[i] <> nil then
      clReleaseKernel(cl_kernel(FKernels[i]));
  FKernels.Clear;

  // Release programs
  for i := FPrograms.Count - 1 downto 0 do
    if FPrograms[i] <> nil then
      clReleaseProgram(cl_program(FPrograms[i]));
  FPrograms.Clear;

  // Release buffers
  for i := FBuffers.Count - 1 downto 0 do
    if FBuffers[i] <> nil then
      clReleaseMemObject(cl_mem(FBuffers[i]));
  FBuffers.Clear;

  // Release command queue
  if FQueue <> nil then
  begin
    clFinish(FQueue);
    clReleaseCommandQueue(FQueue);
    FQueue := nil;
  end;

  // Release context
  if FContext <> nil then
  begin
    clReleaseContext(FContext);
    FContext := nil;
  end;

  FSelectedDevice := -1;
end;

end.
