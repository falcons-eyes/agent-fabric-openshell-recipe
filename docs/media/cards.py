"""제출 영상용 자막 카드 이미지(1600x1000)를 만든다."""
import sys
from PIL import Image, ImageDraw, ImageFont
FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
def card(path, title, sub):
    im = Image.new("RGB", (1600, 1000), (11, 16, 32)); d = ImageDraw.Draw(im)
    ft = ImageFont.truetype(FONT, 64, index=6); fs = ImageFont.truetype(FONT, 34, index=2)
    for text, font, y, color in ((title, ft, 420, (255, 255, 255)), (sub, fs, 530, (159, 232, 112))):
        w = d.textlength(text, font=font); d.text(((1600 - w) / 2, y), text, font=font, fill=color)
    im.save(path)
if __name__ == "__main__":
    card(*sys.argv[1:4])
