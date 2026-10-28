output "vpc_id" {
  value = aws_vpc.this.id
}

output "availability_zones" {
  value = local.azs
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "nat_public_ips" {
  description = "Egress IPs of the cluster, for allow-lists on external services."
  value       = aws_eip.nat[*].public_ip
}
