from pathlib import Path


IMG_W = 28
IMG_H = 28
CONV_K = 5
CONV_STRIDE = 1
SRC_W = ((IMG_W - CONV_K) // CONV_STRIDE) + 1
SRC_H = ((IMG_H - CONV_K) // CONV_STRIDE) + 1
POOL_K = 2
POOL_STRIDE = 2
DST_W = ((SRC_W - POOL_K) // POOL_STRIDE) + 1
DST_H = ((SRC_H - POOL_K) // POOL_STRIDE) + 1
LANE_ID = 0
L0_WEIGHT_NUM = 25
SHIFT_BITS = 10

IMAGE_FILE = Path("C:/Users/28010/Desktop/my_cnn/test/0.txt")
WEIGHT_FILE = Path("C:/Users/28010/Desktop/my_cnn/sim/cnn_test/cw.txt")
BASE_DIR = Path(__file__).resolve().parent
OUT_FILE = BASE_DIR / "l1l2_lane0_pool_map.txt"
OUT_CONSOLE_FILE = BASE_DIR / "l1l2_lane0_console_lines.txt"


def load_image():
    lines = IMAGE_FILE.read_text(encoding="ascii").splitlines()
    if len(lines) != IMG_W * IMG_H:
        raise ValueError(f"image size mismatch: got {len(lines)}")
    return [int(x, 2) for x in lines]


def load_lane_weights():
    lines = WEIGHT_FILE.read_text(encoding="ascii").splitlines()
    weights = [int(x) for x in lines]
    start = LANE_ID * L0_WEIGHT_NUM
    end = start + L0_WEIGHT_NUM
    if len(weights) < end:
        raise ValueError(f"weight size mismatch: got {len(weights)}, need at least {end}")
    return weights[start:end]


def calc_conv_map(img, weights):
    fmap = []
    for base_r in range(0, IMG_H - CONV_K + 1, CONV_STRIDE):
        row_vals = []
        for base_c in range(0, IMG_W - CONV_K + 1, CONV_STRIDE):
            conv_sum = 0
            for kr in range(CONV_K):
                for kc in range(CONV_K):
                    pix = img[(base_r + kr) * IMG_W + (base_c + kc)]
                    wgt = weights[(kr * CONV_K) + kc]
                    conv_sum += pix * wgt
            row_vals.append(conv_sum)
        fmap.append(row_vals)
    return fmap


def relu_quant(val):
    clip = 0 if val < 0 else val
    return (clip >> SHIFT_BITS) & 0xFF


def calc_pool_map(conv_map):
    out = []
    for row in range(DST_H):
        row_vals = []
        for col in range(DST_W):
            max_val = None
            for kr in range(POOL_K):
                for kc in range(POOL_K):
                    src_val = relu_quant(conv_map[(row * POOL_STRIDE) + kr][(col * POOL_STRIDE) + kc])
                    if (max_val is None) or (src_val > max_val):
                        max_val = src_val
            row_vals.append(max_val)
        out.append(row_vals)
    return out


def format_matrix(mat):
    return "\n".join(" ".join(str(x) for x in row) for row in mat) + "\n"


def format_console_lines(mat):
    lines = []
    idx = 0
    for row in range(DST_H):
        for col in range(DST_W):
            lines.append(
                "L1L2_PC lane={lane} idx={idx} row={row} col={col} data={data}".format(
                    lane=LANE_ID,
                    idx=idx,
                    row=row,
                    col=col,
                    data=mat[row][col],
                )
            )
            idx += 1
    return "\n".join(lines) + "\n"


def main():
    img = load_image()
    weights = load_lane_weights()
    conv_map = calc_conv_map(img, weights)
    pool_map = calc_pool_map(conv_map)

    OUT_FILE.write_text(format_matrix(pool_map), encoding="ascii")
    OUT_CONSOLE_FILE.write_text(format_console_lines(pool_map), encoding="ascii")

    print(f"image      : {IMAGE_FILE}")
    print(f"weights    : {WEIGHT_FILE}")
    print(f"lane       : {LANE_ID}")
    print(f"pool map   : {OUT_FILE}")
    print(f"console out: {OUT_CONSOLE_FILE}")
    print(format_console_lines(pool_map), end="")


if __name__ == "__main__":
    main()
