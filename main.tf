# main.tf の中身
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {

  region = var.region
}

resource "aws_vpc" "portfolio_vpc" {
   
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    
    Name = "${var.project_name}-VPC"

    Project = "Terraform Portfolio"
  }
}

# main.tf に追記
# ------------------------------
# 2. Internet Gateway (インターネットゲートウェイ) の作成
# ------------------------------
resource "aws_internet_gateway" "portfolio_igw" {
  # 依存関係: どのVPCに接続するかを指定
  vpc_id = aws_vpc.portfolio_vpc.id 

  tags = {
    Name = "portfolio-igw"
   
  }
}

# main.tf に追記
# ------------------------------
# 3. Subnet (サブネット) の作成
# ------------------------------

# 3-1. パブリックサブネット (Webサーバー用)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.portfolio_vpc.id
  cidr_block              = "10.0.1.0/24" # 10.0.1.x の範囲
  # インターネットへの出口を有効化
  map_public_ip_on_launch = true 
  availability_zone       = "ap-northeast-1a" # 東京の最初のAZを指定

  tags = {
    Name = "public-subnet-1a"
  }
}

# 3-2. プライベートサブネット (データベース用)
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.portfolio_vpc.id
  cidr_block        = "10.0.2.0/24" # 10.0.2.x の範囲
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "private-subnet-1a"
  }
}

# 2つ目のプライベートサブネットを異なるAZに作成します
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.portfolio_vpc.id
  cidr_block        = "10.0.3.0/24" # 既存のCIDRブロックと重複しないように注意
  
  # 異なるアベイラビリティゾーン（ap-northeast-1cなど）を指定します
  # ap-northeast-1a 以外を指定してください
  availability_zone = "ap-northeast-1c" 
  
  tags = {
    Name = "Portfolio Private Subnet 2"
  }
}

# main.tf に追記
# ------------------------------
# 4. Route Table (ルーティングテーブル) の設定
# ------------------------------

# 4-1. パブリックルートテーブルの作成
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.portfolio_vpc.id

  # デフォルトルート (0.0.0.0/0) をIGWに向ける
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.portfolio_igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# 4-2. ルートテーブルとパブリックサブネットの関連付け
resource "aws_route_table_association" "public_rt_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# ------------------------------
# 5. Security Group (セキュリティグループ) の作成
# ------------------------------

# 5-1. Webサーバー用セキュリティグループ (web_sg)
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.portfolio_vpc.id
  name   = "web-server-sg"

  # インターネットからのHTTPアクセス (80番ポート) を許可
  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # SSHアクセス (22番ポート) を許可
  ingress {
    description = "Allow SSH from anywhere (Temporary for test)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  
  # VPC内からのアウトバウンド（外向き）通信をすべて許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 5-2. データベース用セキュリティグループ (db_sg)
resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.portfolio_vpc.id
  name   = "database-sg"

  # WebサーバーのセキュリティグループからのMySQLアクセス (3306番) のみを許可
  ingress {
    description     = "Allow MySQL from Web Server SG"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    # ソースとしてWebサーバーのSGを指定 (ここが重要)
    security_groups = [aws_security_group.web_sg.id] 
  }
  
  # アウトバウンドを全て許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------
# 6. EC2 (Webサーバー) の作成
# ------------------------------

# 6-1. AMIのデータソース取得 (Amazon Linux 2023 最新版)

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*x86_64"]
  }
}


# 6-2. EC2インスタンスの定義
resource "aws_instance" "web_server" {
 ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"  # パブリックサブネットに配置
  subnet_id     = aws_subnet.public_subnet.id
  # web_sgをアタッチ
  security_groups = [aws_security_group.web_sg.id]
  # 起動時にパブリックIPを自動付与
  associate_public_ip_address = true 

  # 起動時に実行するシェルスクリプト (Apache Webサーバーのインストール)
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install httpd -y
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from Terraform Web Server!</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "Portfolio-WebServer"
  }

  lifecycle {
    # 意図しない属性の変更による再作成を防ぐ
    # security_groups/vpc_security_group_ids周りの変更を無視させる
    ignore_changes = [
      vpc_security_group_ids,
      security_groups,
      tags.Name,
      # 必要に応じてその他の属性も追加
    ]
  }
}

# ------------------------------------------------
# 1. DB Subnet Group: プライベートサブネットにDBを配置
# ------------------------------------------------
# RDSインスタンスがVPC内のどのサブネットに配置されるかを指定します。
# データベースは外部からのアクセスを防ぐため、必ずプライベートサブネットに配置します。
resource "aws_db_subnet_group" "portfolio_db_subnet_group" {
  name       = "portfolio-db-subnet-group"
  
  # 【変更箇所】2つのプライベートサブネットIDを指定します
  subnet_ids = [
    aws_subnet.private_subnet.id,  # 既存のサブネット
    aws_subnet.private_subnet_2.id # ステップ 1 で追加した新しいサブネット
  ] 
  
  tags = {
    Name = "Portfolio DB Subnet Group"
  }
}
# ------------------------------------------------
# 2. DB Parameter Group: データベースの設定
# ------------------------------------------------
# データベースの文字コードやタイムゾーンなどの設定を定義します。
# DBエンジンとバージョンに合わせて作成します。
resource "aws_db_parameter_group" "portfolio_db_param_group" {
  name   = "portfolio-db-param-group"
  family = "mysql8.0" # MySQL 8.0を使用する場合

  # タイムゾーンを東京（Asia/Tokyo）に設定する
  parameter {
    name  = "time_zone"
    value = "Asia/Tokyo"
  }
  # 文字コードをUTF8MB4に設定する
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
  parameter {
    name  = "collation_server"
    value = "utf8mb4_ja_0900_as_cs" # 日本語のソート順（MySQL 8.0の場合）
  }

  tags = {
    Name = "Portfolio DB Parameter Group"
  }
}

# ------------------------------------------------
# 3. RDS Instance: データベース本体の作成
# ------------------------------------------------
resource "aws_db_instance" "portfolio_db" {
  # 必須項目
  identifier              = "portfolio-db-instance"
  engine                  = "mysql"
  # engine_version          = "8.0.34"
  instance_class          = "db.t3.micro" # 開発・検証用として無料枠対象のインスタンスタイプ
  allocated_storage       = 20
  storage_type            = "gp2"
  db_name                 = "portfoliodb" # データベース名（アプリケーションが接続するデータベースの名前）
  username = var.db_username
  password = var.db_password
  
  # ネットワーキングとセキュリティ
  vpc_security_group_ids  = [aws_security_group.db_sg.id] # 既存のDB用SGを参照
  db_subnet_group_name    = aws_db_subnet_group.portfolio_db_subnet_group.name
  publicly_accessible     = false # ⚠️ 外部からのアクセスを防ぐため「false」に設定（EC2からのみ接続可能）

  # 運用設定
  parameter_group_name    = aws_db_parameter_group.portfolio_db_param_group.name
  skip_final_snapshot     = true # 削除時にスナップショットを作成しない設定（開発・検証用）
  
  # バックアップ設定（任意）
  # backup_retention_period = 7 # 7日間バックアップを保持
  
  tags = {
    Name = "Portfolio-DB"
  }
}

# ------------------------------------------------
# 4. データベース接続情報を出力する (Outputs)
# ------------------------------------------------
# EC2インスタンスからDBに接続する際に必要となるエンドポイント情報を出力します。
output "db_endpoint" {
  description = "The DNS address of the RDS instance"
  value       = aws_db_instance.portfolio_db.address
}


