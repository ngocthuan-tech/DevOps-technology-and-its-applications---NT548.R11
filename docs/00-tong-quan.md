# 00 — TỔNG QUAN ĐỀ TÀI (cả nhóm đọc trước khi làm)

> Môn **NT548 – DevOps và Ứng dụng**.
> Đây là **nguồn sự thật chung** của nhóm. Mọi tên, đường dẫn và quy ước trong file này là **cố định**. Muốn đổi thì phải báo Thuận và cả nhóm trước.
> Nếu bạn dùng AI hỗ trợ: dán **file này kèm file phân việc của bạn**. Nếu AI đề xuất đổi công cụ, đổi tên hay đổi kiến trúc, **không làm theo**, hỏi Thuận trước.

---

## 1. Đề tài

**Xây dựng quy trình DevSecOps tích hợp AI và phân phối tự động GitOps cho ứng dụng Microservices trên AWS EKS.**

- Phạm vi: **Phương án B, tối giản nhưng đủ yêu cầu đề**.
- Thời gian: **19/11 → 02/12/2026** (14 ngày). Giờ trong file này là giờ Việt Nam (UTC+7).

## 2. Luồng tổng thể (phải thuộc)

```
Dev mở PR hoặc push vào main (repo nt548-app)
  │
  ▼ GitHub Actions (.github/workflows/ci.yml)
  [test]            pytest + coverage                                  (Thuận)
  [sonar]           SonarCloud phân tích code → Quality Gate. FAIL = DỪNG   (TV1)
  [build-scan-push] build image multi-stage → Trivy xuất JSON →
                    Trivy chặn HIGH/CRITICAL đã có bản vá. FAIL = DỪNG       (Thuận + TV1)
                    → (chỉ khi push main) đăng nhập AWS bằng OIDC → push ECR (Thuận)
  [ai-report]       đọc JSON của Sonar + Trivy → Gemini → báo cáo Markdown
                    KHÔNG BAO GIỜ chặn pipeline                         (TV2)
  [update-gitops]   (chỉ khi push main) sửa image tag trong nt548-gitops   (Thuận)
  [iac-lint]        workflow riêng, chạy khi sửa infra/: cfn-lint (+ Checkov) (TV3)
  │
  ▼ Repo nt548-gitops (Git = trạng thái mong muốn)
  ArgoCD (chạy trong EKS) thấy Git thay đổi → tự sync
  │
  ▼ EKS "nt548-eks" (2 node t3.medium ở private subnet)
  namespace app        : frontend (Service LoadBalancer) → api → redis
  namespace argocd     : ArgoCD
  namespace monitoring : Prometheus + Grafana                          (TV3)

Hạ tầng bên dưới: CloudFormation gồm 4 stack network / iam / eks / ecr  (Thuận)
```

**Nguyên tắc cốt lõi:**
1. **Chặn phát hành là việc của Quality Gate (Sonar) và Trivy**, vì kết quả của chúng xác định được. **AI chỉ tư vấn**, không bao giờ quyết định chặn.
2. **Quét đúng image sẽ phát hành**: image được build một lần, quét, rồi push đúng image đó. Không build lại.
3. **CI không đụng vào cluster.** CI chỉ ghi vào Git, ArgoCD tự kéo về (mô hình pull). Vì vậy GitHub Actions không cần quyền vào EKS.
4. **Không có access key AWS dài hạn trong GitHub.** GitHub Actions đăng nhập AWS bằng OIDC để nhận một IAM Role tạm thời.

## 3. Các quyết định đã chốt

