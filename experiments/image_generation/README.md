# Harugyeol Local Image Generation Lab

This folder is for testing real generative image pipelines before moving one
into the mobile app. The Flutter app currently keeps image processing local,
but the embedded TFLite style-transfer model behaves more like a filter. Use
this lab on a Mac mini or desktop first to find a model, prompt, and parameter
set that actually redraws a diary scene.

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

## Useful Presets

- `pastel_diary`: soft pastel/gouache diary illustration.
- `watercolor`: lighter watercolor wash, calmer and less distorted.
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

