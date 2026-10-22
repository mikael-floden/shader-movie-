// Super Silas - the first 30 seconds, rebuilt as one procedural fragment shader.
// No textures, no video frames: every shot is distance fields, noise and light.
// Written against the shader-skills library (github.com/gokayfem/shader-skills);
// `glsl_tools.py bundle` turns this into the paste-ready out file.
//
// Shot list (film seconds):
//   0.00  close flight over sunset clouds        1.75  wide flight toward the sun
//   6.00  forest, fireflies                       10.50 mossy root pass
//  11.25  sparkling stream                        12.50 big tree, sunlit clearing
//  16.00  the knight and the robot wave           19.00 backlit forest
//  21.00  pink dusk over the pines                25.00 the cabin, the catch, the hug
//
// Coordinates: characters are SDFs raymarched with a fixed camera at (0,0,4) looking at -z,
// backgrounds are layered 2D fields painted from the screen position.

#define DEBUG_MODE 0          // 0 final, 1 character normals, 2 character material ids
#define LOOP 0                // 1 = loop the 30 s forever (Shadertoy), 0 = play once

// ---- art controls -------------------------------------------------------
const float FOCAL      = 2.0;   // camera focal length (higher = flatter)
const float EXPOSURE   = 1.15;
const float CAPE_SPEED = 11.0;  // cape flutter speed
const float GRAIN      = 0.025;

// sRGB picks, decoded to linear at use
const vec3 C_SKIN   = vec3(1.0, 0.82, 0.72);
const vec3 C_HAIR   = vec3(0.95, 0.76, 0.40);
const vec3 C_SUIT   = vec3(0.10, 0.62, 0.88);
const vec3 C_CAPE   = vec3(0.86, 0.07, 0.08);
const vec3 C_GREEN  = vec3(0.40, 0.83, 0.18);
const vec3 C_PACI   = vec3(0.08, 0.32, 0.86);
const vec3 C_UKE    = vec3(0.97, 0.80, 0.14);

// ---- materials ------------------------------------------------------------
const float M_SKIN = 1.0, M_HAIR = 2.0, M_SUIT = 3.0, M_CAPE = 4.0, M_GREEN = 5.0, M_EYE = 6.0,
            M_IRIS = 7.0, M_PACI = 8.0, M_UKE = 9.0, M_UKEN = 10.0, M_DARK = 11.0,
            M_KN_TUNIC = 12.0, M_KN_SHIELD = 13.0, M_METAL = 14.0, M_ROBO_FACE = 15.0,
            M_ROBO_CHEST = 16.0, M_ROBO_LEG = 17.0, M_HAT = 18.0, M_COAT = 19.0, M_DADHAIR = 20.0;

// ---- scene state, set once per pixel in setupShot() ------------------------
int   gShot;        // which shot
float gT;           // seconds into the shot
float gTime;        // film time
vec3  gSilasPos;    // world position of Silas
float gSilasScale;
float gSilasYaw;    // turn toward camera
float gSilasTilt;   // 0 upright hover, 1 flying flat
float gSilasRoll;
int   gCast;        // 0 Silas only, 1 + friends, 2 + dad
vec3  gSunUV;       // xy = sun position in screen uv, z = strength
vec3  gKeyDir;      // key light direction (world)
vec3  gKeyCol;
vec3  gFillCol;
vec3  gRimCol;
float gHug;         // 0..1 how far into the dad's arms

// ======================================================================
// small helpers
// ======================================================================
float box2(vec2 p, vec2 b) { vec2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }
float ease(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }
float aaStep(float d, float px) { return clamp(0.5 - d / px, 0.0, 1.0); }
vec3  lin(vec3 c) { return srgbToLinear(c); }
mat3  rotY(float a) { float c = cos(a), s = sin(a); return mat3(c, 0.0, -s, 0.0, 1.0, 0.0, s, 0.0, c); }
mat3  rotZ(float a) { float c = cos(a), s = sin(a); return mat3(c, s, 0.0, -s, c, 0.0, 0.0, 0.0, 1.0); }
vec2  U(float d, float m, vec2 r) { return d < r.x ? vec2(d, m) : r; }

