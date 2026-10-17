#!/usr/bin/env python3
"""Generate the faria2 application icons.

The chosen design (option B) is a dark rounded tile where the outlined
"faria2" wordmark runs diagonally and becomes the arrow shaft; a blue
arrowhead completes the arrow.

Outputs:
  assets/icons/app_icon.svg     vector source (512x512)
  assets/icons/app_icon.png     512x512
  assets/icons/tray_icon.png    64x64
  assets/icons/app_icon.ico     multi-size Windows icon
  windows/runner/resources/app_icon.ico

The wordmark is converted from text to outlines with Pango/Cairo so the icon
does not depend on a font at build time. Rasterization uses GdkPixbuf's
librsvg loader, the ICO is assembled with ImageMagick.

Dependencies: python3-gi (Pango/Cairo/GdkPixbuf + librsvg) and ImageMagick.
"""

import subprocess
import tempfile
from pathlib import Path

import cairo
import gi

gi.require_version('Pango', '1.0')
gi.require_version('PangoCairo', '1.0')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import GdkPixbuf, Pango, PangoCairo

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / 'assets' / 'icons'
WORDMARK = 'faria2'
FONT = 'Noto Sans Bold 120'


def wordmark_data(target_width):
    """Returns (svg path data, width, height) for the outlined wordmark."""
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 8, 8)
    context = cairo.Context(surface)
    layout = PangoCairo.create_layout(context)
    layout.set_font_description(Pango.FontDescription(FONT))
    attributes = Pango.AttrList()
    attributes.insert(Pango.attr_letter_spacing_new(-1.5 * Pango.SCALE))
    layout.set_attributes(attributes)
    layout.set_text(WORDMARK, -1)
    PangoCairo.layout_path(context, layout)

    path = context.copy_path()
    points = []
    for item in path:
        coordinates = item[1]
        for index in range(0, len(coordinates), 2):
            points.append((coordinates[index], coordinates[index + 1]))
    min_x = min(point[0] for point in points)
    min_y = min(point[1] for point in points)
    width = max(point[0] for point in points) - min_x
    height = max(point[1] for point in points) - min_y
    scale = target_width / width

    def fmt(value):
        return ('%.2f' % value).rstrip('0').rstrip('.')

    def transform(x, y):
        return (x - min_x) * scale, (y - min_y) * scale

    parts = []
    for item in path:
        kind, coordinates = item[0], item[1]
        if kind == cairo.PATH_MOVE_TO:
            x, y = transform(coordinates[0], coordinates[1])
            parts.append('M' + fmt(x) + ' ' + fmt(y))
        elif kind == cairo.PATH_LINE_TO:
            x, y = transform(coordinates[0], coordinates[1])
            parts.append('L' + fmt(x) + ' ' + fmt(y))
        elif kind == cairo.PATH_CURVE_TO:
            x1, y1 = transform(coordinates[0], coordinates[1])
            x2, y2 = transform(coordinates[2], coordinates[3])
            x3, y3 = transform(coordinates[4], coordinates[5])
            parts.append('C' + fmt(x1) + ' ' + fmt(y1) + ' ' +
                         fmt(x2) + ' ' + fmt(y2) + ' ' +
                         fmt(x3) + ' ' + fmt(y3))
        elif kind == cairo.PATH_CLOSE_PATH:
            parts.append('Z')
    return ''.join(parts), width * scale, height * scale


def right_head(left_x, width, height, round_tip=10):
    cy = 256
    tip = left_x + width
    return (f'M{left_x} {cy - height / 2} '
            f'L{tip - round_tip * 1.2} {cy - round_tip} '
            f'Q{tip} {cy} {tip - round_tip * 1.2} {cy + round_tip} '
            f'L{left_x} {cy + height / 2} Z')


def build_svg():
    data, word_w, word_h = wordmark_data(400.0)
    head_w = 132.0
    total = word_w + head_w - 6
    left = 256 - total / 2
    top = 256 - word_h / 2
    head_left = left + word_w - 6

    defs = (
        '<defs>'
        '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#101A2B"/>'
        '<stop offset="1" stop-color="#1B2C46"/>'
        '</linearGradient>'
        '<linearGradient id="head" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#8FDDFF"/>'
        '<stop offset="1" stop-color="#2E8BE6"/>'
        '</linearGradient>'
        f'<linearGradient id="word" gradientUnits="userSpaceOnUse" '
        f'x1="{left:.2f}" y1="0" x2="{left + word_w:.2f}" y2="0">'
        '<stop offset="0" stop-color="#EAF7FF"/>'
        '<stop offset="0.82" stop-color="#EAF7FF"/>'
        '<stop offset="1" stop-color="#8FDDFF"/>'
        '</linearGradient>'
        '</defs>'
    )
    body = (
        '<rect x="14" y="14" width="484" height="484" rx="112" '
        'fill="url(#bg)" stroke="#2A3C58" stroke-width="3"/>'
        '<g transform="rotate(45 256 256)">'
        f'<path d="{data}" fill="url(#word)" '
        f'transform="translate({left:.2f} {top:.2f})"/>'
        f'<path d="{right_head(head_left, head_w, 164)}" fill="url(#head)" '
        'stroke="url(#head)" stroke-width="8" stroke-linejoin="round"/>'
        '</g>'
    )
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" '
            'viewBox="0 0 512 512">' + defs + body + '</svg>')


def render(svg, size, target):
    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(svg), size, size, True)
    pixbuf.savev(str(target), 'png', [], [])


def main():
    svg_path = ICONS / 'app_icon.svg'
    svg_path.write_text(build_svg() + '\n')

    app_png = ICONS / 'app_icon.png'
    tray_png = ICONS / 'tray_icon.png'
    render(svg_path, 512, app_png)
    render(svg_path, 64, tray_png)

    with tempfile.TemporaryDirectory() as temp:
        temp_dir = Path(temp)
        frames = []
        for size in (256, 128, 64, 48, 32, 16):
            frame = temp_dir / f'icon-{size}.png'
            render(svg_path, size, frame)
            frames.append(frame)
        ico = ICONS / 'app_icon.ico'
        subprocess.run(['magick', *map(str, frames), str(ico)], check=True)

    (ROOT / 'windows' / 'runner' / 'resources' / 'app_icon.ico').write_bytes(
        (ICONS / 'app_icon.ico').read_bytes()
    )
    print('wrote', svg_path)
    print('wrote', app_png, tray_png, ico)


if __name__ == '__main__':
    main()
