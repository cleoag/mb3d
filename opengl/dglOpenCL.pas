unit dglOpenCL;
{ OpenCL 1.2 dynamic binding for Free Pascal / Win32.
  Follows the same pattern as dglOpenGL.pas:
    1. Type aliases
    2. Constants
    3. Function pointer types
    4. Global function pointer variables
    5. Dynamic DLL loading via LoadLibrary / GetProcAddress

  Usage:
    if InitOpenCL then begin
      // OpenCL available — enumerate platforms, create context, etc.
    end else begin
      // No GPU / no driver — graceful fallback
    end;

  All function pointers start as nil. If InitOpenCL succeeds but a specific
  function is nil, that entry point is not exported by the installed driver. }

{$mode delphi}
{$H+}

interface

uses
  Windows, SysUtils;

// ============================================================================
// Layer 1: OpenCL scalar types
// ============================================================================
type
  cl_char      = ShortInt;
  cl_uchar     = Byte;
  cl_short     = SmallInt;
  cl_ushort    = Word;
  cl_int       = LongInt;
  cl_uint      = LongWord;
  cl_long      = Int64;
  cl_ulong     = UInt64;
  cl_half      = Word;
  cl_float     = Single;
  cl_double    = Double;
  cl_bool      = cl_uint;
  cl_bitfield  = cl_ulong;

  size_t       = NativeUInt;
  Psize_t      = ^size_t;
  intptr_t     = NativeInt;
  Pintptr_t    = ^intptr_t;

  // Opaque handle types (all pointers)
  cl_platform_id   = Pointer;
  cl_device_id     = Pointer;
  cl_context       = Pointer;
  cl_command_queue  = Pointer;
  cl_mem           = Pointer;
  cl_program       = Pointer;
  cl_kernel        = Pointer;
  cl_event         = Pointer;
  cl_sampler       = Pointer;

  // Pointer-to-handle types
  Pcl_platform_id  = ^cl_platform_id;
  Pcl_device_id    = ^cl_device_id;
  Pcl_context      = ^cl_context;
  Pcl_command_queue = ^cl_command_queue;
  Pcl_mem          = ^cl_mem;
  Pcl_program      = ^cl_program;
  Pcl_kernel       = ^cl_kernel;
  Pcl_event        = ^cl_event;

  // Scalar pointer types
  Pcl_int          = ^cl_int;
  Pcl_uint         = ^cl_uint;
  Pcl_ulong        = ^cl_ulong;

  // Enum types (all cl_uint or cl_int based)
  cl_platform_info     = cl_uint;
  cl_device_info       = cl_uint;
  cl_device_type       = cl_bitfield;
  cl_context_info      = cl_uint;
  cl_context_properties = intptr_t;
  Pcl_context_properties = ^cl_context_properties;
  cl_command_queue_properties = cl_bitfield;
  cl_mem_flags         = cl_bitfield;
  cl_mem_info          = cl_uint;
  cl_mem_object_type   = cl_uint;
  cl_buffer_create_type = cl_uint;
  cl_image_info        = cl_uint;
  cl_addressing_mode   = cl_uint;
  cl_filter_mode       = cl_uint;
  cl_sampler_info      = cl_uint;
  cl_program_info      = cl_uint;
  cl_program_build_info = cl_uint;
  cl_build_status      = cl_int;
  cl_kernel_info       = cl_uint;
  cl_kernel_work_group_info = cl_uint;
  cl_event_info        = cl_uint;
  cl_command_type      = cl_uint;
  cl_profiling_info    = cl_uint;
  cl_map_flags         = cl_bitfield;

  // Image format
  cl_image_format = packed record
    image_channel_order:     cl_uint;
    image_channel_data_type: cl_uint;
  end;
  Pcl_image_format = ^cl_image_format;

  // Image descriptor (OpenCL 1.2)
  cl_image_desc = packed record
    image_type:        cl_mem_object_type;
    image_width:       size_t;
    image_height:      size_t;
    image_depth:       size_t;
    image_array_size:  size_t;
    image_row_pitch:   size_t;
    image_slice_pitch: size_t;
    num_mip_levels:    cl_uint;
    num_samples:       cl_uint;
    buffer:            cl_mem;
  end;
  Pcl_image_desc = ^cl_image_desc;

  // Callback types
  TclContextNotify = procedure(errinfo: PAnsiChar; private_info: Pointer;
    cb: size_t; user_data: Pointer); stdcall;
  TclProgramNotify = procedure(prog: cl_program; user_data: Pointer); stdcall;
  TclMemObjectDestructorNotify = procedure(memobj: cl_mem;
    user_data: Pointer); stdcall;
  TclEventNotify = procedure(event: cl_event; event_command_exec_status: cl_int;
    user_data: Pointer); stdcall;

