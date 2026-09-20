# Level Zero version reporting: why the image ships 1.28.6 while CI says 1.32.0

Investigated 2026-09-20, triggered by issue [#18](https://github.com/snailium/llama.cpp-sycl-intel-b70/issues/18) §7.2
and its recurrence in issue [#19](https://github.com/snailium/llama.cpp-sycl-intel-b70/issues/19).
**Status: root-caused, mechanism proven by hash, CI fixed.** A real packaging bug, but a benign one.

## The symptom

Every dev/stable issue body reports the Level Zero version CI derived from the
compute-runtime release notes:

```
**Compute Runtime**: 26.35.39758.10 (paired IGC v2.41.5, L0 1.32.0)
```

But the shipped image does not contain that loader:

```
$ dpkg -l | grep libze1
ii  libze1:amd64   1.28.6-1~26.04~ppa1   oneAPI Level Zero -- share libraries

$ ls -la /usr/lib/x86_64-linux-gnu/libze_loader.so*
lrwxrwxrwx  libze_loader.so.1 -> libze_loader.so.1.28.6
-rw-r--r--  libze_loader.so.1.28.6      (Jun 16 21:12, 1773224 bytes)
```

So "L0 1.32.0" in the issue is **the version CI *intended* to install, not the version that ended up
in the image.** The two are different numbers and the issue body cannot tell them apart.

## It is not the API-vs-loader explanation

The obvious hand-wave is "1.32.0 is the Level Zero *spec* level, 1.28.6 is the *loader* version, they
are different numbering schemes." That is **wrong**, and it is worth stating precisely why, because a
weaker version of it is *half* true and would hide the real bug.

The two numberings do exist — v1.32.0 is built against **spec v1.17.24** while v1.28.6 is built against
**spec v1.15.31** — so "1.32" and "1.17" are genuinely different scales. But that is not the
discrepancy here. The **loader package version and the loader soname move together in lockstep**;
downloading the real v1.32.0 deb proves the package ships the matching soname:

```
$ wget .../level-zero/releases/download/v1.32.0/libze1_1.32.0%2Bu24.04_amd64.deb
$ dpkg-deb -c libze1.deb | grep libze_loader
./usr/lib/x86_64-linux-gnu/libze_loader.so.1 -> libze_loader.so.1.32.0
./usr/lib/x86_64-linux-gnu/libze_loader.so.1.32.0
```

A correctly-installed v1.32.0 deb **would** have produced `libze_loader.so.1.32.0`. It did not. So the
number in the issue body (`L0 1.32.0`) and the soname in the image (`1.28.6`) are the *same* scale —
they are simply two different loader builds, and the image has the wrong one relative to what CI
believed it installed.

## The mechanism (proven)

The image is built from `docker.io/intel/deep-learning-essentials:2026.1.2-devel-ubuntu26.04`.
That base image **already ships Level Zero 1.28.6**:

```
base image:  libze1:amd64      1.28.6-1~26.04~ppa1
             libze-dev:amd64   1.28.6-1~26.04~ppa1
             libze-intel-gpu1  26.22.38646.6-1~26.04~ppa1
loader file: libze_loader.so.1.28.6   (Jun 16 21:12)
```

The Dockerfile installs the CI-selected Level Zero debs in the **build** stage (which compiles the
AOT kernels), and the built image's `libze1` is configured **exactly once**, from the base image:

```
2026-07-24 13:27:51 install libze1:amd64 <none> 1.28.6-1~26.04~ppa1
2026-07-24 13:27:52 status installed libze1:amd64 1.28.6-1~26.04~ppa1
```

There is no second install of a 1.32.0 package. `apt-cache policy libze1` in the final image reports
only `/var/lib/dpkg/status` as the source — no repository, no upgrade path.

### Correction: the earlier "oneDNN displaces the pin" explanation was wrong

An earlier revision of this document claimed the `intel-oneapi-dnnl` install re-resolved its
dependency chain against the base image's `libze1` and displaced the pinned copy. **That is not what
happens**, and it was disproved by direct experiment:

1. Pinning Level Zero 1.32.0 *before* installing `intel-oneapi-dnnl` survives intact —
   `libze1=1.32.0` and `libze_loader.so.1.32.0` both before and after. oneDNN does not downgrade it.
   (There is also no repository offering `libze1` at all — `apt-cache madison libze1` is empty and
   `apt-cache policy` lists only `/var/lib/dpkg/status`, so apt has nothing to resolve it *to*.)
2. The real reason is much simpler: **the `base` stage never had a Level Zero install step.**
   In the `dev` branch Dockerfile, `FROM … AS base` contains just two `RUN`s — the neo driver debs and
   the `intel-oneapi-dnnl` install. The Level Zero pin lives **only in the `build` stage**, where it
   exists for AOT compilation (`ocloc`).

So nothing was ever "overwritten". The final image inherited the base image's loader by omission,
while the issue body reported the *build* stage's pin. The two were never the same thing.

This also explains a long-standing note in the project's own knowledge base:

> base 不需要 libze1/libze-dev (loader 用 base 自带 1.28.6 配新驱动 26.31 实测可用)

That was an accurate observation of the *behaviour* ("the base's loader works"), recorded without
noticing that it was a description of an unintended omission rather than a deliberate choice. The
loader was never consciously selected.

### Hash proof that the shipped loader is the base image's

| Artefact | SHA-256 |
|---|---|
| `libze_loader.so.1.28.6` in **base image** | `d08cf213b06fd5fe83e1d14a21ece3243f1d506222fc7c7f4ce0a6201a6a81d6` |
| `libze_loader.so.1.28.6` in **built image** | `d08cf213b06fd5fe83e1d14a21ece3243f1d506222fc7c7f4ce0a6201a6a81d6` |
| `libze_loader.so.1.32.0` from the **CI-downloaded deb** | `93661120ef96602219c0d86717b0b47380f76693b1d8fef03816bbdae247f455` |

The first two are byte-identical and the third is absent from the image. The 1.32.0 loader is
downloaded, installed, and then displaced — the final image carries the base image's 1.28.6 unchanged.

## What actually differs between 1.28.6 and 1.32.0

"The loader is a thin shim, so it does not matter" is an assertion, not evidence. Measured directly by
extracting both debs and diffing their dynamic symbol tables:

| | 1.28.6 | 1.32.0 |
|---|---|---|
| Loader file size | 1 941 176 B | 1 036 264 B |
| Exported `ze*`/`zes*`/`zel*` symbols | 759 | 832 |
| Spec version (per release notes) | v1.15.31 | v1.17.24 |
| Published | 2026-05-11 | 2026-06-26 |

**The delta is 73 added symbols and 0 removed.** Nothing was deleted or renamed, so this is a strictly
additive, ABI-compatible change — every call a 1.28.6-era client could make still exists in 1.32.0, and
vice versa for everything 1.28.6 offered.

### What the 73 new symbols are

| Group | Count | What it enables |
|---|---|---|
| Graph / executable-graph API (`zeGraph*Ext`, `zeCommandList*GraphExt`, `zeExecutableGraph*`) | 32 | Explicit graph capture + instantiation for reduced launch overhead |
| Tracer callback registrations (`zelTracer*RegisterCallback`) | 32 | Tracing-layer plumbing for the above |
| Device "runtime requirements" query/validate | 6 | `zeDeviceGetRuntimeRequirements{,Key}`, `zeDeviceValidateRuntimeRequirements` |
| Command-list / queue attribute getters | 16 | `GetFlags` / `GetMode` / `GetPriority` / `IsMutable*` |
| Sysman power + RAS | 7 | `zesPowerGetUsage`, `zesPowerGetLimitsExt2`, `zesRas*Exp` |
| Memory ops with parameter structs | 6 | `…WithParameters` variants (copy/fill) |

Note that `zeDeviceGetRuntimeRequirements` and the graph API are **capability queries and optional
extensions** — a client that does not call them is unaffected by their absence. There is no behavioural
change to any pre-existing entry point.

### Why the older file is *larger*

1.28.6 statically links its logging stack; 1.32.0 does not:

| | 1.28.6 | 1.32.0 |
|---|---|---|
| `spdlog` symbols | 750 | 0 |
| `fmt::v10` symbols | 224 | 0 |

This is the v1.30.0 release note *"New logger and remove code bloat"*. The size difference is
**removed logging code, not removed functionality** — it is the opposite of a missing-feature signal.

### Does our workload touch any of the new API?

The SYCL stack does **not** call L0 directly. It goes through Unified Runtime
(`libur_loader.so.0` → `libur_adapter_level_zero.so.0.12.0`, UR 0.12.0 from oneAPI 2026.1), which
resolves every entry point **dynamically** via `dlopen`/`dlsym` — the adapter has *zero* undefined
`ze*` symbols in its dynamic table. That is why a version mismatch degrades quietly instead of failing
to link.

Checked which entry points the UR 0.12.0 adapter actually looks up (539 distinct `ze*` names), and
verified the core surface llama.cpp exercises:

- The 33 core APIs on our path — `zeInit`/`zeInitDrivers`, driver/device/context/queue/command-list
  creation, `zeCommandListAppendLaunchKernel` / `…MemoryCopy` / `…MemoryFill` / `…Barrier`,
  kernel + module creation, events and `zeEventHostSynchronize`, `zeMemAlloc{Device,Shared,Host}`,
  the `zeDeviceGet*Properties` family, `zeMemFree` — are present in **both** 1.28.6 and 1.32.0,
  33 of 33.
- The adapter *probes* for `ze*Graph*Exp` / `zeCommandListBeginGraphCaptureExp` etc., but **those
  symbols exist in neither version** (the graph API shipped under different `*Ext` names). The probe
  fails identically on 1.28.6 and 1.32.0, so graph-based command submission is unavailable either way
  — this is a property of the UR adapter version, not of the loader choice.
- The only genuinely 1.32-only capabilities on the probe list are the `*Ext` graph API and
  `zeEventPoolGetFlags` — optional extensions a client must opt into.

**Conclusion: for this workload the two loaders are functionally equivalent.** The 73 new symbols are
entirely optional capabilities we do not call; every symbol we do call exists in both.

## Impact: benign

The **GPU driver** — `libze_intel_gpu.so.1.17.39758` (`libze-intel-gpu1 26.35.39758.10-0`) — is
correct and current; only the *loader/dispatch* library is older. The loader is a thin,
forward-compatible shim: it resolves entry points and forwards them to the installed driver. A 1.28.6
loader driving a 26.35 driver is a supported combination — the same pairing is what has been serving
production through four promoted builds, with zero `UR_RESULT_ERROR`, no device loss, and no
loader-related failure in any validation run.

The symbol-level evidence above upgrades this from "should be fine" to **"measured to be
equivalent on the exercised surface"**. So this is a **metadata/reporting defect, not a functional
one.** It matters because:

- the issue body is the only build record a future reader has, and it states a version the image
  does not contain;
- if a *future* Level Zero release ever carried a fix that only exists in the loader, CI could
  "pin" it and the image would silently ignore it — the failure would be invisible.

## Fixes (applied 2026-09-20)

The design principle: **do not rely on install order.** Any apt operation can leave a component at a
version other than the one compute-runtime paired it with — including, as here, an omission rather
than an overwrite. So the image now *verifies the whole paired set after all installs finish*, and
repairs whatever drifted.

### 1. Post-install pairing reconciliation — `DONE`

`.devops/intel.Dockerfile`, in the `base` stage after every other install: check whether
`libze_loader.so.${LEVEL_ZERO_VERSION}` exists. If not, report what *is* present and fetch the paired
version; then assert again and fail the build with a diagnostic if it still is not satisfied. This
handles both failure modes — displacement *and* omission — without depending on which line runs last.

Verified against the real defect, building the `base` stage on the unfixed tree:

```
--- reconciling paired dependency versions ---
level-zero loader 1.32.0 absent (have: libze_loader.so.1.28.6); will install the paired version
OK: level-zero loader 1.32.0 present
```

| | before | after |
|---|---|---|
| `dpkg -l libze1` | `1.28.6-1~26.04~ppa1` | **`1.32.0`** |
| `libze_loader.so.1` → | `libze_loader.so.1.28.6` | **`libze_loader.so.1.32.0`** |
| loader bytes / hash | 1773224 / `d08cf213…` | 1036264 / `93661120…` (the real v1.32.0) |

The driver (`libze_intel_gpu.so.1.17.39758`) and oneDNN (`libdnnl.so.3`) are unaffected — confirmed in
the rebuilt base image. The step is **idempotent**: on an image that already satisfies the pair it
prints `ALREADY-SATISFIED` and performs no download, so repeated builds stay fast.

`--allow-downgrades` is required, because the paired version may be older than what the base image
ships (the same reason the driver-deb step already needed it for gmmlib).

### 2. Check the rest of the paired set — `DONE`

The same stage verifies the other three components compute-runtime pins, and fails the build on
mismatch:

```
compute-runtime : 26.35.39758.10-0  (paired: 26.35.39758.10)
IGC             : 2.41.5  (paired: 2.41.5)
gmmlib          : 22.10.0  (paired: 22.10.0)
OK: all paired components verified
```

These three are installed by the driver-deb step and have not been observed to drift, so this is a
*check*, not a repair — but a silent divergence in any of them is exactly the class of bug this
document exists because of. Note the version-string subtlety that cost one build iteration: `IGC_VERSION_FULL`
(`2_2.41.5+22716`) is an *asset filename* fragment and is **not** the installed package version
(`2.41.5`), so the check compares against `IGC_VERSION` with the leading `v` stripped.

### 3. Report the version that is really in the image — `DONE`

`build-dev.yml` and `build-stable.yml` gain a **Verify built image versions** step that runs between
the push and the issue creation. It reads `libze1`'s package version and the loader soname *out of the
built image*, echoes them into the build log, fails the job if they do not match the pin, and feeds
them into the issue body as a new line:

```
**Level Zero**: 1.32.0
**Image actually contains**: libze1 `1.32.0`, loader `libze_loader.so.1.32.0`
```

The issue body can no longer claim a version the image does not contain — which is precisely how this
whole discrepancy went unnoticed: the body reported the *build* stage's pin while the image inherited
the *base* stage's loader. The guard was unit-tested against five cases: correct match, the
original-bug mismatch, empty output, a future version, and a prefix-substring trap (`1.3` vs `1.32.0`,
which correctly does *not* false-pass).

All five paired versions are also written to `/etc/intel-stack-versions` inside the image
(`PAIRED_COMPUTE_RUNTIME` / `PAIRED_IGC` / `PAIRED_GMMLIB` / `PAIRED_LIBZE1` / `PAIRED_LIBZE_LOADER`),
so any pulled image can be interrogated later without re-deriving anything.

### Not done, and why

Dropping the duplicate download entirely (fix option 1 in the original write-up) would be the cleanest
end state, but the runtime stage genuinely needs `intel-oneapi-dnnl` — it is **not** inherited from the
base image (verified) — so the oneAPI install cannot simply be removed. Suppressing the dependency
chain that drags in `libze1` would mean fighting apt's resolver for a library that only two
non-inference consumers link (`libpti.so`, `libmpi_ze_hooks.so`; the UR adapter and `libsycl.so.9`
both resolve L0 dynamically via `dlopen` and need no link-time dependency). Installing the pin last
achieves the same guarantee with far less risk, so that is what shipped.

**These fixes change what future images contain, not any already-built image.** The promoted `stable`
digest `sha256:d7f30320…` and the dev artifact `sha256:4dc70c03…` both still carry loader 1.28.6, and —
per the equivalence measurement above — neither needs to be rebuilt or re-tested for that reason.

## Reference: current pairing

| Layer | Version | Where it comes from |
|---|---|---|
| Driver (`libze_intel_gpu`) | `26.35.39758.10` | CI, from compute-runtime release — **correct** |
| Loader (`libze_loader`) | `1.28.6-1~26.04~ppa1` | base image `intel/deep-learning-essentials:2026.1.2-devel-ubuntu26.04` |
| IGC | `2.41.5+1788943183` | CI, from compute-runtime — **correct** |
| Compute-runtime release notes claim | `level-zero@v1.32.0` | `intel/compute-runtime` release body |
| UR adapter (L0 consumer) | `libur_adapter_level_zero.so.0.12.0` | oneAPI 2026.1 |

Note the last row: the component that actually consumes L0 is pinned by the **oneAPI base image**, not
by the compute-runtime pin, and it is this adapter — not our code — that determines which L0 entry
points are probed. Changing the loader alone would not change which capabilities are reachable unless
the UR adapter also opts into them.
