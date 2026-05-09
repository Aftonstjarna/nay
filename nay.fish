#!/usr/bin/env fish
# nay - nix search + interactive configuration.nix package/service installer
# searches both nixpkgs and NUR

set config /etc/nixos/configuration.nix

# ── helpers ───────────────────────────────────────────────────────────────────

function nay_err
    echo (set_color red)"✗ $argv"(set_color normal) >&2
end

function nay_ok
    echo (set_color green)"✔ $argv"(set_color normal)
end

function nay_warn
    echo (set_color yellow)"⚠ $argv"(set_color normal)
end

function nay_info
    echo (set_color cyan)"→ $argv"(set_color normal)
end

# ── sanity checks ─────────────────────────────────────────────────────────────

if not test -f $config
    nay_err "Cannot find $config"
    exit 1
end

# ── search ────────────────────────────────────────────────────────────────────

if test (count $argv) -ge 1
    set query $argv[1]
else
    read -P "Search nixpkgs + NUR: " query
end

if test -z "$query"
    nay_err "No search query provided."
    exit 1
end

echo ""
nay_info "Searching nixpkgs for '$query'..."

set nixpkgs_raw (nix search nixpkgs $query --json 2>/dev/null)

set nixpkgs_parsed
if test -n "$nixpkgs_raw"
    set nixpkgs_parsed (echo $nixpkgs_raw | python3 -c "
import json, sys
data = json.load(sys.stdin)
for i, (key, val) in enumerate(data.items(), 1):
    name = key.split('.')[-1]
    version = val.get('version', '')
    desc = val.get('description', '').replace('\n', ' ')
    print(f'{name}\t{version}\t{desc}')
")
end

nay_info "Searching NUR for '$query'..."

set nur_parsed (python3 -c "
import json, re, sys, urllib.request

query = sys.argv[1].lower()
url = 'https://nur.nix-community.org/index.json'

try:
    req = urllib.request.Request(url, headers={'User-Agent': 'nay/1.0'})
    with urllib.request.urlopen(req, timeout=10) as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write(f'NUR unavailable: {e}\n')
    sys.exit(0)

results = []
# Each page entry covers one NUR repo; content is free text with entries like:
#   pkgname-1.2.3 nur.repos.reponame.pkgname Description here
pattern = re.compile(
    r'\S+-[\d][\S]*\s+(nur\.repos\.\S+)\s+([^\n]+?)(?=\s+\S+-[\d]|\s*$)',
    re.DOTALL
)
for page in data:
    content = page.get('content', '')
    for m in pattern.finditer(content):
        attr = m.group(1)
        desc = ' '.join(m.group(2).split())[:100]
        if query in attr.lower() or query in desc.lower():
            results.append((attr, desc))

for attr, desc in results:
    print(f'{attr}\t\t{desc}')
" $query 2>/dev/null)

# ── build combined numbered list ──────────────────────────────────────────────

if test -z "$nixpkgs_parsed" -a -z "$nur_parsed"
    nay_err "No results found for '$query'."
    exit 1
end

echo ""

set pkg_names
set pkg_sources   # "nixpkgs" or "nur"
set counter 0

if test -n "$nixpkgs_parsed"
    echo (set_color brblack)"# ── nixpkgs ─────────────────────────────────────────"(set_color normal)
    for line in $nixpkgs_parsed
        set counter (math $counter + 1)
        set parts (string split \t -- $line)
        set name  $parts[1]
        set ver   $parts[2]
        set desc  $parts[3]
        set -a pkg_names $name
        set -a pkg_sources nixpkgs
        printf "%s%3s)%s %-32s %s(%s)%s\n" \
            (set_color brwhite) $counter (set_color normal) \
            (set_color bryellow)$name(set_color normal) \
            (set_color brblack) $ver (set_color normal)
        if test -n "$desc"
            echo "       $desc"
        end
    end
    echo ""
end

if test -n "$nur_parsed"
    echo (set_color brblack)"# ── NUR ─────────────────────────────────────────────"(set_color normal)
    for line in $nur_parsed
        set counter (math $counter + 1)
        set parts (string split \t -- $line)
        set attr  $parts[1]
        set desc  $parts[3]
        set -a pkg_names $attr
        set -a pkg_sources nur
        printf "%s%3s)%s %-44s\n" \
            (set_color brwhite) $counter (set_color normal) \
            (set_color brmagenta)$attr(set_color normal)
        if test -n "$desc"
            echo "       $desc"
        end
    end
    echo ""
end

# ── pick ──────────────────────────────────────────────────────────────────────

read -P "Choose number (or type exact attr name, blank to quit): " choice

if test -z "$choice"
    nay_info "Nothing to do. Exiting."
    exit 0
end

set source nixpkgs
if string match -qr '^\d+$' $choice
    set num $choice
    if test $num -ge 1 -a $num -le (count $pkg_names)
        set pkg $pkg_names[$num]
        set source $pkg_sources[$num]
    else
        nay_err "Number out of range (1–"(count $pkg_names)")."
        exit 1
    end
else
    set pkg $choice
    # Detect NUR by attr format
    if string match -q 'nur.repos.*' $pkg
        set source nur
    end
end

echo ""
nay_info "Selected: $pkg ($source)"
echo ""

set modified false

# ── systemPackages ────────────────────────────────────────────────────────────

# ── insert + sort helper (embeds into section, re-sorts alphabetically) ───────

function nay_insert_pkg
    set _cfg   $argv[1]
    set _pkg   $argv[2]
    set _sec   $argv[3]   # 'nixpkgs' or 'nur'

    set result (sudo python3 << PYEOF
import re, sys

config_path = "$_cfg"
pkg         = "$_pkg"
section     = "$_sec"

with open(config_path) as f:
    lines = f.readlines()

nixpkgs_label = nur_label = sp_end = None
for i, line in enumerate(lines):
    if re.search(r'#\s*──\s*nixpkgs', line): nixpkgs_label = i
    if re.search(r'#\s*──\s*NUR',     line): nur_label     = i
    if re.search(r'^\s*\];',          line) and nixpkgs_label:
        sp_end = i
        break

if nixpkgs_label is None or sp_end is None:
    print("ERROR: missing section labels in systemPackages block")
    sys.exit(1)

if section == 'nixpkgs':
    sec_start = nixpkgs_label + 1
    sec_end   = nur_label if nur_label else sp_end
elif section == 'nur':
    if nur_label is None:
        print("ERROR: no NUR label found")
        sys.exit(1)
    sec_start = nur_label + 1
    sec_end   = sp_end

sec_lines = lines[sec_start:sec_end]

# Detect indentation
indent = '    '
for l in sec_lines:
    m = re.match(r'^(\s+)\S', l)
    if m:
        indent = m.group(1)
        break

# Already present?
if pkg in ''.join(sec_lines):
    print("ALREADY_EXISTS")
    sys.exit(0)

sec_lines.append(f'{indent}{pkg}\n')

def sort_key(l):
    s = l.strip()
    if not s:             return (2, '')
    if s.startswith('#'): return (1, s.lower())
    return (0, re.sub(r'\s*#.*$', '', s).lower())

sec_lines_sorted = sorted(sec_lines, key=sort_key)

new_lines = lines[:sec_start] + sec_lines_sorted + lines[sec_end:]
with open(config_path, 'w') as f:
    f.writelines(new_lines)

print("OK")
PYEOF)
    echo $result
end

# ── systemPackages ────────────────────────────────────────────────────────────

if grep -q "$pkg" $config
    nay_warn "'$pkg' already present in $config — skipping systemPackages."
else
    read -P "Add $pkg to environment.systemPackages? [y/N] " add_pkg
    if string match -qi "y*" $add_pkg
        if test $source = nur
            nay_warn "NUR packages require NUR to be configured in your flake or channels."
            nay_info "See: https://nur.nix-community.org/documentation/"
        end
        set result (nay_insert_pkg $config $pkg $source)
        switch $result
            case OK
                nay_ok "Added $pkg to environment.systemPackages (sorted)."
                set modified true
            case ALREADY_EXISTS
                nay_warn "'$pkg' already present — skipping."
            case 'ERROR*'
                nay_err $result
                nay_info "Add manually: $pkg"
        end
    end
end

# ── services (nixpkgs only — NUR packages rarely expose services this way) ────

if test $source = nixpkgs
    # Strip any dots to get the base service name
    set svc_name (string replace -a '.' '_' $pkg)
    if grep -q "services\.$pkg\|services\.$svc_name" $config
        nay_warn "'services.$pkg' already exists in $config — skipping."
    else
        read -P "Add services.$pkg.enable = true? [y/N] " add_svc
        if string match -qi "y*" $add_svc
            sudo sed -i '$i\  services.'"$pkg"'.enable = true;' $config
            nay_ok "Added services.$pkg.enable = true."
            set modified true
        end
    end
end

# ── rebuild ───────────────────────────────────────────────────────────────────

if test $modified = true
    echo ""
    read -P "Run 'sudo nixos-rebuild switch --show-trace'? [y/N] " do_rebuild
    if string match -qi "y*" $do_rebuild
        sudo nixos-rebuild switch --show-trace
    else
        nay_info "Skipping rebuild. Run when ready:"
        echo "  sudo nixos-rebuild switch --show-trace"
    end
else
    nay_info "No changes made to $config."
end