// ======================================================================
// Silas: toddler hero, faces +x, y up, z toward camera. Head radius ~0.3.
// ======================================================================
vec2 sdSilas(vec3 p, float t) {
    vec2 r = vec2(1e5, 0.0);

    // --- head
    vec3 h = p;
    float head = sdEllipsoid(h, vec3(0.30, 0.285, 0.28));
    float cheeks = sdSphere(h - vec3(0.17, -0.09, 0.0), 0.17);
    head = smin(head, cheeks, 0.06);
    float nose = sdSphere(h - vec3(0.295, -0.01, 0.0), 0.035);
    head = smin(head, nose, 0.03);
    vec3 he = vec3(h.x, h.y, abs(h.z));
    float ear = sdEllipsoid(he - vec3(-0.02, -0.03, 0.27), vec3(0.05, 0.07, 0.035));
    head = smin(head, ear, 0.02);
    r = U(head, M_SKIN, r);

    // eyes: big white ellipsoids with blue iris and dark pupil, looking forward
    vec3 ep = he - vec3(0.22, 0.03, 0.11);
    float eye = sdEllipsoid(ep, vec3(0.065, 0.088, 0.07));
    r = U(eye, M_EYE, r);
    float iris = sdSphere(ep - vec3(0.035, -0.008, 0.008), 0.052);
    r = U(max(iris, eye - 0.006), M_IRIS, r);

    // hair: tufty blond cap, face cut out by a slanted plane
    vec3 hp = h - vec3(-0.035, 0.07, 0.0);
    float hair = sdEllipsoid(hp, vec3(0.325, 0.29, 0.315));
    vec3 tq = hp * 9.0;
    hair -= 0.028 * (sin(tq.x * 1.3 + 1.7 * sin(tq.z)) * sin(tq.z * 1.1 + tq.y) * 0.5 + 0.5);
    hair = smax(hair, dot(h, normalize(vec3(1.0, -0.55, 0.0))) - 0.02, 0.05);
    // fringe tufts over the forehead
    float tuft = sdEllipsoid(h - vec3(0.17, 0.23, 0.08), vec3(0.08, 0.045, 0.07));
    tuft = min(tuft, sdEllipsoid(h - vec3(0.18, 0.22, -0.07), vec3(0.08, 0.045, 0.07)));
    tuft = min(tuft, sdEllipsoid(h - vec3(-0.05, 0.31, 0.02), vec3(0.09, 0.06, 0.08)));
    hair = smin(hair, tuft, 0.04);
    r = U(hair, M_HAIR, r);

    // pacifier: shield, knob and ring in front of the mouth
    vec3 pp = h - vec3(0.305, -0.115, 0.0);
    float shield = sdEllipsoid(pp, vec3(0.022, 0.055, 0.075));
    float knob = sdSphere(pp - vec3(0.03, 0.0, 0.0), 0.022);
    float ring = sdTorus((pp - vec3(0.055, 0.0, 0.0)).yxz, vec2(0.04, 0.011));
    r = U(min(min(shield, knob), ring), M_PACI, r);

    // --- body, hinged at the neck; tilt swings it from below the head to trailing behind
    float a = mix(0.25, 1.25, gSilasTilt);
    vec3 q = p - vec3(-0.03, -0.24, 0.0);
    vec2 D = vec2(-sin(a), -cos(a));         // body axis, pointing to the feet
    vec2 F = vec2(-D.y, D.x);                 // belly direction
    vec3 b = vec3(dot(q.xy, F), -dot(q.xy, D), q.z);

    float torso = sdEllipsoid(b - vec3(0.0, -0.20, 0.0), vec3(0.165, 0.21, 0.165));
    r = U(torso, M_SUIT, r);

    // legs and boots, gently kicking
    float kick = 0.06 * sin(t * 5.0);
    vec3 lb = b; lb.z = abs(lb.z);
    float k2 = b.z > 0.0 ? kick : -kick;
    float leg = sdCapsule(lb, vec3(0.0, -0.33, 0.075), vec3(0.03 + k2, -0.53, 0.085), 0.07);
    float boot = sdEllipsoid(lb - vec3(0.07 + k2, -0.6, 0.085), vec3(0.095, 0.065, 0.07));
    r = U(smin(leg, boot, 0.04), M_GREEN, r);

    // ukulele held across the belly
    vec3 u = b - vec3(0.17, -0.22, 0.07);
    u.xy = rot2(-0.45) * u.xy;
    float ub = sdEllipsoid(u - vec3(0.0, -0.04, 0.0), vec3(0.04, 0.10, 0.095));
    ub = smin(ub, sdEllipsoid(u - vec3(0.0, 0.07, 0.0), vec3(0.035, 0.075, 0.075)), 0.03);
    float hole = sdCylinder(u.yxz - vec3(0.02, 0.04, 0.0), 0.03, 0.025);
    r = U(smax(ub, -hole, 0.005), M_UKE, r);
    float neck = sdCapsule(u, vec3(0.0, 0.12, 0.0), vec3(0.0, 0.33, 0.0), 0.022);
    float pegs = sdEllipsoid(u - vec3(0.0, 0.36, 0.0), vec3(0.025, 0.045, 0.035));
    r = U(min(neck, pegs), M_UKEN, r);
    r = U(max(hole, ub - 0.004) + 0.003, M_DARK, r);

    // arms: near arm strums, far arm frets the neck
    float strum = 0.025 * sin(t * 14.0);
    float arm1 = sdCapsule(b, vec3(0.02, -0.08, 0.15), vec3(0.17, -0.22 + strum, 0.17), 0.05);
    float arm2 = sdCapsule(b, vec3(0.02, -0.08, -0.15), vec3(0.26, 0.0, 0.04), 0.05);
    r = U(min(arm1, arm2), M_SUIT, r);
    float hands = min(sdSphere(b - vec3(0.18, -0.22 + strum, 0.15), 0.048),
                      sdSphere(b - vec3(0.27, 0.01, 0.06), 0.045));
    r = U(hands, M_SKIN, r);

    // --- cape: a fluttering sheet from the shoulders, streaming against the flight
    vec3 c = p - vec3(-0.10, -0.22, 0.0);
    float ca = mix(0.35, 1.45, gSilasTilt);
    vec2 C = vec2(-sin(ca), -cos(ca));        // down the cape
    vec2 N = vec2(C.y, -C.x);                 // away from the back
    float s = dot(c.xy, C);
    float L = mix(0.55, 0.75, gSilasTilt);
    float sc = clamp(s, 0.0, L);
    float wave = (0.055 * sin(sc * 9.0 - t * CAPE_SPEED) + 0.025 * sin(c.z * 9.0 + t * 7.0)) * sc * 1.6;
    float w = dot(c.xy, N) - wave + 0.05 + 0.10 * sc;
    float wid = 0.16 + 0.17 * sc + 0.02 * sin(t * 6.0 + sc * 5.0);
    float cape = max(max(abs(s - 0.5 * L) - 0.5 * L, abs(c.z) - wid), abs(w) - 0.012) - 0.008;
    r = U(cape * 0.7, M_CAPE, r);
    // collar
    float collar = sdTorus((p - vec3(-0.03, -0.25, 0.0)), vec2(0.13, 0.03));
    r = U(collar, M_CAPE, r);

    return r;
}

// ======================================================================
// friends in the forest (shot 6): a little knight and a robot in a top hat
// both stand on y = 0, height ~1.
// ======================================================================
vec2 sdKnight(vec3 p, float t) {
    vec2 r = vec2(1e5, 0.0);
    vec3 h = p - vec3(0.0, 0.80, 0.0);
    r = U(sdSphere(h, 0.17), M_GREEN, r);                               // green face
    float hair = sdEllipsoid(h - vec3(-0.02, 0.06, 0.0), vec3(0.19, 0.15, 0.19));
    hair = smax(hair, -(h.y + 0.02 - 0.25 * max(h.z, 0.0)), 0.03);
    r = U(hair, M_HAIR, r);
    vec3 ep = vec3(h.x, h.y, abs(h.z));
    r = U(sdSphere(ep - vec3(0.06, 0.0, 0.145), 0.035), M_DARK, r);
    float body = sdRoundCone(p - vec3(0.0, 0.33, 0.0), 0.18, 0.12, 0.3);
    r = U(body, M_KN_TUNIC, r);
    vec3 lp = vec3(p.x, p.y, abs(p.z));
    r = U(sdCapsule(lp, vec3(0.0, 0.3, 0.07), vec3(0.0, 0.02, 0.08), 0.055), M_DARK, r);
    r = U(sdEllipsoid(lp - vec3(0.04, 0.03, 0.08), vec3(0.09, 0.05, 0.06)), M_CAPE, r); // red shoes
    // shield on the near arm, sword in the far hand
    vec3 sp = p - vec3(0.08, 0.40, 0.22);
    float sh = max(sdEllipsoid(sp, vec3(0.16, 0.20, 0.035)), sp.y - 0.15);
    r = U(sh, M_KN_SHIELD, r);
    r = U(sdCapsule(p, vec3(0.0, 0.55, -0.17), vec3(0.06, 0.38, -0.2), 0.045), M_KN_TUNIC, r);
    r = U(sdCapsule(p, vec3(0.06, 0.38, -0.21), vec3(0.18, 0.05, -0.22), 0.018), M_METAL, r);
    return r;
}

