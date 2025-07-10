# Arch Linux ARM Cloud Image Builder for Lima

This project automates the creation of an Arch Linux ARM (aarch64) cloud image suitable for use with [Lima](https://github.com/lima-vm/lima) on macOS and Linux hosts. It provides scripts to build, convert, and prepare images, and to generate a Lima template for easy VM deployment.

## Prerequisites

- [Lima](https://github.com/lima-vm/lima) installed on your host (macOS or Linux)
- Sufficient disk space (at least 10GB recommended)
- Internet connection (for package downloads)

## Project Structure

- `build.sh` — Main entrypoint. Orchestrates VM setup, image build, and template generation.
- `create-image.sh` — Runs inside a Lima VM. Builds the Arch Linux ARM image, installs packages, and prepares the disk.
- `create-archlinux-template.sh` — Generates a Lima YAML template referencing the latest built image.

## Usage

### 1. Build the Image

Run the main build script from your host (macOS or Linux):

```sh
./build.sh [options]
```

#### Options:

- `-v <version>` or `--version <version>`: Set a custom version suffix for the image filename.
- `-s` or `--sid`: Use a Debian Sid VM as the build environment (default is Ubuntu).
- `-k` or `--kill`: Force delete the existing `build-arch` Lima VM.

Example:

```sh
./build.sh -v 1
```

This will:

- Start (or reuse) a Lima VM named `build-arch`
- Run `create-image.sh` inside the VM to build the Arch Linux ARM image
- Generate a Lima template YAML referencing the new image

If you run `./build.sh` with no options, it will build the default version (version 0).

**Note:** If you reuse a version (e.g., run `./build.sh` or `./build.sh -v 1` again), any previous build files for that version will be deleted before building a new image.

### 2. Use the Image with Lima

After a successful build, a file like `archlinux.yaml` will be created in the project directory. You can start a Lima VM using this template:

```sh
limactl start ./archlinux.yaml
```

This will launch a VM using your custom Arch Linux ARM image.

## Output Files

- Images are saved in `/tmp/lima/output/` (e.g., `.img`, `.qcow2.xz`)
- The Lima template is `archlinux.yaml` in the project directory

## Notes

- The build process requires root privileges inside the build VM for disk and package operations.
- The image includes cloud-init, OpenSSH, and is pre-configured for DHCP networking.
- For troubleshooting, check the console output of each script for error messages.

## License

[MIT](./LICENSE)

## Attribution - Inspiration (Code)

- [mschirrmeister/archlinux-lima](https://github.com/mschirrmeister/archlinux-lima) — Builds for Archlinux Lima images
- [gmanka-containers/archlinuxarm](https://github.com/gmanka-containers/archlinuxarm) — Builds for Archlinux Docker images
