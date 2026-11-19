# 02 — TV2: Thành phần AI phân tích bảo mật (AI Security Analyzer) và Slide

> **Cách dùng:** dán **file này kèm file `00-TONG-QUAN-DE-TAI.md`** vào AI của bạn, rồi gửi đoạn mở đầu dưới đây.

```
Bạn là mentor Python + DevSecOps của tôi trong đồ án môn NT548. Hãy đọc kỹ 2 file tôi gửi.
Quy tắc:
1. Chỉ làm trong phạm vi file 02. Không đổi tên file, giao diện dòng lệnh (CLI), tên artifact,
   tên biến môi trường hay công cụ đã chốt (Gemini). Nếu thấy cần đổi, hãy nói lý do để tôi hỏi trưởng nhóm.
2. Hướng dẫn từng bước. Giải thích bản chất trước, rồi mới đưa code. Code có chú thích, kèm unit test.
3. Sau mỗi bước, hỏi tôi kết quả chạy thực tế rồi mới sang bước tiếp.
4. Khi tôi gặp lỗi, phân tích log, chỉ ra nguyên nhân gốc trước khi đưa cách sửa.
5. Cuối mỗi buổi, tóm tắt 3 câu hỏi vấn đáp về phần vừa làm.
Bắt đầu từ Bước 0.
```

---

## 1. Vai trò và mục tiêu

Bạn xây một **công cụ dòng lệnh bằng Python**. Công cụ đọc kết quả quét của SonarCloud và Trivy (file JSON), sau đó:
1. **Tổng hợp**: gom về một định dạng chung, đếm theo nguồn và mức độ.
2. **Xếp ưu tiên**: chấm điểm bằng **quy tắc cố định trong code**, không giao cho AI.
3. **Giải thích và đề xuất cách sửa**: gửi top N vấn đề cho Gemini để viết giải thích bằng tiếng Việt và hướng khắc phục cụ thể.
4. **Xuất báo cáo Markdown**: hiển thị trong GitHub Actions Summary và comment vào PR.

**Nhiệm vụ thứ hai:** vẽ **sơ đồ kiến trúc**, làm **slide** và viết **kịch bản demo** (chi tiết ở mục 10).

### Nguyên tắc thiết kế (bắt buộc, giảng viên sẽ hỏi)
- **AI chỉ tư vấn, không bao giờ chặn pipeline.** LLM cho kết quả không ổn định và có thể "bịa". Việc chặn do Quality Gate và Trivy (của TV1) quyết định.
- **Số liệu do code tính, AI chỉ diễn giải.** Số lượng lỗi, mức độ, thứ tự ưu tiên đều được tính bằng code. AI không được tự đếm hay tự xếp hạng.
- **AI hỏng thì vẫn có báo cáo.** Không có key, hết hạn mức, mạng lỗi: vẫn xuất phần thống kê kèm thông báo "Phần AI không khả dụng", và **luôn trả về exit code 0**.
- **Chống bịa:** chỉ gửi dữ liệu thật, yêu cầu AI chỉ dùng dữ liệu đó, đặt temperature thấp, giới hạn top N.

## 2. Ranh giới

| Bạn LÀM | Bạn KHÔNG làm |
|---|---|
| Toàn bộ thư mục `ai-analyzer/` | Sonar/Trivy (TV1 tạo JSON cho bạn) |
| Job `ai-report` trong `ci.yml` (chỉ trong khối `[TV2]`) | Các job khác trong `ci.yml` |
| Lấy Gemini API key (free tier) | Bật billing cho Gemini |
| `docs/ai-analyzer.md`, `docs/report/07-ai.md` | Việc trên AWS. **Bạn không cần tài khoản AWS** |
| **Sơ đồ kiến trúc, slide, kịch bản demo** | Đổi sang OpenAI/Bedrock, hay dùng framework nặng (LangChain…) |
| | Ghép báo cáo (của TV1) |

## 3. Bạn nằm ở đâu trong pipeline

```
sonar (TV1) ──► artifact report-sonar          ─┐
build-scan-push ► artifact report-trivy-frontend ├─► [ai-report] (BẠN) ─► Step Summary + comment PR
               ► artifact report-trivy-api     ─┘     needs: [sonar, build-scan-push], if: always()
```
Job của bạn chạy **kể cả khi các job trước fail**. Đây chính là lúc báo cáo AI có giá trị nhất.

## 4. HỢP ĐỒNG ĐẦU VÀO / ĐẦU RA (không được đổi)