| Hạng mục | Chốt | Ghi chú |
|---|---|---|
| Region AWS | `ap-southeast-1` (Singapore) | Mọi tài nguyên đều ở region này |
| App | Tự viết, 3 service: `frontend` (Python Flask), `api` (Python Flask), `redis` (image chính thức) | CI chỉ build `frontend` và `api` |
| Ngôn ngữ / phiên bản | Python **3.12**, pytest, pytest-cov | |
| IaC | **CloudFormation**, 4 template độc lập | Không dùng Terraform |
| Container registry | Amazon ECR | |
| CI | GitHub Actions | |
| SAST | **SonarCloud** (tên mới: SonarQube Cloud) | Cần repo **public** |
| Quét image | **Trivy** | Chặn `HIGH,CRITICAL` khi đã có bản vá (`--ignore-unfixed`) |
| AI | **Google Gemini API, free tier** | Tên model đặt trong biến `GEMINI_MODEL` |
| GitOps | **ArgoCD** + **Kustomize** | Mô hình app-of-apps |
| Monitoring | **kube-prometheus-stack** (Helm chart, cài qua ArgoCD) | Không bật lưu trữ bền (persistence) |
| Kubernetes | EKS, **phiên bản mới nhất còn trong standard support** | Không dùng bản extended support (đắt hơn 6 lần) |
| Node | Managed Node Group, **2 × t3.medium**, private subnet | Mỗi node tối đa 17 Pod |
| Truy cập ArgoCD và Grafana | `kubectl port-forward` | **Không** mở LoadBalancer cho ArgoCD hay Grafana |
| Mở app ra internet | `Service type: LoadBalancer` cho `frontend` | Không cài AWS Load Balancer Controller (giữ phạm vi B) |

## 4. Kiến trúc mạng AWS (đúng chuẩn)

- 1 VPC `10.0.0.0/16`, trải trên **2 AZ** (EKS bắt buộc tối thiểu 2 AZ).
- **2 public subnet**: chứa Internet Gateway, **1 NAT Gateway** (đặt ở 1 AZ) và Load Balancer của frontend. Gắn tag `kubernetes.io/role/elb = 1`.
- **2 private subnet**: chứa 2 worker node. Route `0.0.0.0/0` đi qua NAT. Gắn tag `kubernetes.io/role/internal-elb = 1`.
- **S3 Gateway Endpoint** (miễn phí): các layer image kéo từ ECR không phải đi qua NAT.
- Node **không có IP public**.
- **Đánh đổi có chủ đích, phải ghi trong báo cáo:** chỉ dùng 1 NAT ở 1 AZ để tiết kiệm. Nếu AZ đó hỏng, node ở AZ còn lại mất đường ra internet. Môi trường production sẽ dùng mỗi AZ một NAT.

## 5. HỢP ĐỒNG TÍCH HỢP (quan trọng nhất, không ai được tự đổi)

### 5.1. Repo và cấu trúc thư mục

Chủ repo: `ngocthuan-tech`. Cả hai repo để **public**. Thành viên được thêm làm **collaborator**. **Không fork**, vì PR từ fork không đọc được secrets.

**Repo 1: `ngocthuan-tech/DevOps-technology-and-its-applications---NT548.R11`**. Trong các tài liệu của nhóm, repo này được **gọi tắt là `nt548-app`** (code, pipeline, IaC, tài liệu).
Link: https://github.com/ngocthuan-tech/DevOps-technology-and-its-applications---NT548.R11
```
nt548-app/
├── services/
│   ├── frontend/        app.py, requirements.txt, requirements-dev.txt, tests/, Dockerfile   (Thuận)
│   └── api/             app.py, requirements.txt, requirements-dev.txt, tests/, Dockerfile   (Thuận)
├── infra/cloudformation/ network.yaml, iam.yaml, eks.yaml, ecr.yaml                          (Thuận)
├── scripts/             deploy-infra.sh, destroy-infra.sh, bootstrap-argocd.sh                (Thuận)
├── ai-analyzer/         analyze.py, ..., prompts/, samples/, tests/, README.md                (TV2)
├── .github/
│   ├── workflows/ci.yml                                                                      (Thuận, có khối của TV1/TV2)
│   ├── workflows/iac-lint.yml                                                                (TV3)
│   └── actions/trivy-scan/action.yml                                                         (TV1)
├── sonar-project.properties                                                                  (TV1)
├── .trivyignore                                                                              (TV1)
└── docs/
    ├── 00-tong-quan.md   (chính file này)
    ├── devsecops.md (TV1) · ai-analyzer.md (TV2) · monitoring.md (TV3)
    ├── report/           các phần báo cáo NN-*.md (mỗi người viết phần mình)
    └── images/           ảnh chụp màn hình (đặt tên theo mục 12)
```

