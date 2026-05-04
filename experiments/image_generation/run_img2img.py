import argparse
import os
from datetime import datetime
from pathlib import Path

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

import torch
from diffusers import StableDiffusionImg2ImgPipeline
from PIL import Image, ImageOps


PRESETS = {
    "pastel_diary": {
        "prompt": (
            "soft pastel gouache diary illustration, warm cozy cafe memory, "
            "gentle hand drawn brush strokes, simplified shapes, soft cream "
            "paper texture, calm emotional daily life scene, beautiful color "
            "harmony, not photorealistic, no text"
        ),
        "negative": (
            "photorealistic, photo filter, harsh contrast, neon, cyberpunk, "
            "distorted hands, distorted face, scary, uncanny, text, watermark, "
            "logo, low quality, blurry"
        ),
    },
    "watercolor": {
        "prompt": (
            "delicate watercolor diary illustration, soft pastel palette, "
            "light paper grain, airy brush wash, peaceful daily memory, "
            "gentle edges, cozy mood, not photorealistic, no text"
        ),
        "negative": (
            "photorealistic, heavy filter, over saturated, neon, dark, scary, "
            "distorted anatomy, text, watermark, logo, low quality"
        ),
    },
    "vangogh": {
        "prompt": (
            "expressive post impressionist oil painting diary illustration, "
            "visible swirling brush strokes, thick impasto texture, warm light, "
            "vivid but tasteful colors, emotional daily memory, no text"
        ),
        "negative": (
            "photorealistic, plain photo filter, flat blur, neon artifacts, "
            "distorted hands, distorted face, scary, text, watermark, logo"
        ),
    },
    "storybook": {
        "prompt": (
            "charming third person storybook illustration of a daily memory, "
            "soft pastel colors, cozy cafe table, gentle character feeling, "
            "rounded simple shapes, warm light, hand painted, no text"
        ),
        "negative": (
            "photorealistic, realistic face, uncanny, horror, harsh contrast, "
            "text, watermark, logo, low quality, distorted hands"
        ),
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run local Stable Diffusion img2img experiments for Harugyeol."
    )
    parser.add_argument("--input", required=True, help="Path to the source photo.")
    parser.add_argument("--output-dir", default="outputs", help="Where images are saved.")
    parser.add_argument(
        "--model-id",
        default="runwayml/stable-diffusion-v1-5",
        help="Hugging Face model id. Try dreamlike-art/dreamlike-photoreal-2.0 or a local path too.",
    )
    parser.add_argument(
        "--preset",
        choices=sorted(PRESETS.keys()),
        default="pastel_diary",
        help="Prompt preset.",
    )
    parser.add_argument("--prompt", default=None, help="Extra prompt text to append.")
    parser.add_argument("--negative-prompt", default=None, help="Extra negative prompt text.")
    parser.add_argument("--strength", type=float, default=0.72, help="0.0 keeps photo, 1.0 redraws more.")
    parser.add_argument("--guidance-scale", type=float, default=7.0)
    parser.add_argument("--steps", type=int, default=28)
    parser.add_argument("--seed", type=int, default=11)
    parser.add_argument("--batch", type=int, default=1)
    parser.add_argument("--size", type=int, default=768, help="Square working size.")
    return parser.parse_args()


def pick_device() -> tuple[str, torch.dtype]:
    if torch.cuda.is_available():
        return "cuda", torch.float16
    if torch.backends.mps.is_available():
        return "mps", torch.float32
    return "cpu", torch.float32


def prepare_image(path: str, size: int) -> Image.Image:
    image = Image.open(path)
    image = ImageOps.exif_transpose(image).convert("RGB")
    image.thumbnail((size, size), Image.Resampling.LANCZOS)

    canvas = Image.new("RGB", (size, size), (246, 241, 232))
    x = (size - image.width) // 2
    y = (size - image.height) // 2
    canvas.paste(image, (x, y))
    return canvas


def build_prompt(args: argparse.Namespace) -> tuple[str, str]:
    preset = PRESETS[args.preset]
    prompt = preset["prompt"]
    if args.prompt:
        prompt = f"{prompt}, {args.prompt}"

    negative = preset["negative"]
    if args.negative_prompt:
        negative = f"{negative}, {args.negative_prompt}"
    return prompt, negative


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
    prompt, negative_prompt = build_prompt(args)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    for index in range(args.batch):
        seed = args.seed + index
        generator_device = "cuda" if device == "cuda" else "cpu"
        generator = torch.Generator(device=generator_device).manual_seed(seed)
        result = pipe(
            prompt=prompt,
            negative_prompt=negative_prompt,
            image=init_image,
            strength=args.strength,
            guidance_scale=args.guidance_scale,
            num_inference_steps=args.steps,
            generator=generator,
        ).images[0]

        name = (
            f"{timestamp}_{args.preset}_s{args.strength}_steps{args.steps}_"
            f"seed{seed}.png"
        )
        output_path = output_dir / name
        result.save(output_path)
        print(f"Saved: {output_path}")


if __name__ == "__main__":
    main()
