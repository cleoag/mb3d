// ============================================================================
// formulas.cl — GPU implementations of MB3D built-in formulas
// ============================================================================
// Each formula transforms (x,y,z,w) in place, reading parameters from
// the per-slot constant array.  Translated from x87 ASM in formulas.pas.
//
// Parameter mapping:
//   params[slot][0] = PVar[-16] = dOption1 (Zmul / Power / Scale)
//   params[slot][1] = PVar[-24] = dOption2 (Fold / MinR)
//   params[slot][2] = PVar[-32] = dOption3
//   params[slot][3] = PVar[-40] = dOption4 (fold for ABox)
//   params[slot][4] = PVar[-48] = dOption5
//   ...
//   For AmazingBox the mapping is:
//     params[slot][0] = Scale (PVar[-16])
//     params[slot][1] = fixedR^2 / minR^2  (PVar[-24])
//     params[slot][2] = minR^2 (PVar[-32])
//     params[slot][3] = fold   (PVar[-40])

// ============================================================================
// IntPow2 — Mandelbulb Power 2 (sine bulb)
// From formulas.pas HybridItIntPow2 lines 4148-4186
// ============================================================================

void formula_intpow2(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double Zmul = p[0];   // dOption1 = Zmul

    double xx = x * x;
    double yy = y * y;
    double a = xx + yy;   // cylindrical r^2

    // New z: z' = Zmul * 2 * sqrt(xx+yy) * z + J3
    it->z = Zmul * 2.0 * sqrt(a) * z + it->J3;

    // Factor: (xx+yy - z^2) / (xx+yy)
    double zz_old = z * z;
    double A = (a - zz_old) / (a + D1EM40);

    // New x,y
    it->x = (xx - yy) * A + it->J1;
    it->y = 2.0 * x * y * A + it->J2;
}

// ============================================================================
// IntPow3
// From formulas.pas HybridItIntPow3 lines 4307-4352
// Pascal: A = 1 - 3*sz / (R + cz_offset)
//         x' = A * x * (sx - 3*sy) + J1
//         y' = A * y * (3*sx - sy) + J2
//         z' = Zmul * z * (sz - 3*R) + J3
// ============================================================================

void formula_intpow3(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double Zmul = p[0];

    double sx = x * x;
    double sy = y * y;
    double R = sx + sy;
    double sz = z * z;

    // cz_offset stored at PVars+24 in CPU; for GPU we pass 0 (or p[5])
    double A = 1.0 - 3.0 * sz / (R + D1EM40);

    it->x = A * x * (sx - 3.0 * sy) + it->J1;
    it->y = A * y * (3.0 * sx - sy) + it->J2;
    it->z = Zmul * z * (sz - 3.0 * R) + it->J3;
}

// ============================================================================
// IntPow4
// From formulas.pas HybridItIntPow4 lines 4354-4419
// Pascal:
//   A = 1 + (sz * (sz - 6*R)) / (R*R + 1e-40)
//   y' = 4*x*y*A*(sx-sy) + J2
//   z' = Zmul * 4 * sqrt(R) * z * (R - sz) + J3
//   x' = A * (sx*(sx - 6*sy) + sy*sy) + J1
// ============================================================================

void formula_intpow4(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double Zmul = p[0];

    double sx = x * x;
    double sy = y * y;
    double R = sx + sy;
    double sz = z * z;

    double A = 1.0 + (sz * (sz - 6.0 * R)) / (R * R + D1EM40);

    it->y = 4.0 * x * y * A * (sx - sy) + it->J2;
    it->z = Zmul * 4.0 * sqrt(R) * z * (R - sz) + it->J3;
    it->x = A * (sx * (sx - 6.0 * sy) + sy * sy) + it->J1;
}

// ============================================================================
// IntPow5
// From formulas.pas HybridIntP5 lines 4421-4504
// Pascal:
//   A  = 1 + 5*(sz*sz - 2*R*sz) / (R*R + 1e-40)
//   y' = A*y*(5*sx*sx - sy*(10*sx - sy)) + J2
//   z' = Zmul*z*(sz*(sz - 10*R) + 5*R*R) + J3
//   x' = A*x*(sx*(sx - 10*sy) + 5*sy*sy) + J1
// ============================================================================