// ============================================================================
// Layer 2: OpenCL constants
// ============================================================================
const
  // Error codes
  CL_SUCCESS                         = 0;
  CL_DEVICE_NOT_FOUND                = -1;
  CL_DEVICE_NOT_AVAILABLE            = -2;
  CL_COMPILER_NOT_AVAILABLE          = -3;
  CL_MEM_OBJECT_ALLOCATION_FAILURE   = -4;
  CL_OUT_OF_RESOURCES                = -5;
  CL_OUT_OF_HOST_MEMORY              = -6;
  CL_PROFILING_INFO_NOT_AVAILABLE    = -7;
  CL_MEM_COPY_OVERLAP               = -8;
  CL_IMAGE_FORMAT_MISMATCH           = -9;
  CL_IMAGE_FORMAT_NOT_SUPPORTED      = -10;
  CL_BUILD_PROGRAM_FAILURE           = -11;
  CL_MAP_FAILURE                     = -12;
  CL_MISALIGNED_SUB_BUFFER_OFFSET    = -13;
  CL_EXEC_STATUS_ERROR_FOR_EVENTS_IN_WAIT_LIST = -14;
  CL_COMPILE_PROGRAM_FAILURE         = -15;
  CL_LINKER_NOT_AVAILABLE            = -16;
  CL_LINK_PROGRAM_FAILURE            = -17;
  CL_DEVICE_PARTITION_FAILED         = -18;
  CL_KERNEL_ARG_INFO_NOT_AVAILABLE   = -19;
  CL_INVALID_VALUE                   = -30;
  CL_INVALID_DEVICE_TYPE             = -31;
  CL_INVALID_PLATFORM                = -32;
  CL_INVALID_DEVICE                  = -33;
  CL_INVALID_CONTEXT                 = -34;
  CL_INVALID_QUEUE_PROPERTIES        = -35;
  CL_INVALID_COMMAND_QUEUE           = -36;
  CL_INVALID_HOST_PTR                = -37;
  CL_INVALID_MEM_OBJECT              = -38;
  CL_INVALID_IMAGE_FORMAT_DESCRIPTOR = -39;
  CL_INVALID_IMAGE_SIZE              = -40;
  CL_INVALID_SAMPLER                 = -41;
  CL_INVALID_BINARY                  = -42;
  CL_INVALID_BUILD_OPTIONS           = -43;
  CL_INVALID_PROGRAM                 = -44;
  CL_INVALID_PROGRAM_EXECUTABLE      = -45;
  CL_INVALID_KERNEL_NAME             = -46;
  CL_INVALID_KERNEL_DEFINITION       = -47;
  CL_INVALID_KERNEL                  = -48;
  CL_INVALID_ARG_INDEX               = -49;
  CL_INVALID_ARG_VALUE               = -50;
  CL_INVALID_ARG_SIZE                = -51;
  CL_INVALID_KERNEL_ARGS             = -52;
  CL_INVALID_WORK_DIMENSION          = -53;
  CL_INVALID_WORK_GROUP_SIZE         = -54;
  CL_INVALID_WORK_ITEM_SIZE          = -55;
  CL_INVALID_GLOBAL_OFFSET           = -56;
  CL_INVALID_EVENT_WAIT_LIST         = -57;
  CL_INVALID_EVENT                   = -58;
  CL_INVALID_OPERATION               = -59;
  CL_INVALID_GL_OBJECT               = -60;
  CL_INVALID_BUFFER_SIZE             = -61;
  CL_INVALID_MIP_LEVEL               = -62;
  CL_INVALID_GLOBAL_WORK_SIZE        = -63;
  CL_INVALID_PROPERTY                = -64;
  CL_INVALID_IMAGE_DESCRIPTOR        = -65;
  CL_INVALID_COMPILER_OPTIONS        = -66;
  CL_INVALID_LINKER_OPTIONS          = -67;
  CL_INVALID_DEVICE_PARTITION_COUNT  = -68;

  // cl_bool
  CL_FALSE = 0;
  CL_TRUE  = 1;

  // cl_device_type
  CL_DEVICE_TYPE_DEFAULT     = cl_bitfield(1 shl 0);
  CL_DEVICE_TYPE_CPU         = cl_bitfield(1 shl 1);
  CL_DEVICE_TYPE_GPU         = cl_bitfield(1 shl 2);
  CL_DEVICE_TYPE_ACCELERATOR = cl_bitfield(1 shl 3);
  CL_DEVICE_TYPE_ALL         = cl_bitfield($FFFFFFFF);

  // cl_platform_info
  CL_PLATFORM_PROFILE    = $0900;
  CL_PLATFORM_VERSION    = $0901;
  CL_PLATFORM_NAME       = $0902;
  CL_PLATFORM_VENDOR     = $0903;
  CL_PLATFORM_EXTENSIONS = $0904;

  // cl_device_info
  CL_DEVICE_TYPE_INFO                    = $1000;
  CL_DEVICE_VENDOR_ID                    = $1001;
  CL_DEVICE_MAX_COMPUTE_UNITS           = $1002;
  CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS    = $1003;
  CL_DEVICE_MAX_WORK_GROUP_SIZE         = $1004;
  CL_DEVICE_MAX_WORK_ITEM_SIZES         = $1005;
  CL_DEVICE_PREFERRED_VECTOR_WIDTH_CHAR = $1006;
  CL_DEVICE_PREFERRED_VECTOR_WIDTH_SHORT = $1007;
  CL_DEVICE_PREFERRED_VECTOR_WIDTH_INT  = $1008;
  CL_DEVICE_PREFERRED_VECTOR_WIDTH_LONG = $1009;
  CL_DEVICE_PREFERRED_VECTOR_WIDTH_FLOAT = $100A;
  CL_DEVICE_PREFERRED_VECTOR_WIDTH_DOUBLE = $100B;
  CL_DEVICE_MAX_CLOCK_FREQUENCY         = $100C;
  CL_DEVICE_ADDRESS_BITS                = $100D;
  CL_DEVICE_MAX_READ_IMAGE_ARGS         = $100E;
  CL_DEVICE_MAX_WRITE_IMAGE_ARGS        = $100F;
  CL_DEVICE_MAX_MEM_ALLOC_SIZE          = $1010;
  CL_DEVICE_GLOBAL_MEM_SIZE             = $101F;
  CL_DEVICE_LOCAL_MEM_SIZE              = $1023;
  CL_DEVICE_ERROR_CORRECTION_SUPPORT    = $1024;
  CL_DEVICE_PROFILING_TIMER_RESOLUTION  = $1025;
  CL_DEVICE_ENDIAN_LITTLE              = $1026;
  CL_DEVICE_AVAILABLE                   = $1027;
  CL_DEVICE_COMPILER_AVAILABLE          = $1028;
  CL_DEVICE_EXECUTION_CAPABILITIES      = $1029;
  CL_DEVICE_NAME                        = $102B;
  CL_DEVICE_VENDOR                      = $102C;
  CL_DRIVER_VERSION                     = $102D;
  CL_DEVICE_PROFILE                     = $102E;
  CL_DEVICE_VERSION                     = $102F;
  CL_DEVICE_EXTENSIONS                  = $1030;
  CL_DEVICE_PLATFORM                    = $1031;
  CL_DEVICE_DOUBLE_FP_CONFIG            = $1032;
  CL_DEVICE_MAX_PARAMETER_SIZE          = $1034;
  CL_DEVICE_IMAGE_SUPPORT               = $1036;

  // cl_context_info
  CL_CONTEXT_REFERENCE_COUNT = $1080;
  CL_CONTEXT_DEVICES         = $1081;
  CL_CONTEXT_PROPERTIES_INFO = $1082;
  CL_CONTEXT_NUM_DEVICES     = $1083;

  // cl_context_properties
  CL_CONTEXT_PLATFORM        = $1084;

  // cl_mem_flags
  CL_MEM_READ_WRITE     = cl_bitfield(1 shl 0);
  CL_MEM_WRITE_ONLY     = cl_bitfield(1 shl 1);
  CL_MEM_READ_ONLY      = cl_bitfield(1 shl 2);
  CL_MEM_USE_HOST_PTR   = cl_bitfield(1 shl 3);
  CL_MEM_ALLOC_HOST_PTR = cl_bitfield(1 shl 4);
  CL_MEM_COPY_HOST_PTR  = cl_bitfield(1 shl 5);

  // cl_program_info
  CL_PROGRAM_REFERENCE_COUNT = $1160;
  CL_PROGRAM_CONTEXT         = $1161;
  CL_PROGRAM_NUM_DEVICES     = $1162;
  CL_PROGRAM_DEVICES         = $1163;
  CL_PROGRAM_SOURCE          = $1164;
  CL_PROGRAM_BINARY_SIZES    = $1165;
  CL_PROGRAM_BINARIES        = $1166;
  CL_PROGRAM_NUM_KERNELS     = $1167;
  CL_PROGRAM_KERNEL_NAMES    = $1168;

  // cl_program_build_info
  CL_PROGRAM_BUILD_STATUS  = $1181;
  CL_PROGRAM_BUILD_OPTIONS = $1182;
  CL_PROGRAM_BUILD_LOG     = $1183;

  // cl_build_status
  CL_BUILD_SUCCESS     =  0;
  CL_BUILD_NONE        = -1;
  CL_BUILD_ERROR       = -2;
  CL_BUILD_IN_PROGRESS = -3;

  // cl_kernel_info
  CL_KERNEL_FUNCTION_NAME   = $1190;
  CL_KERNEL_NUM_ARGS        = $1191;
  CL_KERNEL_REFERENCE_COUNT = $1192;
  CL_KERNEL_CONTEXT         = $1193;
  CL_KERNEL_PROGRAM         = $1194;

  // cl_kernel_work_group_info
  CL_KERNEL_WORK_GROUP_SIZE                  = $11B0;
  CL_KERNEL_COMPILE_WORK_GROUP_SIZE          = $11B1;
  CL_KERNEL_LOCAL_MEM_SIZE                   = $11B2;
  CL_KERNEL_PREFERRED_WORK_GROUP_SIZE_MULTIPLE = $11B3;
  CL_KERNEL_PRIVATE_MEM_SIZE                 = $11B4;

  // cl_command_queue_properties
  CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE = cl_bitfield(1 shl 0);
  CL_QUEUE_PROFILING_ENABLE              = cl_bitfield(1 shl 1);

  // cl_event_info
  CL_EVENT_COMMAND_QUEUE            = $11D0;
  CL_EVENT_COMMAND_TYPE             = $11D1;
  CL_EVENT_REFERENCE_COUNT          = $11D2;
  CL_EVENT_COMMAND_EXECUTION_STATUS = $11D3;
  CL_EVENT_CONTEXT                  = $11D4;

  // cl_profiling_info
  CL_PROFILING_COMMAND_QUEUED = $1280;
  CL_PROFILING_COMMAND_SUBMIT = $1281;
  CL_PROFILING_COMMAND_START  = $1282;
  CL_PROFILING_COMMAND_END    = $1283;

  // cl_command_queue_info
  CL_QUEUE_CONTEXT    = $1090;
  CL_QUEUE_DEVICE     = $1091;
  CL_QUEUE_REFERENCE_COUNT = $1092;
  CL_QUEUE_PROPERTIES_INFO = $1093;

  // cl_mem_info
  CL_MEM_TYPE            = $1100;
  CL_MEM_FLAGS_INFO      = $1101;
  CL_MEM_SIZE            = $1102;
  CL_MEM_HOST_PTR        = $1103;
  CL_MEM_MAP_COUNT       = $1104;
  CL_MEM_REFERENCE_COUNT = $1105;
  CL_MEM_CONTEXT         = $1106;

