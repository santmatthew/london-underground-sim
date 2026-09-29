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

## Other
- Speech: synthesised with Piper TTS (rhasspy/piper-voices). Female PA voice `en_GB-cori-high`; male driver voice `en_GB-vctk-medium` (speaker p243), trained on the CSTR VCTK Corpus, © University of Edinburgh, licensed CC-BY 4.0 (https://datashare.ed.ac.uk/handle/10283/3443). Speech quality was screened with OpenAI Whisper (`tools/audio/asr_check.py`).
- All other audio (ambience, train/door/gate/footstep sounds, chimes) is synthesised procedurally by `tools/audio/make_audio.py`.
- Wikimedia Commons reference photographs were only viewed for calibration; none are shipped.
