from pathlib import Path


LANE_NUM = 12
IMG_W = 8
IMG_H = 8
K = 2
STRIDE = 2
SHIFT_BITS = 10
OUT_W = ((IMG_W - K) // STRIDE) + 1
OUT_H = ((IMG_H - K) // STRIDE) + 1

BASE_DIR = Path(__file__).resolve().parent
OUT_MATRIX_FILE = BASE_DIR / "l4_top12_feature_map_all.txt"
OUT_CONSOLE_FILE = BASE_DIR / "l4_top12_console_lines.txt"


def build_src_maps():
    src_maps = []
    for lane_idx in range(LANE_NUM):
        one_map = []
        for row in range(IMG_H):
            one_row = []
            for col in range(IMG_W):
                one_row.append((lane_idx * 300) + (row * IMG_W * 12) + (col * 17) - 400)
            one_map.append(one_row)
        src_maps.append(one_map)
    return src_maps


def relu_quant(val):
    if val < 0:
        val = 0
    return val >> SHIFT_BITS


def calc_pool_maps(src_maps):
    pool_maps = []

    for lane_idx in range(LANE_NUM):
        lane_map = []
        for row in range(OUT_H):
            one_row = []
            for col in range(OUT_W):
                vals = [
                    relu_quant(src_maps[lane_idx][(row * STRIDE) + 0][(col * STRIDE) + 0]),
                    relu_quant(src_maps[lane_idx][(row * STRIDE) + 0][(col * STRIDE) + 1]),
                    relu_quant(src_maps[lane_idx][(row * STRIDE) + 1][(col * STRIDE) + 0]),
                    relu_quant(src_maps[lane_idx][(row * STRIDE) + 1][(col * STRIDE) + 1]),
                ]
                one_row.append(max(vals))
            lane_map.append(one_row)
        pool_maps.append(lane_map)

    return pool_maps


def format_all_maps(pool_maps):
    lines = []
    for lane_idx, fmap in enumerate(pool_maps):
        lines.append(f"OUT {lane_idx}")
        for row in fmap:
            lines.append(" ".join(str(x) for x in row))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def format_console_lines(pool_maps):
    lines = []
    idx = 0
    for row in range(OUT_H):
        for col in range(OUT_W):
            vals = [pool_maps[lane_idx][row][col] for lane_idx in range(LANE_NUM)]
            items = [f"PC_L4 idx={idx} row={row} col={col}"]
            for lane_idx, val in enumerate(vals):
                items.append(f"out{lane_idx}={val}")
            lines.append(" ".join(items))
            idx += 1
    return "\n".join(lines) + "\n"


def main():
    src_maps = build_src_maps()
    pool_maps = calc_pool_maps(src_maps)

    OUT_MATRIX_FILE.write_text(format_all_maps(pool_maps), encoding="ascii")
    OUT_CONSOLE_FILE.write_text(format_console_lines(pool_maps), encoding="ascii")

    print(f"matrix out : {OUT_MATRIX_FILE}")
    print(f"line out   : {OUT_CONSOLE_FILE}")
    print(format_console_lines(pool_maps), end="")


if __name__ == "__main__":
    main()
