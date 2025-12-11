# Ansible Vault with AWS Parameter Store Setup Guide

Bu dokümantasyon, Ansible Vault şifresini AWS Systems Manager Parameter Store'da güvenli bir şekilde saklamak için gerekli adımları açıklar.

## 🎯 Avantajlar

✅ **Şifre sormadan otomatik çalışır** - CI/CD için ideal
✅ **AWS KMS ile şifrelenir** - Enterprise-level güvenlik
✅ **IAM rolleri ile erişim kontrolü** - Fine-grained permissions
✅ **Şifreyi hiçbir yerde hardcode etmiyoruz** - Best practice
✅ **Team collaboration kolay** - Herkes aynı parametreyi kullanır

---

## 📋 Gereksinimler

1. AWS CLI kurulu olmalı
2. IAM permissions (SSM Parameter Store ve KMS)
3. EC2 instance'a IAM role attach edilmiş olmalı

---

## 🚀 Kurulum Adımları

### Adım 1: IAM Policy Oluştur

Control node'da (Ansible'ı çalıştırdığınız makine) IAM role'üne aşağıdaki policy'i ekleyin:

```bash
# IAM policy oluştur
aws iam create-policy \
  --policy-name AnsibleVaultSSMAccess \
  --policy-document file://iam-policy-ssm.json

# Policy'i mevcut IAM role'e attach et (EC2 instance role'ünüz varsa)
aws iam attach-role-policy \
  --role-name YourEC2InstanceRole \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/AnsibleVaultSSMAccess
```

**NOT:** Eğer EC2 instance'ınızda IAM role yoksa önce bir tane oluşturup attach etmelisiniz.

---

### Adım 2: Script'lere Execute Permission Ver

```bash
cd project/
chmod +x setup-vault-password.sh
chmod +x get-vault-password.sh
```

---

### Adım 3: Vault Şifresini Parameter Store'a Kaydet

```bash
./setup-vault-password.sh
```

Bu script:
- Size bir vault şifresi soracak (güvenli bir şifre girin)
- Şifreyi AWS Parameter Store'a kaydedecek (`/ansible/phonebook/vault-password`)
- SecureString olarak KMS ile şifreleyecek

**Örnek çıktı:**
```
=== Setup Ansible Vault Password in AWS Parameter Store ===

Enter your vault password (it will be hidden):
[şifrenizi girin]

Storing password in Parameter Store...
✓ Password successfully stored in Parameter Store: /ansible/phonebook/vault-password
```

---

### Adım 4: Vault Dosyasını Encrypt Et

Şimdi vault şifresini kullanarak `group_vars/vault.yml` dosyasını encrypt edin:

```bash
# Şifre otomatik olarak Parameter Store'dan çekilir
ansible-vault encrypt group_vars/vault.yml
```

**Başarılı ise görürsünüz:**
```
Encryption successful
```

Dosyayı kontrol edin:
```bash
cat group_vars/vault.yml
```

Şifrelenmiş içerik görmelisiniz:
```
$ANSIBLE_VAULT;1.1;AES256
66386439653865343839303039343266633361653031653837636533366337366239303431346662
...
```

---

### Adım 5: Test Et

```bash
# Vault dosyasını görüntüle (şifre otomatik çekilir)
ansible-vault view group_vars/vault.yml

# Vault dosyasını düzenle
ansible-vault edit group_vars/vault.yml

# Playbook çalıştır (şifre sormaz!)
ansible-playbook playbook.yml
```

---

## 🔧 Troubleshooting

### Hata: "Failed to retrieve vault password from Parameter Store"

**Çözüm 1:** IAM permissions kontrol edin
```bash
aws ssm get-parameter \
  --name "/ansible/phonebook/vault-password" \
  --with-decryption \
  --region us-east-1
```

**Çözüm 2:** IAM role EC2 instance'a attach edilmiş mi?
```bash
# Instance metadata'dan role kontrol et
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

**Çözüm 3:** Parameter Store'da parametre var mı?
```bash
aws ssm describe-parameters --region us-east-1 | grep ansible
```

---

### Hata: "An error occurred (AccessDeniedException)"

IAM policy'nizi kontrol edin. Gerekli permissions:
- `ssm:GetParameter`
- `ssm:PutParameter`
- `kms:Decrypt`

---

### Hata: "get-vault-password.sh: Permission denied"

Execute permission verin:
```bash
chmod +x get-vault-password.sh
```

---

## 📊 Parameter Store'u Yönetme

### Şifreyi Güncelle

```bash
./setup-vault-password.sh  # Yeni şifre gireceksiniz
```

Sonra vault dosyasını yeni şifreyle yeniden encrypt edin:
```bash
ansible-vault rekey group_vars/vault.yml
```

### Şifreyi Görüntüle (Debugging için)

```bash
aws ssm get-parameter \
  --name "/ansible/phonebook/vault-password" \
  --with-decryption \
  --region us-east-1 \
  --query 'Parameter.Value' \
  --output text
```

### Parametreyi Sil

```bash
aws ssm delete-parameter \
  --name "/ansible/phonebook/vault-password" \
  --region us-east-1
```

---

## 🔐 Security Best Practices

1. ✅ **IAM Roles kullanın** - Access key'ler kullanmayın
2. ✅ **Least privilege** - Sadece gerekli parametrelere erişim
3. ✅ **CloudTrail enable** - Parameter erişimlerini audit edin
4. ✅ **KMS custom key** - Default KMS key yerine custom key kullanın (opsiyonel)
5. ✅ **Parameter versioning** - AWS otomatik versiyon tutar
6. ✅ **Farklı environment'ler** - Dev/Prod için ayrı parametreler

---

## 🎓 Advanced: Custom KMS Key Kullanma

Daha fazla kontrol için custom KMS key oluşturabilirsiniz:

```bash
# KMS key oluştur
aws kms create-key \
  --description "Ansible Vault encryption key"

# Key ID'yi alın ve setup script'i güncelleyin:
aws ssm put-parameter \
  --name "/ansible/phonebook/vault-password" \
  --value "YourPassword" \
  --type "SecureString" \
  --key-id "your-kms-key-id" \
  --region us-east-1
```

---

## 📚 Referanslar

- [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [AWS KMS](https://docs.aws.amazon.com/kms/latest/developerguide/overview.html)

---

## ✅ Checklist

- [ ] IAM policy oluşturuldu ve role'e attach edildi
- [ ] Script'lere execute permission verildi
- [ ] `setup-vault-password.sh` çalıştırıldı ve şifre kaydedildi
- [ ] `ansible-vault encrypt group_vars/vault.yml` çalıştırıldı
- [ ] `ansible-playbook playbook.yml` test edildi (şifre sormadan çalışmalı)
- [ ] Vault dosyası `.gitignore`'a eklendi (opsiyonel)

---

**Not:** Bu setup bir kere yapıldıktan sonra, Ansible playbook'larınız hiç şifre sormadan çalışacaktır! 🚀