### 4.1. Giao diện dòng lệnh
```bash
python ai-analyzer/analyze.py \
  --reports-dir reports \
  --output reports/ai-security-report.md \
  [--max-findings 20] \
  [--no-llm]
```
- Biến môi trường: `GEMINI_API_KEY` (không bắt buộc; thiếu thì tự chuyển sang chế độ không dùng LLM), `GEMINI_MODEL` (có giá trị mặc định trong code), `GITHUB_SHA` (không bắt buộc, dùng để ghi vào tiêu đề báo cáo).
- **Exit code luôn là 0**, trừ khi tham số dòng lệnh sai.

### 4.2. File đầu vào trong `--reports-dir` (file nào cũng có thể thiếu hoặc rỗng)
| File | Cấu trúc cần đọc |
|---|---|
| `trivy-frontend.json`, `trivy-api.json` | `Results[].Vulnerabilities[]`: `VulnerabilityID`, `PkgName`, `InstalledVersion`, `FixedVersion` (có thể rỗng), `Severity`, `Title`. Lưu ý `Vulnerabilities` có thể là `null` |
| `sonar-issues.json` | `issues[]`: `rule`, `type` (BUG / VULNERABILITY / CODE_SMELL), `severity` (kiểu cũ), `impacts[]` (kiểu mới: `softwareQuality`, `severity`), `component`, `line`, `message` |
| `sonar-hotspots.json` | `hotspots[]`: `ruleKey`, `vulnerabilityProbability` (HIGH / MEDIUM / LOW), `component`, `line`, `message`, `status` |
| `sonar-qualitygate.json` | `projectStatus.status` (OK / ERROR / NONE), `projectStatus.conditions[]` |

### 4.3. Định dạng chung sau khi chuẩn hóa (trong code)
```python
@dataclass
class Finding:
    source: str          # "trivy" | "sonar-issue" | "sonar-hotspot"
    id: str              # CVE-2021-33503 | python:S5332 ...
    severity: str        # CRITICAL | HIGH | MEDIUM | LOW | INFO
    title: str
    location: str        # "image api · urllib3 1.26.4" | "services/api/app.py:42"
    fix: str | None      # phiên bản đã vá (Trivy) hoặc None
    category: str        # "dependency" | "code" | "hotspot"
    services: list[str]  # ["api"], ["api", "frontend"] nếu trùng CVE ở cả hai
    score: int = 0       # do prioritize.py tính
```

**Quy đổi mức độ:**
- Trivy: giữ nguyên, riêng `UNKNOWN` đổi thành `LOW`.
- Sonar issue: ưu tiên `impacts[].severity` (BLOCKER→CRITICAL, HIGH→HIGH, MEDIUM→MEDIUM, LOW→LOW, INFO→INFO). Nếu không có `impacts` thì dùng `severity` kiểu cũ (BLOCKER→CRITICAL, CRITICAL→HIGH, MAJOR→MEDIUM, MINOR→LOW, INFO→INFO).
- Sonar hotspot: `vulnerabilityProbability` giữ nguyên HIGH / MEDIUM / LOW.

**Điểm ưu tiên** (đặt cố định trong `prioritize.py` và ghi lại trong README):
```
điểm = trọng số mức độ (CRITICAL 100, HIGH 70, MEDIUM 40, LOW 10, INFO 0)
     + 15 nếu đã có bản vá (sửa được ngay)
     + 10 nếu là Sonar issue loại VULNERABILITY
     + 5  nếu xuất hiện ở nhiều service
```
Gộp các CVE trùng nhau giữa 2 image thành 1 mục, `services` là danh sách cả hai.

### 4.4. Đầu ra: `ai-security-report.md` (đúng cấu trúc này)
```markdown
# Báo cáo bảo mật (AI hỗ trợ) — commit abc1234

## 1. Kết quả cổng chặn            ← CODE tính
- SonarCloud Quality Gate: ✅ OK / ❌ ERROR / ⚪ không có dữ liệu
- Trivy: ❌ có N lỗ hổng HIGH/CRITICAL đã có bản vá → sẽ bị chặn / ✅ không có

## 2. Thống kê                      ← CODE tính
| Nguồn | CRITICAL | HIGH | MEDIUM | LOW |
...

## 3. Top N vấn đề cần xử lý trước  ← CODE xếp hạng
| # | Mức độ | ID | Vị trí | Bản vá |
...

## 4. Phân tích và đề xuất khắc phục ← AI viết
(mỗi mục: Vì sao nguy hiểm · Cách sửa cụ thể · Lý do ưu tiên)

## 5. Ghi chú
- Phần 4 do AI (<tên model>) tạo, chỉ mang tính tham khảo, cần người kiểm tra lại.
- Quyết định chặn phát hành do SonarCloud Quality Gate và Trivy thực hiện.
- Thời điểm tạo: <giờ Việt Nam UTC+7>
```

