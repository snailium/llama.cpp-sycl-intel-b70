# How to publish this as your community GitHub project

This directory contains a ready-to-publish community project for an updated llama.cpp + SYCL Docker focused on Intel Arc B70.

## Recommended repo name
`llama.cpp-sycl-intel-b70` or `intel-arc-b70-llama.cpp`

## Steps

1. Create a new empty repository on GitHub (public, MIT license recommended).

2. In this directory on your machine, initialize and push:

```bash
cd /path/to/llama-cpp-sycl-intel-b70

git init
git add .
git commit -m "Initial community SYCL Docker for Intel Arc B70

- Updated intel.Dockerfile with recent oneAPI + compute-runtime + IGC pins for B70
- AOT build with -DGGML_SYCL_DEVICE_ARCH=bmg-g31
- All features kept enabled (Flash Attention, MTP, reorder kernels, no GGML_SYCL_DISABLE_OPT)
- B70-specific tuning guide + docker-compose
- CI workflow stub for rebuilding the image"

git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
git push -u origin main
```

3. (Optional) Turn it into a full fork of upstream for easier diffing:

```bash
# One-time: add upstream
git remote add upstream https://github.com/ggml-org/llama.cpp.git
git fetch upstream
# You can periodically merge/rebase main from upstream when you want fresh llama.cpp source
```

4. Enable GitHub Actions so the workflow can build on push (it is set to not push images by default; add a GHCR login secret if you want automatic publishing).

5. Update the README with your repo links, add a LICENSE (MIT is fine — same as upstream).

6. When Intel releases newer compute-runtime / IGC / oneAPI, bump the ARGs in `.devops/intel.Dockerfile`, test on your B70 with Qwen3 27B-class models (flash-attn + MTP), and open a PR or push directly.

## Testing the image locally after push

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
cd YOUR_REPO_NAME
./scripts/build-b70-image.sh server my-b70-image
```

## Notes for long-term maintenance

- The main value is the tuned `intel.Dockerfile` + documentation.
- You can keep the repo small by not vendoring the entire llama.cpp tree (the Dockerfile expects to be built against a llama.cpp source tree; the build context is the llama.cpp checkout).
- Many users will `git clone` the official llama.cpp and build using this Dockerfile from your repo (copy or submodule it).

Good luck — this should give the community a much fresher B70 experience than the stock Intel-tagged images.
