# AWS EC2 Dynamic Inventory Setup

Bu dokümantasyon, Ansible'ın AWS EC2 instance'larını otomatik olarak keşfetmesi için dynamic inventory yapılandırmasını açıklar.

## 🎯 Neden Dynamic Inventory?

### Static Inventory (Şu anki)
```ini
[db_server]
db_server_phonebook ansible_host=44.222.85.252

[blue_servers]
blue_server_phonebook ansible_host=98.84.23.39
```
❌ **Problemler:**
- IP adresleri hardcoded
- Instance yeniden oluşturulduğunda manuel güncelleme gerekli
- Scaling için manuel değişiklik
- Terraform output'u elle kopyalamak gerekir

### Dynamic Inventory (Yeni)
```yaml
plugin: amazon.aws.aws_ec2
filters:
  tag:Project: phonebook
  instance-state-name: running
```
✅ **Avantajlar:**
- Otomatik instance keşfi
- IP adresleri otomatik çekilir
- Terraform ile tam entegrasyon
- Auto-scaling uyumlu
- Tag-based gruplandırma

---

## 📋 Gereksinimler

### 1. AWS Collection Kurulumu
```bash
ansible-galaxy collection install amazon.aws
```

### 2. Python Boto3 Kurulumu
```bash
pip3 install boto3 botocore
```

### 3. IAM Permissions
EC2 instance IAM role'üne şu policy eklenmelidir:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeTags",
        "ec2:DescribeRegions"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 🚀 Kullanım

### Statik Inventory (Eski Yöntem)
```bash
ansible-playbook playbook.yml -i inventory.ini
```

### Dynamic Inventory (Yeni Yöntem)
```bash
ansible-playbook playbook.yml -i inventory_aws_ec2.yml
```

---

## 📊 Terraform ile Entegrasyon

### EC2 Instance'lara Tag Ekleme

`terraform-files/main.tf` dosyanızda instance'lara doğru tag'leri ekleyin:

```hcl
# Database Server
resource "aws_instance" "db_server" {
  # ... other config ...

  tags = {
    Name        = "db_server_phonebook"
    Project     = "phonebook"
    Role        = "db_server"
    Environment = "production"
  }
}

# Blue Server
resource "aws_instance" "blue_server" {
  # ... other config ...

  tags = {
    Name        = "blue_server_phonebook"
    Project     = "phonebook"
    Role        = "blue_server"
    Color       = "blue"
    Environment = "production"
  }
}

# Green Server
resource "aws_instance" "green_server" {
  # ... other config ...

  tags = {
    Name        = "green_server_phonebook"
    Project     = "phonebook"
    Role        = "green_server"
    Color       = "green"
    Environment = "staging"
  }
}
```

---

## 🔍 Dynamic Inventory Test

### Inventory'yi Listele
```bash
ansible-inventory -i inventory_aws_ec2.yml --list
```

**Örnek Çıktı:**
```json
{
  "db_server_phonebook": {
    "hosts": ["db_server_phonebook"],
    "vars": {
      "ansible_host": "44.222.85.252",
      "ec2_instance_type": "t2.micro",
      "ec2_availability_zone": "us-east-1a"
    }
  },
  "blue_server_phonebook": {
    "hosts": ["blue_server_phonebook"]
  },
  "color_blue": {
    "hosts": ["blue_server_phonebook"]
  },
  "color_green": {
    "hosts": ["green_server_phonebook"]
  }
}
```

### Grupları Görüntüle
```bash
ansible-inventory -i inventory_aws_ec2.yml --graph
```

**Örnek Çıktı:**
```
@all:
  |--@db_server_phonebook:
  |  |--db_server_phonebook
  |--@blue_server_phonebook:
  |  |--blue_server_phonebook
  |--@green_server_phonebook:
  |  |--green_server_phonebook
  |--@color_blue:
  |  |--blue_server_phonebook
  |--@color_green:
  |  |--green_server_phonebook
  |--@env_production:
  |  |--db_server_phonebook
  |  |--blue_server_phonebook
  |--@env_staging:
  |  |--green_server_phonebook
```

### Ping Testi
```bash
ansible all -i inventory_aws_ec2.yml -m ping
```

