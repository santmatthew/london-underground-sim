"""Character specification for the crowd-people pipeline.

Pure python (no bpy / numpy) so it can be imported both from Blender scripts
(make_people.py) and from the venv texture / manifest scripts.

Every character is one entry in SPECS.  Garments are (asset_folder, slot, colour_name|None)
where `slot` selects the atlas tile and the runtime tint channel:

  main   - one-piece outfit (suit, dress, casual-suit) -> own big tile, never recoloured
  top    - shirt / sweater / hoodie          tint channel R
  bottom - trousers / skirt                  tint channel G
  outer  - jacket / cardigan worn on top     tint channel B
  shoes  - shoes / boots                     no tint
  extra  - bag etc. (procedural)             no tint
  hat    - hats                              no tint
  glasses- goes into the face atlas
"""
import os

MPFB_DATA = "/home/msant/.config/blender/5.2/extensions/.user/user_default/mpfb/data"
PROJECT = "/home/msant/Projects/Personal/underground-sim"

# ------------------------------------------------------------------ palettes (sRGB 0..1)
HAIR_COLOURS = {
    "black": (0.07, 0.06, 0.06), "darkbrown": (0.13, 0.085, 0.06), "brown": (0.22, 0.13, 0.08),
    "lightbrown": (0.36, 0.24, 0.13), "auburn": (0.34, 0.12, 0.065), "ginger": (0.58, 0.24, 0.09),
    "blonde": (0.58, 0.43, 0.21), "dirtyblonde": (0.40, 0.30, 0.16), "grey": (0.50, 0.50, 0.50),
    "white": (0.80, 0.80, 0.78), "saltpepper": (0.32, 0.31, 0.30),
}
CLOTH_COLOURS = {
    "navy": (0.10, 0.14, 0.29), "charcoal": (0.20, 0.20, 0.22), "black": (0.10, 0.10, 0.11),
    "grey": (0.42, 0.42, 0.44), "lightgrey": (0.66, 0.66, 0.68), "white": (0.90, 0.90, 0.89),
    "cream": (0.82, 0.78, 0.66), "stone": (0.52, 0.46, 0.36), "olive": (0.30, 0.34, 0.16),
    "burgundy": (0.40, 0.09, 0.14), "red": (0.66, 0.11, 0.11), "mustard": (0.70, 0.52, 0.10),
    "teal": (0.07, 0.42, 0.44), "denim": (0.20, 0.30, 0.50), "lightblue": (0.58, 0.72, 0.90),
    "pink": (0.86, 0.60, 0.66), "green": (0.14, 0.46, 0.25), "brown": (0.34, 0.20, 0.11),
    "purple": (0.36, 0.16, 0.46), "camel": (0.62, 0.46, 0.26),
}
# palettes used by PersonModel for per-instance colour variation (weights favour dark/neutral)
PALETTES = {
    "suit":   [("charcoal", 4), ("navy", 4), ("black", 4), ("grey", 2)],
    "shirt":  [("white", 4), ("lightblue", 3), ("lightgrey", 2), ("pink", 1), ("navy", 1), ("black", 1)],
    "top":    [("black", 4), ("navy", 3), ("grey", 3), ("white", 2), ("olive", 1), ("burgundy", 1),
               ("mustard", 1), ("teal", 1), ("denim", 1), ("red", 1), ("green", 1), ("cream", 1)],
    "bottom": [("black", 5), ("charcoal", 4), ("navy", 3), ("denim", 3), ("grey", 2), ("stone", 2), ("olive", 1)],
    "outer":  [("black", 4), ("navy", 3), ("grey", 3), ("olive", 2), ("burgundy", 1), ("camel", 1)],
    "hair":   [("black", 5), ("darkbrown", 4), ("brown", 3), ("lightbrown", 2), ("auburn", 1), ("blonde", 2),
               ("grey", 1), ("ginger", 1)],
}

RACE = {  # (asian, caucasian, african)
    "cauc": (0.04, 0.92, 0.04), "afr": (0.04, 0.06, 0.90), "asian": (0.90, 0.07, 0.03),
    "sasian": (0.30, 0.58, 0.12), "mixed": (0.15, 0.45, 0.40), "mena": (0.10, 0.76, 0.14),
    "latin": (0.12, 0.62, 0.26), "eurasian": (0.45, 0.50, 0.05),
}

# skin tone multipliers (linear-ish, applied to the sRGB albedo in make_textures.py)
TONE_BROWN = (0.86, 0.72, 0.60)      # turns a light/bronze skin into a South-Asian brown
TONE_BROWN_D = (0.78, 0.62, 0.50)
TONE_TAN = (0.94, 0.86, 0.78)

