# Cutting a release

A release is a `vX.Y.Z` tag. Pushing one runs
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which
builds, signs, notarizes, packages, publishes, and then reads its own work
back. Nothing else needs doing by hand.

Everything below describes what that workflow actually does. If the two ever
disagree, the workflow is right and this file is stale.

## Before you tag

**Bump the version in `project.yml` and commit it.** Both fields:

```yaml
    MARKETING_VERSION: "0.1.1"
    CURRENT_PROJECT_VERSION: "2"
```

`MARKETING_VERSION` is what the tag must match. `CURRENT_PROJECT_VERSION` is
what Sparkle compares to decide whether an installed copy is out of date, so
it has to increase on every release — a build number that stands still means
an update that nobody is offered.

Then:

```bash
git tag v0.1.1
git push origin v0.1.1
```

The first thing the workflow does — before generating the project, before the
tests, before anything is built — is compare the tag against
`MARKETING_VERSION`. They drift when someone bumps one and forgets the other,
and the consequence is not a failed build: it is a release whose feed
advertises a version the app does not report having, so everyone who takes the
update still believes they are out of date and is offered it again forever.

## Approving the run

The job stops and waits. Signing credentials live in a GitHub **environment**
called `release` rather than on the repository, and that environment requires
a human to approve every run.

Approve it from the run's page under **Review deployments**, or:

```bash
gh api --method POST \
  /repos/lardissone/pium/actions/runs/<run-id>/pending_deployments \
  -f 'environment_ids[]=<env-id>' -f state=approved -f comment='release'
```

The prompt is not friction to route around. A release is the thing worth
confirming on purpose, and the same gate is what stops a change merged into a
workflow file from walking off with the signing certificate: reaching those
secrets needs a `v*.*.*` tag *and* somebody saying yes.

## What the workflow produces

Three assets on the GitHub Release:

| Asset | Who reads it |
|---|---|
| `Pium-X.Y.Z.dmg` | A person, downloading Pium for the first time |
| `Pium-X.Y.Z.zip` | Sparkle, installing an update |
| `appcast.xml` | Sparkle, deciding whether there is an update |

The zip is built from the **stapled** app rather than from the DMG's copy, so
a Mac that happens to be offline when it updates still satisfies Gatekeeper
from the stapled ticket instead of needing to reach Apple. The DMG is
notarized and stapled separately, because a disk image is its own container
and Gatekeeper judges it on its own.

## The secrets

Six, all in the `release` environment. None are on the repository, and none
should be put there — a repository secret is readable by every workflow in
the repository, which for a public repo means the workflow naming them is
something anyone can read and fork before deciding what to try.

| Secret | What it is | Where it comes from |
|---|---|---|
| `DEVELOPER_ID_P12` | base64 of the Developer ID Application certificate and its key | Keychain Access → My Certificates → Export |
| `DEVELOPER_ID_P12_PASSWORD` | the password chosen during that export | you, at export time |
| `NOTARY_API_KEY` | the contents of the App Store Connect `.p8` | App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys |
| `NOTARY_KEY_ID` | the key's ten-character identifier | the same screen |
| `NOTARY_ISSUER_ID` | the team's issuer UUID | the same screen |
| `SPARKLE_PRIVATE_KEY` | the EdDSA private key for signing updates | `generate_keys -x <file>`, from the login keychain |

Two notes on the notarization key. It must be a **Team Key** — Apple excludes
individual keys from `notarytool`, and the failure is not obvious. And the
`.p8` downloads exactly once; losing it means revoking the key and issuing
another.

**The Team ID `692T844292` is not a secret** and is written plainly in the
workflow. It is readable in any signed binary, so hiding it would buy nothing
and cost the next reader a lookup.

## Rotating a credential

Two of these expire or can be replaced without ceremony. One cannot.

**The Developer ID certificate** expires — Apple issues them for five years.
Export the new one, set `DEVELOPER_ID_P12` and `DEVELOPER_ID_P12_PASSWORD`
again in the environment. Already-released builds keep working: the signature
on a shipped app is checked against Apple's timestamp, not against whether
the certificate is still current today.

**The notarization key** can be revoked and reissued freely. It authenticates
the submission and nothing else; no shipped artifact depends on it.

**The Sparkle EdDSA key must never be rotated.** Every installed copy of Pium
verifies updates against the public key compiled into it, so a new key means
every existing install rejects every future update — silently, because a
signature that does not verify is indistinguishable to the app from a
tampered download. There is no in-app recovery: the only way back is for each
user to download a fresh copy by hand, and the app cannot tell them to,
because telling them would itself be an update.

Back the private key up somewhere it cannot be lost. Losing it is the same
outcome as rotating it.

If it is ever genuinely compromised, that is a decision with a plan attached
and a release note that tells people to download manually — not a rotation.

## When notarization fails

Read the log rather than guessing. Apple says which file and why:

```bash
xcrun notarytool log <submission-id> \
  --key <path-to-p8> --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
```

The submission id is in the workflow log, on the line beginning `id:`.

Two failures account for most of them:

- **Hardened Runtime missing.** `ENABLE_HARDENED_RUNTIME` is set project-wide
  in `project.yml`, and the workflow asserts it on the exported app before
  submitting, so this should be caught before Apple sees it.
- **A nested component signed with the wrong identity**, or not signed at all
  — usually something inside `Contents/Frameworks`. `codesign --verify
  --strict` on the exported app reproduces it locally.

Notarization rejecting a build is not a signing failure. The app is signed;
Apple is refusing to vouch for it, which happens after the upload rather than
before.

## After it publishes

The workflow already checks the part that matters most: that
`releases/latest/download/appcast.xml` resolves, carries a signature, and
offers the version just tagged. That URL is compiled into every copy of Pium,
and if it stops resolving no installed app reports an error — it finds
nothing, and silence is indistinguishable from there being no news.

The release is published as neither a draft nor a prerelease, deliberately.
GitHub resolves `latest` to neither, so either flag would hide the appcast
from every installed copy while the run itself looked perfectly successful.

What a machine cannot check for you:

1. **Download the DMG from the Releases page** — not from a build directory —
   on a Mac that has never had Pium, and open it. Anything beyond the ordinary
   first-launch prompt is a problem worth stopping for.
2. **Take the update from the previous version.** Install the older release,
   let it find the new one, and watch it through download, install, and
   relaunch.

[`release-checklist.md`](release-checklist.md) is where those results are
recorded, along with what has and has not been walked so far.
