// ============================================================================
// raymarch.cl — Main GPU ray marching kernel for MB3D
// ============================================================================
// Mirrors the CPU ray marcher in Calc.pas (RayMarch + CalcDEfull).
// Each work item = one pixel = one independent ray.

// Include shared types and formulas
// (These are concatenated by the host before compilation)
// #include "common.cl"
// #include "formulas.cl"

// ============================================================================
// Distance estimation — mirrors CalcDEfull in Calc.pas
// ============================================================================

double calcDE(__constant RayMarchParams* rmp,
              __constant FormulaParams* fp,
              Iteration3D* it,
              double C1, double C2, double C3) {

    it->C1 = C1;
    it->C2 = C2;
    it->C3 = C3;

    if (rmp->isCustomDE) {
        // Analytic DE: formula tracks derivative in w
        double de = doHybridDE(it, fp);
        return de * rmp->dDEscale;
    } else {
        // Numeric DE: 3-point gradient via re-evaluation
        // Run at base position
        doHybrid(it, fp);
        double bufRout = it->Rout;
        int bufItResult = it->ItResultI;

        double offset = rmp->mctDEoffset;

        // Offset in C1 direction
        it->C1 = C1 + offset;
        it->C2 = C2;
        it->C3 = C3;
        doHybrid(it, fp);
        double dt = bufRout - it->Rout;
        dt = dt * dt;

        // Offset in C2 direction
        it->C1 = C1;
        it->C2 = C2 + offset;
        it->C3 = C3;
        doHybrid(it, fp);
        double wt = bufRout - it->Rout;
        wt = wt * wt;

        // Offset in C3 direction
        it->C1 = C1;
        it->C2 = C2;
        it->C3 = C3 + offset;
        doHybrid(it, fp);
        double rst = bufRout - it->Rout;
        rst = rst * rst;

        // Restore state
        it->Rout = bufRout;
        it->ItResultI = bufItResult;

        // DE = r * ln(r) / |grad(r)| * scale
        double gradLen = sqrt(dt + wt + rst) + offset * 0.006;
        if (bufRout < D1EM30) return rmp->DEstop;
        double r = sqrt(bufRout);
        return r * log(bufRout) * rmp->dDEscale / (gradLen + D1EM30);
    }
}

// ============================================================================
// Compute ray origin for pixel (px, py)
// Mirrors RMCalculateStartPos in Calc.pas
// ============================================================================

inline DVec3 computeRayOrigin(__constant RayMarchParams* rmp, int px, int py) {
    DVec3 origin;
    origin.x = rmp->Ystart.x + rmp->Vgrads.m[0][0]*px + rmp->Vgrads.m[1][0]*py;
    origin.y = rmp->Ystart.y + rmp->Vgrads.m[0][1]*px + rmp->Vgrads.m[1][1]*py;
    origin.z = rmp->Ystart.z + rmp->Vgrads.m[0][2]*px + rmp->Vgrads.m[1][2]*py;
    return origin;
}

// ============================================================================
// Compute view direction for pixel (px, py)
// Mirrors RMCalculateVgradsFOV in Calc.pas
// Standard perspective: direction from camera through pixel
// ============================================================================

inline DVec3 computeViewDir(__constant RayMarchParams* rmp, int px, int py) {
    // Standard perspective (CameraOptic = 0)
    double cafx = (rmp->CAFX_start - (double)px) * rmp->FOVXmul;
    double cafy = ((double)py / (double)rmp->height - 0.5) * rmp->FOVy;

    // Build direction in camera space
    DVec3 dir;
    double sc, cc, sp, cp;
    sc = sincos(cafx, &cc);
    sp = sincos(cafy, &cp);

    dir.x = -cp * sc;  // right
    dir.y =  sp;       // up
    dir.z =  cp * cc;  // forward

    // Rotate by camera matrix (transpose because Vgrads is column-major in world)
    DVec3 worldDir;
    worldDir.x = rmp->Vgrads.m[0][0]*dir.x + rmp->Vgrads.m[1][0]*dir.y + rmp->Vgrads.m[2][0]*dir.z;
    worldDir.y = rmp->Vgrads.m[0][1]*dir.x + rmp->Vgrads.m[1][1]*dir.y + rmp->Vgrads.m[2][1]*dir.z;
    worldDir.z = rmp->Vgrads.m[0][2]*dir.x + rmp->Vgrads.m[1][2]*dir.y + rmp->Vgrads.m[2][2]*dir.z;

    return normalize3(worldDir);
}

