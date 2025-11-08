data "aws_ami" "amd64" {
  most_recent = true

  filter {
    name   = "name"
    values = ["buildkit-amd64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["self"]
}

data "aws_ami" "arm64" {
  most_recent = true

  filter {
    name   = "name"
    values = ["buildkit-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  owners = ["self"]
}

resource "aws_secretsmanager_secret" "buildkit" {
  name_prefix = "buildkit-"
}

resource "aws_secretsmanager_secret_version" "buildkit" {
  secret_id     = aws_secretsmanager_secret.buildkit.id
  secret_string = var.ts_auth_key
}

resource "aws_launch_template" "amd64" {
  name     = "buildkit-amd64"
  image_id = data.aws_ami.amd64.id

  instance_requirements {
    bare_metal = "excluded"

    vcpu_count {
      min = 32
      max = 64
    }

    memory_mib {
      min = 32768
      max = 65536
    }
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 80
      volume_type = "gp3"
    }
  }

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.security_group_id]
  }

  tags = {
    Name = "buildkit-amd64"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "buildkit-amd64"
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    ts_auth_key="$(aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.buildkit.arn} --query SecretString --output text)"
    tailscale up --authkey "$ts_auth_key" --ssh --timeout 10s
  EOF
  )
}

resource "aws_launch_template" "arm64" {
  name     = "buildkit-arm64"
  image_id = data.aws_ami.arm64.id

  instance_requirements {
    bare_metal = "excluded"

    vcpu_count {
      min = 32
      max = 64
    }

    memory_mib {
      min = 32768
      max = 65536
    }
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 80
      volume_type = "gp3"
    }
  }

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.security_group_id]
  }

  tags = {
    Name = "buildkit-arm64"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "buildkit-arm64"
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    ts_auth_key="$(aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.buildkit.arn} --query SecretString --output text)"
    tailscale up --authkey "$ts_auth_key" --ssh --timeout 10s
  EOF
  )
}

resource "aws_autoscaling_group" "amd64" {
  name = "buildkit-amd64"

  desired_capacity = 1
  max_size         = 1
  min_size         = 1

  vpc_zone_identifier = var.subnet_ids

  mixed_instances_policy {
    instances_distribution {
      on_demand_percentage_above_base_capacity = 100
      spot_allocation_strategy                 = "lowest-price"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.amd64.id
        version            = "$Latest"
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "buildkit-amd64"
    propagate_at_launch = true
  }

  depends_on = [var.route_table_association]
}

resource "aws_autoscaling_group" "arm64" {
  name = "buildkit-arm64"

  desired_capacity = 1
  max_size         = 1
  min_size         = 1

  vpc_zone_identifier = var.subnet_ids

  mixed_instances_policy {
    instances_distribution {
      on_demand_percentage_above_base_capacity = 100
      spot_allocation_strategy                 = "lowest-price"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.arm64.id
        version            = "$Latest"
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "buildkit-arm64"
    propagate_at_launch = true
  }

  depends_on = [var.route_table_association]
}

data "aws_instances" "amd64" {
  filter {
    name   = "tag:Name"
    values = ["buildkit-amd64"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  depends_on = [aws_autoscaling_group.amd64]
}

data "aws_instances" "arm64" {
  filter {
    name   = "tag:Name"
    values = ["buildkit-arm64"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  depends_on = [aws_autoscaling_group.arm64]
}
