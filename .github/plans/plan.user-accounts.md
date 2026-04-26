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
- 尚未看到 `db:seed`（sequel-seed）任務與 seed runner。

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
   - 備註：`sensitive_data.user_name` 保留，因其語意是履歷上的姓名欄位，非帳號關聯名稱。

3. ✅ `password-security-core`（已完成）
   - 已完成：新增 `KeyStretch` module（RbNaCl + Base64）與 `Password` value object。
   - 已完成：新增 `spec/unit/password_spec.rb` 與 `spec/unit/account_spec.rb` 驗證密碼 digest 與比對。
   - 已完成：在 `accounts` schema（001 migration）加入 `password_digest` 欄位。
   - 已完成：在 `Account` 提供 `password=` 與 `password?`（不提供 getter）。

4. `pii-confidential-searchable`
   - 選定要支援的帳號 PII（暫定：先做 email、phone；name 先維持 secure-only）。
   - migration 新增 `*_secure` 與 `*_hash` 欄位、必要索引與唯一性策略。
   - model setter 寫入 secure/hash；getter 僅解密 secure。
   - 實作 search service + routes（透過 hash 查找，不以明文搜尋）。

5. `many-to-many-associations`
   - 建立需要的 join tables（至少一組 account 與其他實體的 M:N）。
   - 在雙向模型定義 appropriately named associations。
   - 使用 `association_dependencies` 確保刪除/清理行為一致。

6. `roles-system`
   - 定義 system roles（至少 `admin`、`member`）與必要的 entity roles（若有）。
   - 決定 role 儲存方式（enum-like 欄位 vs role join table；待決策）。
   - 在服務層與路由套用角色檢查（先最小可用版本）。

7. `service-object-refactor`
   - 新增/重構 account create/get/update/search 與關聯操作服務。
   - 控制器改呼叫 service object，減少 controller 內部資料庫細節。
   - 測試與 seed 也重用相同服務，避免邏輯分岔。

8. `db-seed-optional`
   - （可選）導入 `sequel-seed`。
   - 建立 `db/seeds/<date>_<description>.rb` with `Sequel.seed(:development)` + `run`。
   - 新增 `rake db:seed`，符合 `bundle install && rake db:migrate && rake db:seed`。

9. `account-routes-and-tests`
   - 整合 account 到既有 API（create account、get account、可選 account->courses/attachments 關聯查詢）。
   - 補齊 integration/unit specs，確保路由、安全與服務層行為一致。

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
