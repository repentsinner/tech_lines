// Vertex stage shared by screen_line_body.mat and screen_line_edge.mat.
//
// Each segment arrives as four vertices, one per quad corner:
//   position    = this endpoint (model space)
//   CUSTOM0.xyz = the other endpoint (model space)
//   CUSTOM0.w   = line width in logical pixels
//   UV0         = (side, isEnd): side is -1 or +1 across the line, isEnd
//                 is 0 at the segment's start and 1 at its end
//   UV1.x       = progress at this endpoint
//   COLOR       = linear RGBA for the segment
//
// The quad is built in render-target pixels from Filament's own target
// size, then mapped back to world space through the inverse projection,
// so Filament's own transform lands each corner exactly where it was
// placed. Fragment coverage needs the fragment's position in the
// segment's pixel frame; those coordinates are linear in screen space, so
// they travel premultiplied by clip w and the fragment divides the
// perspective out again.

// Smallest drawn width in target pixels. Thinner lines draw this wide and
// scale their coverage by width instead.
#define SCREEN_LINE_MIN_WIDTH 1.0


// Largest fraction of its distance the depth bias moves a corner towards
// the camera. A line many pixels wide near the camera, as a perspective
// width draws one, would otherwise be moved past the camera and vanish.
#define SCREEN_LINE_MAX_DEPTH_SHIFT 0.25

// Keeps a trimmed endpoint strictly in front of the near plane.
#define SCREEN_LINE_NEAR_MARGIN 1e-5

// Clip-space distance in front of the near plane. Filament's projection
// is reversed-Z, so the near plane is z == w on every backend.
float screenLineNearDistance(vec4 clip) {
    return clip.w - clip.z;
}

// Moves `p` along the segment towards `q` until it lies in front of the
// near plane. Clip space is linear in world space, so the lerp is exact.
vec4 screenLineTrim(vec4 p, vec4 q) {
    float dp = screenLineNearDistance(p);
    if (dp >= SCREEN_LINE_NEAR_MARGIN) {
        return p;
    }
    float dq = screenLineNearDistance(q);
    float t = (SCREEN_LINE_NEAR_MARGIN - dp) / max(dq - dp, 1e-20);
    return mix(p, q, clamp(t, 0.0, 1.0));
}

void screenLineVertex(inout MaterialVertexInputs material) {
    vec4 custom = getCustom0();
    mat4 clipFromWorld = getClipFromWorldMatrix();
    vec4 clipThis = clipFromWorld * (getWorldFromModelMatrix() * getPosition());
    vec4 clipOther = clipFromWorld *
        (getWorldFromModelMatrix() * vec4(custom.xyz, 1.0));

    float side = material.uv0.x;
    bool isEnd = material.uv0.y > 0.5;

    bool thisBehind = screenLineNearDistance(clipThis) < 0.0;
    bool otherBehind = screenLineNearDistance(clipOther) < 0.0;
    vec4 clipA = screenLineTrim(isEnd ? clipOther : clipThis,
                                isEnd ? clipThis : clipOther);
    vec4 clipB = screenLineTrim(isEnd ? clipThis : clipOther,
                                isEnd ? clipOther : clipThis);

    vec4 res = getResolution();
    vec2 pixA = (clipA.xy / clipA.w * 0.5 + 0.5) * res.xy;
    vec2 pixB = (clipB.xy / clipB.w * 0.5 + 0.5) * res.xy;

    vec2 delta = pixB - pixA;
    float lengthPx = length(delta);
    vec2 dir = lengthPx > 1e-4 ? delta / lengthPx : vec2(1.0, 0.0);
    vec2 normal = vec2(-dir.y, dir.x);

    // A present scale below 1 means the platform shrinks the finished
    // frame, so the ramp and the minimum width grow by its inverse: the
    // frame then carries no detail finer than the resample keeps.
    float rampScale = materialParams.rampScale;
    float minWidth = SCREEN_LINE_MIN_WIDTH * rampScale;
    // Perspective width: a positive reference depth draws the line at its
    // width there and scales it by reference over depth elsewhere, as a
    // tube of fixed thickness would foreshorten. Each end takes its own
    // depth, so the width varies along the segment.
    mat4 clipFromView = getClipFromViewMatrix();
    bool orthographic = clipFromView[2][3] == 0.0;
    float referenceDepth = materialParams.widthReferenceDepth;
    float depthScale = referenceDepth > 0.0 && !orthographic
        ? referenceDepth / (isEnd ? clipB : clipA).w
        : 1.0;
    float widthPx = custom.w * materialParams.pixelScale * depthScale;
    float halfDrawn = 0.5 * max(widthPx, minWidth);
    float coverageScale = min(widthPx / minWidth, 1.0);
    // A square pixel's footprint across the line: one pixel for an axis-
    // aligned line, up to the diagonal at 45 degrees. The coverage ramp
    // spans it, which keeps a diagonal line's sum steady as it moves.
    float ramp = (abs(dir.x) + abs(dir.y)) * rampScale;
    float reach = halfDrawn + 0.5 * ramp;

    // Butt caps stop at the endpoint, so the quad only needs to cover the
    // anti-aliasing ramp past it. Round and square caps reach a half width
    // further.
    float capReach = materialParams.capStyle == 0 ? 0.5 * ramp : reach;

    vec4 clipCorner = isEnd ? clipB : clipA;
    vec2 pixCorner = isEnd ? pixB : pixA;
    float along = isEnd ? lengthPx + capReach : -capReach;
    float across = side * reach;
    pixCorner += dir * (isEnd ? capReach : -capReach) + normal * across;

    float w = clipCorner.w;
    vec2 ndc = pixCorner / res.xy * 2.0 - 1.0;
    vec4 world = getWorldFromClipMatrix() * vec4(ndc * w, clipCorner.z, w);
    world /= world.w;

    // Depth bias: move the corner towards the camera along its view ray,
    // which leaves its pixel position unchanged. The quad lies at its
    // endpoint's depth across its whole width, while a face under the line
    // tilted by incidence a comes closer by tan(a) pixel sizes per pixel.
    // So the bias is a relative part for depth precision plus `reach`
    // pixel sizes times the slope factor. An orthographic view has
    // parallel rays, so the corner moves along view z instead.
    vec4 view = getViewFromWorldMatrix() * world;
    float pixelSize = 2.0 / (res.y * clipFromView[1][1]);
    float slopeShift = materialParams.depthSlopeBias * reach * pixelSize;
    if (orthographic) {
        view.z += abs(view.z) * materialParams.depthBias + slopeShift;
    } else {
        view.xyz *= 1.0 - min(
            materialParams.depthBias + slopeShift,
            SCREEN_LINE_MAX_DEPTH_SHIFT);
    }
    world = getWorldFromViewMatrix() * view;
    w = (clipFromWorld * world).w;

    if (thisBehind && otherBehind) {
        // Entirely behind the camera: place the quad beyond the far plane.
        world = getWorldFromClipMatrix() * vec4(0.0, 0.0, -2.0, 1.0);
        world /= world.w;
    }
    material.worldPosition = world;

    // The half width and coverage scale differ between the ends under a
    // perspective width, and must interpolate linearly in screen space
    // like the frame coordinates, so they too travel premultiplied by w.
    material.lineFrame = vec4(along * w, across * w, w, halfDrawn * w);
    material.lineShape = vec4(lengthPx, 0.0, 0.0, ramp);
    material.lineProgress = vec4(material.uv1.x, coverageScale * w, 0.0, 0.0);
}
