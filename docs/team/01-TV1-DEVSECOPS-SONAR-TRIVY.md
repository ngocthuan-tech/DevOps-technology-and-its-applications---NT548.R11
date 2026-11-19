# 01 — TV1: DevSecOps (SonarCloud + Trivy) và Ghép báo cáo

> **Cách dùng:** dán **file này kèm file `00-TONG-QUAN-DE-TAI.md`** vào AI của bạn, rồi gửi đoạn mở đầu dưới đây.

```
Bạn là mentor DevSecOps của tôi trong đồ án môn NT548. Hãy đọc kỹ 2 file tôi gửi.
Quy tắc:
1. Chỉ làm trong phạm vi file 01. Không đổi tên job, tên file, đường dẫn, tên artifact
   hay công cụ đã chốt trong file 00 mục 5. Nếu thấy cần đổi, hãy nói lý do để tôi hỏi trưởng nhóm.
2. Hướng dẫn từng bước một. Giải thích bản chất trước, rồi mới đưa code. Code có chú thích.
3. Sau mỗi bước, hỏi tôi kết quả chạy thực tế rồi mới sang bước tiếp.
4. Khi tôi gặp lỗi, phân tích log và chỉ ra nguyên nhân gốc trước khi đưa cách sửa.
5. Cuối mỗi buổi, tóm tắt cho tôi 3 câu hỏi vấn đáp về phần vừa làm.
Bắt đầu từ Bước 0.
```

---

## 1. Vai trò và mục tiêu

Bạn phụ trách **hai cổng chặn bảo mật** trong pipeline CI:
- **SonarCloud (SAST)**: phân tích mã nguồn để tìm lỗi, lỗ hổng, code smell và security hotspot. **Quality Gate** không đạt thì pipeline dừng.
- **Trivy (quét image)**: quét CVE trong Docker image (gói hệ điều hành và thư viện Python). Có lỗ hổng `HIGH` hoặc `CRITICAL` **đã có bản vá** thì pipeline dừng **trước khi** image được push lên ECR.

Ngoài ra, bạn xuất kết quả của cả hai ra **JSON** để thành phần AI (TV2) đọc.

**Kết quả mong muốn:** trên PR, nếu code hoặc image có vấn đề nghiêm trọng thì pipeline đỏ và image không được phát hành. Sửa xong thì pipeline xanh.

**Nhiệm vụ thứ hai: ghép báo cáo cuối kỳ** (chi tiết ở mục 10). Bạn tạo khung báo cáo, nhận các phần từ thành viên, tự viết các phần chung và phần giám sát (dựa trên ghi chú của TV3), rồi ghép thành bản hoàn chỉnh.

## 2. Ranh giới

| Bạn LÀM | Bạn KHÔNG làm |
|---|---|
| `sonar-project.properties` | App, Dockerfile (của Thuận). Cần sửa thì báo Thuận |
| Job `sonar` trong `ci.yml` (chỉ trong khối `[TV1]`) | Bước build, push ECR, OIDC, update-gitops |
| `.github/actions/trivy-scan/action.yml` | Thành phần AI (của TV2) |
| `.trivyignore` | Bất kỳ việc gì trên AWS. **Bạn không cần tài khoản AWS** |
| Xuất JSON ra `reports/` theo đúng tên file | Đổi công cụ (ví dụ Snyk, Grype…) |
| Kịch bản demo "bị chặn → sửa → qua" | Quét CloudFormation (`iac-lint`, đã chuyển cho TV3) |
| `docs/devsecops.md`, `docs/report/06-devsecops.md` | Slide, sơ đồ kiến trúc (của TV2) |
| **Khung báo cáo, viết phần 01/09/10/12, ghép báo cáo hoàn chỉnh** | |

## 3. Bạn nằm ở đâu trong pipeline

```
test → [sonar] (BẠN) → build-scan-push: build → [trivy-scan] (BẠN) → push ECR (Thuận)
                     ↘                        ↘
                      report-sonar             report-trivy-<svc>
                                    ↘          ↙
                                   ai-report (TV2) đọc các file JSON của bạn
```

- `sonar` fail thì `build-scan-push` không chạy (vì `needs: sonar`).
- Trivy gate fail thì bước push không chạy. Báo cáo JSON vẫn được upload (`if: always()`).

## 4. Kiến thức cần nắm trước khi code

