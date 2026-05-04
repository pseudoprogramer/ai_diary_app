import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a contact sheet for outputs.")
    parser.add_argument("--output", required=True)
    parser.add_argument("--cell-size", type=int, default=220)
    parser.add_argument("--inputs", nargs="+", required=True)
    return parser.parse_args()


def thumbnail(path: str, cell_size: int) -> Image.Image:
    image = Image.open(path)
    image = ImageOps.exif_transpose(image).convert("RGB")
    image.thumbnail((cell_size, cell_size), Image.Resampling.LANCZOS)
    return image


def main() -> None:
    args = parse_args()
    cell = args.cell_size
    margin = 18
    label_h = 28
    gap = 14

    images = [(Path(path), thumbnail(path, cell)) for path in args.inputs]
    width = len(images) * (cell + gap) + margin * 2 - gap
    height = cell + label_h + margin * 2
    sheet = Image.new("RGB", (width, height), (246, 241, 232))
    draw = ImageDraw.Draw(sheet)

    x = margin
    for path, image in images:
        sheet.paste(image, (x + (cell - image.width) // 2, margin))
        draw.text((x, margin + cell + 6), path.stem[:24], fill=(50, 45, 40))
        x += cell + gap

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)
    print(output)


if __name__ == "__main__":
    main()
