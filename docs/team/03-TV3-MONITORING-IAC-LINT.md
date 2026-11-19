# 03 — TV3: Giám sát (Prometheus + Grafana), Quét IaC và Vận hành demo

> **Cách dùng:** dán **file này kèm file `00-TONG-QUAN-DE-TAI.md`** vào AI của bạn, rồi gửi đoạn mở đầu dưới đây.

```
Bạn là mentor Kubernetes/Observability/DevSecOps của tôi trong đồ án môn NT548. Hãy đọc kỹ 2 file tôi gửi.
Quy tắc:
1. Chỉ làm trong phạm vi file 03. Không đổi tên namespace, tên file, đường dẫn hay công cụ
   đã chốt (kube-prometheus-stack cài qua ArgoCD; cfn-lint + Checkov). Nếu thấy cần đổi, hãy nói lý do để tôi hỏi trưởng nhóm.
2. Hướng dẫn từng bước. Giải thích bản chất trước, rồi mới đưa YAML/lệnh. Có chú thích.
3. Ưu tiên luyện tập trên cluster local (kind/minikube) để không tốn tiền AWS.
4. Sau mỗi bước, hỏi tôi kết quả chạy thực tế rồi mới sang bước tiếp.
5. Khi tôi gặp lỗi, phân tích log/sự kiện, chỉ ra nguyên nhân gốc trước khi đưa cách sửa.
6. Cuối mỗi buổi, tóm tắt 3 câu hỏi vấn đáp về phần vừa làm.
Bắt đầu từ Bước 0.
```

---

## 1. Vai trò và mục tiêu

Bạn phụ trách **3 việc kỹ thuật**, và **không viết báo cáo**:

**A. Giám sát:** triển khai **kube-prometheus-stack** (Prometheus, Grafana, kube-state-metrics, node-exporter) lên EKS **theo kiểu GitOps**, nghĩa là khai báo trong repo `nt548-gitops` để ArgoCD tự cài. Sau đó dựng dashboard theo dõi **CPU, RAM, Pod và tình trạng hoạt động** của cluster và ứng dụng.

**B. Quét IaC (`iac-lint`):** workflow GitHub Actions kiểm tra các template CloudFormation của Thuận:
- **cfn-lint**: phát hiện sai cú pháp, sai thuộc tính. Có lỗi thì pipeline đỏ.
- **Checkov**: phát hiện cấu hình thiếu an toàn. Chỉ cảnh báo, không chặn.

Đây là phần "bảo mật hạ tầng" của DevSecOps, bổ sung cho Sonar (code) và Trivy (image).

**C. Vận hành demo:** trình bày phần giám sát khi demo, và **quay video demo dự phòng** trong phiên 30/11.

**Về báo cáo:** bạn chỉ giao **ghi chú kỹ thuật dạng gạch đầu dòng + ảnh chụp** cho TV1. TV1 sẽ viết thành mục báo cáo.

## 2. Ranh giới

| Bạn LÀM | Bạn KHÔNG làm |
|---|---|
| `apps/children/monitoring.yaml`, `apps/children/monitoring-dashboards.yaml` (repo gitops) | Cài ArgoCD, dựng EKS (của Thuận) |
| `monitoring/dashboards/*.yaml` (ConfigMap dashboard) | Manifest của app trong `microservices/` |
| `.github/workflows/iac-lint.yml` (repo nt548-app) | Sửa template CloudFormation. Thấy lỗi thì báo Thuận sửa |
| `docs/monitoring.md` (ghi chú kỹ thuật, gạch đầu dòng là đủ) | Viết báo cáo, làm slide (của TV1, TV2) |
| Ảnh chụp trong `docs/images/09-*.png` | Tạo hay xóa tài nguyên AWS; bật persistence/EBS; mở LoadBalancer cho Grafana |
| Quay video demo dự phòng | Đổi sang CloudWatch Container Insights, Datadog… |

## 3. Quyền truy cập AWS của bạn

- Bạn có **IAM user `nt548-tv3`**, chỉ dùng bằng **dòng lệnh**, không đăng nhập trang web AWS.
- Thuận gửi riêng cho bạn file access key. Cài **AWS CLI v2** và **kubectl**, rồi chạy:
  ```bash
  aws configure --profile nt548        # nhập key, region ap-southeast-1, output json
  aws sts get-caller-identity --profile nt548
  aws eks describe-cluster --name nt548-eks --region ap-southeast-1 --profile nt548
  ```
  Lệnh 1 phải hiện `user/nt548-tv3`. Lệnh 2 báo `ResourceNotFoundException` khi cluster chưa bật là **đúng**. Nếu báo `AccessDenied` thì nhắn Thuận.
