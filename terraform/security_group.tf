resource "aws_security_group" "app_sg" {
  name        = "devops-final-app-sg"
  description = "Allow SSH and app ports"
  vpc_id      = aws_vpc.main.id

  # SSH access - so you can log into the server
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Portfolio app port
  ingress {
    description = "Portfolio app"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Java app port
  ingress {
    description = "Java app"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (e.g. so the server can download updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devops-final-app-sg"
  }
}
