from pathlib import Path


SRC_NUM = 6
OUT_NUM = 12
IMG_W = 12
IMG_H = 12
K = 5
STRIDE = 1
OUT_W = ((IMG_W - K) // STRIDE) + 1
OUT_H = ((IMG_H - K) // STRIDE) + 1
L0_KERNEL_NUM = 6
L0_WEIGHT_NUM = 25
L1_WEIGHT_NUM = 150
TOTAL_GLOBAL_WEIGHT = (L0_KERNEL_NUM * L0_WEIGHT_NUM) + (OUT_NUM * L1_WEIGHT_NUM)

BASE_DIR = Path(__file__).resolve().parent
OUT_MATRIX_FILE = BASE_DIR / "l3_top12_feature_map_all.txt"
OUT_CONSOLE_FILE = BASE_DIR / "l3_top12_console_lines.txt"
OUT_WEIGHT_FILE = BASE_DIR / "l3_top12_global_weights.txt"


def build_src_maps():
    src_maps = []
    for src_idx in range(SRC_NUM):
        one_map = []
        for row in range(IMG_H):
            one_row = []
            for col in range(IMG_W):
                one_row.append((src_idx * 20) + (row * IMG_W) + col + 1)
            one_map.append(one_row)
        src_maps.append(one_map)
    return src_maps


def build_weight_maps():
    weight_maps = []
    for out_idx in range(OUT_NUM):
        out_group = []
        for src_idx in range(SRC_NUM):
            one_kernel = []
            for tap_idx in range(K * K):
                one_kernel.append(out_idx + src_idx + tap_idx + 1)
            out_group.append(one_kernel)
        weight_maps.append(out_group)
    return weight_maps


def build_global_weights(weight_maps):
    weights = []

    for idx in range(L0_KERNEL_NUM * L0_WEIGHT_NUM):
        weights.append(idx + 1)

    for out_idx in range(OUT_NUM):
        for src_idx in range(SRC_NUM):
            for tap_idx in range(K * K):
                weights.append(weight_maps[out_idx][src_idx][tap_idx])

    if len(weights) != TOTAL_GLOBAL_WEIGHT:
        raise ValueError(f"global weight length mismatch: got {len(weights)}, expect {TOTAL_GLOBAL_WEIGHT}")

    return weights


def calc_feature_maps(src_maps, weight_maps):
    feature_maps = []

    for out_idx in range(OUT_NUM):
        out_map = []
        for row in range(OUT_H):
            one_row = []
            for col in range(OUT_W):
                acc = 0
                for src_idx in range(SRC_NUM):
                    for krow in range(K):
                        for kcol in range(K):
                            pix = src_maps[src_idx][row + krow][col + kcol]
                            wgt = weight_maps[out_idx][src_idx][(krow * K) + kcol]
                            acc += pix * wgt
                one_row.append(acc)
            out_map.append(one_row)
        feature_maps.append(out_map)

    return feature_maps


def format_all_maps(feature_maps):
    lines = []
    for out_idx, fmap in enumerate(feature_maps):
        lines.append(f"OUT {out_idx}")
        for row in fmap:
            lines.append(" ".join(str(x) for x in row))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def format_console_lines(feature_maps):
    lines = []
    idx = 0
    for row in range(OUT_H):
        for col in range(OUT_W):
            vals = [feature_maps[out_idx][row][col] for out_idx in range(OUT_NUM)]
            items = [f"PC_L3 idx={idx} row={row} col={col}"]
            for out_idx, val in enumerate(vals):
                items.append(f"out{out_idx}={val}")
            lines.append(" ".join(items))
            idx += 1
    return "\n".join(lines) + "\n"


def format_global_weights(weights):
    return "\n".join(str(x) for x in weights) + "\n"


def main():
    src_maps = build_src_maps()
    weight_maps = build_weight_maps()
    global_weights = build_global_weights(weight_maps)
    feature_maps = calc_feature_maps(src_maps, weight_maps)

    OUT_MATRIX_FILE.write_text(format_all_maps(feature_maps), encoding="ascii")
    OUT_CONSOLE_FILE.write_text(format_console_lines(feature_maps), encoding="ascii")
    OUT_WEIGHT_FILE.write_text(format_global_weights(global_weights), encoding="ascii")

    print(f"matrix out : {OUT_MATRIX_FILE}")
    print(f"line out   : {OUT_CONSOLE_FILE}")
    print(f"weight out : {OUT_WEIGHT_FILE}")
    print(format_console_lines(feature_maps), end="")


if __name__ == "__main__":
    main()
