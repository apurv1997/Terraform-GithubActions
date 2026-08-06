variable "name_prefix" {
  description = "Prefix used to namespace tags and default resource names for this environment"
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "instance_type" {
  type = string
}

variable "enable_deletion_protection" {
  description = "Enable ALB deletion protection for this environment"
  type        = bool
  default     = false
}

# The following are overrides for AWS attributes that force resource
# replacement when changed (ALB/SG/IAM/S3 names). They default to a
# name derived from name_prefix, but can be pinned to a literal value
# so an existing environment's resources aren't renamed/recreated when
# adopted into this module.
variable "alb_name" {
  type    = string
  default = null
}

variable "target_group_name" {
  type    = string
  default = null
}

variable "alb_sg_name" {
  type    = string
  default = null
}

variable "ec2_sg_name" {
  type    = string
  default = null
}

variable "iam_role_name" {
  type    = string
  default = null
}

variable "iam_instance_profile_name" {
  type    = string
  default = null
}

variable "s3_bucket_name" {
  type    = string
  default = null
}
