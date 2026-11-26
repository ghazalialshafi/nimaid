> **Automated:** pushing a version tag does all of this in GitHub Actions (see `docs/releasing.md`). The manual steps below remain valid.

# Building and releasing the Python wheels

```sh
pip install ziglang                       # + Nim >= 2.0
python3 capi/build.py                     # 1. cross-compile the native library for every target  -> capi/dist/
python3 python/build_wheels.py            # 2. assemble the wheels                                 -> python/dist/*.whl
pip install twine
twine check python/dist/*                 # 3. validate metadata
twine upload python/dist/*                # 4. upload (token: https://pypi.org/manage/account/token/)
```

* Upload **`nimaid-noto-emoji` first** (or together): `pip install "nimaid[emoji]"` depends on it.
* The version is `__version__` in `src/nimaid/__init__.py`; `build_wheels.py` refuses to run unless it equals the version in `nimaid.nimble`
  (and the C header). Bump all three together, then rebuild everything.
* Try on TestPyPI first: `twine upload --repository testpypi python/dist/*`, then
  `pip install -i https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple "nimaid[emoji]"`.
* Wheels are `py3-none-<platform>`: one wheel serves every Python ≥ 3.8 (ctypes, no compiled extension module).
  There is deliberately **no sdist**: the native library cannot be built by pip. Users on other platforms get a clear
  "no matching distribution" error; they can build the C API themselves and set `NIMAID_LIB`.
* Test an installed wheel: `pip install dist/<wheel>.whl && python -m unittest discover -s python/tests -v`
  (set `NIMAID_TEST_FONT=fonts/DejaVuSans.ttf` for the extra font test).

| Wheel platform tag | from capi target |
|---|---|
| `manylinux_2_17_{x86_64,aarch64,armv7l,i686}` (+ `manylinux2014_*`) | `linux-*-gnu` (built against glibc 2.17) |
| `musllinux_1_2_{x86_64,aarch64,armv7l}` | `linux-*-musl` |
| `macosx_11_0_{x86_64,arm64}` | `macos-*` |
| `win_amd64`, `win_arm64`, `win32` | `windows-*` |

Not published as wheels: `linux-riscv64-gnu`, `freebsd-x86_64`.