## 5. Cấu trúc thư mục bàn giao

```
ai-analyzer/
├── analyze.py            # CLI: đọc tham số → parsers → prioritize → llm → render
├── parsers.py            # đọc Trivy/Sonar → list[Finding]; chịu được file thiếu, rỗng, null
├── prioritize.py         # chấm điểm, gộp trùng, sắp xếp, lấy top N
├── llm.py                # gọi Gemini; thử lại 1 lần; lỗi thì trả về None
├── render.py             # dựng Markdown theo mục 4.4
├── prompts/system_prompt.md
├── samples/              # JSON mẫu (TV1 giao; tự tạo thêm nếu cần)
├── tests/                # pytest cho parsers, prioritize, render
├── requirements.txt      # google-genai, pytest (ghim phiên bản)
└── README.md
```

## 6. Các bước thực hiện

### Bước 0 (19–20/11): Chuẩn bị
1. Cài Python 3.12, tạo virtualenv.
2. Lấy **Gemini API key** trên Google AI Studio. **Không bật billing.** Lưu key trong biến môi trường máy, **không ghi vào code hay commit**.
3. Đọc trang giới hạn của free tier (số request mỗi phút, mỗi ngày). Lưu ý: dữ liệu gửi qua free tier có thể được Google dùng để cải thiện sản phẩm, nên **không gửi secret hay mã nguồn nhạy cảm**.
4. Trong lúc chờ mẫu từ TV1: cài Trivy và tự chạy `trivy image --format json -o ai-analyzer/samples/trivy-api.json nginx:1.19`. Với Sonar, tạo file mẫu nhỏ theo cấu trúc ở mục 4.2.

### Bước 1 (20–22/11): `parsers.py` + test
- Viết hàm đọc từng loại file, trả về `list[Finding]`.
- Test bắt buộc: file thiếu, file rỗng `{}`, `Vulnerabilities: null`, Sonar có `impacts` và không có `impacts`.

### Bước 2 (22–23/11): `prioritize.py` + `render.py` + chế độ `--no-llm`
- Chấm điểm và gộp trùng theo mục 4.3.
- Dựng Markdown mục 1, 2, 3, 5. Mục 4 ghi "Phần AI không khả dụng: <lý do>".
- **Mốc:** `python ai-analyzer/analyze.py --reports-dir ai-analyzer/samples --output out.md --no-llm` cho ra báo cáo hợp lệ.

### Bước 3 (23–24/11): `llm.py` + prompt
SDK chính thức là gói `google-genai`. Kiểm tra cú pháp với tài liệu hiện hành:
```python
import os
from google import genai
from google.genai import types

def explain(findings_text: str, system_prompt: str) -> str | None:
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        return None                                   # chuyển sang chế độ không dùng LLM
    model = os.getenv("GEMINI_MODEL") or "<model Flash hiện hành>"
    client = genai.Client(api_key=key)
    try:
        resp = client.models.generate_content(
            model=model,
            contents=findings_text,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                temperature=0.2,                      # thấp → ổn định, ít bịa
                max_output_tokens=2048,
            ),
        )
        return resp.text
    except Exception as e:                            # 429/5xx: thử lại 1 lần sau vài giây, vẫn lỗi thì trả về None
        ...
```
- Chọn model **Flash** (nhanh, có free tier). Kiểm tra tên model mới nhất trên Google AI Studio và đặt mặc định trong code. Biến `GEMINI_MODEL` dùng để đổi model mà không phải sửa code.
- Chỉ gửi **top N** finding (mặc định 20) dưới dạng danh sách gọn để tiết kiệm token.
- **Ẩn thông tin nhạy cảm trước khi gửi:** che các chuỗi trông giống key, ví dụ `AKIA[0-9A-Z]{16}` hay `password=...`.