vec2 sdRobot(vec3 p, float t) {
    vec2 r = vec2(1e5, 0.0);
    vec3 h = p - vec3(0.0, 0.86, 0.0);
    r = U(sdRoundBox(h, vec3(0.14, 0.12, 0.13), 0.04), M_ROBO_FACE, r);
    vec3 ep = vec3(h.x, h.y, abs(h.z));
    r = U(sdSphere(ep - vec3(0.13, 0.02, 0.06), 0.03), M_EYE, r);
    // top hat
    r = U(sdCylinder(h - vec3(0.0, 0.17, 0.0), 0.018, 0.22), M_HAT, r);
    r = U(sdCylinder(h - vec3(0.0, 0.30, 0.0), 0.13, 0.14), M_HAT, r);
    r = U(sdRoundBox(p - vec3(0.0, 0.52, 0.0), vec3(0.15, 0.18, 0.15), 0.04), M_ROBO_CHEST, r);
    vec3 lp = vec3(p.x, p.y, abs(p.z));
    r = U(sdRoundBox(lp - vec3(0.0, 0.17, 0.08), vec3(0.06, 0.17, 0.06), 0.02), M_ROBO_LEG, r);
    r = U(sdRoundBox(lp - vec3(0.03, 0.03, 0.08), vec3(0.09, 0.04, 0.07), 0.02), M_DARK, r);
    // near arm waving
    float wv = 0.5 * sin(t * 6.0);
    vec3 a0 = vec3(0.0, 0.62, 0.21);
    vec3 a1 = a0 + vec3(0.12 * sin(wv), 0.28, 0.06);
    r = U(sdCapsule(p, a0, a1, 0.04), M_METAL, r);
    r = U(sdCapsule(p, vec3(0.0, 0.62, -0.21), vec3(0.02, 0.36, -0.24), 0.04), M_METAL, r);
    return r;
}

// ======================================================================
// Dad by the cabin (shot 9): long dark coat, wide hat, long blond hair. Height ~1.8 units.
// ======================================================================
vec2 sdDad(vec3 p, float t, float open) {
    vec2 r = vec2(1e5, 0.0);
    vec3 h = p - vec3(0.0, 1.58, 0.0);
    r = U(sdEllipsoid(h, vec3(0.11, 0.13, 0.11)), M_SKIN, r);
    float hair = sdEllipsoid(h - vec3(-0.03, -0.07, 0.0), vec3(0.13, 0.2, 0.15));
    hair = smax(hair, dot(h, normalize(vec3(1.0, 0.2, 0.0))) - 0.06, 0.03);
    r = U(hair, M_DADHAIR, r);
    r = U(sdCylinder(h - vec3(0.0, 0.10, 0.0), 0.012, 0.21), M_HAT, r);
    r = U(sdEllipsoid(h - vec3(0.0, 0.15, 0.0), vec3(0.12, 0.08, 0.12)), M_HAT, r);
    float body = sdRoundCone(p - vec3(0.0, 0.85, 0.0), 0.17, 0.2, 0.55);
    r = U(body, M_COAT, r);
    vec3 lp = vec3(p.x, p.y, abs(p.z));
    r = U(sdCapsule(lp, vec3(0.0, 0.85, 0.09), vec3(0.0, 0.06, 0.1), 0.075), M_COAT, r);
    r = U(sdEllipsoid(lp - vec3(0.05, 0.04, 0.1), vec3(0.13, 0.05, 0.07)), M_DARK, r);
    // arms: open wide, then wrap around the hug
    vec3 sh = vec3(0.0, 1.33, 0.2);
    vec3 el = mix(vec3(0.2, 1.05, 0.33), vec3(0.2, 1.08, 0.38), open);
    vec3 hd = mix(vec3(0.42, 1.15, 0.12), vec3(-0.05 + 0.6 * open, 1.4 - 0.25 * open, 0.62 + 0.0 * open), open);
    hd = mix(vec3(0.32, 1.08, 0.12), hd, open);
    r = U(min(sdCapsule(lp, sh, el, 0.06), sdCapsule(lp, el, hd, 0.055)), M_COAT, r);
    r = U(sdSphere(lp - hd, 0.05), M_SKIN, r);
    return r;
}

// ======================================================================
// scene map: whichever cast the current shot has
// ======================================================================
vec3 silasLocal(vec3 p) {
    vec3 q = (p - gSilasPos) / gSilasScale;
    q = rotY(gSilasYaw) * q;
    q = rotZ(-gSilasRoll) * q;
    return q;
}

vec2 map(vec3 p) {
    vec2 r = vec2(1e5, 0.0);
    vec3 q = silasLocal(p);
    vec2 s = sdSilas(q, gTime);
    s.x *= gSilasScale;
    r = s;
    if (gCast == 1) {
        float k = 0.62;
        vec3 kp = (p - vec3(0.35, -1.25, -0.6)) / k;
        kp = rotY(1.9) * kp;
        vec2 a = sdKnight(kp, gTime); a.x *= k;
        r = U(a.x, a.y, r);
        vec3 rp = (p - vec3(1.12, -1.25, -0.8)) / k;
        rp = rotY(1.75) * rp;
        vec2 b = sdRobot(rp, gTime); b.x *= k;
        r = U(b.x, b.y, r);
    } else if (gCast == 2) {
        float k = 1.05;
        vec3 dp = (p - vec3(0.35, -2.05, -0.4)) / k;
        dp = rotY(2.0 - 0.45 * gHug) * dp;
        vec2 d = sdDad(dp, gTime, gHug); d.x *= k;
        r = U(d.x, d.y, r);
    }
    return r;
}

