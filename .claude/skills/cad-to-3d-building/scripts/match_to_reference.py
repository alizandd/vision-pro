"""Match-to-Reference helpers for the CAD->3D building pipeline (Phase 4.5).

Use when a *reference model* (e.g. an architect FBX/glTF) is the geometry ground-truth and
our CAD-built model must be snapped to it feature-by-feature. The reference is typically a
single combined mesh, so we measure it by GEOMETRY QUERIES (Z-level histogram, wall-plane
clusters, roof-pitch from normals), optionally narrowed to a component via the reference's
material slots used purely as a face *selector* (no material work).

Run inside Blender (paste into `execute_blender_code` via the Blender MCP, or
`blender --background --python match_to_reference.py`). Headless-safe: no `bpy.ops` that
need a 3D-view context. Conventions: metres; front face toward -Y; building parts parented
to a `Move`/`Rox_Move` empty.

Typical loop:
    ref   = bpy.data.objects["Reference_Structure"]
    model = [o for o in bpy.data.collections["Rox_Building"].objects if o.type == 'MESH']
    align_reference(ref, model)                       # snap ref ONTO model by 3 datums
    print(report(ref, model))                         # numeric diff -> punch-list
    overlay_render(ref, model, "front", "/tmp/d.png") # ghost ref over solid model
    # ...fix model parts to the ref values, re-run report() until within tolerance.
"""
import bpy, math, os
from mathutils import Vector

# Default acceptance tolerances (Definition of Done for Phase 4.5)
TOL_DATUM_M = 0.05   # Z levels & wall planes within 50 mm
TOL_PITCH_DEG = 2.0  # roof pitch within 2 degrees


# ----------------------------------------------------------------- world geometry
def world_bbox(objs):
    """Tight world AABB from **evaluated vertices** -- NOT `object.bound_box`.

    `bound_box` is cached and goes stale after direct mesh edits / `transform_apply`,
    which silently corrupts datum alignment (wrong anchor, false "delta 0"). Evaluating
    the depsgraph mesh is the only reliable read after you mutate geometry.
    """
    dg = bpy.context.evaluated_depsgraph_get()
    mn = Vector((1e18,) * 3); mx = Vector((-1e18,) * 3)
    for o in objs:
        if o.type != 'MESH':
            continue
        oe = o.evaluated_get(dg)
        me = oe.to_mesh()
        mw = oe.matrix_world
        for v in me.vertices:
            w = mw @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
        oe.to_mesh_clear()
    return mn, mx


def _mat_indices(obj, mat_filter):
    """Slot indices whose material name contains `mat_filter` (case-insensitive)."""
    if mat_filter is None:
        return None
    f = mat_filter.lower()
    return {i for i, m in enumerate(obj.data.materials) if m and f in m.name.lower()}


def world_faces(obj, mat_filter=None):
    """Yield (centroid_world, normal_world, area_world) for each polygon.

    `mat_filter` restricts to faces whose material slot name matches -- this is how you
    isolate one component (roof / window / trim) on a single combined reference mesh.
    """
    me = obj.data
    mw = obj.matrix_world
    nm = mw.to_3x3().inverted_safe().transposed()
    keep = _mat_indices(obj, mat_filter)
    for p in me.polygons:
        if keep is not None and p.material_index not in keep:
            continue
        c = mw @ p.center
        n = (nm @ p.normal)
        n.normalize()
        # world area (relative weight): scale local area by the mean axis scale squared
        s = mw.to_scale()
        area = p.area * ((abs(s.x) + abs(s.y) + abs(s.z)) / 3.0) ** 2
        if area <= 1e-9:      # skip degenerate faces (zero area -> bad normal/weight)
            continue
        yield c, n, area


