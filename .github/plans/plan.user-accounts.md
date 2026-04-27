# LockedCV-API 帳號系統作業實作計畫

## 問題與目標
- 目前程式仍以 `User/users` 為核心，尚未有 `Account/accounts`、密碼雜湊/拉伸、可搜尋 PII hash 欄位、角色模型與帳號導向服務層。
- 本週目標是把現有 API 演進成「安全帳號系統」：完成帳號模型、密碼安全、PII 機密+可搜尋、多對多關聯、角色、服務物件、（可選）seeding 與帳號路由整合。
- 額外需求：README 明確標示 Ruby `4.0.2`，並把 `user` 命名逐步轉為 `account`（符合 OOP 名詞語意）。

## 現況分析（已完成）
- 專案：`LockedCV-API`
- `.ruby-version` 已是 `4.0.2`，但 `README.md` 仍寫 `4.0.1`。
- 目前資料模型：`users`、`attachments`、`sensitive_data`；`attachments.user_id -> users.id`，`sensitive_data.attachment_id -> attachments.id`。
- 目前已有機密欄位加密（`*_secure`）模式，但尚未有 `*_hash` 搜尋欄位。
- Controller 與測試大量使用 `/users` 路徑與 `LockedCV::User`。
- 已有部分 service object（查找 attachment/sensitive_data），但尚未形成 account-centric 的 create/get/update/search 服務層。

## 實作策略（分階段）
1. **基礎對齊與命名重構**：先完成 Ruby 版本文件對齊，並設計 `User -> Account` 的遷移策略（避免一次性破壞既有資料/測試）。
2. **安全帳號核心**：建立 KeyStretching + Password handling + Account model/migration（含 hashed password）。
3. **PII 機密+可搜尋**：對選定欄位建立 `*_secure` + `*_hash`，補齊搜尋 service/routes。
4. **關聯與角色**：導入多對多 join table 與 system/entity roles，定義雙向關聯和 association dependencies。
5. **控制器瘦身**：用 service objects 接管 controller 的查詢/建立/更新流程，並在測試和 seed 重用。
6. **可選 seeding**：加上 `sequel-seed` 與 `rake db:seed`，讓協作者能一鍵 setup。
7. **整體整合與回歸**：完成 account 路由與測試整合，確認舊 user 命名已移除或保留相容策略（視決策）。

## Todo 清單（含可先做/待決策）
1. ✅ `baseline-docs-and-version`（已完成）
   - 已完成：README 與 `.github/copilot-instructions.md` 的 Ruby 版本敘述已更新為 `4.0.2`。

2. ✅ `account-domain-renaming`（已完成）
   - 已完成：`User/users` 已改為 `Account/accounts`（model、migration、service、controller、spec、seed 命名）。
   - 已完成：路由改為 `/accounts`，並採巢狀 `/accounts/:account_id/attachments`，不保留 `/users`。
   - 備註：`sensitive_data.user_name` 已改為 `first_name` / `last_name`，避免與 account/user 命名混淆。

3. ✅ `password-security-core`（已完成）
   - 已完成：新增 `KeyStretch` module（RbNaCl + Base64）與 `Password` value object。
   - 已完成：新增 `spec/unit/password_spec.rb` 與 `spec/unit/account_spec.rb` 驗證密碼 digest 與比對。
   - 已完成：在 `accounts` schema（001 migration）加入 `password_digest` 欄位。
   - 已完成：在 `Account` 提供 `password=` 與 `password?`（不提供 getter）。

4. ✅ `pii-confidential-searchable`（已完成）
    - 已完成：選定帳號 PII 為 email 與 phone（username 為明文）。
    - 已完成：migration 001 新增 `email_secure`、`email_hash`、`phone_number_secure`、`phone_number_hash` 欄位與唯一性約束。
    - 已完成：Account model 提供 `email=` 和 `phone_number=` setters 同時寫入 secure/hash；getters 僅解密 secure。
    - 已完成：SecureDB 新增 `hash()` 方法（HMAC-SHA256）用於可搜尋 PII；新增 `rake newkey:hash` task。
    - 已完成：SensitiveData migration 更新欄位必填性；model 更新 first_name/last_name（替代 user_name）。
    - 已完成：所有相關測試通過（41 runs, 141 assertions, 0 failures）。
    - 待做：search service + routes（透過 hash 查找）。


5. ✅ `many-to-many-associations`（已完成）
   - 已完成：建立 `accounts_roles`（`accounts` ↔ `roles`）M:N join table。
   - 已完成：`Account` 與 `Role` 建立雙向關聯（`many_to_many`）。
   - 已完成：補強 migration 型別（`accounts_roles.account_id` 使用 UUID 對齊 `accounts.id`）。