# ------------------------------------------------------------------ atlas layouts
# tile = (u0, v0, su, sv)  in UV space (origin bottom-left)
LAYOUT_SPLIT = dict(size=(1024, 1024), tiles={
    "top": (0.0, 0.5, 0.5, 0.5), "bottom": (0.5, 0.5, 0.5, 0.5), "outer": (0.5, 0.0, 0.5, 0.5),
    "shoes": (0.0, 0.25, 0.25, 0.25), "extra": (0.25, 0.25, 0.25, 0.25), "hat": (0.0, 0.0, 0.25, 0.25),
    "spare": (0.25, 0.0, 0.25, 0.25)})
LAYOUT_MAIN = dict(size=(2048, 1024), tiles={
    "main": (0.0, 0.0, 0.5, 1.0), "outer": (0.5, 0.0, 0.25, 0.5), "shoes": (0.5, 0.5, 0.25, 0.5),
    "extra": (0.75, 0.5, 0.25, 0.5), "hat": (0.75, 0.0, 0.25, 0.5)})
FACE_ATLAS = dict(size=(512, 512), tiles={
    "eyes": (0.0, 0.5, 0.5, 0.5), "lashes": (0.5, 0.5, 0.5, 0.5),
    "brows": (0.0, 0.0, 0.5, 0.5), "glasses": (0.5, 0.0, 0.5, 0.5)})
# vertex colour tint channel for outfit slots
SLOT_CHANNEL = {"top": (1, 0, 0), "bottom": (0, 1, 0), "outer": (0, 0, 1), "main": (0, 0, 0),
                "shoes": (0, 0, 0), "extra": (0, 0, 0), "hat": (0, 0, 0)}
ROUGHNESS = {"top": 0.88, "bottom": 0.85, "outer": 0.85, "main": 0.75, "shoes": 0.45, "extra": 0.7, "hat": 0.8}


def layout_for(garments):
    return LAYOUT_MAIN if any(g[1] == "main" for g in garments) else LAYOUT_SPLIT


# ------------------------------------------------------------------ spec helper
def P(gender, age, height, weight, race, skin, hair, hair_col, garments, tone=None, muscle=0.5,
      eyes="brown", brows="eyebrow001", lashes="eyelashes01", glasses=None, bag=None, hat=None,
      outfit="casual", name="", proportions=0.5, heavy_decimate=None, cup=0.5):
    return dict(gender=gender, age=age, height=height, weight=weight, muscle=muscle, race=race,
                skin=skin, tone=tone, hair=hair, hair_col=hair_col, garments=garments, eyes=eyes,
                brows=brows, lashes=lashes, glasses=glasses, bag=bag, hat=hat, outfit=outfit,
                name=name, proportions=proportions, cup=cup)


M, F = 1.0, 0.0