1. **SAST, SCA và quét image khác nhau thế nào.** Sonar đọc code mình viết (SAST). Trivy đọc những gì nằm trong image: gói hệ điều hành và thư viện bên thứ ba (gần với SCA).
2. **CVE, CVSS và mức độ** CRITICAL / HIGH / MEDIUM / LOW / UNKNOWN.
3. **`--ignore-unfixed`**: chỉ chặn những lỗ hổng đã có bản vá. Lý do: lỗ hổng chưa có bản vá thì dev không làm gì được, nếu chặn sẽ làm tắc pipeline. Đây là một đánh đổi, phải giải thích được.
4. **Exit code**: CI dừng khi một bước trả về exit code khác 0. Trivy dùng `--exit-code 1` để biến "phát hiện lỗi" thành "bước thất bại".
5. **Quality Gate "Sonar way"** áp dụng cho **code mới**: không có issue mới, mọi hotspot mới đã được review, coverage code mới ≥ 80%, trùng lặp ≤ 3%. Vì vậy **phải gửi coverage**, nếu không PR sẽ fail vì coverage.
6. **"Quét đúng thứ sẽ phát hành":** quét chính image đã build, rồi push đúng image đó.

## 5. Đầu ra phải bàn giao

| # | File hoặc kết quả | Tiêu chí hoàn thành |
|---|---|---|
| 1 | `ai-analyzer/samples/trivy-api.json`, `trivy-frontend.json` | **Giao cho TV2 trước 21/11.** Lấy từ Trivy chạy local |
| 2 | `sonar-project.properties` | Sonar nhận đúng code, test và coverage (> 0%) |
| 3 | Job `sonar` trong `ci.yml` | Chạy trên PR, chờ Quality Gate, upload artifact `report-sonar` |
| 4 | `.github/actions/trivy-scan/action.yml` | Tạo `reports/trivy-<svc>.json`, rồi chặn khi có HIGH/CRITICAL đã có bản vá |
| 5 | `ai-analyzer/samples/sonar-*.json` | Mẫu thật lấy từ SonarCloud, **giao cho TV2 trước 26/11** |
| 6 | `.trivyignore` | Mỗi dòng bỏ qua phải có chú thích lý do. Mặc định để trống |
| 7 | Nhánh `demo/vulnerable` | Pipeline đỏ vì Trivy. Gỡ thư viện lỗi thì pipeline xanh |
| 8 | `docs/devsecops.md` | Mô tả cổng chặn, tiêu chí, cách xử lý false positive |
| 9 | `docs/report/06-devsecops.md` + ảnh chụp | Nộp trước 29/11 |
| 10 | Khung `docs/report/` (12 file) | Tạo trước 21/11, báo cả nhóm |
| 11 | `docs/report/01`, `09`, `10`, `12` | Viết xong trước 30/11 |
| 12 | **Báo cáo hoàn chỉnh** đúng mẫu giảng viên | Xong 01/12, nộp 02/12 |

## 6. Các bước thực hiện

### Bước 0 (19–21/11): Trivy chạy local. Không cần AWS, không tốn tiền
1. Cài Docker và Trivy (theo hướng dẫn cài đặt chính thức cho hệ điều hành của bạn).
2. Quét thử và đọc kết quả:
   ```bash
   trivy image python:3.12-slim
   trivy image nginx:1.19            # image cũ, nhiều CVE
   trivy image --format json -o trivy-sample.json nginx:1.19
   ```
3. Mở file JSON, tìm cấu trúc `Results[].Vulnerabilities[]` và các trường `VulnerabilityID`, `PkgName`, `InstalledVersion`, `FixedVersion`, `Severity`, `Title`.
4. Khi Thuận đã có Dockerfile, build image `api` và `frontend` ở máy rồi quét để tạo mẫu thật. Trước đó, dùng mẫu `nginx:1.19` đặt tên `trivy-api.json` để TV2 có dữ liệu làm trước.
5. **Giao mẫu cho TV2** bằng PR vào `ai-analyzer/samples/`.

### Bước 1 (22/11): Thiết lập SonarCloud
1. Đăng nhập sonarcloud.io bằng GitHub, import organization hoặc tài khoản `ngocthuan-tech` (cần Thuận chấp thuận), rồi tạo project cho repo `nt548-app`.
2. **Tắt Automatic Analysis** (Administration → Analysis Method). Không tắt thì phân tích qua CI sẽ báo lỗi.
3. Tạo token và gửi **riêng** cho Thuận để thêm secret `SONAR_TOKEN`. Gửi thêm `SONAR_ORGANIZATION` và `SONAR_PROJECT_KEY` để Thuận thêm vào Variables.
4. Kiểm tra gói Free có hỗ trợ project của nhóm không (repo public thì được).