**Repo 2: `ngocthuan-tech/nt548-gitops`** (trạng thái mong muốn của cluster)
```
nt548-gitops/
├── apps/
│   ├── root.yaml                         app-of-apps, trỏ vào apps/children/        (Thuận)
│   └── children/
│       ├── microservices.yaml            Application → microservices/                (Thuận)
│       ├── monitoring.yaml               Application → chart kube-prometheus-stack    (TV3)
│       └── monitoring-dashboards.yaml    Application → monitoring/dashboards/         (TV3)
├── microservices/                        Kustomize: namespace, deployment, service    (Thuận)
│   └── kustomization.yaml                ← CI sửa image tag ở ĐÂY
└── monitoring/
    └── dashboards/                       ConfigMap dashboard Grafana                  (TV3)
```

### 5.2. Tên tài nguyên cố định

| Tài nguyên | Tên |
|---|---|
| CloudFormation stacks | `nt548-network`, `nt548-iam`, `nt548-eks`, `nt548-ecr` |
| EKS cluster | `nt548-eks` |
| Node group | `nt548-nodes` |
| ECR repositories | `nt548/frontend`, `nt548/api` |
| Namespaces | `app`, `argocd`, `monitoring` |
| Tên Kubernetes Service | `frontend` (port 80 → 8080), `api` (port 5000), `redis` (6379) |
| Image tag | **Full commit SHA** (`${{ github.sha }}`). **Cấm dùng `latest`** |
| Tag AWS trên mọi tài nguyên | `Project=nt548` |

### 5.3. Pipeline: tên job, người phụ trách, artifact

| Job | Chạy khi | Người phụ trách | Artifact xuất ra |
|---|---|---|---|
| `test` | PR + push main | Thuận | `coverage-frontend`, `coverage-api` (file `coverage-<svc>.xml`) |
| `sonar` (needs: test) | PR + push main | TV1 | `report-sonar` (các file `sonar-issues.json`, `sonar-hotspots.json`, `sonar-qualitygate.json`) |
| `build-scan-push` (needs: sonar, matrix 2 service) | PR + push main; **chỉ push ECR khi push main** | Thuận + TV1 (bước Trivy) | `report-trivy-frontend`, `report-trivy-api` (file `trivy-<svc>.json`) |
| `ai-report` (needs: sonar, build-scan-push, `if: always()`) | PR + push main | TV2 | `ai-security-report` (file `ai-security-report.md`) |
| `update-gitops` (needs: build-scan-push) | **chỉ push main** | Thuận | (commit vào nt548-gitops) |

**Quy tắc đặt tên artifact:** mọi báo cáo bảo mật đều có tiền tố `report-`. Nhờ vậy job `ai-report` tải về bằng `pattern: report-*` cùng `merge-multiple: true` và nhận tất cả file vào thư mục `reports/`.

**Khung `ci.yml`** (Thuận hoàn thiện; TV1 và TV2 chỉ sửa trong khối có tên mình, và sửa qua PR):

```yaml
name: ci
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

env:
  AWS_REGION: ap-southeast-1
  PYTHON_VERSION: "3.12"

jobs:
  # ===== [Thuận] =====
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [frontend, api]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "${{ env.PYTHON_VERSION }}" }
      - run: pip install -r services/${{ matrix.service }}/requirements.txt -r services/${{ matrix.service }}/requirements-dev.txt
      - run: pytest services/${{ matrix.service }} --cov=services/${{ matrix.service }} --cov-report=xml:coverage-${{ matrix.service }}.xml
      - uses: actions/upload-artifact@v4
        with:
          name: coverage-${{ matrix.service }}
          path: coverage-${{ matrix.service }}.xml

  # ===== [TV1] BẮT ĐẦU: job sonar =====
  sonar:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - run: echo "TV1 điền theo file 01"
  # ===== [TV1] KẾT THÚC =====

  # ===== [Thuận] build/push; bước Trivy là của [TV1] =====
  build-scan-push:
    needs: sonar
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write          # cần cho OIDC
    strategy:
      fail-fast: false         # service này lỗi thì service kia vẫn được quét, AI có đủ dữ liệu
      matrix:
        service: [frontend, api]
    steps:
      - uses: actions/checkout@v4
      - name: Build image (multi-stage)
        run: docker build -t local/${{ matrix.service }}:${{ github.sha }} services/${{ matrix.service }}
      # --- [TV1] ---
      - uses: ./.github/actions/trivy-scan
        with:
          image-ref: local/${{ matrix.service }}:${{ github.sha }}
          service: ${{ matrix.service }}
      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: report-trivy-${{ matrix.service }}
          path: reports/trivy-${{ matrix.service }}.json
          if-no-files-found: ignore
      # --- [Thuận] chỉ push khi là push vào main ---
      - if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      - if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        id: ecr
        uses: aws-actions/amazon-ecr-login@v2
      - if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          IMAGE=${{ steps.ecr.outputs.registry }}/nt548/${{ matrix.service }}:${{ github.sha }}
          docker tag local/${{ matrix.service }}:${{ github.sha }} "$IMAGE"
          docker push "$IMAGE"

  # ===== [TV2] BẮT ĐẦU: job ai-report =====
  ai-report:
    needs: [sonar, build-scan-push]
    if: always()
    runs-on: ubuntu-latest
    continue-on-error: true    # AI lỗi cũng không làm đỏ pipeline
    steps:
      - run: echo "TV2 điền theo file 02"
  # ===== [TV2] KẾT THÚC =====

  # ===== [Thuận] =====
  update-gitops:
    needs: build-scan-push
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: echo "Checkout nt548-gitops bằng GITOPS_TOKEN → kustomize edit set image → commit, push"
```

