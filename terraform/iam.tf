# Trust policy document for EC2 instances
data "aws_iam_policy_document" "ec2_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM Role for Engine VM
resource "aws_iam_role" "engine" {
  name               = "iii-engine-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust_policy.json

  tags = {
    Name = "iii-engine-role"
  }
}

# Attach SSM policy to Engine role (for SSH-free Session Manager access)
resource "aws_iam_role_policy_attachment" "engine_ssm" {
  role       = aws_iam_role.engine.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch policy to Engine role (for metrics and log ingestion)
resource "aws_iam_role_policy_attachment" "engine_cw" {
  role       = aws_iam_role.engine.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Instance Profile for Engine
resource "aws_iam_instance_profile" "engine" {
  name = "iii-engine-instance-profile"
  role = aws_iam_role.engine.name
}

# IAM Role for Workers (Inference & Caller)
resource "aws_iam_role" "worker" {
  name               = "iii-worker-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust_policy.json

  tags = {
    Name = "iii-worker-role"
  }
}

# Attach SSM policy to Worker role
resource "aws_iam_role_policy_attachment" "worker_ssm" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile for Workers
resource "aws_iam_instance_profile" "worker" {
  name = "iii-worker-instance-profile"
  role = aws_iam_role.worker.name
}
