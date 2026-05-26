# LockedCV-API Centralized Policies 實作計畫

## 問題與目標

- 本週 API 目標是把 authorization decision 從 controller/service scattered checks 收斂到 centralized policy objects。
- API 需要建立 `app/policies/`，每個主要 resource 至少有一個 policy object，讓 account 對 resource 的 view/create/update/delete 權限有明確 predicate。
- API 需要建立 policy scopes，用於 index routes 回傳「目前 account 能看到的 resources」。
- API response 需要使用一致的 authorization status codes：
  - `400 Bad Request`：request 結構、欄位、格式錯誤。
  - `401 Unauthorized`：authentication 失敗、缺 token、token invalid/expired、login failed。
  - `403 Forbidden`：已 authenticated，但缺少執行 action 的 permission。
  - `404 Not Found`：resource 不存在；也可用來隱藏不應被 snooping 的 authorized resource。
- GET resource routes 應回傳該 current account 對 resource 的 policy summary，讓 App 依 API 回傳的權限摘要決定是否顯示 links/buttons/actions。
- `AccountPolicy` 需要提供 system-level capabilities summary，例如 admin/system-role-management/resource-create privileges。

## 現況分析（2026-05-26）

- 專案：`LockedCV-API`
- 目前已有：
  - Bearer token authentication helpers。
  - Token-scoped current account routes：`GET/PUT /api/v1/account`、`PUT /api/v1/account/password`。
  - Token-scoped attachment routes：list/upload/detail/delete/sensitive-data/masked-text/masked-export。
  - Admin target routes：account list/delete、system role assignment。
  - `Account#admin?`、`Account#member?`、`Account#system_role?`。
  - `app/policies/` foundation：`AccountPolicy`、`AttachmentPolicy`、`SensitiveDataPolicy`。
  - `AccountPolicy#capabilities` system-level capability summary。
  - Policy unit specs for account, attachment, sensitive data, and scopes.
  - Service-level authorization checks，例如 `DeleteAccountService`、`AssignSystemRoleService`、`ListAccountsService`。
  - Status code baseline：missing/invalid auth mostly `401`；forbidden admin actions `403`; missing/hidden attachments mostly `404`.
- 目前尚未有：
  - `MaskedAttachmentPolicy`。
  - `summary` / `index_summary` response contract。
  - Policy-aware JSON response，讓 App 不需要自己推論 UI authorization。
  - Controller adoption：routes 仍有部分 `admin?` / owner checks 尚未改成 policy predicates。

### Resource Role 現況

- `Role::RESOURCE_ROLES` 與 seed 目前仍包含 `owner`、`viewer_masked`、`viewer_full`，但這些 role 現在只存在於全域 `roles` / `accounts_roles` 關係。
- 目前沒有 entity-level sharing table 可以表達「某 account 對某 attachment 是 viewer_masked」。
- 因此第一版 policy 不使用 `Attachment#owner` / `Attachment#viewers_masked` 這類全域 role helper 判斷單一 attachment 權限，而是先用 `attachment.account_id == current_account.id` 判斷 owner。
- 產品決策目前只考慮 `owner` 與 `viewer_masked`；`viewer_full` 視為 legacy role name，後續可另開 cleanup。
- `SensitiveDataPolicy` 視 sensitive data 為 attachment-owned resource：先判斷 current account 對 parent attachment 的權限，再決定是否能 view/update/delete sensitive data。
- Professor repo 的 role model 可成立，是因為 course-level roles 透過 `enrollments(account_id, course_id, role_id)` 綁到特定 course；LockedCV 若要同等表達 attachment-level roles，需要類似 `attachment_permissions(account_id, attachment_id, role_id)` 的 entity-level join table。
- Predicate naming 決策：`view?` / `can_view?` 表示可看原始 attachment/raw sensitive data；`view_masked?` / `can_view_masked?` 表示可看遮罩版。若需要泛稱「可看到任一版本」，另用 `access?` 或 `can_access?`，避免 `view?` 語意混淆。
- Policy foundation 已採用此語意：`AttachmentPolicy#view?` 為 owner-only raw access，`#view_masked?` 為 owner 或 viewer_masked masked access，`#access?` 為任一版本可見。
- System roles 採「DB 單選、policy 階層式」：account 在 `accounts_roles` 中應只有一個 system role（`admin` 或 `member`），但 policy capabilities 視 `admin` 為包含一般 member 能力，例如可上傳 attachment。
- 一般註冊帳號仍由 `CreateAccountService` 預設給 `member`；seed、bootstrap admin、system role assignment 透過 shared system-role setter 保持單選。

