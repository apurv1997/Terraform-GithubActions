terraform {
  backend "s3" {
    bucket         = "apurv-terraform-bucket"
    key            = "vpc-project/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-db-locks"
    encrypt        = true
  }
}