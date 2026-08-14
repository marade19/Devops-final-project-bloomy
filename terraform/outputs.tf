output "server_public_ip" {
  value = aws_instance.app_server.public_ip
}

output "server_public_dns" {
  value = aws_instance.app_server.public_dns
}
