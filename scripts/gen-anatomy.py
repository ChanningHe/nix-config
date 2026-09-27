"""Generate docs/images/Anatomy.svg — a theme-aware anatomy diagram of nix-config.

Usage: python3 scripts/gen-anatomy.py docs/images/Anatomy.svg [light|dark]
The optional theme argument forces one palette (for previews only).
"""
import sys
from html import escape

W, H = 1560, 1460
out = []
emit = out.append

# ---------- colors (light / dark) ----------
THEME = {
    "bg": ("#ffffff", "#0d1117"),
    "fg": ("#1f2328", "#c9d1d9"),
    "muted": ("#656d76", "#8b949e"),
    "panel": ("#8c959f", "#3d444d"),
    "cellfill": ("#f6f8fa", "#161b22"),
    "title": ("#0a6e6e", "#2aa198"),
    "input": ("#57606a", "#6e7f96"),
    "output": ("#4d7a3a", "#7a9a63"),
    "flake": ("#9a6700", "#c9a24a"),
    "p": ("#bc4c00", "#e3883b"),
    "a": ("#0969da", "#3b8eea"),
    "m": ("#bf3989", "#db61a2"),
    "bus": ("#0f8a7a", "#2cc4ad"),
    "wire": ("#6e7781", "#8b949e"),
}
HOSTS = {"p": "Platypus", "a": "Annulatus", "m": "MacBook"}


def css():
    light = ";".join(f"--{k}:{v[0]}" for k, v in THEME.items())
    dark = ";".join(f"--{k}:{v[1]}" for k, v in THEME.items())
    return f"""
  svg{{{light}}}
  @media (prefers-color-scheme: dark){{svg{{{dark}}}}}
  text{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;font-size:12px;fill:var(--fg)}}
  .mono{{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:11.5px}}
  .muted{{fill:var(--muted)}} .small{{font-size:10.5px}}
  .panel{{fill:none;stroke:var(--panel);stroke-width:1.5}}
  .dashed{{stroke-dasharray:6 4}}
  .cell{{fill:var(--cellfill);stroke:var(--panel);stroke-width:1}}
  .ln{{fill:none;stroke-width:2}} .dot{{stroke-dasharray:2 3}}
  .thick{{stroke-width:3.5}}
""" + "".join(
        f"  .s-{k}{{stroke:var(--{k})}} .f-{k}{{fill:var(--{k})}}\n" for k in THEME
    )


