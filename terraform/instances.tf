# Engine Gateway VM (Public Subnet)
resource "aws_instance" "engine" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_types["engine"]
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.engine.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = aws_iam_instance_profile.engine.name

  tags = {
    Name = "iii-engine-gateway"
  }
}

# TypeScript Caller Worker VM (Private Subnet)
resource "aws_instance" "caller" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_types["caller"]
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.caller.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = aws_iam_instance_profile.worker.name

  tags = {
    Name = "iii-caller-worker"
  }
}

# Python Inference Worker VM (Private Subnet)
resource "aws_instance" "inference" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_types["inference"]
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.inference.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = aws_iam_instance_profile.worker.name

  tags = {
    Name = "iii-inference-worker"
  }
}