### Bước 2 (22–23/11): `sonar-project.properties`
```properties
sonar.projectKey=<SONAR_PROJECT_KEY>
sonar.organization=<SONAR_ORGANIZATION>

# Code được phân tích: 2 service + thành phần AI
sonar.sources=services,ai-analyzer
sonar.exclusions=**/tests/**,**/samples/**

# Test nằm trong thư mục tests/ của từng service
sonar.tests=services,ai-analyzer
sonar.test.inclusions=**/tests/**

sonar.python.version=3.12
# File coverage do job test tạo ra (coverage-frontend.xml, coverage-api.xml)
sonar.python.coverage.reportPaths=coverage-*.xml
```
**Bẫy coverage 0%:** đường dẫn trong file coverage phải khớp với `sonar.sources`. Job `test` chạy `pytest --cov=services/<svc>` từ thư mục gốc repo. Nếu Sonar báo 0%, mở file `coverage-*.xml` ra xem thẻ `<source>` và thuộc tính `filename`.

### Bước 3 (23–24/11): Job `sonar` trong `ci.yml`
Thay khối `[TV1]` trong khung ở file 00. Phiên bản action phải **ghim theo bản mới nhất trên GitHub Marketplace**:

```yaml
  sonar:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0              # Sonar cần lịch sử git để biết đâu là "code mới"
      - uses: actions/download-artifact@v4
        with:
          pattern: coverage-*
          merge-multiple: true        # đặt coverage-frontend.xml, coverage-api.xml ở thư mục gốc

      - name: SonarCloud scan + chờ Quality Gate
        uses: SonarSource/sonarqube-scan-action@<GHIM_PHIEN_BAN>
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: https://sonarcloud.io
        with:
          args: >
            -Dsonar.qualitygate.wait=true
            -Dsonar.qualitygate.timeout=300

      - name: Xuất kết quả Sonar ra JSON cho AI
        if: always()                  # Quality Gate fail vẫn phải xuất để AI phân tích
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          KEY: ${{ vars.SONAR_PROJECT_KEY }}
          PR: ${{ github.event.pull_request.number }}
        run: |
          mkdir -p reports
          API=https://sonarcloud.io/api
          # Trên PR thì lấy kết quả của PR đó, trên main thì lấy kết quả nhánh main
          if [ -n "$PR" ]; then SCOPE="pullRequest=$PR"; else SCOPE="branch=$GITHUB_REF_NAME"; fi
          curl -sf -u "$SONAR_TOKEN:" "$API/issues/search?componentKeys=$KEY&resolved=false&ps=500&$SCOPE" \
            -o reports/sonar-issues.json || echo '{"issues":[]}' > reports/sonar-issues.json
          curl -sf -u "$SONAR_TOKEN:" "$API/hotspots/search?projectKey=$KEY&ps=500&$SCOPE" \
            -o reports/sonar-hotspots.json || echo '{"hotspots":[]}' > reports/sonar-hotspots.json
          curl -sf -u "$SONAR_TOKEN:" "$API/qualitygates/project_status?projectKey=$KEY&$SCOPE" \
            -o reports/sonar-qualitygate.json || echo '{}' > reports/sonar-qualitygate.json

      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: report-sonar          # BẮT BUỘC đúng tên này (tiền tố report-)
          path: reports/sonar-*.json
          if-no-files-found: ignore
```
Đọc README của action đã ghim để kiểm tra lại tên input. Nếu action đổi cách cấu hình host thì làm theo README.

### Bước 4 (23–24/11): Composite action Trivy
File `.github/actions/trivy-scan/action.yml`:

