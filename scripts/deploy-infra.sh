#!/usr/bin/env bash
# Dựng toàn bộ hạ tầng NT548 theo đúng thứ tự: network → iam → ecr → eks (~25–30 phút)
# Chạy bằng Git Bash (Windows) hoặc Terminal (macOS/Linux):
#   export AWS_PROFILE=nt548-admin      # profile của user a-admins
#   ./scripts/deploy-infra.sh
# Tùy chọn: CREATE_OIDC=false OIDC_ARN=<arn có sẵn> ./scripts/deploy-infra.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-1}"
PROJECT="nt548"
CLUSTER="nt548-eks"
DIR="$(cd "$(dirname "$0")/../infra/cloudformation" && pwd)"
CREATE_OIDC="${CREATE_OIDC:-true}"
OIDC_ARN="${OIDC_ARN:-}"

echo "==> Tài khoản đang dùng:"
aws sts get-caller-identity --query '[Account, Arn]' --output text
echo "==> Region: $REGION"
read -r -p "Đúng tài khoản và region? Gõ y để tiếp tục: " ok
[ "$ok" = "y" ] || { echo "Đã hủy."; exit 1; }

# Hàm dựng 1 stack. "aws cloudformation deploy" tự tạo mới hoặc cập nhật, và CHỜ đến khi xong.
deploy() {
  local name="$1" file="$2"; shift 2
  echo
  echo "==> [$(date +%H:%M)] Đang dựng stack $name ..."
  aws cloudformation deploy \
    --region "$REGION" \
    --stack-name "$name" \
    --template-file "$DIR/$file" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --tags Project="$PROJECT" \
    "$@"
  echo "==> [$(date +%H:%M)] Xong $name"
}

deploy "$PROJECT-network" network.yaml
deploy "$PROJECT-iam"     iam.yaml \
  --parameter-overrides CreateOidcProvider="$CREATE_OIDC" ExistingOidcProviderArn="$OIDC_ARN"
deploy "$PROJECT-ecr"     ecr.yaml
echo "(Stack EKS mất ~15–20 phút. Trong lúc chờ có thể xem tab Events trên CloudFormation console.)"
deploy "$PROJECT-eks"     eks.yaml

echo
echo "==> Cấu hình kubectl"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"
kubectl get nodes -o wide

echo
echo "==> Các giá trị cần dán vào GitHub (Settings → Secrets and variables → Actions):"
echo -n "  Secret   AWS_ROLE_ARN = "
aws cloudformation describe-stacks --region "$REGION" --stack-name "$PROJECT-iam" \
  --query "Stacks[0].Outputs[?OutputKey=='GitHubActionsRoleArn'].OutputValue" --output text
echo -n "  Variable ECR_REGISTRY = "
aws cloudformation describe-stacks --region "$REGION" --stack-name "$PROJECT-ecr" \
  --query "Stacks[0].Outputs[?OutputKey=='RegistryUri'].OutputValue" --output text

echo
echo "!!! CLUSTER ĐANG TÍNH TIỀN (~\$0.30/giờ). Làm xong nhớ chạy: ./scripts/destroy-infra.sh"
