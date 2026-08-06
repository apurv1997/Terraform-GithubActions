# This environment adopts the infrastructure that used to live in the
# repo root. name_prefix only affects tags (safe to change in place);
# the name/bucket overrides below are pinned to the literal values the
# live resources already have, since those attributes force
# replacement if changed. See moved.tf for the matching state-address
# migration.
module "app" {
  source = "../../modules/app-infra"

  name_prefix          = "prod"
  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["ap-south-1a", "ap-south-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]
  instance_type        = "t3.micro"

  enable_deletion_protection = true

  alb_name                  = "learning-alb"
  target_group_name         = "learning-tg"
  alb_sg_name               = "alb-sg"
  ec2_sg_name               = "ec2-sg"
  iam_role_name             = "ec2-ssm-role"
  iam_instance_profile_name = "ec2-ssm-profile"
  s3_bucket_name            = "learning-alb-access-logs-183088117150"
}

output "alb_dns_name" {
  value = module.app.alb_dns_name
}

output "vpc_id" {
  value = module.app.vpc_id
}

output "instance_ids" {
  value = module.app.instance_ids
}