```yaml
name: trivy-scan
description: Quét CVE trong image, xuất JSON đầy đủ cho AI, rồi chặn nếu có HIGH/CRITICAL đã có bản vá
inputs:
  image-ref:
    description: Image đã build ở local (ví dụ local/api:<sha>)
    required: true
  service:
    description: Tên service (frontend | api), dùng để đặt tên file báo cáo
    required: true
  gate-severity:
    description: Các mức độ sẽ chặn
    required: false
    default: HIGH,CRITICAL
runs:
  using: composite
  steps:
    - name: Tạo thư mục reports
      shell: bash
      run: mkdir -p reports

    # Bước 1: báo cáo ĐẦY ĐỦ (mọi mức độ, kể cả chưa có bản vá), KHÔNG chặn → dữ liệu cho AI
    - name: Trivy - báo cáo JSON
      uses: aquasecurity/trivy-action@<GHIM_PHIEN_BAN>
      with:
        image-ref: ${{ inputs.image-ref }}
        scanners: vuln
        format: json
        output: reports/trivy-${{ inputs.service }}.json
        severity: UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL
        exit-code: "0"

    # Bước 2: CỔNG CHẶN, chỉ tính HIGH/CRITICAL đã có bản vá
    - name: Trivy - cổng chặn
      uses: aquasecurity/trivy-action@<GHIM_PHIEN_BAN>
      with:
        image-ref: ${{ inputs.image-ref }}
        scanners: vuln
        format: table               # hiển thị dạng bảng trong log cho dễ đọc
        severity: ${{ inputs.gate-severity }}
        ignore-unfixed: true
        exit-code: "1"
        trivyignores: .trivyignore
        skip-setup-trivy: true      # Trivy đã được cài ở bước trước
```
- Đối chiếu tên input với README của phiên bản đã ghim.
- Nếu gặp `TOOMANYREQUESTS` khi tải cơ sở dữ liệu lỗ hổng: thêm biến môi trường `TRIVY_DB_REPOSITORY: public.ecr.aws/aquasecurity/trivy-db` và bật cache theo README.
- Tạo file `.trivyignore` ở thư mục gốc. Mặc định để trống. Mỗi CVE được bỏ qua phải có dòng chú thích `# lý do, người duyệt, ngày`.

### Bước 5 (25/11): Kiểm thử trên PR
1. Mở PR từ nhánh `feat/tv1-devsecops`.
2. Tab Actions: job `sonar` xanh, `build-scan-push` xanh. Trong mục Artifacts phải có `report-sonar`, `report-trivy-frontend`, `report-trivy-api`.
3. Tải artifact về, mở JSON kiểm tra có dữ liệu.
4. Lấy `sonar-*.json` thật, đưa vào `ai-analyzer/samples/` và **giao cho TV2** (trước 26/11).

### Bước 6 (27–28/11): Kịch bản demo "bị chặn"
1. Tạo nhánh `demo/vulnerable`. Trong `services/api/requirements.txt`, thêm một thư viện cũ có lỗ hổng HIGH/CRITICAL **đã có bản vá**. Ví dụ `urllib3==1.26.4` (có CVE-2021-33503, đã vá ở 1.26.5).
   **Quét local trước** (`trivy image ...`) để chắc chắn Trivy báo HIGH/CRITICAL và có `FixedVersion`. Nếu không thì đổi thư viện khác.
2. Mở PR, pipeline phải **đỏ ở bước "Trivy - cổng chặn"**, không có bước push, job `ai-report` vẫn chạy.
3. Chụp ảnh: log Trivy dạng bảng, pipeline đỏ, báo cáo AI.
4. Gỡ thư viện lỗi ra, push lại thì pipeline xanh. Chụp ảnh.
5. (Tùy chọn) Demo Sonar: thêm một đoạn code có lỗi bảo mật rõ ràng (ví dụ `eval()` trên dữ liệu người dùng nhập) để Quality Gate fail. **Chỉ làm trên nhánh demo, không merge.**

### Bước 7 (28–29/11): Tài liệu
- `docs/devsecops.md`: luồng hai cổng chặn, tiêu chí chặn, cách xử lý false positive (dùng `.trivyignore` có lý do, hoặc đánh dấu "Safe" trên Sonar).
- `docs/report/06-devsecops.md`: lý thuyết (DevSecOps, shift-left, SAST/SCA), cách triển khai, ảnh chụp, đánh giá.

> Phần quét CloudFormation (`iac-lint`) **đã chuyển cho TV3**. Bạn không làm phần này.

## 7. Lỗi hay gặp

| Lỗi | Nguyên nhân | Cách sửa |
|---|---|---|
| "You are running CI analysis while Automatic Analysis is enabled" | Chưa tắt Automatic Analysis | Tắt trong SonarCloud |
| Quality Gate fail vì coverage | Không có coverage hoặc đường dẫn sai | Kiểm tra `coverage-*.xml` đã được tải về chưa, kiểm tra đường dẫn |
| `Not authorized` khi gọi API Sonar | Token sai hoặc thiếu quyền | Tạo lại token, kiểm tra secret |
| Trivy không chặn dù có CVE | CVE chưa có bản vá (bị `ignore-unfixed` bỏ qua) hoặc chỉ ở mức MEDIUM | Đúng với thiết kế. Đổi thư viện demo |
| Không thấy artifact | Sai tên, hoặc thiếu `if: always()` | Tên phải bắt đầu bằng `report-` |
| PR không đọc được secrets | PR mở từ fork | Làm trên nhánh của repo gốc |

