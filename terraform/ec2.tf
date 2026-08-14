# Upload your public key to AWS so you can SSH in
resource "aws_key_pair" "deployer" {
  key_name   = "devops-final-key"
  public_key = file("${path.module}/devops-key.pub")
}

# Find the latest Ubuntu 22.04 image automatically
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (official Ubuntu publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = aws_key_pair.deployer.key_name

  tags = {
    Name = "devops-final-server"
  }
}
