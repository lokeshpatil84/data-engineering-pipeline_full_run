# Kafka Module Outputs
output "cluster_arn" {
  value = aws_msk_cluster.main.arn
}

output "cluster_name" {
  value = aws_msk_cluster.main.cluster_name
}

output "security_group_id" {
  value = aws_security_group.kafka.id
}

# -----------------------------------------------------------------------------
# MSK Bootstrap Broker Outputs - ENABLED after cluster is ACTIVE
# -----------------------------------------------------------------------------
# These outputs are now available since MSK cluster is ACTIVE
# -----------------------------------------------------------------------------

output "bootstrap_servers" {
  value     = aws_msk_cluster.main.bootstrap_brokers
  sensitive = true
  description = "Plaintext bootstrap brokers (port 9092)"
}

output "bootstrap_brokers_tls" {
  value     = aws_msk_cluster.main.bootstrap_brokers_tls
  sensitive = true
  description = "TLS bootstrap brokers (port 9094) - Use this for TLS auth"
}

output "bootstrap_brokers_sasl_iam" {
  value     = try(aws_msk_cluster.main.bootstrap_brokers_sasl_iam, "")
  sensitive = true
  description = "SASL/IAM bootstrap brokers (port 9098) - Use this for IAM auth"
}

output "zookeeper_connect_string" {
  value     = aws_msk_cluster.main.zookeeper_connect_string
  sensitive = true
}