## 參考方向

- Professor repo `tyto2026-api` 可參考：
  - `app/policies/account_policy.rb`
  - `app/policies/course_policy.rb`
  - `app/policies/course_scopes.rb`
- 可採相同概念：
  - Policy initialize with subject and object，例如 `AttachmentPolicy.new(current_account, attachment)`。
  - Predicate methods 使用 `can_view?`、`can_edit?`、`can_delete?`、`can_export_masked_pdf?` 等清楚命名。
  - `summary` 回傳 predicate name 到 boolean 的 hash。
  - `index_summary` 可用於 list response，避免 index route 做過多 expensive checks。
  - Scope object re-expresses policy predicates as queries/lists，並用 tests 保持 scope 與 policy 一致。

## 實作策略（分階段）

1. **Status-code audit**：先盤點現有 controller/service error mapping，對齊 `400/401/403/404` 規則。
2. **Policy object foundation**：建立 `app/policies/`，先做 `AccountPolicy`、`AttachmentPolicy`、`SensitiveDataPolicy`，覆蓋目前最常用 resource。
3. **Policy summaries**：每個 policy 提供 `summary`；需要 index response 時提供 `index_summary`。
4. **Policy scopes**：建立 list/index routes 用的 scope object，例如 `AttachmentPolicy::AccountScope#viewable`、`AccountPolicy::AdminScope#viewable`；scope classes 放在獨立 `*_scopes.rb`，與 policy predicates 分離。
5. **Controller adoption**：controller 不直接問 `admin?` 或手寫 owner checks，改呼叫 policy predicates；resource not visible 時依 snooping 需求回 `404` 或 `403`。
6. **Account capabilities**：在 `AccountPolicy#capabilities` 建立 system-level capability summary，回傳目前 account 可以做的 system actions。
7. **Response contract update**：GET single resource routes 回傳 `policies` / `capabilities`，讓 APP 用 API policy summary 控制 UI。
8. **Tests and docs**：補 policy unit specs、scope consistency specs、integration specs、README/copilot/local docs。

## Todo 清單

1. `status-code-audit`
   - 盤點所有 API routes 的 `400/401/403/404/500`。
   - Login failure 改或確認為 `401 Unauthorized`，符合本週要求。
   - Bad request 統一用於 malformed JSON、mass assignment、invalid file upload、invalid role name、validation failure。
   - Auth token missing/invalid/expired 統一 `401`。
   - Authenticated but not allowed 統一 `403`，除非刻意用 `404` 隱藏 resource existence。
   - 用 integration specs 固定主要 route 的 status code 行為。

2. ✅ `policy-directory-and-require`
   - 新增 `app/policies/`。
   - 更新 app loader / require path，讓 policies 在 API boot 時可用。
   - 建立 naming convention：`AccountPolicy`、`AttachmentPolicy`、`SensitiveDataPolicy`、`MaskedAttachmentPolicy`。

3. ✅ `account-policy`
   - 建立 `AccountPolicy`。
   - Actor-scoped predicates：
     - `is_admin?`
     - `can_list_accounts?`
     - `can_delete_accounts?`
     - `can_manage_system_roles?`
   - Entity-scoped predicates：
     - `can_view?`
     - `can_edit?`
     - `can_change_password?`
     - `can_delete?`
     - `can_assign_role?`
   - `summary` 回傳 viewer 對 target account 的權限。
   - `capabilities` 回傳 viewer 的 system-level privileges。
   - `capabilities` 需放在 policy，不放在 model，避免 model 承擔 authorization decision。

4. ✅ `attachment-policy`
   - 建立 `AttachmentPolicy`。
   - Predicates 至少包含：
     - `can_view?`
     - `can_view_masked?`
     - `can_upload?` 或 actor-scoped create/upload equivalent。
     - `can_delete?`
     - `can_view_sensitive_data?`
     - `can_create_sensitive_data?`
     - `can_preview_masked_text?`
     - `can_export_masked_pdf?`
   - 目前 first pass 沿用「owner account 可做全部 owned attachment actions」。
   - `can_view?` 語意應對齊「可看原始 PDF / raw sensitive data」。
   - `can_view_masked?` 語意應對齊「可看遮罩 PDF / masked output」。
   - `viewer_masked?` predicate 已保留，但因尚無 entity-level sharing table，目前回 `false`。
   - 後續再接 `owner` / `viewer_masked` resource roles 或 sharing model。