# ---------- primitives ----------
def rect(x, y, w, h, cls="panel", rx=4):
    emit(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" class="{cls}"/>')


def text(x, y, s, cls="", anchor="start", extra=""):
    a = f' text-anchor="{anchor}"' if anchor != "start" else ""
    c = f' class="{cls}"' if cls else ""
    emit(f'<text x="{x}" y="{y}"{a}{c}{extra}>{escape(s)}</text>')


def box(x, y, w, h, color, line1, line2, cls="panel"):
    """Two-line labelled box, like the 'Desktop ./hosts/ghost.nix' boxes."""
    emit(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="4" class="{cls} s-{color}"/>')
    if line1:
        text(x + w / 2, y + h / 2 - 3, line1, f"small f-{color}", "middle")
        text(x + w / 2, y + h / 2 + 12, line2, "mono", "middle")
    else:
        text(x + w / 2, y + h / 2 + 4, line2, "mono", "middle")


def tag(x, y, w, h, s, color="title"):
    rect(x, y, w, h)
    text(x + w / 2, y + h / 2 + 4, s, f"mono f-{color}", "middle")


def cell(x, y, w, h, s, users="", color=None):
    rect(x, y, w, h, "cell", 3)
    c = f"mono f-{color}" if color else "mono"
    text(x + 8, y + h / 2 + 4, s, c)
    for i, u in enumerate(reversed(users)):
        emit(f'<circle cx="{x + w - 9 - i * 10}" cy="{y + h / 2}" r="3.5" class="f-{u}"/>')


def path(pts, color, style="", arrow=True):
    d = "M" + " L".join(f"{x},{y}" for x, y in pts)
    m = f' marker-end="url(#ar-{color})"' if arrow else ""
    emit(f'<path d="{d}" class="ln s-{color} {style}"{m}/>')


def grid(x, y, w, cols, items, pitch=32, ch=26, gap=8):
    cw = (w - gap * (cols - 1)) / cols
    for i, it in enumerate(items):
        r, c = divmod(i, cols)
        cell(x + c * (cw + gap), y + r * pitch, cw, ch, *it)
    rows = -(-len(items) // cols)
    return rows * pitch


def sub_box(x, y, w, title, cols, items, dashed=False):
    """Titled container of cells; returns its height so arrows can target it."""
    inner = grid(x + 10, y + 40, w - 20, cols, items)
    h = 40 + inner + 4
    rect(x, y, w, h, "panel dashed" if dashed else "panel")
    tw = len(title) * 7.2 + 20
    tag(x + w - tw, y, tw, 28, title)
    return h


# ---------- document ----------
emit(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
     'role="img" aria-label="nix-config anatomy diagram">')
emit(f"<style>{css()}</style>")
emit("<defs>" + "".join(
    f'<marker id="ar-{k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
    f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="f-{k}"/></marker>'
    for k in ("input", "output", "p", "a", "m", "bus", "wire")) + "</defs>")
emit(f'<rect width="{W}" height="{H}" class="f-bg"/>')

text(W / 2, 58, "ChanningHe's Nix-Config Anatomy", "f-title", "middle",
     ' style="font-size:30px;font-weight:700;text-decoration:underline"')
text(W / 2, 88, "Personal NixOS + Darwin configuration managing a mix of home servers, VMs, and MacOS.",
     "muted", "middle", ' style="font-size:14px"')

# ---------- flake ----------
FX, FY, FW, FH = 575, 260, 340, 850
LDOT, RDOT = FX + 50, FX + FW - 50
emit(f'<rect x="{FX}" y="{FY}" width="{FW}" height="{FH}" rx="60" class="panel s-flake"/>')
text(FX + FW / 2, FY + 48, "flake.nix", "f-flake", "middle", ' style="font-size:22px;font-weight:700"')
text(FX + 20, FY + 88, "inputs = {", "mono f-flake", extra=' style="font-size:15px"')
GX, GY = FX + 40, FY + 105
rect(GX, GY, FW - 80, 140, "panel s-input", 2)
for i in range(12):
    r, c = divmod(i, 4)
    k = "bus" if i == 11 else "input"
    emit(f'<circle cx="{GX + 35 + c * 62}" cy="{GY + 25 + r * 45}" r="16" '
         f'class="f-{k}" stroke="var(--panel)" stroke-width="2" opacity=".85"/>')
text(FX + 20, GY + 170, "};", "mono f-flake", extra=' style="font-size:15px"')
text(FX + 20, GY + 210, "outputs = {", "mono f-flake", extra=' style="font-size:15px"')
text(FX + 20, FY + FH - 30, "};", "mono f-flake", extra=' style="font-size:15px"')


def out_dot(x, y, label, left):
    emit(f'<circle cx="{x}" cy="{y}" r="17" class="f-cellfill s-output" stroke-width="3.5"/>')
    emit(f'<circle cx="{x}" cy="{y}" r="11" class="f-output" opacity=".8"/>')
    if left:
        text(x + 24, y + 4, label, "mono small")
    else:
        text(x - 24, y + 4, label, "mono small", "end")


# ---------- inputs panel ----------
INPUTS = [
    "github:NixOS/nixpkgs/nixos-26.05",
    "github:NixOS/nixpkgs/nixos-unstable",
    "github:nixos/nixpkgs/nixpkgs-26.05-darwin",
    "github:nix-darwin/nix-darwin/nix-darwin-26.05",
    "github:nix-community/home-manager/release-26.05",
    "github:mic92/sops-nix",
    "github:nix-community/disko · nixos-facter-modules",
    "github:serokell/deploy-rs · cachix/git-hooks.nix",
    "github:sodiboo/niri-flake · noctalia-shell · flyline",
    "github:nixos/nixos-hardware · SaumonNet/proxmox-nixos",
    "github:numtide/llm-agents.nix · ChanningHe/nix-vz-builder",
    "git+ssh://github.com/ChanningHe/nix-secrets  (private)",
]
IX, IY, IW = 40, 140, 500
ih = 50 + len(INPUTS) * 36 + 6
rect(IX, IY, IW, ih)
tag(IX + IW / 2 - 80, IY, 160, 30, "Flake URL Inputs")
for i, s in enumerate(INPUTS):
    k = "bus" if i == len(INPUTS) - 1 else "input"
    y = IY + 46 + i * 36
    emit(f'<rect x="{IX + 12}" y="{y}" width="{IW - 24}" height="30" rx="4" class="panel s-{k}"/>')
    text(IX + IW / 2, y + 19, s, f"mono f-{'bus' if k == 'bus' else 'flake'}", "middle")
path([(IX + IW, GY + 70), (GX - 2, GY + 70)], "input", "thick")

# ---------- left outputs → local sources ----------
LOCAL = [
    ("lib", "Custom Lib", "./lib  (relativeToRoot · scanPaths)"),
    ("overlays", "Overlays", "./overlays"),
    ("packages", "Custom Packages", "./pkgs/{common,nixos}"),
    ("formatter", "Formatter", "nixfmt"),
    ("checks", "Checks · pre-commit", "./checks.nix"),
    ("devShells", "Dev Shell", "./shell.nix"),
    ("deploy", "deploy-rs Nodes", "./deploy.nix  (every NixOS host but iso)"),
]
OY0, OP = IY + 50 + len(INPUTS) * 36 + 60, 58
for i, (name, l1, l2) in enumerate(LOCAL):
    y = OY0 + i * OP
    out_dot(LDOT, y, name, True)
    box(245, y - 21, 295, 42, "output", l1, l2)
    path([(LDOT - 18, y), (542, y)], "output", "thick")

# ---------- legend ----------
LX, LY, LW = 40, OY0 - 21, 185
lh = 400
rect(LX, LY, LW, lh, "panel", 0)
text(LX + LW / 2, LY + 22, "Legend", "", "middle")
emit(f'<line x1="{LX}" y1="{LY + 34}" x2="{LX + LW}" y2="{LY + 34}" class="panel"/>')
box(LX + 25, LY + 46, 135, 30, "input", "", "Input")
box(LX + 25, LY + 86, 135, 30, "output", "", "Output")
ly = LY + 140
text(LX + LW / 2, ly, "Required import", "small f-flake", "middle")
for j, k in enumerate("pam"):
    path([(LX + 45, ly + 14 + j * 12), (LX + 140, ly + 14 + j * 12)], k, "", True)
ly += 66
text(LX + LW / 2, ly, "Optional import", "small f-flake", "middle")
for j, k in enumerate("pam"):
    path([(LX + 45, ly + 14 + j * 12), (LX + 140, ly + 14 + j * 12)], k, "dot", True)
ly += 66
text(LX + LW / 2, ly, "hostSpec data bus", "small f-flake", "middle")
path([(LX + 45, ly + 14), (LX + 140, ly + 14)], "bus", "thick")
ly += 38
text(LX + LW / 2, ly, "home-manager wiring", "small f-flake", "middle")
path([(LX + 45, ly + 14), (LX + 140, ly + 14)], "wire", "dashed")
ly += 38
for j, (k, n) in enumerate(HOSTS.items()):
    emit(f'<circle cx="{LX + 30}" cy="{ly + j * 17}" r="4" class="f-{k}"/>')
    text(LX + 42, ly + 4 + j * 17, f"used by {n}", f"small f-{k}")

# ---------- ./modules ----------
MY = OY0 + len(LOCAL) * OP - 5
mw = 500
mh = 40 + grid(LX + 10, MY + 40, mw - 20, 3, [
    ("common/host-spec.nix", "", "bus"), ("hosts/common",), ("hosts/nixos",),
    ("hosts/darwin",), ("home",), ("…",)]) + 26
rect(LX, MY, mw, mh)
tag(LX, MY, 190, 28, "Custom Modules ./modules")
text(LX + 12, MY + mh - 10, "auto-imported via lib.custom.scanPaths from hosts/common/core",
     "small muted")

# ---------- right column geometry ----------
T_NIX, T_DAR, BUS = FX + FW + 18, FX + FW + 30, FX + FW + 44
RX0, RX1 = BUS + 14, 1512
out_dot(RDOT, OY0, "nixosConfigurations", False)
out_dot(RDOT, OY0 + OP, "darwinConfigurations", False)
out_dot(RDOT, OY0 + 2 * OP, "homeConfigurations", False)

# ---------- hosts panel ----------
HY0 = 140
tag(RX1 - 180, HY0, 180, 42, "")
text(RX1 - 90, HY0 + 17, "System Configs", "small f-title", "middle")
text(RX1 - 90, HY0 + 33, "./hosts/{nixos,darwin}", "mono", "middle")
LANE = {"p": RX0 + 12, "a": RX0 + 30, "m": RX0 + 48}
hb = {
    "p": (LANE["p"] - 10, HY0 + 25, 240, "Desktop · NixOS", "./hosts/nixos/Platypus"),
    "a": (LANE["a"] - 10, HY0 + 77, 240, "Server VM · NixOS", "./hosts/nixos/Annulatus"),
    "m": (LANE["m"] - 10, HY0 + 129, 300, "Laptop · nix-darwin", "./hosts/darwin/ChanningdeMacBook-Pro"),
}
for k, (x, y, w, l1, l2) in hb.items():
    box(x, y, w, 42, k, l1, l2)
path([(RDOT + 18, OY0), (T_NIX, OY0), (T_NIX, hb["p"][1] + 21), (hb["p"][0] - 2, hb["p"][1] + 21)], "output")
path([(T_NIX, hb["a"][1] + 21), (hb["a"][0] - 2, hb["a"][1] + 21)], "output")
path([(RDOT + 18, OY0 + OP), (T_DAR, OY0 + OP), (T_DAR, hb["m"][1] + 21), (hb["m"][0] - 2, hb["m"][1] + 21)], "output")
text(RX0 + 60, HY0 + 200, "also: Poecilia · Pseudomugil · Toxotidae · Deissneri · Macrouridae · iso",
     "small muted")

CX0, CX1 = RX0 + 6, RX1 - 6
IN0 = LANE["m"] + 16
IW_ = RX1 - 14 - IN0
cy = HY0 + 222
core_y = cy + 40
core_h = sub_box(IN0, core_y, IW_, "./hosts/common/core", 3, [
    ("default.nix", "pam"), ("platform.nix", "pam"), ("sops.nix", "pam"),
    ("ssh.nix", "pam"), ("openssh-server", "pa"), ("services/ …", "pam")])
users_y = core_y + core_h + 12
users_h = sub_box(IN0, users_y, IW_, "./hosts/common/users", 3, [
    ("channinghe", "pam"), ("rl-man", "a"), ("exampleSecondUser",)])
opt_y = users_y + users_h + 12
opt_h = sub_box(IN0, opt_y, IW_, "./hosts/common/optional", 3, [
    ("systemd-boot", "a"), ("no-firewall", "pa"), ("ip-forward", "pa"),
    ("qemu-guest", "a"), ("rdma/*", "a"), ("nvmeof-client", "a"),
    ("network-storage", "a"), ("attic", "pam"), ("docker", "pa"),
    ("komodo-periphery", "a"), ("rdma-exporter", "a"), ("desktop/ niri", "p"),
    ("audio", "p"), ("steam", "p"), ("darwin/*", "m"),
    ("tailscale", ""), ("incus · podman", ""), ("…", "")], dashed=True)
cont_h = opt_y + opt_h + 10 - cy
rect(CX0, cy, CX1 - CX0, cont_h)
tag(CX1 - 130, cy, 130, 28, "./hosts/common")
rect(RX0, HY0, RX1 - RX0, cy + cont_h + 10 - HY0)

for j, k in enumerate("pam"):
    x = LANE[k]
    top = hb[k][1] + 42
    y_core = core_y + 12 + j * 8
    y_opt = opt_y + 12 + j * 8
    path([(x, top), (x, y_opt)], k, arrow=False)
    path([(x, y_core), (IN0 - 2, y_core)], k)
    path([(x, y_opt), (IN0 - 2, y_opt)], k, "dot")
path([(LANE["a"], users_y + 16), (IN0 - 2, users_y + 16)], "a")

# ---------- data bus ----------
bus_top = 124
bus_y0 = IY + 46 + (len(INPUTS) - 1) * 36 + 15
bus_pts = [(IX + IW - 12, bus_y0), (IX + IW + 18, bus_y0), (IX + IW + 18, bus_top), (BUS, bus_top)]
path(bus_pts, "bus", "thick", arrow=False)
text((IX + IW + BUS) / 2, bus_top - 6,
     "hostSpec ← inherit (inputs.nix-secrets) networkInfo serviceInfo domain email userFullName networking",
     "mono small f-bus", "middle")
path([(BUS, core_y + core_h - 16), (IN0 - 2, core_y + core_h - 16)], "bus", "thick")

# ---------- home panel ----------
HMY = cy + cont_h + 30
tag(RX0, HMY, 170, 42, "")
text(RX0 + 85, HMY + 17, "Home-Manager Configs", "small f-title", "middle")
text(RX0 + 85, HMY + 33, "./home/channinghe", "mono", "middle")
HL = {"p": RX1 - 12, "a": RX1 - 30, "m": RX1 - 48}
hf = {
    "p": (HL["p"] + 10 - 230, HMY + 20, 230, "Platypus", "./home/channinghe/Platypus.nix"),
    "a": (HL["a"] + 10 - 230, HMY + 72, 230, "Annulatus", "./home/channinghe/Annulatus.nix"),
    "m": (HL["m"] + 10 - 340, HMY + 124, 340, "MacBook", "./home/channinghe/ChanningdeMacBook-Pro.nix"),
}
for k, (x, y, w, l1, l2) in hf.items():
    box(x, y, w, 42, k, l1, l2)
gx, gyy = RX0 + 12, HMY + 72
box(gx, gyy, 240, 42, "output", "Standalone · homes.nix", "./home/channinghe/generic.nix")
path([(RDOT + 18, OY0 + 2 * OP), (T_NIX, OY0 + 2 * OP), (T_NIX, gyy + 21), (gx - 2, gyy + 21)], "output")
text(RX0 + 12, HMY + 190, "also: rl-man/nixos-rl.nix · exampleSecondUser · other hosts", "small muted")

# home-manager wiring: users/channinghe → home/<user>/<hostName>.nix
WX = RX1 + 22
path([(RX1 - 14, users_y + 20), (WX, users_y + 20), (WX, hf["m"][1] + 21)], "wire", "dashed", arrow=False)
for k, (x, y, w, *_) in hf.items():
    path([(WX, y + 21), (x + w + 2, y + 21)], "wire", "dashed")
emit(f'<text x="{WX + 14}" y="{(users_y + hf["p"][1]) / 2}" text-anchor="middle" class="mono small muted" '
     f'transform="rotate(90 {WX + 14} {(users_y + hf["p"][1]) / 2})">'
     "home-manager.users → home/${username}/${hostName}.nix</text>")

hcy = HMY + 208
HIN0, HIN1 = RX0 + 16, HL["m"] - 16
hcore_y = hcy + 36
hcore_h = sub_box(HIN0, hcore_y, HIN1 - HIN0, "common/core", 3, [
    ("default.nix", "pam"), ("nixos.nix", "pa"), ("darwin.nix", "m"),
    ("zsh · bash", "pam"), ("git", "pam"), ("neovim", "pam"),
    ("direnv", "pam"), ("yazi", "pam"), ("flyline", "pam"),
    ("fonts", "pam"), ("ssh", "pam"), ("dotfiles", "pam")])
hopt_y = hcore_y + hcore_h + 12
hopt_h = sub_box(HIN0, hopt_y, HIN1 - HIN0, "common/optional", 3, [
    ("browsers", "p"), ("desktops/ niri", "p"), ("media", "p"),
    ("llm-agents", "p"), ("darwin/ssh-*", "m"), ("comms · sops", "")], dashed=True)
rect(RX0 + 6, hcy, RX1 - RX0 - 12, hopt_y + hopt_h + 10 - hcy)
tag(RX0 + 6, hcy, 190, 28, "./home/channinghe/common")
rect(RX0, HMY, RX1 - RX0, hopt_y + hopt_h + 20 - HMY)
for j, k in enumerate("pam"):
    x = HL[k]
    top = hf[k][1] + 42
    y_core = hcore_y + 12 + j * 8
    y_opt = hopt_y + 12 + j * 8
    path([(x, top), (x, y_opt if k != "a" else y_core)], k, arrow=False)
    path([(x, y_core), (HIN1 + 2, y_core)], k)
    if k != "a":
        path([(x, y_opt), (HIN1 + 2, y_opt)], k, "dot")

# bus continues down into home core
path([(BUS, bus_top), (BUS, hcore_y + hcore_h - 16), (HIN0 - 2, hcore_y + hcore_h - 16)], "bus", "thick")

# ---------- footer ----------
text(FX + FW / 2, H - 60, "github.com/ChanningHe/nix-config", "muted", "middle", ' style="font-size:14px"')

emit("</svg>")
svg = "\n".join(out)
if len(sys.argv) > 2 and sys.argv[2] == "light":
    svg = svg.replace("@media (prefers-color-scheme: dark)", "@media not all")
if len(sys.argv) > 2 and sys.argv[2] == "dark":
    svg = svg.replace("@media (prefers-color-scheme: dark){svg{", "@media all{svg{")
open(sys.argv[1], "w").write(svg)