> Các phiên bản action (`@v4`, `@v5`…) phải được kiểm tra lại với bản mới nhất khi viết. Action bên thứ ba (Sonar, Trivy) phải **ghim một phiên bản cụ thể**, không dùng `@master`.

### 5.4. Định dạng file báo cáo (giao giữa TV1 và TV2)

| File | Ai tạo | Định dạng |
|---|---|---|
| `reports/trivy-frontend.json`, `reports/trivy-api.json` | TV1 | Định dạng JSON gốc của Trivy (`--format json`), mọi mức độ, **gồm cả lỗi chưa có bản vá** |
| `reports/sonar-issues.json` | TV1 | Kết quả gốc của API `GET /api/issues/search` |
| `reports/sonar-hotspots.json` | TV1 | Kết quả gốc của API `GET /api/hotspots/search` |
| `reports/sonar-qualitygate.json` | TV1 | Kết quả gốc của API `GET /api/qualitygates/project_status` |
| `reports/ai-security-report.md` | TV2 | Markdown, cấu trúc theo file 02 |

**File nào cũng có thể thiếu** (ví dụ Sonar fail sớm). TV2 phải xử lý được trường hợp này.

### 5.5. Secrets và Variables của repo `nt548-app`

Chỉ Thuận thêm vào GitHub (Settings → Secrets and variables → Actions). **Không gửi giá trị secret qua nhóm chat.** Gửi riêng hoặc người tạo tự thêm vào nếu có quyền.

| Tên | Loại | Ai cung cấp | Dùng ở |
|---|---|---|---|
| `AWS_ROLE_ARN` | Secret | Thuận (output của stack `nt548-iam`) | build-scan-push |
| `SONAR_TOKEN` | Secret | TV1 | sonar |
| `GEMINI_API_KEY` | Secret | TV2 | ai-report |
| `GITOPS_TOKEN` | Secret | Thuận (fine-grained PAT, chỉ quyền ghi vào repo nt548-gitops) | update-gitops |
| `SONAR_ORGANIZATION`, `SONAR_PROJECT_KEY` | Variable | TV1 | sonar |
| `GEMINI_MODEL` | Variable | TV2 | ai-report |
| `ECR_REGISTRY` | Variable | Thuận (`<AWS_ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com`) | update-gitops |

### 5.6. Quy tắc Git

- **Không ai push thẳng vào `main`.** Làm trên nhánh `feat/<người>-<việc>` (ví dụ `feat/tv1-trivy`), rồi mở PR. Thuận review và merge.
- Commit message ngắn, có tiền tố: `feat:`, `fix:`, `docs:`, `ci:`.
- **Không bao giờ commit:** `.env`, access key, kubeconfig, token, file `*.pem`. Repo public thì key lộ sẽ bị bot quét trong vài phút.
- Bật **Secret scanning + Push protection** trong cài đặt repo (miễn phí với repo public).

