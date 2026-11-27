# Event-night runbook: Break It / Build It (Nov 27, 2026)

**Doors 18:15. Event credits usable from 18:00.** One command builds everything. A hot standby on the free trial is the fallback.

All numbers below were measured in the trial rehearsal on Nov 26 (see [Measured numbers](#9-measured-numbers)).

---

## How to run the scripts

| Where | Command prefix |
|---|---|
| **Cloud Shell** (shell.cloud.google.com) | `bash hosting/<script>.sh ...` |
| **Laptop, PowerShell** | `& "C:\Program Files\Git\bin\bash.exe" hosting/<script>.sh ...` |
| **Laptop, Git Bash terminal** | `bash hosting/<script>.sh ...` |

> In PowerShell, plain `bash` starts **WSL** (the Podman VM), not Git Bash. It can't see kubectl, helm or your gcloud login. Always use the full Git Bash path above.

Run the deploy, verify and teardown for a given project **from the same machine**. Secrets and the kubeconfig live in that machine's `hosting/generated/<project>/` folder.

---

## 1. Before the day (do these on Nov 27, by 15:00)

- [ ] **Code is reachable.** Commit and push the `hosting/gke-deploy` branch, then make sure you can `git clone` it wherever you'll deploy from (laptop and/or Cloud Shell).
- [ ] **Prerequisites pass** on each machine you might use: `bash hosting/check-prereqs.sh` must print `READY.`
- [ ] **Cloud Shell rehearsal (untested so far).** If you plan to use Cloud Shell on the night, do the daytime cold rehearsal there.
- [ ] **Themed image.** The deploy commands below use the club theme: `ghcr.io/erik-stief/bib-juice-shop:v20.1.1-bib`. That's Brownson's `juice-theme` baked into stock v20.1.1; it's public on erik-stief's GHCR, and an anonymous pull was verified Nov 26. **It must pass the daytime cold rehearsal** (themed pages load, verify + load test pass). If it doesn't, or if a deploy fails at `warm` on the pre-pull, delete the `--juice-image ...` line from the commands: the stock image is proven.
- [ ] **Presenter laptop.** Local Juice Shop v20.1.1 and Build-It (`node buildit/server.js`) work. These are not hosted on GKE.
- [ ] **Hosted Build-It.** `--with-buildit` also puts Ria's Build-It site (the vulnerability web) on its **own public IP**, in *practice mode*: every visitor gets a private copy, **Save** only changes their copy, and **Reset** always returns it to the original vulnerable code. Nothing they do affects anyone else or any Juice Shop. The **live demo** (a fix really restarting Juice Shop) stays on the presenter laptop. Image: `ghcr.io/erik-stief/bib-buildit:v1`. If it causes any trouble, delete `--with-buildit` from the commands; MultiJuicer doesn't depend on it.
- [ ] **Run sheet printed.** Fill it in as you go:

  | | Standby (trial) | Primary (event credits) |
  |---|---|---|
  | Project ID | | |
  | URL | | |
  | Build-It URL | | |
  | Admin passcode | | |
  | Deploy finished at | | |

---

## 2. 16:30: deploy the hot standby (free trial)

Use a **new** project ID each time. IDs are global and can't be reused for 30 days.

Find the trial billing account ID with `gcloud billing accounts list` (format like `012345-6789AB-CDEF01`; it's the one shown as the free trial in the console).

```
bash hosting/deploy.sh --project bibi-standby-1127 --create-project \
  --billing-account <TRIAL_BILLING_ACCOUNT_ID> --instances 65 --machine-type e2-highmem-8 --nodes 1 \
  --juice-image ghcr.io/erik-stief/bib-juice-shop:v20.1.1-bib --with-buildit
```

- **Expected:** about **11–12 min**, ending with `VERIFY: all checks passed` and a banner showing the URL and admin passcode.
- Copy the URL and passcode onto the run sheet.
- **Make QR codes for the standby URL and its Build-It URL.** In Chrome, open the URL, then address bar → Share → Create QR code. Save them on the slide laptop as `standby-qr.png` and `standby-buildit-qr.png`.
- **Keep the banner off the projector**: it shows the admin passcode.
- Cost: about CA$0.50/h of trial credit.

---

## 3. 17:50: positions

- Terminal open on the deploy machine, in the repo folder. `check-prereqs.sh` prints `READY.`
- Logged in (`gcloud auth login`) as **the Google account that will receive the event credits**.
- Second window: the standby URL open in a browser, joined as a test team, so you know it works.
- Slide laptop: standby QR code ready.

---

## 4. 18:00–18:15: event deploy, minute by minute

### 18:00: identify what the credits gave you

Run `gcloud billing accounts list` and `gcloud projects list`.

| What appeared | Command to use (path) |
|---|---|
| A **new billing account** (e.g. "Break It Build It credits") | **Path A**: we create the project |
| A **project** the organizers created for you | **Path B**: adopt it |
| A **coupon code** to redeem | Redeem it in the console (Billing → Credits → Redeem), then `gcloud billing accounts list` again → Path A |

**Path A: new billing account, we create the project**
```
bash hosting/deploy.sh --project bibi-event-1127 --create-project \
  --billing-account <NEW_BILLING_ACCOUNT_ID> --instances 65 --machine-type e2-highmem-8 --nodes 1 \
  --juice-image ghcr.io/erik-stief/bib-juice-shop:v20.1.1-bib --with-buildit
```

**Path B: organizer-made project**
```
bash hosting/deploy.sh --project <THEIR_PROJECT_ID> --adopt-project \
  --instances 65 --machine-type e2-highmem-8 --nodes 1 \
  --juice-image ghcr.io/erik-stief/bib-juice-shop:v20.1.1-bib --with-buildit
```
If Path B fails at `billing` with "no billing account", the project isn't linked to the credits. Add `--billing-account <ID>` from `gcloud billing accounts list`.

`e2-highmem-8 x1` is the exact shape we rehearsed. A new project's default quota (12 vCPUs across all regions) fits it.

### Timeline: start the command by 18:00:30

Durations are the **slowest of the two rehearsals** (671 s and 721 s total). Worst case is about 12.5 min, so every 30 seconds of delay before you press Enter comes straight out of the buffer. Have the command typed and waiting.

| Phase finishes | Slowest measured | Expected clock | **Switch to standby if not done by** |
|---|---|---|---|
| preflight | 29 s | 18:00:59 | 18:02 |
| project | 12 s | 18:01:11 | 18:02:30 |
| billing | 6 s | 18:01:17 | 18:03 |
| apis | 72 s | 18:02:29 | 18:04:30 |
| quota | 8 s | 18:02:37 | 18:05 |
| node-sa | 6 s | 18:02:43 | 18:05:30 |
| **cluster** | **444 s (7.4 min)** | **18:10:07** | **18:11:30** |
| k8s-base + helm | 21 s | 18:10:28 | 18:12 |
| warm (pre-pull + LB) | 114 s | 18:12:22 | 18:13:30 |
| verify | 41 s | 18:13:03 | 18:14 |

- **During `warm`, 5–8 `curl: (28) Connection timed out` retries are normal.** Google needs about 75 s after "Ensured load balancer" before the public IP answers.
- **Need the URL before verify finishes?** It's in `hosting/generated/<project>/deploy-info.env` as soon as `warm` is done.
- **If a phase fails:** the script prints `FAILED in phase: X`. Check [the failure table](#6-failure-table). Re-running the **same command** is safe; finished phases are skipped in seconds.

---

## 5. 18:14: go / no-go

- **GO (primary)** if the banner printed and `VERIFY: all checks passed`. Make a QR code for the primary URL and put it on the slide.
- **Also GO** if at 18:14 `warm` is done, verify is still running, and every line so far is PASS. The remaining checks are isolation probes, not participant-facing. Take the URL from `hosting/generated/<project>/deploy-info.env` and keep an eye on the terminal.
- **NO-GO** if it isn't done or verify shows FAIL lines. Put the **standby QR code** up and open the doors. Keep fixing the primary in the background only if it's nearly done. Never move people between deployments after they start: their progress lives in their instance.
- **Never hold the doors past 18:14 waiting for the primary.** The standby is identical and already verified.

**Presenter tip:** ask everyone to **register their team during the opening talk**. One instance alone is ready in ~12 s. When all 65 register in the same second it's ~66 s typical and 76 s worst case. Registering early hides even that.

---

## 6. Failure table

Root cause first: read the error, run the check, *then* change something.

| Phase | Symptom | Check | Action |
|---|---|---|---|
| preflight | `NOT READY` / FAIL lines | the lines themselves | Wrong shell (see top of page), or `gcloud auth login` |
| project | `not labelled purpose=break-it-build-it` | is it really the event project? | Path B with `--adopt-project` |
| project | `not found or no access` | `gcloud projects list` | Wrong account logged in, or add `--create-project` |
| billing | `no billing account` / permission denied | `gcloud billing accounts list` | Pass the right `--billing-account`; you need Billing Account User on it |
| apis | slow (>2 min) or error | (none) | Re-run the same command |
| quota | `using 1xe2-highmem-4` warning | the `free quota:` line | Fine: capacity 55. Announce "pair up if you're late" |
| quota | `no machine shape fits` | `hosting/generated/<project>/quota.txt` | Quota is unusably low → **standby** |
| cluster | `ZONE_RESOURCE_POOL_EXHAUSTED` / stockout | error text | Re-run with `--zone us-central1-b` (later: `teardown.sh --mode cluster --zone us-central1-a` to remove the failed one) |
| cluster | service account / permission error | error text | The script retries once after 30 s; otherwise re-run |
| cluster | past 18:11 | (none) | **Standby** |
| helm | timeout / pods not Ready | `kubectl -n multi-juicer get pods`, `kubectl -n multi-juicer describe pod <name>`, `kubectl -n multi-juicer get events --sort-by=.lastTimestamp` | Fix the cause from the events, re-run |
| warm | `LoadBalancer IP not assigned` | `kubectl -n multi-juicer describe svc multi-juicer-public` | Usually quota on IN_USE_ADDRESSES; re-run once, else **standby** |
| verify | `cannot resolve ... DNS egress is broken` | (none) | NetworkPolicy DNS rule; solve notifications won't work, but the app does. GO, and tell presenters the scoreboard may lag |
| verify | `expected BLOCKED, got REACHABLE` | which target | Isolation gap. Don't open with this deployment if the standby passes → **standby** |
| warm / verify | anything mentioning **Build-It** | `kubectl -n multi-juicer describe deploy buildit`, `kubectl -n multi-juicer logs deploy/buildit` | Build-It is optional: **GO with MultiJuicer anyway**. Re-run later to retry, or drop `--with-buildit` |
| verify | `team create returned HTTP 500` | `kubectl -n multi-juicer logs deploy/multi-juicer` | Read the log; re-run deploy |

**kubectl access:**
- Git Bash / Cloud Shell: `export KUBECONFIG=hosting/generated/<project>/kubeconfig`
- PowerShell: `$env:KUBECONFIG = "C:\projects\break-it-build-it\hosting\generated\<project>\kubeconfig"`

---

## 7. During the event

- **Admin.** Open the URL and join team **`admin`** with the admin passcode **from the final banner** (also stored in `hosting/generated/<project>/secret-values.yaml`). Ignore the `Password: ${kubectl get secrets ...}` line in the Helm NOTES halfway through the output: that's a lookup command, not a password. The admin page lists every instance, with restart and delete.
- **Stuck instance.** Use Restart in the admin UI, or `kubectl -n multi-juicer delete pod -l team=<teamname>`. Progress is restored automatically by MultiJuicer's progress sync.
- **How many instances exist:** `kubectl -n multi-juicer get deploy -l app.kubernetes.io/name=juice-shop --no-headers | wc -l`
- **"Reached Maximum Instance Count"** means more people came than planned. Re-run the deploy command with `--instances 85`. It only updates the Helm release (~1 min), the node holds up to ~90, and nobody gets logged out (the cookie secret is kept).
- **Load test** against a live deployment: `bash hosting/loadtest.sh --project <project> --teams 10 --cleanup`. Only use it before doors open: it creates real instances.

---

## 8. After the event

1. Tear down the **standby**:
   ```
   bash hosting/teardown.sh --project bibi-standby-1127 --mode project --yes
   ```
2. Tear down the **primary**:
   - Path A (we created it): `bash hosting/teardown.sh --project bibi-event-1127 --mode project --yes`
   - Path B (organizer-owned): `bash hosting/teardown.sh --project <THEIR_PROJECT_ID> --mode cluster --yes`
3. Each must end with a `VERIFIED:` line. Without `--yes`, teardown only lists what exists.
4. Optional: `gcloud auth revoke --all` on any shared machine.
5. Take down the images on erik-stief's GHCR. For each of https://github.com/users/erik-stief/packages/container/bib-juice-shop/settings and https://github.com/users/erik-stief/packages/container/bib-buildit/settings → Danger Zone → **Delete this package**.
6. Next day: Billing → My Billing Account → Reports, grouped by project, to confirm the spend.

---

## 9. Measured numbers

**Two trial rehearsals, Nov 26 2026**, both us-central1-a, cold from an empty project:
- Run 1: `bibi-test-1126a`, 1x e2-highmem-8, stock image.
- Run 2: `bibi-test-1126b`, 1x e2-standard-4, themed image.

| Phase | Run 1 (s) | Run 2 (s) |
|---|---|---|
| preflight | 5 | 29 |
| project (create) | 12 | 12 |
| billing (link) | 6 | 6 |
| apis (enable, cold) | 72 | 62 |
| quota | 8 | 7 |
| node-sa | 6 | 6 |
| cluster | 417 | 444 |
| k8s-base | 6 | 11 |
| helm | 10 | 9 |
| warm (pre-pull + LB propagation) | 114 | 93 |
| verify | 37 (re-run after DNS fix) | 41 |
| **Cold total** | **~11.3 min** | **12.0 min (721 s)** |

**Load test, 65 simultaneous registrations:**
- All 65 joined, became ready, and were served through the balancer.
- Time to ready: min 14.4 s, **p50 66 s**, p95 72–75 s, max 74–76 s.
- A single instance takes ~11–12 s.
- Where the time went: Juice Shop app init ~41 s median under contention. Node CPU peaked at 75%; memory ~9 GiB of 64 GiB (~135 MiB per instance).

**Trial quota (new project):** CPUS (us-central1) 200, **CPUS_ALL_REGIONS 12**, IN_USE_ADDRESSES 8, SSD_TOTAL_GB 250. A new paid project is likely similar, which is why both deploys use 1x e2-highmem-8.

**Versions:**
- MultiJuicer chart and app 10.4.0 (digest `sha256:c23255924aa409b0dc25cbd37a3cb2263a9c6ea61c5287ad371987a306c2abf5`)
- Juice Shop v20.1.1
- GKE 1.36.4-gke.2377000 (regular channel)

**Issues found in rehearsal (all fixed in the scripts):**
1. **PowerShell `bash` is WSL.** `check-prereqs.sh` now detects it and says so.
2. **gcloud fails in Git Bash with `MSYS_NO_PATHCONV=1`.** It's now only set for the `kubectl exec` calls that need it.
3. **GKE's NodeLocal DNSCache (on by default) broke DNS under the NetworkPolicy.** The webhook check failed with `EAI_AGAIN`. Egress to `node-local-dns` pods is now allowed, and `verify.sh` reports DNS failures explicitly.
4. **The LB IP is assigned ~75 s before it serves traffic.** The script retries; this is expected.