5. ✅ `sensitive-data-policy`
   - 建立 `SensitiveDataPolicy`。
   - Sensitive data 權限委派給 parent attachment policy。
   - Owner 可 view/update/delete raw sensitive data；非 owner 不可看 raw sensitive data。

6. ✅ `policy-scopes`
   - 建立 `AttachmentPolicy::AccountScope`。
   - Scope classes 拆到 `account_scopes.rb`、`attachment_scopes.rb`、`sensitive_data_scopes.rb`，跟 professor repo convention 對齊。
   - `viewable` 回傳 current account 可 list 的 attachments。
   - 若 admin settings 需要，建立 `AccountPolicy::AdminScope#viewable` 作為 admin account list。
   - 補 scope/policy consistency tests：scope 回傳的每個 resource 都應 `view? == true`。

7. `controller-policy-adoption`
   - `GET /api/v1/accounts` 使用 `AccountPolicy` 或 scope 檢查 admin list。
   - `DELETE /api/v1/accounts/:account_id` 使用 `AccountPolicy#can_delete?`。
   - `PUT /api/v1/accounts/:username/system_roles/:role_name` 使用 `AccountPolicy#can_assign_role?` 或 `SystemRolePolicy`。
   - `GET /api/v1/attachments` 使用 `AttachmentPolicy::AccountScope#viewable`。
   - Attachment detail/delete/sensitive-data/masked routes 使用 `AttachmentPolicy`。
   - 保持 route response status 與本週 status-code rules 一致。

8. `policy-json-contract`
   - Single resource GET response 加入 policy summary，例如：

     ```json
     {
       "data": {
         "type": "attachment",
         "attributes": {},
         "policies": {
           "can_view": true,
           "can_delete": true,
           "can_export_masked_pdf": true
         }
       }
     }
     ```

   - Current account response 加入 capabilities，例如：

     ```json
     {
       "capabilities": {
         "is_admin": true,
         "can_list_accounts": true,
         "can_manage_system_roles": true
       }
     }
     ```

   - Index response 視需求加入 `index_summary` 或 per-resource minimal policies。

9. `policy-tests-and-docs`
   - 補 unit specs for each policy。
   - 補 integration specs 確認 routes 使用 policies。
   - 更新 README API response contract。
   - 更新 `.github/copilot-instructions.md` 與 `local.md`。

## 依賴順序

- `status-code-audit` -> `policy-tests-and-docs`
- `policy-directory-and-require` -> 所有 policy objects。
- `account-policy` -> account list/delete/system-role routes。
- `attachment-policy` -> attachment detail/delete/sensitive-data/masked routes。
- `policy-scopes` -> index routes。
- `policy-json-contract` -> APP `plan.validation.md` 中的 policy summary UI。

## 待組內決策

- Login failed status 是否從目前既有行為調整為 `401`，並同步 App error handling。
- Attachment resource roles 目標只考慮 `owner` 與 `viewer_masked`；是否需要新增 entity-level sharing table。
- Sensitive data 是否視為 attachment 的一部分，或獨立 `SensitiveDataPolicy`。
- Masked PDF output 是否需要獨立 `MaskedAttachmentPolicy`，或先由 parent `AttachmentPolicy` 決定。
- Unauthorized resource access 要回 `403` 還是用 `404` 隱藏 existence 的 route-by-route 規則。
- Policy summary JSON 欄位命名：`policies`、`policy`、或 `capabilities`。

## 本週完成定義

- API 有 `app/policies/` 並至少完成 `AccountPolicy` 與 `AttachmentPolicy`。
- 主要 protected routes 不再直接散落 `admin?` / owner authorization checks，而是透過 policy predicate。
- Index routes 使用 policy scopes。
- GET resource response 含 policy summary，current account response 含 capabilities。
- Status code behavior 對齊 `400/401/403/404` 規則並有 specs。
- APP 可以依 API 回傳的 policy summaries 顯示或隱藏 links/buttons/actions。
