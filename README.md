# talos-boot-assets

This repository contains a [GitHub Actions](https://docs.github.com/en/actions) workflow that builds [Talos](https://www.talos.dev/) boot assets, using forks of the SideroLabs repos ([pkgs](https://github.com/jfroy/siderolabs-pkgs), [extensions](https://github.com/jfroy/siderolabs-extensions), [talos](https://github.com/jfroy/siderolabs-talos)). It outputs container images to ghcr.io that can be consumed by a custom [Image Factory](https://github.com/jfroy/siderolabs-image-factory) deployment to produce bootable ISOs or installer images to upgrade existing nodes.

Of note, the workflow builds a few custom extensions, and then _appends_ them to the SideroLabs extensions manifest, such that both official SideroLabs extensions and the custom extensions are available.

## Customizations

### Kernel

The pkgs fork upgrades the kernel to the latest stable release and provides a custom configuration with the following general changes compared to the SideroLabs configuration:

- no xen support
- no hyperv support
- AMD support (SEV, IOMMU, etc)
- only Intel and Mellanox network drivers
- only basic EFI fb graphics drivers
- no legacy SATA/PATA/ATA support
- no legacy network protocols
- netkit (for cilium)
- INET diag w/ destroy (for cilium socket lb)

Support for [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html):

- module unloading
- ACPI TAD, PROC AGG, PCI SLOT, HOTPLUG MEM, BGRT, APEI MEM FAIL,
  EXTLOG, CONFIGFS, PFRUT, FHH
- memory hotplug and hotremove
- memory failure
- zone and device private
- pci p2pdma
- virtio mem

### NVIDIA driver extension

The workflow builds the latest production NVIDIA open kernel kernel modules as part of the pkgs build (to use the ephemeral kernel module signing key). The workflow then builds a custom NVIDIA driver container to bundle the kernel modules with the userspace components. Driver containers are managed by the [NVIDIA gpu-operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html). This new custom extension also depends on a new glibc extension which has now been [upstreamed](https://github.com/siderolabs/extensions/pull/473).

### ZFS extension

My ZFS extension is largely similar to the upstream version, but it includes a new tool (`zfs-service`) that handles importing and unmounting all zfs pools following the Talos service lifecycle, and supports encrypted datasets by passing the `-l` flag to `zpool-import` (see [zpool-import.8](https://openzfs.github.io/openzfs-docs/man/master/8/zpool-import.8.html)).

## Running Image Factory

Image Factory is a service by SideroLabs that consumes Talos boot assets and produces bootable media and installer container images based on a schema that essentially specifies the extensions to include and kernel boot arguments. The official instance is at <https://factory.talos.dev>.

My [fork](https://github.com/jfroy/siderolabs-image-factory) includes small patches to pull the installer, imager, and extensions manifest container images from `ghcr.io/jfroy/siderolabs` instead of `ghcr.io/siderolabs`.

To deploy Image Factory, you basically only need a container runtime (e.g. Docker Engine, podman, containerd, etc) and an image registry (e.g. a [distribution](https://github.com/distribution/distribution) instance, a cloud registry) that Image Factory can push to and that your Talos nodes can pull from. You will also need to generate an image cache signing key (e.g. `openssl ecparam -name prime256v1 -genkey -noout -out image-factory.pem`)

If you are going to produce Secure Boot images, you will also need a set of keys (UKI signing key and cert, PCR cert). You may generate those yourself (see [loader.conf.5](https://man.archlinux.org/man/loader.conf.5) for an example), or use `talosctl gen secureboot`.

The command line arguments are somewhat long, but here's my deployment for example:

```sh
/image-factory \
  -cache-repository localhost:5000/cache \
  -cache-signing-key-path /keys/image-factory.pem \
  -container-signature-issuer-regexp (https://token\\.actions\\.githubusercontent\\.com)|(https://accounts\\.google.com) \
  -container-signature-subject-regexp (https://github.com/jfroy/talos-boot-assets/\\.github/workflows/assets\\.yaml@refs/heads/release-.+)|(.+@siderolabs\\.com) \
  -external-url https://<redacted domain>/ \
  -http-port :8080 \
  -image-registry ghcr.io \
  -installer-external-repository <redacted domain>/installer \
  -installer-internal-repository localhost:5000/installer \
  -min-talos-version 1.8.2 \
  -schematic-service-repository localhost:5000/schematics \
  -secureboot \
  -secureboot-pcr-key-path /keys/pcr-signing-key.pem \
  -secureboot-signing-cert-path /keys/uki-signing-cert.pem \
  -secureboot-signing-key-path /keys/uki-signing-key.pem \
  -talos-versions-recheck-interval 1h
```

Note in particular the regular expressions for the container signature. The first group (of each regex) matches what you will get by using `cosign` inside a GitHub Action workflow to perform [identity-based](https://docs.sigstore.dev/cosign/signing/overview/) signing[^1]. The second group matches the signatures produced by SideroLabs for their extensions.

[^1]: See also <https://edu.chainguard.dev/open-source/sigstore/how-to-keyless-sign-a-container-with-sigstore> and <https://edu.chainguard.dev/open-source/sigstore/cosign/an-introduction-to-cosign> for more information.

## AWS buildkit

The workflow uses AWS buildkit spot instance nodes (one for each architecture). The nodes are created on demand using Terraform when the workflow runs. The GitHub Actions worker and the AWS nodes are connected to a tailnet for secure connectivity.

### AWS AMI

The `ami` directory contains a Packer project to build the AMI used by the spot instances. Run `packer build ami/buildkit.pkr.hcl` to build a new set of AMIs (one per architecture). You will need to setup authn per the [Amazon plugin documentation](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon#authentication).
