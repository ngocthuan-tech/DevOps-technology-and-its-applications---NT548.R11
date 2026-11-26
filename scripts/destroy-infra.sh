#!/usr/bin/env bash
# Xóa hạ tầng NT548 theo ĐÚNG thứ tự để không sót tài nguyên tính tiền.
#   ./scripts/destroy-infra.sh          → xóa eks + network (giữ iam, ecr vì gần như miễn phí)
#   ./scripts/destroy-infra.sh --all    → xóa sạch cả 4 stack (dùng ngày 02/12)
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-1}"
PROJECT="nt548"
CLUSTER="nt548-eks"
ALL="${1:-}"

stack_exists() {
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$1" >/dev/null 2>&1
}

delete_stack() {
  local name="$1"
  if stack_exists "$name"; then
    echo "==> [$(date +%H:%M)] Đang xóa stack $name ..."
    aws cloudformation delete-stack --region "$REGION" --stack-name "$name"
    aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$name"
    echo "==> [$(date +%H:%M)] Đã xóa $name"
  else
    echo "==> Stack $name không tồn tại, bỏ qua"
  fi
}

echo "==> Tài khoản: $(aws sts get-caller-identity --query Arn --output text) | Region: $REGION"

# ---------- Bước 1: dọn tài nguyên do Kubernetes tạo NGOÀI CloudFormation ----------
# Service type LoadBalancer tạo ra ELB + Security Group mà CloudFormation không biết.
# Không dọn trước thì: ELB vẫn tính tiền và stack network bị DELETE_FAILED (VPC còn phụ thuộc).
if stack_exists "$PROJECT-eks"; then
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null 2>&1 || true

  echo "==> Xóa ArgoCD Application trước (nếu không, selfHeal sẽ tạo lại Service vừa xóa)"
  kubectl delete applications.argoproj.io --all -n argocd --timeout=180s 2>/dev/null || true

  echo "==> Xóa mọi Service type LoadBalancer còn sót"
  kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | while read -r ns name; do
        [ -n "$ns" ] && kubectl delete svc "$name" -n "$ns" --timeout=120s || true
      done
fi

# ---------- Bước 2: chờ AWS xóa hẳn Load Balancer trong VPC ----------
VPC_ID="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$PROJECT-network" \
  --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" --output text 2>/dev/null || true)"
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  echo "==> Chờ Load Balancer trong $VPC_ID biến mất (tối đa 5 phút)"
  for i in $(seq 1 30); do
    n2=$(aws elbv2 describe-load-balancers --region "$REGION" --query "length(LoadBalancers[?VpcId=='$VPC_ID'])" --output text)
    n1=$(aws elb describe-load-balancers --region "$REGION" --query "length(LoadBalancerDescriptions[?VPCId=='$VPC_ID'])" --output text)
    [ "$n1" = "0" ] && [ "$n2" = "0" ] && { echo "    Không còn Load Balancer."; break; }
    echo "    Còn $n1 classic + $n2 ALB/NLB, chờ 10s... ($i/30)"
    sleep 10
  done
fi

# ---------- Bước 3: xóa stack theo thứ tự ngược với lúc dựng ----------
delete_stack "$PROJECT-eks"       # ~10–15 phút
delete_stack "$PROJECT-network"
if [ "$ALL" = "--all" ]; then
  delete_stack "$PROJECT-ecr"
  delete_stack "$PROJECT-iam"
fi

# ---------- Bước 4: kiểm tra lần cuối ----------
echo
echo "==> Kiểm tra tài nguyên tính tiền còn sót trong $REGION (tất cả phải là 0):"
echo "    EC2 đang chạy : $(aws ec2 describe-instances --region "$REGION" --filters Name=instance-state-name,Values=running,pending Name=tag:eks:cluster-name,Values=$CLUSTER --query 'length(Reservations[].Instances[])' --output text)"
echo "    NAT Gateway   : $(aws ec2 describe-nat-gateways --region "$REGION" --filter Name=tag:Project,Values=$PROJECT Name=state,Values=available,pending --query 'length(NatGateways)' --output text)"
echo "    Elastic IP    : $(aws ec2 describe-addresses --region "$REGION" --filters Name=tag:Project,Values=$PROJECT --query 'length(Addresses)' --output text)"
echo "    EKS cluster   : $(aws eks list-clusters --region "$REGION" --query "length(clusters[?@=='$CLUSTER'])" --output text)"
echo
echo "==> Xong. Nhớ báo nhóm: \"Cluster đã tắt\"."
