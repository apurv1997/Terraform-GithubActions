resource "aws_iam_role" "ec2_ssm" {
  name = coalesce(var.iam_role_name, "${var.name_prefix}-ec2-ssm-role")
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = coalesce(var.iam_instance_profile_name, "${var.name_prefix}-ec2-ssm-profile")
  role = aws_iam_role.ec2_ssm.name
}