# ----------------------------------------------------------------- alignment
def align_reference(ref, model_objs, x='min', y='min', z='min'):
    """Translate `ref` so three datums coincide with the model: ground (z), front plane,
    and one side corner. `x`/`y`/`z` each = 'min' | 'max' | 'center'. Defaults assume both
    front faces point toward -Y (front plane = min Y) and a shared left corner (min X).
    Returns the applied delta. Rotation/scale on `ref` should already be applied."""
    rmn, rmx = world_bbox([ref])
    mmn, mmx = world_bbox(model_objs)

    def pick(mode, rlo, rhi, mlo, mhi):
        if mode == 'min':    return mlo - rlo
        if mode == 'max':    return mhi - rhi
        return (mlo + mhi) / 2 - (rlo + rhi) / 2  # center

    d = Vector((
        pick(x, rmn.x, rmx.x, mmn.x, mmx.x),
        pick(y, rmn.y, rmx.y, mmn.y, mmx.y),
        pick(z, rmn.z, rmx.z, mmn.z, mmx.z),
    ))
    ref.location += d
    bpy.context.view_layer.update()
    return [round(v, 4) for v in d]


# ----------------------------------------------------------------- datum extraction
def _cluster(vals_weights, tol):
    """Area-weighted 1D clustering. vals_weights = [(value, weight), ...]."""
    items = sorted(vals_weights)
    out = []
    for v, w in items:
        if w <= 0:
            continue
        if out and abs(v - out[-1][0]) <= tol:
            tv, tw = out[-1]
            denom = tw + w
            out[-1] = ((tv * tw + v * w) / denom, denom)
        else:
            out.append((v, w))
    return out


def z_datums(obj, mat_filter=None, tol=TOL_DATUM_M, min_area=0.4):
    """Horizontal-face Z levels (floor / sill / head / eave / ridge), area-weighted."""
    vw = [(round(c.z, 4), a) for c, n, a in world_faces(obj, mat_filter) if abs(n.z) > 0.9]
    return [(round(z, 3), round(w, 2)) for z, w in _cluster(vw, tol) if w >= min_area]


def wall_planes(obj, tol=TOL_DATUM_M, min_area=0.4):
    """Vertical-face planes, split by facing axis. Returns {'x':[...], 'y':[...]} offsets."""
    out = {'x': [], 'y': []}
    for axis in ('x', 'y'):
        i = 0 if axis == 'x' else 1
        vw = [(round(c[i], 4), a) for c, n, a in world_faces(obj)
              if abs(n.z) < 0.1 and abs(n[i]) > 0.9]
        out[axis] = [(round(p, 3), round(w, 2)) for p, w in _cluster(vw, tol) if w >= min_area]
    return out


def roof_pitch(obj, mat_filter=None):
    """Area-weighted roof pitch in degrees from sloped faces (0.1 < |n.z| < 0.95)."""
    num = den = 0.0
    for c, n, a in world_faces(obj, mat_filter):
        if 0.1 < abs(n.z) < 0.95:
            num += math.degrees(math.acos(min(1.0, abs(n.z)))) * a
            den += a
    return round(num / den, 2) if den else None


# ----------------------------------------------------------------- diff
def match_levels(ref_levels, model_levels, tol=0.5):
    """Pair nearest ref/model levels; flag deltas over TOL_DATUM_M and unmatched levels."""
    rows = []
    used = set()
    for rz, rw in ref_levels:
        best, bd = None, 1e9
        for j, (mz, mw) in enumerate(model_levels):
            if j in used:
                continue
            if abs(mz - rz) < bd:
                best, bd = j, abs(mz - rz)
        if best is not None and bd <= tol:
            used.add(best)
            rows.append({"ref": rz, "model": model_levels[best][0],
                         "delta_mm": round((model_levels[best][0] - rz) * 1000, 1),
                         "ok": bd <= TOL_DATUM_M})
        else:
            rows.append({"ref": rz, "model": None, "delta_mm": None, "ok": False,
                         "note": "missing in model"})
    for j, (mz, mw) in enumerate(model_levels):
        if j not in used:
            rows.append({"ref": None, "model": mz, "delta_mm": None, "ok": False,
                         "note": "extra in model"})
    return rows


