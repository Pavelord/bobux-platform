# Bobux Cloud Releases

The `Bobux Release` GitHub Actions workflow reproduces the local release
pipeline on a clean Windows runner. It builds and validates:

- the 32-bit Windows game package;
- the Windows launcher;
- the signed Android APK for ARMv7 and ARM64;
- launcher and mobile manifests with matching SHA-256 hashes;
- the server hotfix archive and public endpoint health checks.

## Release From A Phone

1. Merge the intended code changes into `main`.
2. Open GitHub mobile or github.com and select
   `Pavelord/bobux-platform`.
3. Open **Actions**, select **Bobux Release**, then choose
   **Run workflow**.
4. Leave version and build fields as `auto` for a normal release.
5. Enter short release notes and enable `deploy_production`.
6. Confirm the production switch. Approve the `production` environment if
   GitHub prompts for it on the repository's current plan.
7. Wait for every build, smoke-test, upload, and endpoint check to become
   green.

The workflow creates a private GitHub Release containing the exact Windows ZIP,
launcher ZIP, Android APK, and manifests that were deployed.

## Safety

- Production only accepts newer PC and Android build numbers by default.
- `allow_redeploy` is for recovery of the same build and should normally remain
  disabled.
- Manifests switch only after all uploaded artifact hashes match.
- SSH host keys are pinned in `.github/bobux_known_hosts`.
- Android signing and SSH private keys live only in the protected GitHub
  `production` environment.
- Never paste a signing key, server password, cookie, or environment secret into
  a Codex prompt, issue, pull request, action input, or repository file.

## Cloud Agent Prompt

Use this after the source change has passed review:

```text
Check the Bobux release readiness on main. Read CODEX.md and
docs/CLOUD_RELEASES.md, confirm Bobux Validate is green, then dispatch the
Bobux Release workflow with automatic version numbers and production deployment.
Do not reveal or replace secrets. Report the workflow URL, resolved versions,
artifact hashes, and endpoint health checks.
```

If GitHub does not expose workflow dispatch to the current cloud surface, open
the repository's Actions tab on the phone and run the workflow there.
