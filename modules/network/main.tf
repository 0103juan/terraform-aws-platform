# A VPC with three tiers of subnets per availability zone:
#   public    load balancers and NAT gateways; the only tier with a route to the internet gateway
#   private   workloads; they reach the internet through NAT and are not reachable from it
#   database  data stores; no route to the internet in either direction

locals {
  # A /16 split into /20s: 0-3 public, 4-7 private, 8-11 database. Room for four zones per tier.
  subnets = {
    for index, zone in var.availability_zones : zone => {
      public   = cidrsubnet(var.cidr, 4, index)
      private  = cidrsubnet(var.cidr, 4, index + 4)
      database = cidrsubnet(var.cidr, 4, index + 8)
    }
  }
  # One NAT gateway is a single point of failure and a third of the price; production takes one per zone.
  nat_zones = var.single_nat_gateway ? [var.availability_zones[0]] : var.availability_zones
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

# The default security group allows everything between its members. Emptied, so that nothing can rely on it.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-default-unused" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

resource "aws_subnet" "public" {
  for_each          = local.subnets
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.public
  tags              = merge(var.public_subnet_tags, { Name = "${var.name}-public-${each.key}", Tier = "public" })
}

resource "aws_subnet" "private" {
  for_each          = local.subnets
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.private
  tags              = merge(var.private_subnet_tags, { Name = "${var.name}-private-${each.key}", Tier = "private" })
}

resource "aws_subnet" "database" {
  for_each          = local.subnets
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.database
  tags              = { Name = "${var.name}-database-${each.key}", Tier = "database" }
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_zones)
  domain   = "vpc"
  tags     = { Name = "${var.name}-nat-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.nat_zones)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = { Name = "${var.name}-${each.key}" }
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# One private route table per zone, so that each zone leaves through its own NAT gateway when there is one.
resource "aws_route_table" "private" {
  for_each = local.subnets
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-private-${each.key}" }
}

resource "aws_route" "private_nat" {
  for_each               = local.subnets
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? local.nat_zones[0] : each.key].id
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-database" }
}

resource "aws_route_table_association" "database" {
  for_each       = aws_subnet.database
  subnet_id      = each.value.id
  route_table_id = aws_route_table.database.id
}

# A gateway endpoint costs nothing and keeps S3 traffic (image layers, backups) off the NAT gateway's meter.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([for table in aws_route_table.private : table.id], [aws_route_table.database.id])
  tags              = { Name = "${var.name}-s3" }
}

# Flow logs: who talked to whom, kept for a bounded time. What an incident review asks for first.
resource "aws_cloudwatch_log_group" "flow" {
  name              = "/vpc/${var.name}/flow"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.log_kms_key_arn
}

resource "aws_iam_role" "flow" {
  name = "${var.name}-vpc-flow-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flow" {
  name = "write-flow-logs"
  role = aws_iam_role.flow.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow.arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow.arn
  iam_role_arn         = aws_iam_role.flow.arn
}
