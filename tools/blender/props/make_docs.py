#!/usr/bin/env python3
"""Builds assets/models/props/props_manifest.json and README.md from the per-prop stats written by make_props.py
(build/props_scratch/stats/*.json) plus assets/textures/props/posters/poster_manifest.json.
run: python3 tools/blender/props/make_docs.py"""
import os, json, glob, datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
STAT = os.path.join(ROOT, 'build', 'props_scratch', 'stats')
OUT = os.path.join(ROOT, 'assets', 'models', 'props')
POSTERS = os.path.join(ROOT, 'assets', 'textures', 'props', 'posters', 'poster_manifest.json')

ORDER = ['gate_unit', 'gate_wide', 'gate_fence', 'ticket_machine', 'info_totem', 'journey_planner_screen', 'bench_platform', 'perch_seat',
         'bin', 'bin_recycling', 'help_point', 'fire_cabinet', 'cctv_dome', 'pa_speaker', 'clock', 'emergency_stop_plunger',
         'poster_frame_6sheet', 'poster_frame_4sheet', 'poster_frame_48sheet', 'vending_machine', 'newsstand_kiosk', 'barrier_stanchion',
         'wet_floor_sign', 'cleaning_trolley', 'lift_doors', 'signal_lamp', 'platform_edge_marker']

CONVENTIONS = {
    'units': 'metres', 'up_axis': '+Y', 'front': '-Z (Godot forward). Printed faces / screens / readers face -Z unless a prop says otherwise; '
             'gates: passengers walk toward -Z (entry end = +Z).',
    'origin_types': {
        'floor_centre': 'origin on the floor, centred on the footprint (x, z)',
        'wall_back_bottom_centre': 'wall-mounted: origin at the bottom-centre of the BACK plane (z=0 is the wall surface; the object extends toward -Z). '
                                   'Place it at wall_position + Vector3(0, mount_height, 0) (manifest key mount_height_m)',
        'mount_point': 'ceiling / wall bracket items: origin at the point where the object attaches (see origin_note); place at the mounting point',
        'floor_at_front_plane': 'lift: origin on the floor at the centre of the front fascia plane; the lift car extends toward +Z',
    },
    'collision': 'nodes named "*-convcolonly" are imported by Godot as StaticBody3D + convex CollisionShape3D (the visible mesh is removed).',
    'animated_nodes': 'animated nodes are separate MeshInstance3D nodes whose origin is the pivot. The open pose is stored both here and as glTF extras '
                      '(node.get_meta("extras")): open_rotation_y_deg / open_rotation_x_deg (degrees), open_offset ([x,y,z] metres), open_scale ([x,y,z]).',
    'materials': 'all materials are named mat_*; slots the game may retarget are listed per prop under material_slots. Emissive materials use '
                 'KHR_materials_emissive_strength (Godot emission_energy_multiplier).',
    'dirt': 'structural materials carry a baked dirt/grime gradient in vertex colour (COLOR_0, darker near the floor). Godot enables '
            'vertex_color_use_as_albedo on those materials automatically. Retargeted materials should keep that flag if the gradient is wanted.',
}

KNOWN = [
    'Ticket-gate flaps / wide-gate doors OPEN by swinging about their hinge (rotation.y +-90 deg): a 0.29 m glass panel cannot slide into a 0.16 m pedestal. '
    'A collapse alternative is provided as alt_open_scale (scale.x -> 0.04).',
    'Godot 4.7 ignores KHR_materials_anisotropy, so brushed steel is isotropic (streaks come from the roughness/normal maps only). If you want anisotropic '
    'highlights set BaseMaterial3D.anisotropy_enabled on materials named mat_steel at load time.',
    'Godot\'s glTF importer does not apply COLOR_0 (dirt gradient) to the first primitive of a mesh; the generator therefore keeps a non-dirty material (decal / '
    'glass / polished metal) in slot 0 whenever possible.',
    'Alpha-blended materials (glass, bin sacks, clock glass, cctv dome, thin poster glazing) are ordinary Godot transparent surfaces: mind sorting when '
    'stacking them behind other transparencies.',
    'Frames embed only a small placeholder picture; the 12 advert textures live in assets/textures/props/posters/ and must be assigned to mat_poster '
    'by the game (set albedo_texture and emission_texture).',
    'Each GLB embeds its own copy of the textures it uses (Godot does not de-duplicate across GLBs); texture memory figures below are per prop.',
    'Screens are emissive placeholder UIs (static images). Retarget mat_screen / mat_map_A/B / mat_vend_front etc. for dynamic content.',
]


