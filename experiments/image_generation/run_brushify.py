import argparse
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import (
    Image,
    ImageChops,
    ImageEnhance,
    ImageFilter,
    ImageOps,
)


PRESETS = {
    "opencv_oil_trace": {
        "engine": "opencv_oil",
        "oil_size": 7,
        "oil_dyn_ratio": 1,
        "stylization": 0.22,
        "edge_strength": 0.16,
        "texture_strength": 0.09,
        "color": 1.08,
        "contrast": 1.04,
        "sharpness": 1.05,
    },
    "opencv_focus_oil_trace": {
        "engine": "opencv_focus_oil",
        "oil_size": 7,
        "oil_dyn_ratio": 1,
        "stylization": 0.18,
        "focus_keep": 0.72,
        "edge_strength": 0.11,
        "texture_strength": 0.07,
        "color": 1.10,
        "contrast": 1.04,
        "sharpness": 1.06,
    },
    "opencv_watercolor_trace": {
        "engine": "opencv_stylization",
        "sigma_s": 70,
        "sigma_r": 0.42,
        "edge_strength": 0.10,
        "texture_strength": 0.06,
        "color": 1.04,
        "contrast": 1.00,
        "sharpness": 0.96,
    },
    "recognizable_brush": {
        "engine": "pil",
        "bits": 5,
        "smooth_passes": 3,
        "edge_strength": 0.24,
        "texture_strength": 0.12,
        "color": 1.10,
        "contrast": 1.06,
        "sharpness": 1.12,
    },
    "soft_watercolor_trace": {
        "engine": "pil",
        "bits": 6,
        "smooth_passes": 5,
        "edge_strength": 0.15,
        "texture_strength": 0.08,
        "color": 1.03,
        "contrast": 0.98,
        "sharpness": 0.92,
    },
    "bold_oil_trace": {
        "engine": "pil",
        "bits": 4,
        "smooth_passes": 2,
        "edge_strength": 0.34,
        "texture_strength": 0.18,
        "color": 1.18,
        "contrast": 1.12,
        "sharpness": 1.22,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert a photo into a recognizable brush-painted version."
    )
    parser.add_argument("--input", required=True, help="Path to the source photo.")
    parser.add_argument("--output-dir", default="outputs/brushify")
    parser.add_argument("--preset", choices=sorted(PRESETS), default="recognizable_brush")
    parser.add_argument("--max-size", type=int, default=1024)
    parser.add_argument("--seed", type=int, default=17)
    parser.add_argument(
        "--paper-border",
        action="store_true",
        help="Place the result on a lightly textured diary-paper background.",
    )
    return parser.parse_args()


def load_image(path: str, max_size: int) -> Image.Image:
    image = Image.open(path)
    image = ImageOps.exif_transpose(image).convert("RGB")
    image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
    return image


def smooth_paint(image: Image.Image, passes: int) -> Image.Image:
    painted = image
    for _ in range(passes):
        painted = painted.filter(ImageFilter.SMOOTH_MORE)
        painted = painted.filter(ImageFilter.MedianFilter(3))
    return painted


def edge_mask(image: Image.Image) -> Image.Image:
    gray = ImageOps.grayscale(image)
    edges = gray.filter(ImageFilter.FIND_EDGES)
    edges = ImageOps.autocontrast(edges)
    edges = edges.filter(ImageFilter.GaussianBlur(0.55))
    return edges


def make_texture(size: tuple[int, int], seed: int) -> Image.Image:
    width, height = size
    rng = np.random.default_rng(seed)
    noise = rng.normal(128, 28, (height, width)).clip(0, 255).astype(np.uint8)
    texture = Image.fromarray(noise)
    texture = texture.filter(ImageFilter.GaussianBlur(0.9))

    diagonal = texture.rotate(8, resample=Image.Resampling.BICUBIC, expand=False)
    diagonal = diagonal.filter(ImageFilter.GaussianBlur((1.8)))
    return ImageChops.blend(texture, diagonal, 0.45)


def opencv_oil(image: Image.Image, preset: dict[str, float]) -> Image.Image:
    try:
        import cv2
    except ImportError as exc:
        raise RuntimeError("opencv-contrib-python is required for this preset.") from exc

    rgb = np.asarray(image)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    oil = cv2.xphoto.oilPainting(
        bgr,
        int(preset["oil_size"]),
        int(preset["oil_dyn_ratio"]),
    )
    stylized = cv2.stylization(bgr, sigma_s=65, sigma_r=0.42)
    blended = cv2.addWeighted(oil, 1.0 - preset["stylization"], stylized, preset["stylization"], 0)
    return Image.fromarray(cv2.cvtColor(blended, cv2.COLOR_BGR2RGB))


def opencv_focus_oil(image: Image.Image, preset: dict[str, float]) -> Image.Image:
    try:
        import cv2
    except ImportError as exc:
        raise RuntimeError("opencv-contrib-python is required for this preset.") from exc

    rgb = np.asarray(image).astype(np.uint8)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    oil = cv2.xphoto.oilPainting(
        bgr,
        int(preset["oil_size"]),
        int(preset["oil_dyn_ratio"]),
    )
    soft_detail = cv2.stylization(bgr, sigma_s=45, sigma_r=0.22)

    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    grad_x = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    edges = cv2.magnitude(grad_x, grad_y)
    edges = cv2.normalize(edges, None, 0.0, 1.0, cv2.NORM_MINMAX)

    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    saturation = hsv[:, :, 1].astype(np.float32) / 255.0

    saliency = np.zeros_like(saturation, dtype=np.float32)
    if hasattr(cv2, "saliency"):
        detector = cv2.saliency.StaticSaliencyFineGrained_create()
        ok, saliency_map = detector.computeSaliency(bgr)
        if ok:
            saliency = saliency_map.astype(np.float32)

    height, width = saturation.shape
    yy, xx = np.mgrid[0:height, 0:width]
    nx = (xx - width / 2) / max(1, width / 2)
    ny = (yy - height / 2) / max(1, height / 2)
    center = np.clip(1.0 - np.sqrt(nx * nx + ny * ny), 0.0, 1.0)

    mask = saliency * 0.38 + saturation * 0.28 + edges * 0.24 + center * 0.10
    mask = cv2.GaussianBlur(mask, (0, 0), 9)
    mask = np.clip((mask - 0.16) / 0.64, 0.0, 1.0)
    mask = np.power(mask, 0.75) * float(preset["focus_keep"])
    mask = mask[:, :, None]

    blended = oil.astype(np.float32) * (1.0 - mask) + soft_detail.astype(np.float32) * mask
    return Image.fromarray(cv2.cvtColor(np.clip(blended, 0, 255).astype(np.uint8), cv2.COLOR_BGR2RGB))


def opencv_stylization(image: Image.Image, preset: dict[str, float]) -> Image.Image:
    try:
        import cv2
    except ImportError as exc:
        raise RuntimeError("opencv-contrib-python is required for this preset.") from exc

    rgb = np.asarray(image)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    stylized = cv2.stylization(
        bgr,
        sigma_s=int(preset["sigma_s"]),
        sigma_r=float(preset["sigma_r"]),
    )
    return Image.fromarray(cv2.cvtColor(stylized, cv2.COLOR_BGR2RGB))


def base_paint(image: Image.Image, preset: dict[str, float]) -> Image.Image:
    engine = preset.get("engine", "pil")
    if engine == "opencv_oil":
        return opencv_oil(image, preset)
    if engine == "opencv_focus_oil":
        return opencv_focus_oil(image, preset)
    if engine == "opencv_stylization":
        return opencv_stylization(image, preset)

    painted = smooth_paint(image, int(preset["smooth_passes"]))
    painted = ImageOps.posterize(painted, int(preset["bits"]))
    return painted


def apply_brushify(image: Image.Image, preset: dict[str, float], seed: int) -> Image.Image:
    boosted = ImageEnhance.Color(image).enhance(preset["color"])
    boosted = ImageEnhance.Contrast(boosted).enhance(preset["contrast"])

    painted = base_paint(boosted, preset)
    painted = ImageEnhance.Sharpness(painted).enhance(preset["sharpness"])

    base = np.asarray(painted).astype(np.float32)

    edges = np.asarray(edge_mask(image)).astype(np.float32) / 255.0
    edge_factor = 1.0 - preset["edge_strength"] * np.power(edges, 0.7)
    base *= edge_factor[..., None]

    texture = np.asarray(make_texture(image.size, seed)).astype(np.float32) / 255.0
    texture_factor = 1.0 + preset["texture_strength"] * (texture - 0.5)
    base *= texture_factor[..., None]

    result = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
    result = result.filter(ImageFilter.UnsharpMask(radius=1.1, percent=65, threshold=3))
    return result


def add_paper_border(image: Image.Image, seed: int) -> Image.Image:
    margin = max(28, round(min(image.size) * 0.06))
    width = image.width + margin * 2
    height = image.height + margin * 2

    rng = np.random.default_rng(seed + 1000)
    noise = rng.normal(244, 6, (height, width)).clip(225, 255).astype(np.uint8)
    paper = Image.fromarray(noise).convert("RGB")
    paper = ImageEnhance.Color(paper).enhance(0.35)
    paper = ImageOps.colorize(ImageOps.grayscale(paper), "#eee7da", "#fffdf7")
    paper.paste(image, (margin, margin))
    return paper


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    source = load_image(args.input, args.max_size)
    result = apply_brushify(source, PRESETS[args.preset], args.seed)
    if args.paper_border:
        result = add_paper_border(result, args.seed)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    input_name = Path(args.input).stem[:8]
    output_path = output_dir / f"{timestamp}_{input_name}_{args.preset}_seed{args.seed}.png"
    result.save(output_path)
    print(f"Saved: {output_path}")


if __name__ == "__main__":
    main()