// bounding sphere of the cast, so empty pixels skip the march
float castBound(vec3 ro, vec3 rd) {
    vec3 c = gSilasPos;
    float rad = 0.95 * gSilasScale;
    if (gCast == 1) { c = mix(c, vec3(0.8, -0.7, -0.6), 0.5); rad = max(rad, 1.9); }
    if (gCast == 2) { c = vec3(0.0, -0.9, -0.3); rad = 2.6; }
    vec3 oc = ro - c;
    float b = dot(oc, rd), cc = dot(oc, oc) - rad * rad;
    float h = b * b - cc;
    return h < 0.0 ? -1.0 : max(-b - sqrt(h), 0.0);
}

vec3 materialColor(float m, vec3 p, vec3 n) {
    if (m < 1.5) return lin(C_SKIN);
    if (m < 2.5) return lin(C_HAIR) * (0.85 + 0.25 * gradientNoise(p * 40.0));
    if (m < 3.5) return lin(C_SUIT);
    if (m < 4.5) return lin(C_CAPE);
    if (m < 5.5) return lin(C_GREEN);
    if (m < 6.5) return vec3(0.92);
    if (m < 7.5) {
        vec3 q = silasLocal(p);
        q.z = abs(q.z);
        float d = length(q.yz - vec2(0.022, 0.118));
        if (length(q.yz - vec2(0.045, 0.1)) < 0.012) return vec3(1.5);
        return d < 0.022 ? vec3(0.01) : lin(vec3(0.30, 0.62, 1.0));
    }
    if (m < 8.5) return lin(C_PACI);
    if (m < 9.5) return lin(C_UKE);
    if (m < 10.5) return lin(vec3(0.35, 0.80, 0.12));
    if (m < 11.5) return vec3(0.02);
    if (m < 12.5) return lin(vec3(0.38, 0.48, 0.20));
    if (m < 13.5) {
        float st = step(0.0, sin((p.x - p.z) * 30.0));
        return mix(lin(vec3(0.85, 0.12, 0.1)), lin(vec3(0.98, 0.78, 0.15)), st);
    }
    if (m < 14.5) return lin(vec3(0.55, 0.57, 0.62));
    if (m < 15.5) return lin(vec3(0.15, 0.45, 0.95));
    if (m < 16.5) return lin(vec3(0.92, 0.45, 0.12));
    if (m < 17.5) return lin(vec3(0.42, 0.2, 0.6));
    if (m < 18.5) return lin(vec3(0.06, 0.06, 0.08));
    if (m < 19.5) return lin(vec3(0.10, 0.12, 0.2));
    return lin(vec3(0.85, 0.66, 0.36));
}

vec3 shadeCast(vec3 p, vec3 n, vec3 rd, float m) {
    vec3 alb = materialColor(m, p, n);
    float dif = clamp(dot(n, gKeyDir) * 0.6 + 0.4, 0.0, 1.0);    // wrapped for soft toy skin
    dif *= dif;
    float hemi = 0.5 + 0.5 * n.y;
    float fres = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 3.0);
    float ao = calcAO(p, n, 0.12 * gSilasScale);
    vec3 col = alb * (gKeyCol * dif + gFillCol * hemi * ao + gFillCol * 0.9 * clamp(dot(n, -rd), 0.0, 1.0) * ao);
    // rim from the back light
    col += gRimCol * fres * (0.4 + 0.6 * clamp(dot(n, -gKeyDir * vec3(1.0, -0.4, 1.0)) + 0.6, 0.0, 1.0)) * ao;
    // subsurface-ish warmth on skin and cape
    if (m < 1.5 || abs(m - M_CAPE) < 0.5) col += alb * gKeyCol * 0.18 * pow(clamp(dot(rd, gKeyDir) + 0.3, 0.0, 1.0), 2.0);
    // plastic sheen on eyes, pacifier and the uke
    if (abs(m - M_EYE) < 0.5 || abs(m - M_PACI) < 0.5 || abs(m - M_UKE) < 0.5 || abs(m - M_IRIS) < 0.5) {
        vec3 hh = normalize(gKeyDir - rd);
        col += gKeyCol * 0.6 * pow(clamp(dot(n, hh), 0.0, 1.0), 60.0);
    }
    return col;
}

// ======================================================================
// backgrounds (linear HDR), uv: y in [-1,1], x in [-aspect, aspect]
// ======================================================================
float fbm2(vec2 p) { return fbm(p, 5); }

vec3 sunGlow(vec2 uv, vec2 sp, vec3 col, float size) {
    float d = length(uv - sp);
    return col * (exp(-d * d / (size * size)) * 2.5 + 0.35 * exp(-d * 2.2) + smoothstep(size * 0.25, 0.0, d) * 6.0);
}

// golden-hour sky with a sea of billowing clouds (shots 0, 1)
vec3 bgClouds(vec2 uv, float t, float zoom, float speed) {
    vec2 sp = gSunUV.xy;
    vec3 top = lin(vec3(0.52, 0.62, 0.86));
    vec3 hor = lin(vec3(1.0, 0.82, 0.52));
    vec3 col = mix(hor, top, smoothstep(-0.2, 1.1, uv.y));
    col += sunGlow(uv, sp, lin(vec3(1.0, 0.85, 0.55)), 0.18);
    // wisps up high
    float wsp = fbm2(vec2(uv.x * 1.2 + t * 0.03 * speed, uv.y * 4.0) * zoom + 3.0);
    col = mix(col, lin(vec3(1.0, 0.86, 0.76)) * 1.1, smoothstep(0.25, 0.75, wsp) * smoothstep(0.1, 0.9, uv.y) * 0.5);
    // cloud layers, back to front
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float depth = 1.0 + fi * 0.8;
        vec2 cp = uv * zoom / (1.0 + 0.15 * (3.0 - fi));
        cp.x += t * speed * 0.08 * depth + fi * 7.3;
        float base = mix(0.15, -0.65, fi / 3.0) / zoom;
        float puff = billowFbm(cp * vec2(1.6, 2.2) + fi * 3.1, 5);
        float edge = base + 0.38 * puff - uv.y * 1.0;
        float m = smoothstep(0.0, 0.04 + 0.02 * fi, edge);
        // lit tops, lavender bellies, warm rims toward the sun
        float lit = smoothstep(-0.1, 0.3, 0.38 * billowFbm(cp * vec2(1.6, 2.2) + fi * 3.1 + vec2(0.0, 0.06), 5) + base - uv.y - 0.05);
        vec3 belly = lin(vec3(0.82, 0.66, 0.74));
        vec3 crest = lin(vec3(1.0, 0.90, 0.80)) * 1.25;
        vec3 cc = mix(crest, belly, lit * 0.8);
        float sunSide = exp(-2.5 * length(uv - sp));
        cc += lin(vec3(1.0, 0.75, 0.4)) * sunSide * (1.0 - lit) * 1.8;
        cc = mix(cc, col, 0.35 * (1.0 - fi / 3.0));    // aerial haze
        col = mix(col, cc, m);
    }
    return col;
}

