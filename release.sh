#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

REPO=Gh05d/ash-and-steel-fair-combat
VERSION=$(grep -oP 'local VERSION = "\K[^"]+' mod/FairCombat/Scripts/main.lua)
TAG="v${VERSION}"
ZIP="dist/FairCombat-${VERSION}.zip"

echo "Preparing release: Fair Combat ${TAG}"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "ERROR: Tag ${TAG} already exists. Bump VERSION in mod/FairCombat/Scripts/main.lua first."
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: Working tree is dirty. Commit or stash changes first."
    exit 1
fi

echo "Pushing to origin..."
git push origin master

echo "Building zip..."
python3 scripts/package.py

if [ ! -f "$ZIP" ]; then
    echo "ERROR: Expected zip not found at ${ZIP}"
    exit 1
fi
echo "Release artifact: ${ZIP} ($(du -h "$ZIP" | cut -f1))"

git tag -a "$TAG" -m "Release ${TAG}"
git push origin "$TAG"

echo "Creating GitHub release..."
gh release create "$TAG" "$ZIP" \
    --repo "$REPO" \
    --title "Fair Combat ${TAG}" \
    --notes "$(cat <<NOTES
## Fair Combat ${TAG}

Ends stunlock chains in Of Ash and Steel and gives enemies a Souls-like rhythm: after a stagger or knockdown you get a moment to recover, the enemy who hit you lands one follow-up and then waits, only one melee enemy attacks at a time while the others circle you, enemies commit to their attack direction, the fastest wind-ups are readable, and your melee hits land with a short hit stop and louder hit sounds. Works for humans and animals.

### New in 1.0.1
- **Parry out of a stagger:** once a stagger has run for 0.55 s, pressing parry ends it and you parry (\`parryCancel\` in \`Scripts/config.lua\`, \`false\` turns it off). Attacking and dodging still wait until the stagger is over, knockdowns are not affected.

### Installation
1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest) (experimental build) into \`ofAshAndSteelGame/Binaries/Win64/\`
2. Extract \`FairCombat-${VERSION}.zip\` into the game folder \`ofAshAndSteel/\`
3. Steam Deck / Linux: launch option \`WINEDLLOVERRIDES="dwmapi=n,b" %command%\`
NOTES
)"

echo ""
echo "Release ${TAG} published!"
echo "  GitHub: https://github.com/${REPO}/releases/tag/${TAG}"
echo "Nexus Mods upload will be triggered automatically via GitHub Actions."