void formula_intpow5(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double Zmul = p[0];

    double sx = x * x;
    double sy = y * y;
    double R = sx + sy;
    double sz = z * z;

    double A = 1.0 + 5.0 * (sz * sz - 2.0 * R * sz) / (R * R + D1EM40);

    it->y = A * y * (5.0 * sx * sx - sy * (10.0 * sx - sy)) + it->J2;
    it->z = Zmul * z * (sz * (sz - 10.0 * R) + 5.0 * R * R) + it->J3;
    it->x = A * x * (sx * (sx - 10.0 * sy) + 5.0 * sy * sy) + it->J1;
}

// ============================================================================
// IntPow6
// From formulas.pas HybridIntP6 lines 4506-4605
// Pascal:
//   A  = 1 - (sz*(sz*(sz - 15*R) + 15*R*R)) / (R*R*R + 1e-40)
//   y' = 2*A*x*y*(S1*(3*S1 - 10*S2) + 3*S2*S2) + J2
//   z' = Zmul*2*z*sqrt(R)*(sz*(3*sz - 10*R) + 3*R*R) + J3
//   x' = A*(S1*S1*(S1 - 15*S2) + S2*S2*(15*S1 - S2)) + J1
// ============================================================================

void formula_intpow6(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double Zmul = p[0];

    double S1 = x * x;
    double S2 = y * y;
    double R = S1 + S2;
    double sz = z * z;

    double A = 1.0 - (sz * (sz * (sz - 15.0 * R) + 15.0 * R * R)) /
               (R * R * R + D1EM40);

    it->y = 2.0 * A * x * y * (S1 * (3.0*S1 - 10.0*S2) + 3.0*S2*S2) + it->J2;
    it->z = Zmul * 2.0 * z * sqrt(R) *
            (sz * (3.0*sz - 10.0*R) + 3.0*R*R) + it->J3;
    it->x = A * (S1*S1*(S1 - 15.0*S2) + S2*S2*(15.0*S1 - S2)) + it->J1;
}

// ============================================================================
// IntPow7
// From formulas.pas HybridIntP7 lines 4607-4620 (Pascal comment)
// ============================================================================

void formula_intpow7(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double Zmul = p[0];

    double S1 = x * x;
    double S2 = y * y;
    double R = S1 + S2;
    double S3 = z * z;

    double A = 1.0 - 7.0 * (S3 * (S3 * (S3 - 5.0*R) + 3.0*R*R)) /
               (R * R * R + D1EM40);

    it->y = A * y * (S1*(S1*(7.0*S1 - 35.0*S2) + 21.0*S2*S2) - S2*S2*S2) + it->J2;
    it->z = it->J3 - Zmul * (z*S3*S3*S3 -
            7.0 * z * R * (S3*(3.0*S3 - 5.0*R) + R*R));
    it->x = A * x * (S1*(S1*(S1 - 21.0*S2) + 35.0*S2*S2) - 7.0*S2*S2*S2) + it->J1;
}

// ============================================================================
// IntPow8 — White's formula
// From formulas.pas HybridIntP8 lines 4716+ (x87 ASM)
// The P8 formula uses a polynomial decomposition in cylindrical coords.
// ============================================================================

void formula_intpow8(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double Zmul = p[0];

    double xx = x * x;
    double yy = y * y;
    double zz = z * z;
    double r = xx + yy;   // cylindrical r^2
    double rr = r * r;
    double zzzz = zz * zz;

    // z calculation: z' = -Zmul * 8 * z * sqrt(r) * (zz-r) * (zzzz - 6*r*zz + rr) + J3
    it->z = -Zmul * 8.0 * z * sqrt(r) * (zz - r) * (zzzz - 6.0*r*zz + rr) + it->J3;

    // A calculation: A = 1 + ((rr*70+zzzz)*zzzz - 28*zz*r*(zzzz+rr)) / (rrrr + 1e-40)
    double rrrr = rr * rr;
    double A = 1.0 + ((rr * 70.0 + zzzz) * zzzz - 28.0*zz*r*(zzzz + rr)) /
               (rrrr + D1EM40);

    // x' = A * (xx^4 - 28*xx^2*yy^2 + 70*xx^2*yy^2 ... polynomial)
    // Using simplified form:
    // x' = A * (xx*(xx*(xx*(xx - 28*yy) + 70*yy^2) - 28*yy^3) + yy^4) + J1
    double x8 = xx*xx*xx*xx - 28.0*xx*xx*xx*yy + 70.0*xx*xx*yy*yy
                - 28.0*xx*yy*yy*yy + yy*yy*yy*yy;
    // y': 8*x*y*(xx-yy)*(xx^2 - 6*xx*yy + yy^2) = binomial expansion
    double y8 = 8.0 * x * y * (xx - yy) * (xx*xx - 6.0*xx*yy + yy*yy);

    it->x = A * x8 + it->J1;
    it->y = A * y8 + it->J2;
}

