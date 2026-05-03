# 本週 Authentication 與 Web App 實作計畫

## 問題與目標

- 本週目標是讓使用者可以登入，並建立後續 role-based workflow 的基礎。
- 範圍分成兩條線：更新既有 `LockedCV-API`，以及建立新的 Web App client interface。
- API 需要新增 credentials authentication route，回傳最少包含 account id、username、email、roles 的 JSON；失敗時回傳 `403` 與 JSON error body。
- API production 環境需要拒絕非 SSL/HTTPS request。
- Web App 需要提供 home/login/account/logout 的使用者流程，以 service object 呼叫 API，並用 cookie-based session 保存非敏感登入資訊。

## 現況分析（2026-05-02）

- 專案：`LockedCV-API`
- API framework：Ruby + Roda + Sequel + SQLite。
- 已完成 account domain：`LockedCV::Account`、`accounts` table、`password_digest`、`Account#password?`。
- 已完成帳號 PII 保護：email/phone 以 encrypted `*_secure` 與 searchable `*_hash` 儲存，response 不回傳 password/password_digest。
- 已完成基礎 roles：`Role::SYSTEM_ROLES = admin/member`、`Role::RESOURCE_ROLES = owner/viewer_masked/viewer_full`，並透過 `accounts_roles` join table 關聯 account roles。
- Controller 已依教授 `4-authenticate` 分支方向拆分：`app/controllers/app.rb` 使用 Roda `multi_route` dispatch，`accounts.rb` 放 account-scoped routes，`http_request.rb` 放 request body 與 SSL helper。
- 目前 API 已有 nested account/attachment/sensitive_data routes，並新增 `POST /api/v1/auth/authenticate` route；尚未把 role checks 正式掛到 service/route。
- 目前 repo 只有 API；Web App 應另開 repo 或另開 app 專案後再接 API。

## 實作策略（分階段）

1. **API authentication contract**：先定義 request/response payload，新增 authenticate service 與 route。
2. **Route structure cleanup**：視 controller 複雜度導入 Roda `multi_route`，先拆 authentication/account routes，再逐步搬 attachments/sensitive_data。
3. **SSL enforcement**：在 production 環境檢查 request scheme，阻擋 HTTP request。
4. **Role-aware API guard**：把目前 roles 從 model helper 推進到 service/route 的授權檢查。
5. **Web App repo handoff**：到此需要建立新 Web App repo，接著實作 Roda App、views、sessions、flash、API service client。
6. **End-to-end login workflow**：用 App login form 呼叫 API authenticate route，成功後建立 session，失敗後顯示 flash error。
7. **Role-based UI**：App 依 session account roles 顯示/隱藏 navigation、buttons、links；API 仍是最終授權來源。

## Todo 清單

1. ✅ `api-authentication-service`（已完成）
   - 新增 `AuthenticateAccountService`。
   - Input：`username`、`password`。
   - 驗證方式：查到 account 後呼叫 `account.password?(password)`。
   - 成功回傳 account，由 route 包成安全登入 account response，至少包含 `id`、`username`、`email`、`roles`。
   - 失敗統一回傳 authentication failure，不暴露帳號是否存在。
   - 已補 unit specs：happy path、wrong password、unknown account。

2. ✅ `api-authentication-route`（已完成）
   - 新增 `POST /api/v1/auth/authenticate`。
   - 成功：`200`，JSON body 包含 account id、username、email、roles。
   - 失敗：`403`，JSON body 例如 `{ "message": "Invalid credentials" }`。
   - 已補 integration specs 覆蓋 status code、JSON body、password 不外洩。

3. ✅ `api-route-structure`（已完成）
   - 已導入 Roda `multi_route`。
   - 已拆分：
     - `app/controllers/app.rb`：root、plugin setup、top-level route dispatch。
     - `app/controllers/accounts.rb`：account routes，暫含 attachment/sensitive_data nested routes。
     - `app/controllers/auth.rb`：authentication routes。
     - `app/controllers/http_request.rb`：request body parsing 與 SSL scheme helper。
   - 已跑 specs，確認路徑相容。

4. ✅ `api-require-ssl`（已完成）
   - 已在 request 入口檢查 `HttpRequest#secure?`。
   - 已透過 `SECURE_SCHEME` config 控制允許的 request scheme。
   - development/test 設為 `HTTP`，production 設為 `HTTPS`。
   - 非符合 config 的 scheme 回傳 `403` JSON：`{ "message": "TLS/SSL Required" }`。
   - 已補 integration spec 覆蓋不符合 configured secure scheme 時會被拒絕。