**`prompts/system_prompt.md`** cần có các ý sau:
- Vai trò: chuyên gia bảo mật ứng dụng, viết tiếng Việt, ngắn gọn.
- **Chỉ dùng dữ liệu được cung cấp.** Không bịa CVE, phiên bản hay điểm CVSS. Không chắc thì nói "cần kiểm tra thêm".
- Với mỗi vấn đề: (1) vì sao nguy hiểm, 1–2 câu; (2) cách sửa cụ thể (nâng lên phiên bản nào, sửa dòng code nào); (3) vì sao nên ưu tiên.
- Giữ nguyên thứ tự đã cho. **Không tự xếp hạng lại, không tự đếm.**
- Độ dài tối đa khoảng 800 từ, định dạng Markdown, không dùng tiêu đề cấp 1.

### Bước 4 (24/11): **Mốc M2**
- Chạy local có key và không có key, cả hai đều ra báo cáo hợp lệ, exit code 0.
- `pytest ai-analyzer/tests` xanh.

### Bước 5 (25–26/11): Job `ai-report` trong `ci.yml`
Thay khối `[TV2]` trong khung ở file 00:
```yaml
  ai-report:
    needs: [sonar, build-scan-push]
    if: always()                      # chạy cả khi Sonar/Trivy fail
    runs-on: ubuntu-latest
    continue-on-error: true           # AI không bao giờ làm đỏ pipeline
    permissions:
      contents: read
      pull-requests: write            # để comment vào PR
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install -r ai-analyzer/requirements.txt
      - uses: actions/download-artifact@v4
        with:
          pattern: report-*           # report-sonar, report-trivy-frontend, report-trivy-api
          merge-multiple: true
          path: reports
      - name: Chạy AI analyzer
        env:
          GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
          GEMINI_MODEL: ${{ vars.GEMINI_MODEL }}
        run: python ai-analyzer/analyze.py --reports-dir reports --output reports/ai-security-report.md
      - name: Đưa báo cáo lên Summary
        run: cat reports/ai-security-report.md >> "$GITHUB_STEP_SUMMARY"
      - name: Comment vào PR (sửa comment cũ thay vì tạo mới)
        if: github.event_name == 'pull_request'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh pr comment ${{ github.event.pull_request.number }} --edit-last --body-file reports/ai-security-report.md \
          || gh pr comment ${{ github.event.pull_request.number }} --body-file reports/ai-security-report.md
      - uses: actions/upload-artifact@v4
        with:
          name: ai-security-report    # KHÔNG có tiền tố report- để không lẫn với dữ liệu đầu vào
          path: reports/ai-security-report.md
```
- Gửi key **riêng** cho Thuận để thêm secret `GEMINI_API_KEY`, kèm tên model cho variable `GEMINI_MODEL`.

### Bước 6 (27–28/11): Ghép với pipeline thật
- Khi TV1 có nhánh `demo/vulnerable`: kiểm tra báo cáo AI giải thích đúng CVE bị chặn và đề xuất đúng phiên bản vá.
- So sánh báo cáo AI với dữ liệu gốc. Ghi lại **1–2 trường hợp AI nói sai hoặc thiếu**, đây là tư liệu tốt cho phần "hạn chế" trong báo cáo.
- Chụp ảnh: Step Summary, comment trên PR, báo cáo ở chế độ không dùng LLM (tạm xóa key để chụp).

### Bước 7 (28–29/11): Tài liệu
- `ai-analyzer/README.md`: cách chạy, biến môi trường, công thức tính điểm.
- `docs/report/07-ai.md`: lý do có thành phần AI; kiến trúc (sơ đồ: JSON → chuẩn hóa → xếp ưu tiên → LLM → Markdown); các nguyên tắc ở mục 1; ví dụ đầu ra; hạn chế (bịa, giới hạn hạn mức, quyền riêng tư dữ liệu); hướng phát triển (tự tạo PR sửa lỗi, RAG trên cơ sở dữ liệu CVE…).

## 7. Lỗi hay gặp

| Lỗi | Nguyên nhân | Cách sửa |
|---|---|---|
| `429 RESOURCE_EXHAUSTED` | Vượt hạn mức free tier | Thử lại 1 lần; vẫn lỗi thì dùng chế độ không LLM. Giảm `--max-findings` |
| Lỗi tên model (404) | Tên model đã đổi hoặc bị ngừng | Đổi variable `GEMINI_MODEL` |
| `TypeError: 'NoneType' is not iterable` | Trivy trả `Vulnerabilities: null` khi image sạch | Xử lý `or []` |
| Không thấy file trong `reports/` | Sai `pattern` hoặc thiếu `merge-multiple` | Đúng `pattern: report-*`, `merge-multiple: true` |
| Comment vào PR báo 403 | Thiếu `pull-requests: write` | Thêm vào `permissions` của job |
| Secret rỗng trong PR | PR mở từ fork | Làm trên nhánh của repo gốc |