// ============================================================================
// FloatPow — Real power Mandelbulb (arbitrary float exponent)
// From formulas.pas HybridFloatPow lines 4227-4304
// Pascal:
//   th = atan2(y, x)
//   ph = atan2(z, sqrt(x^2 + y^2))
//   pp = Rout^(pow*0.5)
//   x' = pp * cos(ph*pow) * cos(th*pow) + J1
//   y' = pp * cos(ph*pow) * sin(th*pow) + J2
//   z' = Zmul * pp * sin(ph*pow) + J3
// ============================================================================

void formula_floatpow(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double pw = p[0];    // power
    double Zmul = p[1];  // z multiplier

    double th = atan2(y, x);
    double ph = atan2(z, sqrt(x*x + y*y));

    double pp = pow(it->Rout, 0.5 * pw);

    double sph, cph, sth, cth;
    sph = sincos(ph * pw, &cph);
    sth = sincos(th * pw, &cth);

    it->x = pp * cph * cth + it->J1;
    it->y = pp * cph * sth + it->J2;
    it->z = Zmul * pp * sph + it->J3;
}

// ============================================================================
// AmazingBox — Box fold + Sphere fold + Scale
// From formulas.pas HybridCubeDE lines 4939-5018
// This is the classic Mandelbox formula with analytic DE tracking in w.
//
// Parameters:
//   p[0] = Scale    (PVar[-16])
//   p[1] = fixedR^2/minR^2 ratio (PVar[-24]) — pre-computed
//   p[2] = minR^2   (PVar[-32])
//   p[3] = fold     (PVar[-40])
// ============================================================================

void formula_amazingbox(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double Scale = p[0];
    double fixRdivMinR = p[1];  // Scale / minR^2 when r < minR
    double minR2 = p[2];
    double fold = p[3];

    // Box fold: x = abs(x+fold) - abs(x-fold) - x
    x = fabs(x + fold) - fabs(x - fold) - x;
    y = fabs(y + fold) - fabs(y - fold) - y;
    z = fabs(z + fold) - fabs(z - fold) - z;

    // Sphere fold
    double r2 = x*x + y*y + z*z;
    double mul;
    if (r2 < minR2) {
        mul = fixRdivMinR;   // = Scale / minR^2
    } else if (r2 < 1.0) {
        mul = Scale / r2;     // = Scale / r^2
    } else {
        mul = Scale;
    }

    // Apply scale + Julia offset
    it->x = x * mul + it->J1;
    it->y = y * mul + it->J2;
    it->z = z * mul + it->J3;

    // Track derivative for analytic DE
    it->w = it->w * mul;
}

// ============================================================================
// MengerSponge — IFS Menger sponge
// Classic distance estimator IFS: fold, scale, translate
// ============================================================================

void formula_mengersponge(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z;
    double Scale = p[0];  // typically 3.0

    // Sort: ensure x >= y >= z using conditional swaps
    double t;
    x = fabs(x);
    y = fabs(y);
    z = fabs(z);
    if (x < y) { t = x; x = y; y = t; }
    if (x < z) { t = x; x = z; z = t; }
    if (y < z) { t = y; y = z; z = t; }

    // Scale and translate
    x = Scale * x - (Scale - 1.0);
    y = Scale * y - (Scale - 1.0);
    z = Scale * z;

    if (z > 0.5 * (Scale - 1.0))
        z -= (Scale - 1.0);

    it->x = x;
    it->y = y;
    it->z = z;
    it->w = it->w * Scale;  // DE derivative tracking
}

