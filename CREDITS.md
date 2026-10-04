# Credits
- Network, line and station data: TfL Open Data (Unified API), Open Government Licence v3.
- PBR textures: ambientCG.com (CC0).
- Characters: MakeHuman / MPFB (CC0 and CC-BY asset packs; per-asset attribution in `assets/people/CREDITS.txt` once generated).
- Motion capture: CMU Graphics Lab Motion Capture Database (free for all uses).
- Fonts: Hammersmith One, Barlow, Doto, Libre Baskerville, DotGothic16 — SIL Open Font License (Google Fonts).
- Reference photographs (not shipped) from Wikimedia Commons were used to calibrate the look of stations and signage.

## CC-BY character assets (MakeHuman community packs) — attribution
Licensed CC-BY (attribution required); source: makehumancommunity.org asset packs (shirts02/03, pants02, shoes02, skirts02, suits03, hair02/03, equipment02, glasses02).

- **Elvaerwyn**: elvs_50s_updo, elvs_asymmetrical_skirt, elvs_hooded_sweat_jacket1, elvs_jeans_bootcut, elvs_jeans_straight_leg, elvs_lara_tank1, elvs_male_shirt_tie_tucked1, elvs_male_shirt_untucked_bd1, elvs_male_trouser, elvs_pencil_skirt, elvs_short_daisy_hair, elvs_short_side_do, elvs_wavy_bob
- **Mindfront**: mindfront_female_trousers_1, mindfront_knitted_sweater_01, mindfront_knitted_sweater_02, mindfront_lusekofta, mindfront_m_suit_01, mindfront_male_trousers_1, mindfront_shoes_oxford_female, mindfront_shoes_oxford_male
- **janexx**: janexx_old_female_sweater
- **punkduck**: o4saken_chinesebob01, o4saken_curly01, punkduck_alpha7_curly, punkduck_alpha7_long, punkduck_comfortable_sneakers, punkduck_female_tight_jeans, punkduck_lace_up_blouse, punkduck_male_classic_jeans, punkduck_running_shoes_01, punkduck_sleeveless_shirt, punkduck_v_neck_top

Full per-asset list with links is generated to `assets/people/CREDITS.txt` by `tools/blender/people/make_credits.py`.

## Real-station data
- `data/stations_real.json`: entrances/exits, platform outlines, stairs/escalators and corridors near each station come from **OpenStreetMap** (© OpenStreetMap contributors, ODbL, https://www.openstreetmap.org/copyright) via the Geofabrik Greater London extract; gate/escalator/ticket-hall counts come from the TfL Unified API (Open Government Licence v3).
- `data/line_geometry.json`: the heading of the track between stations and the curvature of each platform, derived from the track geometry of the London Underground and Elizabeth line route relations in **OpenStreetMap** (© OpenStreetMap contributors, ODbL); only the derived numbers are stored (`tools/build_line_geometry.py`). The same file says, for each hop, which stretches run in tunnel, in a cutting, on an embankment or a viaduct, or in the open - from the `tunnel`, `cutting`, `embankment` and `bridge` tags of the railway ways of Greater London in OpenStreetMap (`tools/fetch_line_sections.py`) - and the hops of the Elizabeth line that its route relation lacks (the core tunnels, the Heathrow branch) were found over that line's own ways.
- `data/elizabeth_depths.json`: platform depths of the Elizabeth line stations, from the numbers in MichalPaszkiewicz/tubedepths (`data/platformdepths.js`, which adds the Elizabeth line to the TfL FOI depth table), rounded to whole metres. Only the numbers are used.
- `data/platform_numbers.json`: platform numbers per line and direction, sampled from TfL live arrivals (OGL v3).
- `data/station_layouts.json`: platform depths (metres below street level) read from TfL's official station layout diagrams released under a Freedom of Information request (2015). The drawings are TfL copyright and are **not** included in this repository; only the depth figures are recorded.

## Other
- Speech: synthesised with Piper TTS (rhasspy/piper-voices). Female PA voice `en_GB-cori-high`; male driver voice `en_GB-vctk-medium` (speaker p243), trained on the CSTR VCTK Corpus, © University of Edinburgh, licensed CC-BY 4.0 (https://datashare.ed.ac.uk/handle/10283/3443). Speech quality was screened with OpenAI Whisper (`tools/audio/asr_check.py`).
- All other audio (ambience, train/door/gate/footstep sounds, chimes) is synthesised procedurally by `tools/audio/make_audio.py`.
- Wikimedia Commons reference photographs were only viewed for calibration; none are shipped.
