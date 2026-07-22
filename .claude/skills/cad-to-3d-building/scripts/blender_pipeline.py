"""Verified bpy helpers for the CAD→3D building pipeline.

Run inside Blender (paste into `execute_blender_code` via the Blender MCP, or
`blender --background --python blender_pipeline.py`). Every function here was used to
build the worked sample (`assets/RoxSlice_sample.blend`). They are headless-safe — they
avoid `bpy.ops` calls that need a 3D-view context (e.g. `uv.cube_project`).

Conventions: metres; front face at Y=0, wall thickness into +Y; parts parented to a
`Move` empty; `<unit>_<floor>_<type>_<index>` names.
"""
import bpy, bmesh, json, math, os
from mathutils import Vector


# ---------------------------------------------------------------- scene helpers
def new_collection(name, clear=True):
    c = bpy.data.collections.get(name)
    if c and clear:
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c); c = None
    if not c:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def parent_empty(name, coll):
    e = bpy.data.objects.get(name) or bpy.data.objects.new(name, None)
    if name not in [o.name for o in coll.objects]:
        coll.objects.link(e)
    e.empty_display_size = 0.5
    return e


# ---------------------------------------------------------------- geometry
def make_box(name, x0, x1, y0, y1, z0, z1, coll, parent=None):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    cs = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
          (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    vs = [bm.verts.new(c) for c in cs]
    for f in [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4),
              (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
        bm.faces.new([vs[i] for i in f])
    # consistent OUTWARD normals — critical: inconsistent normals make an EXACT
    # Boolean DIFFERENCE behave like INTERSECTION and destroy the target mesh.
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update(); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); coll.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


def bool_diff(target, cutters):
    for cut in cutters:
        m = target.modifiers.new("b", "BOOLEAN")
        m.operation = "DIFFERENCE"; m.solver = "EXACT"; m.object = cut
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = target
        bpy.ops.object.modifier_apply(modifier=m.name)
    for cut in cutters:
        bpy.data.objects.remove(cut, do_unlink=True)


def make_window(tag, x0, x1, z0, z1, coll, parent, frame_mat, glass_mat):
    """frame (4 jambs) + mullion cross + recessed glass. Returns (frame, glass)."""
    fr, fd0, fd1, mw = 0.09, 0.04, 0.18, 0.04
    parts = [
        make_box(tag + "_fb", x0, x1, fd0, fd1, z0, z0 + fr, coll, parent),
        make_box(tag + "_ft", x0, x1, fd0, fd1, z1 - fr, z1, coll, parent),
        make_box(tag + "_fl", x0, x0 + fr, fd0, fd1, z0, z1, coll, parent),
        make_box(tag + "_fr", x1 - fr, x1, fd0, fd1, z0, z1, coll, parent),
    ]
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    parts.append(make_box(tag + "_mv", cx - mw, cx + mw, fd0, fd1 - 0.02, z0 + fr, z1 - fr, coll, parent))
    parts.append(make_box(tag + "_mh", x0 + fr, x1 - fr, fd0, fd1 - 0.02, cz - mw, cz + mw, coll, parent))
    glass = make_box(tag + "_glass", x0 + fr, x1 - fr, 0.12, 0.13, z0 + fr, z1 - fr, coll, parent)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    frame = bpy.context.view_layer.objects.active
    frame.name = tag + "_frame"
    frame.data.materials.clear(); frame.data.materials.append(frame_mat)
    glass.data.materials.clear(); glass.data.materials.append(glass_mat)
    return frame, glass


def build_backdrop(json_path, coll, offx=0.0):
    """Edge mesh from dxf_extract.py JSON, converted to a beveled curve so it renders."""
    d = json.load(open(json_path)); segs, w = d["segments"], d["w"]
    verts, edges = [], []
    def vid(x, z):
        verts.append((x - w / 2 + offx, 0.0, z)); return len(verts) - 1
    for x1, y1, x2, y2 in segs:
        edges.append((vid(x1, y1), vid(x2, y2)))
    me = bpy.data.meshes.new("Blueprint"); me.from_pydata(verts, edges, []); me.update()
    ob = bpy.data.objects.new("Blueprint", me); coll.objects.link(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="CURVE")
    ob.data.bevel_depth = 0.03; ob.show_in_front = True
    return ob


# ---------------------------------------------------------------- materials
def _img(path, noncolor=False):
    im = bpy.data.images.get(os.path.basename(path)) or bpy.data.images.load(path)
    im.colorspace_settings.name = "Non-Color" if noncolor else "sRGB"
    return im


def pbr_material(name, albedo=None, normal=None, rough=None, tint=None,
                 base_rgb=None, rough_val=0.7):
    """Principled BSDF. Normal/Rough loaded as Non-Color. UV-mapped (exports to glTF)."""
    m = bpy.data.materials.get(name)
    if m:
        bpy.data.materials.remove(m)
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (400, 0)
    nt.links.new(b.outputs[0], out.inputs[0])
    if base_rgb:
        b.inputs["Base Color"].default_value = (*base_rgb, 1)
    b.inputs["Roughness"].default_value = rough_val
    if albedo:
        ta = nt.nodes.new("ShaderNodeTexImage"); ta.image = _img(albedo); ta.extension = "REPEAT"
        if tint:
            mix = nt.nodes.new("ShaderNodeMixRGB"); mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.0; mix.inputs[2].default_value = (*tint, 1)
            nt.links.new(ta.outputs[0], mix.inputs[1]); nt.links.new(mix.outputs[0], b.inputs["Base Color"])
        else:
            nt.links.new(ta.outputs[0], b.inputs["Base Color"])
    if rough:
        tr = nt.nodes.new("ShaderNodeTexImage"); tr.image = _img(rough, True); tr.extension = "REPEAT"
        nt.links.new(tr.outputs[0], b.inputs["Roughness"])
    if normal:
        tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = _img(normal, True); tn.extension = "REPEAT"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn.outputs[0], nm.inputs["Color"]); nt.links.new(nm.outputs[0], b.inputs["Normal"])
    return m


