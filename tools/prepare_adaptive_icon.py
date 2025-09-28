from PIL import Image

SRC = 'assets/app_icon.png'
OUT_ANDROID_FG = 'assets/app_icon_fg.png'
OUT_IOS = 'assets/app_icon_ios.png'

SCALE_PCT = 0.85  # 85% of canvas on longest edge

def render_centered(src_path, dst_path, scale_pct=SCALE_PCT, size=1024):
    im = Image.open(src_path).convert('RGBA')
    alpha = im.split()[-1]
    bbox = alpha.getbbox() or (0, 0, im.width, im.height)
    cropped = im.crop(bbox)

    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    w, h = cropped.size
    scale = scale_pct * size / max(w, h)
    nw, nh = int(w * scale), int(h * scale)
    resized = cropped.resize((nw, nh), Image.LANCZOS)
    canvas.paste(resized, ((size - nw)//2, (size - nh)//2), resized)
    canvas.save(dst_path)
    print(f'Wrote {dst_path}')

def main():
    render_centered(SRC, OUT_ANDROID_FG)
    render_centered(SRC, OUT_IOS)

if __name__ == '__main__':
    main()
