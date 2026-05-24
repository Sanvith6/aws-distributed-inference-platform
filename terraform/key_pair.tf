resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Deploy key to Free Tier account
resource "aws_key_pair" "deployer" {
  key_name   = "iii-deployer-key"
  public_key = tls_private_key.pk.public_key_openssh
}

# Deploy the exact same key to Paid account
resource "aws_key_pair" "deployer_paid" {
  provider   = aws.paid
  key_name   = "iii-deployer-key-paid"
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename        = "${path.module}/iii-key.pem"
  content         = tls_private_key.pk.private_key_pem
}
