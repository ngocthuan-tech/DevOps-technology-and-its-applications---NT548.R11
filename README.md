# DevOps-technology-and-its-applications---NT548.R11

**Đồ án môn NT548.R11 – Công nghệ DevOps và Ứng dụng (UIT)**
Xây dựng quy trình DevSecOps tích hợp AI và phân phối tự động GitOps cho ứng dụng Microservices trên AWS EKS.

> 📌 **Thành viên nhóm đọc `docs/00-tong-quan.md` trước tiên.** Phần việc của từng người nằm trong `docs/team/`.

## Kiến trúc tổng quan

```
Dev push/PR ─► GitHub Actions: test → SonarCloud → build (multi-stage) → Trivy → AI (Gemini) → push ECR
                                                                                       │
                     repo nt548-gitops (image tag) ◄──────── cập nhật tag ─────────────┘
                              │ ArgoCD (pull, tự đồng bộ)
                              ▼
          Amazon EKS (2 node private subnet): frontend → api → redis
                              │
                    Prometheus + Grafana giám sát
Hạ tầng: AWS CloudFormation (network / iam / eks / ecr) · Region ap-southeast-1
```

## Công nghệ

| Lớp | Công cụ |
|---|---|
| IaC | AWS CloudFormation (+ cfn-lint, Checkov) |
| CI | GitHub Actions, đăng nhập AWS bằng OIDC |
| Bảo mật | SonarCloud (SAST), Trivy (quét image) |
| AI | Google Gemini API: tổng hợp, xếp ưu tiên, đề xuất khắc phục |
| Registry | Amazon ECR |
| CD / GitOps | ArgoCD + Kustomize |
| Runtime | Amazon EKS |
| Giám sát | Prometheus + Grafana (kube-prometheus-stack) |

## Cấu trúc repo

```
services/            frontend + api (Flask), test, Dockerfile multi-stage
infra/cloudformation network.yaml, iam.yaml, eks.yaml, ecr.yaml
scripts/             deploy-infra.sh, destroy-infra.sh, bootstrap-argocd.sh
ai-analyzer/         thành phần AI phân tích kết quả bảo mật
.github/workflows/   ci.yml, iac-lint.yml
docs/                tổng quan, phân công, báo cáo, ảnh
```

## Ứng dụng

| Service | Cổng | Endpoint |
|---|---|---|
| frontend | 8080 | `/`, `/health` |
| api | 5000 | `/api/visits`, `/api/info`, `/health` (liveness), `/ready` (readiness) |
| redis | 6379 | image chính thức `redis:7.4-alpine` |

Biến môi trường: `APP_VERSION` (CI gắn = commit SHA), `API_URL`, `REDIS_HOST`, `REDIS_PORT`.

### Chạy local
```bash
docker compose up --build      # mở http://localhost:8080, F5 thấy số lượt tăng
docker compose down
```

### Chạy test
```bash
pip install -r services/api/requirements.txt -r services/api/requirements-dev.txt
pytest services/api --cov=services/api
```

## Quy tắc làm việc
- Không push thẳng vào `main`. Làm trên nhánh `feat/<người>-<việc>` rồi mở Pull Request.
- Không commit `.env`, access key, kubeconfig, token.
- Chi tiết: `docs/00-tong-quan.md` mục 5.6.

## Thành viên

| Thành viên | Phần phụ trách |
|---|---|
| Nguyễn Ngọc Thuận | Hạ tầng (CloudFormation, EKS), CI, GitOps, tích hợp |
| TV1 | DevSecOps (SonarCloud, Trivy), ghép báo cáo |
| TV2 | AI Security Analyzer, slide |
| TV3 | Giám sát (Prometheus/Grafana), quét IaC, vận hành demo |

## License
MIT
