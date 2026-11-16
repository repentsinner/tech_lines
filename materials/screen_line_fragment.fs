// Fragment stage shared by screen_line_body.mat and screen_line_edge.mat.
//
// Coverage is the fraction of a target pixel the line covers, from the
// fragment's exact distance to the segment in pixel space. Both passes
// compute the same value, so the body keeps exactly the fragments the edge
// drops and every fragment draws once.

// Coverage at or above this is treated as full; one 8-bit step below 1.
#define SCREEN_LINE_FULL_COVERAGE (1.0 - 1.0 / 255.0)

// Cap styles, matching LineCap in the Dart API.
#define SCREEN_LINE_CAP_BUTT 0
#define SCREEN_LINE_CAP_ROUND 1
#define SCREEN_LINE_CAP_SQUARE 2

// Coverage of the interval [lo, hi] by a pixel footprint `ramp` wide
// centred at x: their overlap as a fraction of the footprint. It
// integrates to hi - lo for any ramp, so a line thinner than its ramp
// still sums to its width.
float screenLineOverlap(float lo, float hi, float x, float ramp) {
    float h = 0.5 * ramp;
    return max(min(hi, x + h) - max(lo, x - h), 0.0) / ramp;
}

float screenLineCoverage() {
    vec2 local = variable_lineFrame.xy / variable_lineFrame.z;
    float along = local.x;
    float across = abs(local.y);
    float lengthPx = variable_lineShape.x;
    float halfDrawn = variable_lineFrame.w / variable_lineFrame.z;
    float ramp = variable_lineShape.w;

    float coverage;
    if (materialParams.capStyle == SCREEN_LINE_CAP_ROUND) {
        float outside = along - clamp(along, 0.0, lengthPx);
        float distance = length(vec2(outside, across));
        coverage = screenLineOverlap(-halfDrawn, halfDrawn, distance, ramp);
    } else {
        float extent = materialParams.capStyle == SCREEN_LINE_CAP_SQUARE
            ? halfDrawn : 0.0;
        coverage =
            screenLineOverlap(-halfDrawn, halfDrawn, across, ramp) *
            screenLineOverlap(-extent, lengthPx + extent, along, ramp);
    }

    // Dashes measure along the segment in target pixels from its start.
    vec2 dash = materialParams.dash;
    if (dash.x > 0.0 && dash.y > 0.0) {
        float phase = mod(along, dash.x + dash.y);
        coverage *= clamp(dash.x - phase + 0.5, 0.0, 1.0) *
            clamp(phase + 0.5, 0.0, 1.0);
    }

    return coverage * variable_lineProgress.y / variable_lineFrame.z;
}

// Linear RGB of the fragment and its alpha before coverage.
vec4 screenLineColor() {
    vec4 vertexColor = getColor();
    float mixAmount = materialParams.vertexColorMix;
    vec3 rgb = mix(materialParams.lineColor.rgb, vertexColor.rgb, mixAmount);
    // A segment colour carries its own alpha, so it replaces the style
    // colour's alpha rather than multiplying with it.
    float alpha = mix(materialParams.lineColor.a, vertexColor.a, mixAmount) *
        materialParams.opacity;

    // Progress: a negative cursor disables it. Fragments behind the cursor
    // dim; fragments between the cursor and the window end brighten.
    float cursor = materialParams.progressCursor;
    float windowEnd = materialParams.progressWindowEnd;
    float progress = variable_lineProgress.x;
    if (cursor >= 0.0) {
        if (progress < cursor) {
            rgb *= materialParams.progressDim;
        } else if (windowEnd >= 0.0 && progress > cursor && progress <= windowEnd) {
            rgb *= materialParams.progressBoost;
        }
    }

    return vec4(rgb, alpha);
}