// tree trunk field for the forest layers; returns (distance-ish mask, shade)
vec2 trunks(vec2 p, float density, float seed) {
    float cell = floor(p.x * density);
    float best = 1e5, shade = 0.0;
    for (int k = -1; k <= 1; k++) {
        float c = cell + float(k);
        float h = hash12(vec2(c, seed));
        if (h < 0.35) continue;
        float cx = (c + 0.5 + (h - 0.5) * 0.6) / density;
        float w = (0.08 + 0.12 * hash12(vec2(c, seed + 3.0))) / density * 2.2;
        float flare = 1.0 + 1.8 * smoothstep(-0.2, -0.9, p.y);       // root flare at the base
        float d = abs(p.x - cx + 0.02 * sin(p.y * 6.0 + c)) - w * flare;
        if (d < best) { best = d; shade = (p.x - cx) / (w * flare); }
    }
    return vec2(best, shade);
}

// sunlit forest (shots 2, 3, 5, 6, 7). pan = camera travel, sunX = where the light comes from
vec3 bgForest(vec2 uv, float pan, vec2 sp, float clearing) {
    vec3 skyc = lin(vec3(1.0, 0.86, 0.55)) * 1.6;
    vec3 col = mix(lin(vec3(0.55, 0.62, 0.35)), skyc, smoothstep(-0.3, 0.6, uv.y));
    col += sunGlow(uv, sp, lin(vec3(1.0, 0.8, 0.45)), 0.25) * 0.8;
    // canopy blobs high up
    float can = fbm2(vec2(uv.x * 2.0 + pan * 0.3, uv.y * 2.5) + 11.0);
    col = mix(col, lin(vec3(0.20, 0.30, 0.10)) * (0.8 + 0.6 * exp(-2.0 * length(uv - sp))), smoothstep(0.55, 0.85, uv.y + 0.25 * can) * 0.9);
    // clearing glow
    col += lin(vec3(0.9, 0.85, 0.4)) * clearing * exp(-pow((uv.y + 0.25) * 4.0, 2.0)) * exp(-pow((uv.x - sp.x) * 1.3, 2.0));
    // trunk layers: far, mid, near
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float par = 0.35 + 0.5 * fi;
        vec2 p = vec2(uv.x + pan * par, uv.y);
        vec2 tr = trunks(p, mix(2.2, 0.75, fi / 2.0), 17.0 + fi * 5.0);
        float m = aaStep(tr.x, 0.004 + 0.003 * fi);
        float bark = 0.75 + 0.35 * fbm2(vec2(p.x * 25.0, p.y * 3.0) + fi);
        vec3 tc = lin(vec3(0.30, 0.22, 0.12)) * bark * (0.5 + 0.5 * clamp(0.5 + 0.6 * tr.y * sign(sp.x - uv.x), 0.0, 1.0));
        float moss = smoothstep(0.2, 0.7, fbm2(p * 6.0 + fi * 2.0) + (0.2 - uv.y) * 0.6);
        tc = mix(tc, lin(vec3(0.35, 0.45, 0.12)), moss * 0.7);
        // rim of light on the sun side of each trunk
        tc += lin(vec3(1.0, 0.75, 0.35)) * smoothstep(0.7, 1.0, tr.y * sign(sp.x - uv.x)) * 0.45;
        float haze = (2.0 - fi) / 2.0;
        tc = mix(tc, col * 0.6, haze * 0.4);
        col = mix(col, tc, m);
    }
    // god rays fanning from the sun
    vec2 dv = uv - sp;
    float ang = atan(dv.x, -dv.y + 1e-4);
    float rays = smoothstep(0.35, 0.9, fbm2(vec2(ang * 7.0 + pan * 0.2, 0.0) + 5.0)) * smoothstep(0.1, 1.2, length(dv)) * exp(-length(dv) * 0.8);
    col += lin(vec3(1.0, 0.85, 0.5)) * rays * 0.5 * smoothstep(0.4, -0.5, uv.y - sp.y + 0.3);
    // mossy ground with flowers
    float gy = -0.55 + 0.06 * fbm2(vec2(uv.x * 2.0 + pan, 0.0));
    float g = smoothstep(gy + 0.01, gy - 0.01, uv.y);
    vec2 gp = vec2((uv.x + pan * 1.1) / max(0.3, gy - uv.y + 0.15), uv.y);
    vec3 grass = lin(vec3(0.30, 0.45, 0.10)) * (0.6 + 0.6 * fbm2(gp * vec2(3.0, 12.0)));
    grass += lin(vec3(1.0, 0.8, 0.4)) * 0.25 * clearing;
    vec2 fl = gp * vec2(4.0, 30.0);
    vec2 fid = floor(fl);
    vec2 ff = fract(fl) - 0.5;
    float hf = hash12(fid);
    if (hf > 0.78) grass = mix(grass, hf > 0.9 ? lin(vec3(0.45, 0.35, 0.95)) : lin(vec3(0.95, 0.55, 0.85)), smoothstep(0.25, 0.1, length(ff)));
    col = mix(col, grass, g);
    // fireflies: drifting warm sparks
    for (int i = 0; i < 18; i++) {
        float fi = float(i);
        vec2 h = hash22(vec2(fi, 3.7));
        vec2 fp = vec2(fract(h.x - pan * 0.15 * (0.5 + h.y)) * 4.0 - 2.0, -0.7 + 0.8 * h.y + 0.05 * sin(gTime * 2.0 + fi));
        float tw = 0.6 + 0.4 * sin(gTime * 5.0 + fi * 2.3);
        col += lin(vec3(1.0, 0.85, 0.4)) * tw * 0.0012 / (dot(uv - fp, uv - fp) + 0.0006);
    }
    return col;
}

