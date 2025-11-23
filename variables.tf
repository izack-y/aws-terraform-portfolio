# ---------------------------------------------
# プロジェクト全体の変数設定
# ---------------------------------------------

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-1" # 東京リージョン
}

variable "project_name" {
  description = "Project Name Tag"
  type        = string
  default     = "Portfolio"
}

# ---------------------------------------------
# ネットワーク関連
# ---------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# ---------------------------------------------
# データベース関連
# ---------------------------------------------

variable "db_password" {
  description = "Password for RDS"
  type        = string
  sensitive   = true
 
}

variable "db_username" {
  description = "Username for RDS"
  type        = string
  default     = "admin"
}