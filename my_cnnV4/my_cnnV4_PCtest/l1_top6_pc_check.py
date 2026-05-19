from pathlib import Path


IMG_W = 28
IMG_H = 28
K = 5
STRIDE = 1
OUT_W = ((IMG_W - K) // STRIDE) + 1
OUT_H = ((IMG_H - K) // STRIDE) + 1
LANE_NUM = 6
L0_WEIGHT_NUM = 25

IMAGE_FILE = Path("C:/Users/28010/Desktop/my_cnn/test/0.txt")
WEIGHT_FILE = Path("C:/Users/28010/Desktop/my_cnn/sim/cnn_test/cw.txt")
BASE_DIR = Path(__file__).resolve().parent
OUT_MATRIX_FILE = BASE_DIR / "l1_top6_feature_map_all.txt"
OUT_CONSOLE_FILE = BASE_DIR / "l1_top6_console_lines.txt"


def load_image():
    lines = IMAGE_FILE.read_text(encoding="ascii").splitlines()
    if len(lines) != IMG_W * IMG_H:
        raise ValueError(f"image size mismatch: got {len(lines)}")
    return [int(x, 2) for x in lines]


def load_lane_weights():
    lines = WEIGHT_FILE.read_text(encoding="ascii").splitlines()
    weights = [int(x) for x in lines]
    need = LANE_NUM * L0_WEIGHT_NUM
    if len(weights) < need:
        raise ValueError(f"weight size mismatch: got {len(weights)}, need at least {need}")

    lane_weights = []
    for lane in range(LANE_NUM):
        start = lane * L0_WEIGHT_NUM
        lane_weights.append(weights[start:start + L0_WEIGHT_NUM])
    return lane_weights


def calc_feature_map(img, weights):
    feature_map = []
    for base_r in range(0, IMG_H - K + 1, STRIDE):
        row_vals = []
        for base_c in range(0, IMG_W - K + 1, STRIDE):
            conv_sum = 0
            for kr in range(K):
                for kc in range(K):
                    pix = img[(base_r + kr) * IMG_W + (base_c + kc)]
                    wgt = weights[(kr * K) + kc]
                    conv_sum += pix * wgt
            row_vals.append(conv_sum)
        feature_map.append(row_vals)
    return feature_map


def format_all_maps(feature_maps):
    lines = []
    for lane, fmap in enumerate(feature_maps):
        lines.append(f"LANE {lane}")
        for row in fmap:
            lines.append(" ".join(str(x) for x in row))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def format_console_lines(feature_maps):
    lines = []
    idx = 0
    for row in range(OUT_H):
        for col in range(OUT_W):
            vals = [feature_maps[lane][row][col] for lane in range(LANE_NUM)]
            lines.append(
                "PC_WIN idx={idx} row={row} col={col} lane0={lane0} lane1={lane1} lane2={lane2} lane3={lane3} lane4={lane4} lane5={lane5}".format(
                    idx=idx,
                    row=row,
                    col=col,
                    lane0=vals[0],
                    lane1=vals[1],
                    lane2=vals[2],
                    lane3=vals[3],
                    lane4=vals[4],
                    lane5=vals[5],
                )
            )
            idx += 1
    return "\n".join(lines) + "\n"


def main():
    img = load_image()
    lane_weights = load_lane_weights()
    feature_maps = [calc_feature_map(img, lane_weights[lane]) for lane in range(LANE_NUM)]

    OUT_MATRIX_FILE.write_text(format_all_maps(feature_maps), encoding="ascii")
    OUT_CONSOLE_FILE.write_text(format_console_lines(feature_maps), encoding="ascii")

    print(f"image     : {IMAGE_FILE}")
    print(f"weights   : {WEIGHT_FILE}")
    print(f"lanes     : {LANE_NUM}")
    print(f"feature   : {OUT_H}x{OUT_W} per lane")
    print(f"matrix out: {OUT_MATRIX_FILE}")
    print(f"line out  : {OUT_CONSOLE_FILE}")
    print(format_console_lines(feature_maps), end="")


if __name__ == "__main__":
    main()
