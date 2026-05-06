import argparse
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

from run_brushify import PRESETS as BRUSH_PRESETS
from run_brushify import add_paper_border, apply_brushify


VIEWPOINTS = {
    "left": (-1.0, 0.0),
    "right": (1.0, 0.0),
    "up": (0.0, -1.0),
    "down": (0.0, 1.0),
    "upper_left": (-0.75, -0.45),
    "upper_right": (0.75, -0.45),
    "lower_left": (-0.75, 0.45),
    "lower_right": (0.75, 0.45),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Approximate a new camera viewpoint with a 2.5D depth warp, then "
            "apply a recognizable brush trace."
        )
    )
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-dir", default="outputs/viewpoint_brush")
    parser.add_argument("--viewpoint", choices=sorted(VIEWPOINTS), default="upper_right")
    parser.add_argument("--parallax", type=float, default=34.0)
    parser.add_argument("--zoom", type=float, default=1.04)
    parser.add_argument("--max-size", type=int, default=768)
    parser.add_argument("--seed", type=int, default=121)
    parser.add_argument(
        "--brush-preset",
        choices=sorted(BRUSH_PRESETS),
        default="opencv_oil_trace",
    )
    parser.add_argument("--paper-border", action="store_true")
    parser.add_argument("--keep-intermediate", action="store_true")
    return parser.parse_args()


def load_image(path: str, max_size: int) -> Image.Image:
    image = Image.open(path)
    image = ImageOps.exif_transpose(image).convert("RGB")
    image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
    return image


def estimate_depth(rgb: np.ndarray) -> np.ndarray:
    try:
        import cv2
    except ImportError as exc:
        raise RuntimeError("opencv-contrib-python is required for this script.") from exc

    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    saturation = hsv[:, :, 1].astype(np.float32) / 255.0

    height, width = gray.shape
    yy, xx = np.mgrid[0:height, 0:width]
    nx = (xx - width / 2) / max(1, width / 2)
    ny = (yy - height / 2) / max(1, height / 2)
    center = np.clip(1.0 - np.sqrt(nx * nx + ny * ny), 0.0, 1.0)
    lower_foreground = np.clip(yy / max(1, height - 1), 0.0, 1.0)

    grad_x = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    edges = cv2.magnitude(grad_x, grad_y)
    edges = cv2.normalize(edges, None, 0.0, 1.0, cv2.NORM_MINMAX)

    saliency = np.zeros_like(gray, dtype=np.float32)
    if hasattr(cv2, "saliency"):
        detector = cv2.saliency.StaticSaliencyFineGrained_create()
        ok, saliency_map = detector.computeSaliency(bgr)
        if ok:
            saliency = saliency_map.astype(np.float32)

    depth = (
        saliency * 0.38
        + center * 0.20
        + lower_foreground * 0.18
        + saturation * 0.14
        + edges * 0.10
    )
    depth = cv2.GaussianBlur(depth, (0, 0), 7)
    depth = cv2.normalize(depth, None, 0.0, 1.0, cv2.NORM_MINMAX)
    return np.power(depth, 1.15).astype(np.float32)


def viewpoint_warp(
    image: Image.Image,
    viewpoint: str,
    parallax: float,
    zoom: float,
) -> Image.Image:
    try:
        import cv2
    except ImportError as exc:
        raise RuntimeError("opencv-contrib-python is required for this script.") from exc

    rgb = np.asarray(image).astype(np.uint8)
    height, width = rgb.shape[:2]
    depth = estimate_depth(rgb)
    vx, vy = VIEWPOINTS[viewpoint]

    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    cx = (width - 1) / 2
    cy = (height - 1) / 2
    depth_centered = depth - float(depth.mean())

    map_x = (xx - cx) / zoom + cx - depth_centered * parallax * vx
    map_y = (yy - cy) / zoom + cy - depth_centered * parallax * vy
    warped = cv2.remap(
        rgb,
        map_x.astype(np.float32),
        map_y.astype(np.float32),
        interpolation=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(246, 241, 232),
    )

    valid = (
        (map_x >= 0)
        & (map_x < width - 1)
        & (map_y >= 0)
        & (map_y < height - 1)
    ).astype(np.uint8)
    mask = (1 - valid) * 255
    mask = cv2.dilate(mask, np.ones((5, 5), np.uint8), iterations=1)
    inpainted = cv2.inpaint(warped, mask, 5, cv2.INPAINT_TELEA)
    return Image.fromarray(inpainted)


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    source = load_image(args.input, args.max_size)
    shifted = viewpoint_warp(
        source,
        viewpoint=args.viewpoint,
        parallax=args.parallax,
        zoom=args.zoom,
    )

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = Path(args.input).stem[:8]
    if args.keep_intermediate:
        intermediate = output_dir / (
            f"{timestamp}_{stem}_{args.viewpoint}_view_seed{args.seed}.png"
        )
        shifted.save(intermediate)
        print(f"Saved intermediate: {intermediate}")

    brush = apply_brushify(shifted, BRUSH_PRESETS[args.brush_preset], args.seed)
    if args.paper_border:
        brush = add_paper_border(brush, args.seed)

    output = output_dir / (
        f"{timestamp}_{stem}_{args.viewpoint}_{args.brush_preset}_"
        f"p{args.parallax}_seed{args.seed}.png"
    )
    brush.save(output)
    print(f"Saved: {output}")


if __name__ == "__main__":
    main()
