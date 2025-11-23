# outputs.tf

output "web_server_public_ip" {
  description = "The public IP address of the Web Server (EC2)"
  value       = aws_instance.web_server.public_ip
}

output "rds_endpoint" {
  description = "The endpoint address of the RDS database"
  value       = aws_db_instance.portfolio_db.endpoint
}