def glass_material(name="MAT_Glass"):
    m = pbr_material(name, base_rgb=(0.03, 0.05, 0.07), rough_val=0.04)
    b = m.node_tree.nodes["Principled BSDF"]
    try:
        b.inputs["IOR"].default_value = 1.45
    except Exception:
        pass
    return m


def box_uv(ob, tile):
    """Headless real-world box UV: per face, project onto the two axes != dominant normal.
    Gives exportable UVs that tile every `tile` metres. Replaces uv.cube_project."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvl = me.uv_layers.active.data; mw = ob.matrix_world
    for poly in me.polygons:
        ax = max(range(3), key=lambda i: abs(poly.normal[i]))
        for li in poly.loop_indices:
            co = mw @ me.vertices[me.loops[li].vertex_index].co
            u, v = ((co.y, co.z), (co.x, co.z), (co.x, co.y))[ax]
            uvl[li].uv = (u / tile, v / tile)


# ---------------------------------------------------------------- look / world
def sky_world(elevation=0.62, rotation=2.4, strength=0.85):
    w = bpy.context.scene.world; w.use_nodes = True; nt = w.node_tree; nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"   # 5.x renamed Nishita
    sky.sun_elevation = elevation; sky.sun_rotation = rotation
    bg = nt.nodes.new("ShaderNodeBackground"); bg.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs[0], bg.inputs[0]); nt.links.new(bg.outputs[0], out.inputs[0])


def sun(name="MCP_Sun", energy=2.4, elevation=0.7, azimuth=2.1):
    o = bpy.data.objects.get(name)
    if not o:
        d = bpy.data.lights.new(name, "SUN"); o = bpy.data.objects.new(name, d)
        bpy.context.scene.collection.objects.link(o)
    o.data.energy = energy; o.data.angle = 0.02
    o.rotation_euler = (math.pi / 2 - elevation, 0.0, azimuth)
    return o


def render_to(path, loc, target, rx=1000, ry=1150, samples=64, exposure=-2.2):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"; scn.cycles.samples = samples; scn.cycles.use_denoising = True
    vt = [v.identifier for v in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items]
    scn.view_settings.view_transform = "AgX" if "AgX" in vt else "Filmic"
    scn.view_settings.exposure = exposure
    cam = bpy.data.objects.get("Cam") or bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    if "Cam" not in [o.name for o in scn.collection.objects]:
        scn.collection.objects.link(cam)
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    scn.render.resolution_x = rx; scn.render.resolution_y = ry; scn.render.filepath = path
    bpy.ops.render.render(write_still=True)   # NB: poll the file from the host; renders outlast MCP timeouts


# ---------------------------------------------------------------- export
def bake_albedo(ob, out_png, size=512):
    """Bake a procedural/box material's colour to a UV image so it survives glTF export."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvl = me.uv_layers.active.data; mw = ob.matrix_world
    xs = [(mw @ v.co).x for v in me.vertices]; zs = [(mw @ v.co).z for v in me.vertices]
    minx, maxx, minz, maxz = min(xs), max(xs), min(zs), max(zs)
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = mw @ me.vertices[me.loops[li].vertex_index].co
            uvl[li].uv = ((co.x - minx) / (maxx - minx), (co.z - minz) / (maxz - minz))
    mat = ob.data.materials[0]; nt = mat.node_tree
    im = bpy.data.images.new(os.path.basename(out_png), size, size)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = im
    for n in nt.nodes:
        n.select = False
    tex.select = True; nt.nodes.active = tex
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.context.scene.render.engine = "CYCLES"; bpy.context.scene.cycles.samples = 8
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True, margin=6)
    im.filepath_raw = out_png; im.file_format = "PNG"; im.save()
    b = nt.nodes["Principled BSDF"]
    for l in list(nt.links):
        if l.to_node == b and l.to_socket.name == "Base Color":
            nt.links.remove(l)
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    return im


