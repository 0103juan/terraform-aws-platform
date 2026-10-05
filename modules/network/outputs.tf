output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "IPv4 range of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Subnets with a route to the internet gateway, one per zone."
  value       = [for zone in var.availability_zones : aws_subnet.public[zone].id]
}

output "private_subnet_ids" {
  description = "Subnets for workloads, one per zone."
  value       = [for zone in var.availability_zones : aws_subnet.private[zone].id]
}

output "database_subnet_ids" {
  description = "Subnets with no route to the internet, one per zone."
  value       = [for zone in var.availability_zones : aws_subnet.database[zone].id]
}

output "nat_public_ips" {
  description = "Addresses the VPC's outbound traffic comes from: what a third party has to allow."
  value       = [for zone in local.nat_zones : aws_eip.nat[zone].public_ip]
}