// the stream seen from above (shot 4)
vec3 bgStream(vec2 uv, float pan) {
    vec2 p = vec2(uv.x + pan, uv.y);
    float center = -0.25 - 0.35 * (p.x - pan) + 0.08 * sin(p.x * 2.0);
    float d = uv.y - center;
    float wdt = 0.28 + 0.06 * sin(p.x * 1.3);
    vec3 grass = lin(vec3(0.30, 0.42, 0.10)) * (0.55 + 0.7 * fbm2(p * vec2(5.0, 9.0)));
    grass += lin(vec3(1.0, 0.8, 0.4)) * 0.35 * smoothstep(-0.2, 1.0, uv.y);
    vec3 col = grass;
    // moss bank shading
    col *= 0.7 + 0.3 * smoothstep(0.0, 0.12, abs(d) - wdt);
    // water: deep teal with glints
    float w = smoothstep(0.01, -0.01, abs(d) - wdt);
    vec3 water = mix(lin(vec3(0.05, 0.28, 0.45)), lin(vec3(0.25, 0.65, 0.95)), 0.5 + 0.5 * fbm2(vec2(p.x * 3.0 - gTime * 1.5, d * 8.0)));
    vec2 sp = vec2(p.x * 40.0 - gTime * 8.0, d * 60.0);
    float sparkle = pow(max(0.0, valueNoise(sp) * valueNoise(sp * 1.7 + 4.0)), 6.0) * 40.0;
    water += lin(vec3(0.6, 0.9, 1.0)) * sparkle;
    col = mix(col, water, w);
    // rocks along the edge
    vec2 rp = vec2(p.x * 5.0, d * 5.0);
    vec2 rid = floor(rp);
    vec2 rf = fract(rp) - 0.5;
    float rh = hash12(rid + 9.0);
    if (rh > 0.7 && abs(abs(d) - wdt) < 0.12) {
        float rd = length(rf * vec2(1.0, 1.4)) - 0.28;
        vec3 rc = lin(vec3(0.45, 0.42, 0.38)) * (0.6 + 0.6 * clamp(-rf.y * 2.0 + 0.5, 0.0, 1.0));
        col = mix(col, rc, aaStep(rd, 0.03));
    }
    // warm light falling in from the top
    col += lin(vec3(1.0, 0.8, 0.4)) * 0.4 * smoothstep(0.2, 1.2, uv.y);
    return col;
}

// pink dusk over pine hills (shot 8) and behind the cabin (shot 9)
float pineRow(vec2 p, float scale, float seed) {
    vec2 q = p * scale;
    float cell = floor(q.x);
    float best = 1e5;
    for (int k = -1; k <= 1; k++) {
        float c = cell + float(k);
        float h = hash12(vec2(c, seed));
        float cx = c + 0.5 + (h - 0.5) * 0.5;
        float ht = 0.9 + 1.2 * h;
        float x = abs(q.x - cx);
        // stacked triangular tiers
        float y = q.y;
        float tier = fract(y * 2.2 / ht) * 0.35 + 0.15;
        float half_ = (ht - y) * 0.32 * (0.75 + tier);
        float d = max(x - max(half_, 0.0), y - ht);
        best = min(best, d / scale);
    }
    return best;
}

vec3 bgDusk(vec2 uv, float pan) {
    vec3 top = lin(vec3(0.50, 0.48, 0.76));
    vec3 mid = lin(vec3(0.96, 0.62, 0.68));
    vec3 hor = lin(vec3(1.0, 0.78, 0.55));
    vec3 col = mix(hor, mid, smoothstep(-0.25, 0.25, uv.y));
    col = mix(col, top, smoothstep(0.25, 1.0, uv.y));
    col += sunGlow(uv, vec2(-0.2, -0.32), lin(vec3(1.0, 0.7, 0.45)), 0.3) * 0.6;
    // soft pink cloudlets
    vec2 cp = vec2(uv.x * 1.5 + pan * 0.1, uv.y * 4.0);
    float cl = billowFbm(cp + 2.0, 4);
    col = mix(col, lin(vec3(1.0, 0.72, 0.78)), smoothstep(0.55, 0.75, cl) * smoothstep(0.05, 0.4, uv.y) * 0.85);
    // distant mountains
    float mtn = -0.30 + 0.12 * fbm(vec2(uv.x * 1.2 + pan * 0.15, 0.0), 4);
    col = mix(col, mix(lin(vec3(0.55, 0.42, 0.62)), col, 0.4), aaStep(uv.y - mtn, 0.004));
    // pine rows
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float base = -0.42 - 0.12 * fi;
        vec2 p = vec2(uv.x + pan * (0.35 + 0.35 * fi) + fi * 3.3, uv.y - base);
        float d = pineRow(p, mix(9.0, 3.5, fi / 2.0), fi * 11.0);
        d = min(d, p.y);                                       // fill below the tree line
        vec3 tc = mix(lin(vec3(0.62, 0.48, 0.66)), lin(vec3(0.20, 0.20, 0.22)), fi / 2.0);
        tc *= 0.85 + 0.3 * smoothstep(-0.2, 0.4, p.y);
        col = mix(col, tc, aaStep(d, 0.004));
    }
    return col;
}