// ============================================================================
// Compute surface normal via central differences (4 extra DE evaluations)
// Mirrors RMCalculateNormals in Calc.pas
// ============================================================================

DVec3 computeNormal(__constant RayMarchParams* rmp,
                    __constant FormulaParams* fp,
                    Iteration3D* it,
                    DVec3 pos, double de) {
    double eps = fmax(de * 0.5, rmp->DEstop * 0.1);

    double d1 = calcDE(rmp, fp, it, pos.x + eps, pos.y, pos.z);
    double d2 = calcDE(rmp, fp, it, pos.x - eps, pos.y, pos.z);
    double d3 = calcDE(rmp, fp, it, pos.x, pos.y + eps, pos.z);
    double d4 = calcDE(rmp, fp, it, pos.x, pos.y - eps, pos.z);
    double d5 = calcDE(rmp, fp, it, pos.x, pos.y, pos.z + eps);
    double d6 = calcDE(rmp, fp, it, pos.x, pos.y, pos.z - eps);

    DVec3 n;
    n.x = d1 - d2;
    n.y = d3 - d4;
    n.z = d5 - d6;
    return normalize3(n);
}

// ============================================================================
// Simple orbit-trap based coloring
// ============================================================================

inline DVec3 computeColor(Iteration3D* it, __constant RayMarchParams* rmp) {
    // Color based on iteration count + orbit trap
    double t = (double)it->ItResultI / (double)rmp->iMaxIts;
    double trap = sqrt(it->OTrap) + rmp->dColPlus;

    // Simple gradient: warm tones
    DVec3 col;
    col.x = 0.5 + 0.5 * cos(TWO_PI * (trap * 0.3 + 0.0));
    col.y = 0.5 + 0.5 * cos(TWO_PI * (trap * 0.3 + 0.33));
    col.z = 0.5 + 0.5 * cos(TWO_PI * (trap * 0.3 + 0.67));

    // Darken by iteration depth
    double itFade = 1.0 - t * 0.5;
    col.x *= itFade;
    col.y *= itFade;
    col.z *= itFade;

    return col;
}

// ============================================================================
// Main ray march kernel
// ============================================================================