5. ✅ `api-role-authorization-demo`（本週 demo 已完成；完整 resource authorization deferred）
   - 已新增 `AssignSystemRoleService`，作為跟教授 `assign_system_role.rb` 類似的最小 authorization demo。
   - 已新增 `PUT /api/v1/accounts/:username/system_roles/:role_name`。
   - 目前只有 `admin` system role 可以指派 system roles。
   - 已補 unit/integration specs：admin assign、idempotent reassign、non-admin denied、unknown role、unknown account、missing current account。
   - Deferred：完整 policy object 與 resource-level authorization 等教授 authorization/policy 章節後再設計。
   - Deferred：`owner`、`viewer_masked`、`viewer_full` 如何管 attachment/sensitive_data 存取權，需要先對齊 domain sharing model。

6. `web-app-repo-handoff`（需要新 repo）
   - 到這個節點請開新的 Web App repo。
   - 建議 repo 名稱：`LockedCV-App` 或 `LockedCV-Web`.
   - App 需要自己的 README、Gemfile、Roda controller、services、Slim views、session/flash setup。
   - API repo 只保留 API contract、auth route、authorization 與 API tests。

7. `web-app-foundation`（新 repo）
   - 建立 Roda Web App。
   - 建立 layout Slim template，含 navigation：
     - 未登入：home / login / register。
     - 已登入：home / account / logout。
   - 建立 home page、login page、account overview page。
   - 設定 cookie-based sessions，只存非敏感 account info：id、username、email、roles。

8. `web-app-api-service-client`（新 repo）
   - 建立 service object 呼叫 API `POST /api/v1/auth/authenticate`。
   - 成功時將 account DTO 寫入 session。
   - 失敗時保留適當 status code 並顯示 flash error。
   - API base URL 由 config/environment 管理，不寫死在 view/controller。

9. `web-app-login-logout`
   - Login form POST 到 App controller。
   - Login 成功 redirect account overview，並顯示 notice。
   - Login 失敗回 login page，status code 應對齊表單錯誤。
   - Logout 清除 session account data，redirect home/login，並顯示 notice。
   - 未登入使用者進入 account overview 時 redirect login 並顯示 unauthorized flash。

10. `web-app-flash`
    - 設定 Roda flash plugin。
    - 在 layout 或 partial render flash message bar。
    - 定義 `:error` 與 `:notice` styles。
    - 覆蓋 form errors、login failed、logout success、unauthorized access 等轉場。

11. `web-app-role-based-ui`
    - App 依 session roles 顯示/隱藏按鈕或 links。
    - 不把 UI hide/show 當作安全邊界；API authorization 仍必須檢查。
    - 優先挑一段主流程做完整 role-based functionality，例如：
      - owner 上傳/查看 attachment。
      - viewer_masked 只能查看遮罩後資料。
      - viewer_full 可查看完整敏感資料。
      - admin 可進入管理入口。

## 依賴順序

- `api-authentication-service` -> `api-authentication-route`（已完成）
- `api-authentication-route` -> `web-app-api-service-client`
- `api-route-structure` 可在 auth route 前後進行；若本週時間緊，先完成 auth route，再拆 route。
- `api-require-ssl` 已完成。
- `api-role-authorization-demo` 已完成，可支援 Web App 先做 role-aware UI demo。
- 完整 `api-role-authorization` / policy object / resource-level permission -> deferred，等 authorization 章節與 domain sharing model 明確後再做。
- `web-app-repo-handoff` -> 所有 `web-app-*` tasks

## API Contract 草案

### POST `/api/v1/auth/authenticate`

Request:

```json
{
  "username": "jane_smith",
  "password": "my-secret-password"
}
```

Success `200`:

```json
{
  "data": {
    "type": "authenticated_account",
    "attributes": {
      "id": "account-uuid",
      "username": "jane_smith",
      "email": "jane@example.com",
      "roles": ["member"]
    }
  }
}
```

Failure `403`:

```json
{
  "message": "Invalid credentials"
}
```

## 待組內決策

- Login identifier 目前先用 `username`；是否支援 `email` 可後續決定。
- Authentication response 是否需要包含 role type（system/resource）或先只回 role names。
- Web App repo 名稱與部署方式。
- Production SSL error status 要用 `403` 還是課程 demo 指定的狀態碼。
- Resource-level roles 目前是全域 role join table；是否需要補 entity-level authorization table，例如 account 對 attachment 的 permission mapping。
- Register page 是否本週只放 navigation/link，或同步實作註冊流程。

## 本週完成定義

- API 可用 `POST /api/v1/auth/authenticate` 驗證帳密。
- API authentication 成功不外洩 password/password_digest。
- API authentication 失敗回 `403` JSON。
- Production HTTP request 被 SSL guard 阻擋。
- Web App 可登入、登出、保存非敏感 session account data。
- Web App 有 flash notices/errors。
- 至少一段 role-based API guard 與 App UI hide/show 已完成並有測試或可展示流程。