vec3 bgCabin(vec2 uv, float zoom) {
    uv /= zoom;
    vec3 col = bgDusk(uv, 0.0);
    float px = 0.004 / zoom;
    // meadow
    float gy = -0.62 + 0.03 * sin(uv.x * 2.0);
    vec3 meadow = lin(vec3(0.42, 0.42, 0.16)) * (0.6 + 0.5 * fbm2(uv * vec2(4.0, 20.0)));
    meadow += lin(vec3(1.0, 0.6, 0.45)) * 0.15;
    col = mix(col, meadow, aaStep(uv.y - gy, px));
    // stone path
    float path = abs(uv.x - 0.05 + (uv.y + 0.62) * 0.4) - (0.06 - (uv.y + 0.62) * 0.25);
    col = mix(col, lin(vec3(0.5, 0.42, 0.38)) * (0.7 + 0.4 * valueNoise(uv * 40.0)), aaStep(path, px) * step(uv.y, gy));

    vec2 c = uv - vec2(0.05, -0.15);
    // log walls
    float wall = box2(c - vec2(0.0, -0.18), vec2(0.62, 0.32));
    float logs = fract((c.y + 0.5) * 24.0);
    vec3 wood = lin(vec3(0.42, 0.25, 0.13)) * (0.55 + 0.45 * smoothstep(0.0, 0.5, logs) * smoothstep(1.0, 0.6, logs));
    wood *= 0.8 + 0.3 * valueNoise(vec2(c.x * 30.0, floor((c.y + 0.5) * 24.0)));
    col = mix(col, wood, aaStep(wall, px));
    // roof: wide dark gable with a front gable
    vec2 rp = c - vec2(0.0, 0.14);
    float roof = max(abs(rp.x) * 0.62 + rp.y - 0.28, -rp.y - 0.0);
    roof = max(roof, abs(rp.x) - 0.82);
    col = mix(col, lin(vec3(0.16, 0.14, 0.18)) * (0.8 + 0.3 * fract(rp.y * 30.0)), aaStep(roof, px));
    float gable = max(abs(c.x) * 0.95 + (c.y - 0.08) - 0.22, -(c.y - 0.0));
    gable = max(gable, abs(c.x) - 0.30);
    col = mix(col, wood * 0.9, aaStep(gable + 0.02, px));
    col = mix(col, lin(vec3(0.16, 0.14, 0.18)), aaStep(abs(gable + 0.02) - 0.012, px) * step(-0.01, c.y));
    // chimney
    col = mix(col, lin(vec3(0.35, 0.33, 0.36)), aaStep(box2(c - vec2(0.34, 0.38), vec2(0.045, 0.1)), px));
    // glowing windows and the door
    vec3 glow = lin(vec3(1.0, 0.7, 0.3)) * 3.0;
    vec2 wp = vec2(abs(c.x) - 0.36, c.y + 0.16);
    float win = box2(wp, vec2(0.075, 0.085));
    vec3 wc = glow * (0.7 + 0.3 * smoothstep(0.1, -0.08, wp.y));
    wc = mix(wc, lin(vec3(0.2, 0.12, 0.06)), max(aaStep(abs(wp.x) - 0.008, px), aaStep(abs(wp.y) - 0.008, px)));
    col = mix(col, wc, aaStep(win, px));
    col += glow * 0.08 * exp(-max(win, 0.0) * 25.0);
    float upw = box2(c - vec2(0.0, 0.12), vec2(0.06, 0.06));
    col = mix(col, glow * 0.9, aaStep(upw, px));
    col += glow * 0.06 * exp(-max(upw, 0.0) * 25.0);
    float door = box2(c - vec2(0.0, -0.32), vec2(0.09, 0.18));
    col = mix(col, lin(vec3(0.28, 0.16, 0.08)), aaStep(door, px));
    col = mix(col, glow * 0.5, aaStep(box2(c - vec2(0.0, -0.22), vec2(0.05, 0.04)), px));
    return col;
}

// ======================================================================
// the edit: which shot, where everyone is, how it is lit
// ======================================================================
void setupShot(float t) {
    gTime = t;
    gCast = 0;
    gHug = 0.0;
    gSilasYaw = 0.35;
    gSilasRoll = 0.0;
    gSilasTilt = 1.0;
    gKeyDir = normalize(vec3(0.6, 0.5, -0.6));
    gKeyCol = lin(vec3(1.0, 0.82, 0.6)) * 2.2;
    gFillCol = lin(vec3(0.55, 0.55, 0.75)) * 0.75;
    gRimCol = lin(vec3(1.0, 0.8, 0.5)) * 1.6;
    float bob = 0.04 * sin(t * 2.3);

    if (t < 1.75) {                         // close, over the clouds
        gShot = 0; gT = t;
        gSunUV = vec3(1.1, 0.75, 1.0);
        gSilasPos = vec3(-0.85 + 0.12 * gT, 0.1 + bob, 0.6);
        gSilasScale = 1.9;
        gSilasYaw = 0.55;
        gSilasRoll = 0.12;
    } else if (t < 6.0) {                   // wide, flying into the sun
        gShot = 1; gT = t - 1.75;
        gSunUV = vec3(0.55, 0.1, 1.0);
        float k = gT / 4.25;
        gSilasPos = vec3(mix(-1.3, 0.25, k), mix(0.55, 0.25, k) + bob, mix(0.0, -2.0, k));
        gSilasScale = mix(0.75, 0.5, k);
        gSilasYaw = mix(0.4, 0.1, k);
        gKeyDir = normalize(vec3(0.3, 0.3, -1.0));
    } else if (t < 11.25) {                 // forest hover, then the root pass
        gShot = t < 10.5 ? 2 : 3; gT = t - 6.0;
        gSunUV = vec3(0.6, 0.55, 1.0);
        float k = gT / 4.5;
        gSilasTilt = mix(0.15, 0.55, smoothstep(0.5, 1.0, k));
        gSilasPos = vec3(mix(-0.9, 0.5, k), mix(-0.15, 0.0, k) + 1.5 * bob, mix(-0.5, -1.5, k));
        gSilasScale = 0.62;
        gSilasYaw = mix(0.9, 0.3, k);
        gKeyDir = normalize(vec3(0.5, 0.6, -0.8));
        gKeyCol = lin(vec3(1.0, 0.8, 0.5)) * 1.7;
        gFillCol = lin(vec3(0.6, 0.6, 0.55)) * 0.8;
    } else if (t < 12.5) {                  // over the stream
        gShot = 4; gT = t - 11.25;
        gSunUV = vec3(0.3, 1.3, 1.0);
        gSilasPos = vec3(mix(-1.0, 0.3, gT / 1.25), -0.15 + bob, 0.2);
        gSilasScale = 0.85;
        gSilasYaw = 0.25;
        gSilasRoll = 0.15;
        gKeyDir = normalize(vec3(0.2, 0.9, -0.3));
        gFillCol = lin(vec3(0.4, 0.6, 0.7)) * 0.8;
    } else if (t < 19.0) {                  // big tree and clearing, then the friends
        gShot = t < 16.0 ? 5 : 6; gT = t - 12.5;
        gSunUV = vec3(0.75, 0.45, 1.0);
        gSilasPos = vec3(-0.85 + 0.05 * sin(gT), -0.05 + bob, 1.2);
        gSilasScale = 1.35;
        gSilasYaw = 0.6;
        gSilasRoll = 0.08;
        if (gShot == 6) {
            float k = (t - 16.0) / 3.0;
            gCast = 1;
            gSilasPos = vec3(mix(-1.2, -0.6, k), 0.05 + bob, 1.2);
            gSilasScale = 1.15;
        }
        gKeyDir = normalize(vec3(0.8, 0.5, -0.7));
        gKeyCol = lin(vec3(1.0, 0.8, 0.5)) * 1.8;
        gFillCol = lin(vec3(0.62, 0.6, 0.55)) * 0.8;
    } else if (t < 21.0) {                  // backlit forest, rising up
        gShot = 7; gT = t - 19.0;
        gSunUV = vec3(0.9, 0.35, 1.0);
        gSilasPos = vec3(-0.35 + 0.1 * gT, -0.05 + 0.08 * gT + bob, 1.0);
        gSilasScale = 1.45;
        gSilasYaw = 0.75;
        gSilasTilt = 0.85;
        gKeyDir = normalize(vec3(0.7, 0.4, -0.9));
        gKeyCol = lin(vec3(1.0, 0.75, 0.45)) * 1.6;
        gFillCol = lin(vec3(0.6, 0.58, 0.52)) * 0.75;
    } else if (t < 25.0) {                  // dusk flight toward the cabin
        gShot = 8; gT = t - 21.0;
        gSunUV = vec3(-0.2, -0.32, 0.6);
        float k = gT / 4.0;
        gSilasPos = vec3(mix(-0.55, -0.35, k), mix(0.15, -0.05, k) + bob, mix(1.3, 0.8, k));
        gSilasScale = mix(1.2, 0.85, k);
        gSilasYaw = mix(0.35, -0.1, k);
        gKeyDir = normalize(vec3(-0.6, 0.35, -0.8));
        gKeyCol = lin(vec3(1.0, 0.65, 0.55)) * 1.7;
        gFillCol = lin(vec3(0.6, 0.5, 0.75)) * 0.8;
        gRimCol = lin(vec3(1.0, 0.65, 0.6)) * 1.7;
    } else {                                // the cabin: catch and hug
        gShot = 9; gT = t - 25.0;
        gSunUV = vec3(-0.6, -0.3, 0.6);
        gCast = 2;
        float fly = ease(gT / 1.1);
        gHug = ease((gT - 0.8) / 0.8);
        vec3 start = vec3(-2.4, -0.1, 0.4);
        vec3 arms = vec3(0.12, -0.5, 0.25);
        gSilasPos = mix(start, arms, fly) + vec3(0.0, 0.03 * sin(gT * 2.0), 0.0) * (1.0 - gHug);
        gSilasScale = 0.8;
        gSilasYaw = mix(0.2, 0.5, gHug);
        gSilasTilt = mix(1.0, 0.35, gHug);
        gKeyDir = normalize(vec3(-0.5, 0.45, 0.8));
        gKeyCol = lin(vec3(1.0, 0.7, 0.55)) * 1.4;
        gFillCol = lin(vec3(0.6, 0.5, 0.8)) * 0.9;
        gRimCol = lin(vec3(1.0, 0.7, 0.45)) * 1.5;
    }
}