## 6. Phân công

| Người | Phần việc | File hướng dẫn |
|---|---|---|
| **Thuận** (hạ tầng + tích hợp, giữ quyền merge) | App mẫu + Dockerfile multi-stage; CloudFormation 4 stack; OIDC + IAM; khung `ci.yml`, push ECR, update-gitops; repo gitops + ArgoCD; quản lý tài khoản AWS, budget, bật/tắt cluster | File này |
| **TV1** – DevSecOps + **Ghép báo cáo** | SonarCloud + Quality Gate; Trivy composite action; JSON cho AI; kịch bản demo "bị chặn"; **khung báo cáo, ghép báo cáo hoàn chỉnh** | `01-TV1-DEVSECOPS-SONAR-TRIVY.md` |
| **TV2** – AI + **Slide** | AI Security Analyzer (Python + Gemini); job `ai-report`; comment vào PR; **sơ đồ kiến trúc, slide, kịch bản demo** | `02-TV2-AI-SECURITY-ANALYZER.md` |
| **TV3** – Monitoring + Quét IaC + Vận hành demo | kube-prometheus-stack qua ArgoCD; dashboard Grafana; **workflow `iac-lint` (cfn-lint + Checkov)**; **chạy phần demo giám sát, quay video demo dự phòng**. **Không viết báo cáo**, chỉ giao ghi chú kỹ thuật + ảnh | `03-TV3-MONITORING-IAC-LINT.md` |

**Tiêu chí hoàn thành phần của Thuận:**
- `deploy-infra.sh` dựng đủ 4 stack bằng một lệnh. `destroy-infra.sh` xóa sạch, không để sót tài nguyên.
- `kubectl get nodes` thấy 2 node `Ready` ở private subnet.
- Push vào main thì image có tag SHA xuất hiện trong ECR, và `kustomization.yaml` trong repo gitops được cập nhật tự động.
- ArgoCD tự sync, frontend hiển thị phiên bản mới (biến môi trường `APP_VERSION` lấy từ image tag).
- TV3 dùng được `kubectl` nhờ EKS Access Entry (policy `AmazonEKSEditPolicy`).

## 7. Lịch 14 ngày và mốc tích hợp

| Ngày | Thuận | TV1 | TV2 | TV3 |
|---|---|---|---|---|
| 19–20/11 | Tạo 2 repo, thêm collaborator, viết app + test + Dockerfile, `network.yaml`, `iam.yaml` | Cài Trivy local, quét thử, **tạo JSON mẫu cho TV2** | Học định dạng JSON, dựng khung analyzer | Cài kind/minikube, cài thử kube-prometheus-stack ở máy; nhận IAM user |
| **21/11 – M1** | Secrets, file 00 đã lên repo | **Giao JSON mẫu Trivy cho TV2**; hỏi giảng viên mẫu báo cáo, tạo khung `docs/report/` | Có parser đọc được JSON mẫu | Workflow `iac-lint` chạy trên `network.yaml`/`iam.yaml` |
| 22–23/11 | `eks.yaml`, `ecr.yaml`, thử dựng EKS lần đầu rồi xóa | Thiết lập SonarCloud, viết job `sonar` | Tính độ ưu tiên + chế độ không dùng LLM; **sơ đồ kiến trúc bản nháp** | Dashboard tùy chỉnh trên kind, export JSON |
| **24/11 – M2** | Pipeline chạy `test` + `build` trên PR | Job `sonar` + Trivy action đã merge | Analyzer chạy local, có và không có Gemini | ArgoCD Application cho monitoring chạy được trên kind; `iac-lint` quét đủ 4 template |
| 25–26/11 | Push ECR, ArgoCD, update-gitops | Xuất JSON của Sonar, giao mẫu thật cho TV2 | Viết job `ai-report`, comment vào PR | Ghi chú kỹ thuật `docs/monitoring.md` |
| **26/11 – M3** | **Phiên EKS chung #1:** CI → ECR → ArgoCD → app chạy | | | Có quyền kubectl |
| 27–28/11 | Ghép toàn bộ pipeline | Nhánh demo bị chặn, sau đó sửa cho qua | Ghép với pipeline thật; **kịch bản demo** | **Phiên EKS chung #2:** monitoring lên EKS, chụp ảnh |
| **29/11 – M4** | **Thuận, TV1, TV2 nộp phần báo cáo**; TV3 nộp ghi chú kỹ thuật + ảnh | Bắt đầu ghép | Bắt đầu slide | |
| **30/11 – M5** | **Phiên EKS chung #3:** diễn tập demo end-to-end | | | **Quay video demo dự phòng** |
| 01/12 | Sửa lỗi cuối | **Ghép báo cáo hoàn chỉnh** | **Hoàn thiện slide** | Ôn vấn đáp |
| **02/12 – M6** | **Hủy toàn bộ hạ tầng**, kiểm tra không còn tài nguyên chạy | Nộp báo cáo | Ôn vấn đáp | Ôn vấn đáp |

