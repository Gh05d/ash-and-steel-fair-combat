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

### New in 1.0.3
- **Fixes the stutter of 1.0.2:** the game froze for about a quarter second every 1.5 s, most visible while walking. 1.0.2 kept searching for two animal attacks whose AI was not loaded yet; the mod now hooks them when the game loads them.

### New in 1.0.2
- **Animals get no follow-up:** the animal that staggered you no longer bites again while you stagger, it waits until you have recovered (\`animalFollowUp\` in \`Scripts/config.lua\`, \`true\` brings the follow-up back).
- **Waiting animals really wait:** an animal that was told to wait could still slip in a bite when its own taunt or dodge ended, and rats, gnus and others started jumps and heavy attacks while waiting. Both are fixed.
- **No taunting on the brink:** a human enemy at 30 % health or less raises their guard instead of taunting you (\`lowHealthGuard\`, \`false\` turns it off).

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