## 8. Câu hỏi vấn đáp cho phần của bạn

1. SAST khác quét image thế nào? Vì sao cần cả hai?
2. Vì sao Trivy chạy **trước** khi push ECR mà không phải sau?
3. `--ignore-unfixed` được lợi gì và mất gì?
4. Quality Gate gồm những điều kiện nào? "New code" nghĩa là gì?
5. Gặp false positive thì xử lý ra sao mà không làm yếu quy trình?
6. Vì sao chạy Trivy hai lần (báo cáo đầy đủ và cổng chặn)?
7. Ngoài CVE, Trivy còn quét được những gì? (secret, misconfiguration, SBOM)
8. "Shift-left" thể hiện ở đâu trong pipeline của nhóm?

## 9. Phối hợp

- **Phụ thuộc vào Thuận:** khung `ci.yml` và Dockerfile (dự kiến 21–22/11). Trong lúc chờ, làm Bước 0 và Bước 1.
- **TV2 phụ thuộc vào bạn:** mẫu JSON Trivy (21/11) và mẫu Sonar thật (26/11). **Đừng để TV2 phải chờ.**
- **Mọi người nộp phần báo cáo cho bạn trước 29/11.** TV3 không viết báo cáo, chỉ giao ghi chú kỹ thuật + ảnh; bạn viết lại thành mục 09.
- Báo cáo tiến độ 21:00 hằng ngày trong nhóm: *Đã xong / Ngày mai / Vướng*.

---

## 10. NHIỆM VỤ THỨ HAI: Ghép báo cáo cuối kỳ

### Bước R1 (19–21/11): Chuẩn bị khung
1. **Hỏi giảng viên** mẫu báo cáo (Word hay PDF, số trang, cách trích dẫn, có bắt buộc trang bìa/mục lục không) và hình thức chấm (thời lượng demo, vấn đáp). Báo lại cho cả nhóm.
2. Tạo 12 file khung trong `docs/report/` theo bảng ở file 00 mục 12. Mỗi file có sẵn tiêu đề mục và 3–5 gạch đầu dòng gợi ý nội dung cần viết. Mở PR, báo cả nhóm.
3. Viết sẵn **hướng dẫn viết** ở đầu `docs/report/README.md`: giọng văn (ngôi "nhóm"), giữ nguyên thuật ngữ và tên trong file 00, mỗi ảnh có chú thích "Hình X: ...", đặt tên ảnh theo quy ước.

### Bước R2 (25–29/11): Viết các phần của bạn
| File | Nội dung | Nguồn |
|---|---|---|
| `01-gioi-thieu.md` | Bối cảnh, mục tiêu, phạm vi (Phương án B), công nghệ sử dụng | File 00 mục 1–3 |
| `09-monitoring.md` | Lý thuyết giám sát (Prometheus mô hình pull, Grafana, kube-state-metrics…), cách triển khai GitOps, giải thích các panel, ảnh; **thêm mục quét IaC** (cfn-lint, Checkov) | `docs/monitoring.md` và ảnh của TV3. Hỏi TV3 khi chưa rõ |
| `10-ket-qua.md` | Bảng đối chiếu "kết quả dự kiến của đề tài" với "kết quả đạt được", kèm ảnh minh chứng | Ảnh của cả nhóm trong `docs/images/` |
| `12-han-che.md` | Hạn chế (1 NAT, không persistence, AI có thể sai…) và hướng phát triển (các mục Phương án C) | Hỏi ý cả nhóm, gom lại |

### Bước R3 (29/11 – 01/12): Ghép
- **29/11:** kiểm tra đã nhận đủ phần của Thuận (04, 05, 08, 11, 03) và TV2 (07). Ai trễ thì nhắc ngay trong nhóm.
- Ghép theo mẫu giảng viên: thống nhất giọng văn và thuật ngữ, đánh số hình và bảng, mục lục, tài liệu tham khảo, trang bìa có tên và MSSV các thành viên, bảng phân công.
- **01/12:** gửi bản hoàn chỉnh cho cả nhóm đọc lại. Sửa xong thì nộp ngày 02/12.
- Gửi TV2 bản báo cáo sớm nhất có thể để TV2 lấy nội dung làm slide.
