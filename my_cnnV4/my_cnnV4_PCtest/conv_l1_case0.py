from pathlib import Path


IMG_W = 28
IMG_H = 28
K = 5
STRIDE = 1
OUT_W = ((IMG_W - K) // STRIDE) + 1
OUT_H = ((IMG_H - K) // STRIDE) + 1
WIN_R0 = 4
WIN_C0 = 12

IMAGE_FILE = Path("C:/Users/28010/Desktop/my_cnn/test/0.txt")
BASE_DIR = Path(__file__).resolve().parent
PIXEL_FILE = BASE_DIR / "conv_l1_case0_pixels.txt"
WEIGHT_FILE = BASE_DIR / "conv_l1_case0_weights.txt"
RESULT_FILE = BASE_DIR / "conv_l1_case0_result.txt"
FEATURE_MAP_FILE = BASE_DIR / "conv_l1_case0_feature_map.txt"


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


def calc_feature_map(img, weights):
    feature_map = []
    for base_r in range(0, IMG_H - K + 1, STRIDE):
        row_vals = []
        for base_c in range(0, IMG_W - K + 1, STRIDE):
            conv_sum = 0
            for kr in range(K):
                for kc in range(K):
                    pix = img[(base_r + kr) * IMG_W + (base_c + kc)]
                    wgt = weights[kr * K + kc]
                    conv_sum += pix * wgt
            row_vals.append(conv_sum)
        feature_map.append(row_vals)
    return feature_map


def format_feature_map(feature_map):
    return "\n".join(" ".join(str(x) for x in row) for row in feature_map) + "\n"


def main():
    img = load_image()
    weights = [
         1, -1,  2, -2,  3,
        -3,  4, -4,  5, -5,
         6, -6,  7, -7,  8,
        -8,  9, -9, 10,-10,
        11,-11, 12,-12, 13,
    ]

    pixels = extract_window(img)
    conv_sum = sum(p * w for p, w in zip(pixels, weights))
    feature_map = calc_feature_map(img, weights)

    PIXEL_FILE.write_text("\n".join(str(x) for x in pixels) + "\n", encoding="ascii")
    WEIGHT_FILE.write_text("\n".join(str(x) for x in weights) + "\n", encoding="ascii")
    RESULT_FILE.write_text(str(conv_sum) + "\n", encoding="ascii")
    FEATURE_MAP_FILE.write_text(format_feature_map(feature_map), encoding="ascii")

    print(f"pixels  : {pixels}")
    print(f"weights : {weights}")
    print(f"result  : {conv_sum}")
    print(f"feature : {OUT_H}x{OUT_W}, first={feature_map[0][0]}, target={feature_map[WIN_R0][WIN_C0]}")


if __name__ == "__main__":
    main()
