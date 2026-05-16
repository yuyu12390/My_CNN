from pathlib import Path


IMG_W = 28
IMG_H = 28
WIN_R0 = 4
WIN_C0 = 12
K = 5

IMAGE_FILE = Path("C:/Users/28010/Desktop/my_cnn/test/0.txt")
BASE_DIR = Path(__file__).resolve().parent
PIXEL_FILE = BASE_DIR / "conv_l1_case0_pixels.txt"
WEIGHT_FILE = BASE_DIR / "conv_l1_case0_weights.txt"
RESULT_FILE = BASE_DIR / "conv_l1_case0_result.txt"


def load_image():
    lines = IMAGE_FILE.read_text(encoding="ascii").splitlines()
    if len(lines) != IMG_W * IMG_H:
        raise ValueError(f"image size mismatch: got {len(lines)}")
    return [int(x, 2) for x in lines]


def extract_window(img):
    pixels = []
    for r in range(WIN_R0, WIN_R0 + K):
        for c in range(WIN_C0, WIN_C0 + K):
            pixels.append(img[r * IMG_W + c])
    return pixels


def main():
    img = load_image()
    pixels = extract_window(img)
    weights = [
         1, -1,  2, -2,  3,
        -3,  4, -4,  5, -5,
         6, -6,  7, -7,  8,
        -8,  9, -9, 10,-10,
        11,-11, 12,-12, 13,
    ]

    conv_sum = sum(p * w for p, w in zip(pixels, weights))

    PIXEL_FILE.write_text("\n".join(str(x) for x in pixels) + "\n", encoding="ascii")
    WEIGHT_FILE.write_text("\n".join(str(x) for x in weights) + "\n", encoding="ascii")
    RESULT_FILE.write_text(str(conv_sum) + "\n", encoding="ascii")

    print(f"pixels  : {pixels}")
    print(f"weights : {weights}")
    print(f"result  : {conv_sum}")


if __name__ == "__main__":
    main()
