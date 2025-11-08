packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

# Common builder configuration
locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  common_tags = {
    Created     = local.timestamp
    Environment = "production"
    Name        = "buildkit"
  }
}

# amd64 Builder
source "amazon-ebs" "buildkit-amd64" {
  ami_name              = "buildkit-amd64"
  force_delete_snapshot = true
  force_deregister      = true
  instance_type         = "t2.micro"
  region                = var.region
  source_ami            = "ami-0f84105987952c5fd" # Amazon Linux 2023 kernel-6.12 amd64
  ssh_username          = "ec2-user"
  tags                  = merge(local.common_tags, { Architecture = "amd64" })
}

# arm64 Builder
source "amazon-ebs" "buildkit-arm64" {
  ami_name              = "buildkit-arm64"
  force_delete_snapshot = true
  force_deregister      = true
  instance_type         = "t4g.micro"
  region                = var.region
  source_ami            = "ami-0e85b2ec3600b7f4d" # Amazon Linux 2023 kernel-6.12 arm64
  ssh_username          = "ec2-user"
  tags                  = merge(local.common_tags, { Architecture = "arm64" })
}

# Build configuration
build {
  sources = [
    "source.amazon-ebs.buildkit-amd64",
    "source.amazon-ebs.buildkit-arm64"
  ]

  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y containerd git",
    ]
  }

  provisioner "shell" {
    inline = [<<EOF
BUILDKIT_VERSION=0.25.2
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    BUILDKIT_FILE="buildkit-v$BUILDKIT_VERSION.linux-amd64.tar.gz"
    ;;
  aarch64)
    BUILDKIT_FILE="buildkit-v$BUILDKIT_VERSION.linux-arm64.tar.gz"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac
sudo curl -sSL "https://github.com/moby/buildkit/releases/download/v$BUILDKIT_VERSION/$BUILDKIT_FILE" -o buildkit.tar.gz
sudo tar -xzf buildkit.tar.gz -C /usr/local/bin --strip-components=1
      EOF
    ]
  }
  provisioner "shell" {
    inline = ["curl -fsSL https://tailscale.com/install.sh | sudo sh"]
  }

  provisioner "file" {
    source      = "ami/buildkitd.service"
    destination = "/tmp/buildkitd.service"
  }

  provisioner "file" {
    source      = "ami/buildkitd.toml"
    destination = "/tmp/buildkitd.toml"
  }

  provisioner "file" {
    content     = <<EOF
FLAGS="--state mem:"
PORT="0"
EOF
    destination = "/tmp/tailscaled"
  }

  provisioner "shell" {
    inline = [
      "sudo systemctl stop tailscaled.service",
      "sudo mv /tmp/tailscaled /etc/default/tailscaled",
      "sudo rm -rf /var/lib/tailscale",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/buildkit",
      "sudo mv /tmp/buildkitd.toml /etc/buildkit/buildkitd.toml",
      "sudo mv /tmp/buildkitd.service /etc/systemd/system/buildkitd.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable buildkitd"
    ]
  }
}
