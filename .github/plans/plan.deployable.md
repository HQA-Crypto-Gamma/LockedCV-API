# LockedCV-API Deployable API 作業實作計畫

## 問題與目標

- 本週 API 目標是讓 `LockedCV-API` 可以支援 App registration/admin workflow，並部署到 Heroku production 環境。
- API 需要提供基本且風險較高的 account registration backend：App 會送 email、username、password 到 API 建立帳號。
- API 需要新增 Rake task，例如 `db:bootstrap_admin`，把指定使用者提升為 `admin` system role，方便 production 初始管理者設定。
- API 部署到 Heroku 後要改用 Postgres database。
- Deployed API 需要讓 deployed App 可以建立/更新資源。
- Production 環境仍需要維持 HTTPS/TLS 檢查與敏感資料不外洩。

## 現況分析（2026-05-10）

- 專案：`LockedCV-API`
- 目前已完成 account domain、password digest、email/phone encrypted + searchable hash、roles、authentication route。
- 目前已有基本 account creation route：
  - `POST /api/v1/accounts`
- 目前已有 admin-only account listing 與 system role assignment demo：
  - `GET /api/v1/accounts?current_account_id=...`
  - `PUT /api/v1/accounts/:username/system_roles/:role_name`
- 目前 production secure scheme 已有基礎設定，會依 `SECURE_SCHEME` 檢查 request scheme。
- 待強化項目：
  - 已新增 `db:bootstrap_admin` Rake task，可建立或找到指定帳號並授予 `admin`。
  - 已建立 Heroku API app，並使用 Heroku Postgres 作為 production database。
  - 已設定 production config vars 並在 Heroku production database 執行 migrations。
  - 尚未在 Heroku production 執行 `db:bootstrap_admin`。
  - Deployed App 到 deployed API 的 URL/HTTPS 行為仍需要 smoke test。

## 實作策略（分階段）

1. **Registration backend review**：確認 `POST /api/v1/accounts` 的 payload、response、錯誤處理能支援 App registration。
2. **Bootstrap admin task**：新增 `db:bootstrap_admin` Rake task，用 username 找到或建立 account 並授予 `admin` system role。
3. **Postgres compatibility**：確認 Sequel migrations、UUID、timestamps、constraints 在 Postgres 可執行。
4. **Heroku API deployment**：建立 API dyno，設定 production config vars，使用 Heroku Postgres。
5. **Production migration/bootstrap**：在 Heroku 執行 migration，建立必要 roles，提升第一個 admin。
6. **Production API smoke checks**：確認 account creation、authentication、account listing、system role update 都能在 deployed API 運作。
7. **App integration support**：提供 deployed API URL 給 App，確認 App 對 API 的 production request 都走 HTTPS。

## Todo 清單

1. ✅ `registration-api-support`（已存在，需本週複查）
   - 已完成：`POST /api/v1/accounts` 可建立 account。
   - 已完成：建立 account 時會處理 password digest，response 不回傳 password/password_digest。
   - 已完成：new account 預設會加入 `member` role。
   - 待複查：payload 是否與 App registration form 完全對齊：`email`、`username`、`password`。
   - 待複查：錯誤 response 是否足夠讓 App 顯示 registration failure。
   - 待複查：README 需要明確標示本階段尚未驗證 account details。

2. `bootstrap-admin-rake-task`
   - ✅ 新增 `db:bootstrap_admin` Rake task。
   - ✅ Task 可透過 `USERNAME` 指定 target account。
   - ✅ Task 會確保 system roles `admin`、`member` 存在。
   - ✅ Task 可在 account 不存在時用 `USERNAME`、`EMAIL`、互動式密碼建立 account。
   - ✅ Task 會把 target account 加入 `admin` system role。
   - ✅ Task 可重複執行，不會重複建立 role association。
   - ⬜ 補 task 或 service tests，確認缺少 `USERNAME`、新帳號缺少 `EMAIL`、密碼過短會明確失敗。