---

## 🔧 Playbook Güncelleme

Dynamic inventory kullanmak için playbook'ta **hiçbir değişiklik gerekmez!**

Grup isimleri aynı kalır:
- `db_server_phonebook`
- `blue_server_phonebook`
- `green_server_phonebook`

```yaml
- name: Setup database server
  hosts: db_server_phonebook  # Aynı kalıyor!
  become: true
  roles:
    - mysql
```

---

## 🎓 Advanced Kullanım

### Sadece Blue Server'lara Deploy
```bash
ansible-playbook playbook.yml -i inventory_aws_ec2.yml --limit color_blue
```

### Sadece Production Environment
```bash
ansible-playbook playbook.yml -i inventory_aws_ec2.yml --limit env_production
```

### Specific Instance Type
```bash
ansible-playbook playbook.yml -i inventory_aws_ec2.yml \
  --extra-vars "target_instance_type=t2.micro"
```

---

## 🔄 Ansible.cfg Güncelleme

Dynamic inventory'yi default yapmak için `ansible.cfg`:

```ini
[defaults]
# Static inventory yerine dynamic inventory kullan
# inventory = inventory.ini  # EKSİ
inventory = inventory_aws_ec2.yml  # YENİ

# Enable inventory plugins
enable_plugins = amazon.aws.aws_ec2, ini, yaml
```

Sonra sadece:
```bash
ansible-playbook playbook.yml  # Otomatik olarak dynamic inventory kullanır
```

---

## 🐛 Troubleshooting

### Hata: "Unable to parse inventory"
**Çözüm:**
```bash
# Amazon.aws collection kurulu mu kontrol et
ansible-galaxy collection list | grep amazon.aws

# Kurulu değilse:
ansible-galaxy collection install amazon.aws
```

### Hata: "boto3 required for this module"
**Çözüm:**
```bash
pip3 install boto3 botocore
```

### Hata: "AuthFailure: AWS was not able to validate the provided access credentials"
**Çözüm:**
```bash
# IAM role kontrolü
aws sts get-caller-identity

# Instance metadata'dan IAM role
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

### Inventory boş döndürüyor
**Çözüm:**
```bash
# Tag'leri kontrol et
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=phonebook" \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags]' \
  --output table

# Instance durumunu kontrol et
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

---

## 📈 Cache Yönetimi

Dynamic inventory cache kullanır (performans için):

### Cache'i Temizle
```bash
rm -rf /tmp/ansible-aws-cache
```

### Cache'i Disable Et
```yaml
# inventory_aws_ec2.yml
cache: False
```

### Cache Timeout Ayarla
```yaml
# inventory_aws_ec2.yml
cache_timeout: 600  # 10 dakika
```

---

## ✅ Checklist

- [ ] `amazon.aws` collection kuruldu
- [ ] `boto3` ve `botocore` kuruldu
- [ ] IAM role EC2 instance'a attach edildi
- [ ] IAM policy EC2 describe permissions içeriyor
- [ ] Terraform ile instance'lara doğru tag'ler eklendi
- [ ] `inventory_aws_ec2.yml` test edildi (`ansible-inventory --list`)
- [ ] Playbook dynamic inventory ile çalıştırıldı
- [ ] `ansible.cfg` güncellendi (opsiyonel)

---

## 🚀 Production Best Practices

1. **Multi-Region Support**
   ```yaml
   regions:
     - us-east-1
     - eu-west-1
   ```

2. **Strict Mode**
   ```yaml
   strict: True  # Hata olursa fail et
   ```

3. **Custom Hostnames**
   ```yaml
   hostnames:
     - tag:Name
     - private-ip-address  # Public IP yoksa
   ```

4. **Performans**
   ```yaml
   cache: True
   cache_timeout: 3600  # 1 saat
   ```

---

## 📚 Referanslar

- [Ansible AWS EC2 Inventory Plugin](https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ec2_inventory.html)
- [Boto3 Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html)
- [AWS IAM Policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html)

---

**Not:** Dynamic inventory, infrastructure-as-code ve cloud-native deployment'lar için best practice'tir! 🎉
