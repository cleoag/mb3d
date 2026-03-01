// ============================================================================
// common.cl — Shared types and math helpers for MB3D GPU ray marching
// ============================================================================
// All coordinates use double precision (float64) for CPU-identical results.
// Devices without cl_khr_fp64 cannot run these kernels.

#pragma OPENCL EXTENSION cl_khr_fp64 : enable

// ============================================================================
// Constants
// ============================================================================

#define PI           3.14159265358979323846
#define TWO_PI       6.28318530717958647692
#define HALF_PI      1.57079632679489661923
#define D1EM30       1e-30
#define D1EM40       1e-40

// ============================================================================
// Vector types (double precision)
// ============================================================================

typedef struct {
    double x, y, z;
} DVec3;

typedef struct {
    double m[3][3];   // row-major: m[row][col], matches TMatrix3 in Math3D.pas
} DMat3;

// ============================================================================
// Per-iteration state — mirrors TIteration3Dext (TypeDefinitions.pas)
// GPU version: flat struct, no pointers (replaced by indices)
// ============================================================================

typedef struct {
    // Position (matches TIteration3Dext offsets for x,y,z,w at -32..-8 from C1)
    double x, y, z, w;

    // Fractal seed (C1,C2,C3 = start position for Mandelbrot)
    double C1, C2, C3;

    // Julia constants (J1,J2,J3 — or copy of C1,C2,C3 in Mandelbrot mode)
    double J1, J2, J3;

    // Rout = x*x + y*y + z*z (squared radius, updated after each formula call)
    double Rout;

    // Iteration results
    int ItResultI;     // current iteration count
    int maxIt;         // max iterations

    // Bailout
    double RStop;      // squared bailout radius (= Header.RStop^2)

    // Orbit trap
    double OTrap;      // minimum Rout seen during iteration

    // DE tracking
    // For analytic DE formulas: w accumulates the derivative (scale factor)
    // For numeric DE: we re-evaluate at offset positions
    int DEoption;      // DE function selector (2=ABox, 11=ASurf, 20=dIFS, etc.)

    // Smooth iteration
    double SmoothItD;

    // Hybrid chain state
    int nHybrid[6];    // per-slot iteration counts (< 0 = skip OTrap)
    int formulaType[6]; // which formula to run per slot (enum GPU_FORMULA_*)
    int formulaCount;  // number of active formula slots (EndTo+1)
    int iRepeatFrom;   // hybrid loop repeat-from index
    int iStartFrom;    // hybrid loop start-from index
} Iteration3D;

// ============================================================================
// Formula parameters — per-slot constant data
// Each formula slot can have up to 16 double parameters.
// Stored in __constant memory, indexed by [slot][param_index].
// Maps to PVar[-16], PVar[-24], ... in the CPU code.
// ============================================================================

#define MAX_FORMULA_SLOTS  6
#define MAX_FORMULA_PARAMS 16

typedef struct {
    double params[MAX_FORMULA_SLOTS][MAX_FORMULA_PARAMS];
} FormulaParams;

// ============================================================================
// Ray march parameters — mirrors TMCTparameter subset
// ============================================================================

typedef struct {
    // Image dimensions
    int width, height;

    // Camera
    DVec3 Ystart;      // world-space start position (top-left pixel origin)
    DMat3 Vgrads;      // camera rotation matrix (scaled by StepWidth)
    double FOVy;       // vertical FOV in radians
    double StepWidth;  // world-space step size per pixel

    // FOV per-pixel
    double CAFX_start; // = FOVXoff (half-width correction)
    double FOVXmul;    // = FOVy/Height for standard perspective
    int    CameraOptic; // 0=perspective, 1=rectilinear, 2=spherical

    // Ray marching
    double dZstart;    // near clip (in step units from camera)
    double dZend;      // far clip
    double DEstop;     // base DE stop threshold (sDEstop from header)
    double sZstepDiv;  // ray step fraction (0.0 .. 1.0)
    double mctDEstopFactor; // DE stop scale-by-depth
    double mctDEoffset;     // offset for numeric DE gradient
    double mctMH04ZSD;      // max step limiter
    double dDEscale;   // DE scale multiplier
    int    iMaxIts;    // max iterations
    int    iMinIt;     // minimum iterations for DE
    int    MaxItsResult; // = iMaxIts for outside, decremented for inside
    int    iDEAddSteps;  // binary search refinement steps
    int    iSmNormals;   // smooth normals count

    // Formula chain config
    int    formulaCount;  // active formulas in hybrid chain
    int    nHybrid[6];    // per-slot iteration counts
    int    formulaType[6]; // per-slot formula enum
    int    isCustomDE;    // analytic DE available?
    int    DEcombMode;    // 0=off 1=min 2=max etc.
    int    iRepeatFrom;   // hybrid loop repeat-from index
    int    iStartFrom;    // hybrid loop start-from index (usually 0)

    // Julia mode
    int    isJulia;
    double Jx, Jy, Jz, Jw;  // Julia constants

    // Lighting (basic Phong for initial version)
    DVec3 lightDir;    // normalised light direction
    double ambient;    // ambient light level (0..1)
    double diffuse;    // diffuse strength
    double specular;   // specular strength
    double specPower;  // specular exponent
    double fogDist;    // fog distance (0 = no fog)

    // Color
    double dColPlus;   // color offset for gradient
    int    colorOption; // color source selector
} RayMarchParams;