- **Không** đưa key vào code, repo hay nhóm chat. Lưu xong thì xóa tin nhắn và file chứa key.
- Bạn chỉ dùng được cluster **trong các phiên chung do Thuận bật** (26/11, 28/11, 30/11):
  ```bash
  aws eks update-kubeconfig --region ap-southeast-1 --name nt548-eks --profile nt548
  kubectl get nodes
  ```

## 4. Bạn nằm ở đâu trong hệ thống

```
nt548-app:  push/PR sửa infra/cloudformation/**  →  [iac-lint] (BẠN): cfn-lint + Checkov

nt548-gitops/apps/root.yaml (app-of-apps)
   └── apps/children/
        ├── microservices.yaml          (Thuận)
        ├── monitoring.yaml             (BẠN) → Helm chart kube-prometheus-stack → namespace monitoring
        └── monitoring-dashboards.yaml  (BẠN) → monitoring/dashboards/ (ConfigMap) → sidecar Grafana tự nạp
```
Bạn **không chạy `helm install` trên EKS**. Bạn commit YAML vào Git, ArgoCD tự cài. Đó là GitOps.

## 5. Kiến thức cần nắm trước

1. **Prometheus dùng mô hình pull**: định kỳ tới các endpoint `/metrics` lấy số liệu (scrape), lưu dạng chuỗi thời gian (time series).
2. **Nguồn số liệu:** node-exporter (số liệu của node), cAdvisor trong kubelet (CPU/RAM của container), kube-state-metrics (trạng thái đối tượng Kubernetes: Pod phase, replica, restart).
3. **Prometheus Operator, ServiceMonitor:** khai báo "scrape cái gì" bằng tài nguyên Kubernetes thay vì sửa file cấu hình.
4. **PromQL cơ bản:** `rate()`, `sum by()`, `increase()`, selector nhãn `{namespace="app"}`.
5. **Grafana sidecar:** tự nạp mọi ConfigMap có nhãn `grafana_dashboard: "1"`, nên dashboard cũng nằm trong Git được.
6. **EKS là managed control plane:** không scrape được etcd, scheduler, controller-manager. Phải tắt các mục đó để tránh target "down" và cảnh báo giả.
7. **Lint và quét bảo mật IaC:** cfn-lint kiểm tra template **có hợp lệ không** (đúng tên thuộc tính, đúng kiểu dữ liệu). Checkov kiểm tra template **có an toàn không** (ví dụ endpoint public, thiếu mã hóa, thiếu log). Hai việc khác nhau.

## 6. Đầu ra phải bàn giao

| # | File hoặc kết quả | Tiêu chí hoàn thành |
|---|---|---|
| 1 | `.github/workflows/iac-lint.yml` | Chạy khi sửa `infra/cloudformation/**`. cfn-lint lỗi thì đỏ; Checkov in danh sách cảnh báo |
| 2 | Danh sách cảnh báo Checkov đã phân loại | Mỗi cảnh báo ghi: **sửa** (báo Thuận) hoặc **chấp nhận** (kèm lý do) |
| 3 | `apps/children/monitoring.yaml` | ArgoCD sync **Healthy/Synced**, mọi Pod trong `monitoring` đều Running |
| 4 | `apps/children/monitoring-dashboards.yaml` + `monitoring/dashboards/nt548-overview.yaml` | Dashboard "NT548 Overview" tự xuất hiện trong Grafana |
| 5 | `docs/monitoring.md` (gạch đầu dòng) | Cách truy cập, ý nghĩa từng panel, PromQL, kết quả Checkov. **Giao TV1 trước 29/11** |
| 6 | Ảnh `docs/images/09-*.png` | Dashboard bình thường, khi xóa Pod, khi tạo tải; pipeline `iac-lint` |
| 7 | **Video demo dự phòng** | Quay ngày 30/11, upload Google Drive, gửi link cho nhóm |

## 7. PHẦN A: Giám sát

