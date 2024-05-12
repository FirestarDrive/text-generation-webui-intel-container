# Introduction

This project containerises [oobabooga/text-generation-webui](https://github.com/oobabooga/text-generation-webui)
for use with Intel Arc GPUs, using `python:3.11-slim-bookworm` as the base image and oneAPI v. 2024.1 as the runtime.

## Does this actually work?

I've tested it on Ubuntu 23.10 host with Linux kernel 6.5.0 using in-tree (builtin) drivers
on Intel Arc A770M (the laptop version of the A770) with Podman 4.6. The 6.2 kernel should work too.

### How fast is this?

I haven't done any proper measurements, but quick testing on the `mistral-7b-openorca.Q5_K_M.gguf`
gives me about 12.5 tokens/s on the A770M.

Note that the first generation may be 5-6 times slower (while in the "warmup" phase).

### How do I pass my favorite options to `server.py`?

`server.py` is specified as the `ENTRYPOINT`, not as a `CMD`, so you can just append
your arguments right after the image name. Default is `--listen`.

### Note to rootful Docker users
The container is expected to run rootless (e.g., via Podman) where `root` in the container
translates to a non-`root` user on the host. Rootful Docker users might want to drop privileges
within the container by extending the image and assigning a user.


# Privacy Note

Depending on whether `localhost` is available in your container runtime,
Gradio may attempt to share the UI without the `--share` flag.
You may suppress this behaviour by deny-listing `api.gradio.app`
in your firewall or via `/etc/hosts`.

# Acknowledgments

This project was heavily inspired by [@Atinoda](https://github.com/Atinoda)'s
[dockerisation](https://github.com/Atinoda/text-generation-webui-docker) of Text-Generation-WebUI.
