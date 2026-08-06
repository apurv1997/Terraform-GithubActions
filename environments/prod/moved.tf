# Maps every resource's pre-refactor state address (root module) to
# its new address inside module.app. Required once, only in prod,
# because prod's state already has real resources under the old
# addresses. Safe to delete after the first successful apply against
# this config — Terraform records the move in state.

moved {
  from = aws_vpc.main
  to   = module.app.aws_vpc.main
}

moved {
  from = aws_internet_gateway.igw
  to   = module.app.aws_internet_gateway.igw
}

moved {
  from = aws_subnet.public
  to   = module.app.aws_subnet.public
}

moved {
  from = aws_subnet.private
  to   = module.app.aws_subnet.private
}

moved {
  from = aws_eip.nat
  to   = module.app.aws_eip.nat
}

moved {
  from = aws_nat_gateway.nat
  to   = module.app.aws_nat_gateway.nat
}

moved {
  from = aws_route_table.public
  to   = module.app.aws_route_table.public
}

moved {
  from = aws_route_table.private
  to   = module.app.aws_route_table.private
}

moved {
  from = aws_route_table_association.public
  to   = module.app.aws_route_table_association.public
}

moved {
  from = aws_route_table_association.private
  to   = module.app.aws_route_table_association.private
}

moved {
  from = aws_security_group.alb
  to   = module.app.aws_security_group.alb
}

moved {
  from = aws_security_group.ec2
  to   = module.app.aws_security_group.ec2
}

moved {
  from = aws_iam_role.ec2_ssm
  to   = module.app.aws_iam_role.ec2_ssm
}

moved {
  from = aws_iam_role_policy_attachment.ssm
  to   = module.app.aws_iam_role_policy_attachment.ssm
}

moved {
  from = aws_iam_instance_profile.ec2_ssm
  to   = module.app.aws_iam_instance_profile.ec2_ssm
}

moved {
  from = aws_instance.app
  to   = module.app.aws_instance.app
}

moved {
  from = aws_lb.app
  to   = module.app.aws_lb.app
}

moved {
  from = aws_lb_target_group.app
  to   = module.app.aws_lb_target_group.app
}

moved {
  from = aws_lb_target_group_attachment.app
  to   = module.app.aws_lb_target_group_attachment.app
}

moved {
  from = aws_lb_listener.app
  to   = module.app.aws_lb_listener.app
}

moved {
  from = aws_s3_bucket.alb_logs
  to   = module.app.aws_s3_bucket.alb_logs
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.alb_logs
  to   = module.app.aws_s3_bucket_server_side_encryption_configuration.alb_logs
}

moved {
  from = aws_s3_bucket_policy.alb_logs
  to   = module.app.aws_s3_bucket_policy.alb_logs
}