SPECS = [
    # ---------------------------------------------------------------- men
    P(M, 27, 1.86, 0.45, "afr", "young_african_male", "short04", "black",
      [("mindfront_m_suit_01", "main", None), ("mindfront_shoes_oxford_male", "shoes", None)],
      eyes="brown", outfit="business", bag="briefcase", name="young black man, black suit"),
    P(M, 46, 1.80, 0.62, "cauc", "middleage_caucasian_male", "short03", "saltpepper",
      [("toigo_male_suit_3", "main", None), ("shoes03", "shoes", None)],
      eyes="blue", brows="eyebrow003", glasses="spamrakuen_tbm_glasses_frames_01", outfit="business",
      name="middle-aged white man, navy suit and glasses"),
    P(M, 34, 1.74, 0.45, "sasian", "toigo_light_skin_male_bronze", "short01", "black",
      [("elvs_male_shirt_tie_tucked1", "top", None), ("mindfront_male_trousers_1", "bottom", "charcoal"),
       ("shoes04", "shoes", None)], tone=TONE_BROWN, eyes="brown", outfit="business", bag="shoulder",
      name="south asian man, shirt and tie"),
    P(M, 22, 1.78, 0.42, "cauc", "young_caucasian_male", "short02", "brown",
      [("male_casualsuit03", "main", None), ("shoes05", "shoes", None)], eyes="green", outfit="casual",
      bag="backpack", name="young white man, checked shirt and jeans"),
    P(M, 19, 1.80, 0.40, "afr", "young_african_male", "afro01", "black",
      [("elvs_hooded_sweat_jacket1", "top", "charcoal"), ("punkduck_male_classic_jeans", "bottom", "black"),
       ("shoes06", "shoes", None)], eyes="brown", outfit="casual", bag="backpack", name="black teen, hoodie"),
    P(M, 58, 1.72, 0.66, "cauc", "middleage_caucasian_male", "short03", "grey",
      [("mindfront_knitted_sweater_02", "top", "burgundy"), ("elvs_male_trouser", "bottom", "charcoal"),
       ("shoes01", "shoes", None)], eyes="blue", glasses="kwnet_at_optical_glasses", outfit="casual",
      name="older white man, burgundy jumper"),
    P(M, 71, 1.70, 0.52, "cauc", "old_caucasian_male", "short04", "white",
      [("elvs_male_shirt_untucked_bd1", "top", "lightblue"), ("toigo_wool_pants", "bottom", "grey"),
       ("shoes01", "shoes", None)], eyes="blue", hat="fedora01", outfit="casual", name="elderly man in fedora"),
    P(M, 77, 1.65, 0.45, "asian", "old_asian_male", "short04", "grey",
      [("mindfront_knitted_sweater_01", "top", "grey"), ("mindfront_male_trousers_1", "bottom", "black"),
       ("shoes04", "shoes", None)], eyes="brown", glasses="spamrakuen_sagerfrogs_glasses_02", outfit="casual",
      name="elderly east asian man"),
    P(M, 29, 1.72, 0.38, "asian", "young_asian_male", "short01", "black",
      [("namuhekam_male_polo_shirt", "top", "navy"), ("elvs_jeans_straight_leg", "bottom", "denim"),
       ("shoes05", "shoes", None)], eyes="brown", outfit="casual", bag="backpack", name="east asian man, polo"),
    P(M, 41, 1.70, 0.66, "sasian", "toigo_light_skin_male_bronze", "short02", "black",
      [("male_casualsuit05", "main", None), ("shoes03", "shoes", None)], tone=TONE_BROWN_D, eyes="brown",
      outfit="casual", name="south asian man, puffer jacket"),
    P(M, 36, 1.82, 0.50, "cauc", "toigo_light_skin_male_ginger", "short02", "ginger",
      [("elvs_crude_t-shirt_male", "top", "olive"), ("elvs_male_trouser", "bottom", "charcoal"),
       ("punkduck_running_shoes_01", "shoes", None)], eyes="green", outfit="sport", muscle=0.62,
      name="ginger man, sporty"),
    P(M, 52, 1.78, 0.58, "afr", "middleage_african_male", "short04", "saltpepper",
      [("elvs_male_shirt_untucked_bd1", "top", "white"), ("mindfront_male_trousers_1", "bottom", "navy"),
       ("mindfront_shoes_oxford_male", "shoes", None)], eyes="brown", outfit="business_casual",
      bag="shoulder", name="middle-aged black man, shirt sleeves"),
    P(M, 31, 1.79, 0.48, "mena", "toigo_light_skin_male_bronze", "short03", "black",
      [("toigo_male_double-breasted_suit", "main", None), ("toigo_ankle_boots_male", "shoes", None)],
      tone=TONE_TAN, eyes="brown", outfit="business", name="middle-eastern man, double-breasted suit"),
    P(M, 24, 1.84, 0.32, "cauc", "toigo_light_skin_male_freckles", "cortu_short_messy_hair", "lightbrown",
      [("toigo_basic_tucked_t-shirt", "top", "grey"), ("elvs_jeans_bootcut", "bottom", "denim"),
       ("shoes06", "shoes", None)], eyes="blue", outfit="casual", name="thin young white man, tee"),
    P(M, 62, 1.68, 0.60, "sasian", "toigo_light_skin_male_bronze", "short04", "saltpepper",
      [("elvs_male_shirt_tie_tucked1", "top", None), ("toigo_wool_pants", "bottom", "stone"),
       ("shoes01", "shoes", None)], tone=TONE_BROWN, eyes="brown", glasses="kwnet_at_optical_glasses",
      outfit="business_casual", name="older south asian man"),
    P(M, 17, 1.74, 0.36, "cauc", "young_caucasian_male2", "short02", "darkbrown",
      [("elvs_hooded_sweat_jacket1", "top", "navy"), ("elvs_jeans_straight_leg", "bottom", "black"),
       ("shoes06", "shoes", None)], eyes="blue", outfit="casual", bag="backpack", name="white teenager, hoodie"),
    P(M, 48, 1.76, 0.72, "afr", "middleage_african_male", "short01", "black",
      [("toigo_male_suit_tie_and_jacket", "main", None), ("shoes03", "shoes", None)], eyes="brown",
      outfit="business", bag="briefcase", name="heavier black man, grey suit"),
    P(M, 33, 1.83, 0.52, "cauc", "young_caucasian_male", "short01", "dirtyblonde",
      [("male_casualsuit01", "main", None), ("mindfront_shoes_oxford_male", "shoes", None)], eyes="blue",
      muscle=0.68, outfit="business_casual", bag="shoulder", name="athletic white man, blue shirt"),
    # ---------------------------------------------------------------- women
    P(F, 26, 1.68, 0.42, "cauc", "young_caucasian_female", "ponytail01", "brown",
      [("female_elegantsuit01", "main", None), ("toigo_ballet_flats", "shoes", None)], eyes="brown",
      outfit="business", bag="handbag", name="young woman, striped blouse and skirt"),
    P(F, 38, 1.66, 0.50, "afr", "middleage_african_female", "punkduck_alpha7_curly", "black",
      [("toigo_female_double-breasted_suit", "main", None), ("toigo_ankle_boots_female", "shoes", None)],
      eyes="brown", glasses="spamrakuen_sagerfrogs_glasses_01", outfit="business", bag="tote",
      name="black woman, trouser suit"),
    P(F, 29, 1.60, 0.40, "sasian", "cutoff3d_indian_female_skin", "long01", "black",
      [("punkduck_sleeveless_shirt", "top", "teal"), ("toigo_wool_pants", "bottom", "charcoal"),
       ("toigo_ballet_flats", "shoes", None)], eyes="brown", outfit="business_casual", bag="shoulder",
      name="south asian woman, teal blouse"),
    P(F, 21, 1.58, 0.35, "asian", "young_asian_female", "o4saken_chinesebob01", "black",
      [("mindfront_knitted_sweater_02", "top", "mustard"), ("punkduck_female_tight_jeans", "bottom", "denim"),
       ("punkduck_comfortable_sneakers", "shoes", None)], eyes="brown", outfit="casual", bag="backpack",
      name="east asian student, mustard jumper"),
    P(F, 55, 1.65, 0.62, "cauc", "middleage_caucasian_female", "toigo_curled_under_bob", "saltpepper",
      [("toigo_fisherman_sweater", "top", "navy"), ("elvs_asymmetrical_skirt", "bottom", "black"),
       ("toigo_ballet_flats", "shoes", None)], eyes="blue", brows="eyebrow006",
      glasses="spamrakuen_sagerfrogs_glasses_03", outfit="casual", name="older white woman, navy jumper"),
    P(F, 73, 1.57, 0.48, "cauc", "old_caucasian_female", "elvs_50s_updo", "white",
      [("janexx_old_female_sweater", "top", "burgundy"), ("toigo_wool_pants", "bottom", "charcoal"),
       ("shoes03", "shoes", None)], eyes="blue", glasses="kwnet_at_optical_glasses", outfit="casual",
      bag="handbag", name="elderly white woman"),
    P(F, 34, 1.73, 0.44, "cauc", "toigo_light_skin_female_freckles", "toigo_blunt_bob", "blonde",
      [("joepal_crude_t-shirt_female", "top", "white"), ("mindfront_female_trousers_1", "bottom", "denim"),
       ("shoes06", "shoes", None)], eyes="green", outfit="casual", bag="backpack", name="blonde woman, tee and jeans"),
    P(F, 19, 1.63, 0.40, "cauc", "young_caucasian_female2", "braid01", "lightbrown",
      [("elvs_hooded_sweat_jacket1", "top", "grey"), ("punkduck_female_tight_jeans", "bottom", "black"),
       ("shoes05", "shoes", None)], eyes="blue", outfit="casual", name="young woman, grey hoodie"),
    P(F, 44, 1.64, 0.55, "eurasian", "onlytheghosts_middle_aged_eurasian_female", "elvs_wavy_bob", "black",
      [("toigo_shift_dress", "main", None), ("toigo_ballet_flats", "shoes", None)], eyes="brown",
      outfit="business", bag="handbag", name="eurasian woman, dark dress"),
    P(F, 64, 1.62, 0.58, "afr", "old_african_female", "elvs_short_daisy_hair", "grey",
      [("mindfront_knitted_sweater_01", "top", "olive"), ("toigo_wool_pants", "bottom", "black"),
       ("shoes04", "shoes", None)], eyes="brown", glasses="spamrakuen_sagerfrogs_glasses_04", outfit="casual",
      name="older black woman"),
    P(F, 31, 1.75, 0.42, "mena", "toigo_light_skin_female_bronze", "punkduck_alpha7_long", "black",
      [("punkduck_lace_up_blouse", "top", "white"), ("elvs_pencil_skirt", "bottom", "black"),
       ("toigo_ankle_boots_female", "shoes", None)], eyes="brown", outfit="business", bag="tote",
      name="tall woman, white blouse and pencil skirt"),
    P(F, 27, 1.59, 0.38, "asian", "young_asian_female", "ponytail01", "black",
      [("punkduck_v_neck_top", "top", "pink"), ("mindfront_female_trousers_1", "bottom", "black"),
       ("punkduck_comfortable_sneakers", "shoes", None)], eyes="brown", outfit="casual", name="east asian woman, pink top"),
    P(F, 49, 1.61, 0.56, "sasian", "cutoff3d_indian_female_skin", "long01", "saltpepper",
      [("toigo_fisherman_sweater", "top", "burgundy"), ("toigo_wool_pants", "bottom", "black"),
       ("mindfront_shoes_oxford_female", "shoes", None)], tone=(0.92, 0.85, 0.80), eyes="brown", outfit="casual",
      bag="shoulder", name="older south asian woman"),
    P(F, 17, 1.66, 0.42, "afr", "young_african_female", "o4saken_curly01", "black",
      [("elvs_hooded_sweat_jacket1", "top", "black"), ("punkduck_female_tight_jeans", "bottom", "denim"),
       ("shoes05", "shoes", None)], eyes="brown", outfit="casual", bag="backpack", name="black teen girl, hoodie"),
    P(F, 41, 1.66, 0.74, "cauc", "toigo_light_skin_female_ginger_2", "bob02", "auburn",
      [("mindfront_knitted_sweater_02", "top", "grey"), ("mindfront_female_trousers_1", "bottom", "black"),
       ("shoes03", "shoes", None)], eyes="green", outfit="casual", name="plus-size auburn woman"),
    P(F, 23, 1.64, 0.40, "latin", "callharvey3d_midtoned_female", "long01", "darkbrown",
      [("toigo_basic_tucked_t-shirt", "top", "olive"), ("punkduck_female_tight_jeans", "bottom", "black"),
       ("punkduck_running_shoes_01", "shoes", None)], eyes="brown", outfit="casual", bag="tote",
      name="young latina woman"),
    P(F, 57, 1.63, 0.54, "cauc", "middleage_caucasian_female", "elvs_short_side_do", "grey",
      [("elvs_lara_tank1", "top", "charcoal"), ("toigo_wool_pants", "bottom", "navy"),
       ("mindfront_shoes_oxford_female", "shoes", None)], eyes="blue", outfit="business_casual", bag="handbag",
      name="older white woman, grey bob"),
    P(F, 80, 1.52, 0.40, "asian", "old_asian_female", "rehmanpolanski_hair_bun_brown", "grey",
      [("mindfront_lusekofta", "top", "navy"), ("toigo_wool_pants", "bottom", "charcoal"),
       ("shoes04", "shoes", None)], eyes="brown", glasses="kwnet_at_optical_glasses", outfit="casual",
      name="elderly east asian woman, cardigan"),
]

