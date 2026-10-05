output "cluster_name" {
  description = "Name of the cluster."
  value       = aws_eks_cluster.this.name
}

output "endpoint" {
  description = "URL of the Kubernetes API."
  value       = aws_eks_cluster.this.endpoint
}

output "certificate_authority" {
  description = "Base64 certificate authority of the cluster, for a kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group EKS puts on the control plane and on every managed node: the one to allow in a database's or a cache's rules."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