### Bước 0 (19–21/11): Luyện tập trên máy. Miễn phí
1. Cài Docker Desktop (cấp ≥ 4GB RAM), `kubectl`, `helm`, và `kind` (hoặc minikube).
2. Tạo cluster: `kind create cluster --name nt548`.
3. Cài thử bằng Helm **chỉ để học**:
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   helm install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
   kubectl get pods -n monitoring
   kubectl get svc -n monitoring                   # tìm tên service grafana
   kubectl port-forward svc/kps-grafana -n monitoring 3000:80
   ```
4. Mở http://localhost:3000 và xem các dashboard có sẵn: *Kubernetes / Compute Resources / Cluster, Namespace (Pods), Node Exporter / Nodes*.
5. Thử các truy vấn PromQL ở Bước 2 trong Explore.

### Bước 1 (22–24/11): Viết ArgoCD Application, thử trên kind
Cài ArgoCD lên kind để kiểm thử (cách cài giống phần Thuận làm trên EKS), rồi gỡ bản Helm ở Bước 0.

**`apps/children/monitoring.yaml`** (phiên bản chart phải **ghim cụ thể**, kiểm tra bản mới nhất trên Artifact Hub):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack            # cũng là tên release → service sẽ là kube-prometheus-stack-grafana
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # xóa Application thì xóa luôn tài nguyên
spec:
  project: default
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: "<GHIM_PHIEN_BAN_CHART>"   # KHÔNG dùng "*"
    helm:
      valuesObject:
        alertmanager:
          enabled: false                  # Phương án B: tiết kiệm Pod/RAM
        grafana:
          admin:
            existingSecret: grafana-admin # mật khẩu KHÔNG nằm trong Git
            userKey: admin-user
            passwordKey: admin-password
          persistence:
            enabled: false                # KHÔNG tạo EBS → không phát sinh volume mồ côi
          sidecar:
            dashboards:
              enabled: true
              label: grafana_dashboard
              searchNamespace: ALL
        prometheus:
          prometheusSpec:
            retention: 12h                # demo không cần lưu lâu
            resources:
              requests: { cpu: 100m, memory: 512Mi }
              limits: { memory: 1Gi }
            serviceMonitorSelectorNilUsesHelmValues: false
        # EKS quản lý control plane → không scrape được các thành phần dưới đây
        kubeControllerManager: { enabled: false }
        kubeScheduler: { enabled: false }
        kubeEtcd: { enabled: false }
        kubeProxy: { enabled: false }     # metrics của kube-proxy trên EKS chỉ nghe ở 127.0.0.1
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true              # BẮT BUỘC: CRD quá lớn, apply kiểu thường sẽ lỗi
```

**Secret mật khẩu Grafana** (tạo bằng lệnh, **không commit**). Trên EKS, Thuận chạy lệnh này trong script bootstrap:
```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic grafana-admin -n monitoring \
  --from-literal=admin-user=admin --from-literal=admin-password='<mật khẩu mạnh>'
```

**`apps/children/monitoring-dashboards.yaml`:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-dashboards
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/ngocthuan-tech/nt548-gitops.git
    targetRevision: main
    path: monitoring/dashboards
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions:
      - CreateNamespace=true
```

**Mốc M2 (24/11):** trên kind, ArgoCD hiển thị cả 2 Application ở trạng thái **Synced + Healthy**.

### Bước 2 (23–25/11): Dashboard "NT548 Overview"
Tạo dashboard trong Grafana gồm 7 panel:

| Panel | PromQL |
|---|---|
| CPU theo Pod (namespace app) | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="app", container!=""}[5m]))` |
| RAM theo Pod | `sum by (pod) (container_memory_working_set_bytes{namespace="app", container!=""})` |
| Số Pod Running theo namespace | `sum by (namespace) (kube_pod_status_phase{phase="Running"})` |
| Số lần restart (1 giờ) | `sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace="app"}[1h]))` |
| Replica sẵn sàng so với mong muốn | `kube_deployment_status_replicas_available{namespace="app"}` và `kube_deployment_spec_replicas{namespace="app"}` |
| CPU node (%) | `100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))` |
| RAM node (%) | `100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)` |

Trên kind chưa có namespace `app`, nên tạo tạm một deployment thử: `kubectl create ns app && kubectl create deployment demo --image=nginx -n app --replicas=2`.

**Xuất dashboard:** Share → Export → bật **"Export for sharing externally"** (để datasource thành biến, tránh lỗi UID khác nhau giữa kind và EKS). Đóng gói thành ConfigMap:

**`monitoring/dashboards/nt548-overview.yaml`:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nt548-overview-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"          # sidecar Grafana nhận ra nhờ nhãn này
data:
  nt548-overview.json: |
    { ...dán JSON đã export, thụt lề đúng 4 khoảng trắng... }