for i, s in enumerate(SPECS):
    s["id"] = "person_%02d" % i
    s["index"] = i


def age_slider(years):
    """MakeHuman age slider: 0.1875 -> 11y, 0.5 -> 25y, 1.0 -> 90y"""
    if years >= 25:
        return 0.5 + (years - 25.0) / 65.0 * 0.5
    return 0.1875 + (years - 11.0) / 14.0 * 0.3125


def age_band(years):
    if years < 20:
        return "teen"
    if years < 30:
        return "20s"
    if years < 40:
        return "30s"
    if years < 50:
        return "40s"
    if years < 65:
        return "50s-60s"
    return "65+"


def height_slider(gender, race, target_h):
    """rough slider guess; the exact height is reached by a final uniform scale"""
    nominal = 1.604 + 0.141 * gender
    if race[0] > 0.5:
        nominal -= 0.09
    elif race[2] > 0.5:
        nominal += 0.055
    d = target_h - nominal
    return max(0.05, min(0.95, 0.5 + d / (1.37 if d > 0 else 0.7)))


# ------------------------------------------------------------------ asset lookup (pure python)
def find_clothes_dir(name):
    return os.path.join(MPFB_DATA, "clothes", name)


def parse_mhmat(path):
    d = {}
    for line in open(path, errors="ignore"):
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        parts = line.split(None, 1)
        if len(parts) == 2:
            d.setdefault(parts[0], parts[1].strip())
    return d


def parse_mhclo_material(mhclo):
    for line in open(mhclo, errors="ignore"):
        if line.startswith("material "):
            return line.split(None, 1)[1].strip()
    return None