**Báo cáo tiến độ hằng ngày** gửi trong nhóm chat lúc 21:00, theo 3 dòng: *Đã xong / Ngày mai làm / Đang vướng*. Vướng quá 2 giờ thì hỏi ngay, không ôm.

## 8. BẪY TỐN TIỀN (đọc kỹ)

**Chi phí ước tính khi cluster đang chạy** (ap-southeast-1; kiểm tra lại bằng AWS Pricing Calculator):

| Thành phần | Khoảng |
|---|---|
| EKS control plane | ~$0.10/giờ |
| 2 × t3.medium | ~$0.05/giờ mỗi node |
| NAT Gateway | ~$0.05–0.06/giờ, cộng phí theo GB dữ liệu đi qua |
| Load Balancer của frontend | ~$0.025–0.03/giờ |
| Public IPv4 (EIP của NAT, IP của LB) | ~$0.005/giờ mỗi IP |
| **Tổng** | **~$0.30/giờ → ~$7/ngày → ~$220/tháng nếu quên tắt** |

Mỗi phiên làm việc 4 giờ tốn khoảng $1–1.5. Cả đồ án dự kiến khoảng $10–20.

| # | Bẫy | Hậu quả | Cách tránh |
|---|---|---|---|
| 1 | **Quên xóa stack sau mỗi phiên** | ~$7/ngày | Kết thúc phiên phải chạy `destroy-infra.sh`, rồi báo "cluster đã tắt" trong nhóm |
| 2 | **Xóa EKS khi Service LoadBalancer vẫn còn** | LB và Security Group mồ côi vẫn tính tiền, **stack `nt548-network` không xóa được** (DELETE_FAILED) | Theo đúng thứ tự xóa ở mục 11: xóa các ArgoCD Application trước, chờ LB biến mất rồi mới xóa stack |
| 3 | **ArgoCD tự tạo lại tài nguyên vừa xóa** (selfHeal) | Xóa Service xong LB lại xuất hiện | Xóa **Application** trong ArgoCD trước, không xóa Service bằng tay |
| 4 | **Chọn phiên bản Kubernetes cũ đang ở extended support** | Control plane ~$0.60/giờ thay vì $0.10 | Chọn phiên bản mới nhất còn trong standard support |
| 5 | **Bật persistence cho Prometheus/Grafana** | Tạo EBS volume (PVC). Xóa cluster xong volume vẫn còn và vẫn tính tiền | Không bật persistence (Phương án B) |
| 6 | **Mở LoadBalancer cho ArgoCD hoặc Grafana** | Thêm LB (tốn tiền) và mở giao diện quản trị ra internet | Chỉ dùng `kubectl port-forward` |
| 7 | **Tạo tài nguyên nhầm region** | Không thấy trong console nên quên xóa | Luôn dùng `--region ap-southeast-1`. Kiểm tra bằng Billing → Bills hoặc Tag Editor tìm theo `Project=nt548` |
| 8 | **Bật log control plane EKS lên CloudWatch** | Tốn phí lưu log | Không bật. Nếu bật để chụp ảnh thì đặt thời hạn lưu (retention) 1 ngày |
| 9 | **Lộ access key AWS trên repo public** | Bot dựng máy đào coin, có thể mất hàng nghìn đô | Không dùng access key trong CI (đã dùng OIDC). Tài khoản cá nhân bật MFA |
| 10 | **Bật thanh toán (billing) cho project Gemini** | Lộ key sẽ bị tính tiền | Chỉ dùng free tier, **không** bật billing |
| 11 | **ECR giữ quá nhiều image** | Phí lưu trữ (nhỏ nhưng cộng dồn) | Lifecycle policy chỉ giữ 10 image gần nhất |

