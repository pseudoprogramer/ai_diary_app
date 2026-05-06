# Harugyeol Local Image Generation Lab

This folder is for testing real generative image pipelines before moving one
into the mobile app. The Flutter app currently keeps image processing local,
but the embedded TFLite style-transfer model behaves more like a filter. Use
this lab on a Mac mini or desktop first to find a model, prompt, and parameter
set that actually redraws a diary scene.

There are now two experiment directions:

- `run_img2img.py`: generative img2img. More creative, but can drift away from the source photo.
- `run_brushify.py`: photo-trace brush conversion. Keeps the original composition recognizable.
- `run_composed_brush.py`: lightly recompose first, then apply a recognizable brush trace.
- `run_viewpoint_brush.py`: approximate a different camera viewpoint with a 2.5D depth warp, then apply brush trace.

## Goal

Input: one real diary photo.

Output: a newly generated pastel or brush-painting diary illustration that keeps
the memory and rough composition, but no longer looks like a plain photo filter.

## Setup on Mac mini

```bash
cd ai_diary_app/experiments/image_generation
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

For Apple Silicon, PyTorch should use `mps` automatically when available. The
script also enables MPS fallback for operators that are not fully supported.

## Quick Test

```bash
python run_img2img.py \
  --input ~/Desktop/cafe.jpg \
  --preset pastel_diary \
  --strength 0.62 \
  --steps 24 \
  --seed 7
```

Outputs are written to `outputs/`.

## Photo-Trace Brush Test

Use this when the result must still clearly read as the original photo:

```bash
python run_brushify.py \
  --input ~/Desktop/cafe.jpg \
  --preset opencv_oil_trace \
  --paper-border
```

Useful brush presets:

- `opencv_oil_trace`: best first candidate for a recognizable brush painting.
- `opencv_watercolor_trace`: softer, calmer, less chunky.
- `bold_oil_trace`: dependency-free fallback with stronger contrast.
- `recognizable_brush`: dependency-free fallback that stays closest to the photo.

## Hybrid Compose + Brush Test

Use this when plain brush conversion feels too close to the original photo, but
full img2img drifts too far away:

```bash
python run_composed_brush.py \
  --input ~/Desktop/cafe.jpg \
  --strength 0.42 \
  --steps 24 \
  --seed 91 \
  --brush-preset opencv_oil_trace \
  --paper-border \
  --keep-intermediate
```

Recommended tuning:

- Start with `--strength 0.35` to `0.45` for a small composition cleanup.
- Avoid `--strength 0.6+` unless you want a new scene instead of a memory.
- Keep the brush step conservative so the recomposed subject remains readable.

## Viewpoint + Brush Test

Use this when the goal is to feel like the same memory from a slightly different
camera angle. This is a 2.5D approximation, not a true 3D reconstruction, so it
works best as a subtle viewpoint nudge.

```bash
python run_viewpoint_brush.py \
  --input ~/Desktop/cafe.jpg \
  --viewpoint upper_right \
  --parallax 28 \
  --zoom 1.04 \
  --brush-preset opencv_oil_trace \
  --paper-border \
  --keep-intermediate
```

Recommended tuning:

- Start with `--parallax 20` to `35`.
- Use `left`, `right`, `upper_left`, or `upper_right` before trying stronger vertical shifts.
- If edges stretch or smear, lower `--parallax` before changing the brush preset.

## Useful Presets

- `pastel_diary`: soft pastel/gouache diary illustration.
- `watercolor`: lighter watercolor wash, calmer and less distorted.
- `gouache_clean`: stronger redraw with extra text/signature suppression.
- `watercolor_safe`: lower-risk fallback for photos with signs, books, menus, or other text-like areas.
- `vangogh`: stronger brush strokes and color movement.
- `storybook`: cute third-person storybook feeling.

## Tuning Notes

- Increase `--strength` if the result still looks like a filtered photo.
- Decrease `--strength` if faces, objects, or composition collapse.
- Try `0.55`, `0.62`, `0.72`, `0.82` as first checkpoints.
- Use the same `--seed` while comparing prompts.
- Use `--batch 4` to quickly compare variations.

## Good First Direction

For Harugyeol, start with:

```bash
python run_img2img.py --input ~/Desktop/cafe.jpg --preset pastel_diary --strength 0.72 --steps 28 --seed 11 --batch 4
```

If the output finally feels right, save the exact command and model name. That
combination becomes the target for Core ML or another mobile runtime later.

## First Test Notes

The first five real-photo tests showed:

- `pastel_diary --strength 0.72 --steps 18 --size 512` is fast and often good, but one cafe/table photo stayed too close to the original photo.
- `gouache_clean --strength 0.82 --steps 24 --size 512` is the best first candidate when the photo still looks like a filter.
- Strong redraws can invent fake text when the source image contains signs, books, menus, or paper.
- For text-heavy photos, try `watercolor_safe --strength 0.68 --steps 24 --size 512` before increasing strength.
- After the initial model download, 512px generation on Apple Silicon MPS took about 20-28 seconds per image in this lab.
