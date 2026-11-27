# Set up a laptop to run the deploy scripts

This gets a fresh machine able to run `hosting/deploy.sh`, `verify.sh`, `loadtest.sh` and `teardown.sh`.
The event-night steps themselves are in [RUNBOOK.md](RUNBOOK.md).

**Fastest option: skip the laptop setup and use Google Cloud Shell.** It runs in a browser, has every tool
preinstalled, and isn't affected by venue Wi-Fi. Jump to [Cloud Shell](#option-a-cloud-shell-nothing-to-install).

| Platform | Status |
|---|---|
| Cloud Shell | Recommended. Linux with all tools preinstalled |
| Windows + Git Bash | **Tested** (that's what the rehearsals ran on) |
| Linux | Should work (standard GNU tools); untested |
| macOS | **Not supported as-is.** The scripts use GNU `date`/`sort` features and bash 4+. Use Cloud Shell from a Mac |

---

## 1. Get access first (ask the project owner)

The scripts act as **your** Google account. Before you start, the owner of the GCP project you'll deploy to
must add your Google account in **IAM & Admin → IAM → Grant access**:

| You'll run | Role you need |
|---|---|
| `deploy.sh` / `teardown.sh --mode cluster` on an existing project | **Owner** on that project |
| `deploy.sh --create-project ...` (a new project) | Permission to create projects, plus **Billing Account User** on the billing account |
| `teardown.sh --mode project` | **Owner** on the project, plus **Billing Account User** (to unlink billing) |

---

## Option A: Cloud Shell (nothing to install)

1. Open https://shell.cloud.google.com, signed in with the Google account that has access (step 1).
2. Clone the repo and check the tools:
   ```bash
   git clone https://github.com/riaasehgal/break-it-build-it.git
   cd break-it-build-it
   bash hosting/check-prereqs.sh
   ```
3. It must end with `READY.` Cloud Shell is already logged in as you; if the login line fails, run `gcloud auth login`.

Run every command in the runbook as `bash hosting/<script>.sh ...` from the `break-it-build-it` folder.

Cloud Shell keeps your home folder, including `hosting/generated/`, between sessions, but it may time out after
about an hour idle. Re-open it and `cd break-it-build-it` again.

---

## Option B: Windows laptop (tested)

1. **Install the tools.** In PowerShell:
   ```powershell
   winget install Git.Git Google.CloudSDK Helm.Helm
   ```
   Close and reopen the terminal so the new tools are on PATH, then:
   ```powershell
   gcloud components install kubectl gke-gcloud-auth-plugin
   ```
2. **Log in:**
   ```powershell
   gcloud auth login
   ```
   (Optional: `gcloud config set disable_usage_reporting true`.)
3. **Clone the repo:**
   ```powershell
   git clone https://github.com/riaasehgal/break-it-build-it.git
   cd break-it-build-it
   ```
4. **Check:**
   ```powershell
   & "C:\Program Files\Git\bin\bash.exe" hosting/check-prereqs.sh
   ```
   It must end with `READY.`

**Two Windows traps:**
- **Never type plain `bash` in PowerShell.** That starts WSL (a separate Linux VM), which can't see the tools
  or your login. Always use the full Git Bash path above, or open a **Git Bash** terminal and use
  `bash hosting/...` there.
- **Line endings.** If you cloned before Nov 27 14:04, your scripts may have Windows line endings and fail with
  `$'\r': command not found`. Re-clone (or run `git rm --cached -r . && git reset --hard`, which discards local
  edits).

---

## Option C: Linux laptop (should work, untested)

1. Install the Google Cloud CLI (https://cloud.google.com/sdk/docs/install), then:
   ```bash
   gcloud components install kubectl gke-gcloud-auth-plugin
   ```
   (If you installed it with apt, use `sudo apt-get install kubectl google-cloud-cli-gke-gcloud-auth-plugin` instead.)
2. Install Helm 3.8+ (https://helm.sh/docs/intro/install/).
3. Run `gcloud auth login`, clone the repo, and run `bash hosting/check-prereqs.sh` until it prints `READY.`

---

## Important: taking over a deployment someone else started

Each deployment's **admin passcode, cookie secret, kubeconfig and URL** are saved only on the machine that ran
`deploy.sh`, in `hosting/generated/<project>/`. That folder is never committed. On a second laptop:

- **Do not re-run `deploy.sh` for a running deployment without that folder.** It would generate a new admin
  passcode and cookie secret, which **logs every participant out**.
- **Instead, copy the folder** from the original machine, privately (USB stick or direct message, never the
  repo or a public channel), into the same path on your laptop: `hosting/generated/<project>/`.
- Without the folder, read-only help still works:
  ```bash
  gcloud container clusters get-credentials juice --zone us-central1-a --project <project>
  kubectl -n multi-juicer get pods
  ```
  Teardown also works, because it identifies the project by its label:
  `bash hosting/teardown.sh --project <project> --mode project` (dry run first, then add `--yes`).

---

## Optional: offline tests

To run the repo's own test suite (`bash hosting/tests/run-all.sh`) you also need **Docker** (for schema checks and
shellcheck) and **Node.js** (for the Build-It tests). Deploying doesn't need either.