// ============================================================================
// Layer 3: Function pointer types
// ============================================================================
type
  // Platform API
  TclGetPlatformIDs = function(
    num_entries: cl_uint;
    platforms: Pcl_platform_id;
    num_platforms: Pcl_uint): cl_int; stdcall;

  TclGetPlatformInfo = function(
    platform: cl_platform_id;
    param_name: cl_platform_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

  // Device API
  TclGetDeviceIDs = function(
    platform: cl_platform_id;
    device_type: cl_device_type;
    num_entries: cl_uint;
    devices: Pcl_device_id;
    num_devices: Pcl_uint): cl_int; stdcall;

  TclGetDeviceInfo = function(
    device: cl_device_id;
    param_name: cl_device_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

  // Context API
  TclCreateContext = function(
    properties: Pcl_context_properties;
    num_devices: cl_uint;
    devices: Pcl_device_id;
    pfn_notify: TclContextNotify;
    user_data: Pointer;
    errcode_ret: Pcl_int): cl_context; stdcall;

  TclRetainContext = function(context: cl_context): cl_int; stdcall;
  TclReleaseContext = function(context: cl_context): cl_int; stdcall;

  TclGetContextInfo = function(
    context: cl_context;
    param_name: cl_context_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

  // Command Queue API
  TclCreateCommandQueue = function(
    context: cl_context;
    device: cl_device_id;
    properties: cl_command_queue_properties;
    errcode_ret: Pcl_int): cl_command_queue; stdcall;

  TclRetainCommandQueue = function(queue: cl_command_queue): cl_int; stdcall;
  TclReleaseCommandQueue = function(queue: cl_command_queue): cl_int; stdcall;
  TclFlush = function(queue: cl_command_queue): cl_int; stdcall;
  TclFinish = function(queue: cl_command_queue): cl_int; stdcall;

  // Memory Object API
  TclCreateBuffer = function(
    context: cl_context;
    flags: cl_mem_flags;
    size: size_t;
    host_ptr: Pointer;
    errcode_ret: Pcl_int): cl_mem; stdcall;

  TclRetainMemObject = function(memobj: cl_mem): cl_int; stdcall;
  TclReleaseMemObject = function(memobj: cl_mem): cl_int; stdcall;

  TclEnqueueReadBuffer = function(
    queue: cl_command_queue;
    buffer: cl_mem;
    blocking_read: cl_bool;
    offset: size_t;
    size: size_t;
    ptr: Pointer;
    num_events_in_wait_list: cl_uint;
    event_wait_list: Pcl_event;
    event: Pcl_event): cl_int; stdcall;

  TclEnqueueWriteBuffer = function(
    queue: cl_command_queue;
    buffer: cl_mem;
    blocking_write: cl_bool;
    offset: size_t;
    size: size_t;
    ptr: Pointer;
    num_events_in_wait_list: cl_uint;
    event_wait_list: Pcl_event;
    event: Pcl_event): cl_int; stdcall;

  TclEnqueueCopyBuffer = function(
    queue: cl_command_queue;
    src_buffer: cl_mem;
    dst_buffer: cl_mem;
    src_offset: size_t;
    dst_offset: size_t;
    size: size_t;
    num_events_in_wait_list: cl_uint;
    event_wait_list: Pcl_event;
    event: Pcl_event): cl_int; stdcall;

  TclEnqueueMapBuffer = function(
    queue: cl_command_queue;
    buffer: cl_mem;
    blocking_map: cl_bool;
    map_flags: cl_map_flags;
    offset: size_t;
    size: size_t;
    num_events_in_wait_list: cl_uint;
    event_wait_list: Pcl_event;
    event: Pcl_event;
    errcode_ret: Pcl_int): Pointer; stdcall;

  TclEnqueueUnmapMemObject = function(
    queue: cl_command_queue;
    memobj: cl_mem;
    mapped_ptr: Pointer;
    num_events_in_wait_list: cl_uint;
    event_wait_list: Pcl_event;
    event: Pcl_event): cl_int; stdcall;

  TclGetMemObjectInfo = function(
    memobj: cl_mem;
    param_name: cl_mem_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

  // Program API
  TclCreateProgramWithSource = function(
    context: cl_context;
    count: cl_uint;
    strings: PPAnsiChar;
    lengths: Psize_t;
    errcode_ret: Pcl_int): cl_program; stdcall;

  TclCreateProgramWithBinary = function(
    context: cl_context;
    num_devices: cl_uint;
    device_list: Pcl_device_id;
    lengths: Psize_t;
    binaries: PPAnsiChar;
    binary_status: Pcl_int;
    errcode_ret: Pcl_int): cl_program; stdcall;

  TclRetainProgram = function(prog: cl_program): cl_int; stdcall;
  TclReleaseProgram = function(prog: cl_program): cl_int; stdcall;

  TclBuildProgram = function(
    prog: cl_program;
    num_devices: cl_uint;
    device_list: Pcl_device_id;
    options: PAnsiChar;
    pfn_notify: TclProgramNotify;
    user_data: Pointer): cl_int; stdcall;

  TclGetProgramInfo = function(
    prog: cl_program;
    param_name: cl_program_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

  TclGetProgramBuildInfo = function(
    prog: cl_program;
    device: cl_device_id;
    param_name: cl_program_build_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

  // Kernel API
  TclCreateKernel = function(
    prog: cl_program;
    kernel_name: PAnsiChar;
    errcode_ret: Pcl_int): cl_kernel; stdcall;

  TclRetainKernel = function(kernel: cl_kernel): cl_int; stdcall;
  TclReleaseKernel = function(kernel: cl_kernel): cl_int; stdcall;

  TclSetKernelArg = function(
    kernel: cl_kernel;
    arg_index: cl_uint;
    arg_size: size_t;
    arg_value: Pointer): cl_int; stdcall;

  TclGetKernelInfo = function(
    kernel: cl_kernel;
    param_name: cl_kernel_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

  TclGetKernelWorkGroupInfo = function(
    kernel: cl_kernel;
    device: cl_device_id;
    param_name: cl_kernel_work_group_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

  // Enqueue API
  TclEnqueueNDRangeKernel = function(
    queue: cl_command_queue;
    kernel: cl_kernel;
    work_dim: cl_uint;
    global_work_offset: Psize_t;
    global_work_size: Psize_t;
    local_work_size: Psize_t;
    num_events_in_wait_list: cl_uint;
    event_wait_list: Pcl_event;
    event: Pcl_event): cl_int; stdcall;

  // Event API
  TclWaitForEvents = function(
    num_events: cl_uint;
    event_list: Pcl_event): cl_int; stdcall;

  TclGetEventInfo = function(
    event: cl_event;
    param_name: cl_event_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

  TclRetainEvent = function(event: cl_event): cl_int; stdcall;
  TclReleaseEvent = function(event: cl_event): cl_int; stdcall;

  TclGetEventProfilingInfo = function(
    event: cl_event;
    param_name: cl_profiling_info;
    param_value_size: size_t;
    param_value: Pointer;
    param_value_size_ret: Psize_t): cl_int; stdcall;

// ============================================================================
// Layer 4: Global function pointer variables
// ============================================================================
var
  // Platform
  clGetPlatformIDs:         TclGetPlatformIDs;
  clGetPlatformInfo:        TclGetPlatformInfo;
  // Device
  clGetDeviceIDs:           TclGetDeviceIDs;
  clGetDeviceInfo:          TclGetDeviceInfo;
  // Context
  clCreateContext:          TclCreateContext;
  clRetainContext:          TclRetainContext;
  clReleaseContext:         TclReleaseContext;
  clGetContextInfo:         TclGetContextInfo;
  // Command Queue
  clCreateCommandQueue:     TclCreateCommandQueue;
  clRetainCommandQueue:     TclRetainCommandQueue;
  clReleaseCommandQueue:    TclReleaseCommandQueue;
  clFlush:                  TclFlush;
  clFinish:                 TclFinish;
  // Memory
  clCreateBuffer:           TclCreateBuffer;
  clRetainMemObject:        TclRetainMemObject;
  clReleaseMemObject:       TclReleaseMemObject;
  clEnqueueReadBuffer:      TclEnqueueReadBuffer;
  clEnqueueWriteBuffer:     TclEnqueueWriteBuffer;
  clEnqueueCopyBuffer:      TclEnqueueCopyBuffer;
  clEnqueueMapBuffer:       TclEnqueueMapBuffer;
  clEnqueueUnmapMemObject:  TclEnqueueUnmapMemObject;
  clGetMemObjectInfo:       TclGetMemObjectInfo;
  // Program
  clCreateProgramWithSource: TclCreateProgramWithSource;
  clCreateProgramWithBinary: TclCreateProgramWithBinary;
  clRetainProgram:          TclRetainProgram;
  clReleaseProgram:         TclReleaseProgram;
  clBuildProgram:           TclBuildProgram;
  clGetProgramInfo:         TclGetProgramInfo;
  clGetProgramBuildInfo:    TclGetProgramBuildInfo;
  // Kernel
  clCreateKernel:           TclCreateKernel;
  clRetainKernel:           TclRetainKernel;
  clReleaseKernel:          TclReleaseKernel;
  clSetKernelArg:           TclSetKernelArg;
  clGetKernelInfo:          TclGetKernelInfo;
  clGetKernelWorkGroupInfo: TclGetKernelWorkGroupInfo;
  // Enqueue
  clEnqueueNDRangeKernel:   TclEnqueueNDRangeKernel;
  // Events
  clWaitForEvents:          TclWaitForEvents;
  clGetEventInfo:           TclGetEventInfo;
  clRetainEvent:            TclRetainEvent;
  clReleaseEvent:           TclReleaseEvent;
  clGetEventProfilingInfo:  TclGetEventProfilingInfo;

  // Library handle (nil = not loaded)
  CL_LibHandle: Pointer = nil;

const
  OPENCL_LIBNAME = 'OpenCL.dll';

// ============================================================================
// Layer 5: Public API
// ============================================================================

{ Load OpenCL.dll and resolve all function pointers.
  Returns True if DLL loaded successfully.
  Individual function pointers may still be nil if not exported. }
function InitOpenCL(const LibName: String = OPENCL_LIBNAME): Boolean;

{ Release the OpenCL.dll handle and nil all function pointers. }
procedure FreeOpenCL;

{ Returns True if OpenCL.dll is loaded and core functions are available. }
function OpenCLAvailable: Boolean;

{ Get human-readable error string for an OpenCL error code. }
function CLErrorString(ErrorCode: cl_int): String;

implementation

// ---------------------------------------------------------------------------
// DLL loading helpers (mirror dglOpenGL.pas pattern)
// ---------------------------------------------------------------------------

function clLoadLibrary(const Name: String): Pointer;
begin
  Result := Pointer(LoadLibrary(PChar(Name)));
end;

function clFreeLibrary(LibHandle: Pointer): Boolean;
begin
  if LibHandle = nil then
    Result := False
  else
    Result := FreeLibrary(HMODULE(LibHandle));
end;

function clGetProcAddr(const ProcName: PAnsiChar): Pointer;
begin
  if CL_LibHandle = nil then
    Result := nil
  else
    Result := GetProcAddress(HMODULE(CL_LibHandle), ProcName);
end;

// ---------------------------------------------------------------------------
// InitOpenCL
// ---------------------------------------------------------------------------

function InitOpenCL(const LibName: String): Boolean;
begin
  Result := False;

  // Release previous handle if any
  if CL_LibHandle <> nil then
  begin
    clFreeLibrary(CL_LibHandle);
    CL_LibHandle := nil;
  end;

  // Load the DLL
  CL_LibHandle := clLoadLibrary(LibName);
  if CL_LibHandle = nil then Exit;

  // Resolve all function pointers
  // Platform
  clGetPlatformIDs         := clGetProcAddr('clGetPlatformIDs');
  clGetPlatformInfo        := clGetProcAddr('clGetPlatformInfo');
  // Device
  clGetDeviceIDs           := clGetProcAddr('clGetDeviceIDs');
  clGetDeviceInfo          := clGetProcAddr('clGetDeviceInfo');
  // Context
  clCreateContext           := clGetProcAddr('clCreateContext');
  clRetainContext           := clGetProcAddr('clRetainContext');
  clReleaseContext          := clGetProcAddr('clReleaseContext');
  clGetContextInfo          := clGetProcAddr('clGetContextInfo');
  // Command Queue
  clCreateCommandQueue      := clGetProcAddr('clCreateCommandQueue');
  clRetainCommandQueue      := clGetProcAddr('clRetainCommandQueue');
  clReleaseCommandQueue     := clGetProcAddr('clReleaseCommandQueue');
  clFlush                   := clGetProcAddr('clFlush');
  clFinish                  := clGetProcAddr('clFinish');
  // Memory
  clCreateBuffer            := clGetProcAddr('clCreateBuffer');
  clRetainMemObject         := clGetProcAddr('clRetainMemObject');
  clReleaseMemObject        := clGetProcAddr('clReleaseMemObject');
  clEnqueueReadBuffer       := clGetProcAddr('clEnqueueReadBuffer');
  clEnqueueWriteBuffer      := clGetProcAddr('clEnqueueWriteBuffer');
  clEnqueueCopyBuffer       := clGetProcAddr('clEnqueueCopyBuffer');
  clEnqueueMapBuffer        := clGetProcAddr('clEnqueueMapBuffer');
  clEnqueueUnmapMemObject   := clGetProcAddr('clEnqueueUnmapMemObject');
  clGetMemObjectInfo        := clGetProcAddr('clGetMemObjectInfo');
  // Program
  clCreateProgramWithSource := clGetProcAddr('clCreateProgramWithSource');
  clCreateProgramWithBinary := clGetProcAddr('clCreateProgramWithBinary');
  clRetainProgram           := clGetProcAddr('clRetainProgram');
  clReleaseProgram          := clGetProcAddr('clReleaseProgram');
  clBuildProgram            := clGetProcAddr('clBuildProgram');
  clGetProgramInfo          := clGetProcAddr('clGetProgramInfo');
  clGetProgramBuildInfo     := clGetProcAddr('clGetProgramBuildInfo');
  // Kernel
  clCreateKernel            := clGetProcAddr('clCreateKernel');
  clRetainKernel            := clGetProcAddr('clRetainKernel');
  clReleaseKernel           := clGetProcAddr('clReleaseKernel');
  clSetKernelArg            := clGetProcAddr('clSetKernelArg');
  clGetKernelInfo           := clGetProcAddr('clGetKernelInfo');
  clGetKernelWorkGroupInfo  := clGetProcAddr('clGetKernelWorkGroupInfo');
  // Enqueue
  clEnqueueNDRangeKernel    := clGetProcAddr('clEnqueueNDRangeKernel');
  // Events
  clWaitForEvents           := clGetProcAddr('clWaitForEvents');
  clGetEventInfo            := clGetProcAddr('clGetEventInfo');
  clRetainEvent             := clGetProcAddr('clRetainEvent');
  clReleaseEvent            := clGetProcAddr('clReleaseEvent');
  clGetEventProfilingInfo   := clGetProcAddr('clGetEventProfilingInfo');

  Result := True;
end;

// ---------------------------------------------------------------------------
// FreeOpenCL
// ---------------------------------------------------------------------------

procedure FreeOpenCL;
begin
  if CL_LibHandle <> nil then
  begin
    clFreeLibrary(CL_LibHandle);
    CL_LibHandle := nil;
  end;

  // Nil all function pointers
  clGetPlatformIDs         := nil;
  clGetPlatformInfo        := nil;
  clGetDeviceIDs           := nil;
  clGetDeviceInfo          := nil;
  clCreateContext           := nil;
  clRetainContext           := nil;
  clReleaseContext          := nil;
  clGetContextInfo          := nil;
  clCreateCommandQueue      := nil;
  clRetainCommandQueue      := nil;
  clReleaseCommandQueue     := nil;
  clFlush                   := nil;
  clFinish                  := nil;
  clCreateBuffer            := nil;
  clRetainMemObject         := nil;
  clReleaseMemObject        := nil;
  clEnqueueReadBuffer       := nil;
  clEnqueueWriteBuffer      := nil;
  clEnqueueCopyBuffer       := nil;
  clEnqueueMapBuffer        := nil;
  clEnqueueUnmapMemObject   := nil;
  clGetMemObjectInfo        := nil;
  clCreateProgramWithSource := nil;
  clCreateProgramWithBinary := nil;
  clRetainProgram           := nil;
  clReleaseProgram          := nil;
  clBuildProgram            := nil;
  clGetProgramInfo          := nil;
  clGetProgramBuildInfo     := nil;
  clCreateKernel            := nil;
  clRetainKernel            := nil;
  clReleaseKernel           := nil;
  clSetKernelArg            := nil;
  clGetKernelInfo           := nil;
  clGetKernelWorkGroupInfo  := nil;
  clEnqueueNDRangeKernel    := nil;
  clWaitForEvents           := nil;
  clGetEventInfo            := nil;
  clRetainEvent             := nil;
  clReleaseEvent            := nil;
  clGetEventProfilingInfo   := nil;
end;

// ---------------------------------------------------------------------------
// OpenCLAvailable
// ---------------------------------------------------------------------------

function OpenCLAvailable: Boolean;
begin
  Result := (CL_LibHandle <> nil) and Assigned(clGetPlatformIDs)
    and Assigned(clCreateContext) and Assigned(clCreateCommandQueue)
    and Assigned(clCreateProgramWithSource) and Assigned(clBuildProgram)
    and Assigned(clCreateKernel) and Assigned(clEnqueueNDRangeKernel);
end;

// ---------------------------------------------------------------------------
// CLErrorString
// ---------------------------------------------------------------------------

function CLErrorString(ErrorCode: cl_int): String;
begin
  case ErrorCode of
    CL_SUCCESS:                        Result := 'CL_SUCCESS';
    CL_DEVICE_NOT_FOUND:               Result := 'CL_DEVICE_NOT_FOUND';
    CL_DEVICE_NOT_AVAILABLE:           Result := 'CL_DEVICE_NOT_AVAILABLE';
    CL_COMPILER_NOT_AVAILABLE:         Result := 'CL_COMPILER_NOT_AVAILABLE';
    CL_MEM_OBJECT_ALLOCATION_FAILURE:  Result := 'CL_MEM_OBJECT_ALLOCATION_FAILURE';
    CL_OUT_OF_RESOURCES:               Result := 'CL_OUT_OF_RESOURCES';
    CL_OUT_OF_HOST_MEMORY:             Result := 'CL_OUT_OF_HOST_MEMORY';
    CL_BUILD_PROGRAM_FAILURE:          Result := 'CL_BUILD_PROGRAM_FAILURE';
    CL_INVALID_VALUE:                  Result := 'CL_INVALID_VALUE';
    CL_INVALID_DEVICE_TYPE:            Result := 'CL_INVALID_DEVICE_TYPE';
    CL_INVALID_PLATFORM:               Result := 'CL_INVALID_PLATFORM';
    CL_INVALID_DEVICE:                 Result := 'CL_INVALID_DEVICE';
    CL_INVALID_CONTEXT:                Result := 'CL_INVALID_CONTEXT';
    CL_INVALID_QUEUE_PROPERTIES:       Result := 'CL_INVALID_QUEUE_PROPERTIES';
    CL_INVALID_COMMAND_QUEUE:          Result := 'CL_INVALID_COMMAND_QUEUE';
    CL_INVALID_HOST_PTR:               Result := 'CL_INVALID_HOST_PTR';
    CL_INVALID_MEM_OBJECT:             Result := 'CL_INVALID_MEM_OBJECT';
    CL_INVALID_BINARY:                 Result := 'CL_INVALID_BINARY';
    CL_INVALID_BUILD_OPTIONS:          Result := 'CL_INVALID_BUILD_OPTIONS';
    CL_INVALID_PROGRAM:                Result := 'CL_INVALID_PROGRAM';
    CL_INVALID_PROGRAM_EXECUTABLE:     Result := 'CL_INVALID_PROGRAM_EXECUTABLE';
    CL_INVALID_KERNEL_NAME:            Result := 'CL_INVALID_KERNEL_NAME';
    CL_INVALID_KERNEL_DEFINITION:      Result := 'CL_INVALID_KERNEL_DEFINITION';
    CL_INVALID_KERNEL:                 Result := 'CL_INVALID_KERNEL';
    CL_INVALID_ARG_INDEX:              Result := 'CL_INVALID_ARG_INDEX';
    CL_INVALID_ARG_VALUE:              Result := 'CL_INVALID_ARG_VALUE';
    CL_INVALID_ARG_SIZE:               Result := 'CL_INVALID_ARG_SIZE';
    CL_INVALID_KERNEL_ARGS:            Result := 'CL_INVALID_KERNEL_ARGS';
    CL_INVALID_WORK_DIMENSION:         Result := 'CL_INVALID_WORK_DIMENSION';
    CL_INVALID_WORK_GROUP_SIZE:        Result := 'CL_INVALID_WORK_GROUP_SIZE';
    CL_INVALID_WORK_ITEM_SIZE:         Result := 'CL_INVALID_WORK_ITEM_SIZE';
    CL_INVALID_GLOBAL_OFFSET:          Result := 'CL_INVALID_GLOBAL_OFFSET';
    CL_INVALID_EVENT_WAIT_LIST:        Result := 'CL_INVALID_EVENT_WAIT_LIST';
    CL_INVALID_EVENT:                  Result := 'CL_INVALID_EVENT';
    CL_INVALID_OPERATION:              Result := 'CL_INVALID_OPERATION';
    CL_INVALID_BUFFER_SIZE:            Result := 'CL_INVALID_BUFFER_SIZE';
    CL_INVALID_GLOBAL_WORK_SIZE:       Result := 'CL_INVALID_GLOBAL_WORK_SIZE';
  else
    Result := 'CL_UNKNOWN_ERROR(' + IntToStr(ErrorCode) + ')';
  end;
end;

// ---------------------------------------------------------------------------
// Finalization — auto-release on unit unload
// ---------------------------------------------------------------------------

finalization
  FreeOpenCL;

end.
