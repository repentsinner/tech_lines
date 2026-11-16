// A consumer style: fades a line from full at fadeCenter to nothing at
// fadeRadius, measured in the xy plane, the way an application fades a
// ground grid toward the edge of its patch. The world position carries the
// depth bias along the view, so the fade measures within the plane.
void styleLine(inout ScreenLineStyle style, ScreenLineFragment fragment) {
    float reach = distance(fragment.worldPosition.xy,
        materialParams.fadeCenter.xy) / max(materialParams.fadeRadius, 1e-6);
    float fade = 1.0 - smoothstep(0.0, 1.0, reach);
    style.alpha *= fade;
    style.glowScale *= fade;
}