vec3 background(vec2 uv) {
    if (gShot == 0) return bgClouds(uv, gT, 0.8, 3.0);
    if (gShot == 1) return bgClouds(uv, gT + 1.75, 1.2, 1.5);
    if (gShot == 2) return bgForest(uv, gT * 0.12, gSunUV.xy, 0.3);
    if (gShot == 3) {
        vec3 c = bgForest(uv, gT * 0.12, gSunUV.xy, 0.3);
        // a huge mossy root sweeps past the lens
        float k = (gTime - 10.5) / 0.75;
        float x = mix(2.6, -2.6, k);
        float d = uv.x - x + 0.4 * sin(uv.y * 2.0 + 1.0) - 0.6 * uv.y;
        float m = smoothstep(0.9, 0.6, abs(d));
        vec3 root = mix(lin(vec3(0.22, 0.16, 0.08)), lin(vec3(0.30, 0.42, 0.10)), smoothstep(0.0, 0.7, fbm2(uv * 4.0) + 0.3));
        return mix(c, root * 0.8, m);
    }
    if (gShot == 4) return bgStream(uv, gT * 0.9);
    if (gShot == 5) return bgForest(uv * 0.8 + vec2(0.3, 0.1), gT * 0.08, vec2(0.75, 0.45) * 0.8, 1.0);
    if (gShot == 6) return bgForest(uv * 0.9 + vec2(0.2, 0.05), 0.5 + gT * 0.06, vec2(0.95, 0.5), 0.6);
    if (gShot == 7) return bgForest(uv * 1.1, 2.0 + gT * 0.18, gSunUV.xy, 0.4);
    if (gShot == 8) {
        vec3 c = bgDusk(uv, gT * 0.25);
        // the cabin slides in on the right once the meadow opens up
        float k = smoothstep(1.2, 4.0, gT);
        if (k > 0.0) {
            vec2 cu = (uv - vec2(mix(2.4, 1.05, k), -0.05)) / 0.55;
            vec3 cab = bgCabin(cu, 1.0);
            float m = smoothstep(0.0, 0.02, -box2(cu - vec2(0.05, -0.12), vec2(0.85, 0.55))) * step(-0.95, cu.y);
            c = mix(c, cab, m);
        }
        return c;
    }
    return bgCabin(uv - vec2(0.0, 0.12), 1.55 + 0.06 * gT);
}

// ======================================================================
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float t = iTime;
    if (LOOP == 1) t = mod(t, 30.0);
    setupShot(t);

    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    // gentle handheld drift
    vec2 drift = 0.01 * vec2(sin(t * 0.7), sin(t * 0.9 + 1.0));
    vec3 col = background(uv + drift);

    vec3 ro = vec3(0.0, 0.0, 4.0);
    vec3 rd = normalize(vec3(uv, -FOCAL));
    float t0 = castBound(ro, rd);
    if (t0 >= 0.0) {
        vec3 h = raymarch(ro, rd, t0, 9.0, 0.75);
        if (h.x > 0.0) {
            vec3 p = ro + rd * h.x;
            vec3 n = calcNormal(p, 0.0006 * h.x);
            vec3 c = shadeCast(p, n, rd, h.y);
            // a bit of the scene's haze over the cast keeps it in the same air
            c = mix(c, col, 0.03);
            col = c;
#if DEBUG_MODE == 1
            col = n * 0.5 + 0.5;
#elif DEBUG_MODE == 2
            col = debugIdColor(h.y);
#endif
        }
    }

    // grade: warm lift, vignette, dip to black at the very end
    col *= EXPOSURE;
    col = tonemapAgXPunchy(col);
    col = saturation(col, 1.12);
    col *= vignette(uv * 0.5, 1.2) * 0.25 + 0.75;
    col *= smoothstep(30.0, 29.6, t);
    col = linearToSrgb(col);
    col = filmGrain(col, GRAIN, hash12(fragCoord + float(iFrame) * 13.1));
    col += ditherTPDF(fragCoord, iFrame);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