// ============================================================================
// Quaternion Julia
// Standard quaternion multiplication: q' = q*q + c
// ============================================================================

void formula_quaternion(Iteration3D* it, __constant double* p) {
    double x = it->x, y = it->y, z = it->z, w = it->w;

    // q*q = (x^2 - y^2 - z^2 - w^2, 2xy, 2xz, 2xw)
    it->x = x*x - y*y - z*z - w*w + it->J1;
    it->y = 2.0*x*y + it->J2;
    it->z = 2.0*x*z + it->J3;
    it->w = 2.0*x*w;
}

// ============================================================================
// Formula dispatch — switch on formula type enum
// ============================================================================

void dispatch_formula(int type, Iteration3D* it,
                      __constant double* slotParams) {
    switch (type) {
        case GPU_FORMULA_INTPOW2:     formula_intpow2(it, slotParams);     break;
        case GPU_FORMULA_INTPOW3:     formula_intpow3(it, slotParams);     break;
        case GPU_FORMULA_INTPOW4:     formula_intpow4(it, slotParams);     break;
        case GPU_FORMULA_INTPOW5:     formula_intpow5(it, slotParams);     break;
        case GPU_FORMULA_INTPOW6:     formula_intpow6(it, slotParams);     break;
        case GPU_FORMULA_INTPOW7:     formula_intpow7(it, slotParams);     break;
        case GPU_FORMULA_INTPOW8:     formula_intpow8(it, slotParams);     break;
        case GPU_FORMULA_FLOATPOW:    formula_floatpow(it, slotParams);    break;
        case GPU_FORMULA_AMAZINGBOX:  formula_amazingbox(it, slotParams);  break;
        case GPU_FORMULA_MENGERSPONGE: formula_mengersponge(it, slotParams); break;
        case GPU_FORMULA_QUATERNION:  formula_quaternion(it, slotParams);  break;
        default: break;  // unknown formula — no-op
    }
}

// ============================================================================
// Hybrid iteration loop — mirrors doHybridPas in formulas.pas
// Runs up to maxIt formula iterations with hybrid chain dispatch.
// ============================================================================

void doHybrid(Iteration3D* it, __constant FormulaParams* fp) {
    // Set up Julia or Mandelbrot mode
    // (J1,J2,J3 are pre-set by the host before kernel launch)

    // Initialize position from seed
    it->x = it->C1;
    it->y = it->C2;
    it->z = it->C3;
    it->w = 0.0;
    it->Rout = it->x*it->x + it->y*it->y + it->z*it->z;
    it->OTrap = it->Rout;
    it->ItResultI = 0;

    int n = it->iStartFrom;    // current slot index
    int bTmp = it->nHybrid[n] & 0x7FFFFFFF; // countdown for this slot

    for (int iter = 0; iter < it->maxIt; iter++) {
        double Rold = it->Rout;

        // Advance to next active slot if current exhausted
        int safety = 0;
        while (bTmp <= 0 && safety < 12) {
            n++;
            if (n >= it->formulaCount) n = it->iRepeatFrom;
            bTmp = it->nHybrid[n] & 0x7FFFFFFF;
            safety++;
        }
        if (bTmp <= 0) break;  // no active slots

        // Dispatch formula for current slot
        dispatch_formula(it->formulaType[n], it,
                        &fp->params[n][0]);
        bTmp--;

        // Update Rout and OTrap (skip if nHybrid < 0)
        if (it->nHybrid[n] >= 0) {
            it->Rout = it->x*it->x + it->y*it->y + it->z*it->z;
            if (it->Rout < it->OTrap) it->OTrap = it->Rout;
            it->ItResultI++;

            // Bailout check
            if (it->Rout > it->RStop) break;
        }
    }
}

// ============================================================================
// Hybrid iteration with analytic DE tracking
// Same as doHybrid but returns DE = sqrt(Rout) / |w|
// Used when isCustomDE is true (e.g., AmazingBox)
// ============================================================================

double doHybridDE(Iteration3D* it, __constant FormulaParams* fp) {
    it->w = 1.0;  // initialize derivative accumulator
    doHybrid(it, fp);
    double absW = fabs(it->w);
    if (absW < D1EM30) absW = D1EM30;
    return sqrt(it->Rout) / absW;
}