**Bắt buộc ngay hôm nay (Thuận):** tạo **AWS Budget** với 2 mức cảnh báo $10 và $20, gửi email cho Thuận. Bật MFA cho tài khoản root, và không dùng root để làm việc.

## 9. Bẫy kỹ thuật hay gặp

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| Pod `Pending`, sự kiện báo "Too many pods" | t3.medium chỉ chứa tối đa 17 Pod mỗi node | Tắt bớt thành phần (Alertmanager, Dex của ArgoCD), giảm số replica |
| Pod `ImagePullBackOff` | Sai tên hoặc tag image, hoặc node role thiếu quyền đọc ECR | `kubectl describe pod`, kiểm tra tag trong `kustomization.yaml` |
| `kubectl` báo `Unauthorized` | IAM user chưa có Access Entry trong EKS | Nhờ Thuận thêm Access Entry |
| GitHub Actions báo "Not authorized to perform sts:AssumeRoleWithWebIdentity" | Thiếu `permissions: id-token: write`, hoặc trust policy sai tên repo hay nhánh | Kiểm tra điều kiện `sub` là `repo:ngocthuan-tech/DevOps-technology-and-its-applications---NT548.R11:ref:refs/heads/main` (đúng tên đầy đủ, đúng chữ hoa/thường) |
| SonarCloud báo lỗi "Automatic Analysis is enabled" | Bật cả phân tích tự động lẫn phân tích qua CI | Tắt Automatic Analysis trong SonarCloud |
| Coverage trên Sonar bằng 0% | Đường dẫn trong `coverage.xml` không khớp với `sonar.sources` | Xem file 01 |
| Trivy báo `TOOMANYREQUESTS` | Bị giới hạn tải cơ sở dữ liệu lỗ hổng | Dùng mirror `public.ecr.aws/aquasecurity/trivy-db`, bật cache |
| ArgoCD sync kube-prometheus-stack lỗi "metadata.annotations: Too long" | CRD quá lớn để apply kiểu client-side | Thêm `ServerSideApply=true` vào syncOptions |
| Stack CloudFormation `ROLLBACK_COMPLETE` | Lỗi trong template | Đọc tab Events tìm dòng lỗi **đầu tiên**, xóa stack rồi tạo lại |
| Dựng hoặc xóa EKS rất lâu | Bình thường: cluster ~10–15 phút, node group ~5 phút | Tính thời gian này vào lịch phiên |

## 10. Bảo mật bắt buộc (đúng tinh thần DevSecOps)