def fmt(v):
    return ', '.join('%.3f' % x for x in v)


def main():
    stats = {}
    for f in glob.glob(os.path.join(STAT, '*.json')):
        s = json.load(open(f))
        stats[s['name']] = s
    names = [n for n in ORDER if n in stats] + sorted(n for n in stats if n not in ORDER)
    props = {}
    for n in names:
        s = stats[n]; info = s.get('info', {})
        props[n] = {
            'file': n + '.glb',
            'description': info.get('desc', ''),
            'size_m': {'x': s['size'][0], 'y': s['size'][1], 'z': s['size'][2]},
            'bbox_m': {'min': s['bbox_lo'], 'max': s['bbox_hi']},
            'origin': info.get('origin', 'floor_centre').split(' ')[0],
            'origin_note': info.get('origin_note', ''),
            'front': info.get('front', ''),
            'mount_height_m': info.get('mount_height', 0.0),
            'triangles': s['tris'],
            'triangles_by_node': s['parts'],
            'surfaces_draw_calls': s.get('surfaces', 0),
            'nodes': info.get('nodes', {}),
            'animation': s.get('anim', {}),
            'material_slots': info.get('slots', {}),
            'materials': s['materials'],
            'collision_nodes': s.get('collision', []),
            'textures_embedded': s.get('textures', {}),
            'texture_vram_mb_est': s.get('texture_vram_mb', 0),
            'glb_kb': s.get('glb_kb', 0),
            'notes': info.get('notes', []),
        }
    posters = json.load(open(POSTERS)) if os.path.exists(POSTERS) else []
    tot_tris = sum(p['triangles'] for p in props.values())
    per_prop_vram = sum(p['texture_vram_mb_est'] for p in props.values())
    uniq = {}
    for p in props.values():
        for k, wh in p['textures_embedded'].items():
            uniq[k] = wh
    uniq_vram = sum(w * h * 1.33 for w, h in uniq.values()) / 1048576.0
    manifest = {'generated': datetime.date.today().isoformat(), 'generator': 'tools/blender/props/make_props.py', 'conventions': CONVENTIONS,
                'summary': {'props': len(props), 'total_triangles_all_props': tot_tris, 'max_triangles': max(p['triangles'] for p in props.values()),
                            'texture_vram_mb_sum_of_per_prop_copies': round(per_prop_vram, 1),
                            'texture_vram_mb_if_textures_were_shared': round(uniq_vram, 1),
                            'glb_total_mb': round(sum(p['glb_kb'] for p in props.values()) / 1024.0, 1)},
                'known_issues': KNOWN, 'props': props, 'posters': posters}
    json.dump(manifest, open(os.path.join(OUT, 'props_manifest.json'), 'w'), indent=1)

    L = []
    A = L.append
    A('# Station props (`assets/models/props/`)')
    A('')
    A('Procedural, Blender-generated GLB props for stations: gates, machines, furniture, wall/ceiling fixtures, advert frames, retail. '
      'Generator: `tools/blender/props/make_props.py` (see "Regenerating"). Machine-readable twin of this file: `props_manifest.json`.')
    A('')
    A('## Conventions')
    A('')
    A('* Units metres, +Y up, glTF exported with `export_yup`. **Front = -Z** (Godot forward). Screens, prints, readers face -Z unless stated. '
      'Ticket gates: passengers walk toward -Z (entry end = +Z, where readers/lamps/end-wraps face).')
    A('* Origins (manifest key `origin`):')
    for k, v in CONVENTIONS['origin_types'].items():
        A('  * `%s` - %s' % (k, v))
    A('* Collision: nodes named `*-convcolonly` become `StaticBody3D` + convex shape at import (visible mesh removed). Small wall items have none.')
    A('* Animated parts are separate nodes whose origin is the pivot; the open pose is documented per prop and stored as glTF extras '
      '(`node.get_meta("extras")` -> `open_rotation_y_deg`, `open_rotation_x_deg`, `open_offset`, `open_scale`).')
    A('* Materials are named `mat_*`. Slots the game may retarget are listed per prop. Emissive = `KHR_materials_emissive_strength` (Godot `emission_energy_multiplier`).')
    A('* Wear: brushed steel / charcoal / paint / timber / rubber PBR tiles (512 px, generated) + a baked dirt gradient in vertex colour (darker near the floor). '
      'Textures are embedded (<= 1K: tiles 256-512, decals 128-1024).')
    A('* Wall props: `mount_height_m` is the recommended height of the origin above the floor.')
    A('')
    A('## Props')
    for n in names:
        p = props[n]
        A('')
        A('### `%s.glb`' % n)
        A(p['description'])
        A('')
        A('* size (x, y, z): **%.2f x %.2f x %.2f m**; triangles **%d**; draw surfaces %d; GLB %.0f KB; embedded texture VRAM ~%.1f MB (est., BC7 + mips)' % (
            p['size_m']['x'], p['size_m']['y'], p['size_m']['z'], p['triangles'], p['surfaces_draw_calls'], p['glb_kb'], p['texture_vram_mb_est']))
        oline = '* origin: `%s`' % p['origin']
        if p['origin_note']:
            oline += ' (%s)' % p['origin_note']
        if p['mount_height_m']:
            oline += '; mount height %.2f m' % p['mount_height_m']
        A(oline + '; front: %s' % p['front'])
        A('* nodes:')
        for k, v in p['nodes'].items():
            tri = p['triangles_by_node'].get(k)
            A('  * `%s`%s - %s' % (k, ' (%d tris)' % tri if tri is not None else '', v))
        if p['animation']:
            A('* animation / open poses: `%s`' % json.dumps(p['animation']))
        if p['material_slots']:
            A('* retargetable material slots:')
            for k, v in p['material_slots'].items():
                A('  * `%s` - %s' % (k, v))
        A('* all materials: %s' % ', '.join('`%s`' % m for m in p['materials']))
        for note in p['notes']:
            A('* note: ' + note)
    A('')
    A('## Advert posters (`assets/textures/props/posters/`)')
    A('')
    A('12 invented brands (no real artwork/logos), flat-graphic style with legible text, plus `poster_manifest.json`. Portrait posters (1024 x 1536, 2:3) fit '
      '`poster_frame_6sheet` / `poster_frame_4sheet`; landscape posters (2048 x 1024, 2:1) fit `poster_frame_48sheet`. Assign to the frame\'s `mat_poster` '
      '(albedo + emission texture).')
    A('')
    A('| file | orientation | size | brand |')
    A('|---|---|---|---|')
    for p in posters:
        A('| `%s` | %s | %d x %d | %s |' % (p['file'], p['orientation'], p['width'], p['height'], p['brand']))
    A('')
    A('## Performance summary')
    A('')
    A('* %d props, %d triangles in total (largest prop %d tris; budget was ~10k). Typical prop: 1 - 5 draw surfaces per mesh group, 4 - 15 in total.' % (
        len(props), tot_tris, max(p['triangles'] for p in props.values())))
    A('* Texture memory (est. VRAM with BC7 + mipmaps): per prop 0.3 - 5 MB (list above); all 27 props loaded at once with each GLB\'s private copies = '
      '~%.0f MB, or ~%.0f MB if the shared tiles were de-duplicated by the game. Tiling sets are 512 px (paints 256 px), decals <= 1024 px.' % (per_prop_vram, uniq_vram))
    A('* The 12 poster PNGs (1 - 2 K) add ~%.0f MB VRAM if all are loaded at once (load per station instead).' % (
        (8 * 1024 * 1536 + 4 * 2048 * 1024) * 1.33 / 1048576.0))
    A('')
    A('## Known issues / notes')
    A('')
    for k in KNOWN:
        A('* ' + k)
    A('')
    A('## Regenerating')
    A('')
    A('```')
    A('build/venv/bin/python tools/blender/props/proptex_tiles.py      # tiling PBR sets -> assets/textures/props/tile')
    A('build/venv/bin/python tools/blender/props/proptex_decals.py     # printed / screen decals -> assets/textures/props/decals')
    A('build/venv/bin/python tools/blender/props/posters.py            # 12 poster textures -> assets/textures/props/posters')
    A('blender -b --factory-startup -P tools/blender/props/make_props.py -- [prop names]   # GLBs -> assets/models/props (no names = all)')
    A('python3 tools/blender/props/make_docs.py                       # this README + props_manifest.json')
    A('```')
    open(os.path.join(OUT, 'README.md'), 'w').write('\n'.join(L) + '\n')
    print('wrote README.md and props_manifest.json; %d props, %d tris, per-prop tex %.1f MB' % (len(props), tot_tris, per_prop_vram))


if __name__ == '__main__':
    main()