def report(ref, model_objs):
    """Full numeric diff: bbox, Z-level pairing, wall extents, roof pitch + pass flags."""
    rmn, rmx = world_bbox([ref]); mmn, mmx = world_bbox(model_objs)
    rz = z_datums(ref); mz_objs = model_objs
    # union model levels across parts
    mvw = []
    for o in mz_objs:
        mvw += [(round(c.z, 4), a) for c, n, a in world_faces(o) if abs(n.z) > 0.9]
    mz = [(round(z, 3), round(w, 2)) for z, w in _cluster(mvw, TOL_DATUM_M) if w >= 0.4]
    rp = roof_pitch(ref, mat_filter="roof") or roof_pitch(ref)
    mp_num = mp_den = 0.0
    for o in mz_objs:
        for c, n, a in world_faces(o):
            if 0.1 < abs(n.z) < 0.95:
                mp_num += math.degrees(math.acos(min(1.0, abs(n.z)))) * a; mp_den += a
    mp = round(mp_num / mp_den, 2) if mp_den else None
    return {
        "bbox_delta_m": {"x": round((mmx.x - mmn.x) - (rmx.x - rmn.x), 3),
                         "y": round((mmx.y - mmn.y) - (rmx.y - rmn.y), 3),
                         "z": round((mmx.z - mmn.z) - (rmx.z - rmn.z), 3)},
        "z_levels": match_levels(rz, mz),
        "roof_pitch": {"ref": rp, "model": mp,
                       "ok": (rp is not None and mp is not None and abs(rp - mp) <= TOL_PITCH_DEG)},
        "tolerances": {"datum_m": TOL_DATUM_M, "pitch_deg": TOL_PITCH_DEG},
    }


# ----------------------------------------------------------------- overlay render
_OVL = "MTR_RefGhost"


def _ghost_mat(rgba):
    m = bpy.data.materials.get(_OVL) or bpy.data.materials.new(_OVL)
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission"); e.inputs[0].default_value = (*rgba[:3], 1)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader"); mix.inputs[0].default_value = rgba[3]
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(e.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    m.blend_method = 'BLEND'
    return m


def overlay_render(ref, model_objs, view, path, ortho_scale=None, rgba=(1.0, 0.12, 0.12, 0.5),
                   res=(1400, 1000)):
    """EEVEE ortho overlay: `ref` as a coloured ghost over the solid model.
    view in {'front','back','left','right','top','iso'}. Restores ref materials after."""
    mn, mx = world_bbox([ref] + list(model_objs))
    ctr = (mn + mx) / 2
    span = max((mx - mn).x, (mx - mn).y, (mx - mn).z)
    if ortho_scale is None:
        ortho_scale = span * 1.15
    dirs = {'front': (0, -1, 0), 'back': (0, 1, 0), 'left': (-1, 0, 0),
            'right': (1, 0, 0), 'top': (0, 0, 1), 'iso': (-0.8, -1, 0.6)}
    dv = Vector(dirs[view]).normalized()
    cam = bpy.data.objects.get("MTR_Cam")
    if cam is None:
        cam = bpy.data.objects.new("MTR_Cam", bpy.data.cameras.new("MTR_Cam"))
        bpy.context.scene.collection.objects.link(cam)
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = ortho_scale
    cam.location = ctr + dv * (span * 3)
    cam.rotation_euler = (Vector(ctr) - cam.location).to_track_quat("-Z", "Z" if view != 'top' else "Y").to_euler()
    bpy.context.scene.camera = cam

    # swap ref materials for the ghost
    saved = [m for m in ref.data.materials]
    ghost = _ghost_mat(rgba)
    ref.data.materials.clear(); ref.data.materials.append(ghost)
    ref.show_in_front = True

    scn = bpy.context.scene
    try:
        scn.render.engine = 'BLENDER_EEVEE_NEXT'
    except Exception:
        scn.render.engine = 'BLENDER_EEVEE'
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.render.film_transparent = False
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)  # poll the file from the host

    ref.data.materials.clear()
    for m in saved:
        ref.data.materials.append(m)
    return path