3. `postgres-production-database`
   - ✅ 確認 Gemfile 有 production Postgres adapter。
   - ✅ 確認 `DATABASE_URL` 可由 Heroku Postgres 提供。
   - ✅ 確認 config 可讀取 production `DATABASE_URL`。
   - ✅ 已在 Heroku Postgres 跑 migrations。
   - ✅ UUID、foreign keys、unique constraints、join table 已通過 migration。
   - ✅ 確認 local SQLite development/test 不受影響。

4. `api-heroku-deployment`
   - ✅ 建立 Heroku API dyno。
   - ✅ Provision Heroku Postgres。
   - ✅ 設定 `RACK_ENV=production`。
   - ✅ 設定 `SECURE_SCHEME=HTTPS`。
   - ✅ 設定 database encryption key 與 lookup hash key。
   - ✅ 設定 production host/base URL 相關 config。
   - ⬜ 確認 production logs 不輸出 plaintext password、encrypted columns、lookup hashes、secret keys。

5. `production-migration-and-bootstrap`
   - ✅ 在 Heroku 執行 database migration。
   - ✅ `db:bootstrap_admin` 會建立必要 system roles：`admin`、`member`。
   - ✅ `db:bootstrap_admin` 可建立第一個 production account。
   - ✅ `db:bootstrap_admin` 可將第一個 account 提升為 admin。
   - ⬜ 在 Heroku production 執行 `db:bootstrap_admin`。
   - ⬜ 在 Heroku production 驗證 bootstrap task 可重跑且不破壞既有資料。

6. `deployed-api-smoke-checks`
   - ⬜ 測試 `POST /api/v1/accounts` 可在 deployed API 建立 account。
   - ⬜ 測試 `POST /api/v1/auth/authenticate` 可登入新 account。
   - ⬜ 測試 admin 可呼叫 `GET /api/v1/accounts?current_account_id=...`。
   - ⬜ 測試 admin 可呼叫 `PUT /api/v1/accounts/:username/system_roles/:role_name`。
   - ⬜ 測試 HTTP request 在 production 會被拒絕或導向 HTTPS。
   - ⬜ 測試 API response 不包含 password/password_digest/encrypted columns/hash columns。

7. `app-production-integration`
   - ⬜ 提供 deployed API base URL 給 App。
   - ⬜ 確認 App production `API_URL` 指向 deployed API。
   - ⬜ 確認 deployed App registration 會寫入 API production Postgres。
   - ⬜ 確認 deployed App admin settings 可讀取/更新 API production resources。

## 依賴順序

- `registration-api-support` 複查 -> `app-production-integration`
- `bootstrap-admin-rake-task` -> `production-migration-and-bootstrap`
- `postgres-production-database` -> `api-heroku-deployment`
- `api-heroku-deployment` -> `production-migration-and-bootstrap`
- `production-migration-and-bootstrap` -> `deployed-api-smoke-checks`
- `deployed-api-smoke-checks` -> App repo 的 deployed App smoke checks

## 待組內決策

- ✅ `db:bootstrap_admin` 使用 `USERNAME` 指定 target account；建立新帳號時另外要求 `EMAIL` 與密碼。
- Production 是否允許 `db:seed` 建立 demo data，或只建立 roles + 手動 registration。
- ✅ 已 provision Heroku Postgres 作為 production database。
- Production API 是否需要 CORS；若 App 與 API 都是 server-side HTTP calls，可能不需要 browser CORS。
- Deployment smoke check 是否用 HTTPie/manual commands，或補成可重跑的 rake smoke task。

## 本週完成定義

- API 可以支援 App registration 建立 production account。
- API 有可重複執行的 `db:bootstrap_admin` task，能把指定 account 提升為 admin。
- Heroku API dyno 使用 Postgres database，migrations 可成功執行。
- Production roles 與第一個 admin 可被 bootstrap。
- Deployed API 可讓 deployed App 建立/更新 resources。
- Production API 維持 HTTPS/TLS 要求，且 response 不外洩 password、encrypted columns、lookup hashes 或 secret keys。
