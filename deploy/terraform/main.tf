# [VULN-12] CWE-732/CWE-284 Insecure cloud infrastructure for IaC scanning.
provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAQ4FAKE0DEMO00000"                              # hardcoded creds
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYFAKEDEMOKEY"
}

resource "aws_s3_bucket" "exports" {
  bucket = "wallet-saver-exports-demo"
  acl    = "public-read"                                            # public bucket
}

resource "aws_s3_bucket_public_access_block" "exports" {
  bucket                  = aws_s3_bucket.exports.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_security_group" "open" {
  name = "wallet-open-sg"
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                                     # open to world
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                                     # SSH open to world
  }
}

resource "aws_db_instance" "wallet" {
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = "wallet_admin"
  password               = "Pg_demo_password_2026"                 # hardcoded db password
  publicly_accessible    = true                                    # public DB
  storage_encrypted      = false                                   # unencrypted storage
  skip_final_snapshot    = true
}
