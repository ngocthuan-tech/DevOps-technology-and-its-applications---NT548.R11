# Hạ tầng AWS bằng CloudFormation

4 stack độc lập, dựng theo thứ tự và xóa theo thứ tự ngược lại. Region: `ap-southeast-1`.

| Thứ tự | Stack | Template | Tạo ra | Tốn tiền? |
|---|---|---|---|---|
| 1 | `nt548-network` | `network.yaml` | VPC, 2 public + 2 private subnet (2 AZ), IGW, **1 NAT**, S3 Gateway Endpoint | NAT ~$0.05/giờ |
| 2 | `nt548-iam` | `iam.yaml` | Role cho EKS cluster, role cho node, OIDC + role cho GitHub Actions | Miễn phí |
| 3 | `nt548-ecr` | `ecr.yaml` | Repo `nt548/frontend`, `nt548/api` (immutable tag, scan on push, giữ 10 image) | Gần như 0 |
| 4 | `nt548-eks` | `eks.yaml` | EKS cluster + 2 node t3.medium ở private subnet + quyền kubectl cho TV3 | **~$0.20/giờ** |

## Sơ đồ mạng

```
                         Internet
                            │
                    Internet Gateway
   ┌────────────── VPC 10.0.0.0/16 ──────────────────────────┐
   │   AZ a                              AZ b                │
   │  ┌ public 10.0.0.0/24 ┐            ┌ public 10.0.1.0/24 ┐│
   │  │ NAT GW, LB frontend │            │ LB frontend        ││
   │  └─────────┬───────────┘            └────────────────────┘│
   │            │ 0.0.0.0/0 (private route table)              │
   │  ┌ private 10.0.10.0/24 ┐           ┌ private 10.0.11.0/24 ┐
   │  │ node EKS #1          │           │ node EKS #2          │
   │  └──────────────────────┘           └──────────────────────┘
   │        S3 Gateway Endpoint (kéo layer image ECR, không qua NAT)
   └──────────────────────────────────────────────────────────┘
```

## Cách các stack nói chuyện với nhau

- `network` và `iam` **export** giá trị (ID subnet, ARN role). `eks` **import** bằng `Fn::ImportValue`.
- Khi `eks` còn đang import thì CloudFormation **không cho xóa** `network`/`iam` → ép xóa đúng thứ tự.

## Lệnh

```bash
export AWS_PROFILE=nt548-admin   # profile của user a-admins
./scripts/deploy-infra.sh        # dựng (~25–30 phút)
./scripts/destroy-infra.sh       # xóa eks + network sau MỖI phiên
./scripts/destroy-infra.sh --all # xóa sạch (ngày 02/12)
```

## Các lựa chọn và lý do (dùng cho báo cáo / vấn đáp)

| Lựa chọn | Lý do |
|---|---|
| Node ở private subnet | Node không có IP public, Internet không chạm trực tiếp được |
| 1 NAT thay vì 2 | Tiết kiệm ~50% phí NAT; đánh đổi: AZ chứa NAT hỏng thì node AZ kia mất đường ra Internet |
| S3 Gateway Endpoint | Miễn phí, giảm phí dữ liệu qua NAT khi kéo image |
| `UpgradePolicy: STANDARD` | Không bao giờ rơi vào Extended Support ($0.60/giờ thay vì $0.10) |
| Access Entry (`AuthenticationMode: API`) | Phân quyền kubectl bằng IAM, khai báo trong code; TV3 chỉ có quyền `edit` |
| OIDC cho GitHub Actions | Không có access key dài hạn; chỉ nhánh `main` của đúng repo mới nhận được role |
| ECR `IMMUTABLE` | Tag = commit SHA, không ai ghi đè được image đã phát hành |
