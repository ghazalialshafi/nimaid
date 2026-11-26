# Releasing nimaid (fully automated)

One tag builds, tests and publishes everything: **C API packages, CLI binaries, WebAssembly module, Python wheels, GitHub Release, PyPI and (optionally) npm.**

```sh
python3 tools/bump_version.py 0.5.0        # sets the version in every file (nimble, header, Python, npm, ...)
$EDITOR CHANGELOG.md                        # add a "## [0.5.0] - date" section: it becomes the release notes
git commit -am "Release 0.5.0" && git tag v0.5.0 && git push && git push --tags
```

That's all. The `release` workflow (`.github/workflows/release.yml`) runs on the tag:

| Stage | What happens |
|---|---|
| **check** | tag == version in `nimaid.nimble`; all version strings agree; `CHANGELOG.md` has a section for it |
| **build** (15 jobs in parallel) | for every target: Nim generates C for that exact OS/CPU, **Zig** compiles and links it → C API package (static + shared lib, header, docs), standalone **CLI** (font built in), and for `wasm32-wasi` the **WebAssembly** module + JS wrapper. Each job already runs the C, C++, CLI and wasm test suites where the target can execute |
| **wheels** | `python/build_wheels.py` turns the shared libraries into platform wheels (`manylinux2014`, `musllinux_1_2`, `macosx_11_0`, `win*`) + `nimaid-noto-emoji`; `twine check` |
| **test-native** | on real machines — Linux x86_64 and ARM64, macOS Intel and Apple Silicon, Windows x64 (+ Windows ARM64, non-blocking): unpack the archives, run both CLIs (must agree byte for byte), compile and run the C test suite with `zig cc`, `pip install` the wheel and run the Python tests |
| **test-containers** | manylinux2014 (glibc 2.17, Python 3.8), Alpine (musl), and under QEMU: arm64 and armv7 (Debian + Alpine) and i386 |
| **test-wasm** | the wasm test suite on Node 18, 20 and 22 |
| **release** | *(only if everything above passed)* GitHub Release with all archives, wheels, fonts archive, `SHA256SUMS`; notes from `CHANGELOG.md` |
| **publish-pypi** | uploads the wheels to PyPI |
| **publish-npm** | *(opt-in)* `npm publish` of the wasm package |

A **dry run** (build + all tests, no publishing) is: Actions → release → *Run workflow*. Tick *testpypi* to also upload to TestPyPI.
The lighter `ci` workflow runs on every push and pull request (native Linux build, wasm, wheel, all test suites).

## One-time setup

### 1. PyPI — Trusted Publishing (no tokens)

Add **two** pending publishers (https://pypi.org/manage/account/publishing/ → *Add a new pending publisher*). Trusted Publishing matches one
environment per job, so the two projects use different environment names:

| Field | `nimaid` | `nimaid-noto-emoji` |
|---|---|---|
| Owner | `ghazalialshafi` | `ghazalialshafi` |
| Repository name | `nimaid` | `nimaid` |
| Workflow name | `release.yml` | `release.yml` |
| Environment name | `pypi` | `pypi-emoji` |

Then in GitHub: *Settings → Environments → New environment* — create **`pypi`** and **`pypi-emoji`** (add *required reviewers* if you want a manual approval before each upload).
For TestPyPI do the same at https://test.pypi.org/manage/account/publishing/ with the environments `testpypi` and `testpypi-emoji`.

*Prefer tokens?* Create a PyPI API token and store it as the repository secret `PYPI_API_TOKEN` (TestPyPI: `TEST_PYPI_API_TOKEN`); the workflow uses it when present.

### 2. npm (optional)

Create an npm access token ("Automation") → repository secret **`NPM_TOKEN`**, and set the repository variable **`PUBLISH_NPM`** = `true` (*Settings → Secrets and variables → Actions → Variables*). The package is published as `nimaid` with provenance.

### 3. GitHub

*Settings → Actions → General → Workflow permissions*: leave the default (read); the release job requests `contents: write` itself. Nothing else is needed — `GITHUB_TOKEN` creates the release.

## Running the same build locally

```sh
pip install ziglang==0.17.1           # + Nim >= 2.0
python3 capi/build.py                 # all targets -> capi/dist/  (C API, CLI, wasm)
python3 capi/build.py -t native       # just this machine, with tests
python3 python/build_wheels.py        # wheels -> python/dist/
python3 tools/ci_smoke.py linux-x86_64-gnu     # what the native test jobs run
```

## Notes and troubleshooting

* **Nothing is published unless every test job is green.** Fix the problem, delete the tag (`git push --delete origin v0.5.0; git tag -d v0.5.0`), re-tag.
  PyPI never accepts the same version twice: if only the PyPI step failed, re-run that job (`skip-existing` makes it idempotent); if a wheel was wrong, bump to the next version.
* **Runner labels** (`macos-15-intel`, `ubuntu-24.04-arm`, `windows-11-arm`, ...) change over time: update the `test-native` matrix when GitHub retires one.
  `windows-11-arm` is marked `experimental` and cannot block a release.
* **Versions are pinned**: Nim `2.2.x`, `ziglang==0.17.1` (env at the top of the workflow). Bump deliberately, run the dry run, compare.
* Platforms without a wheel: `linux-riscv64-gnu` and `freebsd-x86_64` have C API + CLI archives but no PyPI wheel.
* macOS binaries are not notarised; browsers add a quarantine flag: `xattr -d com.apple.quarantine nimaid`.