## 8. Câu hỏi vấn đáp cho phần của bạn

1. Vì sao AI không được quyền chặn pipeline?
2. Làm sao hạn chế AI bịa thông tin? (Số liệu do code tính, chỉ đưa dữ liệu thật, temperature thấp, top N, cảnh báo cho người đọc.)
3. Gemini hết hạn mức hoặc mất kết nối thì pipeline thế nào?
4. Dữ liệu gửi cho AI có rủi ro gì? Nhóm xử lý ra sao?
5. Vì sao xếp ưu tiên bằng quy tắc trong code chứ không để AI xếp?
6. Làm sao đánh giá báo cáo AI tốt hay dở?
7. Vì sao chọn Gemini mà không chọn Bedrock hay OpenAI?
8. Nếu phát triển tiếp, thành phần AI có thể làm thêm gì?

## 9. Phối hợp

- **Bạn phụ thuộc vào TV1:** mẫu JSON Trivy (21/11) và mẫu Sonar thật (26/11). Chưa có thì tự tạo mẫu như Bước 0, không ngồi chờ.
- **Phụ thuộc vào Thuận:** khung `ci.yml` để thêm job, và việc thêm secret.
- **Nộp `docs/report/07-ai.md` cho TV1 trước 29/11.** Lấy nội dung báo cáo từ TV1 để làm slide.
- Báo cáo tiến độ 21:00 hằng ngày trong nhóm: *Đã xong / Ngày mai / Vướng*.

---

## 10. NHIỆM VỤ THỨ HAI: Sơ đồ kiến trúc, slide, kịch bản demo

### Bước S1 (22–23/11): Sơ đồ kiến trúc
- Vẽ trên **draw.io (diagrams.net)**, miễn phí, bật bộ icon AWS (More Shapes → AWS).
- **Sơ đồ 1, hạ tầng AWS:** Region Singapore → VPC → 2 AZ → mỗi AZ có 1 public subnet và 1 private subnet; Internet Gateway; NAT Gateway (chỉ ở 1 AZ); Load Balancer ở public subnet; 2 node EKS ở private subnet; ECR; S3 Gateway Endpoint. Tham khảo file 00 mục 4.
- **Sơ đồ 2, luồng DevSecOps + GitOps:** Dev → GitHub → GitHub Actions (test → SonarCloud → build → Trivy → AI/Gemini → ECR) → repo gitops → ArgoCD → EKS → Prometheus/Grafana. Tham khảo file 00 mục 2.
- Lưu file `.drawio` và xuất `.png` vào `docs/images/03-kien-truc-*.png`. **Gửi Thuận duyệt trước 24/11.**

### Bước S2 (27–28/11): Kịch bản demo (~10 phút)
| Phút | Nội dung | Người trình bày |
|---|---|---|
| 0–1 | Sơ đồ kiến trúc, luồng tổng thể | TV2 |
| 1–2 | CloudFormation: 4 stack, VPC/subnet, EKS; `iac-lint` | Thuận + TV3 |
| 2–5 | PR có thư viện lỗi → Sonar/Trivy chặn → báo cáo AI trên PR | TV1 + TV2 |
| 5–8 | Sửa lỗi → merge → ECR → repo gitops đổi tag → ArgoCD sync → app hiện phiên bản mới | Thuận |
| 8–10 | Grafana: dashboard, xóa Pod tự phục hồi, tạo tải | TV3 |

Ghi rõ **từng lệnh, từng cửa sổ cần mở sẵn** cho mỗi bước, và **phương án dự phòng** khi lỗi (chuyển sang video do TV3 quay ngày 30/11). Lưu ở `docs/demo-script.md`. Cả nhóm diễn tập trong phiên 30/11.

### Bước S3 (29/11 – 01/12): Slide (~12–15 trang)
- Thứ tự: bối cảnh và mục tiêu → kiến trúc → IaC → CI + DevSecOps → AI → GitOps → giám sát → demo → chi phí → hạn chế và hướng phát triển → phân công.
- Mỗi slide tối đa 5 dòng chữ, ưu tiên sơ đồ và ảnh chụp thật (lấy trong `docs/images/`).
- Mỗi người được 2–3 slide cho phần mình trình bày. Gửi bản nháp cho cả nhóm ngày 30/11, hoàn thiện ngày 01/12.