6. ✅ `roles-system`（本階段完成）
   - 已完成：定義 system roles（`admin`、`member`）與 resource roles（`owner`、`viewer_masked`、`viewer_full`）命名與分類。
   - 已完成：採 role join table 儲存（非 enum 欄位）。
   - 已完成：`Account` 加入 `admin?`、`member?`、`system_role?` helper。
   - 已完成：`Attachment` 加入 `owner`、`viewers_masked`、`viewers_full` helper（目前以全域 roles 對應）。
   - 備註：待 authentication 授權章節後，再把角色檢查正式掛進 service/route 的存取控制流程。

7. `service-object-refactor`
   - 新增/重構 account create/get/update/search 與關聯操作服務。
   - 控制器改呼叫 service object，減少 controller 內部資料庫細節。
   - 測試與 seed 也重用相同服務，避免邏輯分岔。

   - Status update（2026-04-27）：現有 API service refactor 已完成；update/search deferred。
   - 已完成：新增 `CreateAccountService`、`FindAccountService`，讓 account create/get 流程走 service。
   - 已完成：新增 `CreateAttachmentService`，並沿用 `FindAttachmentService`，讓 attachment create/find 流程走 service。
   - 已完成：新增 `CreateSensitiveDataService`，並沿用 `FindSensitiveDataService`，讓 sensitive_data create/find 流程走 service。
   - 已完成：`app/controllers/app.rb` 不再直接處理現有 create/find workflow 的 model 建立與查找，改由 service object 負責。
   - 已完成：新增 `spec/unit/services_spec.rb`，覆蓋 service happy/sad paths 與 scoped lookup 行為。
   - 已完成：integration specs 的 setup 改用 service objects，避免測試資料建立流程和 app workflow 分岔。
   - 已完成：新增 `db/seeds/create_all.rb` 與 `db/seeds/role_seeds.yml`，seed runner 會重用 service objects 建立 roles、accounts、attachments、sensitive_data。
   - 已完成：`Rakefile` 新增 `rake db:seed`，並讓 `db:load_models` 載入 services。
   - 已驗證：`rake db:seed` 通過。
   - 已驗證：`rake style` 通過。
   - Deferred：`UpdateAccountService` / `SearchAccountsService` 尚未建立，因為目前 `app.rb` 沒有 account update/search routes；等 route 與 API contract 設計後再補。

8. `db-seed-optional`（已完成）
   - 已完成：使用 Sequel seed extension（`sequel/extensions/seed`）執行 seed files。
   - 已完成：建立 `db/seeds/create_all.rb`，並以 `Sequel.seed(:development)` + `run` 包裝 seed runner。
   - 已完成：新增 `db/seeds/role_seeds.yml`，讓每個 model 都有對應 seed data：roles、accounts、attachments、sensitive_data。
   - 已完成：`create_all.rb` 讀取各 model YAML seed data，並透過 service objects 建立 account -> attachment -> sensitive_data。
   - 已完成：新增 `rake db:seed`，符合 `bundle install && rake db:migrate && rake db:seed`。
   - 已驗證：`rake db:seed` 通過。
   - 已驗證：`rake style` 通過。

9. `account-routes-and-tests`（本階段完成）
   - 已完成：整合 account create/get routes：`POST /api/v1/accounts`、`GET /api/v1/accounts/:account_id`。
   - 已完成：整合 account -> attachments nested routes：create/list/get attachment。
   - 已完成：整合 attachment -> sensitive_data nested routes：create/get sensitive_data。
   - 已完成：README API examples 已對齊目前 account payload（`username`、`email`、`phone_number`、`password`）與 sensitive_data payload（`first_name` / `last_name`）。
   - 已完成：integration specs 覆蓋 happy/sad/security cases，包含 mass assignment、missing resource、scoped lookup 與 sensitive data path injection。
   - 已完成：補強 account response 不回傳 `password` / `password_digest`。
   - 已完成：補強 attachment scoped route，避免透過其他 account path 讀到不屬於該 account 的 attachment。
   - Deferred：account list/update/search routes 尚未開啟；目前 list route 因未有 auth 而保留停用。

## 依賴順序
- `baseline-docs-and-version` -> `account-domain-renaming`
- `account-domain-renaming` -> `password-security-core`
- `password-security-core` -> `pii-confidential-searchable`
- `account-domain-renaming` -> `many-to-many-associations`
- `many-to-many-associations` -> `roles-system`
- `password-security-core` + `pii-confidential-searchable` + `roles-system` -> `service-object-refactor`
- `service-object-refactor` -> `account-routes-and-tests`
- `service-object-refactor` -> `db-seed-optional`

## 待組內決策（先標記 blocked，不阻擋前置作業）
- PII 最終範圍（已暫定可先做：email/phone；會後再決定是否擴充 name/address 的 hash 搜尋）。
- 角色模型採單欄位還是 role join table（是否需要 entity-level role）。
- 哪一組 many-to-many 關聯最符合你們領域模型（例如 accounts<->projects / accounts<->courses）。
- `db:seed` 是否列為本週必做還是加分項（optional）。
