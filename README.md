# nay
yay for nix, uses nix-search-cli to to find packages and searches the NUR; Adds to /etc/nixos/configuration.nix and then runs rebuild
Vibecoded, if anyone wants to take this concept and make it properly they can use the name and everything

Claude Text
# nay
Interactive `nix search` + `configuration.nix` editor for NixOS.  
Searches both **nixpkgs** and **NUR** (Nix User Repository), numbered like `yay`.

## What it does

1. Runs `nix search nixpkgs <query> --json` and fetches NUR's search index in parallel
2. Displays numbered results in two labeled sections: `── nixpkgs` and `── NUR`
3. You pick by number (or type an exact attr name)
4. Checks if the package/service already exists in `configuration.nix`
5. Optionally adds to `environment.systemPackages`
6. Optionally adds `services.<name>.enable = true;` (nixpkgs only)
7. Offers to run `sudo nixos-rebuild switch --show-trace` if anything changed

## Installation

```fish
sudo cp nay.fish /usr/local/bin/nay
sudo chmod +x /usr/local/bin/nay
```

Or to your home bin:

```fish
cp nay.fish ~/.local/bin/nay
chmod +x ~/.local/bin/nay
```

## Usage

```fish
nay ripgrep       # search term up front
nay               # prompted interactively
```

Example output:

```
── nixpkgs ───────────────────────────────────────────
  1) ripgrep                           (14.1.1)
       A search tool combining the usability of ag with the raw speed of grep
  2) ripgrep-all                       (0.10.0)
       Ripgrep, but also search in PDFs, E-Books, Office documents, zip, etc.

── NUR ──────────────────────────────────────────────
  3) nur.repos.crazazy.ripgrep-wrap
       A ripgrep wrapper with extra features

Choose number (or type exact attr name, blank to quit): 1

→ Selected: ripgrep (nixpkgs)

Add ripgrep to environment.systemPackages? [y/N] y
✔ Added ripgrep to environment.systemPackages.
Add services.ripgrep.enable = true? [y/N] n

Run 'sudo nixos-rebuild switch --show-trace'? [y/N] y
```

## NUR setup

NUR packages (`nur.repos.X.Y`) require NUR to be configured in your system first.  
See: https://nur.nix-community.org/documentation/

NUR results are shown regardless — the script will remind you if you try to add one.

## Assumptions

- Config is at `/etc/nixos/configuration.nix`
- `environment.systemPackages` uses the standard single-line format:
  ```nix
  environment.systemPackages = with pkgs; [
    ...
  ];
  ```
- Service stubs are inserted before the final `}` of the file
- NUR search requires an internet connection (fetches `https://nur.nix-community.org/index.json`)
- Requires `python3` for JSON parsing (available on any NixOS system)

## Notes

- Duplicate detection: greps for `pkgs.<name>` (nixpkgs) or the full attr (NUR) and `services.<name>`
- Service prompts are skipped for NUR packages (NUR packages rarely expose NixOS services)
- No automatic backup; consider tracking `/etc/nixos/` with git
