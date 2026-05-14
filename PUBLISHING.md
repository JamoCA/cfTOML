# Publishing cfTOML to ForgeBox

This document describes the steps to publish a new version of cfTOML to ForgeBox.

> **Maintainer note:** ForgeBox publish is a manual, user-driven action. It requires CommandBox authentication and cannot be automated from the implementation tools.

## Pre-publish checklist

1. All Phase 6 tasks complete
2. Test suite passes on at least the primary engine (ACF 2016): `curl http://localhost:8128/tests/runner.cfm | tail -3` shows `0 failed, 0 errors`
3. Engine matrix run completed (`tools/run-engine-matrix.ps1`) - document any engine-specific failures in CHANGELOG. Note: the `server.*.json` engine configs contain `javaHome` values hardcoded to the original maintainer's paths. Before running the matrix, contributors must edit each `server.*.json` to point to their local JDK installations (or remove the `javaHome` key to let CommandBox auto-select).
4. Conformance suite run completed (`tests/conformance/run-conformance.cfm`) - pass rate documented in `tests/conformance/README.md`
5. `box.json` version matches the release version (e.g., `1.0.0`)
6. `CHANGELOG.md` has an entry for the release
7. `README.md` reflects the current API surface
8. All branches merged to `master`
9. Working tree is clean (`git status` shows no uncommitted changes)

## Publish steps

```
# 1. Make sure you're on master with the latest changes
git checkout master
git pull origin master

# 2. Tag the release
git tag -a v1.0.0 -m "cfTOML 1.0.0 release"
git push origin v1.0.0

# 3. Push the tag to GitHub (triggers any release automation)
git push --tags

# 4. (Optional) Create a GitHub release with notes
# Visit https://github.com/jamoCA/cf-toml/releases/new
# Select v1.0.0, copy CHANGELOG entry into the body

# 5. Publish to ForgeBox via CommandBox
box forgebox publish

# Note: Requires ForgeBox login. Run `box forgebox login` first if not already authenticated.
# The publish command zips the project (respecting box.json's "ignore" list) and uploads.
```

## Post-publish

1. Verify the package appears at https://www.forgebox.io/view/cftoml
2. Update the TOML implementations wiki: https://github.com/toml-lang/toml/wiki - add cfTOML to the implementation list with a link to the ForgeBox page and GitHub repo
3. Announce on the user's blog (https://www.mycfml.com/) and any relevant CFML community forums

## Subsequent releases

For patches and feature releases:

1. Bump `box.json` version (semver: `1.0.X` for patches, `1.X.0` for new features, `X.0.0` for breaking changes)
2. Add a new `CHANGELOG.md` entry
3. Commit, tag, push, publish
