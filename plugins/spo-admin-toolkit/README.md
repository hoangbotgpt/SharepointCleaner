# spo-admin-toolkit (Claude Code plugin)

Plugin hỗ trợ Claude viết công cụ PowerShell quản lý dung lượng SharePoint Online.

## Thành phần
| Loại | Tên | Mục đích |
|---|---|---|
| Skill | `spo-project-conventions` | Cấu trúc module SPCleaner, đặt tên, schema output, menu, báo cáo |
| Skill | `spo-connect` | Cài PnP.PowerShell, đăng ký Entra app, xác thực, cache connection |
| Skill | `spo-site-storage` | Chức năng 1 – site > X GB |
| Skill | `spo-file-inventory` | Quét file của site; chức năng 2 (file lớn) và 3 (file trùng) |
| Skill | `spo-version-cleanup` | Chức năng 4 (file nhiều version) và 5 (xoá version cũ) |
| Skill | `spo-stale-files` | Chức năng 6 (file lâu không truy cập) và 7 (xoá file đó) |
| Skill | `spo-safe-delete` | Checklist an toàn cho mọi thao tác xoá |
| Skill | `spo-pester-testing` | Test Pester 5 với mock PnP, PSScriptAnalyzer |
| Command | `/spo-scaffold [tenant]` | Dựng toàn bộ project |
| Command | `/spo-feature <mô tả>` | Thêm/sửa một chức năng đúng quy ước |
| Command | `/spo-review [path]` | Review an toàn code xoá |
| Agent | `spo-safety-reviewer` | Reviewer chỉ đọc, kiểm tra 12 tiêu chí an toàn |
| Hook | PostToolUse `Invoke-PostEditCheck.ps1` | Sau khi Claude sửa file .ps1: chặn cmdlet bị cấm, kiểm tra ShouldProcess, chạy PSScriptAnalyzer (nếu đã cài) |

## Cài đặt
Project đã khai báo marketplace cục bộ `spo-local` trong `.claude/settings.json` và bật plugin. Nếu Claude Code chưa nhận plugin, chạy trong `claude`:
```
/plugin marketplace add ./
/plugin install spo-admin-toolkit@spo-local
```
