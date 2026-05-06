import argparse
import os
from datetime import datetime
from pathlib import Path

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

import torch
from diffusers import StableDiffusionImg2ImgPipeline
from PIL import Image, ImageOps

from run_brushify import PRESETS as BRUSH_PRESETS
from run_brushify import add_paper_border, apply_brushify
from run_img2img import pick_device


DEFAULT_PROMPT = (
    "same real daily memory, preserve the main people, objects, cafe table, "
    "flowers, cups, food, and recognizable place, slightly cleaner composition, "
    "tidier framing, warmer natural light, subtle depth, realistic proportions, "
    "no new people, no text changes, no fantasy"
)

DEFAULT_NEGATIVE = (
    "different scene, changed identity, new person, missing main subject, "
    "distorted face, distorted hands, fake text, gibberish text, watermark, "
    "logo, neon, oversaturated, dark, scary, abstract, low quality"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate a lightly recomposed photo from a source image, then apply "
            "a recognizable brush trace."
        )
    )
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-dir", default="outputs/composed_brush")
    parser.add_argument("--model-id", default="runwayml/stable-diffusion-v1-5")
    parser.add_argument("--prompt", default=DEFAULT_PROMPT)
    parser.add_argument("--negative-prompt", default=DEFAULT_NEGATIVE)
    parser.add_argument("--strength", type=float, default=0.42)
    parser.add_argument("--guidance-scale", type=float, default=6.0)
    parser.add_argument("--steps", type=int, default=24)
    parser.add_argument("--seed", type=int, default=91)
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument(
        "--brush-preset",
        choices=sorted(BRUSH_PRESETS),
        default="opencv_oil_trace",
    )
    parser.add_argument("--paper-border", action="store_true")
    parser.add_argument(
        "--keep-intermediate",
        action="store_true",
        help="Save the recomposed image before brush conversion.",
    )
    return parser.parse_args()


def prepare_image(path: str, size: int) -> Image.Image:
    image = Image.open(path)
    image = ImageOps.exif_transpose(image).convert("RGB")
    image.thumbnail((size, size), Image.Resampling.LANCZOS)

    canvas = Image.new("RGB", (size, size), (246, 241, 232))
    x = (size - image.width) // 2
    y = (size - image.height) // 2
    canvas.paste(image, (x, y))
    return canvas


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    device, dtype = pick_device()
    print(f"Loading model: {args.model_id}")
    print(f"Device: {device}, dtype: {dtype}")

    pipe = StableDiffusionImg2ImgPipeline.from_pretrained(
        args.model_id,
        torch_dtype=dtype,
        safety_checker=None,
        requires_safety_checker=False,
    )
    pipe = pipe.to(device)
    if device != "cpu":
        pipe.enable_attention_slicing()

    init_image = prepare_image(args.input, args.size)
    generator_device = "cuda" if device == "cuda" else "cpu"
    generator = torch.Generator(device=generator_device).manual_seed(args.seed)

    recomposed = pipe(
        prompt=args.prompt,
        negative_prompt=args.negative_prompt,
        image=init_image,
        strength=args.strength,
        guidance_scale=args.guidance_scale,
        num_inference_steps=args.steps,
        generator=generator,
    ).images[0]

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = Path(args.input).stem[:8]
    if args.keep_intermediate:
        intermediate = output_dir / f"{timestamp}_{stem}_recomposed_seed{args.seed}.png"
        recomposed.save(intermediate)
        print(f"Saved intermediate: {intermediate}")

    brush = apply_brushify(recomposed, BRUSH_PRESETS[args.brush_preset], args.seed)
    if args.paper_border:
        brush = add_paper_border(brush, args.seed)

    output = output_dir / (
        f"{timestamp}_{stem}_composed_{args.brush_preset}_"
        f"s{args.strength}_seed{args.seed}.png"
    )
    brush.save(output)
    print(f"Saved: {output}")


if __name__ == "__main__":
    main()