__kernel void ray_march(
    __constant RayMarchParams* rmp,
    __constant FormulaParams* fp,
    __global uint* outputPixels,
    int width, int height)
{
    int px = get_global_id(0);
    int py = get_global_id(1);
    if (px >= width || py >= height) return;

    // Per-work-item iteration state (private memory)
    Iteration3D it;

    // Copy hybrid chain config from ray march params
    it.maxIt = rmp->iMaxIts;
    it.RStop = 100.0;  // squared bailout, typical value
    it.DEoption = 0;
    it.formulaCount = rmp->formulaCount;
    it.iRepeatFrom = rmp->iRepeatFrom;
    it.iStartFrom = rmp->iStartFrom;
    for (int i = 0; i < 6; i++) {
        it.nHybrid[i] = rmp->nHybrid[i];
        it.formulaType[i] = rmp->formulaType[i];
    }

    // Set up Julia constants
    if (rmp->isJulia) {
        it.J1 = rmp->Jx;
        it.J2 = rmp->Jy;
        it.J3 = rmp->Jz;
    }
    // (For Mandelbrot mode, J1-J3 are set per-step from ray position)

    // Compute ray origin and direction
    DVec3 origin = computeRayOrigin(rmp, px, py);
    DVec3 viewDir = computeViewDir(rmp, px, py);

    // Ray march parameters
    double maxRayLen = rmp->dZend;
    double stepDiv = rmp->sZstepDiv;
    double baseDEstop = rmp->DEstop;
    double dEstopFactor = rmp->mctDEstopFactor;

    // March the ray
    double zStepped = 0.0;
    double msDEstop = baseDEstop;
    double lastDE = 1e10;
    double lastStep = 0.0;
    double RSFmul = 1.0;
    int hit = 0;

    // Initial step forward
    double stepFwd = rmp->dZstart;
    DVec3 pos;
    pos.x = origin.x + viewDir.x * stepFwd;
    pos.y = origin.y + viewDir.y * stepFwd;
    pos.z = origin.z + viewDir.z * stepFwd;
    zStepped = stepFwd;

    // Set Julia/Mandelbrot constants
    if (!rmp->isJulia) {
        it.J1 = pos.x;
        it.J2 = pos.y;
        it.J3 = pos.z;
    }

    double de = calcDE(rmp, fp, &it, pos.x, pos.y, pos.z);

    // Check if already inside at start
    if (it.ItResultI >= rmp->MaxItsResult || de < msDEstop) {
        // Inside at ray start — mark as hit
        hit = (de < msDEstop) ? 1 : 2;
    }

    if (hit == 0) {
        // Main ray march loop
        for (int step = 0; step < 2000; step++) {
            if (zStepped > maxRayLen) break;

            // Handle max-iteration hit: step back half
            if (it.ItResultI >= rmp->MaxItsResult) {
                double halfBack = -0.5 * lastStep;
                pos.x += viewDir.x * halfBack;
                pos.y += viewDir.y * halfBack;
                pos.z += viewDir.z * halfBack;
                zStepped += halfBack;

                if (!rmp->isJulia) {
                    it.J1 = pos.x;
                    it.J2 = pos.y;
                    it.J3 = pos.z;
                }
                de = calcDE(rmp, fp, &it, pos.x, pos.y, pos.z);
                lastStep = -halfBack;
            }

            if (it.ItResultI < rmp->iMinIt ||
                (it.ItResultI < rmp->MaxItsResult && de >= msDEstop)) {
                // Step forward
                lastDE = de;
                double stepSize = de * stepDiv * RSFmul;

                // Max step limiter
                double maxStep = fmax(msDEstop, 0.4) * rmp->mctMH04ZSD;
                if (maxStep < stepSize) stepSize = maxStep;

                lastStep = stepSize;
                pos.x += viewDir.x * stepSize;
                pos.y += viewDir.y * stepSize;
                pos.z += viewDir.z * stepSize;
                zStepped += stepSize;

                // Update adaptive DE stop
                double actZ = fmax(0.0, zStepped);
                msDEstop = baseDEstop * (1.0 + actZ * dEstopFactor);

                // Evaluate DE at new position
                if (!rmp->isJulia) {
                    it.J1 = pos.x;
                    it.J2 = pos.y;
                    it.J3 = pos.z;
                }
                de = calcDE(rmp, fp, &it, pos.x, pos.y, pos.z);

                // Overshoot correction
                if (de > lastDE + lastStep) de = lastDE + lastStep;

                // Adaptive step factor
                if (lastDE > de + D1EM30) {
                    RSFmul = fmax(0.5, lastStep / (lastDE - de));
                } else {
                    RSFmul = 1.0;
                }
            } else {
                // Surface found
                hit = (it.ItResultI < rmp->MaxItsResult) ? 1 : 2;
                break;
            }
        }
    }

    // Compute pixel color
    uint pixel;
    if (hit > 0) {
        // Compute normal
        DVec3 normal = computeNormal(rmp, fp, &it, pos, de);

        // Basic surface color from orbit trap
        DVec3 surfColor = computeColor(&it, rmp);

        // Phong lighting
        double NdotL = dot3(normal, rmp->lightDir);
        NdotL = fmax(0.0, NdotL);

        // Half vector for specular
        DVec3 halfVec = normalize3(add3(rmp->lightDir, (DVec3){0.0, 0.0, 1.0}));
        double NdotH = fmax(0.0, dot3(normal, halfVec));
        double spec = pow(NdotH, rmp->specPower) * rmp->specular;

        // Combine
        double diff = rmp->diffuse * NdotL;
        double amb = rmp->ambient;

        DVec3 finalColor;
        finalColor.x = surfColor.x * (amb + diff) + spec;
        finalColor.y = surfColor.y * (amb + diff) + spec;
        finalColor.z = surfColor.z * (amb + diff) + spec;

        // Fog
        if (rmp->fogDist > 0.0) {
            double fogFactor = exp(-zStepped / rmp->fogDist);
            fogFactor = clampd(fogFactor, 0.0, 1.0);
            DVec3 fogColor = {0.1, 0.12, 0.15};
            finalColor.x = finalColor.x * fogFactor + fogColor.x * (1.0 - fogFactor);
            finalColor.y = finalColor.y * fogFactor + fogColor.y * (1.0 - fogFactor);
            finalColor.z = finalColor.z * fogFactor + fogColor.z * (1.0 - fogFactor);
        }

        // Clamp to [0,1]
        finalColor.x = clampd(finalColor.x, 0.0, 1.0);
        finalColor.y = clampd(finalColor.y, 0.0, 1.0);
        finalColor.z = clampd(finalColor.z, 0.0, 1.0);

        pixel = pack_rgba(finalColor.x, finalColor.y, finalColor.z);
    } else {
        // Background — simple gradient
        double t = (double)py / (double)height;
        pixel = pack_rgba(
            0.05 + 0.02 * t,
            0.05 + 0.05 * t,
            0.1 + 0.15 * t);
    }

    outputPixels[py * width + px] = pixel;
}