// ============================================================================
// Formula type enumeration (GPU_FORMULA_*)
// ============================================================================

// Built-in formulas (match formulas.pas dispatch order)
#define GPU_FORMULA_NONE          0
#define GPU_FORMULA_INTPOW2       1   // Mandelbulb power 2 (sine bulb)
#define GPU_FORMULA_INTPOW3       2
#define GPU_FORMULA_INTPOW4       3
#define GPU_FORMULA_INTPOW5       4
#define GPU_FORMULA_INTPOW6       5
#define GPU_FORMULA_INTPOW7       6
#define GPU_FORMULA_INTPOW8       7   // White's formula
#define GPU_FORMULA_FLOATPOW      8   // Real power Mandelbulb
#define GPU_FORMULA_AMAZINGBOX    9   // AmazingBox (box fold + sphere fold)
#define GPU_FORMULA_AMAZINGSURF  10   // AmazingSurf variant
#define GPU_FORMULA_QUATERNION   11   // Quaternion Julia
#define GPU_FORMULA_MENGERSPONGE 12   // IFS Menger sponge
#define GPU_FORMULA_BULBOX       13   // Hybrid Bulbox
// 100+ reserved for transpiled custom formulas

// ============================================================================
// Inline math helpers
// ============================================================================

inline double dot3(DVec3 a, DVec3 b) {
    return a.x*b.x + a.y*b.y + a.z*b.z;
}

inline double len3sq(DVec3 v) {
    return v.x*v.x + v.y*v.y + v.z*v.z;
}

inline double len3(DVec3 v) {
    return sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
}

inline DVec3 add3(DVec3 a, DVec3 b) {
    DVec3 r;
    r.x = a.x + b.x;
    r.y = a.y + b.y;
    r.z = a.z + b.z;
    return r;
}

inline DVec3 sub3(DVec3 a, DVec3 b) {
    DVec3 r;
    r.x = a.x - b.x;
    r.y = a.y - b.y;
    r.z = a.z - b.z;
    return r;
}

inline DVec3 scale3(DVec3 v, double s) {
    DVec3 r;
    r.x = v.x * s;
    r.y = v.y * s;
    r.z = v.z * s;
    return r;
}

inline DVec3 normalize3(DVec3 v) {
    double len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    if (len < D1EM30) return v;
    return scale3(v, 1.0 / len);
}

// Matrix-vector multiply: result = M * v (row-major)
inline DVec3 matvec3(DMat3 M, DVec3 v) {
    DVec3 r;
    r.x = M.m[0][0]*v.x + M.m[0][1]*v.y + M.m[0][2]*v.z;
    r.y = M.m[1][0]*v.x + M.m[1][1]*v.y + M.m[1][2]*v.z;
    r.z = M.m[2][0]*v.x + M.m[2][1]*v.y + M.m[2][2]*v.z;
    return r;
}

// Matrix-vector multiply transpose: result = M^T * v
inline DVec3 matvec3T(DMat3 M, DVec3 v) {
    DVec3 r;
    r.x = M.m[0][0]*v.x + M.m[1][0]*v.y + M.m[2][0]*v.z;
    r.y = M.m[0][1]*v.x + M.m[1][1]*v.y + M.m[2][1]*v.z;
    r.z = M.m[0][2]*v.x + M.m[1][2]*v.y + M.m[2][2]*v.z;
    return r;
}

// Clamp a double to [lo, hi]
inline double clampd(double x, double lo, double hi) {
    return fmin(fmax(x, lo), hi);
}

// ============================================================================
// Pixel output helpers
// ============================================================================

// Pack RGBA into a single uint (0xAARRGGBB format, matching Windows COLORREF)
inline uint pack_rgba(double r, double g, double b) {
    uint ri = (uint)clamp((int)(r * 255.0 + 0.5), 0, 255);
    uint gi = (uint)clamp((int)(g * 255.0 + 0.5), 0, 255);
    uint bi = (uint)clamp((int)(b * 255.0 + 0.5), 0, 255);
    return 0xFF000000u | (ri << 16) | (gi << 8) | bi;
}
