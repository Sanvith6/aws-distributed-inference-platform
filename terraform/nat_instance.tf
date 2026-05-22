data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "nat" {
  name        = "iii-nat-sg"
  description = "Allow private subnet inbound, all outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  tags = {
    Name = "iii-nat-sg"
  }
}

resource "aws_instance" "nat" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_types["nat"]
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nat.id]
  source_dest_check      = false # CRITICAL for NAT routing
  key_name               = aws_key_pair.deployer.key_name

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail
              
              # Enable IP forwarding in kernel
              sysctl -w net.ipv4.ip_forward=1
              echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
              
              # Configure iptables masquerading dynamically on the default interface
              DEFAULT_INTERFACE=$(ip route show | awk '/default/ {print $5}')
              iptables -t nat -A POSTROUTING -o "$DEFAULT_INTERFACE" -j MASQUERADE
              
              # Save iptables rules to local file (avoids apt/interactive packages entirely)
              mkdir -p /etc/iptables
              iptables-save > /etc/iptables/rules.v4
              
              # Write a simple boot service to restore rules on system restart
              cat <<'INNER_EOF' > /etc/systemd/system/nat-boot.service
              [Unit]
              Description=Restore iptables nat rules
              After=network.target

              [Service]
              Type=oneshot
              ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
              RemainAfterExit=yes

              [Install]
              WantedBy=multi-user.target
              INNER_EOF
              
              systemctl daemon-reload
              systemctl enable nat-boot.service
              systemctl start nat-boot.service
              EOF

  tags = {
    Name = "iii-nat-instance"
  }
}
