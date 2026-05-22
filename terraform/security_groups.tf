resource "aws_security_group" "engine" {
  name        = "iii-engine-sg"
  description = "Engine HTTP/HTTPS/WS and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from your IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "WebSocket RPC from Private Subnet (Caller Worker)"
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iii-engine-sg"
  }
}

# Security Group for TypeScript Caller Worker VM in Private Subnet
resource "aws_security_group" "caller" {
  name        = "iii-caller-sg"
  description = "Caller worker SG in Private Subnet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from Engine VM (Bastion)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.engine.private_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iii-caller-sg"
  }
}

# Security Group for Python Inference Worker VM in Private Subnet
resource "aws_security_group" "inference" {
  name        = "iii-inference-sg"
  description = "Inference worker SG in Private Subnet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from Engine VM (Bastion)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.engine.private_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iii-inference-sg"
  }
}
