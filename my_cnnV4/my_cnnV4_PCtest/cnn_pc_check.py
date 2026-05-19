from pathlib import Path


IMG_W = 28
IMG_H = 28
L1_OUT_CH = 6
L1_K = 5
L1_OUT_W = 24
L1_OUT_H = 24
L2_OUT_W = 12
L2_OUT_H = 12
L3_OUT_CH = 12
L3_K = 5
L3_OUT_W = 8
L3_OUT_H = 8
L4_OUT_W = 4
L4_OUT_H = 4
FC_OUT = 10
SHIFT_BITS = 10

BASE_DIR = Path(__file__).resolve().parent
IMAGE_FILE = Path("C:/Users/28010/Desktop/my_cnn/test/0.txt")
CW_FILE = Path("C:/Users/28010/Desktop/my_cnn/sim/cnn_test/cw.txt")
FCW_FILE = Path("C:/Users/28010/Desktop/my_cnn/sim/cnn_test/fcw.txt")

OUT_SCORE_FILE = BASE_DIR / "cnn_scores.txt"
OUT_CONSOLE_FILE = BASE_DIR / "cnn_console_lines.txt"


def load_image():
    vals = [int(x, 2) for x in IMAGE_FILE.read_text(encoding="ascii").splitlines()]
    if len(vals) != IMG_W * IMG_H:
        raise ValueError(f"image size mismatch: {len(vals)}")
    fmap = []
    for r in range(IMG_H):
        fmap.append(vals[r * IMG_W:(r + 1) * IMG_W])
    return fmap


def load_conv_weights():
    vals = [int(x) for x in CW_FILE.read_text(encoding="ascii").splitlines()]
    if len(vals) != 1950:
        raise ValueError(f"conv weight size mismatch: {len(vals)}")
    return vals


def load_fc_weights():
    vals = [int(x) for x in FCW_FILE.read_text(encoding="ascii").splitlines()]
    if len(vals) != 1920:
        raise ValueError(f"fc weight size mismatch: {len(vals)}")
    return vals


def relu_quant(v):
    if v < 0:
        v = 0
    return (v >> SHIFT_BITS) & 0xFF


def conv1(image, weights):
    out = []
    for oc in range(L1_OUT_CH):
        kbase = oc * 25
        fmap = []
        for r in range(L1_OUT_H):
            row = []
            for c in range(L1_OUT_W):
                acc = 0
                for kr in range(L1_K):
                    for kc in range(L1_K):
                        acc += image[r + kr][c + kc] * weights[kbase + kr * L1_K + kc]
                row.append(acc)
            fmap.append(row)
        out.append(fmap)
    return out


def pool_maps(src_maps, src_h, src_w):
    dst = []
    for fmap in src_maps:
        out_map = []
        for r in range(0, src_h, 2):
            row = []
            for c in range(0, src_w, 2):
                vals = [
                    relu_quant(fmap[r + 0][c + 0]),
                    relu_quant(fmap[r + 0][c + 1]),
                    relu_quant(fmap[r + 1][c + 0]),
                    relu_quant(fmap[r + 1][c + 1]),
                ]
                row.append(max(vals))
            out_map.append(row)
        dst.append(out_map)
    return dst


def conv3(src_maps, weights):
    out = []
    base = 150
    for _ in range(L3_OUT_CH):
        fmap = []
        for _ in range(L3_OUT_H):
            fmap.append([0] * L3_OUT_W)
        out.append(fmap)

    for ic in range(L1_OUT_CH):
        for group in range(2):
            for lane in range(6):
                oc = (group * 6) + lane
                kbase = base + (ic * 300) + (group * 150) + (lane * 25)
                for r in range(L3_OUT_H):
                    for c in range(L3_OUT_W):
                        acc = 0
                        for kr in range(L3_K):
                            for kc in range(L3_K):
                                acc += src_maps[ic][r + kr][c + kc] * weights[kbase + kr * L3_K + kc]
                        out[oc][r][c] += acc

    return out


def fc_calc(src_maps, fcw):
    scores = []
    for out_idx in range(FC_OUT):
        base = out_idx * 192
        acc = 0
        for group in range(2):
            for lane in range(6):
                ch = group * 6 + lane
                for pos in range(16):
                    r = pos // 4
                    c = pos % 4
                    w_idx = base + group * 96 + lane * 16 + pos
                    acc += src_maps[ch][r][c] * fcw[w_idx]
        scores.append(acc)
    return scores


def main():
    image = load_image()
    cw = load_conv_weights()
    fcw = load_fc_weights()

    l1 = conv1(image, cw)
    l2 = pool_maps(l1, L1_OUT_H, L1_OUT_W)
    l3 = conv3(l2, cw)
    l4 = pool_maps(l3, L3_OUT_H, L3_OUT_W)
    scores = fc_calc(l4, fcw)

    pred = max(range(len(scores)), key=lambda i: scores[i])

    score_lines = []
    console_lines = []
    for idx, score in enumerate(scores):
        score_lines.append(f"{score}")
        console_lines.append(f"PC_SCORE idx={idx} score={score}")
    console_lines.append(f"PC_PREDICT digit={pred} score={scores[pred]}")

    OUT_SCORE_FILE.write_text("\n".join(score_lines) + "\n", encoding="ascii")
    OUT_CONSOLE_FILE.write_text("\n".join(console_lines) + "\n", encoding="ascii")

    print(f"image      : {IMAGE_FILE}")
    print(f"conv weight: {CW_FILE}")
    print(f"fc weight  : {FCW_FILE}")
    print(f"score file : {OUT_SCORE_FILE}")
    print(f"console out: {OUT_CONSOLE_FILE}")
    for line in console_lines:
        print(line)


if __name__ == "__main__":
    main()
