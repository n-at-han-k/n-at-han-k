#!/usr/bin/env bash
# Converge one of n-at-han-k's gems onto the kettle-jem gem template.
#
#   .github/kettle-jem/converge-repo.sh <clone-dir> <repo-name> <license>
#
# Run by converge-ruby-gems.yml against a fresh clone of the repo's default
# branch. Writes to the clone only — the workflow owns the commit, push and PR.
#
# Modelled on ruby-gtk-project's .github/aw/converge-port-gem.sh, which is
# where every comment below was paid for.
#
# Exit 0 converged, 1 something went wrong that needs fixing, 3 the repo is not
# ready for kettle-jem and needs a change of its own first. 3 is not a failure:
# it is a finding, and the workflow reports it per repo.
#
# kettle-jem needs Ruby >= 4.0 and a bundle pinning prism 1.9.0: it declares
# `prism >= 1.6.0` but calls Prism::Node#breadth_first_search_all, which only
# exists in prism >= 1.9.0. Ruby 4.0.x bundles 1.8.1, so without the pin every
# run dies with NoMethodError. BUNDLE_GEMFILE must already point at that bundle.
set -uo pipefail

CLONE=${1:?usage: converge-repo.sh <clone-dir> <repo-name> <license>}
REPO=${2:?}
LICENSE=${3:?}
KJ=$(cd "$(dirname "$0")" && pwd)

# A compound expression goes in verbatim: it is valid SPDX, it is what the
# project declares, and `spec.licenses = ["A AND B"]` builds. Never assert one
# half, and never substitute a licence for a repo that declares none.
case "$LICENSE" in
  ""|"-"|UNKNOWN|NOASSERTION)
    echo "::error::$REPO has no SPDX licence — add one before converging" >&2
    exit 1
    ;;
esac

# kettle-jem hard-fails with "no gemspec found" (exit 2). A repo without one is
# not a gem, and the workflow filters those out before calling this.
if ! compgen -G "$CLONE/*.gemspec" > /dev/null; then
  echo "::error::$REPO has no gemspec" >&2
  exit 1
fi

# The template rewrites required_ruby_version from config rather than reading
# it, so feed it the project's own floor. A gemspec that cannot be loaded
# (native extension requires, git ls-files) still yields the literal.
min_ruby=$(cd "$CLONE" && ruby -rrubygems -e '
  src = File.read(Dir["*.gemspec"].first)
  m = src[/required_ruby_version\s*=\s*["\x27]>=?\s*([0-9]+\.[0-9]+)/, 1]
  print(m || "")
' 2>/dev/null)
if [ -z "$min_ruby" ]; then
  echo "::error::$REPO gemspec declares no required_ruby_version" >&2
  exit 1
fi

# kettle-jem rewrites its own config, the README and the CHANGELOG on every run
# through recipes that ignore `files: keep_destination`. Re-assert them from git
# afterwards so the next run does not inherit drifted inputs.
PROTECTED=(
  .structuredmerge/kettle-jem.yml
  .structuredmerge/kettle-jem.lock
  README.md
  CHANGELOG.md
  .github/FUNDING.yml
)

# 1. Seed the config, always from this repo's copy, with the licence and the
#    Ruby floor pinned. If `licenses:` is left for kettle-jem to derive,
#    config_sync injects `licenses: [MIT]` and the NEXT run rewrites the
#    gemspec to MIT and drops MIT.md into an Apache-2.0 or LGPL project.
mkdir -p "$CLONE/.structuredmerge"
sed -e "s|{{LICENSE}}|$LICENSE|g" -e "s|{{MIN_RUBY}}|$min_ruby|g" \
  "$KJ/kettle-jem.yml" > "$CLONE/.structuredmerge/kettle-jem.yml"

# 2. The template owns `bindir = exe`, and kettle-jem writes its own dev
#    scripts into bin/. Move every declared executable across, or gem build
#    fails with `["exe/<name>"] are not files`.
for e in $(cd "$CLONE" && ruby -e 'spec = Gem::Specification.load(Dir["*.gemspec"].first); puts spec&.executables' 2>/dev/null); do
  if [ -f "$CLONE/bin/$e" ] && [ ! -e "$CLONE/exe/$e" ]; then
    mkdir -p "$CLONE/exe"
    git -C "$CLONE" mv "bin/$e" "exe/$e" 2>/dev/null || mv "$CLONE/bin/$e" "$CLONE/exe/$e"
    chmod +x "$CLONE/exe/$e"
  fi
done

# 3. Converge. --no-changelog: without it kettle-jem appends its own template
#    changelog entries into the project's CHANGELOG on every run.
#
#    --quiet swallows the reason along with the noise, so capture it: a run
#    that reports "apply failed" and nothing else cannot be acted on.
log=$(mktemp)
if ! kettle-jem apply "$CLONE" --accept --skip-commit --quiet --no-changelog > "$log" 2>&1; then
  # kettle-jem merges spec.files only as an Array literal, a Dir[] call, or a
  # known Bundler git-ls-files assignment, and inserts its own canonical
  # assignment when there is none at all. Anything else — async-matrix's
  # `Dir.glob([...], File::FNM_DOTMATCH, base: __dir__)`, for one — stops it
  # dead. Rewriting it here would change what the gem ships, which is the
  # author's call and not a template's, so this is reported, not fixed.
  if grep -q "Unsupported gemspec spec.files assignment" "$log"; then
    echo "::notice::$REPO: gemspec spec.files is not a shape kettle-jem can merge — rewrite it as an Array literal or Dir[], or remove it and let kettle-jem own it"
    exit 3
  fi
  echo "::error::$REPO: kettle-jem apply failed" >&2
  sed 's/^/  /' "$log" >&2
  exit 1
fi

# 4. Re-assert the recipe-owned paths.
for p in "${PROTECTED[@]}"; do
  git -C "$CLONE" checkout -- "$p" 2>/dev/null || true
done

# 5. Refuse to hand back a repo whose licence moved. A gem's licence is a
#    promise already made to whoever installed it; a template does not get to
#    change it.
if ! grep -q -- "$LICENSE" "$CLONE"/*.gemspec; then
  echo "::error::$REPO gemspec licence is no longer $LICENSE" >&2
  exit 1
fi
for stray in MIT.md AGPL-3.0-only.md PolyForm-Small-Business-1.0.0.md certs/pboling.pem; do
  case "$stray" in "$LICENSE.md") continue ;; esac
  if [ -e "$CLONE/$stray" ]; then
    echo "::error::$REPO: kettle-jem wrote $stray under a $LICENSE licence" >&2
    exit 1
  fi
done

echo "$REPO: converged ($LICENSE, ruby >= $min_ruby)"
