# Authenticated fork updates

This fork (Oriel) checks `tosiabunio/Oriel` releases. An update can be installed
inside Oriel only when it has a manifest and Ed25519 signature verified against the
public key bundled in the app. Unsigned releases offer their release page instead.

Each release contains three assets:

- `Oriel-<version>.dmg`
- `Oriel-<version>.manifest.json`
- `Oriel-<version>.manifest.sig` (the 64-byte signature of the exact manifest bytes)

Up to 2026.10.5 the files kept the original name, `OriCmd-<version>…`, which
installs from 2026.10.4 and earlier look for; the image holds `Oriel.app`. The updater installs it in place of the running
app, renaming an `OriCmd.app` to `Oriel.app` unless another `Oriel.app` is there.

From 2026.10.5 the updater also accepts files named `Oriel-<version>…` and an app
with the fork's own bundle identifier, `io.github.tosiabunio.oriel` (the signed
manifest names it, and the app in the image must have it), so that a later release
can move the app to its own identity. `release.sh` signs the identifier of the app
it built. From 2026.10.6 the app is `io.github.tosiabunio.oriel`, its files are named
`Oriel-<version>…` and the repository is `tosiabunio/Oriel` (`tosiabunio/OriCmd`
before; GitHub redirects the old address). The signed manifest names the repository
too, so installs of 2026.10.5 and earlier refuse these releases: they are installed
by hand, once.

The signed manifest names the repository, version, disk image, bundle identifier,
SHA-256 digest and byte count. Oriel verifies the signature before decoding the
manifest, limits metadata and download sizes, and checks the downloaded image
before mounting it. It also verifies the app's bundle signature and requires its
version to match the signed version exactly.

## Signing key

The public key is in `OriCmd/UpdateSigningPublicKey.txt`. The initial private key
was generated locally and preserved in the primary checkout at
`build/update-signing/private.key`, with permissions 0600. A copy is also kept in
the `authenticated-updates` worktree at the same relative path. It is ignored by Git and
is never an app resource or release asset. Preserve a secure backup before
cleaning build folders; losing this key prevents signing updates for installed
copies that trust its public key.

For a new fork with no key yet:

```sh
scripts/build-update-signer.sh
build/update-signer keygen build/update-signing/private.key OriCmd/UpdateSigningPublicKey.txt
```

Key generation refuses to overwrite either an existing private key or public key.
Changing the public key requires a trusted app update or manual installation; do
not generate a replacement key as part of a normal release.

## Preparing a release

Fork releases use `YEAR.MONTH.RELEASE`, starting with `2026.10.0`. Increase the
last component for each release in the same month and start at 0 for the first
release of a new month. Months have no leading zero (`2027.1.0`). The release
script accepts the current version or a newer one, and rejects older versions
and legacy upstream numbering. The internal build number continues increasing.
Record imported upstream versions and commits separately in the release notes;
an upstream import does not change the fork's version.

The release script targets the fork and uploads all three signed assets. It does
not update the upstream Homebrew tap. Set `ORICMD_UPDATE_SIGNING_KEY` to the private
key's location when publishing from another worktree or using a backed-up key.

```sh
ORICMD_UPDATE_SIGNING_KEY=/secure/path/private.key scripts/release.sh 2026.10.0 notes.md
```

That command commits, tags, pushes and publishes a release. Preparation during
development is limited to editing and testing the scripts; publishing requires
the user's explicit instruction under the repository conventions.

To sign an already-built image without publishing:

```sh
scripts/build-update-signer.sh
build/update-signer sign /secure/path/private.key OriCmd/UpdateSigningPublicKey.txt \
  build/Oriel-2026.10.0.dmg tosiabunio/Oriel 2026.10.0 io.github.tosiabunio.oriel
```

The signer refuses a private key that does not match the app's public key. Run
`scripts/test/update-auth.sh` to test genuine updates, tampered metadata and
images, wrong publishers, mismatched release metadata and cancellation. These
tests generate disposable keys and never read the real private key.