```

### Bước 3 (26/11 và 28/11): Lên EKS trong phiên chung
1. Kết nối cluster theo mục 3, kiểm tra `kubectl get nodes` và `kubectl get applications -n argocd`.
2. Mở PR vào `nt548-gitops` chứa 2 Application và dashboard. Thuận merge, ArgoCD tự sync.
3. Theo dõi: `kubectl get pods -n monitoring -w`. Đếm tổng số Pod: `kubectl get pods -A --no-headers | wc -l`. Mỗi node t3.medium tối đa 17 Pod, 2 node là 34.
4. Truy cập Grafana:
   ```bash
   kubectl get svc -n monitoring                      # xác nhận tên service
   kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
   ```
5. Chụp ảnh 3 kịch bản:
   - **Bình thường:** dashboard NT548 Overview và dashboard có sẵn *Kubernetes / Compute Resources / Cluster*.
   - **Tự phục hồi:** `kubectl delete pod -n app -l app=api` (kiểm tra nhãn thực tế bằng `kubectl get pods -n app --show-labels`), xem Pod mới được tạo lại.
   - **Tạo tải:**
     ```bash
     kubectl run load -n app --rm -it --image=busybox --restart=Never -- \
       sh -c "while true; do wget -q -O- http://frontend >/dev/null; done"
     ```
     Xem CPU của frontend/api tăng lên. Dừng bằng Ctrl+C.

### Bước 4 (27–29/11): Ghi chú kỹ thuật cho TV1
`docs/monitoring.md`, **chỉ cần gạch đầu dòng**, không cần viết văn:
- Các thành phần đã cài và vai trò của từng cái (node-exporter, kube-state-metrics, Prometheus, Grafana).
- Lý do các lựa chọn: tắt Alertmanager, không persistence, retention 12h, tắt scrape etcd/scheduler.
- Lệnh truy cập Grafana.
- Bảng 7 panel: panel đó đo gì, PromQL dùng gì.
- Kết quả 3 kịch bản (bình thường, xóa Pod, tạo tải) kèm tên ảnh.
- Kết quả Checkov (xem Phần B).

**Giao TV1 trước 29/11.** TV1 hỏi chỗ nào chưa rõ thì trả lời giúp TV1.

## 8. PHẦN B: Quét IaC (`iac-lint`)

### Bước B0 (19–21/11): Thử ở máy
```bash
pip install cfn-lint checkov
cfn-lint infra/cloudformation/*.yaml --regions ap-southeast-1
checkov -d infra/cloudformation --framework cloudformation
```
Nếu Thuận chưa có template thì tự viết một template nhỏ (chỉ có 1 VPC) và **cố ý gõ sai** một thuộc tính (ví dụ `CidrBlok`) để xem cfn-lint báo lỗi ra sao.

### Bước B1 (21–24/11): Workflow
File **`.github/workflows/iac-lint.yml`**. Đây là workflow riêng, **không sửa `ci.yml`**. Phiên bản công cụ phải ghim cụ thể:
```yaml
name: iac-lint
on:
  pull_request:
    paths: ["infra/cloudformation/**", ".github/workflows/iac-lint.yml"]
  push:
    branches: [main]
    paths: ["infra/cloudformation/**", ".github/workflows/iac-lint.yml"]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  cfn-lint:                       # CỔNG CHẶN: template sai thì đỏ
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v7
        with: { python-version: "3.12" }
      - run: pip install "cfn-lint==<GHIM_PHIEN_BAN>"
      - name: Kiểm tra cú pháp và thuộc tính template
        run: cfn-lint infra/cloudformation/*.yaml --regions ap-southeast-1

  checkov:                        # CHỈ CẢNH BÁO: không chặn
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v7
        with: { python-version: "3.12" }
      - run: pip install "checkov==<GHIM_PHIEN_BAN>"
      - name: Quét cấu hình bảo mật
        run: checkov -d infra/cloudformation --framework cloudformation --soft-fail
```
**Vì sao Checkov chỉ cảnh báo:** đồ án có một số đánh đổi có chủ đích (endpoint EKS để public, chỉ 1 NAT, không bật VPC Flow Logs để tiết kiệm). Nếu Checkov chặn thì pipeline sẽ luôn đỏ. Thay vào đó, nhóm **ghi lại và giải thích** từng cảnh báo.

### Bước B2 (24–26/11): Phân loại cảnh báo Checkov
Lập bảng trong `docs/monitoring.md` (mục "Quét IaC"):

| Mã kiểm tra | Nội dung | Quyết định | Lý do |
|---|---|---|---|
| CKV_AWS_... | ... | Sửa / Chấp nhận | ... |

Mục nào "Sửa" thì báo Thuận. Mục nào "Chấp nhận" thì ghi lý do (chi phí, phạm vi đồ án). Nếu cảnh báo nào được chấp nhận hẳn, có thể bỏ qua bằng chú thích `checkov:skip` ngay trong template, **kèm lý do**, và bàn với Thuận trước.

### Bước B3: Demo
Tạo PR trên nhánh `demo/iac-broken`, gõ sai một thuộc tính trong `network.yaml` → `cfn-lint` đỏ → chụp ảnh `09-iac-lint-failed.png`. **Không merge.**

## 9. PHẦN C: Vận hành demo và quay video dự phòng

- Trong buổi demo, bạn trình bày **phút 8–10** (Grafana: dashboard, xóa Pod, tạo tải) và phụ Thuận phần `iac-lint` (phút 1–2). Kịch bản chi tiết do TV2 viết trong `docs/demo-script.md`.
- **Quay video dự phòng** trong phiên chung 30/11:
  - Dùng **OBS Studio** (miễn phí), độ phân giải 1080p.
  - Quay đủ toàn bộ kịch bản demo từ đầu đến cuối, mỗi người tự nói phần mình.
  - Upload lên Google Drive (**không** đưa vào repo vì file lớn), gửi link vào nhóm.
  - Mở thử video trên máy khác để chắc chắn xem được.

## 10. Lỗi hay gặp

| Lỗi | Nguyên nhân | Cách sửa |
|---|---|---|
| Sync lỗi "metadata.annotations: Too long" | Thiếu `ServerSideApply=true` | Thêm vào `syncOptions` |
| Grafana `CreateContainerConfigError` | Chưa có secret `grafana-admin` | Tạo secret, Pod tự chạy lại |
| Pod `Pending`, "Too many pods" hoặc "Insufficient memory" | Node đầy | Giảm `resources.requests`, báo Thuận |
| Target down: etcd / scheduler / controller-manager | Không tắt các mục đó trên EKS | Đặt `enabled: false` như mẫu |
| Dashboard báo "datasource not found" | Export chưa bật "for sharing externally" | Export lại |
| Dashboard không xuất hiện | Thiếu nhãn `grafana_dashboard: "1"` hoặc sai namespace | Kiểm tra nhãn, xem log sidecar của Grafana |
| `kubectl` báo `Unauthorized` | Chưa có Access Entry, hoặc sai profile AWS | Nhờ Thuận kiểm tra, dùng đúng `--profile nt548` |
| `iac-lint` không chạy | PR không sửa file trong `infra/cloudformation/` | Đúng thiết kế (lọc theo `paths`). Chạy tay bằng `workflow_dispatch` |
| cfn-lint báo lỗi E3xxx | Sai thuộc tính hoặc kiểu dữ liệu trong template | Báo Thuận dòng lỗi |

## 11. Câu hỏi vấn đáp cho phần của bạn

1. Prometheus dùng mô hình pull hay push? Ưu và nhược điểm?
2. node-exporter, cAdvisor và kube-state-metrics khác nhau thế nào?
3. ServiceMonitor là gì? Vì sao dùng nó thay vì sửa file cấu hình Prometheus?
4. Giải thích `rate(container_cpu_usage_seconds_total[5m])`.
5. Vì sao trên EKS phải tắt scrape etcd và scheduler?
6. Vì sao không bật persistence? Production thì nên làm thế nào?
7. Vì sao dashboard cũng nằm trong Git?
8. cfn-lint khác Checkov thế nào? Vì sao một cái chặn, một cái chỉ cảnh báo?
9. Quét IaC nằm ở đâu trong "shift-left"? Nó bắt được lỗi gì mà Sonar và Trivy không bắt được?
10. Vì sao IAM user của bạn chỉ có quyền `eks:DescribeCluster` mà vẫn dùng được `kubectl`? (Gợi ý: IAM xác thực bạn là ai; EKS Access Entry quyết định bạn làm được gì trong cluster.)

## 12. Phối hợp

- **Bạn phụ thuộc vào Thuận:** template CloudFormation (cho `iac-lint`), cluster EKS, ArgoCD, Access Entry, và việc merge PR. Trước 26/11, phần giám sát làm được hết trên kind.
- **TV1 phụ thuộc vào bạn:** `docs/monitoring.md` + ảnh, **trước 29/11**.
- **TV2:** gửi bạn kịch bản demo trước 30/11.
- Báo cáo tiến độ 21:00 hằng ngày trong nhóm: *Đã xong / Ngày mai / Vướng*.
