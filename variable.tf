variable "vpc_cidr" {
  default  = "10.0.0.0/16"
  }

  variable "aws_region" {
    default = "ap-south-1"
  }

  variable "azs" {
    default = ["ap-south-1a", "ap-south-1b"]
  }

  variable "public_subnet_cidrs" {
    default = ["10.0.1.0/24", "10.0.2.0/24"]
  }

  variable "private_subnet_cidrs" {
    default = ["10.0.101.0/24", "10.0.102.0/24"]
  }

  variable "instance_type" {
    default = "t3.micro"
  }