- GitHub Actions dùng **OIDC**. Trust policy chỉ cho phép repo `nt548-app` (tên đầy đủ ở mục 5.1) ở nhánh `main` nhận role. Role chỉ có quyền push vào 2 repo ECR (**least privilege**).
- Node role chỉ có các policy tối thiểu: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`.
- Image chạy bằng **user không phải root**, base image dạng slim.
- Không đưa secret vào Git, kể cả repo gitops. Mật khẩu admin của Grafana để trong Kubernetes Secret, tạo bằng lệnh.
- Thành viên cần quyền AWS thì được cấp **IAM user riêng có MFA**. Không ai dùng chung tài khoản.

## 11. Quy trình một phiên làm việc trên AWS (chỉ Thuận chạy)

**Bật** (tổng cộng ~25–30 phút):
1. `scripts/deploy-infra.sh`: chạy theo thứ tự network → iam → ecr → eks.
2. `aws eks update-kubeconfig --region ap-southeast-1 --name nt548-eks`
3. `scripts/bootstrap-argocd.sh`: cài ArgoCD (ghim phiên bản), tạo namespace `monitoring` cùng secret của Grafana, rồi apply `apps/root.yaml`.
4. Báo nhóm: **"Cluster đã bật, dự kiến tắt lúc HH:MM"**.

**Tắt** (bắt buộc đúng thứ tự):
1. `kubectl delete applications.argoproj.io --all -n argocd`: finalizer sẽ xóa luôn Service LoadBalancer.
2. Chờ đến khi `aws elb describe-load-balancers` **và** `aws elbv2 describe-load-balancers` không còn LB nào của cluster.
3. Xóa stack `nt548-eks` và chờ xóa xong.
4. Xóa stack `nt548-network`. `nt548-iam` và `nt548-ecr` có thể giữ lại giữa các phiên vì chi phí không đáng kể; đến 02/12 thì xóa hết.
5. Kiểm tra lần cuối: EC2, NAT Gateway, Load Balancer, Elastic IP, EBS volume đều phải trống.
6. Báo nhóm: **"Cluster đã tắt"**.

## 12. Cấu trúc báo cáo cuối kỳ (TV1 ghép; TV2 làm slide)

| Phần | File | Người viết |
|---|---|---|
| 1. Giới thiệu, mục tiêu, phạm vi | `docs/report/01-gioi-thieu.md` | TV1 |
| 2. Cơ sở lý thuyết | Mỗi người viết lý thuyết của phần mình, đặt trong file phần đó (riêng monitoring do TV1 viết) | Thuận, TV1, TV2 |
| 3. Kiến trúc tổng thể + sơ đồ | `docs/report/03-kien-truc.md` | Thuận viết, TV2 vẽ sơ đồ |
| 4. IaC với CloudFormation | `docs/report/04-iac.md` | Thuận |
| 5. CI pipeline | `docs/report/05-ci.md` | Thuận |
| 6. DevSecOps: Sonar + Trivy | `docs/report/06-devsecops.md` | TV1 |
| 7. Thành phần AI | `docs/report/07-ai.md` | TV2 |
| 8. GitOps với ArgoCD | `docs/report/08-gitops.md` | Thuận |
| 9. Giám sát + quét IaC | `docs/report/09-monitoring.md` | **TV1 viết** từ ghi chú kỹ thuật và ảnh của TV3 |
| 10. Demo và kết quả | `docs/report/10-ket-qua.md` | TV1 tổng hợp ảnh |
| 11. Chi phí và tối ưu | `docs/report/11-chi-phi.md` | Thuận |
| 12. Hạn chế và hướng phát triển | `docs/report/12-han-che.md` | TV1 tổng hợp ý kiến cả nhóm |

**Slide và kịch bản demo:** TV2 (xem file 02). **Video demo dự phòng:** TV3 quay trong phiên 30/11.

**Ảnh chụp màn hình** đặt tên `docs/images/<phần>-<mô-tả>.png`, ví dụ `06-trivy-blocked.png`. **Hạn nộp phần báo cáo: 29/11**, nộp cho TV1.

## 13. Câu hỏi vấn đáp chung (ai cũng phải trả lời được)

1. Một commit đi từ code đến Pod như thế nào? (Kể lại mục 2 bằng lời của mình.)
2. CI khác CD thế nào? Ở đồ án này phần nào là CI, phần nào là CD?
3. GitOps là gì? Mô hình pull của ArgoCD khác mô hình push (CI dùng `kubectl apply`) ở điểm nào? Vì sao an toàn hơn?
4. Vì sao AI không được quyền chặn pipeline?
5. Vì sao dùng OIDC thay cho access key?
6. Vì sao node đặt ở private subnet? NAT Gateway để làm gì? Vì sao chỉ dùng 1 NAT?
7. Vì sao chọn EKS mà không chọn ECS?
8. Shift-left security là gì? Sonar và Trivy nằm ở đâu trong "shift-left"?
9. Nếu một Pod chết thì chuyện gì xảy ra? Ai phát hiện, ai khởi động lại?
10. Hệ thống tốn bao nhiêu tiền, và nhóm đã tiết kiệm bằng cách nào?

## 14. Việc còn phải chốt (Thuận xác nhận)

- [ ] Repo để **public** được không? Không được thì phải xem lại phương án SonarCloud.
- [ ] Tài khoản AWS là tài khoản cá nhân hay **AWS Academy Learner Lab**? Learner Lab thường không cho tạo IAM Role hay OIDC provider, nên phải điều chỉnh phần IAM.
- [ ] Ngày báo cáo/vấn đáp chính xác, và mẫu báo cáo (Word?) giảng viên yêu cầu.
