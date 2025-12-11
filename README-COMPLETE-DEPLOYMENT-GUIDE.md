# Phonebook Blue-Green Deployment - Kurulum Rehberi

Bu rehber, **hiç bilmeyen** birinin bile sıfırdan başlayıp Phonebook uygulamasını Blue-Green deployment stratejisiyle AWS'de çalıştırabilmesini sağlar.

---

## 📋 İçindekiler

1. [Proje Hakkında](#proje-hakkında)
2. [Gereksinimler](#gereksinimler)
3. [Mimari Yapı](#mimari-yapı)
4. [Adım 1: Altyapı Hazırlığı](#adım-1-altyapı-hazırlığı)
5. [Adım 2: Terraform ile AWS Altyapısı](#adım-2-terraform-ile-aws-altyapısı)
6. [Adım 3: Ansible Kurulumu](#adım-3-ansible-kurulumu)
7. [Adım 4: Ansible Vault Setup](#adım-4-ansible-vault-setup)
8. [Adım 5: İlk Deployment](#adım-5-ilk-deployment)
9. [Adım 6: Blue-Green Switch Test](#adım-6-blue-green-switch-test)
10. [Adım 7: Rollback Test](#adım-7-rollback-test)
11. [Troubleshooting](#troubleshooting)
12. [Sonraki Adımlar](#sonraki-adımlar)

---

## 🎯 Proje Hakkında

### Ne Yapıyoruz?

**Phonebook** adında basit bir Flask web uygulamasını AWS'de **Blue-Green deployment** stratejisiyle çalıştırıyoruz.

### Blue-Green Deployment Nedir?

- **Blue:** Şu anda çalışan, kullanıcıların gördüğü versiyon
- **Green:** Yeni versiyon, test ediliyor
- **Switch:** Green test edilip hazır olduğunda, trafiği Green'e yönlendiriyoruz
- **Rollback:** Green'de sorun çıkarsa, anında Blue'ya geri dönüyoruz

### Neden Blue-Green?

✅ **Sıfır kesinti** - Kullanıcılar hiçbir şey fark etmez
✅ **Güvenli güncelleme** - Önce test, sonra production
✅ **Hızlı rollback** - Sorun olursa 1 saniyede geri dön
✅ **A/B testing** - İki versiyonu karşılaştırabilirsiniz

---

## 🛠 Gereksinimler

### AWS Account

- [ ] AWS hesabı (Free tier yeterli)
- [ ] IAM kullanıcısı veya Admin yetkisi
- [ ] AWS CLI kurulu ve yapılandırılmış (lokal makinede)
- [ ] AWS credentials yapılandırılmış

### Lokal Makine

**İşletim Sistemi:**
- Windows, Linux veya macOS (herhangi biri uygun)

**Yazılımlar:**
- [ ] Terraform 1.0+ kurulu
- [ ] Git kurulu
- [ ] SSH client (ssh komutu)
- [ ] Text editor (VS Code önerilir)

**NOT:** Ansible'ı lokal makinenize kurmanıza gerek yok! Terraform otomatik olarak bir Control Node (EC2 instance) oluşturacak ve üzerine Ansible kuracak.

### Bilgi Seviyesi

- Temel Linux komutları
- YAML syntax (öğrenerek ilerleyebilirsiniz)
- Temel AWS bilgisi (EC2, Security Groups)

**ÖNEMLI:** Bu rehber baştan sona her şeyi açıkladığı için önceden bilmek zorunda değilsiniz!

---

## 🏗 Mimari Yapı

```
        Lokal Makine
            │ (Terraform çalıştır)
            ▼
┌───────────────────────────────────────────────────────────────┐
│                      AWS CLOUD                                │
│                                                               │
│  ┌─────────────────┐                                         │
│  │  Control Node   │ ◄─── SSH ile bağlan, Ansible komutları  │
│  │  (EC2 Ubuntu)   │      buradan çalıştır                   │
│  │  Ansible yüklü  │                                         │
│  └────────┬────────┘                                         │
│           │ (Ansible ile yönet)                              │
│           ▼                                                  │
│  ┌───────────────────────────────────────────────┐          │
│  │    Application Load Balancer                  │          │
│  │    (Traffic Yönlendiricisi)                   │          │
│  └──────────┬───────────────────┬─────────────────┘          │
│             │                   │                            │
│   ┌─────────▼─────────┐  ┌─────▼──────────┐                │
│   │   Blue Server     │  │  Green Server  │                │
│   │  (Production)     │  │   (Staging)    │                │
│   │  Flask App        │  │  Flask App     │                │
│   └─────────┬─────────┘  └────────┬───────┘                │
│             │                      │                         │
│             └──────────┬───────────┘                         │
│                        │                                     │
│              ┌─────────▼──────────┐                         │
│              │  MySQL Database    │                         │
│              │  (phonebook_db)    │                         │
│              └────────────────────┘                         │
└───────────────────────────────────────────────────────────────┘
```

**4 EC2 Instance (Tamamı Ubuntu 22.04):**
1. **Control Node** - Ansible kurulu, buradan tüm deployment komutları çalıştırılır
2. **db_server_phonebook** - MySQL veritabanı
3. **blue_server_phonebook** - Blue environment (production)
4. **green_server_phonebook** - Green environment (staging)

**1 ALB (Application Load Balancer):**
- Trafiği blue veya green'e yönlendirir
- Health check yapar
- Switch sırasında kesintisiz geçiş sağlar

**İş Akışı:**
1. Lokal makineden Terraform ile 4 EC2 instance oluşturulur
2. Control Node'a SSH ile bağlanılır
3. Tüm Ansible komutları Control Node üzerinden çalıştırılır
4. Control Node, diğer 3 sunucuyu (DB, Blue, Green) yönetir

---

## 📍 Adım 1: Altyapı Hazırlığı

### 1.1: Klasör Yapısını Hazırla

```bash
# Projeye git
cd ansible/session-06;ansible-capstone-b2

# Yapıyı kontrol et
ls -la
# Görmelisiniz:
# - terraform-files/
# - ansible-project/
```

**Neden:** Terraform dosyaları AWS altyapısını, ansible-project klasörü Ansible kodlarını içerir.

---

### 1.2: AWS CLI Yapılandır

```bash
# AWS CLI versiyonunu kontrol et
aws --version
# aws-cli/2.x.x ... görmeli

# Yoksa kur:
# Ubuntu/Debian:
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Credentials yapılandır
aws configure
```

**Soruları Yanıtla:**
```
AWS Access Key ID: [AWS Console'dan aldığınız key]
AWS Secret Access Key: [AWS Console'dan aldığınız secret]
Default region name: us-east-1
Default output format: json
```

**Test:**
```bash
aws sts get-caller-identity
# Account ID ve User ARN görmelisiniz
```

**Neden:** Ansible ve Terraform, AWS'ye bu credentials ile bağlanacak.

---

### 1.3: SSH Key Hazırla

```bash
# Terraform dizinine git
cd terraform-files

# SSH key var mı kontrol et
ls -la *.pem
# your-key-name.pem görmelisiniz

# Permission ayarla (ZORUNLU!)
chmod 400 your-key-name.pem

# Key'in yerini not et, EC2 instance'lara SSH ile bağlanmak için bu key gerekli.
pwd
# /path/to/ansible/session-06;ansible-capstone-b2/terraform-files
```

---

## 🏗 Adım 2: Terraform ile AWS Altyapısı

### 2.1: Terraform Yapılandırmasını İncele

```bash
cd terraform-files

# Ana yapılandırma dosyası
cat main.tf | head -50
```

**Bu dosya ne yapar:**
- **4 EC2 instance oluşturur:**
  - 1 Control Node (Ansible kurulu)
  - 1 Database Server (MySQL)
  - 1 Blue Server (Flask app)
  - 1 Green Server (Flask app)
- 1 ALB oluşturur
- 2 Target Group oluşturur (blue-tg, green-tg)
- Security Groups ayarlar (port 22, 80, 3306)
- IAM roles ekler (EC2FullAccess, SSMReadOnlyAccess)
- **Control Node'a otomatik Ansible kurulumu yapar** (null_resource provisioner)

**Neden:** Manuel olarak AWS Console'dan tek tek oluşturmak yerine, kod ile otomatize ediyoruz. Herkes aynı ortamı kullanacak!

---

### 2.2: Terraform Variables Ayarla

```bash
# myvars.auto.tfvars dosyasını aç
nano myvars.auto.tfvars
```

**Düzenle:**
```hcl
aws_region = "us-east-1"
mykey      = "your-key-name"
mykeypem   = "your-key-name.pem"
user       = "refia"  # Kendi adınızı yazın
```

**Kaydet:** `Ctrl+O`, Enter, `Ctrl+X`

**Neden:** Bu değişkenler Terraform'a hangi region, hangi key kullanacağını söyler.

---

### 2.3: Terraform Init (İlk Kurulum)

```bash
terraform init
```

**Ne olur:**
- AWS provider indirilir
- .terraform/ klasörü oluşturulur
- Backend yapılandırılır

**Çıktı:**
```
Initializing the backend...
Initializing provider plugins...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

**Neden:** Terraform, AWS ile konuşmak için gerekli pluginleri indirir.

---

### 2.4: Terraform Plan (Ne Yapılacak?)

```bash
terraform plan
```

**Ne olur:**
- Terraform, ne oluşturacağını listeler
- Değişiklikleri gösterir
- Hata varsa uyarır

**Çıktı Özeti:**
```
Plan: 15 to add, 0 to change, 0 to destroy.
```

**İncelenmesi Gerekenler:**
- `+ aws_instance.nodes[0]` - Control Node (Ansible installed)
- `+ aws_instance.nodes[1]` - Database server
- `+ aws_instance.nodes[2]` - Blue server
- `+ aws_instance.nodes[3]` - Green server
- `+ aws_lb.phonebook_alb` - Load balancer (yorumlu olabilir)
- `+ aws_security_group...` - Güvenlik grupları
- `+ null_resource.config` - Control Node provisioning

**Neden:** Yanlışlıkla yanlış kaynak oluşturmamak için önce plan'ı görüyoruz.

---

### 2.5: Terraform Apply (Altyapıyı Oluştur)

```bash
terraform apply
```

**Onay İste:**
```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes  # "yes" yaz ve Enter
```

**Ne olur:**
- 4 EC2 instance başlatılır (~2-3 dakika)
- Control Node'a Ansible kurulumu yapılır (~2 dakika)
- ALB oluşturulur (eğer yorumlu değilse) (~3 dakika)
- Security groups ayarlanır
- IAM roles attach edilir
- Control Node'a inventory.ini kopyalanır

**BEKLEME SÜRESİ: 5-7 dakika**

**Çıktı (Son):**
```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:

control_node_ip = "13.217.221.127"
db_server_ip = "44.222.85.252"
blue_server_ip = "98.84.23.39"
green_server_ip = "34.229.64.209"
region = "us-east-1"
all_instance_ips = {
  "control_node" = "13.217.221.127"
  "db_server" = "44.222.85.252"
  "blue_server" = "98.84.23.39"
  "green_server" = "34.229.64.209"
}
```

**ÖNEMLİ:** `control_node_ip`'yi not edin! Bu sunucuya SSH ile bağlanacaksınız.

**Neden:** Altyapıyı AWS'de fiziksel olarak oluşturuyoruz. Artık 4 EC2 çalışıyor ve Control Node Ansible'a hazır!

---

### 2.6: Dynamic Inventory Hazırlığı

**ÖNEMLİ:** Bu projede **Dynamic Inventory** kullanacağız! IP'leri manuel olarak not etmenize gerek yok.

**Dynamic Inventory Nedir?**
- Ansible, AWS API'den otomatik olarak instance'ları çeker
- Tag'lere göre otomatik gruplama yapar
- IP değişse bile manuel güncelleme gerektirmez
- Daha profesyonel ve maintenance-free

**Kontrol (opsiyonel):**
```bash
# Instance'ları görmek isterseniz
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=phonebook" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],PublicIpAddress,PrivateIpAddress]' \
  --output table
```
ya da terraform outputlarından da bakabilirsiniz.
---

### 2.7: VS Code ile Control Node'a Bağlan

**ÖNERİLEN YÖNTEM:** VS Code Remote SSH ile bağlanın! Dosya yapısını görmek ve düzenlemek çok daha kolay olacak.

#### Seçenek 1: VS Code Remote SSH (Önerilen) 🎯

**Adım 1: Remote SSH Extension Kur**
```
1. VS Code'u açın
2. Extensions (Ctrl+Shift+X)
3. "Remote - SSH" ara ve kur
4. "Remote Explorer" (Ctrl+Shift+P → Remote-SSH: Connect to Host)
```

**Adım 2: SSH Config Dosyasını Düzenle**
```bash
# Lokal makinenizde
# Windows: C:\Users\YourUsername\.ssh\config
# Linux/Mac: ~/.ssh/config

# Config dosyasını açın (yoksa oluşturun)
code ~/.ssh/config  # veya
notepad C:\Users\YourUsername\.ssh\config
```

**Config'e ekleyin:**
```
Host ansible-control-node
    HostName control-node-public-ip
    User ubuntu
    IdentityFile \your-key-path\your-key-name.pem
    StrictHostKeyChecking no
```

**ÖNEMLI:**
- `HostName` kısmını Terraform output'tan aldığınız `control_node_ip` ile değiştirin
- `IdentityFile` yolunu kendi key dosyanızın tam yoluna göre düzenleyin

**Adım 3: VS Code'dan Bağlan**
```
1. VS Code'da Remote Explorer'ı açın (sol sidebar'dan)
2. "SSH Targets" altında "ansible-control-node" görünecek
3. Sağ tık → "Connect to Host in New Window"
4. Yeni VS Code penceresi açılacak
5. "Linux" seçin (ilk bağlantıda sorar)
```

**Adım 4: Proje Klasörünü Aç**
```
VS Code'da (Control Node'a bağlıyken):
File → Open Folder → /home/ubuntu/

Açılan klasörde sizinle paylaşılan 'ansible-project'
```



**Artık:**
- ✅ Dosya yapısını sol tarafta görebilirsiniz
- ✅ Terminal'i VS Code içinde açabilirsiniz (Ctrl+`)
- ✅ Dosyaları VS Code editöründe düzenleyebilirsiniz
- ✅ Extension'ları Control Node'da kullanabilirsiniz

**Adım 5: Kurulumları Kontrol Et**
```bash
# VS Code terminal'de (Control Node'da)
ansible --version
# ansible [core 2.15.x] görmeli

aws --version
# aws-cli/2.x.x görmeli

ls -la ~/*.pem
# SSH key kopyalanmış olmalı
```

---

#### Seçenek 2: Klasik SSH (Alternatif)

```bash
# Lokal makinenizden terminal ile bağlanın
ssh -i your-key-name.pem ubuntu@CONTROL_NODE_IP

# Örnek:
ssh -i terraform-files/RefiaKeyPair.pem ubuntu@13.217.221.127

# Bağlandığınızda:
ubuntu@Control-Node:~$
```

**Sorun Çıkarsa:**
```bash
# Permission hatası (lokal makinede):
chmod 400 your-key-name.pem

# Connection timeout:
# Security group port 22 açık mı kontrol edin
```

---

**✨ VS Code Remote SSH Avantajları:**
- 🗂️ Dosya yapısını görsel olarak görme
- ✏️ Syntax highlighting ile düzenleme
- 🔍 Dosyalarda arama yapma (Ctrl+Shift+F)
- 📁 Multiple terminal açma
- 🎨 YAML, Python için extension desteği
- 🐛 Daha kolay debugging

---

## 🎮 Adım 3: Ansible Yapılandırması

**ÖNEMLİ NOT:** Bu adımdan itibaren tüm komutlar **Control Node üzerinde** çalıştırılacak! Lokal makinenizde değil!

### 3.1: Control Node'da Proje Dosyalarını Hazırla

Şimdi Ansible projesini Control Node'a kopyalayacağız çünkü tüm komutları buradan çalıştıracağız.

**Seçenek 1: Kopyala yapıştır**

# Control Node'da (VsCode ile bağlı olduğunuz terminal)
Localinizdeki ansible-project klasörünü kopyalayarak vscode explorerda açık olan /home/ubuntu klasörüne kopyalayabilirsiniz.

**Seçenek 2: SCP ile kopyala (lokal makinenizden)**
```bash
# Lokal makinenizde başka bir terminal açın
cd /path/to/ansible/session-06;ansible-capstone-b2

# Proje klasörünü Control Node'a kopyala
scp -i terraform-files/RefiaKeyPair.pem -r ansible-project ubuntu@13.217.221.127:/home/ubuntu/

# Tekrar Control Node terminaline dönün
cd /home/ubuntu/ansible-project
ls -la
```

**Görmelisiniz:**
- `playbook.yml` - Ana playbook
- `roles/` - Roller (mysql, web, alb-switch)
- `ansible.cfg` - Ansible yapılandırması
- `group_vars/`, `host_vars/` - Değişkenler
- `phonebook` - Uygulama dosyaları
- `inventory_aws_ec2.yml` - dinamik envanter
- `get-vault-password.sh`, `get-vault-password.sh` - secret yönetimi 
- `iam-policy-ssm.json` - ssm yetkisi

---

### 3.2: Ansible Versiyonunu Kontrol Et

```bash
# Control Node'da
ansible --version
```

**Çıktı:**
```
ansible [core 2.15.x]
  python version = 3.10.x
  jinja version = 3.1.x
```

**✅ Ansible zaten kurulu!** Terraform provisioner tarafından otomatik kuruldu.

**Neden:** Terraform, Control Node'u oluştururken Ansible'ı otomatik kurdu. Herkes aynı versiyonu kullanıyor.

---

### 3.3: AWS Ansible Collection Kur (Control Node'da)

```bash
# Control Node'da - AWS modüllerini kur
ansible-galaxy collection install amazon.aws community.general

# Kontrol et
ansible-galaxy collection list | grep -E "amazon.aws|community.general"
```

**Çıktı:**
```
amazon.aws     6.x.x
community.general  8.x.x
```

**Neden:** Ansible'ın AWS ile (ALB, EC2) ve Slack ile çalışması için bu koleksiyonlar gerekli.

---

### 3.4: Python Boto3 Kur (Control Node'da)

```bash
# Control Node'da - AWS SDK kur
pip3 install boto3 botocore

# Kontrol et
python3 -c "import boto3; print(boto3.__version__)"
```

**Çıktı:** `1.28.x` veya üzeri

**Neden:** Ansible'ın AWS API'lerini kullanabilmesi için boto3 gerekli.

---

### 3.5: Dynamic Inventory Dosyasını Kontrol Et

**ÖNEMLİ:** Bu projede **AWS EC2 Dynamic Inventory** kullanıyoruz! Static inventory.ini yok.

```bash
# Control Node'da - Proje klasörüne git
cd /home/ubuntu/ansible-project

# Dynamic inventory dosyasını kontrol et
cat inventory_aws_ec2.yml
```

**Göreceğiniz içerik:**
```yaml
---
plugin: amazon.aws.aws_ec2

regions:
  - us-east-1

# Sadece phonebook projesi ve running instance'lar
filters:
  tag:Project: phonebook
  instance-state-name: running

# Tag'lere göre otomatik gruplama
keyed_groups:
  # Role tag'ine göre grup (db_server_phonebook, blue_server_phonebook, etc.)
  - key: tags.Role
    prefix: ""
    separator: "_phonebook"

  # Color tag'ine göre grup (color_blue, color_green)
  - key: tags.Color
    prefix: color

# Otomatik değişken atamaları
compose:
  ansible_host: public_ip_address
  ansible_user: "'ubuntu'"
  ansible_ssh_private_key_file: "'~/your-key-name.pem'"
  ansible_ssh_common_args: "'-o StrictHostKeyChecking=no'"
```

**✅ Dynamic Inventory Avantajları:**
- IP'ler otomatik çekilir (AWS API'den)
- Tag'lere göre otomatik gruplama (`db_server_phonebook`, `blue_server_phonebook`, `green_server_phonebook`)
- Instance durumu değişse bile güncelleme otomatik
- Profesyonel production-ready yaklaşım

**SSH Key Path'i Güncelle:**
```bash
# inventory_aws_ec2.yml'de key path'ini düzenle
nano inventory_aws_ec2.yml

# Bu satırı bulun ve key isminizi yazın:
ansible_ssh_private_key_file: "'~/RefiaKeyPair.pem'"
```

**Kaydet:** `Ctrl+O`, Enter, `Ctrl+X`

**Neden:** Dynamic inventory, AWS'deki değişikliklere otomatik adapte olur. IP değişse, instance eklenip çıksa sorun olmaz!

---

### 3.6: Dynamic Inventory Test (Control Node'da)

```bash
# Control Node'da - Proje klasöründe olduğunuzdan emin olun
cd /home/ubuntu/ansible-project

# Dynamic inventory'yi test et - tüm host'ları listele
ansible-inventory -i inventory_aws_ec2.yml --list

# Graph formatında görüntüle (daha okunabilir)
ansible-inventory -i inventory_aws_ec2.yml --graph

# Sunuculara ping at (dynamic inventory kullanarak)
ansible all -i inventory_aws_ec2.yml -m ping
```

**Başarılı Çıktı (--graph):**
```
@all:
  |--@aws_ec2:
  |  |--control_node_phonebook
  |  |--db_server_phonebook
  |  |--blue_server_phonebook
  |  |--green_server_phonebook
  |--@ungrouped:
```

**Başarılı Çıktı (ping):**
```json
db_server_phonebook | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
blue_server_phonebook | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
green_server_phonebook | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

**Hata Alırsanız:**
```bash
# AWS credentials kontrol (Control Node'da IAM role var mı?)
aws sts get-caller-identity

# SSH key permission kontrolü
ls -la ~/RefiaKeyPair.pem
# -r-------- 1 ubuntu ubuntu görmeli (400 permission)

# Gerekirse düzelt
chmod 400 ~/RefiaKeyPair.pem

# Dynamic inventory debug mode
ansible-inventory -i inventory_aws_ec2.yml --list -vvv
```

**Neden:** Dynamic inventory'nin AWS'den instance'ları doğru çektiğini ve erişebildiğimizi doğruluyoruz. Tag-based gruplama çalışıyor!

---

## 🔐 Adım 4: Ansible Vault Setup

**ÖNEMLİ:** Terraform zaten Control Node'a IAM role attach etti! SSM (Parameter Store) erişimi mevcut.

### 4.1: IAM Permissions Kontrolü

```bash
# Control Node'da - IAM role kontrolü
aws sts get-caller-identity

# Parameter Store erişimini test et
aws ssm describe-parameters --region us-east-1
```

**✅ Başarılı çıktı alırsanız:** IAM permissions hazır!

**Eğer "Unable to locate credentials" hatası alırsanız:**
```bash
# AWS credentials yapılandırın (Control Node'da)
aws configure
# Access Key, Secret Key, Region girin
```

---

### 4.2: Script'lere Execute Permission Ver

```bash
# Control Node'da - Proje klasöründe
cd /home/ubuntu/ansible-project

# Script'lere çalıştırma izni ver
chmod +x setup-vault-password.sh
chmod +x get-vault-password.sh

# Kontrol et
ls -la *.sh
# -rwxr-xr-x ... setup-vault-password.sh
# -rwxr-xr-x ... get-vault-password.sh
```

**Neden:** Bash script'leri çalıştırılabilir olmalı (executable bit).

---

### 4.3: Vault Şifresini Parameter Store'a Kaydet

```bash
# Control Node'da - Setup script'ini çalıştır
./setup-vault-password.sh
```

**Soru:**
```
=== Setup Ansible Vault Password in AWS Parameter Store ===

Enter your vault password (it will be hidden):
```

**Güçlü bir şifre girin:** (örn: `MyVaultP@ssw0rd2025!`)
- Minimum 8 karakter
- Büyük/küçük harf, rakam, özel karakter

**Şifreyi yazmayacak (güvenlik)** - tekrar soracak:
```
Confirm password:
```

**Başarılı Çıktı:**
```
✓ Password successfully stored in Parameter Store: /ansible/phonebook/vault-password
✓ You can now encrypt your vault file using:
  ansible-vault encrypt group_vars/vault.yml
```

**Neden:** Vault şifresini AWS'de güvenli bir şekilde (KMS şifreli) saklıyoruz. Böylece her seferinde şifre girmemize gerek kalmayacak.

---

### 4.4: Vault Dosyasını Encrypt Et

```bash
# Control Node'da - Vault dosyasını şifrele
cd /home/ubuntu/ansible-project
ansible-vault encrypt group_vars/vault.yml
```

**Çıktı:**
```
Encryption successful
```

**Şifreli dosyayı kontrol et:**
```bash
cat group_vars/vault.yml
```

**Görmelisiniz:**
```
$ANSIBLE_VAULT;1.1;AES256
66386439653865343839303039343266633361653031653837636533366337366239303431346662
38663965653138383738393536326634366234653835656431323537383732323332373561663663
...
```

**Decrypt test:**
```bash
ansible-vault view group_vars/vault.yml
```

**Çıktı:** Şifrelenmemiş içeriği görmeli (vault_db_password, vault_slack_token)

**Neden:** Hassas bilgileri (şifreler, token'lar) açık metin olarak tutmuyoruz. Ansible otomatik olarak decrypt edecek.

---

### 4.5: Ansible.cfg'yi Kontrol Et

```bash
# Control Node'da
cd /home/ubuntu/ansible-project
cat ansible.cfg | grep vault_password_file
```

**Çıktı:**
```
vault_password_file = ./get-vault-password.sh
```

**Bu satır varsa:** ✅ Hazır!
**Yoksa ekle:**
```bash
nano ansible.cfg
# [defaults] altına ekle:
# vault_password_file = ./get-vault-password.sh
```

**Neden:** Ansible, vault şifresini bu script'ten otomatik alacak. Artık `--ask-vault-pass` yazmaya gerek yok!

---

## 🚀 Adım 5: İlk Deployment

**HATIRLATMA:** Tüm bu adımlar Control Node üzerinde çalıştırılacak!

### 5.1: Pre-Flight Check (Control Node'da)

```bash
# Control Node'da - Proje klasöründe olduğunuzdan emin olun
cd /home/ubuntu/ansible-project

# Tüm dosyaların yerinde olduğunu kontrol et
ls -la
# playbook.yml
# inventory_aws_ec2.yml  ← Dynamic inventory
# ansible.cfg
# roles/
# group_vars/
# host_vars/
# *.sh

# ansible.cfg'de inventory'yi ayarla (tek seferlik)
nano ansible.cfg
```

**ansible.cfg'ye ekle:**
```ini
[defaults]
inventory = inventory_aws_ec2.yml
host_key_checking = False
remote_user = ubuntu
roles_path = ./roles
deprecation_warnings = False
interpreter_python = auto_silent
vault_password_file = ./get-vault-password.sh
```

**Kaydet ve test et:**
```bash
# Artık -i parametresi yazmaya gerek yok!
ansible all -m ping
```

**Tüm sunucular "pong" dönmeli.**

**Neden:** ansible.cfg'de inventory tanımladık, artık her komutta `-i inventory_aws_ec2.yml` yazmaya gerek yok!

---

### 5.2: Sadece Database Deploy Et (Test)

```bash
# Control Node'da - İlk olarak sadece database'i deploy edelim
cd /home/ubuntu/ansible-project
ansible-playbook playbook.yml --tags db
```

**Ne Olacak:**
1. Pre-flight checks (Python, disk space)
2. Common packages install
3. MySQL kurulumu
4. Database oluşturma
5. Remote user oluşturma
6. Post-tasks (MySQL çalışıyor mu?)

**Süre:** 3-5 dakika

**Başarılı Çıktı (Son):**
```
PLAY RECAP *********************************************************************
db_server_phonebook        : ok=15   changed=8    unreachable=0    failed=0
```

**Neden:** Önce sadece veritabanını kuruyoruz. Sorun varsa erken tespit ediyoruz.

---

### 5.3: Database'i Test Et

```bash
# Control Node'dan Database server'a SSH ile bağlan (private IP kullan)
ssh -i /home/ubuntu/RefiaKeyPair.pem ubuntu@172.31.60.105

# MySQL'e giriş yap
mysql -u remoteUser -pcloud123

# Database'i kontrol et
SHOW DATABASES;
USE phonebook_db;
SHOW TABLES;
DESCRIBE phonebook;

# Çıkış
exit  # MySQL'den çık
exit  # DB server'dan çık (Control Node'a dön)
```

**Görmelisiniz:**
- `phonebook_db` database
- `phonebook` tablosu
- `id`, `name`, `number` kolonları

**Neden:** Veritabanının doğru kurulduğunu manuel olarak kontrol ediyoruz.

---

### 5.4: Blue Server Deploy Et

```bash
# Control Node'da - Sadece blue server'a deploy et
cd /home/ubuntu/ansible-project
ansible-playbook playbook.yml --tags blue
```

**Ne Olacak:**
1. Pre-flight checks (DB erişimi)
2. Common packages
3. Python ve pip kurulumu
4. Flask app kopyalama (phonebook-app-blue.j2)
5. Requirements.txt kopyalama
6. Templates kopyalama
7. Dependencies kurulumu
8. MySQL bekleme (wait_for)
9. App başlatma
10. Post-tasks (health check)

**Süre:** 2-3 dakika

**Başarılı Çıktı:**
```
PLAY RECAP *********************************************************************
blue_server_phonebook      : ok=18   changed=12   unreachable=0    failed=0
```

**Neden:** Blue environment'ı kuruyoruz. Bu production environment olacak.

---

### 5.5: Blue Server'ı Test Et

**Test 1: Control Node'dan (private IP ile)**
```bash
# Control Node'da - Blue server'a curl at
curl http://172.31.61.201/health
curl http://172.31.61.201/
```

**Test 2: Lokal Makinenizden (public IP ile)**
```bash
# Lokal makinenizde - Blue server'ın public IP'sini kullanın
# (Terraform output'tan alın: blue_server_ip)
BLUE_IP="98.84.23.39"

# Health check
curl http://$BLUE_IP/health

# Ana sayfa
curl http://$BLUE_IP/

# Browser'da aç
# http://98.84.23.39/
```

**Health Check Response:**
```json
{
  "status": "healthy",
  "environment": "Blue",
  "database": {
    "status": "connected",
    "host": "172.31.60.105",
    "database": "phonebook_db"
  },
  "application": {
    "name": "Phonebook",
    "version": "1.0"
  }
}
```

**Browser'da:** Phonebook uygulamasını görmeli, "Blue" yazmalı.

**Neden:** Blue server'ın çalıştığını ve database'e bağlandığını doğruluyoruz.

---

### 5.6: Green Server Deploy Et

```bash
# Control Node'da - Sadece green server'a deploy et
cd /home/ubuntu/ansible-project
ansible-playbook playbook.yml --tags green
```

**Ne Olacak:** Blue ile aynı adımlar, ama "Green" environment

**Süre:** 2-3 dakika

**Başarılı Çıktı:**
```
PLAY RECAP *********************************************************************
green_server_phonebook     : ok=18   changed=12   unreachable=0    failed=0
```

**Neden:** Green environment'ı kuruyoruz. Bu staging/test environment olacak.

---

### 5.7: Green Server'ı Test Et

**Test 1: Control Node'dan (private IP ile)**
```bash
# Control Node'da - Green server'a curl at
curl http://172.31.62.143/health
curl http://172.31.62.143/
```

**Test 2: Lokal Makinenizden (public IP ile)**
```bash
# Lokal makinenizde - Green server'ın public IP'sini kullanın
GREEN_IP="34.229.64.209"

# Health check
curl http://$GREEN_IP/health

# Browser'da aç
# http://34.229.64.209/
```

**Browser'da:** Phonebook uygulamasını görmeli, "Green" yazmalı.

**Neden:** Green server'ın da çalıştığını doğruluyoruz.

---

### 5.8: ALB (Load Balancer) Bilgilerini Al

```bash
# ALB DNS adını al
aws elbv2 describe-load-balancers \
  --names phonebook-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text
```

**Çıktı:**
```
phonebook-alb-1234567890.us-east-1.elb.amazonaws.com
```

**Bu DNS'i not edin!**

**Browser'da aç:**
```
http://phonebook-alb-1234567890.us-east-1.elb.amazonaws.com/
```

**Şu anda:** Blue server görünmeli (ALB default olarak blue'ya yönlendirir)

**Neden:** Kullanıcılar bu ALB DNS'i üzerinden uygulamaya erişecek. Blue/Green switch burada yapılıyor.

---

## 🔄 Adım 6: Blue-Green Switch Test

### 6.1: ALB Listener'ını Kontrol Et

```bash
# Şu anki target group
aws elbv2 describe-listeners \
  --listener-arns $(aws elbv2 describe-load-balancers --names phonebook-alb --query 'LoadBalancers[0].Listeners[0].ListenerArn' --output text) \
  --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
  --output text
```

**Çıktı:**
```
arn:aws:elasticloadbalancing:us-east-1:...:targetgroup/phonebook-tg-blue/...
```

**"blue" yazıyor:** ✅ Şu anda Blue aktif

**Neden:** Switch öncesi durumu biliyoruz.

---

### 6.2: Green'e Switch Yap

```bash
# Control Node'da - ALB switch playbook'unu çalıştır
cd /home/ubuntu/ansible-project
ansible-playbook playbook.yml --tags switch
```

**Ne Olacak:**
1. AWS CLI kontrolleri
2. Green health check (/health endpoint)
3. Green healthy mi? → Evet
4. ALB listener'ı green'e yönlendir
5. Doğrula (assert)
6. Slack bildirimi gönder (eğer aktifse)
7. Deployment log kaydet

**Süre:** 30 saniye - 1 dakika

**Başarılı Çıktı:**
```
TASK [alb-switch : Assert Green deployment succeeded] **************************
ok: [localhost] => {
    "changed": false,
    "msg": "✓ Successfully switched to GREEN environment"
}

TASK [alb-switch : Display final deployment status] ****************************
ok: [localhost] => {
    "msg": "==========================================\nDeployment Summary\n==========================================\nTimestamp: 2024-12-09T10:30:15Z\nStatus: SUCCESS\nTarget: Green Environment\nCurrent Active: GREEN\n=========================================="
}

PLAY RECAP *********************************************************************
localhost                  : ok=15   changed=2    unreachable=0    failed=0
```

**Neden:** Production trafiğini Blue'dan Green'e geçiriyoruz. Kullanıcılar artık Green versiyonu görecek.

---

### 6.3: Switch'i Doğrula

```bash
# ALB DNS'ini browser'da yenile
# http://phonebook-alb-1234567890.us-east-1.elb.amazonaws.com/

# "Green" yazmalı!

# Health check
curl http://phonebook-alb-1234567890.us-east-1.elb.amazonaws.com/health
```

**Response:**
```json
{
  "environment": "Green",
  ...
}
```

**Listener ARN kontrol:**
```bash
aws elbv2 describe-listeners \
  --listener-arns $(aws elbv2 describe-load-balancers --names phonebook-alb --query 'LoadBalancers[0].Listeners[0].ListenerArn' --output text) \
  --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
  --output text
```

**Çıktı:** `...phonebook-tg-green...` görmelisiniz

**Neden:** Switch'in başarılı olduğunu doğruluyoruz.

---

## 🔙 Adım 7: Rollback Test

### 7.1: Green'i Bozalım (Simüle)

```bash
# Control Node'dan Green server'a bağlan (private IP)
ssh -i /home/ubuntu/RefiaKeyPair.pem ubuntu@172.31.62.143

# Flask uygulamasını durdur
sudo pkill -f phonebook-app.py

# Kontrol et
curl http://localhost/health
# Connection refused veya 503 görmeli

exit  # Green'den çık, Control Node'a dön
```

**Neden:** Gerçek hayatta Green'de sorun çıkarsa ne olacağını test ediyoruz.

---

### 7.2: Rollback Playbook'unu Çalıştır

```bash
# Control Node'da - Switch playbook'unu tekrar çalıştır
cd /home/ubuntu/ansible-project
ansible-playbook playbook.yml --tags switch
```

**Ne Olacak:**
1. Green health check → **BAŞARISIZ!** (503 veya connection refused)
2. Fail fast → Abort
3. **Rescue bloğu çalışır:**
   - Blue'ya rollback
   - Assert ile doğrula
   - Slack rollback bildirimi
4. **Always bloğu:**
   - Log kaydet (Status: rollback)
   - Summary göster

**Başarılı Rollback Çıktısı:**
```
TASK [alb-switch : Fail fast if Green is not healthy] *************************
fatal: [localhost]: FAILED! => {
    "msg": "Green server is not healthy (status: -1). Aborting deployment."
}

TASK [alb-switch : Deployment failed - initiating rollback to Blue] ***********
ok: [localhost] => {
    "msg": "⚠ Deployment to Green failed. Rolling back to Blue..."
}

TASK [alb-switch : Confirm Blue is active after rollback] *********************
ok: [localhost] => {
    "changed": false,
    "msg": "✓ Successfully rolled back to BLUE environment"
}

PLAY RECAP *********************************************************************
localhost                  : ok=12   changed=2    unreachable=0    failed=0
```

**Neden:** Otomatik rollback'in çalıştığını görüyoruz. Production güvende!

---

### 7.3: Rollback'i Doğrula

```bash
# ALB DNS'ini browser'da kontrol et
# http://phonebook-alb-1234567890.us-east-1.elb.amazonaws.com/

# "Blue" yazmalı! (Geri döndük)

# Listener ARN
aws elbv2 describe-listeners \
  --listener-arns $(aws elbv2 describe-load-balancers --names phonebook-alb --query 'LoadBalancers[0].Listeners[0].ListenerArn' --output text) \
  --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
  --output text
```

**Çıktı:** `...phonebook-tg-blue...` görmelisiniz

**Neden:** Rollback başarılı, kullanıcılar kesintisiz Blue'yu görmeye devam ediyor.

---

### 7.4: Green'i Düzelt ve Tekrar Dene

```bash
# Control Node'dan Green server'a bağlan
ssh -i /home/ubuntu/RefiaKeyPair.pem ubuntu@172.31.62.143

# App'i tekrar başlat
cd /home/ubuntu
sudo nohup python3 phonebook-app.py > /dev/null 2>&1 &

# Health check
curl http://localhost/health
# 200 OK ve "healthy" görmeli

exit  # Green'den çık, Control Node'a dön

# Control Node'da - Şimdi switch'i tekrar dene
cd /home/ubuntu/ansible-project
ansible-playbook playbook.yml --tags switch
```

**Bu sefer başarılı olmalı!** Green tekrar aktif.

**Neden:** Rollback sonrası düzeltme yapıp tekrar deploy edebiliyoruz.

---

## 🧪 Test Senaryoları

### Test 1: Database Bağlantısı

```bash
# Control Node'dan Blue server'a bağlan
ssh -i /home/ubuntu/RefiaKeyPair.pem ubuntu@172.31.61.201

# Database'e bağlanma testi
mysql -h 172.31.60.105 -u remoteUser -pcloud123 -e "SELECT 1"

exit  # Blue server'dan çık
```

**Başarılı:** Query sonucu dönmeli

---

### Test 2: Phonebook Ekleme

**Browser'da:**
1. ALB DNS'ini aç
2. "Add Record" tıkla
3. İsim: "John Doe"
4. Telefon: "5551234567"
5. Save

**Kontrol:**
- Kayıt eklenmeli
- Blue ve Green'de aynı kayıt görünmeli (aynı DB)

---

### Test 3: Blue-Green Switch (Canlı)

**Terminal 1 (Lokal makinenizde veya Control Node'da):**
```bash
# ALB'yi sürekli ping at (ALB DNS'ini kendi değerinizle değiştirin)
while true; do
  curl -s http://phonebook-alb-1234567890.us-east-1.elb.amazonaws.com/health | jq '.environment'
  sleep 2
done
```

**Terminal 2 (Control Node'da - yeni SSH session açın):**
```bash
# Control Node'a yeni bir SSH bağlantısı açın
ssh -i RefiaKeyPair.pem ubuntu@CONTROL_NODE_IP

# Switch yap
cd /home/ubuntu/ansible-project
ansible-playbook playbook.yml --tags switch
```

**Gözlem:** Terminal 1'de "Blue" → "Green" geçişi ~1 saniyede olmalı

**Neden:** Sıfır kesinti testi. Kullanıcılar geçişi fark etmez.

---

## 🔍 Troubleshooting

### Problem 1: SSH Connection Refused

**Hata:**
```
fatal: [db_server_phonebook]: UNREACHABLE! => {"msg": "Failed to connect"}
```

**Çözüm:**
```bash
# Security group kontrol
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=phonebook-sec-gr" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'

# Port 22 açık mı? Yoksa ekle:
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

---

### Problem 2: Vault Decrypt Hatası

**Hata:**
```
ERROR! Attempting to decrypt but no vault secrets found
```

**Çözüm:**
```bash
# Parameter Store'da şifre var mı?
aws ssm get-parameter --name "/ansible/phonebook/vault-password" --with-decryption

# Script çalışıyor mu?
./get-vault-password.sh

# ansible.cfg'de path doğru mu?
cat ansible.cfg | grep vault_password_file
```

---

### Problem 3: MySQL Connection Error

**Hata:**
```
Can't connect to MySQL server on 'X.X.X.X'
```

**Çözüm:**
```bash
# Control Node'dan MySQL server'a bağlan (private IP)
ssh -i /home/ubuntu/RefiaKeyPair.pem ubuntu@172.31.60.105

# bind-address kontrolü
sudo cat /etc/mysql/mysql.conf.d/mysqld.cnf | grep bind-address
# bind-address = 0.0.0.0 olmalı

# MySQL çalışıyor mu?
sudo systemctl status mysql

# Port 3306 açık mı?
sudo netstat -tlnp | grep 3306

exit  # DB server'dan çık
```

---

### Problem 4: ALB Health Check Failed

**Hata:**
```
Target health: unhealthy
```

**Çözüm:**
```bash
# Control Node'da - Target group health kontrolü
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...:targetgroup/phonebook-tg-green/...

# Green server'a bağlan (private IP)
ssh -i /home/ubuntu/RefiaKeyPair.pem ubuntu@172.31.62.143

# App çalışıyor mu?
ps aux | grep phonebook-app.py

# Port 80 açık mı?
curl http://localhost/health

# Restart app
sudo pkill -f phonebook-app.py
cd /home/ubuntu
sudo nohup python3 phonebook-app.py > /dev/null 2>&1 &

exit  # Green server'dan çık
```

---

### Problem 5: Slack Bildirimleri Gelmiyor

**Çözüm:**
```bash
# Control Node'da
cd /home/ubuntu/ansible-project

# Slack enabled mi?
cat roles/alb-switch/vars/main.yml | grep slack_enabled
# true olmalı

# Token doğru mu?
ansible-vault view group_vars/vault.yml | grep slack_token

# Manuel test
curl -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer xoxp-YOUR-TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"channel":"#channel","text":"Test"}'
```

---

## 📊 Deployment Logs

### Log Dosyalarının Yeri

```bash
# Control Node'da - Ansible deployment log
cat /var/log/ansible-deployment.log

# Flask app logs - Blue server (Control Node'dan)
ssh -i /home/ubuntu/RefiaKeyPair.pem ubuntu@172.31.61.201
tail -f /var/log/phonebook.log  # (eğer logging eklediyseniz)
exit

# MySQL logs - DB server (Control Node'dan)
ssh -i /home/ubuntu/RefiaKeyPair.pem ubuntu@172.31.60.105
sudo tail -f /var/log/mysql/error.log
exit
```

---

## 🎯 Sonraki Adımlar

### Yapmayı Düşünebilirsiniz:

1. **Domain Ekle:**
   - Route53'te domain alın (örn: phonebook.example.com)
   - ALB'ye CNAME ekleyin

2. **HTTPS Ekle:**
   - ACM'den SSL certificate alın
   - ALB'ye HTTPS listener ekleyin

3. **Monitoring:**
   - CloudWatch metrics
   - ALB access logs
   - X-Ray tracing

4. **CI/CD Pipeline:**
   - GitHub Actions
   - Automatic deployment on push

5. **Scaling:**
   - Auto Scaling Groups
   - Multiple availability zones

6. **Database Backup:**
   - RDS snapshot
   - Automated backups

---

## ✅ Final Checklist

Tüm adımları tamamladıysanız:

- [x] AWS altyapısı oluşturuldu (Terraform)
- [x] **4 EC2 instance çalışıyor** (Control Node + DB + Blue + Green)
- [x] **Control Node'a SSH ile bağlanıldı**
- [x] **Control Node'da Ansible yapılandırıldı**
- [x] ALB yapılandırıldı (eğer yorumlu değilse)
- [x] Ansible Vault setup tamamlandı (AWS Parameter Store)
- [x] Database deploy edildi ve çalışıyor
- [x] Blue server deploy edildi ve çalışıyor
- [x] Green server deploy edildi ve çalışıyor
- [x] Health check endpoint'leri çalışıyor
- [x] Blue → Green switch başarılı
- [x] Otomatik rollback test edildi
- [x] ALB üzerinden uygulama erişilebilir (veya public IP'ler ile)
- [x] Phonebook CRUD işlemleri çalışıyor

**🎉 TEBRİKLER! Production-ready Blue-Green Deployment projeniz hazır!**

**✨ Artık herkes aynı kurulumu kullanıyor:**
- Lokal makinede sadece Terraform ve SSH client gerekiyor
- Control Node'da tüm Ansible komutları çalışıyor
- Ubuntu 22.04 üzerinde herkes için aynı komutlar çalışıyor

---

## 📚 Ek Kaynaklar

- [Ansible Documentation](https://docs.ansible.com/)
- [AWS ALB Documentation](https://docs.aws.amazon.com/elasticloadbalancing/)
- [Blue-Green Deployment Patterns](https://martinfowler.com/bliki/BlueGreenDeployment.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

## 💡 Öğrenme Notları

Bu projede öğrendiğiniz Ansible konuları:

✅ **Temel:**
- Playbooks ve Roles
- Inventory yönetimi
- Ansible.cfg yapılandırması

✅ **İleri Seviye:**
- Ansible Vault
- AWS Parameter Store entegrasyonu
- Dynamic inventory
- Block-rescue-always error handling
- Pre-tasks ve post-tasks
- Tags ile selective execution
- Assert validations
- Health checks
- Handlers ve notifications

✅ **Best Practices:**
- Idempotency
- DRY (Don't Repeat Yourself)
- Secrets management
- Error handling
- Logging
- Testing

---

**Son Güncelleme:** 2024-12-09
**Proje Sahibi:** Ansible Bootcamp Capstone
**Lisans:** Educational Use
