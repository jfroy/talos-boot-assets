data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

resource "aws_vpc" "buildkit" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "buildkit"
  }
}

resource "aws_subnet" "buildkit" {
  count = length(data.aws_availability_zones.available.names)

  vpc_id                              = aws_vpc.buildkit.id
  cidr_block                          = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone                   = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch             = true
  private_dns_hostname_type_on_launch = "resource-name"

  tags = {
    Name = "buildkit-${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_internet_gateway" "buildkit" {
  vpc_id = aws_vpc.buildkit.id

  tags = {
    Name = "buildkit"
  }
}

resource "aws_route_table" "buildkit" {
  vpc_id = aws_vpc.buildkit.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.buildkit.id
  }

  tags = {
    Name = "buildkit"
  }
}

resource "aws_route_table_association" "buildkit" {
  count          = length(aws_subnet.buildkit)
  subnet_id      = aws_subnet.buildkit[count.index].id
  route_table_id = aws_route_table.buildkit.id
}