def export_glb(coll_name, out_glb, max_tex=1024):
    """Triangulate-on-export, +Y up, downscale textures, export the building collection."""
    scn = bpy.context.scene; col = bpy.data.collections.get(coll_name)
    for o in col.objects:
        if o.type == "MESH" and not any(m.type == "TRIANGULATE" for m in o.modifiers):
            o.modifiers.new("tri", "TRIANGULATE").min_vertices = 4
    used = {n.image for o in col.objects if o.type == "MESH"
            for m in o.data.materials if m and m.use_nodes
            for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}
    for im in used:
        w, h = im.size
        if max(w, h) > max_tex:
            f = max_tex / max(w, h); im.scale(int(w * f), int(h * f))
    bpy.ops.object.select_all(action="DESELECT")
    for o in col.objects:
        o.hide_set(False); o.select_set(True)
    bpy.context.view_layer.objects.active = col.objects[0]
    bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_materials="EXPORT",
                              export_image_format="AUTO", export_texcoords=True, export_normals=True)
    return os.path.getsize(out_glb)


def validate_glb(out_glb):
    """Re-import into a temp collection; return counts + bbox; then clean up."""
    scn = bpy.context.scene; vl = bpy.context.view_layer
    tmp = bpy.data.collections.new("VALIDATE"); scn.collection.children.link(tmp)
    vl.active_layer_collection = vl.layer_collection.children["VALIDATE"]
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=out_glb)
    new = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - before]
    meshes = [o for o in new if o.type == "MESH"]
    mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
    res = {"meshes": len(meshes), "dims_m": [round(mx[i] - mn[i], 3) for i in range(3)]}
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(tmp)
    return res
